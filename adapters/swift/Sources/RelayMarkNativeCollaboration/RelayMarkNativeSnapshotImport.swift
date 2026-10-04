import Foundation
import RelayMarkSwift
import YSwift

/// Finite retained-snapshot migration on the same Yrs owner. Hosts must durably
/// retain Prepared.originalState and exact import evidence before installation.
/// Normal edits/admission never call this decoder as a fallback.
@MainActor public enum RelayMarkNativeSnapshotImport {
    public struct Prepared {
        public let originalState: Data
        public let result: Data
        fileprivate let owner: ObjectIdentifier
        fileprivate let originalSnapshot: Data
        fileprivate let originalVector: Data
        fileprivate let updates: [RelayMarkNativeDocument.SnapshotAttributeUpdate]
    }
    public static func prepare(document:RelayMarkNativeDocument,namespace:String,
                               expectedSnapshot:Data) throws -> Prepared {
        guard document.integrationStatus().isComplete,try document.snapshot()==expectedSnapshot else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let result=try RelayMarkSourceCodec.importDocumentSnapshot(expectedSnapshot,namespace:namespace)
        guard let decoded=try JSONSerialization.jsonObject(with:result) as? [String:Any],
              decoded["requires_reconstruction"] as? Bool == false,
              let changes=decoded["normalizations"] as? [[String:Any]],
              let expectedTree=decoded["snapshot"] as? [String:Any],
              var original=try JSONSerialization.jsonObject(with:expectedSnapshot) as? [String:Any] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        var updates:[RelayMarkNativeDocument.SnapshotAttributeUpdate]=[]
        func patch(_ node:inout [String:Any],path:ArraySlice<Int>,name:String,value:Any,before:Any?,adding:Bool) throws {
            if let index=path.first {
                guard var children=node["children"] as? [[String:Any]],children.indices.contains(index) else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
                try patch(&children[index],path:path.dropFirst(),name:name,value:value,before:before,adding:adding);node["children"]=children
            } else {
                guard node["kind"] as? String == "element",var attributes=node["attributes"] as? [String:Any] else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
                if adding { guard attributes[name]==nil else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit } }
                else { guard NSDictionary(dictionary:["value":attributes[name] ?? NSNull()]).isEqual(to:["value":before ?? NSNull()]) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit } }
                if value is NSNull { attributes.removeValue(forKey:name) } else { attributes[name]=value };node["attributes"]=attributes
            }
        }
        for change in changes {
            guard let path=change["path"] as? [Int],!path.isEmpty,let name=change["name"] as? String,
                  let operation=change["operation"] as? String,["add_attribute","set_attribute","remove_attribute"].contains(operation) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            let value:Any=operation=="remove_attribute" ? NSNull() : change["value"] ?? NSNull()
            try patch(&original,path:path[...],name:name,value:value,before:change["before"],adding:operation=="add_attribute")
            updates.append(.init(path:path,attributes:[name:value]))
        }
        guard NSDictionary(dictionary:original).isEqual(to:expectedTree) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        _=try RelayMarkSourceCodec.snapshotToDocument(JSONSerialization.data(withJSONObject:original))
        return Prepared(originalState:try document.encodeUpdate(),result:result,owner:ObjectIdentifier(document),originalSnapshot:expectedSnapshot,originalVector:document.stateVector(),updates:updates)
    }
    /// Stale peer changes refuse before mutation. No text/node reconstruction is
    /// allowed by this additive/removal attribute installation boundary.
    public static func install(document:RelayMarkNativeDocument,prepared:Prepared) throws -> Data {
        guard ObjectIdentifier(document)==prepared.owner,try document.encodeUpdate()==prepared.originalState,document.stateVector()==prepared.originalVector,
              try document.snapshot()==prepared.originalSnapshot else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return try document.replaceSnapshotNodes([],attributeUpdates:prepared.updates,origin:Origin("relaymark:finite-import"))
    }
}
