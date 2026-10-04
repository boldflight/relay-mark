import Foundation

/// The packaged maintained StepMap/identity witness owner. This stateless
/// preparation confers neither accepted receipt scope nor source authority.
public enum RelayMarkContentEditCodec {
    public static func buildWitness(_ evidence: Data) throws -> Data {
        let object=try JSONSerialization.jsonObject(with:evidence)
        return try RelayMarkPortableRuntime.call(resource:"content-edit-runtime",global:"RelayMarkContentEditRuntime",operation:"buildContentEditWitness",arguments:[object])
    }
}
