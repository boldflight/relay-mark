import Foundation

/// Shared XML operations over community Yrs. Hosts own selection and authorization.
@MainActor
enum RelayMarkNativeRichXML {
    struct Trim {
        let removal: RelayMarkNativeDocument.SnapshotTextRemoval
        let prefixRuns: [[String: Any]]
    }
    struct InlineSplit {
        let suffix: [[String: Any]]
        let removeFrom: Int
        let trim: Trim?
    }

    static func splitInline(_ children: [[String: Any]], at offset: Int, path: [Int]) throws -> InlineSplit {
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

    static func splitRuns(_ runs: [[String: Any]], at offset: Int) throws -> ([[String: Any]], [[String: Any]]) {
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

    static func node(at path: [Int], in tree: [String: Any]) throws -> [String: Any] {
        var result = tree
        for index in path {
            let content = try children(result)
            guard content.indices.contains(index) else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
            result = content[index]
        }
        return result
    }
    static func children(_ node: [String: Any]) throws -> [[String: Any]] {
        guard let content = node["children"] as? [[String: Any]] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return content
    }
    static func mutate(path: ArraySlice<Int>, in node: inout [String: Any],
                               change: (inout [String: Any]) throws -> Void) throws {
        guard let index = path.first else { try change(&node); return }
        var content = try children(node)
        guard content.indices.contains(index) else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
        try mutate(path: path.dropFirst(), in: &content[index], change: change)
        node["children"] = content
    }
    static func freshID() -> String { "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "") }
    static func isCharacterBoundary(_ offset: Int, in value: String) -> Bool {
        guard offset >= 0 else { return false }
        var count = 0
        for character in value { if count == offset { return true }; count += String(character).utf16.count }
        return count == offset
    }

    static func apply(document: RelayMarkNativeDocument, tree: [String: Any],
                      edits: [RelayMarkNativeDocument.SnapshotNodeReplacement], trims: [Trim] = [],
                      attributeUpdates: [RelayMarkNativeDocument.SnapshotAttributeUpdate] = []) throws -> Data {
        var prospective = tree
        for update in attributeUpdates {
            try mutate(path: update.path[...], in: &prospective) { node in
                var attributes = node["attributes"] as? [String: Any] ?? [:]
                for (key, value) in update.attributes { attributes[key] = value is NSNull ? nil : value }
                node["attributes"] = attributes
            }
        }
        for trim in trims {
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
        let expected = try RelayMarkNativeDocumentProjection.project(
            snapshot: JSONSerialization.data(withJSONObject: prospective, options: [.sortedKeys]))
        let removals = trims.map(\.removal)
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        _ = try scratch.replaceSnapshotNodes(edits, textRemovals: removals, attributeUpdates: attributeUpdates)
        guard try RelayMarkNativeDocumentProjection.project(document: scratch) == expected,
              try scratch.richProseProjection().isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return try document.replaceSnapshotNodes(edits, textRemovals: removals, attributeUpdates: attributeUpdates)
    }

}
