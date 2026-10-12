import Foundation

/// The packaged maintained StepMap/identity witness owner. This stateless
/// preparation confers neither accepted receipt scope nor source authority.
public enum RelayMarkContentEditCodec {
    /// Pure canonical HTML conversion through the packaged shared DOM/PM
    /// grammar. The returned document grants no source, media or edit authority.
    /// Hosts must fence the captured paste and authorize references before using
    /// this material in their existing document transaction.
    public static func importDocumentHTML(_ html: String, namespace: String) throws -> Data {
        try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime",
            operation: "importDocumentHTML", arguments: [["html": html, "namespace": namespace]])
    }

    /// Logical PM attributes and physical XML fields share the browser codec.
    /// This is stateless grammar conversion, with no source or edit authority.
    public static func encodeDocumentAttributes(nodeName: String, attributes: [String: Any]) throws -> [String: Any] {
        try documentAttributes(operation: "encodeDocumentAttributes", nodeName: nodeName, attributes: attributes)
    }
    public static func decodeDocumentAttributes(nodeName: String, attributes: [String: Any]) throws -> [String: Any] {
        try documentAttributes(operation: "decodeDocumentAttributes", nodeName: nodeName, attributes: attributes)
    }
    private static func documentAttributes(operation: String, nodeName: String, attributes: [String: Any]) throws -> [String: Any] {
        let result = try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime",
            operation: operation, arguments: [nodeName, attributes])
        guard let value = try JSONSerialization.jsonObject(with: result) as? [String: Any] else {
            throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument
        }
        return value
    }

    /// Finite detached aggregate-settings archive conversion. This invokes the
    /// existing grammar owner and grants no live schema or donor authority.
    public static func importAggregateSettingsSnapshot(_ snapshot: Data) throws -> Data {
        try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime",
            operation: "importAggregateSettingsSnapshot", arguments: [JSONSerialization.jsonObject(with: snapshot)])
    }

    /// Candidate-bounded subtraction of host-authenticated typed masks. This
    /// pure operation grants no authorship or erasure authority.
    public static func subtractSourceSelectors(candidates: Data, excluding: Data) throws -> Data {
        try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "subtractSourceSelectors", arguments: [JSONSerialization.jsonObject(with: candidates), JSONSerialization.jsonObject(with: excluding)])
    }
    public static func command(document: Data, request: Data) throws -> Data {
        try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "createContentEditCommand", arguments: [JSONSerialization.jsonObject(with: document), JSONSerialization.jsonObject(with: request)])
    }
    /// Original source ordinals resolve internal navigation before the existing
    /// writer commits. This pure plan confers no archive or donor authority.
    public static func planReviewedAnchorAllocation(_ evidence: Data) throws -> Data {
        try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "planReviewedAnchorAllocation", arguments: [JSONSerialization.jsonObject(with: evidence)])
    }
    public static func planReviewedHeadingNavigation(_ evidence: Data) throws -> Data {
        try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "planReviewedHeadingNavigation", arguments: [JSONSerialization.jsonObject(with: evidence)])
    }
    /// Pure clipboard repair; confers no reviewed-history or host authority.
    /// Pure clipboard Slice parser; returned context grants no host authority.
    public static func importClipboardHTML(_ html: String, namespace: String) throws -> Data {
        try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime",
            operation: "importClipboardHTML", arguments: [["html": html, "namespace": namespace]])
    }
    public static func planClipboardAnchorAllocation(_ evidence: Data) throws -> Data {
        try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "planClipboardAnchorAllocation", arguments: [JSONSerialization.jsonObject(with: evidence)])
    }
    public static func planClipboardHeadingNavigation(_ evidence: Data) throws -> Data {
        try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "planClipboardHeadingNavigation", arguments: [JSONSerialization.jsonObject(with: evidence)])
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
