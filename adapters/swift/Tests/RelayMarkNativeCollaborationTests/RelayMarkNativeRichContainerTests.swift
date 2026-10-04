import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeRichContainerTests: XCTestCase {
    private func fixture() throws -> (Data, RelayMarkDocument) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich-containers-v3", withExtension: "json"))
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return (try XCTUnwrap(Data(base64Encoded: XCTUnwrap(value["update"] as? String))),
                try RelayMarkDocument.decodeJSON(JSONSerialization.data(withJSONObject: XCTUnwrap(value["expected_ast"]))))
    }

    func testRichTaskAndCellProjectionRetainsGrammarAndCellGeometry() throws {
        let (seed, expected) = try fixture(), native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed); try peer.applyUpdate(seed)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), expected)
        let prose = try native.richProseProjection()
        XCTAssertTrue(prose.isEditable)
        XCTAssertEqual(prose.taskItems.count, 2)
        XCTAssertEqual(prose.tableCells.count, 5)
        XCTAssertEqual(prose.tableCells.map(\.column), [0, 0, 0, 1, 1])
        let task = try XCTUnwrap(prose.taskItems.first { $0.path.count > 2 })
        let before = try native.snapshot()
        let update = try native.setRichTaskItemChecked(path: task.path, expectedID: task.id,
            expectedEntityID: task.entityID, expectedChecked: task.checked, checked: !task.checked)
        try peer.applyUpdate(update)
        XCTAssertEqual(try native.snapshot(), try peer.snapshot())
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try native.snapshot(), before)
        XCTAssertEqual(try peer.snapshot(), before)
    }

    func testRichTaskAndCellReturnPreservesFollowingBlocksAndRelationship() throws {
        for (path, offset) in [([0, 0, 0], 3), ([0, 0, 1], 4), ([0, 0, 3, 0, 0, 0], 4),
                               ([0, 0, 3, 0, 1, 0, 0, 1], 4)] {
            let (seed, _) = try fixture(), native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try native.applyUpdate(seed); try peer.applyUpdate(seed)
            let before = try native.snapshot(), prose = try native.richProseProjection()
            let row = try XCTUnwrap(prose.blockPaths.firstIndex(of: path))
            let update = try RelayMarkNativeRichReturn.apply(document: native,
                blockPath: path, utf16Offset: offset, expectedSnapshot: before).update
            try peer.applyUpdate(update)
            XCTAssertEqual(try native.snapshot(), try peer.snapshot())
            XCTAssertEqual(String(try native.richProseProjection().text.characters),
                (String(prose.text.characters) as NSString).replacingCharacters(in:
                    NSRange(location: prose.blockRanges[row].location + offset, length: 0), with: "\n"))
            let outer = try RelayMarkNativeDocumentProjection.project(document: native).blocks[0].childBlocks[0]
            XCTAssertEqual(outer.props["entityId"]?.stringValue, "12345678-1234-4234-8234-123456789abc")
            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            XCTAssertEqual(try native.snapshot(), before)
            XCTAssertEqual(try peer.snapshot(), before)
        }
    }
}
