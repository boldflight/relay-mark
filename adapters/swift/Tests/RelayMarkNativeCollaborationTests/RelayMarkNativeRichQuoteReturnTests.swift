import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeRichQuoteReturnTests: XCTestCase {
    private func seed() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "markdown-blocks-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
    }

    func testQuoteEndReturnAndEmptyExitReplayAndUndoWithoutLosingIDs() throws {
        let source = try seed()
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(source)
        try peer.applyUpdate(source)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let quote = before.blocks[2]
        let lastParagraphID = quote.childBlocks[1].id
        let paragraph = try native.anchor(path: [2, 1], index: 0)
        let snapshot = try native.snapshot()
        let first = try native.returnInRichQuote(at: paragraph, utf16Offset: 12,
                                                        expectedSnapshot: snapshot)
        XCTAssertEqual(first.kind, .append)
        try peer.applyUpdate(first.update)
        var after = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(after, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(after.blocks[2].id, quote.id)
        XCTAssertEqual(after.blocks[2].childBlocks.map(\.id),
                       quote.childBlocks.map(\.id) + [first.paragraphID])
        XCTAssertEqual(after.blocks[2].childBlocks.last?.plainText, "")

        let empty = try native.anchor(path: [2, 2], index: 0)
        let second = try native.returnInRichQuote(at: empty, utf16Offset: 0,
                                                         expectedSnapshot: native.snapshot())
        XCTAssertEqual(second.kind, .exit)
        XCTAssertEqual(second.paragraphID, first.paragraphID)
        try peer.applyUpdate(second.update)
        after = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(after, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(after.blocks[2].childBlocks.map(\.id), [quote.childBlocks[0].id, lastParagraphID])
        XCTAssertEqual(after.blocks[3].id, first.paragraphID)
        XCTAssertEqual(after.blocks[3].type, "paragraph")
        XCTAssertThrowsError(try native.returnInRichQuote(at: empty, utf16Offset: 0,
                                                                  expectedSnapshot: snapshot))
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)
    }

    func testQuoteInteriorReturnPreservesTheOriginalParagraphIDAndPeerText() throws {
        let source = try seed()
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(source)
        try peer.applyUpdate(source)
        let bold = try native.formatText(at: 0, length: 11, attributes: ["bold": [:]], path: [2, 0, 0])
        try peer.applyUpdate(bold)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let paragraph = try native.anchor(path: [2, 0], index: 0)
        let checkpoint = try native.encodeUpdate()
        XCTAssertThrowsError(try native.returnInRichQuote(at: paragraph, utf16Offset: 99,
                                                                  expectedSnapshot: native.snapshot()))
        XCTAssertThrowsError(try native.returnInRichQuote(at: paragraph, utf16Offset: 5,
                                                                  expectedSnapshot: Data()))
        XCTAssertEqual(try native.encodeUpdate(), checkpoint)
        let change = try native.returnInRichQuote(at: paragraph, utf16Offset: 5,
                                                         expectedSnapshot: native.snapshot())
        XCTAssertEqual(change.kind, .split)
        try peer.applyUpdate(change.update)
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(after, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(after.blocks[2].childBlocks.map(\.id),
                       [before.blocks[2].childBlocks[0].id, change.paragraphID, before.blocks[2].childBlocks[1].id])
        XCTAssertEqual(after.blocks[2].childBlocks.map(\.plainText), ["First", " quote", "Second quote"])
        if case .inline(let prefix)? = after.blocks[2].childBlocks[0].content.first,
           case .inline(let suffix)? = after.blocks[2].childBlocks[1].content.first {
            XCTAssertEqual(prefix.type, "strong")
            XCTAssertEqual(suffix.type, "strong")
        } else { XCTFail("Quote split lost its inline mark") }
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)
    }
}
