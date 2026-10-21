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
        #expect(policy["field_prefix"] as? String == RelayMarkContentEditCodec.settingsPolicy.prefix)
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
