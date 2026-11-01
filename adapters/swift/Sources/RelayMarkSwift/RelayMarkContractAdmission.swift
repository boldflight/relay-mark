import Foundation

extension RelayMarkContract {
    /// Admits a stored or received document descriptor only when it is exactly this engine's
    /// canonical contract (version, schema, source contract and physical schema hash). Any other
    /// descriptor, such as a document that predates the physical schema hash or one written under
    /// another attribute encoding, is refused so the host recovers through its existing path
    /// instead of reading it.
    public static func admit(descriptor: Data) throws {
        _ = try RelayMarkEngineCall.run("admit_descriptor", descriptor)
    }
}
