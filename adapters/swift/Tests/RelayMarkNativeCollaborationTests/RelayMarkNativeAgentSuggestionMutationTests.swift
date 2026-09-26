import Foundation
import XCTest
import RelayMarkCollaboration
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeAgentSuggestionMutationTests: XCTestCase {
    private let id = "b00000000000040008000000000000082"

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "agent-suggestion-v3-draft", withExtension: "json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(object["update"] as? String)))
    }

    private func dismiss(_ document: RelayMarkNativeDocument, index: Int = 1,
                         review: String = "ready", confidence: Double? = 0.88) throws -> Data {
        try RelayMarkNativeAgentSuggestionMutation.dismiss(
            document: document, atRootIndex: index, expectedID: id,
            expectedReview: review, expectedKind: "note",
            expectedConfidence: confidence, expectedEvidence: [],
            expectedContent: "Check **this** source.")
    }

    func testDismissReplaysAndOneUndoRestoresSuggestionBetweenAdjacentProse() throws {
        let update = try fixture()
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        try native.applyUpdate(update)
        try peer.applyUpdate(update)
        try browser.applyUpdate(update)

        let before = try native.snapshot()
        let removed = try dismiss(native)
        try peer.applyUpdate(removed)
        try browser.applyUpdate(removed)
        XCTAssertEqual(try native.snapshot(), try peer.snapshot())
        XCTAssertEqual(try native.markdownV3ProseProjection().suggestionAtoms, [])
        XCTAssertEqual(String(try native.markdownV3ProseProjection().text.characters), "Before\nAfter")
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native))

        let restored = try XCTUnwrap(native.undo())
        try peer.applyUpdate(restored)
        try browser.applyUpdate(restored)
        XCTAssertEqual(try native.snapshot(), before)
        XCTAssertEqual(try peer.snapshot(), before)
        XCTAssertEqual(try native.markdownV3ProseProjection().suggestionAtoms.first?.id, id)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native))
    }

    func testStaleSelectionAndChangedAuthoredStateDoNotMutate() throws {
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(fixture())
        let before = try native.encodeUpdate()
        XCTAssertThrowsError(try dismiss(native, index: 0))
        XCTAssertThrowsError(try dismiss(native, review: "draft"))
        XCTAssertThrowsError(try dismiss(native, confidence: nil))
        XCTAssertEqual(try native.encodeUpdate(), before)

        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(before)
        _ = try dismiss(peer)
        try native.applyUpdate(peer.encodeUpdate())
        let afterPeer = try native.encodeUpdate()
        XCTAssertThrowsError(try dismiss(native))
        XCTAssertEqual(try native.encodeUpdate(), afterPeer)
    }
}
