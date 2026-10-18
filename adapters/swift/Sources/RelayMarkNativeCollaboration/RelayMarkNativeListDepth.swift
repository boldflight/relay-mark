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

    /// Whether `path` is the first paragraph of a bullet, ordered or task list
    /// item, read from the one child of its top-level node that holds it.
    func isRichListParagraph(path: [Int]) -> Bool {
        guard path.count >= 3, path.last == 0,
              var node = (try? snapshot(items: path[1]..<(path[1] + 1), ofTopLevel: path[0]))?["children"] as? [[String: Any]]
        else { return false }
        let local = [0, 0] + path.dropFirst(2)
        var list: [String: Any] = ["children": node]
        for index in local.dropLast(2) {
            guard let children = list["children"] as? [[String: Any]], children.indices.contains(index) else { return false }
            list = children[index]
        }
        node = list["children"] as? [[String: Any]] ?? []
        let name = list["name"] as? String ?? ""
        return ["bulletList", "orderedList", "taskList"].contains(name) && node.indices.contains(local[local.count - 2]) &&
            node[local[local.count - 2]]["name"] as? String == (name == "taskList" ? "taskItem" : "listItem")
    }

    /// The same check and command on a window of top-level nodes around the
    /// item. `paper` is the caller's projection of the document as it is now.
    func canChangeRichListDepth(paragraphPath: [Int], change: RelayMarkNativeListDepthChange,
                                paper: RelayMarkCollaborativeProse) -> Bool {
        (try? RelayMarkNativeRichEditing.windowed(document: self, paper: paper, paths: [paragraphPath]) { scope in
            try windowedListDepthRequest(paragraphPath: paragraphPath, change: change, scope: scope)
        }) != nil
    }

    func changeRichListDepth(paragraphPath: [Int], change: RelayMarkNativeListDepthChange,
                             paper: RelayMarkCollaborativeProse) throws -> RelayMarkNativeRichEditing.Change {
        try RelayMarkNativeRichEditing.windowed(document: self, paper: paper, paths: [paragraphPath]) { scope in
            let request = try windowedListDepthRequest(paragraphPath: paragraphPath, change: change, scope: scope)
            return try RelayMarkNativeRichEditing.command(document: self, tree: scope.tree,
                name: request.name, selection: request.selection, scope: scope).change
        }
    }
}

@MainActor
private extension RelayMarkNativeDocument {
    func windowedListDepthRequest(paragraphPath: [Int], change: RelayMarkNativeListDepthChange,
                                  scope: RelayMarkNativeRichEditing.Scope) throws -> (name: String, selection: [String: Any]) {
        guard scope.projection.isEditable else { throw Failure.unsupportedProseEdit }
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: scope.tree)
        let position = try RelayMarkNativeRichEditing.positionForPath(scope.local(paragraphPath), in: source) + 1
        let name = change == .indent ? "sink_list_item" : "lift_list_item"
        let selection: [String: Any] = ["type": "text", "anchor": position, "head": position]
        _ = try RelayMarkContentEditCodec.command(document: JSONSerialization.data(withJSONObject: source.json()),
            request: JSONSerialization.data(withJSONObject: ["command": name, "selection": selection]))
        return (name, selection)
    }

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
