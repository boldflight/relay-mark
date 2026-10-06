import Foundation

/// An explicit addition of selected retained blocks. Community Yrs supplies the
/// XML operations; RelayMark validates the existing portable editor schema.
@MainActor
public extension RelayMarkNativeDocument {
    func appendRecoveredRichBlocks(from sourceSnapshot: Data, indices: [Int],
                                         expectedSnapshot: Data) throws -> RelayMarkNativeRichEditing.Change {
        guard try snapshot() == expectedSnapshot, integrationStatus().isComplete,
              !indices.isEmpty, indices == indices.sorted(), Set(indices).count == indices.count else {
            throw Failure.unsupportedProseEdit
        }
        _ = try RelayMarkNativeDocumentProjection.project(snapshot: sourceSnapshot)
        _ = try RelayMarkNativeDocumentProjection.project(snapshot: expectedSnapshot)
        guard let source = try JSONSerialization.jsonObject(with: sourceSnapshot) as? [String: Any],
              let blocks = source["children"] as? [[String: Any]],
              indices.allSatisfy({ blocks.indices.contains($0) }),
              let current = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any],
              let existing = current["children"] as? [[String: Any]] else {
            throw Failure.unsupportedProseEdit
        }
        func copied(_ node: [String: Any]) -> [String: Any] {
            var result = node
            if var attributes = node["attributes"] as? [String: Any], attributes["relaymarkId"] != nil {
                attributes["relaymarkId"] = "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
                result["attributes"] = attributes
            }
            if let children = node["children"] as? [[String: Any]] { result["children"] = children.map(copied) }
            return result
        }
        let additions = indices.map { copied(blocks[$0]) }
        return try RelayMarkNativeRichEditing.replaceRootChildren(document: self, tree: current,
            index: existing.count, count: 0, replacements: additions,
            reviewedArchive: try PMYXmlBridge.canonical().document(fromSnapshot: source), reviewedIndices: indices)
    }
}
