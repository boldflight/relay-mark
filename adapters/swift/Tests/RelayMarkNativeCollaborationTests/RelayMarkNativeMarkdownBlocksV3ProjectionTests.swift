import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeMarkdownBlocksV3ProjectionTests: XCTestCase {
    private func fixture() throws -> (update: Data, expected: RelayMarkDocument) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "markdown-blocks-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(fixture["root"] as? String, "default")
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: try XCTUnwrap(fixture["expected_ast"])))
        return (update, expected)
    }

    func testCommunityYjsFixtureProjectsToExactPortableASTAfterReplayAndReopen() throws {
        let (update, expected) = try fixture()
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try native.applyUpdate(update)
        XCTAssertTrue(native.integrationStatus().isComplete)
        let ast = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        XCTAssertEqual(ast, expected)
        XCTAssertEqual(ast.blocks.map(\.type), ["paragraph", "heading", "quote", "list", "list", "code", "horizontal_rule", "paragraph"])
        XCTAssertFalse(try native.proseProjection().isEditable)
        let prose = try native.markdownV3ProseProjection()
        XCTAssertTrue(prose.isEditable)
        XCTAssertTrue(String(prose.text.characters).contains("Before 🌍"))
        XCTAssertEqual(prose.position(atUTF16: 0)?.path, [0, 0])

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: reopened), expected)
    }

    func testMixedTableFixtureKeepsExistingTableProjection() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "table-mixed-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native),
                       try RelayMarkNativeMixedTableProjection.project(snapshot: native.snapshot()))
        XCTAssertFalse(try native.markdownV3ProseProjection().isEditable)
    }

    func testStableParagraphIDEditsSpannedTableCellWithoutRebuildingGrid() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "table-mixed-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        let before = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        let table = try XCTUnwrap(before.blocks.first { $0.type == "table" })
        let row = try XCTUnwrap(table.childBlocks.first)
        let cell = try XCTUnwrap(row.childBlocks.first)
        let paragraph = try XCTUnwrap(cell.childBlocks.first)
        XCTAssertEqual(paragraph.plainText, "A")

        let delta = try RelayMarkNativeMarkdownV3TextMutation.replace(
            document: native, blockID: paragraph.id, childIndex: 0,
            start: 0, end: 1, text: "Shared")
        let after = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        let updatedTable = try XCTUnwrap(after.blocks.first { $0.id == table.id })
        let updatedCell = try XCTUnwrap(updatedTable.childBlocks.first?.childBlocks.first)
        XCTAssertEqual(updatedCell.props, cell.props)
        XCTAssertEqual(updatedCell.childBlocks.first?.id, paragraph.id)
        XCTAssertEqual(updatedCell.childBlocks.first?.plainText, "Shared")

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(update)
        try reopened.applyUpdate(delta)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: reopened), after)
        let checkpoint = try native.encodeUpdate()
        XCTAssertThrowsError(try RelayMarkNativeMarkdownV3TextMutation.replace(
            document: native, blockID: "b00000000000040008000000000000000", childIndex: 0,
            start: 0, end: 0, text: "X"))
        XCTAssertEqual(try native.encodeUpdate(), checkpoint)
    }

    func testCommunityInlineMarksProjectToExactPortableASTAfterReplayAndReopen() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "inline-marks-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: try XCTUnwrap(fixture["expected_ast"])))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try native.applyUpdate(update)
        XCTAssertTrue(native.integrationStatus().isComplete)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), expected)
        let prose = try native.markdownV3ProseProjection()
        XCTAssertTrue(prose.isEditable)
        XCTAssertTrue(String(prose.text.characters).contains("bold italic strike"))

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: reopened), expected)

        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        var blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
        var paragraph = blocks[0]
        var leaves = try XCTUnwrap(paragraph["children"] as? [[String: Any]])
        var runs = try XCTUnwrap(leaves[2]["delta"] as? [[String: Any]])
        let linkIndex = try XCTUnwrap(runs.firstIndex { ($0["attributes"] as? [String: Any])?["link"] != nil })
        var marks = try XCTUnwrap(runs[linkIndex]["attributes"] as? [String: Any])
        var link = try XCTUnwrap(marks["link"] as? [String: Any])
        link["title"] = "unapproved"
        marks["link"] = link
        runs[linkIndex]["attributes"] = marks
        leaves[2]["delta"] = runs
        paragraph["children"] = leaves
        blocks[0] = paragraph
        snapshot["children"] = blocks
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(
            snapshot: JSONSerialization.data(withJSONObject: snapshot)))
    }

    func testBoundedV3TextMutationRetainsStructureAndSurvivesReplay() throws {
        let (update, expected) = try fixture()
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)

        let delta = try RelayMarkNativeMarkdownV3TextMutation.replace(
            document: native, path: [0, 0], start: 0, end: 6, text: "After")
        let updated = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        XCTAssertEqual(updated.blocks.map(\.id), expected.blocks.map(\.id))
        XCTAssertEqual(updated.blocks.dropFirst(), expected.blocks.dropFirst())
        XCTAssertEqual(updated.blocks[0].plainText, "After 🌍second line")

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(update)
        try reopened.applyUpdate(delta)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: reopened), updated)

        let checkpoint = try native.encodeUpdate()
        XCTAssertThrowsError(try RelayMarkNativeMarkdownV3TextMutation.replace(
            document: native, path: [0, 0], start: 0, end: 0, text: "\n"))
        XCTAssertThrowsError(try RelayMarkNativeMarkdownV3TextMutation.replace(
            document: native, path: [0], start: 0, end: 0, text: "X"))
        XCTAssertThrowsError(try RelayMarkNativeMarkdownV3TextMutation.replace(
            document: native, path: [0, 0], start: 7, end: 7, text: "X"))
        XCTAssertEqual(try native.encodeUpdate(), checkpoint)
    }

    func testV3TextMutationPreservesOneMarkedRunAndRejectsCrossMarkReplacement() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "inline-marks-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)

        _ = try RelayMarkNativeMarkdownV3TextMutation.replace(
            document: native, path: [0, 0], start: 8, end: 12, text: "BOLD")
        let projected = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        XCTAssertTrue(projected.blocks[0].plainText.contains("boBOLDtalic strike"))
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        let blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
        let children = try XCTUnwrap(blocks[0]["children"] as? [[String: Any]])
        let runs = try XCTUnwrap(children[0]["delta"] as? [[String: Any]])
        let marked = try XCTUnwrap(runs.first { ($0["insert"] as? String)?.contains("BOLD") == true })
        let attributes = try XCTUnwrap(marked["attributes"] as? [String: Any])
        XCTAssertEqual(Set(attributes.keys), Set(["bold", "italic", "strike"]))

        let checkpoint = try native.encodeUpdate()
        XCTAssertThrowsError(try RelayMarkNativeMarkdownV3TextMutation.replace(
            document: native, path: [0, 0], start: 5, end: 8, text: "cross"))
        XCTAssertEqual(try native.encodeUpdate(), checkpoint)
    }

    func testRejectsUnknownMetadataMarksDuplicateIDsAndDeeperLists() throws {
        let (update, _) = try fixture()
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        func changed(_ edit: (inout [[String: Any]]) -> Void) throws -> Data {
            var snapshot = original
            var blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
            edit(&blocks)
            snapshot["children"] = blocks
            return try JSONSerialization.data(withJSONObject: snapshot)
        }
        let unknown = try changed { blocks in
            var attrs = blocks[0]["attributes"] as! [String: Any]
            attrs["style"] = "unexpected"
            blocks[0]["attributes"] = attrs
        }
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: unknown))

        let duplicate = try changed { blocks in
            var attrs = blocks[1]["attributes"] as! [String: Any]
            attrs["relaymarkId"] = (blocks[0]["attributes"] as! [String: Any])["relaymarkId"]
            blocks[1]["attributes"] = attrs
        }
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: duplicate))

        let marked = try changed { blocks in
            var leaves = blocks[0]["children"] as! [[String: Any]]
            var runs = leaves[0]["delta"] as! [[String: Any]]
            runs[0]["attributes"] = ["highlight": [:]]
            leaves[0]["delta"] = runs
            blocks[0]["children"] = leaves
        }
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: marked))

        let deeper = try changed { blocks in
            var items = blocks[3]["children"] as! [[String: Any]]
            var firstChildren = items[0]["children"] as! [[String: Any]]
            var nestedItems = firstChildren[1]["children"] as! [[String: Any]]
            var nestedChildren = nestedItems[0]["children"] as! [[String: Any]]
            nestedChildren.append(firstChildren[1])
            nestedItems[0]["children"] = nestedChildren
            firstChildren[1]["children"] = nestedItems
            items[0]["children"] = firstChildren
            blocks[3]["children"] = items
        }
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: deeper))
    }
}
