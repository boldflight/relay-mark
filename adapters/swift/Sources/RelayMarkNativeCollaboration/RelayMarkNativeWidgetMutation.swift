import Foundation
import RelayMarkSwift

/// Authored widget insertion and settings use the same canonical document grammar and Yrs transaction owner.
/// Domain publication, answers and permission changes remain host actions.
@MainActor public enum RelayMarkNativeWidgetMutation {
    public static func insert(document: RelayMarkNativeDocument,parentPath: [Int],at index: Int,
                              authoredBlock: Data,expectedSnapshot: Data) throws -> RelayMarkNativeRichEditing.Change {
        guard try document.snapshot()==expectedSnapshot,let block=try JSONSerialization.jsonObject(with:authoredBlock) as? [String:Any],
              let type=block["type"] as? String,type.hasPrefix("relay.") else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        guard let tree=try JSONSerialization.jsonObject(with:expectedSnapshot) as? [String:Any],
              var ast=try JSONSerialization.jsonObject(with:document.authoredDocument()) as? [String:Any] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        // A nested option/label is not a legal document root. Resolve its actual
        // identified parent, then validate the complete prospective authored tree.
        if parentPath.isEmpty {
            guard var blocks=ast["blocks"] as? [[String:Any]],index>=0,index<=blocks.count else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
            blocks.insert(block,at:index);ast["blocks"]=blocks
        } else {
            let parent=try RelayMarkNativeRichXML.node(at:parentPath,in:tree)
            guard let attributes=parent["attributes"] as? [String:Any],let id=attributes["relaymarkId"] as? String,
                  var blocks=ast["blocks"] as? [[String:Any]] else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
            func insert(in node: inout [String:Any]) throws -> Bool {
                if node["id"] as? String == id {
                    guard var children=node["content"] as? [[String:Any]],index>=0,index<=children.count else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
                    children.insert(block,at:index);node["content"]=children;return true
                }
                guard var children=node["content"] as? [[String:Any]] else { return false }
                for position in children.indices where try insert(in:&children[position]) { node["content"]=children;return true }
                return false
            }
            var found=false
            for position in blocks.indices where try insert(in:&blocks[position]) { found=true;break }
            guard found else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
            ast["blocks"]=blocks
        }
        let candidate=try RelayMarkSourceCodec.documentToSnapshot(JSONSerialization.data(withJSONObject:ast))
        guard let canonical=try JSONSerialization.jsonObject(with:candidate) as? [String:Any] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let parent=try RelayMarkNativeRichXML.node(at:parentPath,in:canonical)
        let children=try RelayMarkNativeRichXML.children(parent)
        guard children.indices.contains(index) else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
        let parentID: String?
        if parentPath.isEmpty { parentID = nil }
        else {
            let originalParent = try RelayMarkNativeRichXML.node(at: parentPath, in: tree)
            parentID = (originalParent["attributes"] as? [String: Any])?["relaymarkId"] as? String
            guard parentID != nil else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
        }
        return try RelayMarkNativeRichEditing.insertWidget(document: document, tree: tree,
            candidate: canonical, parentID: parentID, index: index)
    }
    /// Remove an identified authored child through the same complete parent/tree
    /// preflight. Required labels and other invalid final ancestry refuse before mutation.
    public static func remove(document:RelayMarkNativeDocument,path:[Int],expectedID:String,
                              expectedSnapshot:Data) throws -> RelayMarkNativeRichEditing.Change {
        guard !path.isEmpty,try document.snapshot()==expectedSnapshot,
              let tree=try JSONSerialization.jsonObject(with:expectedSnapshot) as? [String:Any] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let node=try RelayMarkNativeRichXML.node(at:path,in:tree)
        guard let attributes=node["attributes"] as? [String:Any],attributes["relaymarkId"] as? String==expectedID else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
        return try RelayMarkNativeRichEditing.removeWidget(document: document, tree: tree, id: expectedID)
    }

