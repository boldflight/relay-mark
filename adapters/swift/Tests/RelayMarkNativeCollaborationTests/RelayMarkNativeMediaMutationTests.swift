import Foundation
import XCTest
import RelayMarkCollaboration
import RelayMarkProseProjection
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeMediaMutationTests: XCTestCase {
    private func update(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let original = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        guard name == "rich-video-v3-draft" else { return original }
        // Original archive stays unchanged; this operation starts after the
        // finite importer removes recorded presentation-only default attrs.
        let retained = RelayMarkNativeDocument()
        try retained.applyUpdate(original)
        let prepared = try RelayMarkNativeSnapshotImport.prepare(document: retained,
            namespace: "retained-media-commands", expectedSnapshot: retained.snapshot())
        _ = try RelayMarkNativeSnapshotImport.install(document: retained, prepared: prepared)
        return try retained.encodeUpdate()
    }

    func testImageDimensionsEditInPlacePreservesPeerFieldsAndRejectsStaleOrUnsafeChanges() throws {
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let source = "Before **🌍**\n\n![Original](https://example.test/image.png \"Caption\")\n\nAfter Ω"
        let seed = try native.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "media-properties"))
        try peer.applyUpdate(seed)
        let media = try XCTUnwrap(native.richProseProjection().mediaAtoms.first)
        let neighborAnchor = try native.anchor(path: [0, 0], index: 3)

        let peerAlt = try RelayMarkNativeWidgetMutation.updateAttributes(document: peer,
            path: media.path, expectedID: media.id,
            expected: JSONSerialization.data(withJSONObject: ["alt": "Original"]),
            changes: JSONSerialization.data(withJSONObject: ["alt": "Peer 🌍"]), expectedMediaSource: media.source)
        try native.applyUpdate(peerAlt.update)
        let change = try native.editorCommand(separateUndoItem: true) {
            try RelayMarkNativeWidgetMutation.updateAttributes(document: native,
                path: media.path, expectedID: media.id,
                expected: JSONSerialization.data(withJSONObject: ["width": NSNull(), "height": NSNull()]),
                changes: JSONSerialization.data(withJSONObject: ["width": 320, "height": 240]), expectedMediaSource: media.source)
        }
        try peer.applyUpdate(change.update)
        XCTAssertEqual(try peer.authoredDocument(), try native.authoredDocument())
        let changed = try XCTUnwrap(native.richProseProjection().mediaAtoms.first)
        XCTAssertEqual(changed.width, 320); XCTAssertEqual(changed.height, 240)
        XCTAssertEqual(changed.alt, "Peer 🌍"); XCTAssertEqual(changed.title, "Caption")
        XCTAssertEqual(changed.id, media.id); XCTAssertEqual(changed.source, media.source)
        XCTAssertEqual(try native.resolve(anchor: neighborAnchor)?.path, [0, 0])

        _ = try XCTUnwrap(native.undo())
        XCTAssertNil(try native.richProseProjection().mediaAtoms.first?.width)
        XCTAssertEqual(try native.richProseProjection().mediaAtoms.first?.alt, "Peer 🌍")
        _ = try XCTUnwrap(native.redo())
        XCTAssertEqual(try native.richProseProjection().mediaAtoms.first?.width, 320)
        let checkpoint = try native.encodeUpdate()
        for source in [nil, "https://example.test/replaced.png"] as [String?] {
            XCTAssertThrowsError(try RelayMarkNativeWidgetMutation.updateAttributes(document: native,
                path: media.path, expectedID: media.id,
                expected: JSONSerialization.data(withJSONObject: ["width": 320]),
                changes: JSONSerialization.data(withJSONObject: ["width": 640]), expectedMediaSource: source))
            XCTAssertEqual(try native.encodeUpdate(), checkpoint)
        }
        for (before, patch) in [
            (["width": 100], ["width": 640]),
            (["width": 320], ["width": -1]),
            (["src": media.source], ["src": "javascript:alert(1)"])
        ] as [([String: Any], [String: Any])] {
            XCTAssertThrowsError(try RelayMarkNativeWidgetMutation.updateAttributes(document: native,
                path: media.path, expectedID: media.id,
                expected: JSONSerialization.data(withJSONObject: before),
                changes: JSONSerialization.data(withJSONObject: patch), expectedMediaSource: media.source))
            XCTAssertEqual(try native.encodeUpdate(), checkpoint)
        }
    }

    func testImageRemoveInsertAndUndoReplayWithoutChangingNeighborBlocks() throws {
        let seed = try update("rich-image-v3-draft")
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let browser = RelayMarkNativeDocument()
        for replica in [native, peer] { try replica.applyUpdate(seed) }
        try browser.applyUpdate(seed)
        let original = try RelayMarkNativeDocumentProjection.project(document: native)
        let media = try XCTUnwrap(native.richProseProjection().mediaAtoms.first)
        let beforeID = "bc5e20755a10547d08d9054f33618c548"
        let afterID = "b29908e62e7c2496580e5aea7bb8e4f14"

        let removed = try RelayMarkNativeMediaMutation.remove(document: native, atRootIndex: 1,
            expectedID: media.id, expectedSource: media.source)
        try peer.applyUpdate(removed.update)
        try browser.applyUpdate(removed.update)
        XCTAssertTrue(try native.richProseProjection().isEditable)
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeDocumentProjection.project(document: native))

        let inserted = try RelayMarkNativeMediaMutation.insert(document: native, atRootIndex: 1,
            expectedPreviousID: beforeID, expectedNextID: afterID,
            block: .init(id: media.id, kind: .image, source: media.source,
                         alt: media.alt, title: media.title))
        try peer.applyUpdate(inserted.update)
        try browser.applyUpdate(inserted.update)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), original)
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()), original)
        XCTAssertTrue(try native.richProseProjection().isEditable)

        let undone = try XCTUnwrap(native.undo())
        try peer.applyUpdate(undone)
        try browser.applyUpdate(undone)
        XCTAssertTrue(try native.richProseProjection().isEditable)
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeDocumentProjection.project(document: native))
    }

    func testVideoIdentityAttributeEditIsCanonicalAndCannotAddPresentationFields() throws {
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let seed = try update("rich-video-v3-draft")
        try native.applyUpdate(seed); try peer.applyUpdate(seed)
        let media = try XCTUnwrap(native.richProseProjection().mediaAtoms.first)
        let original = try native.encodeUpdate()
        for patch in [["width": 640], ["source": "mux"], ["status": "ready"], ["videoId": "invalid"]] as [[String: Any]] {
            let before = Dictionary(uniqueKeysWithValues: patch.keys.map { ($0, $0 == "videoId" ? media.source as Any : NSNull()) })
            XCTAssertThrowsError(try RelayMarkNativeWidgetMutation.updateAttributes(document: native,
                path: media.path, expectedID: media.id,
                expected: JSONSerialization.data(withJSONObject: before),
                changes: JSONSerialization.data(withJSONObject: patch), expectedMediaSource: media.source))
            XCTAssertEqual(try native.encodeUpdate(), original)
        }
        let nextID = "11111111-1111-4111-8111-111111111111"
        let change = try RelayMarkNativeWidgetMutation.updateAttributes(document: native,
            path: media.path, expectedID: media.id,
            expected: JSONSerialization.data(withJSONObject: ["videoId": media.source]),
            changes: JSONSerialization.data(withJSONObject: ["videoId": nextID]), expectedMediaSource: media.source)
        try peer.applyUpdate(change.update)
        XCTAssertEqual(try peer.authoredDocument(), try native.authoredDocument())
        XCTAssertEqual(try native.richProseProjection().mediaAtoms.first?.source, nextID)
        XCTAssertEqual(try native.richProseProjection().mediaAtoms.first?.id, media.id)
    }

    func testVideoIdentityAndInvalidMediaAreRejectedBeforeMutation() throws {
        let seed = try update("rich-video-v3-draft")
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        for replica in [native, peer] { try replica.applyUpdate(seed) }
        let media = try XCTUnwrap(native.richProseProjection().mediaAtoms.first)
        let original = try RelayMarkNativeDocumentProjection.project(document: native)
        let checkpoint = try native.encodeUpdate()
        XCTAssertThrowsError(try RelayMarkNativeMediaMutation.remove(document: native, atRootIndex: 1,
            expectedID: media.id, expectedSource: "another-video"))
        XCTAssertEqual(try native.encodeUpdate(), checkpoint)

        let removed = try RelayMarkNativeMediaMutation.remove(document: native, atRootIndex: 1,
            expectedID: media.id, expectedSource: media.source)
        try peer.applyUpdate(removed.update)
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
        try peer.applyUpdate(inserted.update)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), original)
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
    }

    func testAdjacentTextAndSecondImageReplayWithoutReplacingEitherMediaAtom() throws {
        let seed = try update("rich-image-v3-draft")
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let browser = RelayMarkNativeDocument()
        for replica in [native, peer] { try replica.applyUpdate(seed) }
        try browser.applyUpdate(seed)
        let first = try XCTUnwrap(native.richProseProjection().mediaAtoms.first)
        XCTAssertTrue(try native.richProseProjection().isEditable)

        let proseUpdate = try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [0, 0], start: 12, end: 12, text: " together")
        try peer.applyUpdate(proseUpdate)
        try browser.applyUpdate(proseUpdate)
        let secondID = "b" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let added = try RelayMarkNativeMediaMutation.insert(document: native, atRootIndex: 2,
            expectedPreviousID: first.id, expectedNextID: "b29908e62e7c2496580e5aea7bb8e4f14",
            block: .init(id: secondID, kind: .image, source: "https://images.example.org/second.png"))
        try peer.applyUpdate(added.update)
        try browser.applyUpdate(added.update)
        XCTAssertEqual(try native.richProseProjection().mediaAtoms.count, 2)
        let checkpoint = try native.encodeUpdate()
        XCTAssertThrowsError(try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [1], start: 0, end: 1, text: "lost"))
        XCTAssertEqual(try native.encodeUpdate(), checkpoint)

        let removed = try RelayMarkNativeMediaMutation.remove(document: native, atRootIndex: 1,
            expectedID: first.id, expectedSource: first.source)
        try peer.applyUpdate(removed.update)
        try browser.applyUpdate(removed.update)
        let final = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(final.blocks[0].plainText, "Before image together")
        XCTAssertEqual(try native.richProseProjection().mediaAtoms.map(\.id), [secondID])
        XCTAssertEqual(final, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(final, try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()))
    }
}
