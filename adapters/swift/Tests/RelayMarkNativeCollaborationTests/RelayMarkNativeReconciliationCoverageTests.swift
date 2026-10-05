import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeReconciliationCoverageTests: XCTestCase {
    private func coverage(_ local: RelayMarkNativeDocument, _ server: RelayMarkNativeDocument) throws -> [String: Any] {
        let serverVector = server.stateVector()
        let outgoing = try local.encodeUpdate(since: serverVector)
        let delta = try server.encodeUpdate(since: local.stateVector())
        return try JSONSerialization.jsonObject(with: RelayMarkSourceCodec.reconciliationCoverage(
            localFootprint: local.captureUpdateFootprint(outgoing), serverFootprint: local.captureUpdateFootprint(delta),
            serverStateVector: serverVector)) as! [String: Any]
    }

    func testAcknowledgedDeletionReopensWithoutUnexplainedOutgoingWork() throws {
        let local = RelayMarkNativeDocument(), server = RelayMarkNativeDocument()
        let seed = try local.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("A🌍Z", namespace: "native-ack-delete"))
        try server.applyUpdate(seed)
        let deleted = try RelayMarkNativeRichEditing.replace(document: local, range: NSRange(location: 1, length: 2), runs: [], expectedSnapshot: local.snapshot())
        try server.applyUpdate(deleted.update)
        let checkpoint = try local.encodeUpdate(), reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(checkpoint)
        let vector = reopened.stateVector(), outgoing = try reopened.encodeUpdate(since: server.stateVector())
        XCTAssertNotEqual(outgoing, Data([0,0]))
        let original = try JSONSerialization.jsonObject(with: reopened.captureUpdateFootprint(outgoing)) as! [String: Any]
        XCTAssertEqual((original["structs"] as! [Any]).count, 0)
        XCTAssertFalse((original["declared_deletes"] as! [Any]).isEmpty)
        let result = try coverage(reopened, server)
        XCTAssertEqual(result["covered"] as? Bool, true)
        XCTAssertEqual((result["uncovered_structs"] as! [Any]).count, 0)
        XCTAssertEqual((result["uncovered_deletes"] as! [Any]).count, 0)
        XCTAssertEqual(try reopened.encodeUpdate(), checkpoint)
        XCTAssertEqual(reopened.stateVector(), vector)
        XCTAssertEqual(String(try reopened.richProseProjection().text.characters), "AZ")
    }

    func testLocalObservedClocksAndDeletesNeverAcknowledgeUnsentWork() throws {
        let local = RelayMarkNativeDocument(), server = RelayMarkNativeDocument()
        let seed = try local.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("A🌍Z", namespace: "native-unsent-delete"))
        try server.applyUpdate(seed)
        let deleted = try RelayMarkNativeRichEditing.replace(document: local, range: NSRange(location: 1, length: 2), runs: [], expectedSnapshot: local.snapshot())
        let deletionResult = try coverage(local, server)
        XCTAssertEqual(deletionResult["covered"] as? Bool, false)
        XCTAssertEqual((deletionResult["uncovered_structs"] as! [Any]).count, 0)
        XCTAssertEqual((deletionResult["uncovered_deletes"] as! [[String: Any]]).reduce(0) { $0 + ($1["count"] as! Int) }, 2)
        try server.applyUpdate(deleted.update)
        let serverVector = server.stateVector()
        _ = try RelayMarkNativeRichEditing.replace(document: local, range: NSRange(location: 0, length: 0), runs: [("N", [:])], expectedSnapshot: local.snapshot())
        let insertionResult = try coverage(local, server)
        XCTAssertEqual(insertionResult["covered"] as? Bool, false)
        XCTAssertEqual((insertionResult["uncovered_structs"] as! [[String: Any]]).reduce(0) { $0 + ($1["count"] as! Int) }, 1)
        XCTAssertEqual((insertionResult["uncovered_deletes"] as! [Any]).count, 0)
        let outgoing = try local.captureUpdateFootprint(local.encodeUpdate(since: serverVector))
        let delta = try local.captureUpdateFootprint(server.encodeUpdate(since: local.stateVector()))
        XCTAssertThrowsError(try RelayMarkSourceCodec.reconciliationCoverage(localFootprint: outgoing,
            serverFootprint: delta, serverStateVector: serverVector + Data([0])))
    }
}
