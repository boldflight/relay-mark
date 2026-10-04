import Foundation
import Testing
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration
struct RelayMarkNativeCanonicalMetadataTests {
 @Test @MainActor func initializesAndExchangesSameAuthoredEnvelopeOnce() throws {
  let source = "<!-- relay:question id=\"q-one\" type=\"multiple_choice\" -->\n**Capital?**\n- ( ) Paris\n- ( ) London\n<!-- /relay:question -->"
  var raw = try JSONSerialization.jsonObject(with:RelayMarkSourceCodec.parseDocument(source,namespace:"native-form-peer")) as! [String:Any]
  raw["frontmatter"] = [String:Any]();raw["annotations"] = [Any]();raw["resources"] = [Any]();raw["meta"] = ["origin":"native"]
  let ast = try JSONSerialization.data(withJSONObject:raw)
  let first = RelayMarkNativeDocument(),peer = RelayMarkNativeDocument()
  let update = try first.initializeDocument(authoredAST:ast)
  #expect(try first.undo()==nil)
  try peer.applyUpdate(update)
  #expect(try JSONSerialization.jsonObject(with:first.authoredDocument()) as? NSDictionary == raw as NSDictionary)
  #expect(try first.authoredDocument()==peer.authoredDocument())
  #expect(throws:(any Error).self) { try first.initializeDocument(authoredAST:ast) }
  let decoded = try RelayMarkDocument.decodeJSON(first.authoredDocument())
  #expect(decoded.meta["origin"]?.stringValue=="native")
 }
}
