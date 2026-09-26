import Foundation
import XCTest
import RelayMarkCollaboration
import RelayMarkProseProjection
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeInlineAtomMutationTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "inline-atoms-v3-draft", withExtension: "json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(object["update"] as? String)))
    }

    func testBrowserFixtureInsertReplacePeerConvergenceAndUndo() throws {
        let initial = try fixture()
        let native = RelayMarkNativeDocument()
        let peer = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        for replica in [native, peer] { try replica.applyUpdate(initial) }
        try browser.applyUpdate(initial)

        let tag = RelayMarkNativeInlineAtomMutation.Atom(kind: .relayTag, attributes: [
            "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "name": "followup",
            "source": "[[Tag: aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa | #followup]]"
        ])
        let before = try native.markdownV3ProseProjection()
        let originalIDs = before.inlineAtoms.map(\.id)
        let protectedTagAnchor = try native.anchor(path: [0, 3], index: 0)
        let inserted = try RelayMarkNativeInlineAtomMutation.insert(
            document: native, blockID: "b00000000000040008000000000000031", childIndex: 2, atom: tag)
        try peer.applyUpdate(inserted)
        try browser.applyUpdate(inserted)
        let insertedProse = try native.markdownV3ProseProjection()
        XCTAssertEqual(insertedProse.inlineAtoms.map(\.id),
                       [originalIDs[0], "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", originalIDs[1], originalIDs[2]])
        XCTAssertEqual(String(insertedProse.text.characters),
                       "Meet \u{FFFC}\u{FFFC} for \u{FFFC}. [[unknown]] stays text.\n\u{FFFC}")
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try native.resolve(anchor: protectedTagAnchor)?.path, [0, 4])
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native))
        let replacement = RelayMarkNativeInlineAtomMutation.Atom(kind: .relayReference, attributes: [
            "entityType": "Person", "entityId": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            "label": "Grace Hopper",
            "source": "[[Person: bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb | Grace Hopper]]"
        ])
        let target = try XCTUnwrap(insertedProse.inlineAtoms.first(where: { $0.id == originalIDs[0] }))
        let replaced = try RelayMarkNativeInlineAtomMutation.replace(document: native, range: target.range,
                                                                     expectedID: target.id,
                                                                     atom: replacement)
        try peer.applyUpdate(replaced)
        try browser.applyUpdate(replaced)
        let final = try native.markdownV3ProseProjection()
        XCTAssertEqual(final.inlineAtoms.map(\.id),
                       ["bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                        originalIDs[1], originalIDs[2]])
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try native.resolve(anchor: protectedTagAnchor)?.path, [0, 4])
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native))
        let undo = try XCTUnwrap(native.undo())
        try peer.applyUpdate(undo)
        try browser.applyUpdate(undo)
        XCTAssertEqual(try native.markdownV3ProseProjection().inlineAtoms.map(\.id),
                       insertedProse.inlineAtoms.map(\.id))
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native))
        let undoInsertion = try XCTUnwrap(native.undo())
        try peer.applyUpdate(undoInsertion)
        try browser.applyUpdate(undoInsertion)
        XCTAssertEqual(try native.markdownV3ProseProjection().inlineAtoms.map(\.id), originalIDs)
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native))
    }

    func testMalformedSourceAndStaleRangeLeaveReplicaUntouched() throws {
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(fixture())
        let before = try native.encodeUpdate()
        let malformed = RelayMarkNativeInlineAtomMutation.Atom(kind: .relayTag, attributes: [
            "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "name": "followup",
            "source": "[[Tag: aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa | #wrong]]"
        ])
        XCTAssertThrowsError(try RelayMarkNativeInlineAtomMutation.insert(
            document: native, blockID: "b00000000000040008000000000000031", childIndex: 2, atom: malformed))
        XCTAssertThrowsError(try RelayMarkNativeInlineAtomMutation.replace(
            document: native, range: NSRange(location: 4, length: 1),
            expectedID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", atom: malformed))
        XCTAssertThrowsError(try RelayMarkNativeInlineAtomMutation.replace(
            document: native, range: NSRange(location: 5, length: 1),
            expectedID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", atom: malformed))
        XCTAssertEqual(try native.encodeUpdate(), before)
    }
}
