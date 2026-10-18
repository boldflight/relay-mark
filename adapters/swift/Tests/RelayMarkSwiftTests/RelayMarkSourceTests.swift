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
