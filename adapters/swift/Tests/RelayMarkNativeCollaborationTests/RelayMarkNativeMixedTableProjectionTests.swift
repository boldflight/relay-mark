import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeMixedTableProjectionTests: XCTestCase {
    private func fixture() throws -> (update: Data, raw: [String: Any]) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "table-mixed-v3-draft", withExtension: "json"))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(raw["update"] as? String)))
        return (update, raw)
    }

    func testMixedYjsReplayAndTypedASTKeepProseOrderIDsEmptyBlocksAndCellGeometry() throws {
        let (update, fixture) = try fixture()
        XCTAssertEqual(fixture["root"] as? String, "default")
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try native.applyUpdate(update)
        XCTAssertTrue(native.integrationStatus().isComplete)

        let snapshot = try native.snapshot()
        let ast = try RelayMarkNativeMixedTableProjection.project(snapshot: snapshot)
        XCTAssertEqual(ast.type, "relaymark.document")
        XCTAssertEqual(ast.version, 1)
        XCTAssertEqual(ast.blocks.map(\.type), ["paragraph", "table", "paragraph", "paragraph"])
        XCTAssertEqual(ast.blocks[0].plainText, "Before 🌍 <table>")
        XCTAssertEqual(ast.blocks[2].plainText, "")
        XCTAssertTrue(ast.blocks[2].content.isEmpty)
        XCTAssertEqual(ast.blocks[3].plainText, "After the shared table")

        let table = ast.blocks[1]
        XCTAssertEqual(table.childBlocks.count, 3)
        let header = try XCTUnwrap(table.childBlocks.first?.childBlocks.first)
        XCTAssertEqual(header.type, "table_cell")
        XCTAssertEqual(header.props["header"]?.boolValue, true)
        XCTAssertEqual(header.props["colspan"]?.numberValue, 2)
        XCTAssertEqual(header.props["rowspan"]?.numberValue, 1)
        XCTAssertEqual(header.props["colwidth"]?.arrayValue?.compactMap(\.numberValue), [120, 180])
        XCTAssertEqual(header.props["align"], .null)
        XCTAssertEqual(header.plainText, "A")
        XCTAssertEqual(table.childBlocks[1].childBlocks.map(\.plainText), ["Alice", "Bob"])
        XCTAssertEqual(table.childBlocks[2].childBlocks.count, 2)
        XCTAssertTrue(table.childBlocks[2].childBlocks.allSatisfy { $0.plainText.isEmpty })

        var ids = [String]()
        func collect(_ block: RelayMarkBlock) {
            ids.append(block.id)
            block.childBlocks.forEach(collect)
        }
        ast.blocks.forEach(collect)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(ids.count, 17)
        let normalized = try XCTUnwrap(fixture["normalized"] as? [String: Any])
        let nodes = try XCTUnwrap(normalized["content"] as? [[String: Any]])
        XCTAssertEqual(ast.blocks.map(\.id), nodes.compactMap { ($0["attrs"] as? [String: Any])?["relaymarkId"] as? String })

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertTrue(reopened.integrationStatus().isComplete)
        XCTAssertEqual(try RelayMarkNativeMixedTableProjection.project(snapshot: reopened.snapshot()), ast)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: reopened.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: snapshot) as? NSDictionary)
        XCTAssertFalse(try native.proseProjection().isEditable)
    }

    func testMixedProjectionRejectsUnknownMetadataMarksDuplicateIDsAndBrokenGrid() throws {
        let (update, _) = try fixture()
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        func changed(_ edit: (inout [String: Any]) -> Void) throws -> Data {
            var copy = original
            edit(&copy)
            return try JSONSerialization.data(withJSONObject: copy)
        }
        func nodes(_ snapshot: inout [String: Any], _ edit: (inout [[String: Any]]) -> Void) {
            var blocks = snapshot["children"] as! [[String: Any]]
            edit(&blocks)
            snapshot["children"] = blocks
        }

        let unknown = try changed { snapshot in
            nodes(&snapshot) { blocks in
                var attrs = blocks[0]["attributes"] as! [String: Any]
                attrs["style"] = "unsupported"
                blocks[0]["attributes"] = attrs
            }
        }
        XCTAssertThrowsError(try RelayMarkNativeMixedTableProjection.project(snapshot: unknown))

        let duplicate = try changed { snapshot in
            nodes(&snapshot) { blocks in
                var attrs = blocks[2]["attributes"] as! [String: Any]
                attrs["relaymarkId"] = (blocks[0]["attributes"] as! [String: Any])["relaymarkId"]
                blocks[2]["attributes"] = attrs
            }
        }
        XCTAssertThrowsError(try RelayMarkNativeMixedTableProjection.project(snapshot: duplicate))

        let marked = try changed { snapshot in
            nodes(&snapshot) { blocks in
                var leaves = blocks[0]["children"] as! [[String: Any]]
                var runs = leaves[0]["delta"] as! [[String: Any]]
                runs[0]["attributes"] = ["bold": [:]]
                leaves[0]["delta"] = runs
                blocks[0]["children"] = leaves
            }
        }
        XCTAssertThrowsError(try RelayMarkNativeMixedTableProjection.project(snapshot: marked))

        let brokenGrid = try changed { snapshot in
            nodes(&snapshot) { blocks in
                var rows = blocks[1]["children"] as! [[String: Any]]
                var cells = rows[0]["children"] as! [[String: Any]]
                var attrs = cells[0]["attributes"] as! [String: Any]
                attrs["colspan"] = 1
                attrs["colwidth"] = [120]
                cells[0]["attributes"] = attrs
                rows[0]["children"] = cells
                blocks[1]["children"] = rows
            }
        }
        XCTAssertThrowsError(try RelayMarkNativeMixedTableProjection.project(snapshot: brokenGrid))

        let hugeSpan = try changed { snapshot in
            nodes(&snapshot) { blocks in
                var rows = blocks[1]["children"] as! [[String: Any]]
                var cells = rows[0]["children"] as! [[String: Any]]
                var attrs = cells[0]["attributes"] as! [String: Any]
                attrs["colspan"] = Int.max
                attrs["colwidth"] = NSNull()
                cells[0]["attributes"] = attrs
                rows[0]["children"] = cells
                blocks[1]["children"] = rows
            }
        }
        XCTAssertThrowsError(try RelayMarkNativeMixedTableProjection.project(snapshot: hugeSpan))
        XCTAssertTrue(native.integrationStatus().isComplete)
    }
}
