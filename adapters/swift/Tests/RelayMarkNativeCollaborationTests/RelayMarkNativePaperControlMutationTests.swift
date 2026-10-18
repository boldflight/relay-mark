import Foundation
import XCTest
import RelayMarkCollaboration
import RelayMarkProseProjection
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativePaperControlMutationTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "paper-controls-v3-draft", withExtension: "json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(object["update"] as? String)))
    }

    private let paragraphID = "b00000000000040008000000000000061"
    private let anchorID = "b00000000000040008000000000000062"
    private let buttonID = "b00000000000040008000000000000063"
    private let insertedID = "b00000000000040008000000000000068"

    func testInsertUpdateRemoveRetainIdentityAndReplayToPeers() throws {
        let update = try fixture()
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let browser = RelayMarkNativeDocument()
        for replica in [native, peer] { try replica.applyUpdate(update) }
        try browser.applyUpdate(update)

        let block = RelayMarkNativePaperControlMutation.Block(
            id: insertedID, control: .anchor, authored: ["name": "later"])
        let inserted = try RelayMarkNativePaperControlMutation.insert(
            document: native, atRootIndex: 1,
            expectedPreviousID: paragraphID, expectedNextID: anchorID, block: block)
        try peer.applyUpdate(inserted.update)
        try browser.applyUpdate(inserted.update)
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try native.richProseProjection().blockAtoms.first?.id, insertedID)

        let buttonAnchor = try native.anchor(path: [3], index: 0)
        let changed = try RelayMarkNativePaperControlMutation.update(
            document: native, atRootIndex: 3, expectedID: buttonID,
            expectedSource: "@Button(label: \"Next\", kind: \"anchor\", target: \"next\")",
            authored: ["label": "Continue", "kind": "anchor", "target": "next"])
        try peer.applyUpdate(changed.update)
        try browser.applyUpdate(changed.update)
        XCTAssertEqual(try native.resolve(anchor: buttonAnchor)?.path, [3])
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try native.richProseProjection().blockAtoms[2].displayLabel, "Continue")

        let removed = try RelayMarkNativePaperControlMutation.remove(
            document: native, atRootIndex: 1, expectedID: insertedID,
            expectedSource: "@Anchor(name: \"later\")")
        try peer.applyUpdate(removed.update)
        try browser.applyUpdate(removed.update)
        XCTAssertEqual(try peer.snapshot(), try native.snapshot())
        XCTAssertEqual(try native.resolve(anchor: buttonAnchor)?.path, [2])
        XCTAssertEqual(try native.richProseProjection().blockAtoms.map(\.id).contains(insertedID), false)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeDocumentProjection.project(document: native))
    }

    func testInvalidFieldsDuplicateIdentityAndStaleCheckpointsDoNotMutate() throws {
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let update = try fixture()
        try native.applyUpdate(update)
        try peer.applyUpdate(update)
        let before = try native.encodeUpdate()
        let duplicate = RelayMarkNativePaperControlMutation.Block(
            id: anchorID, control: .anchor, authored: ["name": "duplicate"])
        XCTAssertThrowsError(try RelayMarkNativePaperControlMutation.insert(
            document: native, atRootIndex: 1, expectedPreviousID: paragraphID,
            expectedNextID: anchorID, block: duplicate))
        let unsafe = RelayMarkNativePaperControlMutation.Block(
            id: insertedID, control: .button,
            authored: ["label": "Run", "kind": "link", "target": "javascript:alert(1)"])
        XCTAssertThrowsError(try RelayMarkNativePaperControlMutation.insert(
            document: native, atRootIndex: 1, expectedPreviousID: paragraphID,
            expectedNextID: anchorID, block: unsafe))
        let hostField = RelayMarkNativePaperControlMutation.Block(
            id: insertedID, control: .anchor, authored: ["name": "later", "authorized": "true"])
        XCTAssertThrowsError(try RelayMarkNativePaperControlMutation.insert(
            document: native, atRootIndex: 1, expectedPreviousID: paragraphID,
            expectedNextID: anchorID, block: hostField))
        XCTAssertThrowsError(try RelayMarkNativePaperControlMutation.insert(
            document: native, atRootIndex: 1, expectedPreviousID: "stale",
            expectedNextID: anchorID, block: .init(id: insertedID, control: .anchor,
                                                    authored: ["name": "later"])))
        XCTAssertEqual(try native.encodeUpdate(), before)

        let peerChange = try RelayMarkNativePaperControlMutation.update(
            document: peer, atRootIndex: 2, expectedID: buttonID,
            expectedSource: "@Button(label: \"Next\", kind: \"anchor\", target: \"next\")",
            authored: ["label": "Proceed", "kind": "anchor", "target": "next"])
        try native.applyUpdate(peerChange.update)
        let afterPeerChange = try native.encodeUpdate()
        XCTAssertThrowsError(try RelayMarkNativePaperControlMutation.update(
            document: native, atRootIndex: 2, expectedID: buttonID,
            expectedSource: "@Button(label: \"Next\", kind: \"anchor\", target: \"next\")",
            authored: ["label": "Continue", "kind": "anchor", "target": "next"]))
        XCTAssertThrowsError(try RelayMarkNativePaperControlMutation.remove(
            document: native, atRootIndex: 2, expectedID: buttonID,
            expectedSource: "@Button(label: \"Next\", kind: \"anchor\", target: \"next\")"))
        XCTAssertThrowsError(try RelayMarkNativePaperControlMutation.remove(
            document: native, atRootIndex: 1, expectedID: buttonID,
            expectedSource: "@Button(label: \"Proceed\", kind: \"anchor\", target: \"next\")"))
        XCTAssertEqual(try native.encodeUpdate(), afterPeerChange)
    }
}
