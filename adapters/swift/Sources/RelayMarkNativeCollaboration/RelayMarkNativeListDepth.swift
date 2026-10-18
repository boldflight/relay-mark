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
    /// item, read from its own top-level node.
    func isRichListParagraph(path: [Int]) -> Bool {
        guard path.count >= 3, path.last == 0, let first = path.first,
              var node = (try? snapshot(topLevel: first..<(first + 1)))?["children"] as? [[String: Any]] else { return false }
        var list: [String: Any] = ["children": node]
        for index in [0] + path.dropFirst().dropLast(2) {
            guard let children = list["children"] as? [[String: Any]], children.indices.contains(index) else { return false }
            list = children[index]
        }
        node = list["children"] as? [[String: Any]] ?? []
        let name = list["name"] as? String ?? ""
        return ["bulletList", "orderedList", "taskList"].contains(name) && node.indices.contains(path[path.count - 2]) &&
            node[path[path.count - 2]]["name"] as? String == (name == "taskList" ? "taskItem" : "listItem")
    }

    /// The same check and command on a window of top-level nodes around the
    /// item. `paper` is the caller's projection of the document as it is now.
    func canChangeRichListDepth(paragraphPath: [Int], change: RelayMarkNativeListDepthChange,
                                paper: RelayMarkCollaborativeProse) -> Bool {
        (try? windowedListDepthRequest(paragraphPath: paragraphPath, change: change, paper: paper)) != nil
    }

    func changeRichListDepth(paragraphPath: [Int], change: RelayMarkNativeListDepthChange,
                             paper: RelayMarkCollaborativeProse) throws -> RelayMarkNativeRichEditing.Change {
        let request = try windowedListDepthRequest(paragraphPath: paragraphPath, change: change, paper: paper)
        return try RelayMarkNativeRichEditing.command(document: self, tree: request.scope.tree,
            name: request.name, selection: request.selection, scope: request.scope).change
    }
}

@MainActor
private extension RelayMarkNativeDocument {
    func windowedListDepthRequest(paragraphPath: [Int], change: RelayMarkNativeListDepthChange,
                                  paper: RelayMarkCollaborativeProse)
        throws -> (scope: RelayMarkNativeRichEditing.Scope, name: String, selection: [String: Any]) {
        guard let first = paragraphPath.first else { throw Failure.invalidTextPath }
        let scope = try RelayMarkNativeRichEditing.scope(document: self, paper: paper, nodes: first...first)
        guard scope.projection.isEditable else { throw Failure.unsupportedProseEdit }
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: scope.tree)
        let position = try RelayMarkNativeRichEditing.positionForPath(scope.local(paragraphPath), in: source) + 1
        let name = change == .indent ? "sink_list_item" : "lift_list_item"
        let selection: [String: Any] = ["type": "text", "anchor": position, "head": position]
        _ = try RelayMarkContentEditCodec.command(document: JSONSerialization.data(withJSONObject: source.json()),
            request: JSONSerialization.data(withJSONObject: ["command": name, "selection": selection]))
        return (scope, name, selection)
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
