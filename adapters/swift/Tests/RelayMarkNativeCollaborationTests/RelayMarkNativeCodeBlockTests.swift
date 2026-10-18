import Foundation
import XCTest
import RelayMarkCollaboration
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeCodeBlockTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "code-block-v1", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    private func bytes(_ fixture: [String: Any], _ key: String) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: XCTUnwrap(fixture[key] as? String)))
    }
    func testRealBrowserMultilineCodeTypingPreservesAnchorsLanguageUndoAndPeerMerge() throws {
        let fixture = try fixture(), doc = RelayMarkNativeDocument()
        try doc.applyUpdate(bytes(fixture, "seed"))
        XCTAssertTrue(doc.supportsCodeBlockEditing())
        XCTAssertFalse(doc.supportsInlineFormatting())
        let before = try doc.snapshot(), position = try XCTUnwrap(fixture["index"] as? Int)
        let insertion = try XCTUnwrap(fixture["inserted"] as? String)
        let blockAnchor = try doc.anchor(path: [0], index: 0)
        let update = try doc.replaceCodeBlockText(start: position, end: position, text: insertion)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: doc.snapshot()) as? NSDictionary, fixture["after"] as? NSDictionary)
        for spec in try XCTUnwrap(fixture["anchors"] as? [[String: Any]]) {
            let resolved = try XCTUnwrap(doc.resolve(anchor: bytes(spec, "anchor")))
            XCTAssertEqual(resolved.path, [0, 0]); XCTAssertEqual(resolved.index, spec["index"] as? Int)
        }
        XCTAssertEqual(try doc.resolve(anchor: blockAnchor)?.path, [0])
        let browser = RelayMarkNativeDocument()
        try browser.applyUpdate(bytes(fixture, "seed")); try browser.applyUpdate(update)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary, fixture["after"] as? NSDictionary)
        _ = try XCTUnwrap(doc.undo()); XCTAssertEqual(try doc.snapshot(), before)
        _ = try XCTUnwrap(doc.redo())
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(bytes(fixture, "seed"))
        let remote = try peer.replaceCodeBlockText(start: 0, end: 0, text: "// peer\n")
        try peer.applyUpdate(update); try doc.applyUpdate(remote)
        XCTAssertEqual(try peer.snapshot(), try doc.snapshot())
        let reopened = RelayMarkNativeDocument(); try reopened.applyUpdate(doc.encodeUpdate())
        XCTAssertTrue(reopened.supportsCodeBlockEditing()); XCTAssertEqual(try reopened.snapshot(), try doc.snapshot())
        let browserResult = RelayMarkNativeDocument()
        try browserResult.applyUpdate(bytes(fixture, "seed")); try browserResult.applyUpdate(bytes(fixture, "update"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: browserResult.snapshot()) as? NSDictionary, fixture["after"] as? NSDictionary)
    }
    func testEmptyLeafRemainsEditableAndInvalidUTF16ControlsMarksAndShapesDoNotMutate() throws {
        let fixture = try fixture(), doc = RelayMarkNativeDocument()
        try doc.applyUpdate(bytes(fixture, "seed"))
        let before = try doc.encodeUpdate(), initial = try XCTUnwrap(fixture["initial"] as? String)
        for (start, end, text) in [(5, 5, "x"), (-1, 0, "x"), (0, initial.utf16.count + 1, ""), (0, 0, "\r"), (0, 0, "\u{2028}"), (0, 0, String(repeating: "x", count: 131_073))] {
            XCTAssertThrowsError(try doc.replaceCodeBlockText(start: start, end: end, text: text))
            XCTAssertEqual(try doc.encodeUpdate(), before)
        }
        _ = try doc.replaceCodeBlockText(start: 0, end: initial.utf16.count, text: "")
        XCTAssertTrue(doc.supportsCodeBlockEditing())
        _ = try doc.replaceCodeBlockText(start: 0, end: 0, text: "あ\n\tΩ")
        XCTAssertEqual(String(try doc.proseProjection().text.characters), "あ\n\tΩ")
        for mutation in ["marked", "mixed", "nested", "language", "twoLeaves", "noLeaf"] {
            var node = try XCTUnwrap((fixture["before"] as? [String: Any])?["children"] as? [[String: Any]])[0]
            var children = try XCTUnwrap(node["children"] as? [[String: Any]])
            if mutation == "marked" { children[0]["delta"] = [["insert": "text", "attributes": ["bold": [:]]]]; node["children"] = children }
            if mutation == "language" { node["attributes"] = ["language": "bad\ninfo"] }
            if mutation == "twoLeaves" { node["children"] = children + children }
            if mutation == "noLeaf" { node["children"] = [] as [Any] }
            var nodes = [node]
            if mutation == "mixed" { nodes.append(["kind": "element", "name": "paragraph", "children": []]) }
            if mutation == "nested" { nodes = [["kind": "element", "name": "blockquote", "children": nodes]] }
            let source = RelayMarkNativeDocument()
            _ = try source.edit(JSONSerialization.data(withJSONObject: ["kind": "insertNodes", "path": [], "index": 0, "nodes": nodes]))
            let invalid = RelayMarkNativeDocument(); try invalid.applyUpdate(source.encodeUpdate())
            let checkpoint = try invalid.encodeUpdate()
            XCTAssertFalse(invalid.supportsCodeBlockEditing(), mutation)
            XCTAssertThrowsError(try invalid.replaceCodeBlockText(start: 0, end: 0, text: "x"), mutation)
            XCTAssertEqual(try invalid.encodeUpdate(), checkpoint)
        }
    }
}
