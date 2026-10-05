import Foundation
import XCTest
import RelayMarkSwift
import RelayMarkProseProjection
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeMixedTableProjectionTests: XCTestCase {
    private func fixture() throws -> (update: Data, raw: [String: Any]) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "table-mixed-v3-draft", withExtension: "json"))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(raw["update"] as? String)))
        return (update, raw)
    }

    func testAuthoredMergedAndPartialWidthsSurviveNativeReopenAndStaticRendering() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/relaymark/collaboration/fixtures/canonical-table-widths.json"))) as? [String: Any])
        let ast = try JSONSerialization.data(withJSONObject: fixture["document"]!)
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: ast)
        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(document.encodeUpdate())
        let cells = try reopened.richProseProjection().tableCells
        XCTAssertEqual(cells[0].columnWidths, [120, 180])
        XCTAssertEqual(cells[0].columnSpan, 2)
        XCTAssertEqual(cells[1].columnWidths, [0])
        XCTAssertEqual(cells[1].rowSpan, 2)
        XCTAssertEqual(cells[4].columnWidths, [0])
        XCTAssertEqual(cells[5].columnWidths, [90])
        let actual = try RelayMarkSourceCodec.snapshotToDocument(reopened.snapshot())
        let html = try RelayMarkSourceCodec.renderDocument(actual)
        for colgroup in fixture["expected_colgroups"] as! [String] { XCTAssertTrue(html.contains(colgroup)) }
        XCTAssertTrue(html.contains("colwidth=\"120,180\""))
        XCTAssertTrue(html.contains("style=\"text-align: center\""))
        XCTAssertFalse(html.contains("width: 0px"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: actual) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: ast) as? NSDictionary)
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

    func testCellTextUsesTheSameNativeSelectionAndYrsMutationPath() throws {
        let (seed, _) = try fixture()
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try native.richProseProjection()
        XCTAssertTrue(before.isEditable)
        let header = try XCTUnwrap(before.tableCells.first)
        XCTAssertEqual(header.columns, 2)
        XCTAssertEqual(header.row, 0)
        XCTAssertEqual(header.column, 0)
        XCTAssertEqual(header.rowSpan, 1)
        XCTAssertEqual(header.columnSpan, 2)
        XCTAssertTrue(header.header)
        XCTAssertEqual(header.columnWidths, [120, 180])
        XCTAssertNil(header.alignment)
        XCTAssertEqual(before.tableCells.filter { $0.row == 1 }.map(\.column), [0, 1])
        XCTAssertEqual(before.tableCells.first(where: { $0.row == 1 && $0.column == 0 })?.columnWidths, [120])
        let text = String(before.text.characters)
        let alice = (text as NSString).range(of: "Alice")
        XCTAssertNotEqual(alice.location, NSNotFound)
        let slices = before.textRanges(in: alice)
        XCTAssertEqual(slices.count, 1)
        let slice = try XCTUnwrap(slices.first)
        XCTAssertEqual(slice.path, [1, 1, 0, 0, 0])
        XCTAssertEqual(slice.length, alice.length)

        let original = try RelayMarkNativeDocumentProjection.project(document: native)
        let update = try RelayMarkNativeRichTextMutation.replace(
            document: native, path: slice.path, start: slice.index,
            end: slice.index + slice.length, text: "Alicia")
        try peer.applyUpdate(update)
        let edited = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(edited, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(edited.blocks[1].childBlocks[1].childBlocks[0].plainText, "Alicia")
        XCTAssertEqual(edited.blocks[1].childBlocks[0], original.blocks[1].childBlocks[0])
        XCTAssertEqual(edited.blocks[1].childBlocks[1].childBlocks[1], original.blocks[1].childBlocks[1].childBlocks[1])

        let bold = try native.formatText(at: 0, length: 1, attributes: ["bold": [:]],
                                         path: [1, 0, 0, 0, 0])
        try peer.applyUpdate(bold)
        let appended = try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [1, 0, 0, 0, 0], start: 1, end: 1, text: "!")
        try peer.applyUpdate(appended)
        let styled = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(styled, try RelayMarkNativeDocumentProjection.project(document: peer))
        let headerParagraph = styled.blocks[1].childBlocks[0].childBlocks[0].childBlocks[0]
        guard case .inline(let strong)? = headerParagraph.content.first else {
            return XCTFail("Expected bold table header")
        }
        XCTAssertEqual(strong.type, "strong")
        XCTAssertEqual(strong.plainText, "A!")
    }

    func testTypingSeedsAnEmptyTableCellWithoutReplacingItsParagraph() throws {
        let (seed, _) = try fixture()
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let path = [1, 2, 0, 0]
        let projection = try native.richProseProjection()
        let index = try XCTUnwrap(projection.blockPaths.firstIndex(of: path))
        XCTAssertEqual(projection.blockRanges[index].length, 0)
        let update = try RelayMarkNativeRichTextMutation.replace(
            document: native, path: path, start: 0, end: 0, text: "First")
        try peer.applyUpdate(update)
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(after, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(after.blocks[1].childBlocks[2].childBlocks[0].plainText, "First")
        XCTAssertEqual(after.blocks[1].childBlocks[2].childBlocks[0].id,
                       before.blocks[1].childBlocks[2].childBlocks[0].id)
        XCTAssertEqual(after.blocks[1].childBlocks[2].childBlocks[1],
                       before.blocks[1].childBlocks[2].childBlocks[1])
    }

    func testMixedProjectionSharesInlineMarksAndRejectsUnknownMetadataDuplicateIDsAndBrokenGrid() throws {
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
                var rows = blocks[1]["children"] as! [[String: Any]]
                var cells = rows[0]["children"] as! [[String: Any]]
                var paragraphs = cells[0]["children"] as! [[String: Any]]
                var leaves = paragraphs[0]["children"] as! [[String: Any]]
                var runs = leaves[0]["delta"] as! [[String: Any]]
                runs[0]["attributes"] = ["bold": [:]]
                leaves[0]["delta"] = runs
                paragraphs[0]["children"] = leaves
                cells[0]["children"] = paragraphs
                rows[0]["children"] = cells
                blocks[1]["children"] = rows
            }
        }
        let markedAST = try RelayMarkNativeMixedTableProjection.project(snapshot: marked)
        guard case .inline(let inline)? = markedAST.blocks[1].childBlocks[0].childBlocks[0].childBlocks[0].content.first else {
            return XCTFail("Expected marked table cell text")
        }
        XCTAssertEqual(inline.type, "strong")
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: marked), markedAST)

        let unknownMark = try changed { snapshot in
            nodes(&snapshot) { blocks in
                var leaves = blocks[0]["children"] as! [[String: Any]]
                var runs = leaves[0]["delta"] as! [[String: Any]]
                runs[0]["attributes"] = ["unsupported": [:]]
                leaves[0]["delta"] = runs
                blocks[0]["children"] = leaves
            }
        }
        XCTAssertThrowsError(try RelayMarkNativeMixedTableProjection.project(snapshot: unknownMark))

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

        let aligned = try changed { snapshot in
            nodes(&snapshot) { blocks in
                var rows = blocks[1]["children"] as! [[String: Any]]
                var cells = rows[1]["children"] as! [[String: Any]]
                var attrs = cells[0]["attributes"] as! [String: Any]
                attrs["align"] = "right"
                cells[0]["attributes"] = attrs
                rows[1]["children"] = cells
                blocks[1]["children"] = rows
            }
        }
        let alignedProse = try RelayMarkCollaborativeProse(snapshot: aligned, dialect: .rich)
        XCTAssertTrue(alignedProse.isEditable)
        XCTAssertEqual(alignedProse.tableCells.first(where: { $0.row == 1 && $0.column == 0 })?.alignment, "right")

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
