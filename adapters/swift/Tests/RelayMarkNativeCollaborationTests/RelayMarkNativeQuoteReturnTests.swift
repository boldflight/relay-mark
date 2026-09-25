import Foundation
import XCTest
import RelayMarkCollaboration
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeQuoteReturnTests: XCTestCase {
    func testBrowserEndReturnTypingAnchorsUndoAndReopen() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "quote-return-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(fixture["seed"] as? String)))
        let doc = RelayMarkNativeDocument(); try doc.applyUpdate(seed)
        let original = try doc.snapshot(), paragraph = try doc.anchor(path: [0, 0], index: 0)
        let text = try doc.anchor(path: [0, 0, 0], index: 12)
        let append = try doc.appendEmptyQuoteParagraph(after: paragraph)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: doc.snapshot()) as? NSDictionary, fixture["afterReturn"] as? NSDictionary)
        XCTAssertTrue(doc.supportsQuoteEditing())
        let empty = try doc.snapshot()
        let typed = try doc.replaceQuoteText(start: 15, end: 15, text: "Next Ω")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: doc.snapshot()) as? NSDictionary, fixture["after"] as? NSDictionary)
        XCTAssertEqual(try doc.resolve(anchor: paragraph)?.path, [0, 0])
        XCTAssertEqual(try doc.resolve(anchor: text)?.index, 12)
        _ = try XCTUnwrap(doc.undo()); XCTAssertEqual(try doc.snapshot(), empty)
        _ = try XCTUnwrap(doc.undo()); XCTAssertEqual(try doc.snapshot(), original)
        _ = try XCTUnwrap(doc.redo()); _ = try XCTUnwrap(doc.redo())
        let peer = try RelayMarkCollaborationDocument(); try peer.applyUpdate(seed)
        try peer.applyUpdate(append); try peer.applyUpdate(typed)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: peer.snapshot()) as? NSDictionary, fixture["after"] as? NSDictionary)
        let reopened = RelayMarkNativeDocument(); try reopened.applyUpdate(doc.encodeUpdate())
        XCTAssertTrue(reopened.supportsQuoteEditing()); XCTAssertEqual(try reopened.snapshot(), try doc.snapshot())
        _ = try doc.replaceQuoteText(start: 21, end: 21, text: "!")
        XCTAssertEqual(try doc.proseProjection().text.runs.last?.inlinePresentationIntent, .stronglyEmphasized)
        _ = try doc.replaceQuoteText(start: 15, end: 22, text: "")
        _ = try doc.replaceQuoteText(start: 15, end: 15, text: "Retyped")
        XCTAssertEqual(try doc.proseProjection().text.runs.last?.inlinePresentationIntent, .stronglyEmphasized)
        let before = try doc.encodeUpdate()
        XCTAssertThrowsError(try doc.appendEmptyQuoteParagraph(after: paragraph))
        XCTAssertThrowsError(try doc.replaceQuoteText(start: 13, end: 16, text: "x"))
        XCTAssertThrowsError(try doc.replaceQuoteText(start: 16, end: 16, text: "\n"))
        XCTAssertEqual(try doc.encodeUpdate(), before)
    }
}
