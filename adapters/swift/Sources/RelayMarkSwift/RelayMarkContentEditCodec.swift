import Foundation

/// The native editing runtime in relaymark-core: HTML and clipboard import,
/// the attribute codecs, maintained editor commands, clipboard navigation
/// plans and the ProseMirror-to-Yjs write plan.
public enum RelayMarkContentEditCodec {
    /// Pure canonical HTML conversion through the packaged shared DOM/PM
    /// grammar. The returned document grants no source, media or edit authority.
    /// Hosts must fence the captured paste and authorize references before using
    /// this material in their existing document transaction.
    public static func importDocumentHTML(_ html: String, namespace: String) throws -> Data {
        try RelayMarkEngineCall.run("import_html", text: html, options: ["namespace": namespace])
    }

    /// Logical PM attributes and physical XML fields share the browser codec.
    /// This is stateless grammar conversion, with no source or edit authority.
    public static func encodeDocumentAttributes(nodeName: String, attributes: [String: Any]) throws -> [String: Any] {
        if !settingsPolicy.nodes.contains(nodeName) { return try unrelated(attributes).filter { !($0.value is NSNull) } }
        return try documentAttributes(operation: "encodeDocumentAttributes", nodeName: nodeName, attributes: attributes)
    }
    public static func decodeDocumentAttributes(nodeName: String, attributes: [String: Any]) throws -> [String: Any] {
        if !settingsPolicy.nodes.contains(nodeName) { return try unrelated(attributes) }
        if isAggregate(attributes) { return attributes }
        return try documentAttributes(operation: "decodeDocumentAttributes", nodeName: nodeName, attributes: attributes)
    }

    /// The server's current form encoding keeps a node's settings as one `settings` object, which
    /// already is the authored shape: no presence marker and no per-key physical fields. It reads
    /// as it is; writing still goes through the physical encoding, so a native edit of a question
    /// node's own attributes is refused by the engine rather than mixed into an aggregate document.
    static func isAggregate(_ attributes: [String: Any]) -> Bool {
        attributes[settingsPolicy.attribute] is [String: Any]
            && !attributes.keys.contains(where: { $0.hasPrefix(settingsPolicy.prefix) })
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
        let job = operation == "encodeDocumentAttributes" ? "encode_attributes" : "decode_attributes"
        let result = try RelayMarkEngineCall.run(job, RelayMarkEngineCall.json(attributes), options: ["name": nodeName])
        guard let value = try JSONSerialization.jsonObject(with: result) as? [String: Any] else {
            throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument
        }
        return value
    }


    public static func command(document: Data, request: Data) throws -> Data {
        try RelayMarkEngineCall.run("edit_command", RelayMarkEngineCall.array([document, request]))
    }

    /// The typed Markdown shortcut `{selection, text}` completes in `document`,
    /// in the command evidence shape plus `rule`, or JSON null when none does.
    public static func inputRule(document: Data, request: Data) throws -> Data {
        try RelayMarkEngineCall.run("edit_input_rule", RelayMarkEngineCall.array([document, request]))
    }

    /// The characters a typed shortcut can end with; typing anything else completes none.
    public static let inputRuleTriggers: Set<Character> = {
        Set((try? RelayMarkEngineCall.text("input_rule_triggers", Data())) ?? "")
    }()

    /// Whether typing `text` after a block's `before` text could complete a shortcut.
    public static func inputRuleMatches(before: String, text: String) -> Bool {
        guard let request = try? RelayMarkEngineCall.json(["before": before, "text": text]),
              let answer = try? RelayMarkEngineCall.run("input_rule_matches", request) else { return false }
        return answer == Data("true".utf8)
    }
    /// Pure clipboard Slice parser; returned context grants no host authority.
    public static func importClipboardHTML(_ html: String, namespace: String) throws -> Data {
        try RelayMarkEngineCall.run("import_clipboard_html", text: html, options: ["namespace": namespace])
    }
    public static func planClipboardAnchorAllocation(_ evidence: Data) throws -> Data {
        try RelayMarkEngineCall.run("clipboard_anchors", evidence)
    }
    public static func planClipboardHeadingNavigation(_ evidence: Data) throws -> Data {
        try RelayMarkEngineCall.run("clipboard_headings", evidence)
    }

    public static func prepareWrite(before: Data, steps: Data, after: Data) throws -> Data {
        try RelayMarkEngineCall.run("edit_prepare_write", RelayMarkEngineCall.array([before, steps, after]))
    }
    public static func planTextWrite(prepared: Data, sourceParent: String, sourceGroup: Int, targetParent: String, targetGroup: Int, sourceOffset: Int, sourceLength: Int) throws -> Data {
        let rest = try RelayMarkEngineCall.json([sourceParent, sourceGroup, targetParent, targetGroup, ["offset": sourceOffset, "length": sourceLength]] as [Any])
        return try RelayMarkEngineCall.run("edit_plan_text_write", RelayMarkEngineCall.array([prepared] + RelayMarkEngineCall.elements(rest)))
    }
}
