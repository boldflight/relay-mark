import Foundation
import XCTest
import RelayMarkCollaboration
import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeInlineMarkTests: XCTestCase {
    func testBrowserMarksAtomicExclusiveCodeAnchorsAndLocalUndo() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "inline-marks-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let item = try XCTUnwrap((fixture["cases"] as? [[String: Any]])?.first)
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(item["update"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed); try peer.applyUpdate(seed)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary, item["snapshot"] as? NSDictionary)
        let anchor = try native.anchor(path: [0, 0], index: 9)
        // Includes one surrogate pair. One Yrs transaction removes incompatible
        // strike and adds code without deleting/reinserting text identities.
        let update = try native.formatProse(start: 0, end: 9, attributes: ["code": [:], "strike": NSNull()])
        try peer.applyUpdate(update)
        XCTAssertEqual(try native.resolve(anchor: anchor)?.index, 9)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: peer.snapshot()) as? NSDictionary)
        try native.applyUpdate(peer.replaceProse(start: 0, end: 0, text: "Peer "))
        XCTAssertEqual(try native.resolve(anchor: anchor)?.index, 14)
        try peer.applyUpdate(XCTUnwrap(native.undo()))
        XCTAssertTrue(String(try native.proseProjection().text.characters).hasPrefix("Peer Strike 🌍"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: peer.snapshot()) as? NSDictionary)
        try peer.applyUpdate(XCTUnwrap(native.redo()))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: peer.snapshot()) as? NSDictionary)
        let before = try native.encodeUpdate()
        XCTAssertThrowsError(try native.formatProse(start: 13, end: 14, attributes: ["strike": [:]]))
        XCTAssertEqual(try native.encodeUpdate(), before)
    }

    func testReplacementAndInteriorTypingPreserveCodeInOneUndoItem() throws {
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        _ = try native.replaceProse(start: 0, end: 0, text: "code")
        _ = try native.formatProse(start: 0, end: 4, attributes: ["code": [:]])
        try peer.applyUpdate(native.encodeUpdate())
        let anchor = try native.anchor(path: [0, 0], index: 3)
        try peer.applyUpdate(native.replaceProse(start: 1, end: 2, text: "あ"))
        XCTAssertEqual(String(try native.proseProjection().text.characters), "cあde")
        XCTAssertTrue(try native.proseProjection().text.runs.allSatisfy { $0.inlinePresentationIntent == .code })
        XCTAssertEqual(try native.resolve(anchor: anchor)?.index, 3)
        try peer.applyUpdate(native.replaceProse(start: 2, end: 2, text: "🌍"))
        XCTAssertTrue(try native.proseProjection().text.runs.allSatisfy { $0.inlinePresentationIntent == .code })
        try peer.applyUpdate(XCTUnwrap(native.undo()))
        XCTAssertEqual(String(try native.proseProjection().text.characters), "cあde")
        try peer.applyUpdate(XCTUnwrap(native.undo()))
        XCTAssertEqual(String(try native.proseProjection().text.characters), "code")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: peer.snapshot()) as? NSDictionary)
    }
}
