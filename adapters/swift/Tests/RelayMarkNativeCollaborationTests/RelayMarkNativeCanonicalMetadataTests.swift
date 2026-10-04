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
  let steps=try JSONSerialization.jsonObject(with:change.steps) as! [[String:Any]]
  #expect(steps[0]["stepType"] as? String == "replace")
  let media=try #require(document.richProseProjection().mediaAtoms.first)
  let removed=try RelayMarkNativeMediaMutation.remove(document:document,atRootIndex:1,expectedID:media.id,expectedSource:media.source)
  try peer.applyUpdate(removed)
  let inserted=try RelayMarkNativeMediaMutation.insert(document:document,atRootIndex:1,expectedPreviousID:"bc5e20755a10547d08d9054f33618c548",expectedNextID:"b29908e62e7c2496580e5aea7bb8e4f14",block:.init(id:media.id,kind:.videoEmbed,source:media.source))
  try peer.applyUpdate(inserted)
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
  let settingsSteps=try JSONSerialization.jsonObject(with:settings.steps) as! [[String:Any]]
  #expect(settingsSteps as NSArray == [["stepType":"attr","pos":0,"attr":"required","value":true]] as NSArray)
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
  let reopened=RelayMarkNativeDocument(guid:"document-incarnation",retainDeletedItems:true,historyOwnerID:first.historyOwnerID)
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

 @Test @MainActor func nativeFreshRichTextAccountingIncludesIndependentQuestionOptionEdits() throws {
  let doc=RelayMarkNativeDocument()
  try doc.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("<!-- relay:question id=\"q\" type=\"multiple_choice\" -->\nA🌍Z\n- ( ) Choice\n<!-- /relay:question -->",namespace:"fresh-rich-ids"))
  let vector=doc.stateVector()
  try doc.insertText("!",at:4,path:[0,0,0])
  try doc.insertText("🌍",at:6,path:[0,1,0])
  let state=try doc.encodeUpdate()
  let evidence=try JSONSerialization.jsonObject(with:doc.captureVisibleTextItems(since:vector)) as! [String:Any]
  #expect(evidence["contract_version"] as? Int == 1)
  #expect(evidence["kind"] as? String == "text_items")
  let runs=evidence["runs"] as! [[String:Any]]
  #expect(runs.map{$0["count"] as! Int} == [1,2])
  #expect((runs[0]["type"] as? NSDictionary) != (runs[1]["type"] as? NSDictionary))
  #expect(try doc.encodeUpdate()==state)
 }

 @Test @MainActor func inlineMediaImportInitializesIdentifiedNativeSiblingsWithoutRichTextLoss() throws {
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("spec/relaymark/collaboration/fixtures/canonical-inline-media.json"))) as! [String:Any]
  let source=try RelayMarkSourceCodec.parseDocument(fixture["source"] as! String,namespace:fixture["namespace"] as! String)
  let doc=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
  try peer.applyUpdate(doc.initializeDocument(authoredAST:source))
  #expect(try JSONSerialization.jsonObject(with:peer.authoredDocument()) as? NSDictionary == fixture["expected_ast"] as? NSDictionary)
 }

 @Test @MainActor func maintainedNativeContentWitnessSeparatesRichRelocationFromHumanText() throws {
  let doc=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
  try peer.applyUpdate(doc.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("**Generated 😀 suffix**",namespace:"native-content-witness")))
  let observed=try doc.captureContentEditObservation()
  let original=(try JSONSerialization.jsonObject(with:doc.captureTextItems(path:[0,0],start:10,length:9)) as! [String:Any])["runs"] as! [[String:Any]]
  let change=try RelayMarkNativeRichEditing.replace(document:doc,range:NSRange(location:10,length:0),runs:[("\n",[:])],expectedSnapshot:doc.snapshot())
  #expect(change.beforeSnapshot==observed.beforeSnapshot)
  #expect(throws:(any Error).self){try peer.buildContentEditWitness(observed,steps:change.steps,update:change.update)}
  #expect(throws:(any Error).self){try doc.buildContentEditWitness(observed,steps:change.steps,update:Data([0,0]))}
  let proof=try JSONSerialization.jsonObject(with:doc.buildContentEditWitness(observed,steps:change.steps,update:change.update)) as! [String:Any]
  #expect(((proof["text_items"] as! [String:Any])["runs"] as! [Any]).isEmpty)
  let copies=proof["proven_copies"] as! [[String:Any]]
  #expect(copies.count==1)
  #expect((copies[0]["source"] as! [String:Any])["runs"] as? NSArray == original as NSArray)
  #expect(((copies[0]["destination"] as! [String:Any])["runs"] as! [[String:Any]])[0]["count"] as? Int == 9)
  #expect(proof["requires_mutation_correspondence"] as? Bool == true)
  #expect(throws:(any Error).self){try doc.buildContentEditWitness(observed,steps:change.steps,update:change.update)}
  try peer.applyUpdate(change.update);#expect(try doc.authoredDocument()==peer.authoredDocument())
  let typedObservation=try doc.captureContentEditObservation()
  let typing=try RelayMarkNativeRichEditing.replace(document:doc,range:NSRange(location:0,length:0),runs:[("A🌍Z",["underline":[:]])],expectedSnapshot:doc.snapshot())
  let typed=try JSONSerialization.jsonObject(with:doc.buildContentEditWitness(typedObservation,steps:typing.steps,update:typing.update)) as! [String:Any]
  let human=(typed["text_items"] as! [String:Any])["runs"] as! [[String:Any]]
  #expect(human.reduce(0){$0+($1["count"] as! Int)}==4)
  #expect((typed["proven_copies"] as! [Any]).isEmpty)
 }

 @Test @MainActor func ownedNativeInverseWitnessRestoresOriginalUnicodeIDsWithoutClaimingPeerText() throws {
  let doc=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument(),id=UUID()
  try doc.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("@FormQuestion(id: \"q\", type: \"short_text\") {\nA🌍Z\n}",namespace:"inverse-native-witness"))
  let original=try JSONSerialization.jsonObject(with:doc.captureTextItems(path:[0,0,0],start:1,length:2)) as! [String:Any]
  _ = try doc.performOwnedCommand(operationID:id){try RelayMarkNativeRichEditing.replace(document:doc,range:NSRange(location:1,length:2),runs:[],expectedSnapshot:doc.snapshot()).update}
  try peer.applyUpdate(doc.encodeUpdate())
  try doc.applyUpdate(peer.insertText("🌍",at:1,path:[0,0,0]))
  let observation=try doc.captureContentEditObservation()
  let inverse=try #require(try doc.undoWithReference())
  #expect(inverse.kind == .undo)
  #expect(throws:(any Error).self){try peer.buildOwnedHistoryWitness(observation,effect:inverse)}
  let proof=try JSONSerialization.jsonObject(with:doc.buildOwnedHistoryWitness(observation,effect:inverse)) as! [String:Any]
  #expect((proof["text_items"] as! [String:Any])["runs"] as? NSArray == NSArray())
  let copies=proof["proven_copies"] as! [[String:Any]]
  #expect(copies.count==1)
  #expect((copies[0]["source"] as! [String:Any])["runs"] as? NSArray == original["runs"] as? NSArray)
  #expect(((copies[0]["destination"] as! [String:Any])["runs"] as! [[String:Any]])[0]["count"] as? Int == 2)
  #expect(proof["requires_mutation_correspondence"] as? Bool == true)
  #expect(proof["requires_owned_history_correspondence"] as? Bool == true)
  #expect(proof["owned_history_correspondence"] == nil)
  #expect(try String(doc.richProseProjection().text.characters)=="A🌍🌍Z")
  #expect(throws:(any Error).self){try doc.buildOwnedHistoryWitness(observation,effect:inverse)}
  let redoObservation=try doc.captureContentEditObservation()
  let redo=try #require(try doc.redoWithReference())
  let redoProof=try JSONSerialization.jsonObject(with:doc.buildOwnedHistoryWitness(redoObservation,effect:redo)) as! [String:Any]
  #expect(redo.kind == .redo)
  #expect((redoProof["proven_copies"] as! [Any]).isEmpty)
  #expect((redoProof["fresh_items"] as! [String:Any])["runs"] as? NSArray == NSArray())
  #expect(try String(doc.richProseProjection().text.characters)=="A🌍Z")
 }

 @Test @MainActor func firstOwnedTypingColdReopenUndoPreservesPeerBranchThroughAnotherReopen() throws {
  let first=UUID(),second=UUID(),doc=RelayMarkNativeDocument(guid:"first-owned-typing")
  try doc.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("",namespace:"first-owned-typing"))
  let seed=try JSONSerialization.jsonObject(with:doc.authoredDocument()) as! [String:Any]
  let identity=(seed["blocks"] as! [[String:Any]])[0]["id"] as! String
  _ = try doc.performOwnedCommand(operationID:first){try RelayMarkNativeRichEditing.replace(document:doc,range:NSRange(location:0,length:0),runs:[("He",[:])],expectedSnapshot:doc.snapshot()).update}
  _ = try doc.exportHistoryState(scopeToken:"first-typing-owner")
  _ = try doc.performOwnedCommand(operationID:second){try RelayMarkNativeRichEditing.replace(document:doc,range:NSRange(location:2,length:0),runs:[("llo",[:])],expectedSnapshot:doc.snapshot()).update}
  let checkpoint=try doc.exportHistoryState(scopeToken:"first-typing-owner")
  let reopened=RelayMarkNativeDocument(guid:try RelayMarkNativeDocument.historyDocumentGUID(checkpoint),historyOwnerID:try RelayMarkNativeDocument.historyOwner(checkpoint))
  try reopened.applyUpdate(RelayMarkNativeDocument.historyDocumentState(checkpoint));try reopened.restoreHistoryState(checkpoint,scopeToken:"first-typing-owner")
  let peer=RelayMarkNativeDocument();try peer.applyUpdate(reopened.encodeUpdate())
  try reopened.applyUpdate(peer.insertText("Peer ",at:0,path:[0,0]))
  let senderSnapshot=try reopened.captureSenderSnapshot()
  let undo=try #require(try reopened.undoWithReference())
  #expect(undo.beforeSnapshot==senderSnapshot)
  let sync=try JSONSerialization.jsonObject(with:undo.steps) as! [[String:Any]]
  #expect(sync.count==1);#expect(sync[0]["stepType"] as? String == "replace")
  #expect(sync[0]["from"] as? Int == 0);#expect(sync[0]["to"] as? Int == 12)
  #expect(undo.ownerID==doc.historyOwnerID);#expect(undo.operationIDs == [first,second]);#expect(try String(reopened.richProseProjection().text.characters)=="Peer ")
  let blocks=(try JSONSerialization.jsonObject(with:reopened.authoredDocument()) as! [String:Any])["blocks"] as! [[String:Any]]
  #expect(blocks[0]["id"] as? String == identity)
  try peer.applyUpdate(undo.update);#expect(try peer.authoredDocument()==reopened.authoredDocument())
  let afterUndo=try reopened.exportHistoryState(scopeToken:"first-typing-owner")
  let again=RelayMarkNativeDocument(guid:try RelayMarkNativeDocument.historyDocumentGUID(afterUndo),historyOwnerID:try RelayMarkNativeDocument.historyOwner(afterUndo))
  try again.applyUpdate(RelayMarkNativeDocument.historyDocumentState(afterUndo));try again.restoreHistoryState(afterUndo,scopeToken:"first-typing-owner")
  let redo=try #require(try again.redoWithReference());#expect(redo.operationIDs == [first,second])
  #expect(try String(again.richProseProjection().text.characters)=="Peer Hello")
  let finalUndo=try #require(try again.undoWithReference());#expect(finalUndo.operationIDs == [first,second])
  #expect(try String(again.richProseProjection().text.characters)=="Peer ")
 }

 @Test @MainActor func durableCheckpointDoesNotBreakNormalOwnedTypingGroup() throws {
  let first=UUID(uuidString:"11111111-1111-4111-8111-111111111111")!,second=UUID(uuidString:"22222222-2222-4222-8222-222222222222")!
  let doc=RelayMarkNativeDocument(guid:"owned-typing-group")
  try doc.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("Base",namespace:"owned-typing-group"))
  _ = try doc.performOwnedCommand(operationID:first){try doc.insertText("!",at:4,path:[0,0])}
  _ = try doc.exportHistoryState(scopeToken:"owner/typing-group")
  _ = try doc.performOwnedCommand(operationID:second){try doc.insertText("?",at:5,path:[0,0])}
  let undo=try doc.undoWithReference();#expect(undo?.reference == first);#expect(undo?.operationIDs == [first,second])
  #expect(try String(doc.richProseProjection().text.characters)=="Base")
  let archive=try doc.exportHistoryState(scopeToken:"owner/typing-group")
  let reopened=RelayMarkNativeDocument(guid:try RelayMarkNativeDocument.historyDocumentGUID(archive),historyOwnerID:try RelayMarkNativeDocument.historyOwner(archive))
  try reopened.applyUpdate(RelayMarkNativeDocument.historyDocumentState(archive));try reopened.restoreHistoryState(archive,scopeToken:"owner/typing-group")
  let redo=try reopened.redoWithReference();#expect(redo?.reference == first);#expect(redo?.operationIDs == [first,second])
  #expect(try String(reopened.richProseProjection().text.characters)=="Base!?")
  let third=UUID(uuidString:"33333333-3333-4333-8333-333333333333")!
  _ = try reopened.performOwnedCommand(operationID:third,separateHistoryItem:true){try reopened.insertText(".",at:6,path:[0,0])}
  let separate=try reopened.undoWithReference();#expect(separate?.operationIDs == [third])
  #expect(try String(reopened.richProseProjection().text.characters)=="Base!?")
  let before=try reopened.encodeUpdate()
  #expect(throws:(any Error).self){try reopened.performOwnedCommand(operationID:first){try reopened.insertText("duplicate",at:0,path:[0,0])}}
  #expect(try reopened.encodeUpdate()==before)

 }

 @Test @MainActor func ownedSourceCommandReferenceSurvivesUndoRedoReopenAndRefusesUnboundHistoryBeforeMutation() throws {
  let operationID=UUID(uuidString:"11111111-1111-4111-8111-111111111111")!
  let doc=RelayMarkNativeDocument(guid:"source-reference")
  try doc.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("Hello",namespace:"source-reference"))
  _ = try doc.performOwnedCommand(operationID:operationID){
   let a=try doc.insertText("!",at:5,path:[0,0]),b=try doc.insertText("?",at:6,path:[0,0])
   return try doc.mergeUpdates([a,b])
  }
  let archive=try doc.exportHistoryState(scopeToken:"owner/source-reference")
  var retained=try JSONSerialization.jsonObject(with:archive) as! [String:Any]
  var legacyHistory=retained["history"] as! [String:Any]
  legacyHistory["metadata"]=(legacyHistory["metadata"] as! [Any]).map{ value -> Any in
   if value is NSNull {return value};return ["operation_id":operationID.uuidString.lowercased()]
  }
  retained["history"]=legacyHistory;retained.removeValue(forKey:"owner_id")
  let originalRetained=try JSONSerialization.data(withJSONObject:retained,options:[.sortedKeys])
  let converted=try RelayMarkNativeDocument.importRetainedHistoryState(originalRetained,historyOwnerID:doc.historyOwnerID)
  #expect(converted.originalState==originalRetained)
  #expect(try RelayMarkNativeDocument.historyOwner(converted.state)==doc.historyOwnerID)
  #expect(throws:(any Error).self){try RelayMarkNativeDocument.historyDocumentState(originalRetained)}
  #expect(throws:(any Error).self){try RelayMarkNativeDocument.importRetainedHistoryState(Data("{}".utf8),historyOwnerID:doc.historyOwnerID)}
  let historical=RelayMarkNativeDocument(guid:try RelayMarkNativeDocument.historyDocumentGUID(converted.state),historyOwnerID:try RelayMarkNativeDocument.historyOwner(converted.state))
  try historical.applyUpdate(RelayMarkNativeDocument.historyDocumentState(converted.state));try historical.restoreHistoryState(converted.state,scopeToken:"owner/source-reference")
  #expect(try historical.undoWithReference()?.operationIDs==[operationID])

  let reopened=RelayMarkNativeDocument(guid:try RelayMarkNativeDocument.historyDocumentGUID(archive),historyOwnerID:try RelayMarkNativeDocument.historyOwner(archive))
  try reopened.applyUpdate(RelayMarkNativeDocument.historyDocumentState(archive))
  try reopened.restoreHistoryState(archive,scopeToken:"owner/source-reference")
  let undo=try reopened.undoWithReference();#expect(undo?.reference==operationID)
  #expect(try String(reopened.richProseProjection().text.characters)=="Hello")
  let redoArchive=try reopened.exportHistoryState(scopeToken:"owner/source-reference")
  let second=RelayMarkNativeDocument(guid:try RelayMarkNativeDocument.historyDocumentGUID(redoArchive),historyOwnerID:try RelayMarkNativeDocument.historyOwner(redoArchive))
  try second.applyUpdate(RelayMarkNativeDocument.historyDocumentState(redoArchive));try second.restoreHistoryState(redoArchive,scopeToken:"owner/source-reference")
  let redo=try second.redoWithReference();#expect(redo?.reference==operationID)
  #expect(try String(second.richProseProjection().text.characters)=="Hello!?")
  _ = try second.insertText("unbound",at:7,path:[0,0])
  let state=try second.encodeUpdate(),history=try second.exportHistoryState(scopeToken:"owner/source-reference")
  #expect(throws:(any Error).self){try second.undoWithReference()}
  #expect(try second.encodeUpdate()==state)
  #expect(try second.exportHistoryState(scopeToken:"owner/source-reference")==history)
  #expect(throws:(any Error).self){try doc.groupingUndo{try doc.performOwnedCommand(operationID:UUID()){Data()}}}
 }

 @Test @MainActor func reviewedFullDocumentReplacementRetainsRichIdentitiesMetadataPeerAndUndo() throws {
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  var raw=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("spec/relaymark/collaboration/fixtures/canonical-directives.json"))) as! [String:Any]
  var blocks=raw["blocks"] as! [[String:Any]]
  let question=try JSONSerialization.jsonObject(with:RelayMarkSourceCodec.parseDocument("<!-- relay:question id=\"reviewed-q\" type=\"multiple_choice\" -->\n**Rich question?**\n- ( ) Paris\n- ( ) London\n<!-- /relay:question -->",namespace:"reviewed-recovery")) as! [String:Any]
  blocks += question["blocks"] as! [[String:Any]]
  blocks.append(["id":"b00000000000040008000000000000090","type":"image","content":[],"props":["src":"/m/retained-image","alt":"Diagram","title":NSNull(),"width":120,"height":80]])
  raw["blocks"]=blocks;raw["frontmatter"]=["title":"Exact recovery"];raw["annotations"]=[] as [Any];raw["resources"]=[] as [Any];raw["meta"]=["retained":"original"]
  let authored=try JSONSerialization.data(withJSONObject:raw,options:[.sortedKeys]),doc=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
  try peer.applyUpdate(doc.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("Original",namespace:"original-recovery")))
  let original=try doc.authoredDocument(),snapshot=try doc.snapshot(),command=UUID()
  var change:RelayMarkNativeRichEditing.Change?
  _ = try doc.performOwnedCommand(operationID:command,separateHistoryItem:true){let result=try RelayMarkNativeRichEditing.replaceDocument(document:doc,authoredAST:authored,expectedSnapshot:snapshot);change=result;return result.update}
  let effect=try #require(change);#expect(effect.authoredMetadataChanged);try peer.applyUpdate(effect.update)
  #expect(try JSONSerialization.jsonObject(with:doc.authoredDocument()) as? NSDictionary == raw as NSDictionary)
  #expect(try doc.authoredDocument()==peer.authoredDocument())
  #expect(throws:(any Error).self){try RelayMarkNativeRichEditing.replaceDocument(document:doc,authoredAST:authored,expectedSnapshot:snapshot)}
  let updatedSnapshot=try doc.snapshot(),updatedState=try doc.encodeUpdate()
  var malformed=raw;malformed["blocks"]=[["id":"bad","type":"unsupported-rich-node","content":[]]]
  #expect(throws:(any Error).self){try RelayMarkNativeRichEditing.replaceDocument(document:doc,authoredAST:JSONSerialization.data(withJSONObject:malformed),expectedSnapshot:updatedSnapshot)}
  #expect(try doc.encodeUpdate()==updatedState)
  let undo=try #require(try doc.undoWithReference());try peer.applyUpdate(undo.update)
  #expect(try doc.authoredDocument()==original);#expect(try peer.authoredDocument()==original)
  let redo=try #require(try doc.redoWithReference());try peer.applyUpdate(redo.update)
  #expect(try doc.authoredDocument()==peer.authoredDocument())
  #expect(try JSONSerialization.jsonObject(with:doc.authoredDocument()) as? NSDictionary == raw as NSDictionary)
 }

 @Test @MainActor func sameDocumentNewManagerCannotRestoreAnotherHistoryNamespace() throws {
  let owner=UUID(),doc=RelayMarkNativeDocument(guid:"manager-owner",historyOwnerID:owner)
  try doc.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("Base",namespace:"manager-owner"))
  let operation=UUID()
  _ = try doc.performOwnedCommand(operationID:operation){try doc.insertText("!",at:4,path:[0,0])}
  #expect(try doc.ownedCommandGroup(operationID:operation).ownerID==owner)
  let state=try doc.exportHistoryState(scopeToken:"account/document/manager")
  let wrong=RelayMarkNativeDocument(guid:"manager-owner")
  try wrong.applyUpdate(RelayMarkNativeDocument.historyDocumentState(state))
  let original=try wrong.encodeUpdate(),originalHistory=try wrong.exportHistoryState(scopeToken:"account/document/manager")
  #expect(throws:(any Error).self){try wrong.restoreHistoryState(state,scopeToken:"account/document/manager")}
  #expect(try wrong.encodeUpdate()==original)
  #expect(try wrong.exportHistoryState(scopeToken:"account/document/manager")==originalHistory)
  let reopened=RelayMarkNativeDocument(guid:"manager-owner",historyOwnerID:owner)
  try reopened.applyUpdate(RelayMarkNativeDocument.historyDocumentState(state));try reopened.restoreHistoryState(state,scopeToken:"account/document/manager")
  #expect(try reopened.undoWithReference()?.ownerID==owner)
  #expect(try String(reopened.richProseProjection().text.characters)=="Base")
 }

 @Test @MainActor func removeLinkTypeEmitsEachAuthoredHrefWithoutDefaultAttributeGuessing() throws {
  let document=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
  try peer.applyUpdate(document.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("[A](https://one.example) [B](https://two.example)",namespace:"remove-links")))
  let maybeChange=try RelayMarkNativeRichEditing.format(document:document,range:NSRange(location:0,length:3),mark:"link",enabled:false,expectedSnapshot:document.snapshot())
  let change=try #require(maybeChange)
  let steps=try JSONSerialization.jsonObject(with:change.steps) as! [[String:Any]]
  #expect(steps.count==2)
  #expect(steps.map{$0["stepType"] as! String} == ["removeMark","removeMark"])
  #expect(steps.map{(($0["mark"] as! [String:Any])["attrs"] as! [String:Any])["href"] as! String} == ["https://one.example","https://two.example"])
  #expect(steps.map{$0["from"] as! Int} == [1,3]);#expect(steps.map{$0["to"] as! Int} == [2,4])
  try peer.applyUpdate(change.update)
  let undoValue=try document.undo();let undo=try #require(undoValue);try peer.applyUpdate(undo)
  #expect(try document.authoredDocument()==peer.authoredDocument())
 }

 @Test @MainActor func actualRichMarkStepPreservesUnicodeItemsAndPeerChoice() throws {
  let document=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
  let source="<!-- relay:question id=\"q-one\" type=\"multiple_choice\" -->\nA🌍Z\n- ( ) Paris\n<!-- /relay:question -->"
  try peer.applyUpdate(document.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument(source,namespace:"format-choice")))
  let items=try document.captureTextItems(path:[0,0,0],start:0,length:4)
  let before=try document.captureSenderSnapshot()
  let observation=try document.captureContentEditObservation()
  let maybeChange=try RelayMarkNativeRichEditing.format(document:document,range:NSRange(location:1,length:2),mark:"bold",enabled:true,expectedSnapshot:document.snapshot())
  let change=try #require(maybeChange)
  #expect(change.beforeSnapshot == before)
  let formatProof=try JSONSerialization.jsonObject(with:document.buildContentEditWitness(observation,steps:change.steps,update:change.update)) as! [String:Any]
  #expect(((formatProof["text_items"] as! [String:Any])["runs"] as! [Any]).isEmpty)
  #expect((formatProof["proven_copies"] as! [Any]).isEmpty)
  let steps=try JSONSerialization.jsonObject(with:change.steps) as! [[String:Any]]
  #expect(steps as NSArray == [["stepType":"addMark","from":3,"to":5,"mark":["type":"bold"]]] as NSArray)
  try peer.applyUpdate(change.update)
  #expect(try document.captureTextItems(path:[0,0,0],start:0,length:4)==items)
  let remote=try RelayMarkNativeRichEditing.replace(document:peer,range:NSRange(location:5,length:0),runs:[("Peer ",[:])],expectedSnapshot:peer.snapshot())
  try document.applyUpdate(remote.update)
  let maybeUndo=try document.undo();let undo=try #require(maybeUndo);try peer.applyUpdate(undo)
  #expect(String(try document.richProseProjection().text.characters)=="A🌍Z\nPeer Paris")
  #expect(try document.authoredDocument()==peer.authoredDocument())
  let maybeRemove=try RelayMarkNativeRichEditing.format(document:peer,range:NSRange(location:1,length:2),mark:"italic",enabled:true,expectedSnapshot:peer.snapshot())
  let remove=try #require(maybeRemove)
  try document.applyUpdate(remove.update)
  let maybeUnmark=try RelayMarkNativeRichEditing.format(document:document,range:NSRange(location:1,length:2),mark:"italic",enabled:false,expectedSnapshot:document.snapshot())
  let unmark=try #require(maybeUnmark)
  let removed=try JSONSerialization.jsonObject(with:unmark.steps) as! [[String:Any]]
  #expect(removed as NSArray == [["stepType":"removeMark","from":3,"to":5,"mark":["type":"italic"]]] as NSArray)
  #expect(try RelayMarkNativeRichEditing.format(document:document,range:NSRange(location:1,length:2),mark:"italic",enabled:false,expectedSnapshot:document.snapshot())==nil)
 }

 @Test @MainActor func addingRichChoiceValidatesTheActualQuestionAndKeepsExistingPeerItems() throws {
  let document=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
  let source="<!-- relay:question id=\"q-one\" type=\"multiple_choice\" -->\nCapital?\n- ( ) Paris\n<!-- /relay:question -->"
  let seed=try document.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument(source,namespace:"add-choice"));try peer.applyUpdate(seed)
  let retained=try document.captureTextItems(path:[0,1,0],start:0,length:5)
  let option:[String:Any] = ["id":"b11111111111141118111111111111111","type":"relay.form_option",
      "props":["id":"london","correct":false,"points":NSNull(),"settings":[:]],
      "content":[["type":"strong","content":[["type":"text","text":"London"]]]]]
  let update=try RelayMarkNativeWidgetMutation.insert(document:document,parentPath:[0],at:2,
      authoredBlock:JSONSerialization.data(withJSONObject:option),expectedSnapshot:document.snapshot())
  let widgetSteps=try JSONSerialization.jsonObject(with:update.steps) as! [[String:Any]]
  #expect(widgetSteps.count==1 && widgetSteps[0]["stepType"] as? String == "replace")
  try peer.applyUpdate(update.update)
  #expect(try document.authoredDocument()==peer.authoredDocument())
  #expect(try document.captureTextItems(path:[0,1,0],start:0,length:5)==retained)
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
  let retained=try document.captureTextItems(path:[0,1,0],start:0,length:5)
  let update=try RelayMarkNativeWidgetMutation.remove(document:document,path:[0,2],expectedID:parts[2]["id"] as! String,expectedSnapshot:snapshot)
  let widgetSteps=try JSONSerialization.jsonObject(with:update.steps) as! [[String:Any]]
  #expect(widgetSteps.count==1 && widgetSteps[0]["stepType"] as? String == "replace")
  try peer.applyUpdate(update.update)
  #expect(try document.authoredDocument()==peer.authoredDocument())
  #expect(try document.captureTextItems(path:[0,1,0],start:0,length:5)==retained)
  #expect(String(try document.richProseProjection().text.characters)=="Capital?\nParis")
 }

}

