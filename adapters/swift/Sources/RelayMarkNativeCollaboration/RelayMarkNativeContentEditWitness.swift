import Foundation
import RelayMarkSwift

extension RelayMarkNativeDocument {
    /// Private same-owner immediate command observation. It cannot be decoded
    /// from transport or moved to another owner, and provides no permission.
    public final class ContentEditObservation {
        fileprivate weak var owner:RelayMarkNativeDocument?
        fileprivate let identity:Data
        fileprivate let clocks:Any
        fileprivate var consumed=false
        public let beforeSnapshot:Data
        fileprivate init(owner:RelayMarkNativeDocument,identity:Data,clocks:Any,beforeSnapshot:Data){
            self.owner=owner;self.identity=identity;self.clocks=clocks;self.beforeSnapshot=beforeSnapshot
        }
    }
    public func captureContentEditObservation() throws -> ContentEditObservation {
        let identity=try captureIdentitySnapshot()
        let footprint=try JSONSerialization.jsonObject(with:captureUpdateFootprint(Data([0,0]))) as! [String:Any]
        guard let clocks=footprint["state_vector"] else {throw Failure.unsupportedProseEdit}
        return ContentEditObservation(owner:self,identity:identity,clocks:clocks,beforeSnapshot:try captureSenderSnapshot())
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
