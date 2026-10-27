import Foundation
import Testing
@testable import RelayMarkSwift
struct RelayMarkSourceTests {
  @Test func canonicalSourceAndSnapshotRetainSharedRichFixture() throws {
    let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let fixture = try Data(contentsOf:root.appendingPathComponent("spec/relaymark/collaboration/fixtures/canonical-directives.json"))
    let snapshot = try RelayMarkSourceCodec.documentToSnapshot(fixture)
    let decoded = try RelayMarkSourceCodec.snapshotToDocument(snapshot)
    #expect(try JSONSerialization.jsonObject(with: decoded) as? NSDictionary == JSONSerialization.jsonObject(with: fixture) as? NSDictionary)
    let source = try RelayMarkSourceCodec.serializeDocument(fixture)
    let roundtrip = try RelayMarkSourceCodec.parseDocument(source, namespace:"swift-import")
    #expect(try JSONSerialization.jsonObject(with: roundtrip) as? NSDictionary == JSONSerialization.jsonObject(with: fixture) as? NSDictionary)
    let imported = try RelayMarkSourceCodec.parseDocument("# Title\n\n**Résumé 世界**",namespace:"unicode-cross-runtime")
    let object = try JSONSerialization.jsonObject(with: imported) as! [String:Any]
    #expect((object["blocks"] as! [[String:Any]]).count == 2)
    #expect(try RelayMarkSourceCodec.renderDocument(imported).contains("<strong>Résumé 世界</strong>"))
  }
  /// A form paper whose collaboration document keeps each question's settings as one aggregate
  /// `settings` attribute (the server's current encoding) still projects to its authored document.
  @Test func aggregateSettingsFormSnapshotProjectsToTheAuthoredDocument() throws {
    func header(_ pairs: [(String, String)]) -> String {
      pairs.sorted { $0.0 < $1.0 }.map { "\($0.0)=\"\($0.1.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;"))\"" }.joined(separator: " ")
    }
    func question(_ id: String, _ type: String, _ label: String, _ settings: String) -> String {
      "<!-- relay:question \(header([("id", id), ("type", type), ("required", "true"), ("settings", settings), ("options", "[]")])) -->\n\(label)\n<!-- /relay:question -->"
    }
    let source = "Upload one or more files.\n\n" + question("name", "short_text", "Your name", "{}") + "\n\n" + question("evidence", "file_upload", "Evidence files", "{\"max_files\":3}")
    let authored = try RelayMarkSourceCodec.parseDocument(source, namespace: "aggregate-form")
    let physical = try RelayMarkSourceCodec.documentToSnapshot(authored)
    // The aggregate encoding: one `settings` object per question node, no per-key physical fields.
    func aggregate(_ node: Any) -> Any {
      guard var element = node as? [String: Any], element["kind"] as? String == "element" else { return node }
      if var attributes = element["attributes"] as? [String: Any], element["name"] as? String == "questionBlock" || element["name"] as? String == "questionOption" {
        var settings: [String: Any] = [:]
        for key in Array(attributes.keys) where key.hasPrefix("settings:") {
          let encoded = String(key.dropFirst("settings:".count)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
          let padded = encoded + String(repeating: "=", count: (4 - encoded.count % 4) % 4)
          if let data = Data(base64Encoded: padded), let name = String(data: data, encoding: .utf8) { settings[name] = attributes[key] }
          attributes.removeValue(forKey: key)
        }
        attributes["settings"] = settings
        element["attributes"] = attributes
      }
      if let children = element["children"] as? [Any] { element["children"] = children.map(aggregate) }
      return element
    }
    var tree = try #require(JSONSerialization.jsonObject(with: physical) as? [String: Any])
    tree["children"] = (try #require(tree["children"] as? [Any])).map(aggregate)
    let aggregateSnapshot = try JSONSerialization.data(withJSONObject: tree)
    let projected = try RelayMarkSourceCodec.snapshotToDocument(aggregateSnapshot)
    #expect(try JSONSerialization.jsonObject(with: projected) as? NSDictionary == JSONSerialization.jsonObject(with: authored) as? NSDictionary)
  }
  /// A question node whose settings are one aggregate object reads as its authored attributes; a node that
  /// mixes the aggregate with per-key physical fields is still refused, never merged.
  @Test func aggregateQuestionSettingsReadAsAuthoredAttributes() throws {
    let aggregate: [String: Any] = ["relaymarkId": "b2", "id": "evidence", "required": true, "settings": ["max_files": 3]]
    let decoded = try RelayMarkContentEditCodec.decodeDocumentAttributes(nodeName: "questionBlock", attributes: aggregate)
    #expect(NSDictionary(dictionary: decoded) == NSDictionary(dictionary: aggregate))
    let option = try RelayMarkContentEditCodec.decodeDocumentAttributes(nodeName: "questionOption", attributes: ["relaymarkId": "o1", "settings": [String: Any]()])
    #expect(option["settings"] as? [String: Any] != nil)
    #expect(throws: (any Error).self) {
      _ = try RelayMarkContentEditCodec.decodeDocumentAttributes(nodeName: "questionBlock", attributes: ["relaymarkId": "b2", "settings": ["a": 1], "settings:eA": true])
    }
  }
  @Test func retainedEmptyCalloutSourceUsesCanonicalBodyAcrossRuntimes() throws {
    let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf:root.appendingPathComponent("spec/relaymark/collaboration/fixtures/canonical-empty-callout-source.json"))
    let fixture = try JSONSerialization.jsonObject(with:data) as! [String:Any]
    for item in fixture["cases"] as! [[String:Any]] {
      let source = item["source"] as! String
      let imported = try JSONSerialization.jsonObject(with:RelayMarkSourceCodec.importSource(source,namespace:fixture["namespace"] as! String)) as! [String:Any]
      #expect(imported["document"] as? NSDictionary == item["expected_ast"] as? NSDictionary)
      let document = try JSONSerialization.data(withJSONObject:imported["document"]!)
      let exact = try RelayMarkSourceCodec.serializeDocument(document)
      #expect(try JSONSerialization.jsonObject(with:RelayMarkSourceCodec.parseDocument(exact, namespace: "empty-callout-roundtrip")) as? NSDictionary == item["expected_ast"] as? NSDictionary)
    }
  }

  @Test func historicalExactSourceUsesFiniteSharedMigrationWithoutLiveCompatibility() throws {
    let source="```relaymark-ast\n{\"type\":\"relaymark.document\",\"version\":1,\"blocks\":[{\"id\":\"old-note\",\"type\":\"paragraph\",\"content\":[{\"type\":\"strong\",\"content\":[{\"type\":\"text\",\"text\":\"Résumé 🌍\"}]}]}]}\n```\n"
    #expect(throws:(any Error).self){try RelayMarkSourceCodec.parseDocument(source,namespace:"historical-source")}
    let imported=try JSONSerialization.jsonObject(with:RelayMarkSourceCodec.importSource(source,namespace:"historical-source")) as! [String:Any]
    let document=imported["document"] as! [String:Any],blocks=document["blocks"] as! [[String:Any]]
    #expect(blocks[0]["id"] as? String == "b3caafb0d7c034362851808ae213c59be")
    #expect(document["version"] == nil)
    var snapshot=try JSONSerialization.jsonObject(with:RelayMarkSourceCodec.documentToSnapshot(JSONSerialization.data(withJSONObject:document))) as! [String:Any]
    var children=snapshot["children"] as! [[String:Any]],attrs=children[0]["attributes"] as! [String:Any]
    attrs.removeValue(forKey:"relaymarkId");children[0]["attributes"]=attrs;snapshot["children"]=children
    let migrated=try JSONSerialization.jsonObject(with:RelayMarkSourceCodec.importDocumentSnapshot(JSONSerialization.data(withJSONObject:snapshot),namespace:"paper-incarnation")) as! [String:Any]
    #expect((migrated["normalizations"] as! [[String:Any]]).count==1)
    #expect(migrated["requires_reconstruction"] as? Bool == false)
  }

  @Test func historicalBodylessDataViewUsesSharedWidgetGrammar() throws {
    let line = "@DataView(source: \"pulse.streak\", projection: \"calendar\", filter: {basis: \"work\"}, limit: 30, title: \"Retained Ω\")"
    let suffix = "\n\n```text\n" + line + "\n```\n"
    let imported = try RelayMarkSourceCodec.parseDocument(line + suffix, namespace: "historical-data-view")
    let braced = try RelayMarkSourceCodec.parseDocument(line + " {\n}" + suffix, namespace: "historical-data-view")
    #expect(try JSONSerialization.jsonObject(with: imported) as? NSDictionary == JSONSerialization.jsonObject(with: braced) as? NSDictionary)
    let object = try JSONSerialization.jsonObject(with: imported) as! [String: Any]
    let blocks = object["blocks"] as! [[String: Any]]
    #expect(blocks.map { $0["type"] as! String } == ["relay.data_view", "code"])
    let props = blocks[0]["props"] as! [String: Any]
    #expect(props["source"] as? String == "pulse.streak")
    #expect(props["title"] as? String == "Retained Ω")
    #expect(props["filter"] as? NSDictionary == ["basis": "work"] as NSDictionary)
    let snapshot = try RelayMarkSourceCodec.documentToSnapshot(imported)
    #expect(try JSONSerialization.jsonObject(with: RelayMarkSourceCodec.snapshotToDocument(snapshot)) as? NSDictionary == object as NSDictionary)
    #expect(throws: (any Error).self) { try RelayMarkSourceCodec.parseDocument("@DataView(source: \"https://example.test\", projection: \"sql\")", namespace: "invalid-data-view") }
  }
}
