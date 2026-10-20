import Foundation

/// Marks a whole RelayMark document as written by one agent run, with the
/// `ai_authored` mark (`run_id`), as Relay's server marks a generation it
/// builds. A client marks a generation it builds itself, such as an Enhanced
/// draft made on the device, before it becomes a paper.
///
/// The mark is last in schema order, so it wraps each text leaf directly.
/// Code (spans and blocks) cannot carry it and stays unmarked; text already
/// marked keeps its run.
public enum RelayMarkAgentAuthorship {
    public enum Failure: Error, Equatable { case invalidRunID, invalidDocument }

    public static func markDocument(_ document: Data, runID: String) throws -> Data {
        guard !runID.isEmpty, runID.count <= 64 else { throw Failure.invalidRunID }
        guard var root = try JSONSerialization.jsonObject(with: document) as? [String: Any],
              let blocks = root["blocks"] as? [Any] else { throw Failure.invalidDocument }
        root["blocks"] = blocks.map { mark($0, runID) }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private static func mark(_ value: Any, _ runID: String) -> Any {
        guard var node = value as? [String: Any], let type = node["type"] as? String else { return value }
        switch type {
        case "code", "code_span", "ai_authored":
            return node
        case "text":
            return ["type": "ai_authored", "run_id": runID, "content": [node]] as [String: Any]
        default:
            if let content = node["content"] as? [Any] { node["content"] = content.map { mark($0, runID) } }
            return node
        }
    }
}
