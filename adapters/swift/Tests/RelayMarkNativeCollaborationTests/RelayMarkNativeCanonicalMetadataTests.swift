import Foundation
import Testing
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration
struct RelayMarkNativeCanonicalMetadataTests {
 @Test @MainActor func historicalVideoMigratesDerivedDefaultsInPlaceThenUsesActualMaintainedReplacement() throws {
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("spec/relaymark/collaboration/fixtures/rich-video-v3-draft.json"))) as! [String:Any]
  let document=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
  let original=Data(base64Encoded:fixture["update"] as! String)!
  try document.applyUpdate(original);try peer.applyUpdate(original)
  let anchors=try [[0],[1],[2],[0,0],[2,0]].map{try document.anchor(path:$0,index:0)}
  #expect(throws:(any Error).self){try document.authoredDocument()}
  let prepared=try RelayMarkNativeSnapshotImport.prepare(document:document,namespace:"retained-video",expectedSnapshot:document.snapshot())
  let retainedOriginal=try document.encodeUpdate()
  #expect(prepared.originalState == retainedOriginal)
  let migration=try RelayMarkNativeSnapshotImport.install(document:document,prepared:prepared)
  try peer.applyUpdate(migration)
  let migratedAnchors=try [[0],[1],[2],[0,0],[2,0]].map{try document.anchor(path:$0,index:0)}
  #expect(migratedAnchors == anchors)
  #expect(try document.authoredDocument() == peer.authoredDocument())
  let snapshot=try JSONSerialization.jsonObject(with:document.snapshot()) as! [String:Any]
  let video=(snapshot["children"] as! [[String:Any]])[1]
  #expect(Set((video["attributes"] as! [String:Any]).keys) == Set(["relaymarkId","videoId"]))
  let change=try RelayMarkNativeRichEditing.replace(document:document,range:NSRange(location:0,length:6),runs:[("After",[:])],expectedSnapshot:document.snapshot())
  try peer.applyUpdate(change.update)
  #expect(String(try document.richProseProjection().text.characters) == "After video\n\u{FFFC}\nAfter video")
  #expect(try document.authoredDocument() == peer.authoredDocument())
  #expect(change.caret?.offset == 5)
  let media=try #require(document.richProseProjection().mediaAtoms.first)
  let removed=try RelayMarkNativeMediaMutation.remove(document:document,atRootIndex:1,expectedID:media.id,expectedSource:media.source)
  try peer.applyUpdate(removed.update)
  let inserted=try RelayMarkNativeMediaMutation.insert(document:document,atRootIndex:1,expectedPreviousID:"bc5e20755a10547d08d9054f33618c548",expectedNextID:"b29908e62e7c2496580e5aea7bb8e4f14",block:.init(id:media.id,kind:.videoEmbed,source:media.source))
  try peer.applyUpdate(inserted.update)
  #expect(try document.authoredDocument() == peer.authoredDocument())
  #expect(throws:(any Error).self){try RelayMarkNativeSnapshotImport.install(document:document,prepared:prepared)}
 }
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
  try second.applyUpdate(settings.update)
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


 @Test @MainActor func inlineMediaImportInitializesIdentifiedNativeSiblingsWithoutRichTextLoss() throws {
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("spec/relaymark/collaboration/fixtures/canonical-inline-media.json"))) as! [String:Any]
  let source=try RelayMarkSourceCodec.parseDocument(fixture["source"] as! String,namespace:fixture["namespace"] as! String)
  let doc=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
  try peer.applyUpdate(doc.initializeDocument(authoredAST:source))
  #expect(try JSONSerialization.jsonObject(with:peer.authoredDocument()) as? NSDictionary == fixture["expected_ast"] as? NSDictionary)
 }









 @Test @MainActor func removeLinkTypeEmitsEachAuthoredHrefWithoutDefaultAttributeGuessing() throws {
  let document=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("spec/relaymark/collaboration/fixtures/retained-marked-text-branches.json"))) as! [String:Any]
  let original=Data(base64Encoded:fixture["state_base64"] as! String)!
  try document.applyUpdate(original);try peer.applyUpdate(original)
  let maybeChange=try RelayMarkNativeRichEditing.format(document:document,range:NSRange(location:0,length:3),mark:"link",enabled:false,expectedSnapshot:document.snapshot())
  let change=try #require(maybeChange)
  let unlinked=String(decoding:try document.authoredDocument(),as:UTF8.self)
  #expect(!unlinked.contains("https://one.example") && !unlinked.contains("https://two.example"))
  try peer.applyUpdate(change.update)
  let undoValue=try document.undo();let undo=try #require(undoValue);try peer.applyUpdate(undo)
  #expect(try document.authoredDocument()==peer.authoredDocument())
 }

 @Test @MainActor func actualRichMarkStepPreservesUnicodeItemsAndPeerChoice() throws {
  let document=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
  let source="<!-- relay:question id=\"q-one\" type=\"multiple_choice\" -->\nA🌍Z\n- ( ) Paris\n<!-- /relay:question -->"
  try peer.applyUpdate(document.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument(source,namespace:"format-choice")))
  let maybeChange=try RelayMarkNativeRichEditing.format(document:document,range:NSRange(location:1,length:2),mark:"bold",enabled:true,expectedSnapshot:document.snapshot())
  let change=try #require(maybeChange)
  try peer.applyUpdate(change.update)
  let remote=try RelayMarkNativeRichEditing.replace(document:peer,range:NSRange(location:5,length:0),runs:[("Peer ",[:])],expectedSnapshot:peer.snapshot())
  try document.applyUpdate(remote.update)
  let maybeUndo=try document.undo();let undo=try #require(maybeUndo);try peer.applyUpdate(undo)
  #expect(String(try document.richProseProjection().text.characters)=="A🌍Z\nPeer Paris")
  #expect(try document.authoredDocument()==peer.authoredDocument())
  let maybeRemove=try RelayMarkNativeRichEditing.format(document:peer,range:NSRange(location:1,length:2),mark:"italic",enabled:true,expectedSnapshot:peer.snapshot())
  let remove=try #require(maybeRemove)
  try document.applyUpdate(remove.update)
  let maybeUnmark=try RelayMarkNativeRichEditing.format(document:document,range:NSRange(location:1,length:2),mark:"italic",enabled:false,expectedSnapshot:document.snapshot())
  _ = try #require(maybeUnmark)
  #expect(try RelayMarkNativeRichEditing.format(document:document,range:NSRange(location:1,length:2),mark:"italic",enabled:false,expectedSnapshot:document.snapshot())==nil)
 }

 @Test @MainActor func addingRichChoiceValidatesTheActualQuestionAndKeepsExistingPeerItems() throws {
  let document=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
  let source="<!-- relay:question id=\"q-one\" type=\"multiple_choice\" -->\nCapital?\n- ( ) Paris\n<!-- /relay:question -->"
  let seed=try document.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument(source,namespace:"add-choice"));try peer.applyUpdate(seed)
  let option:[String:Any] = ["id":"b11111111111141118111111111111111","type":"relay.form_option",
      "props":["id":"london","correct":false,"points":NSNull(),"settings":[:]],
      "content":[["type":"strong","content":[["type":"text","text":"London"]]]]]
  let update=try RelayMarkNativeWidgetMutation.insert(document:document,parentPath:[0],at:2,
      authoredBlock:JSONSerialization.data(withJSONObject:option),expectedSnapshot:document.snapshot())
  try peer.applyUpdate(update.update)
  #expect(try document.authoredDocument()==peer.authoredDocument())
  #expect(String(try document.richProseProjection().text.characters)=="Capital?\nParis\nLondon")
  let result=try document.undo();let undo=try #require(result);try peer.applyUpdate(undo)
  #expect(try document.authoredDocument()==peer.authoredDocument())
  #expect(String(try document.richProseProjection().text.characters)=="Capital?\nParis")
 }

 @Test @MainActor func removingChoiceKeepsRichQuestionAndRejectsInvalidParentSettingsBeforeMutation() throws {
  let document=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
  let source="<!-- relay:question id=\"q-one\" type=\"multiple_choice\" -->\n**Capital?**\n- ( ) Paris\n- ( ) London\n<!-- /relay:question -->"
  let seed=try document.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument(source,namespace:"remove-choice"));try peer.applyUpdate(seed)
  let ast=try RelayMarkNativeDocumentProjection.project(document:document)
  let state=try document.encodeUpdate(),snapshot=try document.snapshot()
  let raw=try JSONSerialization.jsonObject(with:document.authoredDocument()) as! [String:Any]
  let parts=((raw["blocks"] as! [[String:Any]])[0]["content"] as! [[String:Any]])
  #expect(throws:(any Error).self) { try RelayMarkNativeWidgetMutation.updateAttributes(document:document,path:[0],expectedID:ast.blocks[0].id,expected:Data(#"{"type":"multiple_choice"}"#.utf8),changes:Data(#"{"type":"unsupported_type"}"#.utf8)) }
  #expect(try document.encodeUpdate()==state)
  #expect(throws:(any Error).self) { try RelayMarkNativeWidgetMutation.remove(document:document,path:[0,0],expectedID:parts[0]["id"] as! String,expectedSnapshot:snapshot) }
  #expect(try document.encodeUpdate()==state)
  let update=try RelayMarkNativeWidgetMutation.remove(document:document,path:[0,2],expectedID:parts[2]["id"] as! String,expectedSnapshot:snapshot)
  try peer.applyUpdate(update.update)
  #expect(try document.authoredDocument()==peer.authoredDocument())
  #expect(String(try document.richProseProjection().text.characters)=="Capital?\nParis")
 }

}
