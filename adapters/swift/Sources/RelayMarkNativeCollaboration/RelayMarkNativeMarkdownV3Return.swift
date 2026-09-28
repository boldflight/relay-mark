import Foundation
import RelayMarkSwift

/// Structural Return over the existing YSwift XML. The editor/host supplies an
/// exact snapshot and selection; Yrs owns merging, transactions and undo.
@MainActor
public enum RelayMarkNativeMarkdownV3Return {
    public enum Kind: Sendable { case split, exit }
    public struct Result: Sendable {
        public let update: Data
        public let kind: Kind
        public let blockID: String
    }

    public static func apply(document: RelayMarkNativeDocument, blockPath: [Int],
                             utf16Offset: Int, expectedSnapshot: Data) throws -> Result {
        guard document.integrationStatus().isComplete, try document.snapshot() == expectedSnapshot,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let projection = try document.markdownV3ProseProjection()
        guard projection.isEditable, let row = projection.blockPaths.firstIndex(of: blockPath),
              let parentIndex = blockPath.last else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
        let range = projection.blockRanges[row]
        let source = (String(projection.text.characters) as NSString).substring(with: range)
        guard isCharacterBoundary(utf16Offset, in: source) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let block = try node(at: blockPath, in: tree), name = block["name"] as? String ?? ""
        guard ["paragraph", "heading", "calloutTitle"].contains(name) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let parentPath = Array(blockPath.dropLast()), parent = try node(at: parentPath, in: tree)
        let parentName = parent["name"] as? String ?? "fragment", body = try children(parent)
        let inList = ["listItem", "taskItem"].contains(parentName)
        let listPath = Array(parentPath.dropLast())
        let itemIndex = parentPath.last ?? 0
        let list = inList ? try node(at: listPath, in: tree) : [:]
        let listName = list["name"] as? String ?? ""
        let oldID = (block["attributes"] as? [String: Any])?["relaymarkId"] as? String ?? ""
        if inList {
            guard ["bulletList", "orderedList", "taskList"].contains(listName),
                  parentName == (listName == "taskList" ? "taskItem" : "listItem") else {
                throw RelayMarkNativeDocument.Failure.invalidTextPath
            }
            if source.isEmpty && parentIndex == body.count - 1 {
                // Existing list lifting preserves linked-task policy. An empty
                // secondary body block needs a separate container-lift command.
                guard parentIndex == 0 else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                let update = try document.changeMarkdownV3ListDepth(paragraphPath: blockPath,
                    change: .outdent, expectedSnapshot: expectedSnapshot)
                return Result(update: update, kind: .exit, blockID: oldID)
            }
        }
        if source.isEmpty && parentName == "blockquote" && parentIndex == body.count - 1 {
            let quotePath = parentPath, outerPath = Array(quotePath.dropLast())
            guard let quoteIndex = quotePath.last else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
            let edits: [RelayMarkNativeDocument.SnapshotNodeReplacement]
            if body.count == 1 {
                edits = [.init(parentPath: outerPath, start: quoteIndex, count: 1, nodes: [block])]
            } else {
                edits = [.init(parentPath: quotePath, start: parentIndex, count: 1, nodes: []),
                         .init(parentPath: outerPath, start: quoteIndex + 1, count: 0, nodes: [block])]
            }
            return try perform(document: document, tree: tree, edits: edits,
                trim: nil, kind: .exit, blockID: oldID)
        }

        let newID = freshID()
        let newItemID = freshID()
        // The community list command uses its default first paragraph at the
        // end of a textblock. Interior heading Return instead splits its body.
        let splitItem = inList && (name == "paragraph" || utf16Offset == source.utf16.count)
        func element(_ name: String, attrs: [String: Any], children: [[String: Any]]) -> [String: Any] {
            ["kind": "element", "name": name, "attributes": attrs, "children": children]
        }
        func item(_ children: [[String: Any]]) -> [String: Any] {
            var attrs: [String: Any] = ["relaymarkId": newItemID]
            if parentName == "taskItem" { attrs["checked"] = false }
            return element(parentName, attrs: attrs, children: children)
        }
        if utf16Offset == 0 && !source.isEmpty &&
            ((splitItem && parentIndex == 0) || (name == "heading" && !splitItem)) {
            // Keep the existing nonempty node intact at the start boundary.
            let empty = element("paragraph", attrs: ["relaymarkId": newID], children: [])
            let edit = splitItem
                ? RelayMarkNativeDocument.SnapshotNodeReplacement(parentPath: listPath, start: itemIndex, count: 0, nodes: [item([empty])])
                : RelayMarkNativeDocument.SnapshotNodeReplacement(parentPath: parentPath, start: parentIndex, count: 0, nodes: [empty])
            return try perform(document: document, tree: tree, edits: [edit], trim: nil, kind: .split, blockID: newID)
        }

        let split = try splitInline(try children(block), at: utf16Offset, path: blockPath)
        let nextName = name == "heading" && !splitItem && utf16Offset < source.utf16.count ? "heading" : "paragraph"
        var attrs: [String: Any] = ["relaymarkId": newID]
        if nextName == "heading" {
            attrs["level"] = (block["attributes"] as? [String: Any])?["level"] ?? 1
            attrs["headingId"] = "h-" + newID
        }
        let next = element(nextName, attrs: attrs, children: split.suffix)
        var edits = [RelayMarkNativeDocument.SnapshotNodeReplacement(parentPath: blockPath,
            start: split.removeFrom, count: try children(block).count - split.removeFrom, nodes: [])]
        if splitItem {
            let tail = Array(body.dropFirst(parentIndex + 1))
            if !tail.isEmpty {
                edits.append(.init(parentPath: parentPath, start: parentIndex + 1, count: tail.count, nodes: []))
            }
            edits.append(.init(parentPath: listPath, start: itemIndex + 1, count: 0, nodes: [item([next] + tail)]))
        } else {
            edits.append(.init(parentPath: parentPath, start: parentIndex + 1, count: 0, nodes: [next]))
        }
        return try perform(document: document, tree: tree, edits: edits, trim: split.trim, kind: .split, blockID: newID)
    }

