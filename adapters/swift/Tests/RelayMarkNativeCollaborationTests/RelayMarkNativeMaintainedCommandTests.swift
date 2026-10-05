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
}
