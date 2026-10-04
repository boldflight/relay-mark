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
}
