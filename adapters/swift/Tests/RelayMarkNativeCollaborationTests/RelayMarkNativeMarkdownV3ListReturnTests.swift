import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeMarkdownV3ListReturnTests: XCTestCase {
    private func cases() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "list-end-return-v3", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testBrowserFlatAndNestedEndReturnPreservesNodesAndUndoes() throws {
        for (name, path) in [("flat_ordered", [0, 0, 0]), ("nested_ordered", [0, 0, 1, 0, 0])] {
            let fixture = try XCTUnwrap(cases()[name] as? [String: Any])
            let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String)))
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try native.applyUpdate(seed)
            try peer.applyUpdate(seed)
            let before = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
            let snapshot = try native.snapshot()
            let anchor = try native.anchor(path: path, index: 0)
            let originalState = try native.encodeUpdate()
            XCTAssertThrowsError(try native.appendEmptyMarkdownV3ListItem(
                after: Data([255]), expectedSnapshot: snapshot))
            XCTAssertThrowsError(try native.appendEmptyMarkdownV3ListItem(
                after: anchor, expectedSnapshot: Data()))
            XCTAssertEqual(try native.encodeUpdate(), originalState)

            let change = try native.appendEmptyMarkdownV3ListItem(after: anchor, expectedSnapshot: snapshot)
            try peer.applyUpdate(change.update)
            let after = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
            var raw = try XCTUnwrap(fixture["expected_ast"] as? [String: Any])
            var blocks = try XCTUnwrap(raw["blocks"] as? [[String: Any]])
            if name == "flat_ordered" {
                var items = try XCTUnwrap(blocks[0]["content"] as? [[String: Any]])
                items[1]["id"] = change.itemID
                var paragraphs = try XCTUnwrap(items[1]["content"] as? [[String: Any]])
                paragraphs[0]["id"] = change.paragraphID
                items[1]["content"] = paragraphs
                blocks[0]["content"] = items
            } else {
                var outer = try XCTUnwrap(blocks[0]["content"] as? [[String: Any]])
                var nested = try XCTUnwrap(outer[0]["content"] as? [[String: Any]])
                var items = try XCTUnwrap(nested[1]["content"] as? [[String: Any]])
                items[1]["id"] = change.itemID
                var paragraphs = try XCTUnwrap(items[1]["content"] as? [[String: Any]])
                paragraphs[0]["id"] = change.paragraphID
                items[1]["content"] = paragraphs
                nested[1]["content"] = items
                outer[0]["content"] = nested
                blocks[0]["content"] = outer
            }
            raw["blocks"] = blocks
            XCTAssertEqual(after, try RelayMarkDocument.decodeJSON(JSONSerialization.data(withJSONObject: raw)))
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), after)
            let afterState = try native.encodeUpdate()
            XCTAssertThrowsError(try native.appendEmptyMarkdownV3ListItem(after: anchor, expectedSnapshot: snapshot))
            let emptyPath = name == "flat_ordered" ? [0, 1, 0] : [0, 0, 1, 1, 0]
            XCTAssertThrowsError(try native.appendEmptyMarkdownV3ListItem(
                after: native.anchor(path: emptyPath, index: 0), expectedSnapshot: native.snapshot()))
            XCTAssertEqual(try native.encodeUpdate(), afterState)
            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), before)
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), before)
        }
    }
}
