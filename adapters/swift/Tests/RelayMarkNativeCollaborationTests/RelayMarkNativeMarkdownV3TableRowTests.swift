import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeMarkdownV3TableRowTests: XCTestCase {
    func testCommunityAddRowAfterPreservesExistingTableAndReplaysUndo() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "table-add-row-v3", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        let checkpoint = try native.snapshot()
        let state = try native.encodeUpdate()
        let cell = try native.anchor(path: [0, 1, 0], index: 0)
        XCTAssertThrowsError(try native.addMarkdownV3TableRow(afterCell: cell,
            expectedCellID: "b00000000000040008000000000000008", expectedSnapshot: Data()))
        XCTAssertThrowsError(try native.addMarkdownV3TableRow(afterCell: cell,
            expectedCellID: "b00000000000040008000000000000009", expectedSnapshot: checkpoint))
        XCTAssertEqual(try native.encodeUpdate(), state)

        let change = try native.addMarkdownV3TableRow(afterCell: cell,
            expectedCellID: "b00000000000040008000000000000008", expectedSnapshot: checkpoint)
        XCTAssertEqual(change.cellIDs.count, 2)
        XCTAssertEqual(change.paragraphIDs.count, 2)
        try peer.applyUpdate(change.update)
        let after = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        XCTAssertEqual(after, try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer))
        XCTAssertEqual(after.blocks[0].childBlocks.prefix(2), before.blocks[0].childBlocks.prefix(2))
        XCTAssertEqual(after.blocks[0].childBlocks[2].id, change.rowID)
        XCTAssertEqual(after.blocks[0].childBlocks[2].childBlocks.map(\.id), change.cellIDs)
        XCTAssertEqual(after.blocks[0].childBlocks[2].childBlocks.map { $0.childBlocks[0].id },
                       change.paragraphIDs)
        XCTAssertEqual(after.blocks[0].childBlocks[2].childBlocks.map { $0.props["colwidth"] },
                       before.blocks[0].childBlocks[1].childBlocks.map { $0.props["colwidth"] })

        func replacing(_ value: Any) -> Any {
            if var object = value as? [String: Any] {
                let ids = ["b00000000000040008000000000000064": change.rowID,
                           "b00000000000040008000000000000065": change.cellIDs[0],
                           "b00000000000040008000000000000066": change.paragraphIDs[0],
                           "b00000000000040008000000000000067": change.cellIDs[1],
                           "b00000000000040008000000000000068": change.paragraphIDs[1]]
                if let id = object["id"] as? String, let replacement = ids[id] { object["id"] = replacement }
                return object.mapValues(replacing)
            }
            if let array = value as? [Any] { return array.map(replacing) }
            return value
        }
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: replacing(try XCTUnwrap(fixture["expected_ast"]))))
        XCTAssertEqual(after, expected)
        XCTAssertThrowsError(try native.addMarkdownV3TableRow(afterCell: cell,
            expectedCellID: "b00000000000040008000000000000008", expectedSnapshot: checkpoint))
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), before)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), before)

        let merged = RelayMarkNativeDocument()
        try merged.applyUpdate(try XCTUnwrap(Data(base64Encoded:
            try XCTUnwrap(fixture["merged_seed"] as? String))))
        let mergedState = try merged.encodeUpdate()
        XCTAssertThrowsError(try merged.addMarkdownV3TableRow(afterCell:
            merged.anchor(path: [0, 1, 0], index: 0),
            expectedCellID: "b00000000000040008000000000000008",
            expectedSnapshot: merged.snapshot()))
        XCTAssertEqual(try merged.encodeUpdate(), mergedState)
    }
}
