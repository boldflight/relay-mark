import Foundation
import XCTest
import RelayMarkSwift
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

}
