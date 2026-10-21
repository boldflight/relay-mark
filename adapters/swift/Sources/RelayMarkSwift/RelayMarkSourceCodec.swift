import Foundation
import JavaScriptCore
import RelayMarkEngine

/// The canonical RelayMark engine (relaymark-core), the same conversions the
/// server and the web use. It owns no Yjs document, undo manager, transport or
/// host domain action.
public enum RelayMarkSourceCodec {
    public enum Failure: Error, Equatable { case unavailable, invalidInput, invalidAuthoredDocument }
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
        try RelayMarkEngineCall.run("from_snapshot", snapshot)
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
        catch { throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument }
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
    static func json(_ value: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(value) else { throw RelayMarkSourceCodec.Failure.invalidInput }
        return try JSONSerialization.data(withJSONObject: value)
    }
}

/// Synchronous stateless package calls share one thread-confined context per
/// shipped resource. No context crosses threads or owns a live editor replica.
enum RelayMarkPortableRuntime {
    /// JavaScriptCore keeps the heap a context grew to until the context is
    /// released, so a call this large retires its context once calls pause; the
    /// next call starts a fresh one. On the main thread, where editing can make
    /// several in a row, that is after `mainThreadIdle` without another call;
    /// on any other thread it is at once.
    static let retainedLimit = 256 * 1024
    static let mainThreadIdle: TimeInterval = 1

    private static func retire(_ key: String, unlessCalledAfter calls: Int) {
        guard Thread.isMainThread else { Thread.current.threadDictionary.removeObject(forKey: key); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + mainThreadIdle) {
            let retained = Thread.main.threadDictionary
            guard retained[key + ".calls"] as? Int == calls else { return }
            retained.removeObject(forKey: key)
        }
    }

    static func call(resource: String, global: String, operation: String, arguments: [Any]) throws -> Data {
        let key="relaymark.canonical.portable."+resource
        // Releases the call's bridged values, and a retired context, before returning.
        return try autoreleasepool {
            let context:JSContext
            if let retained=Thread.current.threadDictionary[key] as? JSContext {context=retained}
            else {
                guard let path=Bundle.module.url(forResource:resource,withExtension:"js"),
                      let script=try? String(contentsOf:path,encoding:.utf8),let fresh=JSContext() else {throw RelayMarkSourceCodec.Failure.unavailable}
                fresh.evaluateScript(script)
                guard fresh.exception==nil else {throw RelayMarkSourceCodec.Failure.unavailable}
                Thread.current.threadDictionary[key]=fresh;context=fresh
            }
            var large = arguments.contains { ($0 as? String).map { $0.utf8.count > retainedLimit } ?? false }
            defer {
                // The arguments stay reachable from the global object until cleared.
                for name in ["relayMarkRuntimeGlobal", "relayMarkRuntimeOperation", "relayMarkRuntimeArguments"] {
                    context.setObject(JSValue(undefinedIn: context), forKeyedSubscript: name as NSString)
                }
                let calls = ((Thread.current.threadDictionary[key + ".calls"] as? Int) ?? 0) &+ 1
                Thread.current.threadDictionary[key + ".calls"] = calls
                if large { retire(key, unlessCalledAfter: calls) }
            }
            context.exception=nil
            context.setObject(global,forKeyedSubscript:"relayMarkRuntimeGlobal" as NSString)
            context.setObject(operation,forKeyedSubscript:"relayMarkRuntimeOperation" as NSString)
            context.setObject(arguments,forKeyedSubscript:"relayMarkRuntimeArguments" as NSString)
            let result=context.evaluateScript("JSON.stringify(globalThis[relayMarkRuntimeGlobal][relayMarkRuntimeOperation](...relayMarkRuntimeArguments))")
            if context.exception != nil {
                throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument
            }
            guard let encoded=result?.toString(),let data=encoded.data(using:.utf8) else {throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument}
            if data.count > retainedLimit { large = true }
            return data
        }
    }
}
