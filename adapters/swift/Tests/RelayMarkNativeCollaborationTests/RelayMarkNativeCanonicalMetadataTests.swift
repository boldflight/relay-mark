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
 @Test @MainActor func nativeQuestionOptionsEditIndependentlyAndLocalUndoRetainsPeerChoice() throws {
  let source = "<!-- relay:question id=\"q-one\" type=\"multiple_choice\" -->\n**Capital?**\n- ( ) Paris\n- ( ) London\n<!-- /relay:question -->"
  let ast = try RelayMarkSourceCodec.parseDocument(source,namespace:"native-form-peer")
  let first=RelayMarkNativeDocument(),second=RelayMarkNativeDocument()
  let seed=try first.initializeDocument(authoredAST:ast);try second.applyUpdate(seed)
  let projection=try first.richProseProjection()
  #expect(projection.isEditable)
  #expect(projection.authoredWidgets.map(\.nodeName)==["questionOption","questionOption","questionBlock"])
  #expect(String(projection.text.characters)=="Capital?\nParis\nLondon")
  let typing = try RelayMarkNativeRichEditing.replace(document:first,range:NSRange(location:0,length:0),runs:[("New ",[:])],inheritMarks:true,expectedSnapshot:first.snapshot())
  try second.applyUpdate(typing.update)
  let a=try RelayMarkNativeRichTextMutation.replace(document:first,path:[0,1,0],start:0,end:0,text:"A ")
  let b=try RelayMarkNativeRichTextMutation.replace(document:second,path:[0,2,0],start:0,end:0,text:"B ")
  try first.applyUpdate(b);try second.applyUpdate(a)
  #expect(try first.authoredDocument()==second.authoredDocument())
  let maybeUndo=try first.undo();let undo=try #require(maybeUndo);try second.applyUpdate(undo)
  #expect(try first.authoredDocument()==second.authoredDocument())
  #expect(String(try first.richProseProjection().text.characters)=="New Capital?\nParis\nB London")
  let q=try RelayMarkNativeDocumentProjection.project(document:first).blocks[0]
  let settings=try RelayMarkNativeWidgetMutation.updateAttributes(document:first,path:[0],expectedID:q.id,
      expected:Data(#"{"required":false}"#.utf8),changes:Data(#"{"required":true}"#.utf8))
  try second.applyUpdate(settings)
  #expect(try first.authoredDocument()==second.authoredDocument())
  #expect(try RelayMarkNativeDocumentProjection.project(document:first).blocks[0].props["required"]?.boolValue==true)
 }

 @Test @MainActor func genericRichContainersDataDeclarationsAndImageDimensionsRemainEditable() throws {
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  var ast=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("spec/relaymark/collaboration/fixtures/canonical-directives.json"))) as! [String:Any]
  var blocks=ast["blocks"] as! [[String:Any]]
  blocks.append(["id":"b00000000000040008000000000000020","type":"image","content":[],"props":["src":"/m/diagram","alt":"Diagram","title":NSNull(),"width":120,"height":80]])
  blocks.append(["id":"b00000000000040008000000000000021","type":"relay.data_view","content":[],"props":["source":"tasks.mine","projection":"list","title":"Tasks","filter":["done":false]]])
  ast["blocks"]=blocks
  let document=RelayMarkNativeDocument();try document.initializeDocument(authoredAST:JSONSerialization.data(withJSONObject:ast))
  let projection=try document.richProseProjection()
  #expect(projection.isEditable)
  #expect(projection.authoredWidgets.filter{$0.kind == .directive}.map(\.nodeName)==["relayEvidence","relayClaim","relayComparison"])
  #expect(projection.authoredWidgets.last?.kind == .dataView)
  #expect(projection.mediaAtoms.first?.width==120);#expect(projection.mediaAtoms.first?.height==80)
  #expect(projection.tableCells.count==2)
 }

 @Test @MainActor func canonicalQuestionHistoryCheckpointReopensOnSameOwnerWithPeerChoiceIntact() throws {
  let source = "<!-- relay:question id=\"q-one\" type=\"multiple_choice\" -->\n**Capital?**\n- ( ) Paris\n- ( ) London\n<!-- /relay:question -->"
  var raw=try JSONSerialization.jsonObject(with:RelayMarkSourceCodec.parseDocument(source,namespace:"native-history")) as! [String:Any]
  raw["meta"]=["origin":"native"]
  let first=RelayMarkNativeDocument(guid:"document-incarnation",retainDeletedItems:true),peer=RelayMarkNativeDocument(guid:"document-incarnation",retainDeletedItems:true)
  try peer.applyUpdate(first.initializeDocument(authoredAST:JSONSerialization.data(withJSONObject:raw)))
  let own=try RelayMarkNativeRichTextMutation.replace(document:first,path:[0,1,0],start:0,end:5,text:"Lyon")
  try peer.applyUpdate(own)
  let remote=try RelayMarkNativeRichTextMutation.replace(document:peer,path:[0,2,0],start:0,end:6,text:"Oslo")
  try first.applyUpdate(remote)
  let archive=try first.exportHistoryState(scopeToken:"account/org/document/incarnation/lane/owner")
  let reopened=RelayMarkNativeDocument(guid:"document-incarnation",retainDeletedItems:true)
  try reopened.applyUpdate(RelayMarkNativeDocument.historyDocumentState(archive))
  try reopened.restoreHistoryState(archive,scopeToken:"account/org/document/incarnation/lane/owner")
  #expect(try reopened.authoredDocument()==first.authoredDocument())
  #expect(throws:(any Error).self) { try reopened.restoreHistoryState(archive,scopeToken:"another-owner") }
  #expect(try reopened.undo() != nil)
  #expect(String(try reopened.richProseProjection().text.characters)=="Capital?\nParis\nOslo")
  #expect(try RelayMarkDocument.decodeJSON(reopened.authoredDocument()).meta["origin"]?.stringValue=="native")
  #expect(try reopened.redo() != nil)
  #expect(String(try reopened.richProseProjection().text.characters)=="Capital?\nLyon\nOslo")
  _=try RelayMarkNativeRichTextMutation.replace(document:reopened,path:[0,1,0],start:0,end:0,text:"New ")
  #expect(try reopened.undo() != nil)
  #expect(String(try reopened.richProseProjection().text.characters)=="Capital?\nLyon\nOslo")
 }

 @Test @MainActor func fullReferenceTitleUsesSharedSourceAndAtomicPresentation() throws {
  let label=" [A]\n\"B\"\\ "
  let source=try RelayMarkSourceCodec.buildEntityReferenceSource(entityType:"Person",entityID:"11111111-1111-4111-8111-111111111111",label:label)
  #expect(source == #"[[Person: 11111111-1111-4111-8111-111111111111 | "\u0020\u005b\u0041\u005d\u000a\u0022\u0042\u0022\u005c\u0020"]]"#)
  let document=RelayMarkNativeDocument()
  try document.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument(source,namespace:"reference-title"))
  let projection=try document.richProseProjection()
  #expect(projection.isEditable)
  #expect(projection.inlineAtoms.first?.label==label)
  #expect(projection.inlineAtoms.first?.range.length==1)
 }

 @Test @MainActor func onboardingStaticImagesRemainCanonicalNativeMedia() throws {
  for src in ["/images/onboarding/connected-note.png","/images/onboarding/connected-work.png"] {
   let document=RelayMarkNativeDocument()
   try document.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("![Connected](\(src))",namespace:"onboarding-image"))
   #expect(try document.richProseProjection().mediaAtoms.first?.source==src)
  }
 }

 @Test @MainActor func historicalSourceImportsExactSharedIdentityFixtureOnCanonicalYrsOwner() throws {
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("spec/relaymark/collaboration/fixtures/canonical-historical-source.json"))) as! [String:Any]
  let ast=try RelayMarkSourceCodec.parseDocument(fixture["source"] as! String,namespace:fixture["namespace"] as! String)
  #expect(try JSONSerialization.jsonObject(with:ast) as? NSDictionary == fixture["expected_ast"] as? NSDictionary)
  let document=RelayMarkNativeDocument();try document.initializeDocument(authoredAST:ast)
  #expect(try JSONSerialization.jsonObject(with:document.authoredDocument()) as? NSDictionary == fixture["expected_ast"] as? NSDictionary)
 }
 @Test @MainActor func historicalBlockReferencesAndMediaInitializeCanonicalNativeAtoms() throws {
  let source = "@EntityRef(id: \"11111111-1111-4111-8111-111111111111\", projection: \"card\") {\nAuthored fallback\n}\n\n::video[/v/11111111-1111-4111-8111-111111111111]\n\n<https://example.com/a.gif>"
  let ast=try RelayMarkSourceCodec.parseDocument(source,namespace:"old-native-media")
  let raw=try JSONSerialization.jsonObject(with:ast) as! [String:Any]
  #expect((raw["blocks"] as! [[String:Any]]).map{$0["type"] as! String} == ["relay.entity_reference","relay.video_embed","image"])
  let doc=RelayMarkNativeDocument();try doc.initializeDocument(authoredAST:ast)
  #expect(try JSONSerialization.jsonObject(with:doc.authoredDocument()) as? NSDictionary == raw as NSDictionary)
  let projection=try doc.richProseProjection();#expect(projection.mediaAtoms.count==2);#expect(projection.entityReferenceAtoms.map(\.entityID)==["11111111-1111-4111-8111-111111111111"])
 }
 @Test @MainActor func nativeRichTextIdentityAndFormattingEvidencePreservePeerCausalMarkers() throws {
  let source="<!-- relay:question id=\"q-one\" type=\"multiple_choice\" -->\nA🌍Z\n- ( ) Paris\n<!-- /relay:question -->\n\n@Callout(tone: \"info\", emphasis: \"soft\") {\nNested\n}"
  let doc=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
  try peer.applyUpdate(doc.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument(source,namespace:"native-format-evidence")))
  let before=try doc.encodeUpdate()
  let selected=try doc.captureTextItems(path:[0,0,0],start:1,length:2)
  let rows=try JSONSerialization.jsonObject(with:selected) as! [String:Any]
  #expect(rows["contract_version"] as? Int == 1);#expect(rows["kind"] as? String == "text_items")
  #expect((rows["runs"] as! [[String:Any]])[0]["count"] as? Int == 2)
  #expect(try peer.captureTextItems(path:[0,0,0],start:1,length:2)==selected)
  let update=try peer.formatText(at:1,length:2,attributes:["bold":[String:Any]()],path:[0,0,0])
  let evidence=try doc.captureFormatEvent(update:update,mark:"bold",textItems:selected,operationID:UUID(uuidString:"11111111-1111-4111-8111-111111111111")!)
  let event=try JSONSerialization.jsonObject(with:evidence) as! [String:Any]
  #expect(event["contract_version"] as? Int == 1);#expect(event["kind"] as? String == "format_event")
  #expect(event["version"] == nil)
  let changes=event["changes"] as! [[String:Any]];#expect(changes.count==2)
  #expect((changes[0]["before"] as! [String:Any])["enabled"] as? Bool == false)
  #expect((changes[0]["after"] as! [String:Any])["enabled"] as? Bool == true)
  #expect(try doc.encodeUpdate()==before)
  let all=try JSONSerialization.jsonObject(with:doc.captureVisibleTextItems()) as! [String:Any]
  #expect((all["runs"] as! [[String:Any]]).reduce(0){$0+($1["count"] as! Int)}==15)
  let unrelated=try peer.formatText(at:0,length:2,attributes:["bold":[String:Any]()],path:[0,1,0])
  let hidden=try doc.mergeUpdates([update,unrelated])
  #expect(throws:(any Error).self){try doc.captureFormatEvent(update:hidden,mark:"bold",textItems:selected,operationID:UUID())}
  let wrong=try doc.captureTextItems(path:[0,1,0],start:0,length:2)
  #expect(throws:(any Error).self){try doc.captureFormatEvent(update:update,mark:"bold",textItems:wrong,operationID:UUID())}
  #expect(try doc.encodeUpdate()==before)
 }
 @Test @MainActor func nativeOwnedUndoCopiesAndRichAnchoredOperationsUseCanonicalEvidence() throws {
  let doc=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
  try doc.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("@FormQuestion(id: \"q\", type: \"short_text\") {\nA🌍Z\n}",namespace:"undo-source"))
  let selected=try JSONSerialization.jsonObject(with:doc.captureTextItems(path:[0,0,0],start:1,length:2)) as! [String:Any]
  let operation=try JSONSerialization.jsonObject(with:doc.captureReplaceProseOperation(start:.init(path:[0,0,0],index:1),end:.init(path:[0,0,0],index:3),text:"")) as! [String:Any]
  #expect(operation["kind"] as? String == "replace_prose")
  #expect((operation["start_anchor"] as? [String:Any])?["type"] != nil)
  #expect((operation["end_anchor"] as? [String:Any])?["assoc"] as? Int == 0)
  #expect(throws:(any Error).self){try doc.captureReplaceProseOperation(start:.init(path:[0,0,0],index:2),end:.init(path:[0,0,0],index:3),text:"")}
  try doc.replaceText(at:1,length:2,with:"",path:[0,0,0])
  try peer.applyUpdate(doc.encodeUpdate())
  try doc.applyUpdate(peer.insertText("🌍",at:1,path:[0,0,0]))
  let vector=doc.stateVector();#expect(try doc.undo() != nil)
  let state=try doc.encodeUpdate()
  let observation=try JSONSerialization.jsonObject(with:doc.captureRestoredTextItems(since:vector)) as! [String:Any]
  let copies=observation["copies"] as! [[String:Any]];#expect(copies.count==1)
  #expect((copies[0]["source"] as! [String:Any])["runs"] as? NSArray == selected["runs"] as? NSArray)
  #expect((copies[0]["source"] as? NSDictionary) != (copies[0]["destination"] as? NSDictionary))
  #expect(try doc.encodeUpdate()==state)
 }

}
