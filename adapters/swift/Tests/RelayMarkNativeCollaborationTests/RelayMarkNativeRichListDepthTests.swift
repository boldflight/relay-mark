import Foundation
import XCTest
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeRichListDepthTests: XCTestCase {
    private func seed() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "list-operations-v3", withExtension: "json"))
        let fixtures = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let fixture = try XCTUnwrap(fixtures["interior_flat_ordered"] as? [String: Any])
        return try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String)))
    }

    func testIndentAndOutdentReplayBrowserMarksAndUndoAsSeparateSteps() throws {
        let source = try seed(), native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(source)
        try peer.applyUpdate(source)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let originalText = try native.richProseProjection().text
        XCTAssertFalse(native.canChangeRichListDepth(paragraphPath: [0, 0, 0], change: .indent))
        let indent = try native.changeRichListDepth(paragraphPath: [0, 1, 0], change: .indent,
                                                         expectedSnapshot: native.snapshot())
        try peer.applyUpdate(indent)
        let nested = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(nested, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(String(try native.richProseProjection().text.characters), String(originalText.characters))
        XCTAssertEqual(nested.blocks[0].childBlocks.count, 1)
        XCTAssertEqual(nested.blocks[0].childBlocks[0].childBlocks[1].props["start"]?.numberValue, 1)
        XCTAssertEqual(nested.blocks[0].childBlocks[0].childBlocks[1].childBlocks[0], before.blocks[0].childBlocks[1])
        let outdent = try native.changeRichListDepth(paragraphPath: [0, 0, 1, 0, 0], change: .outdent,
                                                          expectedSnapshot: native.snapshot())
        try peer.applyUpdate(outdent)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), nested)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), nested)
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)
    }

    func testTopLevelOutdentKeepsParagraphIdentityAndMarkedContent() throws {
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument(), source = try seed()
        try native.applyUpdate(source)
        try peer.applyUpdate(source)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let update = try native.changeRichListDepth(paragraphPath: [0, 1, 0], change: .outdent,
                                                         expectedSnapshot: native.snapshot())
        try peer.applyUpdate(update)
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(after, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(after.blocks.map(\.type), ["list", "paragraph"])
        XCTAssertEqual(after.blocks[0].id, before.blocks[0].id)
        XCTAssertEqual(after.blocks[1], before.blocks[0].childBlocks[1].childBlocks[0])
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)
    }
}