    /// Move one identified sibling using the same maintained rich transform.
    /// The original node and its rich content are supplied by the current document.
    public static func move(document: RelayMarkNativeDocument, path: [Int], expectedID: String,
                            direction: Int, expectedSnapshot: Data) throws -> RelayMarkNativeRichEditing.Change {
        guard !path.isEmpty, direction == -1 || direction == 1,
              try document.snapshot() == expectedSnapshot,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any],
              let index = path.last else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let parentPath = Array(path.dropLast())
        let parent = try RelayMarkNativeRichXML.node(at: parentPath, in: tree)
        let siblings = try RelayMarkNativeRichXML.children(parent)
        guard siblings.indices.contains(index), siblings.indices.contains(index + direction),
              let name = siblings[index]["name"] as? String, siblings[index + direction]["name"] as? String == name,
              (siblings[index]["attributes"] as? [String: Any])?["relaymarkId"] as? String == expectedID else {
            throw RelayMarkNativeDocument.Failure.invalidTextPath
        }
        let parentID = (parent["attributes"] as? [String: Any])?["relaymarkId"] as? String
        guard parentPath.isEmpty || parentID != nil else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
        return try RelayMarkNativeRichEditing.moveWidget(document: document, tree: tree,
            parentID: parentID, index: index, direction: direction)
    }

    public struct AttributeUpdate: Sendable {
        public let path: [Int]
        public let id: String
        public let expected, changes: Data
        public init(path: [Int], id: String, expected: Data, changes: Data) {
            self.path = path; self.id = id; self.expected = expected; self.changes = changes
        }
    }

    /// Validate every captured touched field before one maintained attribute transform.
    /// Single-choice correctness can clear siblings without a partial command.
    public static func updateAttributes(document: RelayMarkNativeDocument,
                                        updates: [AttributeUpdate]) throws -> RelayMarkNativeRichEditing.Change {
        guard !updates.isEmpty, Set(updates.map(\.id)).count == updates.count,
              let tree = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        var changes: [(id: String, attributes: [String: Any])] = []
        for update in updates {
            let guarded = try guardedAttributes(tree: tree, path: update.path, expectedID: update.id,
                expected: update.expected, changes: update.changes, expectedMediaSource: nil)
            let changed = guarded.patch.filter { !NSDictionary(dictionary: ["value": guarded.attributes[$0.key] ?? NSNull()]).isEqual(to: ["value": $0.value]) }
            if !changed.isEmpty { changes.append((update.id, changed)) }
        }
        guard !changes.isEmpty else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return try RelayMarkNativeRichEditing.updateWidgets(document: document, tree: tree, changes: changes)
    }

    /// Compare the touched attribute keys, preserving independent peer fields and child text.
    /// Media commands also bind the displayed source identity before changing properties.
    public static func updateAttributes(document: RelayMarkNativeDocument,path: [Int],expectedID: String,
                                        expected: Data,changes: Data,
                                        expectedMediaSource: String? = nil) throws -> RelayMarkNativeRichEditing.Change {
        guard let tree = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let guarded = try guardedAttributes(tree: tree, path: path, expectedID: expectedID,
            expected: expected, changes: changes, expectedMediaSource: expectedMediaSource)
        return try RelayMarkNativeRichEditing.updateWidget(document: document, tree: tree,
            id: expectedID, attributes: guarded.patch)
    }

    private static func guardedAttributes(tree: [String: Any], path: [Int], expectedID: String,
                                           expected: Data, changes: Data, expectedMediaSource: String?) throws -> (patch: [String: Any], attributes: [String: Any]) {
        guard let before=try JSONSerialization.jsonObject(with:expected) as? [String:Any],
              let patch=try JSONSerialization.jsonObject(with:changes) as? [String:Any],!patch.isEmpty,
              Set(before.keys)==Set(patch.keys),!patch.keys.contains("relaymarkId"),!patch.keys.contains("id") else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let node=try RelayMarkNativeRichXML.node(at:path,in:tree)
        guard let name=node["name"] as? String,
              name=="questionBlock" || name=="questionOption" || name=="relayDataView" || name.hasPrefix("relay") || name=="image" || name=="videoEmbed",
              let physical=node["attributes"] as? [String:Any],physical["relaymarkId"] as? String==expectedID else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let attributes = try RelayMarkContentEditCodec.decodeDocumentAttributes(nodeName: name, attributes: physical)
        guard before.allSatisfy({key,value in NSDictionary(dictionary:["value":attributes[key] ?? NSNull()]).isEqual(to:["value":value])}) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        if name=="image" || name=="videoEmbed" {
            guard let expectedMediaSource,
                  attributes[name=="image" ? "src" : "videoId"] as? String==expectedMediaSource else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
        } else if expectedMediaSource != nil {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return (patch, attributes)
    }
}
