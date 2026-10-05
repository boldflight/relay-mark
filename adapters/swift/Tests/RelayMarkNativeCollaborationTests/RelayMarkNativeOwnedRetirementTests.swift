import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeOwnedRetirementTests: XCTestCase {
    func testWholeRetirementReopensSurvivorAcrossSharedParentRedoneAndFreshCommand() throws {
        let seed = RelayMarkNativeDocument()
        _ = try seed.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("A🌍Z", namespace: "retirement-seed"))
        let owner = UUID(), doc = RelayMarkNativeDocument(guid: "owned-retirement", historyOwnerID: owner)
        try doc.applyUpdate(seed.encodeUpdate())
        let first = UUID(), second = UUID(), third = UUID()
        func deletion(_ id: UUID, _ length: Int) throws -> RelayMarkNativeDocument.OwnedCommandGroup {
            _ = try doc.performOwnedCommand(operationID: id, separateHistoryItem: true) {
                try RelayMarkNativeRichEditing.replace(document: doc, range: NSRange(location: 0, length: length), runs: [], expectedSnapshot: doc.snapshot()).update
            }
            return try doc.ownedCommandGroup(operationID: id)
        }
        let old = try deletion(first, 1)
        _ = try deletion(second, 2)
        XCTAssertNotNil(try doc.undoWithReference()); XCTAssertNotNil(try doc.redoWithReference())
        let oldRedo = try deletion(third, 1)
        XCTAssertNotNil(try doc.undoWithReference())
        let before = try doc.encodeUpdate(), archive = try doc.exportHistoryState(scopeToken: "current-account/document/incarnation/owner")
        XCTAssertThrowsError(try doc.retireOwnedHistoryGroups([old, old]))
        XCTAssertThrowsError(try doc.retireOwnedHistoryGroups([.init(ownerID: UUID(), reference: old.reference, operationIDs: old.operationIDs)]))
        XCTAssertThrowsError(try doc.retireOwnedHistoryGroups([.init(ownerID: owner, reference: old.reference, operationIDs: [first, second])]))
        XCTAssertEqual(try doc.encodeUpdate(), before)
        XCTAssertEqual(try doc.exportHistoryState(scopeToken: "current-account/document/incarnation/owner"), archive)
        let counts = try doc.retireOwnedHistoryGroups([old, oldRedo])
        XCTAssertEqual(counts.undo, 1); XCTAssertEqual(counts.redo, 1)
        XCTAssertEqual(try doc.encodeUpdate(), before)
        let after = try doc.exportHistoryState(scopeToken: "current-account/document/incarnation/owner")
        let reopened = RelayMarkNativeDocument(guid: doc.documentGUID, historyOwnerID: owner)
        try reopened.applyUpdate(RelayMarkNativeDocument.historyDocumentState(after))
        try reopened.restoreHistoryState(after, scopeToken: "current-account/document/incarnation/owner")
        XCTAssertEqual(try reopened.undoWithReference()?.reference, second)
        XCTAssertEqual(String(try reopened.richProseProjection().text.characters), "🌍Z")
        XCTAssertEqual(try reopened.redoWithReference()?.reference, second)
        XCTAssertEqual(String(try reopened.richProseProjection().text.characters), "Z")
        XCTAssertNotNil(try reopened.undoWithReference()); XCTAssertNil(try reopened.undoWithReference())
        let fresh = UUID()
        _ = try reopened.performOwnedCommand(operationID: fresh) {
            try RelayMarkNativeRichEditing.replace(document: reopened, range: NSRange(location: 3, length: 0), runs: [("Ω", [:])], expectedSnapshot: reopened.snapshot()).update
        }
        XCTAssertEqual(try reopened.ownedCommandGroup(operationID: fresh).reference, fresh)
        XCTAssertNotNil(try reopened.undoWithReference())
        XCTAssertEqual(String(try reopened.richProseProjection().text.characters), "🌍Z")
    }
}
