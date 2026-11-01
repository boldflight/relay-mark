import Foundation
import Testing
@testable import RelayMarkSwift
struct RelayMarkContractTests {
    @Test func unversionedASTAndOldNumberCollision() throws {
        #expect(RelayMarkContract.version == 1)
        #expect(RelayMarkContract.schema == "relaymark-prosemirror")
        #expect(RelayMarkContract.sourceContract == "relaymark_ast")
        let source = Data(#"{"type":"relaymark.document","blocks":[]}"#.utf8)
        let ast = try RelayMarkDocument.decodeJSON(source)
        #expect(ast.blocks.isEmpty)
        #expect(throws: (any Error).self) {
            try RelayMarkDocument.decodeJSON(Data(#"{"type":"relaymark.document","version":1,"blocks":[]}"#.utf8))
        }
    }
}

/// Blocks without settings skip the engine; the shared codec must agree.
struct RelayMarkAttributeCodecConformanceTests {
    private func shared(_ operation: String, _ name: String, _ attributes: [String: Any]) -> [String: Any]? {
        let job = operation == "encodeDocumentAttributes" ? "encode_attributes" : "decode_attributes"
        return (try? RelayMarkEngineCall.run(job, RelayMarkEngineCall.json(attributes), options: ["name": name]))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    @Test func settingsNodesMatchTheSpec() throws {
        let spec = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../spec/relaymark/xml-attribute-encoding.json")
        let policy = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: spec)) as? [String: Any])
        #expect(Set(policy["nodes"] as? [String] ?? []) == RelayMarkContentEditCodec.settingsPolicy.nodes)
        #expect(policy["logical_attribute"] as? String == RelayMarkContentEditCodec.settingsPolicy.attribute)
    }

    @Test(arguments: [
        #"{"relaymarkId":"b1","level":2,"headingId":null}"#,
        #"{"colspan":2,"colwidth":[120,80],"align":"center"}"#,
        #"{"relaymarkId":"b2","settings:eA":true}"#,
        #"{"settings":{"a":1}}"#,
    ])
    func nativeAttributesMatchTheSharedCodec(json: String) throws {
        let attributes = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        for (operation, native) in [("encodeDocumentAttributes", RelayMarkContentEditCodec.encodeDocumentAttributes),
                                    ("decodeDocumentAttributes", RelayMarkContentEditCodec.decodeDocumentAttributes)] {
            let expected = shared(operation, "heading", attributes)
            let actual = try? native("heading", attributes)
            #expect((expected == nil) == (actual == nil), "\(operation)")
            if let expected, let actual { #expect(NSDictionary(dictionary: expected) == NSDictionary(dictionary: actual), "\(operation)") }
        }
    }
}

/// The web editor's stock @tiptap/y-tiptap writes a question's settings as one object attribute
/// (spec/relaymark/editor/y-tiptap-settings-v1.json, generated from it). Swift must write the same
/// attributes, and shares the aggregate cases that refuse per-key input.
struct RelayMarkSettingsAttributeFixtureTests {
    private func cases(_ name: String) throws -> [[String: Any]] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../spec/relaymark/editor/\(name)")
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try #require(fixture["cases"] as? [[String: Any]])
    }

    @Test func encodeMatchesWhatStockYTiptapWrites() throws {
        let all = try cases("y-tiptap-settings-v1.json")
        #expect(all.count == 6)
        for item in all {
            let node = try #require((item["options"] as? [String: Any])?["name"] as? String)
            let encoded = try RelayMarkContentEditCodec.encodeDocumentAttributes(nodeName: node, attributes: try #require(item["input"] as? [String: Any]))
            #expect(NSDictionary(dictionary: encoded) == NSDictionary(dictionary: try #require(item["expected"] as? [String: Any])), "\(item["name"] ?? "")")
            #expect(!encoded.keys.contains { $0.hasPrefix("settings:") })
        }
    }

    @Test func sharedSettingsCasesHold() throws {
        for item in try cases("settings-attributes-v1.json") {
            let node = try #require((item["options"] as? [String: Any])?["name"] as? String)
            let input = try #require(item["input"] as? [String: Any])
            let encode = item["job"] as? String == "encode_attributes"
            let run = { try encode ? RelayMarkContentEditCodec.encodeDocumentAttributes(nodeName: node, attributes: input)
                                   : RelayMarkContentEditCodec.decodeDocumentAttributes(nodeName: node, attributes: input) }
            if item["expected_error"] != nil {
                #expect(throws: (any Error).self, "\(item["name"] ?? "")") { _ = try run() }
            } else {
                #expect(NSDictionary(dictionary: try run()) == NSDictionary(dictionary: try #require(item["expected"] as? [String: Any])), "\(item["name"] ?? "")")
            }
        }
    }
}

/// The shared descriptor-admission cases every runtime runs.
struct RelayMarkDescriptorAdmissionTests {
    @Test func sharedCases() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../spec/relaymark/editor/descriptor-admission-v1.json")
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try #require(fixture["cases"] as? [[String: Any]])
        #expect(!cases.isEmpty)
        for item in cases {
            let input = try JSONSerialization.data(withJSONObject: item["input"] ?? NSNull(), options: [.fragmentsAllowed])
            let refused = item["expected_error"] != nil
            do { try RelayMarkContract.admit(descriptor: input); #expect(!refused, "\(item["name"] ?? "")") }
            catch { #expect(refused, "\(item["name"] ?? "")") }
        }
    }
}
