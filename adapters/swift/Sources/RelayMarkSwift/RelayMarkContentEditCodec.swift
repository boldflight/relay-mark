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
    public static func buildWitness(_ evidence: Data) throws -> Data {
        let object=try JSONSerialization.jsonObject(with:evidence)
        return try RelayMarkPortableRuntime.call(resource:"content-edit-runtime",global:"RelayMarkContentEditRuntime",operation:"buildContentEditWitness",arguments:[object])
    }
}
