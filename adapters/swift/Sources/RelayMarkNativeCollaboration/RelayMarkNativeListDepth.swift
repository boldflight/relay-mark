import Foundation
import RelayMarkSwift

public enum RelayMarkNativeListDepthChange: Sendable {
    case indent, outdent
}

@MainActor
public extension RelayMarkNativeDocument {
    func canChangeMarkdownV3ListDepth(paragraphPath: [Int], change: RelayMarkNativeListDepthChange) -> Bool {
        (try? markdownV3ListDepthPlan(paragraphPath: paragraphPath, change: change, expectedSnapshot: snapshot())) != nil
    }

    /// Native equivalents of ProseMirror sinkListItem/liftListItem. Only moved
    /// items are copied; unaffected lists, items and text retain their Yrs IDs.
    /// Following siblings become children of an outdented item, preserving order.
    func changeMarkdownV3ListDepth(paragraphPath: [Int], change: RelayMarkNativeListDepthChange,
                                  expectedSnapshot: Data) throws -> Data {
        let (edits, expected) = try markdownV3ListDepthPlan(paragraphPath: paragraphPath,
            change: change, expectedSnapshot: expectedSnapshot)
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(encodeUpdate())
        _ = try scratch.replaceSnapshotNodes(edits)
        guard try RelayMarkNativeMarkdownBlocksV3Projection.project(document: scratch) == expected,
              try scratch.markdownV3ProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        return try replaceSnapshotNodes(edits)
    }
}

