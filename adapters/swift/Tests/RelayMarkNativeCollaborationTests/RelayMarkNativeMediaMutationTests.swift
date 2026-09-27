import Foundation
import XCTest
import RelayMarkCollaboration
import RelayMarkProseProjection
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeMediaMutationTests: XCTestCase {
    private func update(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
    }

    func testImageRemoveInsertAndUndoReplayWithoutChangingNeighborBlocks() throws {
        let seed = try update("rich-image-v3-draft")
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        for replica in [native, peer] { try replica.applyUpdate(seed) }
        try browser.applyUpdate(seed)
        let original = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        let media = try XCTUnwrap(native.markdownV3ProseProjection().mediaAtoms.first)
        let beforeID = "bc5e20755a10547d08d9054f33618c548"
        let afterID = "b29908e62e7c2496580e5aea7bb8e4f14"

        let removed = try RelayMarkNativeMediaMutation.remove(document: native, atRootIndex: 1,
            expectedID: media.id, expectedSource: media.source)
        try peer.applyUpdate(removed)
        try browser.applyUpdate(removed)
        XCTAssertTrue(try native.markdownV3ProseProjection().isEditable)
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native))

        let inserted = try RelayMarkNativeMediaMutation.insert(document: native, atRootIndex: 1,
            expectedPreviousID: beforeID, expectedNextID: afterID,
            block: .init(id: media.id, kind: .image, source: media.source,
                         alt: media.alt, title: media.title))
        try peer.applyUpdate(inserted)
        try browser.applyUpdate(inserted)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), original)
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()), original)
        XCTAssertTrue(try native.markdownV3ProseProjection().isEditable)

        let undone = try XCTUnwrap(native.undo())
        try peer.applyUpdate(undone)
        try browser.applyUpdate(undone)
        XCTAssertTrue(try native.markdownV3ProseProjection().isEditable)
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native))
    }

    func testVideoIdentityAndInvalidMediaAreRejectedBeforeMutation() throws {
        let seed = try update("rich-video-v3-draft")
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        for replica in [native, peer] { try replica.applyUpdate(seed) }
        let media = try XCTUnwrap(native.markdownV3ProseProjection().mediaAtoms.first)
        let original = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        let checkpoint = try native.encodeUpdate()
        XCTAssertThrowsError(try RelayMarkNativeMediaMutation.remove(document: native, atRootIndex: 1,
            expectedID: media.id, expectedSource: "another-video"))
        XCTAssertEqual(try native.encodeUpdate(), checkpoint)

        let removed = try RelayMarkNativeMediaMutation.remove(document: native, atRootIndex: 1,
            expectedID: media.id, expectedSource: media.source)
        try peer.applyUpdate(removed)
        let afterRemove = try native.encodeUpdate()
        let beforeID = "bc5e20755a10547d08d9054f33618c548"
        let afterID = "b29908e62e7c2496580e5aea7bb8e4f14"
        for block in [
            RelayMarkNativeMediaMutation.Block(id: media.id, kind: .videoEmbed, source: "../private"),
            .init(id: media.id, kind: .videoEmbed, source: media.source, alt: "hidden"),
            .init(id: beforeID, kind: .videoEmbed, source: media.source),
            .init(id: media.id, kind: .image, source: "blob:preview")
        ] {
            XCTAssertThrowsError(try RelayMarkNativeMediaMutation.insert(document: native,
                atRootIndex: 1, expectedPreviousID: beforeID, expectedNextID: afterID, block: block))
            XCTAssertEqual(try native.encodeUpdate(), afterRemove)
        }
        XCTAssertThrowsError(try RelayMarkNativeMediaMutation.insert(document: native,
            atRootIndex: 1, expectedPreviousID: afterID, expectedNextID: beforeID,
            block: .init(id: media.id, kind: .videoEmbed, source: media.source)))
        XCTAssertEqual(try native.encodeUpdate(), afterRemove)

        let inserted = try RelayMarkNativeMediaMutation.insert(document: native, atRootIndex: 1,
            expectedPreviousID: beforeID, expectedNextID: afterID,
            block: .init(id: media.id, kind: .videoEmbed, source: media.source))
        try peer.applyUpdate(inserted)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), original)
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
    }

    func testAdjacentTextAndSecondImageReplayWithoutReplacingEitherMediaAtom() throws {
        let seed = try update("rich-image-v3-draft")
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        for replica in [native, peer] { try replica.applyUpdate(seed) }
        try browser.applyUpdate(seed)
        let first = try XCTUnwrap(native.markdownV3ProseProjection().mediaAtoms.first)
        XCTAssertTrue(try native.markdownV3ProseProjection().isEditable)

        let proseUpdate = try RelayMarkNativeMarkdownV3TextMutation.replace(
            document: native, path: [0, 0], start: 12, end: 12, text: " together")
        try peer.applyUpdate(proseUpdate)
        try browser.applyUpdate(proseUpdate)
        let secondID = "b" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let added = try RelayMarkNativeMediaMutation.insert(document: native, atRootIndex: 2,
            expectedPreviousID: first.id, expectedNextID: "b29908e62e7c2496580e5aea7bb8e4f14",
            block: .init(id: secondID, kind: .image, source: "https://images.example.org/second.png"))
        try peer.applyUpdate(added)
        try browser.applyUpdate(added)
        XCTAssertEqual(try native.markdownV3ProseProjection().mediaAtoms.count, 2)
        let checkpoint = try native.encodeUpdate()
        XCTAssertThrowsError(try RelayMarkNativeMarkdownV3TextMutation.replace(
            document: native, path: [1], start: 0, end: 1, text: "lost"))
        XCTAssertEqual(try native.encodeUpdate(), checkpoint)

        let removed = try RelayMarkNativeMediaMutation.remove(document: native, atRootIndex: 1,
            expectedID: first.id, expectedSource: first.source)
        try peer.applyUpdate(removed)
        try browser.applyUpdate(removed)
        let final = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        XCTAssertEqual(final.blocks[0].plainText, "Before image together")
        XCTAssertEqual(try native.markdownV3ProseProjection().mediaAtoms.map(\.id), [secondID])
        XCTAssertEqual(final, try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer))
        XCTAssertEqual(final, try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()))
    }
}
