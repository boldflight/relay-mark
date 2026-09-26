import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeMarkdownBlocksV3ProjectionTests: XCTestCase {
    func testCommunityInlineAtomsProjectExactIdentityAndRejectUnresolvedSource() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "inline-atoms-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: try XCTUnwrap(fixture["expected_ast"])))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try native.applyUpdate(update)
        XCTAssertTrue(native.integrationStatus().isComplete)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), expected)
        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: reopened), expected)

        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        func changed(_ edit: (inout [[String: Any]]) -> Void) throws -> Data {
            var snapshot = original
            var blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
            edit(&blocks)
            snapshot["children"] = blocks
            return try JSONSerialization.data(withJSONObject: snapshot)
        }
        let unresolved = try changed { blocks in
            var paragraph = blocks[0]
            var children = paragraph["children"] as! [[String: Any]]
            var reference = children[1]
            var attrs = reference["attributes"] as! [String: Any]
            attrs["entityId"] = NSNull()
            reference["attributes"] = attrs
            children[1] = reference
            paragraph["children"] = children
            blocks[0] = paragraph
        }
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: unresolved))
        let colored = try changed { blocks in
            var paragraph = blocks[0]
            var children = paragraph["children"] as! [[String: Any]]
            var tag = children[3]
            var attrs = tag["attributes"] as! [String: Any]
            attrs["color"] = "green"
            tag["attributes"] = attrs
            children[3] = tag
            paragraph["children"] = children
            blocks[0] = paragraph
        }
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: colored))
    }

    func testCommunityTaskListFixtureProjectsCheckedAndLinkedNestedItemsWithoutAdmittingEditing() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "task-list-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: try XCTUnwrap(fixture["expected_ast"])))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try native.applyUpdate(update)
        XCTAssertTrue(native.integrationStatus().isComplete)
        let actual = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.blocks[1].type, "task_list")
        XCTAssertEqual(actual.blocks[1].childBlocks[0].props["checked"], .bool(true))
        XCTAssertEqual(actual.blocks[1].childBlocks[0].props["entityId"],
                       .string(try XCTUnwrap(fixture["linked_entity_id"] as? String)))
        XCTAssertFalse(try native.markdownV3ProseProjection().isEditable)

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: reopened), expected)
    }

    private func fixture() throws -> (update: Data, expected: RelayMarkDocument) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "markdown-blocks-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(fixture["root"] as? String, "default")
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: try XCTUnwrap(fixture["expected_ast"])))
        return (update, expected)
    }

    func testCommunityOfferedMarksProjectAndRejectAttributedHighlight() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "inline-offered-marks-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: try XCTUnwrap(fixture["expected_ast"])))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try native.applyUpdate(update)
        XCTAssertTrue(native.integrationStatus().isComplete)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), expected)
        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: reopened), expected)

        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        var blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
        var paragraph = blocks[0]
        var leaves = try XCTUnwrap(paragraph["children"] as? [[String: Any]])
        var runs = try XCTUnwrap(leaves[0]["delta"] as? [[String: Any]])
        var marks = try XCTUnwrap(runs[2]["attributes"] as? [String: Any])
        marks["highlight"] = ["color": "yellow"]
        runs[2]["attributes"] = marks
        leaves[0]["delta"] = runs
        paragraph["children"] = leaves
        blocks[0] = paragraph
        snapshot["children"] = blocks
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(
            snapshot: JSONSerialization.data(withJSONObject: snapshot)))
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
        XCTAssertTrue(try native.markdownV3ProseProjection().isEditable)
    }

    func testCommunityImageFixtureProjectsToExactPortableASTWithoutAdmittingTextEditing() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich-image-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: try XCTUnwrap(fixture["expected_ast"])))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try native.applyUpdate(update)
        XCTAssertTrue(native.integrationStatus().isComplete)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), expected)
        XCTAssertEqual(expected.blocks.map(\.type), ["paragraph", "image", "paragraph"])
        XCTAssertFalse(try native.markdownV3ProseProjection().isEditable)

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: reopened), expected)

        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        func changed(_ edit: (inout [[String: Any]]) -> Void) throws -> Data {
            var snapshot = original
            var blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
            edit(&blocks)
            snapshot["children"] = blocks
            return try JSONSerialization.data(withJSONObject: snapshot)
        }
        let temporary = try changed { blocks in
            var image = blocks[1]
            var attrs = image["attributes"] as! [String: Any]
            attrs["src"] = "blob:upload-preview"
            image["attributes"] = attrs
            blocks[1] = image
        }
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: temporary))
        let secure = try changed { blocks in
            var image = blocks[1]
            var attrs = image["attributes"] as! [String: Any]
            attrs["src"] = "https://images.example.org/figure.png"
            image["attributes"] = attrs
            blocks[1] = image
        }
        var secureAST = try XCTUnwrap(fixture["expected_ast"] as? [String: Any])
        var secureBlocks = try XCTUnwrap(secureAST["blocks"] as? [[String: Any]])
        var secureImage = secureBlocks[1]
        var secureProps = try XCTUnwrap(secureImage["props"] as? [String: Any])
        secureProps["src"] = "https://images.example.org/figure.png"
        secureImage["props"] = secureProps
        secureBlocks[1] = secureImage
        secureAST["blocks"] = secureBlocks
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: secure),
                       try RelayMarkDocument.decodeJSON(JSONSerialization.data(withJSONObject: secureAST)))
        let credentials = try changed { blocks in
            var image = blocks[1]
            var attrs = image["attributes"] as! [String: Any]
            attrs["src"] = "https://user:pass@example.org/figure.png"
            image["attributes"] = attrs
            blocks[1] = image
        }
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: credentials))
        let dimensions = try changed { blocks in
            var image = blocks[1]
            var attrs = image["attributes"] as! [String: Any]
            attrs["width"] = 120
            image["attributes"] = attrs
            blocks[1] = image
        }
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: dimensions))
        let hidden = try changed { blocks in
            blocks[1]["children"] = [["kind": "text", "delta": [["insert": "hidden"]]]]
        }
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: hidden))
    }

    func testCommunityVideoFixtureProjectsOnlyDurableIdentity() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich-video-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: try XCTUnwrap(fixture["expected_ast"])))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try native.applyUpdate(update)
        XCTAssertTrue(native.integrationStatus().isComplete)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), expected)
        XCTAssertEqual(expected.blocks.map(\.type), ["paragraph", "relay.video_embed", "paragraph"])
        XCTAssertFalse(try native.markdownV3ProseProjection().isEditable)

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: reopened), expected)

        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        func changed(_ edit: (inout [[String: Any]]) -> Void) throws -> Data {
            var snapshot = original
            var blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
            edit(&blocks)
            snapshot["children"] = blocks
            return try JSONSerialization.data(withJSONObject: snapshot)
        }
        let hydrated = try changed { blocks in
            var video = blocks[1]
            var attrs = video["attributes"] as! [String: Any]
            attrs["playbackId"] = "derived-playback"
            video["attributes"] = attrs
            blocks[1] = video
        }
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: hydrated))
        let malformed = try changed { blocks in
            var video = blocks[1]
            var attrs = video["attributes"] as! [String: Any]
            attrs["videoId"] = "../private"
            video["attributes"] = attrs
            blocks[1] = video
        }
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: malformed))
        let hidden = try changed { blocks in
            blocks[1]["children"] = [["kind": "text", "delta": [["insert": "hidden"]]]]
        }
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: hidden))
    }

    func testCommunityCalloutFixtureKeepsRichTitleAndEditsExistingBodyLeaf() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich-callout-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: try XCTUnwrap(fixture["expected_ast"])))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try native.applyUpdate(update)
        XCTAssertTrue(native.integrationStatus().isComplete)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), expected)
        XCTAssertEqual(expected.blocks.map(\.type), ["paragraph", "relay.callout", "paragraph"])
        XCTAssertEqual(expected.blocks[1].childBlocks.map(\.type), ["relay.callout_title", "paragraph"])
        let prose = try native.markdownV3ProseProjection()
        XCTAssertTrue(prose.isEditable)
        XCTAssertEqual(prose.blockPaths, [[0], [1, 0], [1, 1], [2]])
        XCTAssertEqual(prose.callouts.count, 1)
        XCTAssertEqual(prose.callouts[0].id, expected.blocks[1].id)
        XCTAssertEqual(prose.callouts[0].tone, "warning")
        XCTAssertEqual(prose.callouts[0].emphasis, "strong")
        XCTAssertEqual((String(prose.text.characters) as NSString).substring(with: prose.callouts[0].range),
                       "Pay attention\nShared note")
        XCTAssertEqual((String(prose.text.characters) as NSString).substring(
            with: try XCTUnwrap(prose.callouts[0].titleRange)), "Pay attention")

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: reopened), expected)

        let delta = try RelayMarkNativeMarkdownV3TextMutation.replace(
            document: native, path: [1, 1, 0], start: 0, end: 6, text: "Together")
        try reopened.applyUpdate(delta)
        let edited = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        XCTAssertEqual(edited.blocks[1].id, expected.blocks[1].id)
        XCTAssertEqual(edited.blocks[1].childBlocks.map(\.id), expected.blocks[1].childBlocks.map(\.id))
        XCTAssertEqual(edited.blocks[1].childBlocks[1].plainText, "Together note")
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: reopened), edited)

        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        var blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
        var callout = blocks[1]
        var attrs = try XCTUnwrap(callout["attributes"] as? [String: Any])
        attrs["tone"] = "custom"
        callout["attributes"] = attrs
        blocks[1] = callout
        snapshot["children"] = blocks
        XCTAssertThrowsError(try RelayMarkNativeMarkdownBlocksV3Projection.project(
            snapshot: JSONSerialization.data(withJSONObject: snapshot)))
    }

    func testCommunityCalloutAppearanceChangeReplaysAndUndoesWithoutRebuildingContent() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich-callout-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument()
        let peer = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try peer.applyUpdate(update)
        let before = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        let id = before.blocks[1].id
        let calloutAnchor = try native.anchor(path: [1], index: 0)
        let titleAnchor = try native.anchor(path: [1, 0, 0], index: 4)
        let originalUpdate = try native.encodeUpdate()

        for (expectedID, expectedTone, expectedEmphasis, tone, emphasis) in [
            ("wrong", "warning", "strong", "info", "soft"),
            (id, "neutral", "strong", "info", "soft"),
            (id, "warning", "soft", "info", "soft"),
            (id, "warning", "strong", "unknown", "soft"),
            (id, "warning", "strong", "info", "unknown")
        ] {
            XCTAssertThrowsError(try native.setCalloutAppearance(
                anchor: calloutAnchor, expectedID: expectedID,
                expectedTone: expectedTone, expectedEmphasis: expectedEmphasis,
                tone: tone, emphasis: emphasis))
        }
        XCTAssertThrowsError(try native.setCalloutAppearance(
            anchor: try native.anchor(path: [0], index: 0), expectedID: id,
            expectedTone: "warning", expectedEmphasis: "strong", tone: "info", emphasis: "soft"))
        XCTAssertEqual(try native.encodeUpdate(), originalUpdate)

        let change = try native.setCalloutAppearance(
            anchor: calloutAnchor, expectedID: id,
            expectedTone: "warning", expectedEmphasis: "strong", tone: "info", emphasis: "soft")
        try peer.applyUpdate(change)
        let after = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        XCTAssertEqual(after.blocks[1].props["tone"], .string("info"))
        XCTAssertEqual(after.blocks[1].props["emphasis"], .string("soft"))
        XCTAssertEqual(after.blocks.map(\.id), before.blocks.map(\.id))
        XCTAssertEqual(after.blocks[1].childBlocks, before.blocks[1].childBlocks)
        XCTAssertEqual(try native.resolve(anchor: titleAnchor)?.path, [1, 0, 0])
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), after)
        XCTAssertThrowsError(try native.setCalloutAppearance(
            anchor: calloutAnchor, expectedID: id,
            expectedTone: "warning", expectedEmphasis: "strong", tone: "error", emphasis: "soft"))
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), before)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), before)
        try peer.applyUpdate(try XCTUnwrap(native.redo()))
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), after)
    }

    func testCalloutPlainFirstRunAcceptsTypingButBoldTitleBoundaryStaysFenced() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich-callout-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try peer.applyUpdate(update)
        let before = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        let delta = try RelayMarkNativeMarkdownV3TextMutation.replace(
            document: native, path: [1, 1, 0], start: 0, end: 0, text: "Ω ")
        try peer.applyUpdate(delta)
        let after = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        XCTAssertEqual(after.blocks[1].childBlocks[0], before.blocks[1].childBlocks[0])
        XCTAssertEqual(after.blocks[1].childBlocks[1].plainText, "Ω Shared note")
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), after)
        let checkpoint = try native.encodeUpdate()
        XCTAssertThrowsError(try RelayMarkNativeMarkdownV3TextMutation.replace(
            document: native, path: [1, 0, 0], start: 0, end: 0, text: "X"))
        XCTAssertEqual(try native.encodeUpdate(), checkpoint)
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
            runs[0]["attributes"] = ["textStyle": [:]]
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
