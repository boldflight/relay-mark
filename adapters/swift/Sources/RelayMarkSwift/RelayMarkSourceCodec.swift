import Foundation
import RelayMarkEngine

/// The canonical RelayMark engine (relaymark-core), the same conversions the
/// server and the web use. It owns no Yjs document, undo manager, transport or
/// host domain action.
public enum RelayMarkSourceCodec {
    public enum Failure: Error, Equatable {
        case unavailable, invalidInput, invalidAuthoredDocument
        /// The engine refused a job, in its own words: the job name and the reason it gave. A host logs the
        /// reflected error and shows its own copy; the engine's wording is never user-facing.
        case engineRefused(job: String, reason: String)
    }
    public static func parseDocument(_ source: String, namespace: String) throws -> Data {
        try RelayMarkEngineCall.run("parse", text: source, options: ["namespace": namespace])
    }
    public static func serializeDocument(_ document: Data) throws -> String {
        try RelayMarkEngineCall.text("serialize", document)
    }
    public static func projectDocumentMarkdown(_ document: Data) throws -> String {
        try RelayMarkEngineCall.text("markdown", document)
    }
    public static func renderDocument(_ document: Data) throws -> String {
        try RelayMarkEngineCall.text("html", document)
    }
    /// Canonical authored PM block ordinals, never hydrated labels or XML offsets.
    /// Duplicate explicit Anchor names remain ambiguous and require a unique match.
    public static func paperDocumentDestinations(document: Data) throws -> Data {
        try RelayMarkEngineCall.run("paper_destinations", document)
    }
    public static func importDocument(_ original: Data, namespace: String) throws -> Data {
        try RelayMarkEngineCall.run("import_document", original, options: ["namespace": namespace])
    }
    public static func importSource(_ source: String, namespace: String) throws -> Data {
        try RelayMarkEngineCall.run("import_source", text: source, options: ["namespace": namespace])
    }
    public static func importDocumentSnapshot(_ original: Data, namespace: String) throws -> Data {
        try RelayMarkEngineCall.run("import_snapshot", original, options: ["namespace": namespace])
    }
    public static func documentToSnapshot(_ document: Data) throws -> Data {
        try RelayMarkEngineCall.run("to_snapshot", document)
    }
    public static func snapshotToDocument(_ snapshot: Data) throws -> Data {
        do { return try RelayMarkEngineCall.run("from_snapshot", snapshot) }
        catch {
            // A collaboration document whose form settings are one aggregate attribute (the server's
            // current encoding) is not the physical per-key encoding from_snapshot reads. The engine
            // projects it without touching the live document; any other refusal stays the first one.
            guard let preview = try? RelayMarkEngineCall.run("aggregate_settings", snapshot),
                  let decoded = try? JSONSerialization.jsonObject(with: preview) as? [String: Any],
                  let document = decoded["document"],
                  let bytes = try? JSONSerialization.data(withJSONObject: document, options: [.fragmentsAllowed]) else { throw error }
            return bytes
        }
    }
    public static func buildEntityReferenceSource(entityType: String, entityID: String, label: String) throws -> String {
        try RelayMarkEngineCall.text("entity_reference_source", Data(), options: ["type": entityType, "id": entityID, "label": label])
    }
    public static func isSafeImageSource(_ source: String) throws -> Bool {
        try RelayMarkEngineCall.run("safe_image_source", text: source) == Data("true".utf8)
    }
    public static func validateTextAttributes(_ attributes: [String:Any]) throws {
        _ = try RelayMarkEngineCall.run("text_attributes", RelayMarkEngineCall.json(attributes))
    }
    public static func directiveDefinitions() throws -> Data { try RelayMarkEngineCall.run("directive_definitions", Data()) }
}

/// One call into relaymark-core: input bytes and JSON options in, result bytes
/// out. A refusal is an invalid authored document, as the engine reports it.
enum RelayMarkEngineCall {
    static func run(_ job: String, _ input: Data, options: [String: Any] = [:]) throws -> Data {
        let encoded = options.isEmpty ? Data() : try json(options)
        do { return try relaymarkRun(job: job, input: input, options: encoded) }
        catch {
            // The engine's refusal names the job and its reason; the generated error type is
            // internal to the engine module, so its description is the reason we can keep.
            let reason = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            throw RelayMarkSourceCodec.Failure.engineRefused(job: job, reason: reason)
        }
    }
    static func run(_ job: String, text: String, options: [String: Any] = [:]) throws -> Data {
        try run(job, Data(text.utf8), options: options)
    }
    static func text(_ job: String, _ input: Data, options: [String: Any] = [:]) throws -> String {
        guard let text = String(data: try run(job, input, options: options), encoding: .utf8) else {
            throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument
        }
        return text
    }
    /// A JSON array of already encoded JSON values, without re-encoding them.
    static func array(_ items: [Data]) -> Data {
        var out = Data("[".utf8)
        for (index, item) in items.enumerated() {
            if index > 0 { out.append(UInt8(ascii: ",")) }
            out.append(item)
        }
        out.append(UInt8(ascii: "]"))
        return out
    }
    /// The encoded elements of a JSON array.
    static func elements(_ array: Data) throws -> [Data] {
        guard let items = try JSONSerialization.jsonObject(with: array) as? [Any] else { throw RelayMarkSourceCodec.Failure.invalidInput }
        return try items.map { try JSONSerialization.data(withJSONObject: $0, options: .fragmentsAllowed) }
    }
    static func json(_ value: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(value) else { throw RelayMarkSourceCodec.Failure.invalidInput }
        return try JSONSerialization.data(withJSONObject: value)
    }
}
