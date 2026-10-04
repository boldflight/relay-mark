import Foundation
import JavaScriptCore

/// The same packaged portable source/AST grammar used by browser clients.
/// This runtime owns no Yjs document, undo manager, transport or host domain actions.
public enum RelayMarkSourceCodec {
    public enum Failure: Error { case unavailable, invalidInput, invalidAuthoredDocument }
    public static func parseDocument(_ source: String, namespace: String) throws -> Data {
        try call("parseDocument",arguments:[source,["namespace":namespace]])
    }
    public static func serializeDocument(_ document: Data) throws -> String {
        try text("serializeDocument",document:document)
    }
    public static func projectDocumentMarkdown(_ document: Data) throws -> String {
        try text("projectDocumentMarkdown",document:document)
    }
    public static func renderDocument(_ document: Data) throws -> String {
        try text("renderDocument",document:document)
    }
    public static func importDocument(_ original: Data, namespace: String) throws -> Data {
        try call("importDocument",arguments:[json(original),["namespace":namespace]])
    }
    public static func documentToSnapshot(_ document: Data) throws -> Data {
        try call("documentToSnapshot",arguments:[json(document)])
    }
    public static func snapshotToDocument(_ snapshot: Data) throws -> Data {
        try call("snapshotToDocument",arguments:[json(snapshot)])
    }
    private static func json(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed)
    }
    private static func text(_ name: String, document: Data) throws -> String {
        let data = try call(name,arguments:[json(document)])
        guard let value = try json(data) as? String else { throw Failure.invalidAuthoredDocument }
        return value
    }
    private static func call(_ name: String, arguments: [Any]) throws -> Data {
        guard let path = Bundle.module.url(forResource:"document-source",withExtension:"js"),
              let context = JSContext() else { throw Failure.unavailable }
        let script = try String(contentsOf:path,encoding:.utf8)
        context.evaluateScript(script)
        guard context.exception == nil else { throw Failure.unavailable }
        context.setObject(name,forKeyedSubscript:"relayMarkOperation" as NSString)
        context.setObject(arguments,forKeyedSubscript:"relayMarkArguments" as NSString)
        guard let result = context.evaluateScript("JSON.stringify(RelayMarkSourceRuntime[relayMarkOperation](...relayMarkArguments))"),
              context.exception == nil,let encoded = result.toString(),let data = encoded.data(using:.utf8) else { throw Failure.invalidAuthoredDocument }
        return data
    }
}
