import Foundation

/// Stateless calls into the packaged content-edit runtime: HTML and clipboard
/// import, attribute codecs and the ProseMirror-to-Yjs write plan.
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
        if !settingsPolicy.nodes.contains(nodeName) { return try unrelated(attributes).filter { !($0.value is NSNull) } }
        return try documentAttributes(operation: "encodeDocumentAttributes", nodeName: nodeName, attributes: attributes)
    }
    public static func decodeDocumentAttributes(nodeName: String, attributes: [String: Any]) throws -> [String: Any] {
        if !settingsPolicy.nodes.contains(nodeName) { return try unrelated(attributes) }
        return try documentAttributes(operation: "decodeDocumentAttributes", nodeName: nodeName, attributes: attributes)
    }

    /// spec/relaymark/xml-attribute-encoding.json: only these nodes carry
    /// encoded settings fields. Every other node's attributes pass through as
    /// the shared codec passes them, so a block's attributes need no runtime call.
    static let settingsPolicy = (nodes: Set(["questionBlock", "questionOption"]), attribute: "settings", prefix: "settings:")

    /// The shared codec's check for a node without settings: no settings fields.
    private static func unrelated(_ attributes: [String: Any]) throws -> [String: Any] {
        guard attributes[settingsPolicy.attribute] == nil,
              !attributes.keys.contains(where: { $0.hasPrefix(settingsPolicy.prefix) }) else {
            throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument
        }
        return attributes
    }
    private static func documentAttributes(operation: String, nodeName: String, attributes: [String: Any]) throws -> [String: Any] {
        let result = try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime",
            operation: operation, arguments: [nodeName, attributes])
        guard let value = try JSONSerialization.jsonObject(with: result) as? [String: Any] else {
            throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument
        }
        return value
    }


    public static func command(document: Data, request: Data) throws -> Data {
        try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "createContentEditCommand", arguments: [JSONSerialization.jsonObject(with: document), JSONSerialization.jsonObject(with: request)])
    }
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

}
