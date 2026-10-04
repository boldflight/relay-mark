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
    public static func importSource(_ source: String, namespace: String) throws -> Data {
        try call("importDocumentSource",arguments:[source,["namespace":namespace]])
    }
    public static func importDocumentSnapshot(_ original: Data, namespace: String) throws -> Data {
        try call("importDocumentSnapshot",arguments:[json(original),["namespace":namespace]])
    }
    public static func documentToSnapshot(_ document: Data) throws -> Data {
        try call("documentToSnapshot",arguments:[json(document)])
    }
    public static func snapshotToDocument(_ snapshot: Data) throws -> Data {
        try call("snapshotToDocument",arguments:[json(snapshot)])
    }
    public static func buildEntityReferenceSource(entityType: String, entityID: String, label: String) throws -> String {
        let data=try call("buildEntityReferenceSource",arguments:[["entityType":entityType,"entityId":entityID,"label":label]])
        guard let value=try json(data) as? String else { throw Failure.invalidAuthoredDocument }
        return value
    }
    public static func isSafeImageSource(_ source: String) throws -> Bool {
        let data=try call("safeImageSource",arguments:[source])
        guard let value=try json(data) as? Bool else { throw Failure.invalidAuthoredDocument }
        return value
    }
    public static func validateTextAttributes(_ attributes: [String:Any]) throws {
        guard try json(call("validateTextAttributes",arguments:[attributes])) as? Bool == true else { throw Failure.invalidAuthoredDocument }
    }
    /// Stateless classification of host-authenticated current receipts. Neither
    /// these JSON inputs nor its result grants source or document authority.
    public static func classifyContentEditReference(binding: Data, transaction: Data, proof: Data, humanAncestry: Data) throws -> Data {
        try call("classifyContentEditReference",arguments:[json(binding),json(transaction),json(proof),json(humanAncestry)])
    }
    public static func foldSourceReferences(binding: Data, candidateSelector: Data, references: Data) throws -> Data {
        try call("foldSourceReferences",arguments:[json(binding),json(candidateSelector),json(references)])
    }
    public static func directiveDefinitions() throws -> Data { try call("editorDirectiveDefinitions",arguments:[]) }
    private static func json(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed)
    }
    private static func text(_ name: String, document: Data) throws -> String {
        let data = try call(name,arguments:[json(document)])
        guard let value = try json(data) as? String else { throw Failure.invalidAuthoredDocument }
        return value
    }
    private static func call(_ name: String, arguments: [Any]) throws -> Data {
        try RelayMarkPortableRuntime.call(resource:"document-source",global:"RelayMarkSourceRuntime",operation:name,arguments:arguments)
    }
}

/// Synchronous stateless package calls share one thread-confined context per
/// shipped resource. No context crosses threads or owns a live editor replica.
enum RelayMarkPortableRuntime {
    static func call(resource: String, global: String, operation: String, arguments: [Any]) throws -> Data {
        let key="relaymark.canonical.portable."+resource
        let context:JSContext
        if let retained=Thread.current.threadDictionary[key] as? JSContext {context=retained}
        else {
            guard let path=Bundle.module.url(forResource:resource,withExtension:"js"),
                  let script=try? String(contentsOf:path,encoding:.utf8),let fresh=JSContext() else {throw RelayMarkSourceCodec.Failure.unavailable}
            fresh.evaluateScript(script)
            guard fresh.exception==nil else {throw RelayMarkSourceCodec.Failure.unavailable}
            Thread.current.threadDictionary[key]=fresh;context=fresh
        }
        context.exception=nil
        context.setObject(global,forKeyedSubscript:"relayMarkRuntimeGlobal" as NSString)
        context.setObject(operation,forKeyedSubscript:"relayMarkRuntimeOperation" as NSString)
        context.setObject(arguments,forKeyedSubscript:"relayMarkRuntimeArguments" as NSString)
        guard let result=context.evaluateScript("JSON.stringify(globalThis[relayMarkRuntimeGlobal][relayMarkRuntimeOperation](...relayMarkRuntimeArguments))"),
              context.exception==nil,let encoded=result.toString(),let data=encoded.data(using:.utf8) else {throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument}
        return data
    }
}