@MainActor
private extension RelayMarkNativeDocument {
    func markdownV3ListDepthPlan(paragraphPath: [Int], change: RelayMarkNativeListDepthChange,
                                expectedSnapshot: Data) throws -> ([SnapshotNodeReplacement], RelayMarkDocument) {
        guard integrationStatus().isComplete, try snapshot() == expectedSnapshot,
              try markdownV3ProseProjection().isEditable, paragraphPath.count >= 3,
              paragraphPath.last == 0,
              var tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else {
            throw Failure.unsupportedProseEdit
        }
        func node(at path: [Int]) throws -> [String: Any] {
            var result = tree
            for index in path {
                guard let children = result["children"] as? [[String: Any]], children.indices.contains(index) else {
                    throw Failure.invalidTextPath
                }
                result = children[index]
            }
            return result
        }
        func children(_ node: [String: Any]) throws -> [[String: Any]] {
            guard let result = node["children"] as? [[String: Any]] else { throw Failure.unsupportedProseEdit }
            return result
        }
        func freshList(_ list: [String: Any], items: [[String: Any]], startingAtOne: Bool = false) -> [String: Any] {
            var result = list
            var attrs = list["attributes"] as? [String: Any] ?? [:]
            if startingAtOne && list["name"] as? String == "orderedList" { attrs["start"] = 1 }
            attrs["relaymarkId"] = "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
            result["attributes"] = attrs
            result["children"] = items
            return result
        }
        let itemPath = Array(paragraphPath.dropLast()), listPath = Array(itemPath.dropLast())
        guard let itemIndex = itemPath.last, let listIndex = listPath.last else { throw Failure.invalidTextPath }
        let list = try node(at: listPath), item = try node(at: itemPath)
        let listName = list["name"] as? String ?? ""
        let itemName = listName == "taskList" ? "taskItem" : "listItem"
        let items = try children(list)
        guard ["bulletList", "orderedList", "taskList"].contains(listName),
              item["name"] as? String == itemName,
              try node(at: paragraphPath)["name"] as? String == "paragraph" else { throw Failure.unsupportedProseEdit }
        let edits: [SnapshotNodeReplacement]
        switch change {
        case .indent:
            guard itemIndex > 0 else { throw Failure.unsupportedProseEdit }
            let previousPath = listPath + [itemIndex - 1]
            let previous = items[itemIndex - 1], previousChildren = try children(previous)
            guard previous["name"] as? String == itemName else { throw Failure.unsupportedProseEdit }
            let destination: SnapshotNodeReplacement
            if let last = previousChildren.last, last["name"] as? String == listName {
                destination = SnapshotNodeReplacement(parentPath: previousPath + [previousChildren.count - 1],
                    start: try children(last).count, count: 0, nodes: [item])
            } else {
                destination = SnapshotNodeReplacement(parentPath: previousPath,
                    start: previousChildren.count, count: 0, nodes: [freshList(list, items: [item], startingAtOne: true)])
            }
            edits = [destination, SnapshotNodeReplacement(parentPath: listPath, start: itemIndex, count: 1, nodes: [])]
        case .outdent:
            let containingPath = Array(listPath.dropLast()), containing = try node(at: containingPath)
            if ["listItem", "taskItem"].contains(containing["name"] as? String ?? "") {
                let outerPath = Array(containingPath.dropLast()), outer = try node(at: outerPath)
                guard let containingIndex = containingPath.last,
                      containing["name"] as? String == itemName,
                      ["bulletList", "orderedList", "taskList"].contains(outer["name"] as? String ?? ""),
                      ((outer["name"] as? String == "taskList") == (listName == "taskList")) else {
                    throw Failure.unsupportedProseEdit
                }
                var moved = item, movedChildren = try children(item)
                let tail = Array(items.dropFirst(itemIndex + 1))
                if !tail.isEmpty {
                    if var last = movedChildren.last, last["name"] as? String == listName {
                        last["children"] = try children(last) + tail
                        movedChildren[movedChildren.count - 1] = last
                    } else {
                        movedChildren.append(freshList(list, items: tail))
                    }
                    moved["children"] = movedChildren
                }
                let removal = itemIndex == 0
                    ? SnapshotNodeReplacement(parentPath: containingPath, start: listIndex, count: 1, nodes: [])
                    : SnapshotNodeReplacement(parentPath: listPath, start: itemIndex, count: items.count - itemIndex, nodes: [])
                edits = [SnapshotNodeReplacement(parentPath: outerPath, start: containingIndex + 1, count: 0, nodes: [moved]), removal]
            } else {
                // A linked task represents a domain entity. Lifting its prose
                // must not silently discard that relationship.
                let entity = (item["attributes"] as? [String: Any])?["entityId"]
                guard entity == nil || entity is NSNull else { throw Failure.unsupportedProseEdit }
                var lifted = try children(item)
                let tail = Array(items.dropFirst(itemIndex + 1))
                if !tail.isEmpty { lifted.append(freshList(list, items: tail)) }
                if itemIndex == 0 {
                    edits = [SnapshotNodeReplacement(parentPath: containingPath, start: listIndex, count: 1, nodes: lifted)]
                } else {
                    edits = [SnapshotNodeReplacement(parentPath: listPath, start: itemIndex, count: items.count - itemIndex, nodes: []),
                        SnapshotNodeReplacement(parentPath: containingPath, start: listIndex + 1, count: 0, nodes: lifted)]
                }
            }
        }
        func apply(_ edit: SnapshotNodeReplacement, to raw: inout [String: Any], path: ArraySlice<Int>) throws {
            guard var content = raw["children"] as? [[String: Any]] else { throw Failure.invalidTextPath }
            if let index = path.first {
                guard content.indices.contains(index) else { throw Failure.invalidTextPath }
                try apply(edit, to: &content[index], path: path.dropFirst())
            } else {
                guard edit.start >= 0, edit.count >= 0, edit.start + edit.count <= content.count else {
                    throw Failure.invalidTextPath
                }
                content.replaceSubrange(edit.start..<(edit.start + edit.count), with: edit.nodes)
            }
            raw["children"] = content
        }
        for edit in edits { try apply(edit, to: &tree, path: edit.parentPath[...]) }
        let expected = try RelayMarkNativeMarkdownBlocksV3Projection.project(
            snapshot: JSONSerialization.data(withJSONObject: tree, options: [.sortedKeys]))
        return (edits, expected)
    }
}
