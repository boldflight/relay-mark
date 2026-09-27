import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeMarkdownV3ListOperationsTests: XCTestCase {
    private func fixture(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "list-operations-v3", withExtension: "json"))
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(all[name] as? [String: Any])
    }

    private func expected(_ fixture: [String: Any], itemID: String, paragraphID: String) throws -> RelayMarkDocument {
        let oldItem = "b00000000000040008000000000000065"
        let oldParagraph = "b00000000000040008000000000000066"
        func replacing(_ value: Any) -> Any {
            if var dictionary = value as? [String: Any] {
                if dictionary["id"] as? String == oldItem { dictionary["id"] = itemID }
                if dictionary["id"] as? String == oldParagraph { dictionary["id"] = paragraphID }
                return dictionary.mapValues(replacing)
            }
            if let array = value as? [Any] { return array.map(replacing) }
            return value
        }
        return try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: replacing(try XCTUnwrap(fixture["expected_ast"]))))
    }

    func testBrowserFlatAndNestedInteriorReturnPreservesMarksIDsAndPeerUndo() throws {
        for (name, path, leafPath) in [
            ("interior_flat_ordered", [0, 1, 0], [0, 1, 0, 0]),
            ("interior_nested_ordered", [0, 0, 1, 0, 0], [0, 0, 1, 0, 0, 0])
        ] {
            let source = try fixture(name)
            let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(source["seed"] as? String)))
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try native.applyUpdate(seed)
            try peer.applyUpdate(seed)
            let before = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
            let snapshot = try native.snapshot()
            let paragraph = try native.anchor(path: path, index: 0)
            let suffixAnchor = try native.anchor(path: leafPath, index: 7)
            let state = try native.encodeUpdate()
            XCTAssertThrowsError(try native.splitMarkdownV3ListItem(
                at: paragraph, utf16Offset: 8, expectedSnapshot: snapshot))
            XCTAssertThrowsError(try native.splitMarkdownV3ListItem(
                at: paragraph, utf16Offset: 3, expectedSnapshot: Data()))
            XCTAssertEqual(try native.encodeUpdate(), state)
            let change = try native.splitMarkdownV3ListItem(
                at: paragraph, utf16Offset: 3, expectedSnapshot: snapshot)
            try peer.applyUpdate(change.update)
            let after = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
            XCTAssertEqual(after, try expected(source, itemID: change.itemID,
                                               paragraphID: change.paragraphID))
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), after)
            XCTAssertEqual(try native.resolve(anchor: suffixAnchor)?.index, 3)
            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), before)
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), before)
        }
    }

    func testBrowserFlatAndNestedEmptyExitReusesParagraphIDAndUndoes() throws {
        for (name, path) in [
            ("exit_flat_ordered", [0, 1, 0]), ("exit_flat_bullet", [0, 1, 0]),
            ("exit_nested_ordered", [0, 0, 1, 0, 0]),
            ("exit_nested_bullet", [0, 0, 1, 0, 0])
        ] {
            let source = try fixture(name)
            let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(source["seed"] as? String)))
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try native.applyUpdate(seed)
            try peer.applyUpdate(seed)
            let before = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
            let snapshot = try native.snapshot()
            let anchor = try native.anchor(path: path, index: 0)
            let state = try native.encodeUpdate()
            XCTAssertThrowsError(try native.exitEmptyMarkdownV3ListItem(
                at: anchor, expectedSnapshot: Data()))
            XCTAssertEqual(try native.encodeUpdate(), state)
            let change = try native.exitEmptyMarkdownV3ListItem(
                at: anchor, expectedSnapshot: snapshot)
            try peer.applyUpdate(change.update)
            let after = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
            let expected = try expected(source, itemID: change.newItemID ??
                "b00000000000040008000000000000065", paragraphID:
                "b00000000000040008000000000000066")
            XCTAssertEqual(after, expected)
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), after)
            XCTAssertThrowsError(try native.exitEmptyMarkdownV3ListItem(
                at: anchor, expectedSnapshot: snapshot))
            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), before)
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), before)
        }
    }
}
