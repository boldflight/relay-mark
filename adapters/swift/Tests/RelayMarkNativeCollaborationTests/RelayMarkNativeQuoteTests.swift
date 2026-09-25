import Foundation
import XCTest
import RelayMarkCollaboration
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeQuoteTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "quote-v1", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    private func bytes(_ fixture: [String: Any], _ key: String) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: XCTUnwrap(fixture[key] as? String)))
    }
    func testBrowserQuoteTypingPreservesMarksAncestorsAnchorsUndoAndPeerReopen() throws {
        let fixture = try fixture(), doc = RelayMarkNativeDocument()
        try doc.applyUpdate(bytes(fixture, "seed"))
        XCTAssertTrue(doc.supportsQuoteEditing()); XCTAssertFalse(doc.supportsInlineFormatting())
        let before = try doc.snapshot(), index = try XCTUnwrap(fixture["index"] as? Int)
        let quote = try doc.anchor(path: [0], index: 0), paragraph = try doc.anchor(path: [0, 0], index: 0)
        let update = try doc.replaceQuoteText(start: index, end: index, text: XCTUnwrap(fixture["inserted"] as? String))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: doc.snapshot()) as? NSDictionary, fixture["after"] as? NSDictionary)
        for spec in try XCTUnwrap(fixture["anchors"] as? [[String: Any]]) {
            let resolved = try XCTUnwrap(doc.resolve(anchor: bytes(spec, "anchor")))
            let expected = try XCTUnwrap(spec["resolved"] as? [String: Any])
            XCTAssertEqual(resolved.path, [0, 0, 0]); XCTAssertEqual(resolved.index, expected["index"] as? Int)
        }
        XCTAssertEqual(try doc.resolve(anchor: quote)?.path, [0]); XCTAssertEqual(try doc.resolve(anchor: paragraph)?.path, [0, 0])
        let browser = try RelayMarkCollaborationDocument(); try browser.applyUpdate(bytes(fixture, "seed")); try browser.applyUpdate(update)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary, fixture["after"] as? NSDictionary)
        _ = try XCTUnwrap(doc.undo()); XCTAssertEqual(try doc.snapshot(), before); _ = try XCTUnwrap(doc.redo())
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(bytes(fixture, "seed"))
        let remote = try peer.replaceQuoteText(start: 0, end: 0, text: "Peer ")
        try peer.applyUpdate(update); try doc.applyUpdate(remote)
        XCTAssertEqual(try peer.snapshot(), try doc.snapshot())
        let reopened = RelayMarkNativeDocument(); try reopened.applyUpdate(doc.encodeUpdate())
        XCTAssertTrue(reopened.supportsQuoteEditing()); XCTAssertEqual(try reopened.snapshot(), try doc.snapshot())
        let actual = RelayMarkNativeDocument(); try actual.applyUpdate(bytes(fixture, "seed")); try actual.applyUpdate(bytes(fixture, "update"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: actual.snapshot()) as? NSDictionary, fixture["after"] as? NSDictionary)
    }
    func testInvalidRangesStructuralInputAndUnsupportedShapesAreNonmutating() throws {
        let fixture = try fixture(), doc = RelayMarkNativeDocument(); try doc.applyUpdate(bytes(fixture, "seed"))
        let before = try doc.encodeUpdate()
        for (start, end, text) in [(8, 8, "x"), (-1, 0, ""), (0, 99, ""), (0, 0, "\n"), (0, 0, "\u{2028}"), (0, 0, String(repeating: "x", count: 131_073))] {
            XCTAssertThrowsError(try doc.replaceQuoteText(start: start, end: end, text: text)); XCTAssertEqual(try doc.encodeUpdate(), before)
        }
        let initial = try XCTUnwrap(fixture["initial"] as? String)
        _ = try doc.replaceQuoteText(start: 0, end: initial.utf16.count, text: "")
        XCTAssertTrue(doc.supportsQuoteEditing())
        _ = try doc.replaceQuoteText(start: 0, end: 0, text: "あ 🌍")
        for mutation in ["mixed", "nested", "twoParagraphs", "noLeaf", "attributes", "unknownMark"] {
            var quote = try XCTUnwrap((fixture["before"] as? [String: Any])?["children"] as? [[String: Any]])[0]
            var paragraphs = try XCTUnwrap(quote["children"] as? [[String: Any]])
            if mutation == "twoParagraphs" { quote["children"] = paragraphs + paragraphs }
            if mutation == "noLeaf" { paragraphs[0]["children"] = [] as [Any]; quote["children"] = paragraphs }
            if mutation == "attributes" { quote["attributes"] = ["unknown": 1] }
            if mutation == "unknownMark" { paragraphs[0]["children"] = [["kind": "text", "delta": [["insert": "text", "attributes": ["unknown": [:]]]]]]; quote["children"] = paragraphs }
            var nodes = [quote]
            if mutation == "mixed" { nodes.append(["kind": "element", "name": "paragraph", "children": []]) }
            if mutation == "nested" { nodes = [["kind": "element", "name": "blockquote", "children": nodes]] }
            let source = try RelayMarkCollaborationDocument(); _ = try source.edit(JSONSerialization.data(withJSONObject: ["kind": "insertNodes", "path": [], "index": 0, "nodes": nodes]))
            let invalid = RelayMarkNativeDocument(); try invalid.applyUpdate(source.encodeUpdate())
            let checkpoint = try invalid.encodeUpdate()
            XCTAssertFalse(invalid.supportsQuoteEditing(), mutation)
            XCTAssertThrowsError(try invalid.replaceQuoteText(start: 0, end: 0, text: "x")); XCTAssertEqual(try invalid.encodeUpdate(), checkpoint)
        }
    }
}
