import Foundation
import RelayMarkSwift

/// Authored widget insertion and settings use the same canonical document grammar and Yrs transaction owner.
/// Domain publication, answers and permission changes remain host actions.
@MainActor public enum RelayMarkNativeWidgetMutation {
    public static func insert(document: RelayMarkNativeDocument,parentPath: [Int],at index: Int,
                              authoredBlock: Data,expectedSnapshot: Data) throws -> Data {
        guard try document.snapshot()==expectedSnapshot,let block=try JSONSerialization.jsonObject(with:authoredBlock) as? [String:Any],
              let type=block["type"] as? String,type.hasPrefix("relay.") else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let ast=try JSONSerialization.data(withJSONObject:["type":"relaymark.document","blocks":[block]])
        guard let snapshot=try JSONSerialization.jsonObject(with:RelayMarkSourceCodec.documentToSnapshot(ast)) as? [String:Any],
              let nodes=snapshot["children"] as? [[String:Any]],nodes.count==1,
              let tree=try JSONSerialization.jsonObject(with:expectedSnapshot) as? [String:Any] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return try RelayMarkNativeRichXML.apply(document:document,tree:tree,
          edits:[.init(parentPath:parentPath,start:index,count:0,nodes:nodes)])
    }
    /// Compare only the touched attribute keys, preserving independent peer fields and child text.
    public static func updateAttributes(document: RelayMarkNativeDocument,path: [Int],expectedID: String,
                                        expected: Data,changes: Data) throws -> Data {
        let snapshot=try document.snapshot()
        guard let tree=try JSONSerialization.jsonObject(with:snapshot) as? [String:Any],
              let before=try JSONSerialization.jsonObject(with:expected) as? [String:Any],
              let patch=try JSONSerialization.jsonObject(with:changes) as? [String:Any],!patch.isEmpty,
              Set(before.keys)==Set(patch.keys),!patch.keys.contains("relaymarkId"),!patch.keys.contains("id") else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let node=try RelayMarkNativeRichXML.node(at:path,in:tree)
        guard let name=node["name"] as? String,name=="questionBlock" || name=="questionOption" || name=="relayDataView" || name.hasPrefix("relay"),
              let attributes=node["attributes"] as? [String:Any],attributes["relaymarkId"] as? String==expectedID,
              before.allSatisfy({key,value in NSDictionary(dictionary:["value":attributes[key] ?? NSNull()]).isEqual(to:["value":value])}) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return try RelayMarkNativeRichXML.apply(document:document,tree:tree,edits:[],
          attributeUpdates:[.init(path:path,attributes:patch)])
    }
}
