import Foundation
import RelayMarkSwift

/// Structural Return over the existing YSwift XML. The editor/host supplies an
/// exact snapshot and selection; Yrs owns merging, transactions and undo.
@MainActor
public enum RelayMarkNativeMarkdownV3Return {
    private typealias XML = RelayMarkNativeMarkdownV3XML
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
        guard XML.isCharacterBoundary(utf16Offset, in: source) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let block = try XML.node(at: blockPath, in: tree), name = block["name"] as? String ?? ""
        guard ["paragraph", "heading", "calloutTitle"].contains(name) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let parentPath = Array(blockPath.dropLast()), parent = try XML.node(at: parentPath, in: tree)
        let parentName = parent["name"] as? String ?? "fragment", body = try XML.children(parent)
        let inList = ["listItem", "taskItem"].contains(parentName)
        let listPath = Array(parentPath.dropLast())
        let itemIndex = parentPath.last ?? 0
        let list = inList ? try XML.node(at: listPath, in: tree) : [:]
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

        let newID = XML.freshID()
        let newItemID = XML.freshID()
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

        let split = try XML.splitInline(try XML.children(block), at: utf16Offset, path: blockPath)
        let nextName = name == "heading" && !splitItem && utf16Offset < source.utf16.count ? "heading" : "paragraph"
        var attrs: [String: Any] = ["relaymarkId": newID]
        if nextName == "heading" {
            attrs["level"] = (block["attributes"] as? [String: Any])?["level"] ?? 1
            attrs["headingId"] = "h-" + newID
        }
        let next = element(nextName, attrs: attrs, children: split.suffix)
        var edits = [RelayMarkNativeDocument.SnapshotNodeReplacement(parentPath: blockPath,
            start: split.removeFrom, count: try XML.children(block).count - split.removeFrom, nodes: [])]
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

    private static func perform(document: RelayMarkNativeDocument, tree: [String: Any],
                                edits: [RelayMarkNativeDocument.SnapshotNodeReplacement], trim: XML.Trim?,
                                kind: Kind, blockID: String) throws -> Result {
        Result(update: try XML.apply(document: document, tree: tree, edits: edits,
                                     trims: trim.map { [$0] } ?? []), kind: kind, blockID: blockID)
    }
}