    private struct Trim {
        let removal: RelayMarkNativeDocument.SnapshotTextRemoval
        let prefixRuns: [[String: Any]]
    }
    private struct InlineSplit {
        let suffix: [[String: Any]]
        let removeFrom: Int
        let trim: Trim?
    }

    private static func splitInline(_ children: [[String: Any]], at offset: Int, path: [Int]) throws -> InlineSplit {
        var position = 0
        for (index, child) in children.enumerated() {
            let text = child["kind"] as? String == "text"
            let runs = child["delta"] as? [[String: Any]] ?? []
            let width = text ? try runs.map { run -> String in
                guard let value = run["insert"] as? String else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                return value
            }.joined().utf16.count : 1
            if position + width <= offset { position += width; continue }
            if position >= offset {
                return InlineSplit(suffix: Array(children.dropFirst(index)), removeFrom: index, trim: nil)
            }
            guard text else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            let local = offset - position
            let (left, right) = try splitRuns(runs, at: local)
            let suffix: [String: Any] = ["kind": "text", "delta": right]
            return InlineSplit(suffix: [suffix] + children.dropFirst(index + 1), removeFrom: index + 1,
                trim: Trim(removal: .init(path: path + [index], start: local, count: width - local), prefixRuns: left))
        }
        guard position == offset else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return InlineSplit(suffix: [], removeFrom: children.count, trim: nil)
    }

    private static func splitRuns(_ runs: [[String: Any]], at offset: Int) throws -> ([[String: Any]], [[String: Any]]) {
        var left: [[String: Any]] = [], right: [[String: Any]] = [], position = 0
        for run in runs {
            guard let text = run["insert"] as? String else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            let local = min(max(offset - position, 0), text.utf16.count)
            guard let prefixRange = Range(NSRange(location: 0, length: local), in: text),
                  let suffixRange = Range(NSRange(location: local, length: text.utf16.count - local), in: text) else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            if local > 0 { var value = run; value["insert"] = String(text[prefixRange]); left.append(value) }
            if local < text.utf16.count { var value = run; value["insert"] = String(text[suffixRange]); right.append(value) }
            position += text.utf16.count
        }
        return (left, right)
    }

    private static func perform(document: RelayMarkNativeDocument, tree: [String: Any],
                                edits: [RelayMarkNativeDocument.SnapshotNodeReplacement], trim: Trim?,
                                kind: Kind, blockID: String) throws -> Result {
        var prospective = tree
        if let trim {
            try mutate(path: trim.removal.path[...], in: &prospective) { $0["delta"] = trim.prefixRuns }
        }
        for edit in edits {
            try mutate(path: edit.parentPath[...], in: &prospective) { parent in
                var content = try children(parent)
                guard edit.start >= 0, edit.count >= 0, edit.start + edit.count <= content.count else {
                    throw RelayMarkNativeDocument.Failure.invalidTextPath
                }
                content.replaceSubrange(edit.start..<(edit.start + edit.count), with: edit.nodes)
                parent["children"] = content
            }
        }
        let expected = try RelayMarkNativeMarkdownBlocksV3Projection.project(
            snapshot: JSONSerialization.data(withJSONObject: prospective, options: [.sortedKeys]))
        let removals = trim.map { [$0.removal] } ?? []
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        _ = try scratch.replaceSnapshotNodes(edits, textRemovals: removals)
        guard try RelayMarkNativeMarkdownBlocksV3Projection.project(document: scratch) == expected,
              try scratch.markdownV3ProseProjection().isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return Result(update: try document.replaceSnapshotNodes(edits, textRemovals: removals), kind: kind, blockID: blockID)
    }

    private static func node(at path: [Int], in tree: [String: Any]) throws -> [String: Any] {
        var result = tree
        for index in path {
            let content = try children(result)
            guard content.indices.contains(index) else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
            result = content[index]
        }
        return result
    }
    private static func children(_ node: [String: Any]) throws -> [[String: Any]] {
        guard let content = node["children"] as? [[String: Any]] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return content
    }
    private static func mutate(path: ArraySlice<Int>, in node: inout [String: Any],
                               change: (inout [String: Any]) throws -> Void) throws {
        guard let index = path.first else { try change(&node); return }
        var content = try children(node)
        guard content.indices.contains(index) else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
        try mutate(path: path.dropFirst(), in: &content[index], change: change)
        node["children"] = content
    }
    private static func freshID() -> String { "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "") }
    private static func isCharacterBoundary(_ offset: Int, in value: String) -> Bool {
        guard offset >= 0 else { return false }
        var count = 0
        for character in value { if count == offset { return true }; count += String(character).utf16.count }
        return count == offset
    }
}
