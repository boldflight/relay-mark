import Foundation
import Testing
@testable import RelayMarkSwift

@Suite("Shared structured HTML conversion")
struct RelayMarkHTMLImportTests {
    @Test("HTML preserves heading, list, table, callout and marked Unicode instead of flattening them")
    func structuredHTMLPreservesIndependentSemantics() throws {
        let html = "<h2>Résumé <strong>世界</strong></h2><ul><li><p>First</p></li></ul><table><tr><td><p>Cell</p></td></tr></table><aside data-relay-callout=\"info\"><p>Keep this</p></aside>"
        let data = try RelayMarkContentEditCodec.importDocumentHTML(html, namespace: "clipboard-semantic-proof")
        let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let snapshot = try #require(result["snapshot"] as? [String: Any])
        let nodes = try #require(snapshot["children"] as? [[String: Any]])
        #expect(nodes.compactMap { $0["name"] as? String } == ["heading", "bulletList", "table", "callout"])
        let heading = try #require(nodes[0]["attributes"] as? [String: Any])
        #expect(heading["level"] as? Int == 2)
        let callout = try #require(nodes[3]["attributes"] as? [String: Any])
        #expect(callout["tone"] as? String == "info")
        let document = try #require(result["document"] as? [String: Any])
        let encoded = try JSONSerialization.data(withJSONObject: document)
        let rendered = try RelayMarkSourceCodec.renderDocument(encoded)
        #expect(rendered.contains("Résumé <strong>世界</strong>"))
        #expect(rendered.contains("<ul>"))
        #expect(rendered.contains("<table>"))
        #expect(rendered.contains("Keep this"))
        #expect(document["version"] == nil)
    }

    @Test("Unknown HTML semantics are refused instead of silently stripping authored input")
    func unknownHTMLSemanticsRefused() throws {
        #expect(throws: (any Error).self) {
            try RelayMarkContentEditCodec.importDocumentHTML("<p onclick=\"steal()\">Keep me</p>", namespace: "clipboard-refusal-proof")
        }
        #expect(throws: (any Error).self) {
            try RelayMarkContentEditCodec.importDocumentHTML("<unknown-authored>Keep me</unknown-authored>", namespace: "clipboard-refusal-proof")
        }
    }
}
