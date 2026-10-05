import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeRichListReturnTests: XCTestCase {
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
            let before = try RelayMarkNativeDocumentProjection.project(document: native)
            let snapshot = try native.snapshot()
            let originalState = try native.encodeUpdate()
            XCTAssertThrowsError(try RelayMarkNativeRichReturn.apply(document: native,
                blockPath: [999], utf16Offset: 0, expectedSnapshot: snapshot))
            XCTAssertThrowsError(try RelayMarkNativeRichReturn.apply(document: native,
                blockPath: path, utf16Offset: 0, expectedSnapshot: Data()))
            XCTAssertEqual(try native.encodeUpdate(), originalState)

            let projection = try native.richProseProjection()
            let row = try XCTUnwrap(projection.blockPaths.firstIndex(of: path))
            let offset = projection.blockRanges[row].length
            let result = try RelayMarkNativeRichReturn.apply(document: native,
                blockPath: path, utf16Offset: offset, expectedSnapshot: snapshot)
            let nextPath = name == "flat_ordered" ? [0, 1] : [0, 0, 1, 1]
            var node = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
            for index in nextPath { node = try XCTUnwrap((node["children"] as? [[String: Any]])?[index]) }
            let itemID = try XCTUnwrap((node["attributes"] as? [String: Any])?["relaymarkId"] as? String)
            try peer.applyUpdate(result.change.update)
            let after = try RelayMarkNativeDocumentProjection.project(document: native)
            var raw = try XCTUnwrap(fixture["expected_ast"] as? [String: Any])
            var blocks = try XCTUnwrap(raw["blocks"] as? [[String: Any]])
            if name == "flat_ordered" {
                var items = try XCTUnwrap(blocks[0]["content"] as? [[String: Any]])
                items[1]["id"] = itemID
                var paragraphs = try XCTUnwrap(items[1]["content"] as? [[String: Any]])
                paragraphs[0]["id"] = result.blockID
                items[1]["content"] = paragraphs
                blocks[0]["content"] = items
            } else {
                var outer = try XCTUnwrap(blocks[0]["content"] as? [[String: Any]])
                var nested = try XCTUnwrap(outer[0]["content"] as? [[String: Any]])
                var items = try XCTUnwrap(nested[1]["content"] as? [[String: Any]])
                items[1]["id"] = itemID
                var paragraphs = try XCTUnwrap(items[1]["content"] as? [[String: Any]])
                paragraphs[0]["id"] = result.blockID
                items[1]["content"] = paragraphs
                nested[1]["content"] = items
                outer[0]["content"] = nested
                blocks[0]["content"] = outer
            }
            raw["blocks"] = blocks
            XCTAssertEqual(after, try RelayMarkDocument.decodeJSON(JSONSerialization.data(withJSONObject: raw)))
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), after)
            let afterState = try native.encodeUpdate()
            XCTAssertThrowsError(try RelayMarkNativeRichReturn.apply(document: native,
                blockPath: path, utf16Offset: offset, expectedSnapshot: snapshot))
            XCTAssertEqual(try native.encodeUpdate(), afterState)
            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)
        }
    }
}
