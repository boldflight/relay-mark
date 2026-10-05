import Foundation
import XCTest
import RelayMarkSwift
import RelayMarkProseProjection
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeMaintainedCommandTests: XCTestCase {
    func testMaintainedReturnCapturesGeneratedSuffixAndRetainsPeerThroughOwnedUndo() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("- **A🌍Z**", namespace: "maintained-return"))
        try peer.applyUpdate(seed)
        let operationID = UUID(), observation = try document.captureContentEditObservation()
        var result: RelayMarkNativeRichReturn.Result!
        _ = try document.performOwnedCommand(operationID: operationID, separateHistoryItem: true) {
            result = try RelayMarkNativeRichReturn.apply(document: document, blockPath: [0,0,0], utf16Offset: 3, expectedSnapshot: document.snapshot())
            return result.change.update
        }
        let witness = try JSONSerialization.jsonObject(with: document.buildContentEditWitness(observation, steps: result.change.steps, update: result.change.update)) as! [String: Any]
        XCTAssertEqual(((witness["text_items"] as! [String: Any])["runs"] as! [Any]).count, 0)
        let copies = witness["proven_copies"] as! [[String: Any]]
        XCTAssertEqual(copies.reduce(0) { total, copy in total + ((copy["destination"] as! [String: Any])["runs"] as! [[String: Any]]).reduce(0) { $0 + ($1["count"] as! Int) } }, 1)
        try peer.applyUpdate(result.change.update)
        let peerChange = try RelayMarkNativeRichEditing.replace(document: peer, range: NSRange(location: 0, length: 0), runs: [("Peer ", [:])], expectedSnapshot: peer.snapshot())
        try document.applyUpdate(peerChange.update)
        let inverseObservation = try document.captureContentEditObservation()
        let inverse = try XCTUnwrap(document.undoWithReference())
        XCTAssertEqual(inverse.reference, operationID)
        let inverseWitness = try JSONSerialization.jsonObject(with: document.buildOwnedHistoryWitness(inverseObservation, effect: inverse)) as! [String: Any]
        XCTAssertEqual(((inverseWitness["text_items"] as! [String: Any])["runs"] as! [Any]).count, 0)
        try peer.applyUpdate(inverse.update)
        XCTAssertEqual(String(try document.richProseProjection().text.characters), "Peer A🌍Z")
        XCTAssertEqual(try peer.authoredDocument(), try document.authoredDocument())
    }

    func testMaintainedListSinkingClassifiesMovedMarkedTextAsCopies() throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("1. First\n2. **Second**", namespace: "maintained-indent"))
        let observation = try document.captureContentEditObservation()
        let change = try document.changeRichListDepth(paragraphPath: [0,1,0], change: .indent, expectedSnapshot: document.snapshot())
        let witness = try JSONSerialization.jsonObject(with: document.buildContentEditWitness(observation, steps: change.steps, update: change.update)) as! [String: Any]
        XCTAssertEqual(((witness["text_items"] as! [String: Any])["runs"] as! [Any]).count, 0)
        let copies = witness["proven_copies"] as! [[String: Any]]
        XCTAssertEqual(copies.reduce(0) { total, copy in total + ((copy["destination"] as! [String: Any])["runs"] as! [[String: Any]]).reduce(0) { $0 + ($1["count"] as! Int) } }, 6)
    }
    func testQuotedReturnRetainsActualStoredMarksForSubsequentTyping() throws {
        let document=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
        let seed=try document.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("> **Quoted 🌍 text**",namespace:"return-inherited-marks"))
        try peer.applyUpdate(seed)
        let returned=try RelayMarkNativeRichReturn.apply(document:document,blockPath:[0,0],utf16Offset:14,expectedSnapshot:document.snapshot())
        let marks=try XCTUnwrap(returned.change.storedMarks),attributes=try JSONSerialization.jsonObject(with:XCTUnwrap(returned.change.storedTextAttributes)) as! [String:Any]
        XCTAssertEqual(String(decoding:marks,as:UTF8.self),"[{\"type\":\"bold\"}]")
        XCTAssertEqual(Set(attributes.keys),["bold"])
        let typingStyle=try RelayMarkCollaborativeProse.attributedText(text:"Next Ω",attributes:XCTUnwrap(returned.change.storedTextAttributes))
        XCTAssertTrue(typingStyle.runs.allSatisfy { $0.inlinePresentationIntent?.contains(.stronglyEmphasized)==true })
        try peer.applyUpdate(returned.change.update)
        let caret=try XCTUnwrap(returned.change.caret),projection=try document.richProseProjection(),row=try XCTUnwrap(projection.blockPaths.firstIndex(of:caret.blockPath))
        let observation=try document.captureContentEditObservation()
        let typed=try RelayMarkNativeRichEditing.replace(document:document,range:NSRange(location:projection.blockRanges[row].location+caret.offset,length:0),runs:[("Next Ω",attributes)],expectedSnapshot:document.snapshot())
        let witness=try JSONSerialization.jsonObject(with:document.buildContentEditWitness(observation,steps:typed.steps,update:typed.update)) as! [String:Any]
        XCTAssertEqual(((witness["text_items"] as! [String:Any])["runs"] as! [[String:Any]]).reduce(0){$0+($1["count"] as! Int)},6)
        try peer.applyUpdate(typed.update)
        let ast=try RelayMarkNativeDocumentProjection.project(document:document)
        guard case .inline(let typedInline) = ast.blocks[0].childBlocks[1].content[0] else { return XCTFail("Next line must retain rich inline text") }
        XCTAssertEqual(typedInline.type,"strong");XCTAssertEqual(typedInline.content[0].text,"Next Ω")
        XCTAssertEqual(try document.snapshot(),try peer.snapshot())
    }

    func testRangedReturnDeletesOnlySelectedUnicodeBeforeTheActualSplitAndOwnedUndo() throws {
        let document=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
        let seed=try document.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("**A🌍Z**",namespace:"ranged-return"))
        try peer.applyUpdate(seed)
        let before=try document.snapshot(),observation=try document.captureContentEditObservation(),operationID=UUID()
        var returned:RelayMarkNativeRichReturn.Result!
        _=try document.performOwnedCommand(operationID:operationID,separateHistoryItem:true){
            returned=try RelayMarkNativeRichReturn.apply(document:document,blockPath:[0],utf16Offset:1,selectionEnd:.init(blockPath:[0],offset:3),expectedSnapshot:before)
            return returned.change.update
        }
        let witness=try JSONSerialization.jsonObject(with:document.buildContentEditWitness(observation,steps:returned.change.steps,update:returned.change.update)) as! [String:Any]
        XCTAssertEqual(((witness["text_items"] as! [String:Any])["runs"] as! [Any]).count,0)
        let copies=witness["proven_copies"] as! [[String:Any]]
        XCTAssertEqual(copies.reduce(0){$0+(($1["destination"] as! [String:Any])["runs"] as! [[String:Any]]).reduce(0){$0+($1["count"] as! Int)}},1)
        XCTAssertEqual(String(try document.richProseProjection().text.characters),"A\nZ")
        try peer.applyUpdate(returned.change.update)
        let inverse=try XCTUnwrap(document.undoWithReference());XCTAssertEqual(inverse.reference,operationID)
        try peer.applyUpdate(inverse.update)
        XCTAssertEqual(try document.snapshot(),before);XCTAssertEqual(try peer.snapshot(),before)
    }

    func testReturnAtCodeEndAddsLFInsideTheSameLanguageBlock() throws {
        let document=RelayMarkNativeDocument(),peer=RelayMarkNativeDocument()
        let source="````swift\nlet 🌍 = \"```\"\nprint(🌍)\n// tail\n````"
        let seed=try document.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument(source,namespace:"return-code-lf"))
        try peer.applyUpdate(seed)
        let before=try RelayMarkNativeDocumentProjection.project(document:document),projection=try document.richProseProjection()
        let observation=try document.captureContentEditObservation()
        let returned=try RelayMarkNativeRichReturn.apply(document:document,blockPath:[0],utf16Offset:projection.blockRanges[0].length,expectedSnapshot:document.snapshot())
        let witness=try JSONSerialization.jsonObject(with:document.buildContentEditWitness(observation,steps:returned.change.steps,update:returned.change.update)) as! [String:Any]
        XCTAssertEqual(((witness["text_items"] as! [String:Any])["runs"] as! [[String:Any]]).reduce(0){$0+($1["count"] as! Int)},1)
        let after=try RelayMarkNativeDocumentProjection.project(document:document)
        XCTAssertEqual(after.blocks.count,1);XCTAssertEqual(after.blocks[0].id,before.blocks[0].id)
        XCTAssertEqual(after.blocks[0].props["language"],before.blocks[0].props["language"])
        XCTAssertEqual(String(try document.richProseProjection().text.characters),String(projection.text.characters)+"\n")
        try peer.applyUpdate(returned.change.update);XCTAssertEqual(try document.snapshot(),try peer.snapshot())
    }

    func testSharedTypingLinkProjectionPreservesCanonicalHrefAndRefusesExecutableHref() throws {
        let document=RelayMarkNativeDocument()
        _=try document.initializeDocument(authoredAST:RelayMarkSourceCodec.parseDocument("[Label](https://example.com/path)",namespace:"typing-link-title"))
        let projection=try document.richProseProjection()
        XCTAssertTrue(projection.isEditable)
        XCTAssertEqual(projection.text.runs.first?.link?.absoluteString,"https://example.com/path")
        let attributes:[String:Any]=["link":["href":"https://example.com/path","target":"_blank","rel":"noopener noreferrer nofollow","class":NSNull(),"title":NSNull()],"italic":[:]]
        let styled=try RelayMarkCollaborativeProse.attributedText(text:"Label",attributes:JSONSerialization.data(withJSONObject:attributes))
        XCTAssertEqual(styled.runs.first?.link?.absoluteString,"https://example.com/path")
        XCTAssertTrue(styled.runs.allSatisfy{$0.inlinePresentationIntent?.contains(.emphasized)==true})
        var unsafe=attributes;var link=unsafe["link"] as! [String:Any];link["href"]="javascript:alert(1)";unsafe["link"]=link
        XCTAssertThrowsError(try RelayMarkCollaborativeProse.attributedText(text:"Unsafe",attributes:JSONSerialization.data(withJSONObject:unsafe)))
        XCTAssertThrowsError(try RelayMarkCollaborativeProse.attributedText(text:"Unknown",attributes:JSONSerialization.data(withJSONObject:["unknown":[:]])))
    }

    func testFullLinkPropertiesSurviveNativeEditCheckpointAndRender() throws {
        var ast = try JSONSerialization.jsonObject(with: RelayMarkSourceCodec.parseDocument("[Label](https://example.com/path \"Tooltip 🌍\")", namespace: "native-link-properties")) as! [String: Any]
        var blocks = ast["blocks"] as! [[String: Any]], content = blocks[0]["content"] as! [[String: Any]]
        XCTAssertEqual(content[0]["props"] as? [String: String], ["title": "Tooltip 🌍"])
        let props = ["title": "Tooltip \"quoted\" 🌍", "target": "_self", "rel": "author nofollow", "class": "paper-link cited"]
        content[0]["props"] = props; blocks[0]["content"] = content; ast["blocks"] = blocks
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: JSONSerialization.data(withJSONObject: ast)); try peer.applyUpdate(seed)
        let attrs: [String: Any] = ["link": props.merging(["href": "https://example.com/path"]) { _, new in new }]
        let observation = try document.captureContentEditObservation()
        let change = try RelayMarkNativeRichEditing.replace(document: document, range: NSRange(location: 0, length: 5), runs: [("Edited 🌍", attrs)], expectedSnapshot: document.snapshot())
        let witness = try JSONSerialization.jsonObject(with: document.buildContentEditWitness(observation, steps: change.steps, update: change.update)) as! [String: Any]
        XCTAssertEqual(((witness["text_items"] as! [String: Any])["runs"] as! [[String: Any]]).reduce(0) { $0 + ($1["count"] as! Int) }, 9)
        try peer.applyUpdate(change.update)
        let reopened = RelayMarkNativeDocument(); try reopened.applyUpdate(document.encodeUpdate())
        let final = try RelayMarkNativeDocumentProjection.project(document: reopened)
        guard case .inline(let link) = final.blocks[0].content[0] else { return XCTFail("Link must remain authored") }
        XCTAssertEqual(link.props, props.mapValues(RelayMarkValue.string)); XCTAssertEqual(link.plainText, "Edited 🌍")
        XCTAssertEqual(final, try RelayMarkNativeDocumentProjection.project(document: peer))
        let encoded = try document.authoredDocument()
        XCTAssertTrue(try RelayMarkSourceCodec.renderDocument(encoded).contains("title=\"Tooltip &quot;quoted&quot; 🌍\""))
        XCTAssertEqual(try reopened.richProseProjection().text.runs.first?.link?.absoluteString, "https://example.com/path")
    }

}
