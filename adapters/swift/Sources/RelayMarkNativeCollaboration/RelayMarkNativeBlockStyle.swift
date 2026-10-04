import Foundation

public enum RelayMarkNativeBlockStyle: Equatable, Sendable {
    case paragraph, heading(Int), quote, bulletList, orderedList, taskList
}

@MainActor
public extension RelayMarkNativeDocument {
    /// Converts the selected top-level paragraph/heading through ordinary Yrs XML.
    /// Child runs, semantic references and authored IDs are copied intact. Wrapper
    /// IDs are fresh. This is an explicit structural command and one undo item.
    func setRichBlockStyle(at index: Int, style: RelayMarkNativeBlockStyle,
                                expectedSnapshot: Data) throws -> Data {
        guard integrationStatus().isComplete, try snapshot() == expectedSnapshot,
              try richProseProjection().isEditable,
              var root = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any],
              var blocks = root["children"] as? [[String: Any]], blocks.indices.contains(index),
              ["paragraph", "heading"].contains(blocks[index]["name"] as? String ?? ""),
              let attributes = blocks[index]["attributes"] as? [String: Any],
              let id = attributes["relaymarkId"] as? String else { throw Failure.unsupportedProseEdit }
        if case .heading(let level) = style, blocks[index]["name"] as? String == "heading" {
            return try setRichHeadingLevel(anchor: anchor(path: [index], index: 0),
                expectedHeadingID: attributes["headingId"] as? String, level: level)
        }
        let children = blocks[index]["children"] as? [[String: Any]] ?? []
        func freshID() -> String { "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "") }
        func element(_ name: String, _ attrs: [String: Any], _ content: [[String: Any]]) -> [String: Any] {
            ["kind": "element", "name": name, "attributes": attrs, "children": content]
        }
        let paragraph = element("paragraph", ["relaymarkId": id], children)
        let replacement: [String: Any]
        switch style {
        case .paragraph: replacement = paragraph
        case .heading(let level):
            guard (1...6).contains(level) else { throw Failure.unsupportedProseEdit }
            let headingID = attributes["headingId"] as? String ?? "h-" + UUID().uuidString.lowercased()
            replacement = element("heading", ["relaymarkId": id, "level": level, "headingId": headingID], children)
        case .quote: replacement = element("blockquote", ["relaymarkId": freshID()], [paragraph])
        case .bulletList, .orderedList, .taskList:
            let task = style == .taskList
            var itemAttrs: [String: Any] = ["relaymarkId": freshID()]
            if task { itemAttrs["checked"] = false }
            let item = element(task ? "taskItem" : "listItem", itemAttrs, [paragraph])
            var attrs: [String: Any] = ["relaymarkId": freshID()]
            if style == .orderedList { attrs["start"] = 1; attrs["type"] = NSNull() }
            replacement = element(task ? "taskList" : style == .orderedList ? "orderedList" : "bulletList", attrs, [item])
        }
        blocks[index] = replacement
        root["children"] = blocks
        let prospective = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let expected = try RelayMarkNativeDocumentProjection.project(snapshot: prospective)
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(encodeUpdate())
        _ = try scratch.replaceSnapshotNodes(parentPath: [], start: index, count: 1, nodes: [replacement])
        guard try RelayMarkNativeDocumentProjection.project(document: scratch) == expected,
              try scratch.richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        return try replaceSnapshotNodes(parentPath: [], start: index, count: 1, nodes: [replacement])
    }
}
