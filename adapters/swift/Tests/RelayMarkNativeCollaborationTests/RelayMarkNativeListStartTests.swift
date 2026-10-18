import Foundation
import XCTest
import RelayMarkCollaboration
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeListStartTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "list-start-v1", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    private func bytes(_ fixture: [String: Any], _ key: String) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: XCTUnwrap(fixture[key] as? String)))
    }
    func testBrowserStartAttributeParityAnchorsUndoAndConcurrentText() throws {
        let fixture = try fixture(), doc = RelayMarkNativeDocument()
        try doc.applyUpdate(bytes(fixture, "seed"))
        let before = try doc.snapshot(), anchor = try doc.anchor(path: [0, 0, 1], index: 0)
        let update = try doc.setOrderedListStart(anchor: anchor, expectedStart: 3, start: 7)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: doc.snapshot()) as? NSDictionary, fixture["after"] as? NSDictionary)
        for spec in try XCTUnwrap(fixture["anchors"] as? [[String: Any]]) {
            let resolved = try XCTUnwrap(doc.resolve(anchor: bytes(spec, "anchor")))
            XCTAssertEqual(resolved.path, spec["path"] as? [Int])
            XCTAssertEqual(resolved.index, spec["index"] as? Int)
        }
        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(bytes(fixture, "seed")); try peer.applyUpdate(update)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: peer.snapshot()) as? NSDictionary, try JSONSerialization.jsonObject(with: doc.snapshot()) as? NSDictionary)
        _ = try XCTUnwrap(doc.undo()); XCTAssertEqual(try doc.snapshot(), before)
        _ = try XCTUnwrap(doc.redo())
        let concurrent = RelayMarkNativeDocument()
        try concurrent.applyUpdate(bytes(fixture, "seed"))
        let text = try concurrent.insertText("Peer ", at: 0, path: [0, 1, 0, 0])
        try concurrent.applyUpdate(update); try doc.applyUpdate(text)
        XCTAssertEqual(try concurrent.snapshot(), try doc.snapshot())
        let reopened = RelayMarkNativeDocument(); try reopened.applyUpdate(doc.encodeUpdate())
        XCTAssertEqual(try reopened.snapshot(), try doc.snapshot())
        let browserResult = RelayMarkNativeDocument()
        try browserResult.applyUpdate(bytes(fixture, "seed")); try browserResult.applyUpdate(bytes(fixture, "update"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: browserResult.snapshot()) as? NSDictionary, fixture["after"] as? NSDictionary)
    }
    func testInvalidStaleAndForeignAnchorsDoNotMutate() throws {
        let fixture = try fixture(), doc = RelayMarkNativeDocument()
        try doc.applyUpdate(bytes(fixture, "seed"))
        let anchor = try doc.anchor(path: [0, 0, 1], index: 0), before = try doc.encodeUpdate()
        for value in [0, -1, 1_000_001] {
            XCTAssertThrowsError(try doc.setOrderedListStart(anchor: anchor, expectedStart: 3, start: value))
        }
        XCTAssertThrowsError(try doc.setOrderedListStart(anchor: anchor, expectedStart: 4, start: 7))
        XCTAssertThrowsError(try doc.setOrderedListStart(anchor: doc.anchor(path: [0], index: 0), expectedStart: 1, start: 7))
        XCTAssertThrowsError(try doc.setOrderedListStart(anchor: Data([255]), expectedStart: 3, start: 7))
        let foreign = RelayMarkNativeDocument()
        XCTAssertThrowsError(try foreign.setOrderedListStart(anchor: anchor, expectedStart: 3, start: 7))
        XCTAssertEqual(try doc.encodeUpdate(), before)
        _ = try doc.setOrderedListStart(anchor: anchor, expectedStart: 3, start: 1_000_000)
        _ = try doc.setOrderedListStart(anchor: anchor, expectedStart: 1_000_000, start: 1)
    }
}
