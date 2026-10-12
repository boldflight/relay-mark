import Foundation
import RelayMarkSwift
import RelayMarkProseProjection

public typealias RelayMarkNativeListDepthChange = RelayMarkListDepthChange

@MainActor
public extension RelayMarkNativeDocument {
    func canChangeRichListDepth(paragraphPath: [Int], change: RelayMarkNativeListDepthChange) -> Bool {
        (try? maintainedListDepthRequest(paragraphPath: paragraphPath, change: change, expectedSnapshot: snapshot())) != nil
    }

    func changeRichListDepth(paragraphPath: [Int], change: RelayMarkNativeListDepthChange,
                            expectedSnapshot: Data) throws -> RelayMarkNativeRichEditing.Change {
        let request = try maintainedListDepthRequest(paragraphPath: paragraphPath, change: change, expectedSnapshot: expectedSnapshot)
        return try RelayMarkNativeRichEditing.command(document: self, tree: request.tree,
            name: request.name, selection: request.selection).change
    }
}

@MainActor
private extension RelayMarkNativeDocument {
    func maintainedListDepthRequest(paragraphPath: [Int], change: RelayMarkNativeListDepthChange,
                                    expectedSnapshot: Data) throws -> (tree: [String: Any], name: String, selection: [String: Any]) {
        guard integrationStatus().isComplete, try snapshot() == expectedSnapshot,
              try richProseProjection().isEditable,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else { throw Failure.unsupportedProseEdit }
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: tree)
        let position = try RelayMarkNativeRichEditing.positionForPath(paragraphPath, in: source) + 1
        let name = change == .indent ? "sink_list_item" : "lift_list_item"
        let selection: [String: Any] = ["type": "text", "anchor": position, "head": position]
        _ = try RelayMarkContentEditCodec.command(document: JSONSerialization.data(withJSONObject: source.json()),
            request: JSONSerialization.data(withJSONObject: ["command": name, "selection": selection]))
        return (tree, name, selection)
    }
}
