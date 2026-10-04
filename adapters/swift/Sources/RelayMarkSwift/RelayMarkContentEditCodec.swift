import Foundation

/// The packaged maintained StepMap/identity witness owner. This stateless
/// preparation confers neither accepted receipt scope nor source authority.
public enum RelayMarkContentEditCodec {
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
