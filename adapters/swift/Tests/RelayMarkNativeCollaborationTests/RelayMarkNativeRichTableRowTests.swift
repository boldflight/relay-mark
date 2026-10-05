import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeRichTableRowTests: XCTestCase {
    func testCommunityAddRowAfterPreservesExistingTableAndReplaysUndo() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "table-add-row-v3", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let checkpoint = try native.snapshot()
        let state = try native.encodeUpdate()
        let cell = try native.anchor(path: [0, 1, 0], index: 0)
        XCTAssertTrue(RelayMarkNativeRichTableCommand.canApply(.addRowAfter, document: native, cellAnchor: cell,
            expectedCellID: "b00000000000040008000000000000008"))
        XCTAssertThrowsError(try RelayMarkNativeRichTableCommand.apply(.addRowAfter, document: native, cellAnchor: cell,
            expectedCellID: "b00000000000040008000000000000008", expectedSnapshot: Data()))
        XCTAssertThrowsError(try RelayMarkNativeRichTableCommand.apply(.addRowAfter, document: native, cellAnchor: cell,
            expectedCellID: "b00000000000040008000000000000009", expectedSnapshot: checkpoint))
        XCTAssertEqual(try native.encodeUpdate(), state)

        let change = try RelayMarkNativeRichTableCommand.apply(.addRowAfter, document: native, cellAnchor: cell,
            expectedCellID: "b00000000000040008000000000000008", expectedSnapshot: checkpoint)
        try peer.applyUpdate(change.update)
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        let rowID = after.blocks[0].childBlocks[2].id
        let cellIDs = after.blocks[0].childBlocks[2].childBlocks.map(\.id)
        let paragraphIDs = after.blocks[0].childBlocks[2].childBlocks.map { $0.childBlocks[0].id }
        XCTAssertEqual(cellIDs.count, 2)
        XCTAssertEqual(paragraphIDs.count, 2)
        XCTAssertEqual(after, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(after.blocks[0].childBlocks.prefix(2), before.blocks[0].childBlocks.prefix(2))
        XCTAssertEqual(after.blocks[0].childBlocks[2].id, rowID)
        XCTAssertEqual(after.blocks[0].childBlocks[2].childBlocks.map(\.id), cellIDs)
        XCTAssertEqual(after.blocks[0].childBlocks[2].childBlocks.map { $0.childBlocks[0].id },
                       paragraphIDs)
        XCTAssertEqual(after.blocks[0].childBlocks[2].childBlocks.map { $0.props["colwidth"] },
                       before.blocks[0].childBlocks[1].childBlocks.map { $0.props["colwidth"] })

        func replacing(_ value: Any) -> Any {
            if var object = value as? [String: Any] {
                let ids = ["b00000000000040008000000000000064": rowID,
                           "b00000000000040008000000000000065": cellIDs[0],
                           "b00000000000040008000000000000066": paragraphIDs[0],
                           "b00000000000040008000000000000067": cellIDs[1],
                           "b00000000000040008000000000000068": paragraphIDs[1]]
                if let id = object["id"] as? String, let replacement = ids[id] { object["id"] = replacement }
                return object.mapValues(replacing)
            }
            if let array = value as? [Any] { return array.map(replacing) }
            return value
        }
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: replacing(try XCTUnwrap(fixture["expected_ast"]))))
        XCTAssertEqual(after, expected)
        XCTAssertThrowsError(try RelayMarkNativeRichTableCommand.apply(.addRowAfter, document: native, cellAnchor: cell,
            expectedCellID: "b00000000000040008000000000000008", expectedSnapshot: checkpoint))
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)

    }
}
