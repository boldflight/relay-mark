import Foundation

/// Empty secondary-paragraph Enter follows TipTap splitListItem and the
/// ProseMirror liftEmptyBlock fallback. Yrs still owns transactions and undo.
@MainActor
enum RelayMarkNativeMarkdownV3ListExit {
    private typealias XML = RelayMarkNativeMarkdownV3XML

    static func apply(document: RelayMarkNativeDocument, tree: [String: Any],
                      blockPath: [Int], blockID: String) throws -> RelayMarkNativeMarkdownV3Return.Result {
        let itemPath = Array(blockPath.dropLast()), listPath = Array(itemPath.dropLast())
        let containingPath = Array(listPath.dropLast())
        guard let paragraphIndex = blockPath.last, let itemIndex = itemPath.last,
              let listIndex = listPath.last else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
        let block = try XML.node(at: blockPath, in: tree), item = try XML.node(at: itemPath, in: tree)
        let list = try XML.node(at: listPath, in: tree), items = try XML.children(list)
        let containing = try XML.node(at: containingPath, in: tree)
        var edits = [RelayMarkNativeDocument.SnapshotNodeReplacement(parentPath: itemPath,
            start: paragraphIndex, count: 1, nodes: [])]
        func identifiedCopy(_ node: [String: Any], children: [[String: Any]]) -> [String: Any] {
            var result = node, attrs = node["attributes"] as? [String: Any] ?? [:]
            attrs["relaymarkId"] = XML.freshID()
            result["attributes"] = attrs; result["children"] = children
            return result
        }
        if containing["name"] as? String == item["name"] as? String && itemIndex == items.count - 1 {
            // Community splitListItem exits at the outer item level. A trailing
            // outer body becomes a separate sibling, as in ProseMirror's slice.
            let outerListPath = Array(containingPath.dropLast())
            guard let outerIndex = containingPath.last else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
            let outerBody = try XML.children(containing), tail = Array(outerBody.dropFirst(listIndex + 1))
            var next = identifiedCopy(item, children: [block])
            var attrs = next["attributes"] as? [String: Any] ?? [:]
            if item["name"] as? String == "taskItem" { attrs["checked"] = false; attrs.removeValue(forKey: "entityId") }
            next["attributes"] = attrs
            var siblings = [next]
            if !tail.isEmpty {
                var body = tail
                if body.first?["name"] as? String != "paragraph" {
                    body.insert(["kind": "element", "name": "paragraph",
                                 "attributes": ["relaymarkId": XML.freshID()], "children": [[String: Any]]()], at: 0)
                }
                siblings.append(identifiedCopy(containing, children: body))
                edits.append(.init(parentPath: containingPath, start: listIndex + 1, count: tail.count, nodes: []))
            }
            edits.append(.init(parentPath: outerListPath, start: outerIndex + 1, count: 0, nodes: siblings))
        } else {
            // liftEmptyBlock splits the surrounding list around the paragraph.
            // Existing item/relationship metadata stays on its retained prefix.
            let tail = Array(items.dropFirst(itemIndex + 1))
            var lifted = [block]
            if !tail.isEmpty {
                lifted.append(identifiedCopy(list, children: tail))
                edits.append(.init(parentPath: listPath, start: itemIndex + 1, count: tail.count, nodes: []))
            }
            edits.append(.init(parentPath: containingPath, start: listIndex + 1, count: 0, nodes: lifted))
        }
        return .init(update: try XML.apply(document: document, tree: tree, edits: edits),
                     kind: .exit, blockID: blockID)
    }
}
