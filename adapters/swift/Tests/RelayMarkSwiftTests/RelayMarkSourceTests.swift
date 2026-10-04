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

}
