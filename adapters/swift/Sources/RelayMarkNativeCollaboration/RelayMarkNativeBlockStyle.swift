import Foundation

public enum RelayMarkNativeBlockStyle: Equatable, Sendable {
    case paragraph, heading(Int), quote, bulletList, orderedList, taskList
}

@MainActor
public extension RelayMarkNativeDocument {
    /// Convert the identified paragraph/heading with maintained node markup and
    /// wrapping steps, preserving its inline content as the transform's gap.
    func setRichBlockStyle(at index: Int, style: RelayMarkNativeBlockStyle,
                                expectedSnapshot: Data) throws -> RelayMarkNativeRichEditing.Change {
        guard integrationStatus().isComplete, try snapshot() == expectedSnapshot,
              try richProseProjection().isEditable,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any],
              let blocks = tree["children"] as? [[String: Any]], blocks.indices.contains(index),
              ["paragraph", "heading"].contains(blocks[index]["name"] as? String ?? ""),
              let attributes = blocks[index]["attributes"] as? [String: Any],
              let id = attributes["relaymarkId"] as? String else { throw Failure.unsupportedProseEdit }
        return try RelayMarkNativeRichEditing.setBlockStyle(document: self, tree: tree, id: id, style: style)
    }
}