extension RelayMarkNativeCanonicalMetadataTests {
 @Test @MainActor func actualRichReplacementExportsSenderSnapshotAndCompleteSteps() throws {
  let document=RelayMarkNativeDocument()
  try document.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("Hello world",namespace:"native-steps"))
  let before=try document.captureSenderSnapshot()
  let change=try RelayMarkNativeRichEditing.replace(document:document,range:NSRange(location:6,length:5),runs:[("peer",["bold":true]),("!",["italic":true])],expectedSnapshot:document.snapshot())
  #expect(change.beforeSnapshot == before)
  let steps=try JSONSerialization.jsonObject(with:change.steps) as! [[String:Any]]
  #expect(steps.count==1)
  #expect(steps[0]["stepType"] as? String == "replace")
  #expect(steps[0]["from"] as? Int == 7);#expect(steps[0]["to"] as? Int == 12)
  let content=(steps[0]["slice"] as! [String:Any])["content"] as! [[String:Any]]
  #expect(content[0]["text"] as? String == "peer")
  #expect((content[0]["marks"] as! [[String:Any]])[0]["type"] as? String == "bold")
  #expect(content[1]["text"] as? String == "!")
  #expect((content[1]["marks"] as! [[String:Any]])[0]["type"] as? String == "italic")
  #expect(String(try document.richProseProjection().text.characters)=="Hello peer!")
  let enter=try RelayMarkNativeRichEditing.replace(document:document,range:NSRange(location:3,length:0),runs:[("\n",[:])],expectedSnapshot:document.snapshot())
  let enterSteps=try JSONSerialization.jsonObject(with:enter.steps) as! [[String:Any]]
  #expect(enterSteps.contains{$0["stepType"] as? String == "replace"})
  #expect(String(try document.richProseProjection().text.characters)=="Hel\nlo peer!")
  let inserted=try RelayMarkNativeRichEditing.insertBlock(document:document,range:NSRange(location:0,length:0),block:["type":"paragraph","content":[["type":"text","text":"New"]]],placement:.insertContent,expectedSnapshot:document.snapshot())
  let insertedSteps=try JSONSerialization.jsonObject(with:inserted.steps) as! [[String:Any]]
  let repair=try #require(insertedSteps.first{$0["stepType"] as? String == "attr" && $0["attr"] as? String == "relaymarkId"})
  #expect(repair["value"] as? String != nil)
  let insertedProse=String(try document.richProseProjection().text.characters)
  #expect(insertedProse=="\nNew\nHel\nlo peer!")
 }
}
