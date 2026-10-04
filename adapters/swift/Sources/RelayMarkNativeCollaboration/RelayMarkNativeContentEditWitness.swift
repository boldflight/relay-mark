import Foundation
import RelayMarkSwift

extension RelayMarkNativeDocument {
    /// Private same-owner immediate command observation. It cannot be decoded
    /// from transport or moved to another owner, and provides no permission.
    public final class ContentEditObservation {
        fileprivate weak var owner:RelayMarkNativeDocument?
        fileprivate let identity:Data
        fileprivate let clocks:Any
        fileprivate let stateVector:Data
        fileprivate var consumed=false
        public let beforeSnapshot:Data
        fileprivate init(owner:RelayMarkNativeDocument,identity:Data,clocks:Any,stateVector:Data,beforeSnapshot:Data){
            self.owner=owner;self.identity=identity;self.clocks=clocks;self.stateVector=stateVector;self.beforeSnapshot=beforeSnapshot
        }
    }
    public func captureContentEditObservation() throws -> ContentEditObservation {
        let identity=try captureIdentitySnapshot()
        let footprint=try JSONSerialization.jsonObject(with:captureUpdateFootprint(Data([0,0]))) as! [String:Any]
        guard let clocks=footprint["state_vector"] else {throw Failure.unsupportedProseEdit}
        return ContentEditObservation(owner:self,identity:identity,clocks:clocks,stateVector:stateVector(),beforeSnapshot:try captureSenderSnapshot())
    }
    /// Immediate read-only inverse evidence from the actual same-manager effect.
    /// Sources may be tombstoned. Accepted receipts, actor/group authority and
    /// complete mutation correspondence remain server gates.
    public func buildOwnedHistoryWitness(_ observation:ContentEditObservation,effect:OwnedHistoryEffect) throws -> Data {
        guard observation.owner===self,!observation.consumed,integrationStatus().isComplete,
              effect.beforeSnapshot==observation.beforeSnapshot else {throw Failure.unsupportedProseEdit}
        let observed=try JSONSerialization.jsonObject(with:captureRestoredTextItems(since:observation.stateVector)) as! [String:Any]
        guard let copies=observed["copies"] as? [[String:Any]] else {throw Failure.unsupportedProseEdit}
        let history:[String:Any]=["kind":effect.kind.rawValue,"reference":effect.reference.uuidString.lowercased(),
            "operation_ids":effect.operationIDs.map{$0.uuidString.lowercased()}]
        let evidence:[String:Any]=["before_snapshot":try JSONSerialization.jsonObject(with:observation.identity),
            "after_snapshot":try JSONSerialization.jsonObject(with:captureIdentitySnapshot()),"before_state_vector":observation.clocks,
            "operation":["kind":"content_edit","steps":try JSONSerialization.jsonObject(with:effect.steps),"history":history],
            "restored_copies":copies,"footprint":try JSONSerialization.jsonObject(with:captureUpdateFootprint(effect.update))]
        let result=try RelayMarkContentEditCodec.buildOwnedHistoryWitness(JSONSerialization.data(withJSONObject:evidence,options:[.sortedKeys]))
        observation.consumed=true
        return result
    }
    /// Reads the actual original command update and delegates causal allocation
    /// accounting to the shared maintained StepMap/grammar owner. Complete
    /// mutation replay, clipboard source authority and receipts remain server gates.
    public func buildContentEditWitness(_ observation:ContentEditObservation,steps:Data,update:Data,explicitCopies:Data?=nil) throws -> Data {
        guard observation.owner===self,!observation.consumed,integrationStatus().isComplete else {throw Failure.unsupportedProseEdit}
        let before=try JSONSerialization.jsonObject(with:observation.identity)
        let after=try JSONSerialization.jsonObject(with:captureIdentitySnapshot())
        var operation:[String:Any]=["kind":"content_edit","steps":try JSONSerialization.jsonObject(with:steps)]
        if let explicitCopies {operation["copies"]=try JSONSerialization.jsonObject(with:explicitCopies)}
        let evidence:[String:Any]=["sender_before_snapshot":before,"before_snapshot":before,
            "sender_after_snapshot":after,"after_snapshot":after,"before_state_vector":observation.clocks,
            "operation":operation,"footprint":try JSONSerialization.jsonObject(with:captureUpdateFootprint(update))]
        let prepared=try RelayMarkContentEditCodec.buildWitness(JSONSerialization.data(withJSONObject:evidence,options:[.sortedKeys]))
        observation.consumed=true
        return prepared
    }
}
