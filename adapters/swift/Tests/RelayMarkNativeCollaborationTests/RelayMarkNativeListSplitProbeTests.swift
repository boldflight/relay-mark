import Foundation
import XCTest
import RelayMarkNativeCollaboration

/// Evidence only: native Return remains gated. Standard Yjs/Yrs relative
/// positions do not follow text copied to another leaf by ProseMirror split.
@MainActor
final class RelayMarkNativeListSplitProbeTests: XCTestCase {
    func testCommunityListSplitRetainsPrefixButCollapsesSuffixAnchor() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "list-split-probe-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String)))
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let anchors = try XCTUnwrap(fixture["anchors"] as? [[String: Any]])
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: document.snapshot()) as? NSDictionary, fixture["before"] as? NSDictionary)
        for item in anchors {
            let anchor = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(item["anchor"] as? String)))
            let resolved = try XCTUnwrap(document.resolve(anchor: anchor))
            XCTAssertEqual(resolved.path, item["path"] as? [Int])
            XCTAssertEqual(resolved.index, item["index"] as? Int)
        }
        try document.applyUpdate(update)
        XCTAssertTrue(document.integrationStatus().isComplete)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: document.snapshot()) as? NSDictionary, fixture["after"] as? NSDictionary)
        XCTAssertEqual(String(try document.proseProjection().text.characters), "Outer\nNes\nted 🌍 text\nSibling")
        for item in anchors {
            let anchor = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(item["anchor"] as? String)))
            let expected = try XCTUnwrap(item["resolved"] as? [String: Any])
            let resolved = try XCTUnwrap(document.resolve(anchor: anchor))
            XCTAssertEqual(resolved.path, expected["path"] as? [Int])
            XCTAssertEqual(resolved.index, expected["index"] as? Int)
            if item["name"] as? String == "suffix" {
                XCTAssertEqual(resolved.path, [0, 0, 1, 0, 0, 0])
                XCTAssertEqual(resolved.index, 3)
                // The suffix actually moved to a different sibling leaf. Its
                // old anchor does not resolve to index 7 in that new leaf.
                XCTAssertNotEqual(resolved.path, [0, 0, 1, 1, 0, 0])
            }
        }
        let snapshot = try document.snapshot()
        try document.applyUpdate(update)
        XCTAssertEqual(try document.snapshot(), snapshot)
    }
}
