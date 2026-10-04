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

    private func tag() -> RelayMarkNativeInlineAtomMutation.Atom {
        .init(kind: .relayTag, attributes: [
            "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "name": "followup",
            "source": "[[Tag: aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa | #followup]]"
        ])
    }

    func testMidLeafInsertionPreservesMarksAndReplaysAcrossBrowserAndNative() throws {
        let initial = try fixture()
        let native = RelayMarkNativeDocument()
        let peer = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        for replica in [native, peer] { try replica.applyUpdate(initial) }
        try browser.applyUpdate(initial)
        let marked = try native.formatText(at: 1, length: 3,
                                           attributes: ["bold": [String: Any]()], path: [0, 0])
        try peer.applyUpdate(marked)
        try browser.applyUpdate(marked)
        let originalLeaf = try native.anchor(path: [0, 0], index: 1)
        let adjacentAtom = try native.anchor(path: [0, 1], index: 0)
        let observation = try native.captureContentEditObservation()
        let inserted = try RelayMarkNativeInlineAtomMutation.insert(
            document: native, blockID: "b00000000000040008000000000000031",
            childIndex: 0, utf16Offset: 2, expectedLeafText: "Meet ", atom: tag())
        let steps = try XCTUnwrap(JSONSerialization.jsonObject(with: inserted.steps) as? [[String: Any]])
        XCTAssertEqual(steps.first?["stepType"] as? String, "replace")
        let witness = try XCTUnwrap(JSONSerialization.jsonObject(with:
            native.buildContentEditWitness(observation, steps: inserted.steps, update: inserted.update)) as? [String: Any])
        XCTAssertEqual((witness["text_items"] as? [String: Any])?["runs"] as? [[String: Int]], [])
        try peer.applyUpdate(inserted.update)
        try browser.applyUpdate(inserted.update)

        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        let blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
        let children = try XCTUnwrap(blocks[0]["children"] as? [[String: Any]])
        XCTAssertEqual(children.count, 7)
        XCTAssertEqual(children[0]["kind"] as? String, "text")
        XCTAssertEqual(children[1]["name"] as? String, "relayTag")
        XCTAssertEqual(children[2]["kind"] as? String, "text")
        let left = try XCTUnwrap(children[0]["delta"] as? [[String: Any]])
        let right = try XCTUnwrap(children[2]["delta"] as? [[String: Any]])
        XCTAssertEqual(left.compactMap { $0["insert"] as? String }.joined(), "Me")
        XCTAssertEqual(right.compactMap { $0["insert"] as? String }.joined(), "et ")
        XCTAssertNotNil((left.last?["attributes"] as? [String: Any])?["bold"] as? [String: Any])
        XCTAssertNotNil((right.first?["attributes"] as? [String: Any])?["bold"] as? [String: Any])
        XCTAssertEqual(try native.resolve(anchor: originalLeaf)?.path, [0, 0])
        XCTAssertEqual(try native.resolve(anchor: adjacentAtom)?.path, [0, 3])
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeDocumentProjection.project(document: native))
        let undone = try XCTUnwrap(native.undo())
        try peer.applyUpdate(undone)
        try browser.applyUpdate(undone)
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try native.richProseProjection().inlineAtoms.count, 3)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeDocumentProjection.project(document: native))
    }

    func testMidLeafUnicodeBoundaryAndStalePositionsFailClosed() throws {
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(fixture())
        _ = try native.insertText("🌍", at: 2, path: [0, 0])
        let before = try native.encodeUpdate()
        for offset in [-1, 0, 3, 8] {
            XCTAssertThrowsError(try RelayMarkNativeInlineAtomMutation.insert(
                document: native, blockID: "b00000000000040008000000000000031",
                childIndex: 0, utf16Offset: offset,
                expectedLeafText: "Me🌍et ", atom: tag()))
        }
        XCTAssertThrowsError(try RelayMarkNativeInlineAtomMutation.insert(
            document: native, blockID: "b00000000000040008000000000000031",
            childIndex: 0, utf16Offset: 4, expectedLeafText: "Meet ", atom: tag()))
        XCTAssertThrowsError(try RelayMarkNativeInlineAtomMutation.insert(
            document: native, blockID: "b00000000000040008000000000000031",
            childIndex: 1, utf16Offset: 1, expectedLeafText: "Me🌍et ", atom: tag()))
        let wrongSource = RelayMarkNativeInlineAtomMutation.Atom(kind: .relayTag, attributes: [
            "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "name": "followup",
            "source": "[[Tag: aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa | #wrong]]"
        ])
        XCTAssertThrowsError(try RelayMarkNativeInlineAtomMutation.insert(
            document: native, blockID: "b00000000000040008000000000000031",
            childIndex: 0, utf16Offset: 4, expectedLeafText: "Me🌍et ", atom: wrongSource))
        XCTAssertEqual(try native.encodeUpdate(), before)
        _ = try RelayMarkNativeInlineAtomMutation.insert(
            document: native, blockID: "b00000000000040008000000000000031",
            childIndex: 0, utf16Offset: 4, expectedLeafText: "Me🌍et ", atom: tag())
        XCTAssertEqual(try native.richProseProjection().inlineAtoms.count, 4)
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
        let before = try native.richProseProjection()
        let originalIDs = before.inlineAtoms.map(\.id)
        let protectedTagAnchor = try native.anchor(path: [0, 3], index: 0)
        let inserted = try RelayMarkNativeInlineAtomMutation.insert(
            document: native, blockID: "b00000000000040008000000000000031", childIndex: 2, atom: tag)
        try peer.applyUpdate(inserted.update)
        try browser.applyUpdate(inserted.update)
        let insertedProse = try native.richProseProjection()
        XCTAssertEqual(insertedProse.inlineAtoms.map(\.id),
                       [originalIDs[0], "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", originalIDs[1], originalIDs[2]])
        XCTAssertEqual(String(insertedProse.text.characters),
                       "Meet \u{FFFC}\u{FFFC} for \u{FFFC}. [[unknown]] stays text.\n\u{FFFC}")
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try native.resolve(anchor: protectedTagAnchor)?.path, [0, 4])
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeDocumentProjection.project(document: native))
        let replacement = RelayMarkNativeInlineAtomMutation.Atom(kind: .relayReference, attributes: [
            "entityType": "Person", "entityId": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            "label": "Grace Hopper",
            "source": "[[Person: bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb | Grace Hopper]]"
        ])
        let target = try XCTUnwrap(insertedProse.inlineAtoms.first(where: { $0.id == originalIDs[0] }))
        let replaced = try RelayMarkNativeInlineAtomMutation.replace(document: native, range: target.range,
                                                                     expectedID: target.id,
                                                                     atom: replacement)
        try peer.applyUpdate(replaced.update)
        try browser.applyUpdate(replaced.update)
        let final = try native.richProseProjection()
        XCTAssertEqual(final.inlineAtoms.map(\.id),
                       ["bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                        originalIDs[1], originalIDs[2]])
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try native.resolve(anchor: protectedTagAnchor)?.path, [0, 4])
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeDocumentProjection.project(document: native))
        let undo = try XCTUnwrap(native.undo())
        try peer.applyUpdate(undo)
        try browser.applyUpdate(undo)
        XCTAssertEqual(try native.richProseProjection().inlineAtoms.map(\.id),
                       insertedProse.inlineAtoms.map(\.id))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeDocumentProjection.project(document: native))
        let undoInsertion = try XCTUnwrap(native.undo())
        try peer.applyUpdate(undoInsertion)
        try browser.applyUpdate(undoInsertion)
        XCTAssertEqual(try native.richProseProjection().inlineAtoms.map(\.id), originalIDs)
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeDocumentProjection.project(document: native))
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
