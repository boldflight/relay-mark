import Foundation

/// The packaged maintained StepMap/identity witness owner. This stateless
/// preparation confers neither accepted receipt scope nor source authority.
public enum RelayMarkContentEditCodec {
    public static func command(document: Data, request: Data) throws -> Data {
        try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "createContentEditCommand", arguments: [JSONSerialization.jsonObject(with: document), JSONSerialization.jsonObject(with: request)])
    }
    public static func prepareWrite(before: Data, steps: Data, after: Data) throws -> Data {
        try RelayMarkPortableRuntime.call(resource:"content-edit-runtime",global:"RelayMarkContentEditRuntime",operation:"prepareContentEditWrite",arguments:[JSONSerialization.jsonObject(with:before),JSONSerialization.jsonObject(with:steps),JSONSerialization.jsonObject(with:after)])
    }
    public static func planTextWrite(prepared: Data, sourceParent: String, sourceGroup: Int, targetParent: String, targetGroup: Int, sourceOffset: Int, sourceLength: Int) throws -> Data {
        try RelayMarkPortableRuntime.call(resource:"content-edit-runtime",global:"RelayMarkContentEditRuntime",operation:"planContentEditTextWrite",arguments:[JSONSerialization.jsonObject(with:prepared),sourceParent,sourceGroup,targetParent,targetGroup,["offset":sourceOffset,"length":sourceLength]])
    }
    /// Preliminary inverse producer. The returned flags explicitly require
    /// authenticated accepted-history replay and complete mutation proof.
    public static func buildOwnedHistoryWitness(_ evidence:Data) throws -> Data {
        let object=try JSONSerialization.jsonObject(with:evidence)
        return try RelayMarkPortableRuntime.call(resource:"content-edit-runtime",global:"RelayMarkContentEditRuntime",operation:"buildOwnedHistoryWitness",arguments:[object])
    }
    /// Regional allocation evidence only. Archive hashes, donor ancestry and
    /// target authorization remain independently authenticated by the host.
    public static func prepareReviewedRecoveryWitness(_ evidence: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: evidence)
        return try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "prepareReviewedRecoveryWitness", arguments: [object])
    }
    /// Target-only replay of a host-authenticated original issued association.
    /// Receipt scope, donor authority and complete mutation proof remain external.
    public static func prepareRetainedReviewedRecoveryWitness(_ evidence: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: evidence)
        return try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "prepareRetainedReviewedRecoveryWitness", arguments: [object])
    }
    /// Bounded imported archive IDs only; no donor authorship authority.
    public static func reviewedRecoverySourceSelection(_ evidence: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: evidence)
        return try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "reviewedRecoverySourceSelection", arguments: [object])
    }
    /// Map already-authenticated human archive IDs through recomputed regions.
    public static func mapReviewedRecoverySelection(_ evidence: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: evidence)
        return try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "mapReviewedRecoverySelection", arguments: [object])
    }
    /// Read-only plan from host-authenticated complete actor/owner cuts and reviewed associations.
    /// This result is not source or erasure authority; authenticate the complete persisted sidecar.
    public static func planReviewedRecoveryRetirement(_ evidence: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: evidence)
        return try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "planReviewedRecoveryRetirement", arguments: [object])
    }

    /// Trusted receipt replay and complete-group retirement. This issues no
    /// erasure authority and does not change retained source classification.
    public static func retireOwnedHistoryCheckpoint(_ evidence: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: evidence)
        return try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "retireOwnedHistoryCheckpoint", arguments: [object])
    }
    public static func buildWitness(_ evidence: Data) throws -> Data {
        let object=try JSONSerialization.jsonObject(with:evidence)
        return try RelayMarkPortableRuntime.call(resource:"content-edit-runtime",global:"RelayMarkContentEditRuntime",operation:"buildContentEditWitness",arguments:[object])
    }
}
