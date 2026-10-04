import Foundation
import XCTest
import RelayMarkSwift
import RelayMarkProseProjection
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeDocumentProjectionTests: XCTestCase {
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
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), expected)
        let prose = try native.richProseProjection()
        XCTAssertTrue(prose.isEditable)
        XCTAssertEqual(String(prose.text.characters), "Meet \u{FFFC} for \u{FFFC}. [[unknown]] stays text.\n\u{FFFC}")
        XCTAssertEqual(prose.inlineAtoms.map(\.kind), [.relayReference, .relayTag, .relayReference])
        XCTAssertEqual(prose.inlineAtoms.map(\.path), [[0, 1], [0, 3], [1, 0]])
        XCTAssertEqual(prose.inlineAtoms.map(\.range), [
            NSRange(location: 5, length: 1), NSRange(location: 11, length: 1),
            NSRange(location: 38, length: 1)
        ])
        XCTAssertEqual(prose.inlineAtoms.map(\.id), [
            "9f815b37-67b3-4101-868c-5335351feb6a",
            "9712027d-18db-448e-8514-cea7c215d6f7",
            "12345678-1234-4234-8234-123456789abc"
        ])
        XCTAssertEqual(prose.inlineAtoms.map(\.label), ["Ada Lovelace", "#today", "Prepare review"])
        XCTAssertEqual(prose.inlineAtoms.map(\.source), [
            "[[Person: 9f815b37-67b3-4101-868c-5335351feb6a | Ada Lovelace]]",
            "[[Tag: 9712027d-18db-448e-8514-cea7c215d6f7 | #today]]",
            "[[Task: 12345678-1234-4234-8234-123456789abc | Prepare review]]"
        ])
        XCTAssertEqual(prose.textRanges(in: NSRange(location: 0, length: 39)).map(\.path),
                       [[0, 0], [0, 2], [0, 4]])
        for atom in prose.inlineAtoms {
            XCTAssertTrue(prose.textRanges(in: atom.range).isEmpty)
            for edge in [atom.range.location, NSMaxRange(atom.range)] {
                let position = try XCTUnwrap(prose.position(atUTF16: edge))
                XCTAssertEqual(prose.offset(path: position.path, index: position.index), edge)
            }
        }
        XCTAssertEqual(prose.position(atUTF16: 5)?.path, [0, 0])
        XCTAssertEqual(prose.position(atUTF16: 6)?.path, [0, 2])
        XCTAssertEqual(prose.position(atUTF16: 11)?.path, [0, 2])
        XCTAssertEqual(prose.position(atUTF16: 12)?.path, [0, 4])
        XCTAssertEqual(prose.position(atUTF16: 38)?.path, [1])
        XCTAssertEqual(prose.position(atUTF16: 38)?.index, 0)
        XCTAssertEqual(prose.position(atUTF16: 39)?.path, [1])
        XCTAssertEqual(prose.position(atUTF16: 39)?.index, 1)

        _ = try native.insertText("new ", at: 0, path: [0, 2])
        let edited = try native.richProseProjection()
        XCTAssertEqual(String(edited.text.characters), "Meet \u{FFFC}new  for \u{FFFC}. [[unknown]] stays text.\n\u{FFFC}")
        XCTAssertEqual(edited.inlineAtoms.map(\.range.location), [5, 15, 42])
        XCTAssertEqual(edited.inlineAtoms.map(\.id), prose.inlineAtoms.map(\.id))
        let editedAST = try RelayMarkNativeDocumentProjection.project(document: native)
        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: reopened), editedAST)

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
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: unresolved))
        XCTAssertFalse(try RelayMarkCollaborativeProse(snapshot: unresolved, dialect: .rich).isEditable)
        let mismatchedSource = try changed { blocks in
            var paragraph = blocks[0]
            var children = paragraph["children"] as! [[String: Any]]
            var reference = children[1]
            var attrs = reference["attributes"] as! [String: Any]
            attrs["source"] = "[[Person: 9f815b37-67b3-4101-868c-5335351feb6a | Someone else]]"
            reference["attributes"] = attrs
            children[1] = reference
            paragraph["children"] = children
            blocks[0] = paragraph
        }
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: mismatchedSource))
        XCTAssertFalse(try RelayMarkCollaborativeProse(snapshot: mismatchedSource, dialect: .rich).isEditable)
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
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: colored))
        XCTAssertFalse(try RelayMarkCollaborativeProse(snapshot: colored, dialect: .rich).isEditable)
    }

    func testCommunityTaskListFixtureProjectsCheckedAndLinkedNestedItemsInUnifiedProseMap() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "task-list-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: try XCTUnwrap(fixture["expected_ast"])))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try native.applyUpdate(update)
        XCTAssertTrue(native.integrationStatus().isComplete)
        let actual = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.blocks[1].type, "task_list")
        XCTAssertEqual(actual.blocks[1].childBlocks[0].props["checked"], .bool(true))
        XCTAssertEqual(actual.blocks[1].childBlocks[0].props["entityId"],
                       .string(try XCTUnwrap(fixture["linked_entity_id"] as? String)))
        let prose = try native.richProseProjection()
        XCTAssertTrue(prose.isEditable)
        XCTAssertEqual(prose.taskItems.map(\.path), [[1, 0], [1, 0, 2, 0], [1, 1]])
        XCTAssertEqual(prose.taskItems.map(\.checked), [true, false, false])
        XCTAssertEqual(prose.taskItems.map(\.entityID), [fixture["linked_entity_id"] as? String, nil, nil])
        XCTAssertTrue(prose.taskItems.allSatisfy { $0.firstParagraphRange.location >= 0 })

        var malformed = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        var blocks = try XCTUnwrap(malformed["children"] as? [[String: Any]])
        var list = blocks[1]
        var items = try XCTUnwrap(list["children"] as? [[String: Any]])
        var item = items[0]
        var attributes = try XCTUnwrap(item["attributes"] as? [String: Any])
        attributes["checked"] = "true"
        item["attributes"] = attributes
        items[0] = item
        list["children"] = items
        blocks[1] = list
        malformed["children"] = blocks
        XCTAssertFalse(try RelayMarkCollaborativeProse(
            snapshot: JSONSerialization.data(withJSONObject: malformed), dialect: .rich).isEditable)

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: reopened), expected)
    }

    func testMixedTaskProseEditsConvergeWithoutChangingTaskStructure() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "task-list-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let prose = try native.richProseProjection()
        XCTAssertTrue(prose.isEditable)

        for path in [[0, 0], [1, 0, 2, 0, 0, 0]] {
            let range = try XCTUnwrap(prose.blockPaths.firstIndex(of: Array(path.dropLast())))
            let selection = NSRange(location: prose.blockRanges[range].location, length: 0)
            let position = try XCTUnwrap(prose.position(atUTF16: selection.location))
            XCTAssertEqual(position.path, path)
            let update = try RelayMarkNativeRichTextMutation.replace(
                document: native, path: path, start: 0, end: 0, text: "Edited ")
            try peer.applyUpdate(update)
        }
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(after, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(after.blocks[1].id, before.blocks[1].id)
        XCTAssertEqual(after.blocks[1].childBlocks.map(\.id), before.blocks[1].childBlocks.map(\.id))
        XCTAssertEqual(after.blocks[1].childBlocks[0].props, before.blocks[1].childBlocks[0].props)
        XCTAssertEqual(after.blocks[0].plainText, "Edited " + before.blocks[0].plainText)
        XCTAssertEqual(after.blocks[1].childBlocks[0].childBlocks[2].childBlocks[0].plainText,
                       "Edited " + before.blocks[1].childBlocks[0].childBlocks[2].childBlocks[0].plainText)
    }

    func testNestedTaskToggleReplaysAndUndoesWithoutRetargetingAnotherItem() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "task-list-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try native.richProseProjection()
        let nested = try XCTUnwrap(before.taskItems.first(where: { $0.path == [1, 0, 2, 0] }))
        let update = try native.setRichTaskItemChecked(path: nested.path, expectedID: nested.id,
            expectedEntityID: nested.entityID, expectedChecked: false, checked: true)
        try peer.applyUpdate(update)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native),
                       try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(try native.richProseProjection().taskItems.map(\.checked), [true, true, false])
        XCTAssertThrowsError(try native.setRichTaskItemChecked(path: nested.path, expectedID: nested.id,
            expectedEntityID: nested.entityID, expectedChecked: false, checked: true))
        XCTAssertThrowsError(try native.setRichTaskItemChecked(path: [1, 1], expectedID: nested.id,
            expectedEntityID: nested.entityID, expectedChecked: false, checked: true))
        let undo = try XCTUnwrap(native.undo())
        try peer.applyUpdate(undo)
        XCTAssertEqual(try native.richProseProjection().taskItems.map(\.checked), before.taskItems.map(\.checked))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native),
                       try RelayMarkNativeDocumentProjection.project(document: peer))
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
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), expected)
        let prose = try native.richProseProjection()
        XCTAssertTrue(prose.isEditable)
        let offered = prose.text.runs.compactMap { run -> Set<RelayMarkOfferedMark>? in
            run[RelayMarkOfferedMarksAttribute.self]
        }
        XCTAssertTrue(offered.contains([.underline]))
        XCTAssertTrue(offered.contains([.highlight]))
        XCTAssertTrue(offered.contains([.superscript]))
        XCTAssertTrue(offered.contains([.subscript]))
        XCTAssertTrue(offered.contains(Set(RelayMarkOfferedMark.allCases)))
        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: reopened), expected)

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
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(
            snapshot: JSONSerialization.data(withJSONObject: snapshot)))
    }

    func testCommunityYjsFixtureProjectsToExactPortableASTAfterReplayAndReopen() throws {
        let (update, expected) = try fixture()
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try native.applyUpdate(update)
        XCTAssertTrue(native.integrationStatus().isComplete)
        let ast = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(ast, expected)
        XCTAssertEqual(ast.blocks.map(\.type), ["paragraph", "heading", "quote", "list", "list", "code", "horizontal_rule", "paragraph"])
        XCTAssertFalse(try native.proseProjection().isEditable)
        let prose = try native.richProseProjection()
        XCTAssertTrue(prose.isEditable)
        XCTAssertTrue(String(prose.text.characters).contains("Before 🌍"))
        XCTAssertEqual(prose.position(atUTF16: 0)?.path, [0, 0])

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: reopened), expected)
    }

    func testMixedTableFixtureKeepsExistingTableProjection() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "table-mixed-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native),
                       try RelayMarkNativeMixedTableProjection.project(snapshot: native.snapshot()))
        XCTAssertTrue(try native.richProseProjection().isEditable)
    }

    func testCommunityImageFixtureProjectsToExactPortableASTWithProtectedMediaAtom() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich-image-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: try XCTUnwrap(fixture["expected_ast"])))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try native.applyUpdate(update)
        XCTAssertTrue(native.integrationStatus().isComplete)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), expected)
        XCTAssertEqual(expected.blocks.map(\.type), ["paragraph", "image", "paragraph"])
        let prose = try native.richProseProjection()
        XCTAssertTrue(prose.isEditable)
        XCTAssertEqual(prose.mediaAtoms.count, 1)
        XCTAssertEqual(prose.mediaAtoms[0].kind, .image)
        XCTAssertEqual(prose.mediaAtoms[0].id, "b28718f2e96f1458d9608c7222745fbc0")
        XCTAssertEqual(prose.mediaAtoms[0].source, "/m/11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(prose.mediaAtoms[0].alt, "Shared diagram")
        XCTAssertEqual(prose.mediaAtoms[0].title, "Planning")
        XCTAssertEqual(prose.mediaAtoms[0].path, [1])
        XCTAssertEqual(prose.mediaAtoms[0].range.length, 1)
        XCTAssertTrue(prose.textRanges(in: prose.mediaAtoms[0].range).isEmpty)
        XCTAssertEqual(prose.position(atUTF16: prose.mediaAtoms[0].range.location)?.path, [1])

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: reopened), expected)

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
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: temporary))
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
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: secure),
                       try RelayMarkDocument.decodeJSON(JSONSerialization.data(withJSONObject: secureAST)))
        let credentials = try changed { blocks in
            var image = blocks[1]
            var attrs = image["attributes"] as! [String: Any]
            attrs["src"] = "https://user:pass@example.org/figure.png"
            image["attributes"] = attrs
            blocks[1] = image
        }
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: credentials))
        let dimensions = try changed { blocks in
            var image = blocks[1]
            var attrs = image["attributes"] as! [String: Any]
            attrs["width"] = -120
            image["attributes"] = attrs
            blocks[1] = image
        }
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: dimensions))
        let hidden = try changed { blocks in
            blocks[1]["children"] = [["kind": "text", "delta": [["insert": "hidden"]]]]
        }
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: hidden))
    }

    func testCommunityEntityReferenceFixturePreservesAuthoredSource() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "entity-reference-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: try XCTUnwrap(fixture["expected_ast"])))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), expected)
        let prose = try native.richProseProjection()
        XCTAssertTrue(prose.isEditable)
        XCTAssertEqual(prose.entityReferenceAtoms.count, 1)

        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        var blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
        var reference = blocks[1]
        var attrs = try XCTUnwrap(reference["attributes"] as? [String: Any])
        attrs["projection"] = "chip"
        reference["attributes"] = attrs
        blocks[1] = reference
        snapshot["children"] = blocks
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(
            snapshot: JSONSerialization.data(withJSONObject: snapshot)))
    }

    func testCommunityPaperControlsFixtureProjectsOnlyAuthoredFields() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "paper-controls-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: try XCTUnwrap(fixture["expected_ast"])))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), expected)
        let prose = try native.richProseProjection()
        XCTAssertTrue(prose.isEditable)
        XCTAssertEqual(String(prose.text.characters), "Before\n\u{FFFC}\n\u{FFFC}\n\u{FFFC}\n\u{FFFC}\n\u{FFFC}\nAfter")
        XCTAssertEqual(prose.blockAtoms.map(\.control), [.anchor, .button, .button, .button, .connection])
        XCTAssertEqual(prose.blockAtoms.map(\.id), (62...66).map {
            "b000000000000400080000000000000\($0)"
        })
        XCTAssertEqual(prose.blockAtoms.map(\.path), [[1], [2], [3], [4], [5]])
        XCTAssertEqual(prose.blockAtoms.map(\.range.location), [7, 9, 11, 13, 15])
        XCTAssertEqual(prose.blockAtoms.map(\.range.length), [1, 1, 1, 1, 1])
        XCTAssertEqual(prose.blockAtoms.map(\.displayLabel), ["next", "Next", "Search Alex", "Docs", "google"])
        XCTAssertEqual(prose.blockAtoms.map(\.source), [
            "@Anchor(name: \"next\")",
            "@Button(label: \"Next\", kind: \"anchor\", target: \"next\")",
            "@Button(label: \"Search Alex\", kind: \"command\", target: \"/search Alex\")",
            "@Button(label: \"Docs\", kind: \"link\", target: \"https://example.com/docs\")",
            "@Connection(provider: \"google\")"
        ])
        XCTAssertEqual(prose.textRanges(in: NSRange(location: 0, length: 22)).map(\.path), [[0, 0], [6, 0]])
        for atom in prose.blockAtoms {
            XCTAssertTrue(prose.textRanges(in: atom.range).isEmpty)
            for edge in [atom.range.location, NSMaxRange(atom.range)] {
                let position = try XCTUnwrap(prose.position(atUTF16: edge))
                XCTAssertEqual(prose.offset(path: position.path, index: position.index), edge)
            }
        }
        _ = try native.insertText("!", at: 6, path: [0, 0])
        let edited = try native.richProseProjection()
        XCTAssertEqual(edited.blockAtoms.map(\.range.location), [8, 10, 12, 14, 16])
        XCTAssertEqual(edited.blockAtoms.map(\.id), prose.blockAtoms.map(\.id))

        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        var blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
        var button = blocks[2]
        var attrs = try XCTUnwrap(button["attributes"] as? [String: Any])
        attrs["authorized"] = true
        button["attributes"] = attrs
        blocks[2] = button
        snapshot["children"] = blocks
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(
            snapshot: JSONSerialization.data(withJSONObject: snapshot)))
        XCTAssertFalse(try RelayMarkCollaborativeProse(snapshot: JSONSerialization.data(withJSONObject: snapshot),
                                                        dialect: .rich).isEditable)
        attrs.removeValue(forKey: "authorized")
        attrs["target"] = "javascript:alert(1)"
        button["attributes"] = attrs
        blocks[2] = button
        snapshot["children"] = blocks
        let unsafeTarget = try JSONSerialization.data(withJSONObject: snapshot)
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: unsafeTarget))
        XCTAssertFalse(try RelayMarkCollaborativeProse(snapshot: unsafeTarget, dialect: .rich).isEditable)
        attrs["target"] = "next"
        button["attributes"] = attrs
        button["children"] = [["kind": "text", "delta": [["insert": "hidden"]]]]
        blocks[2] = button
        snapshot["children"] = blocks
        let hiddenChild = try JSONSerialization.data(withJSONObject: snapshot)
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: hiddenChild))
        XCTAssertFalse(try RelayMarkCollaborativeProse(snapshot: hiddenChild, dialect: .rich).isEditable)
    }

    func testCommunityAgentSuggestionFixtureProjectsOnlyAuthoredContent() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "agent-suggestion-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: try XCTUnwrap(fixture["expected_ast"])))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), expected)
        let suggestion = try XCTUnwrap(expected.blocks.dropFirst().first)
        XCTAssertEqual(suggestion.type, "relay.agent_suggestion")
        XCTAssertEqual(suggestion.props["review"], .string("ready"))
        XCTAssertNil(suggestion.props["proposalId"])
        let prose = try native.richProseProjection()
        XCTAssertTrue(prose.isEditable)
        XCTAssertEqual(String(prose.text.characters), "Before\n\u{FFFC}\nAfter")
        XCTAssertEqual(prose.suggestionAtoms.count, 1)
        let atom = try XCTUnwrap(prose.suggestionAtoms.first)
        XCTAssertEqual(atom.id, "b00000000000040008000000000000082")
        XCTAssertEqual(atom.review, "ready")
        XCTAssertEqual(atom.kind, "note")
        XCTAssertEqual(atom.confidence, 0.88)
        XCTAssertEqual(atom.evidence, [])
        XCTAssertEqual(atom.content, "Check **this** source.")
        XCTAssertEqual(atom.range, NSRange(location: 7, length: 1))
        XCTAssertEqual(atom.path, [1])
        XCTAssertEqual(prose.textRanges(in: atom.range), [])
        XCTAssertEqual(prose.textRanges(in: NSRange(location: 0, length: 13)).map(\.path), [[0, 0], [2, 0]])
        for edge in [atom.range.location, NSMaxRange(atom.range)] {
            let position = try XCTUnwrap(prose.position(atUTF16: edge))
            XCTAssertEqual(prose.offset(path: position.path, index: position.index), edge)
        }
        XCTAssertThrowsError(try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [1], start: 0, end: 1, text: "replacement"))
        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(try native.encodeUpdate())
        _ = try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [0, 0], start: 6, end: 6, text: "!")
        _ = try RelayMarkNativeRichTextMutation.replace(
            document: peer, path: [2, 0], start: 0, end: 0, text: "?")
        try native.applyUpdate(try peer.encodeUpdate())
        try peer.applyUpdate(try native.encodeUpdate())
        let edited = try native.richProseProjection()
        XCTAssertEqual(String(edited.text.characters), "Before!\n\u{FFFC}\n?After")
        XCTAssertEqual(String(try peer.richProseProjection().text.characters),
                       String(edited.text.characters))
        XCTAssertEqual(edited.suggestionAtoms.first?.id, atom.id)
        XCTAssertEqual(edited.suggestionAtoms.first?.range, NSRange(location: 8, length: 1))
        XCTAssertEqual(edited.suggestionAtoms.first?.content, atom.content)

        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        func altered(_ edit: (inout [String: Any]) -> Void) throws -> Data {
            var snapshot = original
            var blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
            var node = blocks[1]
            edit(&node)
            blocks[1] = node
            snapshot["children"] = blocks
            return try JSONSerialization.data(withJSONObject: snapshot)
        }
        for key in ["proposalId", "proposalStatus", "title", "undoable", "source"] {
            let bad = try altered { node in
                var attrs = node["attributes"] as! [String: Any]
                attrs[key] = "host-only"
                node["attributes"] = attrs
            }
            XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: bad))
            XCTAssertFalse(try RelayMarkCollaborativeProse(snapshot: bad, dialect: .rich).isEditable)
        }
        let rejected = try altered { node in
            var attrs = node["attributes"] as! [String: Any]
            attrs["review"] = "accepted"
            node["attributes"] = attrs
        }
        XCTAssertFalse(try RelayMarkCollaborativeProse(snapshot: rejected, dialect: .rich).isEditable)
        let child = try altered { $0["children"] = [["kind": "text", "delta": [["insert": "hidden"]]]] }
        XCTAssertFalse(try RelayMarkCollaborativeProse(snapshot: child, dialect: .rich).isEditable)
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
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), expected)
        XCTAssertEqual(expected.blocks.map(\.type), ["paragraph", "relay.video_embed", "paragraph"])
        let prose = try native.richProseProjection()
        XCTAssertTrue(prose.isEditable)
        XCTAssertEqual(prose.mediaAtoms.count, 1)
        XCTAssertEqual(prose.mediaAtoms[0].kind, .videoEmbed)
        XCTAssertEqual(prose.mediaAtoms[0].id, "b28718f2e96f1458d9608c7222745fbc0")
        XCTAssertEqual(prose.mediaAtoms[0].source, "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(prose.mediaAtoms[0].path, [1])
        XCTAssertEqual(prose.mediaAtoms[0].range.length, 1)

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: reopened), expected)

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
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: hydrated))
        let malformed = try changed { blocks in
            var video = blocks[1]
            var attrs = video["attributes"] as! [String: Any]
            attrs["videoId"] = "../private"
            video["attributes"] = attrs
            blocks[1] = video
        }
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: malformed))
        let hidden = try changed { blocks in
            blocks[1]["children"] = [["kind": "text", "delta": [["insert": "hidden"]]]]
        }
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: hidden))
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
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), expected)
        XCTAssertEqual(expected.blocks.map(\.type), ["paragraph", "relay.callout", "paragraph"])
        XCTAssertEqual(expected.blocks[1].childBlocks.map(\.type), ["relay.callout_title", "paragraph"])
        let prose = try native.richProseProjection()
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
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: reopened), expected)

        let delta = try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [1, 1, 0], start: 0, end: 6, text: "Together")
        try reopened.applyUpdate(delta)
        let edited = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(edited.blocks[1].id, expected.blocks[1].id)
        XCTAssertEqual(edited.blocks[1].childBlocks.map(\.id), expected.blocks[1].childBlocks.map(\.id))
        XCTAssertEqual(edited.blocks[1].childBlocks[1].plainText, "Together note")
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: reopened), edited)

        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        var blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
        var callout = blocks[1]
        var attrs = try XCTUnwrap(callout["attributes"] as? [String: Any])
        attrs["tone"] = "custom"
        callout["attributes"] = attrs
        blocks[1] = callout
        snapshot["children"] = blocks
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(
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
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
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
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(after.blocks[1].props["tone"], .string("info"))
        XCTAssertEqual(after.blocks[1].props["emphasis"], .string("soft"))
        XCTAssertEqual(after.blocks.map(\.id), before.blocks.map(\.id))
        XCTAssertEqual(after.blocks[1].childBlocks, before.blocks[1].childBlocks)
        XCTAssertEqual(try native.resolve(anchor: titleAnchor)?.path, [1, 0, 0])
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), after)
        XCTAssertThrowsError(try native.setCalloutAppearance(
            anchor: calloutAnchor, expectedID: id,
            expectedTone: "warning", expectedEmphasis: "strong", tone: "error", emphasis: "soft"))
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)
        try peer.applyUpdate(try XCTUnwrap(native.redo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), after)
    }

    func testBrowserCalloutAddTitleReplaysUndoesAndRejectsStaleCheckpoint() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "callout-add-title-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let source = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(source)
        try peer.applyUpdate(source)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let checkpoint = try native.snapshot()
        let state = try native.encodeUpdate()
        let calloutID = before.blocks[1].id
        let anchor = try native.anchor(path: [1], index: 0)
        XCTAssertThrowsError(try native.addCalloutTitle(anchor: anchor, expectedID: "wrong", expectedSnapshot: checkpoint))
        XCTAssertThrowsError(try native.addCalloutTitle(anchor: try native.anchor(path: [0], index: 0),
                                                        expectedID: calloutID, expectedSnapshot: checkpoint))
        XCTAssertEqual(try native.encodeUpdate(), state)

        let change = try native.addCalloutTitle(anchor: anchor, expectedID: calloutID,
                                                expectedSnapshot: checkpoint)
        try peer.applyUpdate(change.update)
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        var expected = try XCTUnwrap(fixture["expected_ast_after_add_title"] as? [String: Any])
        var blocks = try XCTUnwrap(expected["blocks"] as? [[String: Any]])
        var callout = blocks[1]
        var children = try XCTUnwrap(callout["content"] as? [[String: Any]])
        children[0]["id"] = change.titleID
        callout["content"] = children
        blocks[1] = callout
        expected["blocks"] = blocks
        XCTAssertEqual(after, try RelayMarkDocument.decodeJSON(JSONSerialization.data(withJSONObject: expected)))
        XCTAssertEqual(after.blocks.map(\.id), before.blocks.map(\.id))
        XCTAssertEqual(after.blocks[1].childBlocks[1], before.blocks[1].childBlocks[0])
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), after)
        let afterState = try native.encodeUpdate()
        XCTAssertThrowsError(try native.addCalloutTitle(anchor: anchor, expectedID: calloutID,
                                                        expectedSnapshot: checkpoint))
        XCTAssertEqual(try native.encodeUpdate(), afterState)
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)
        try peer.applyUpdate(try XCTUnwrap(native.redo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), after)

        let changed = RelayMarkNativeDocument()
        try changed.applyUpdate(source)
        let changedAnchor = try changed.anchor(path: [1], index: 0)
        _ = try changed.setCalloutAppearance(anchor: changedAnchor, expectedID: calloutID,
                                             expectedTone: "warning", expectedEmphasis: "strong",
                                             tone: "info", emphasis: "strong")
        let changedState = try changed.encodeUpdate()
        XCTAssertThrowsError(try changed.addCalloutTitle(anchor: changedAnchor, expectedID: calloutID,
                                                         expectedSnapshot: checkpoint))
        XCTAssertEqual(try changed.encodeUpdate(), changedState)

        let nested = RelayMarkNativeDocument()
        try nested.applyUpdate(try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["nested_body_update"] as? String))))
        let nestedState = try nested.encodeUpdate()
        XCTAssertThrowsError(try nested.addCalloutTitle(anchor: try nested.anchor(path: [1], index: 0),
                                                        expectedID: calloutID, expectedSnapshot: nested.snapshot()))
        XCTAssertEqual(try nested.encodeUpdate(), nestedState)
    }

    func testBrowserEmptyCalloutTitleAcceptsFirstTextAndKeepsIdentity() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "callout-add-title-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let source = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["empty_title_update"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(source)
        try peer.applyUpdate(source)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(before.blocks[1].childBlocks[0].plainText, "")
        let update = try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [1, 0], start: 0, end: 0, text: "New title")
        try peer.applyUpdate(update)
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(after.blocks[1].childBlocks[0].plainText, "New title")
        XCTAssertEqual(after.blocks[1].childBlocks.map(\.id), before.blocks[1].childBlocks.map(\.id))
        XCTAssertEqual(after.blocks[1].childBlocks[1], before.blocks[1].childBlocks[1])
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), after)
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)
    }

    func testCalloutPlainFirstRunAcceptsTypingButBoldTitleBoundaryStaysFenced() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich-callout-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        try peer.applyUpdate(update)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let delta = try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [1, 1, 0], start: 0, end: 0, text: "Ω ")
        try peer.applyUpdate(delta)
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(after.blocks[1].childBlocks[0], before.blocks[1].childBlocks[0])
        XCTAssertEqual(after.blocks[1].childBlocks[1].plainText, "Ω Shared note")
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), after)
        let checkpoint = try native.encodeUpdate()
        XCTAssertThrowsError(try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [1, 0, 0], start: 0, end: 0, text: "X"))
        XCTAssertEqual(try native.encodeUpdate(), checkpoint)
    }

    func testStableParagraphIDEditsSpannedTableCellWithoutRebuildingGrid() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "table-mixed-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let table = try XCTUnwrap(before.blocks.first { $0.type == "table" })
        let row = try XCTUnwrap(table.childBlocks.first)
        let cell = try XCTUnwrap(row.childBlocks.first)
        let paragraph = try XCTUnwrap(cell.childBlocks.first)
        XCTAssertEqual(paragraph.plainText, "A")

        let delta = try RelayMarkNativeRichTextMutation.replace(
            document: native, blockID: paragraph.id, childIndex: 0,
            start: 0, end: 1, text: "Shared")
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        let updatedTable = try XCTUnwrap(after.blocks.first { $0.id == table.id })
        let updatedCell = try XCTUnwrap(updatedTable.childBlocks.first?.childBlocks.first)
        XCTAssertEqual(updatedCell.props, cell.props)
        XCTAssertEqual(updatedCell.childBlocks.first?.id, paragraph.id)
        XCTAssertEqual(updatedCell.childBlocks.first?.plainText, "Shared")

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(update)
        try reopened.applyUpdate(delta)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: reopened), after)
        let checkpoint = try native.encodeUpdate()
        XCTAssertThrowsError(try RelayMarkNativeRichTextMutation.replace(
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
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), expected)
        let prose = try native.richProseProjection()
        XCTAssertTrue(prose.isEditable)
        XCTAssertTrue(String(prose.text.characters).contains("bold italic strike"))

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(try native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: reopened), expected)

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
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(
            snapshot: JSONSerialization.data(withJSONObject: snapshot)))
    }

    func testBoundedTextMutationRetainsStructureAndSurvivesReplay() throws {
        let (update, expected) = try fixture()
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)

        let delta = try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [0, 0], start: 0, end: 6, text: "After")
        let updated = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(updated.blocks.map(\.id), expected.blocks.map(\.id))
        XCTAssertEqual(updated.blocks.dropFirst(), expected.blocks.dropFirst())
        XCTAssertEqual(updated.blocks[0].plainText, "After 🌍second line")

        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(update)
        try reopened.applyUpdate(delta)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: reopened), updated)

        let checkpoint = try native.encodeUpdate()
        XCTAssertThrowsError(try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [0, 0], start: 0, end: 0, text: "\n"))
        XCTAssertThrowsError(try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [0], start: 0, end: 0, text: "X"))
        XCTAssertThrowsError(try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [0, 0], start: 7, end: 7, text: "X"))
        XCTAssertEqual(try native.encodeUpdate(), checkpoint)
    }

    func testTextMutationPreservesOneMarkedRunAndRejectsCrossMarkReplacement() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "inline-marks-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(update)

        _ = try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [0, 0], start: 8, end: 12, text: "BOLD")
        let projected = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertTrue(projected.blocks[0].plainText.contains("boBOLDtalic strike"))
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        let blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
        let children = try XCTUnwrap(blocks[0]["children"] as? [[String: Any]])
        let runs = try XCTUnwrap(children[0]["delta"] as? [[String: Any]])
        let marked = try XCTUnwrap(runs.first { ($0["insert"] as? String)?.contains("BOLD") == true })
        let attributes = try XCTUnwrap(marked["attributes"] as? [String: Any])
        XCTAssertEqual(Set(attributes.keys), Set(["bold", "italic", "strike"]))

        let checkpoint = try native.encodeUpdate()
        XCTAssertThrowsError(try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [0, 0], start: 5, end: 8, text: "cross"))
        XCTAssertEqual(try native.encodeUpdate(), checkpoint)
    }

    func testCommunityParagraphJoinFixtureConvergesButDoesNotRecoverConcurrentRemovedNodeTyping() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "paragraph-join-v3", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        func bytes(_ key: String) throws -> Data {
            try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture[key] as? String)))
        }
        let left = RelayMarkNativeDocument(), right = RelayMarkNativeDocument()
        try left.applyUpdate(bytes("seed")); try right.applyUpdate(bytes("seed"))
        try left.applyUpdate(bytes("browser_join_update")); try left.applyUpdate(bytes("peer_update"))
        try right.applyUpdate(bytes("peer_update")); try right.applyUpdate(bytes("browser_join_update"))
        XCTAssertTrue(left.integrationStatus().isComplete && right.integrationStatus().isComplete)
        let merged = try RelayMarkNativeDocumentProjection.project(document: left)
        XCTAssertEqual(merged, try RelayMarkNativeDocumentProjection.project(document: right))
        XCTAssertEqual(merged.blocks.count, 1)
        XCTAssertEqual(merged.blocks[0].plainText, "Left Right")
        // Compatibility receipt only. This is explicitly NOT the product's
        // no-loss acceptance gate: the concurrent raw update remains a fixture,
        // but neither the merged view nor the browser's normal Undo places it.
        XCTAssertEqual(fixture["concurrent_right_text_visible"] as? Bool, false)
        try left.applyUpdate(bytes("browser_undo_update")); try right.applyUpdate(bytes("browser_undo_update"))
        let undone = try RelayMarkNativeDocumentProjection.project(document: left)
        XCTAssertEqual(undone, try RelayMarkNativeDocumentProjection.project(document: right))
        XCTAssertEqual(undone.blocks.map(\.plainText), ["Left ", "Right"])
        XCTAssertEqual(fixture["recovered_concurrent_text"] as? Bool, false)
    }

    func testMixedRunPasteKeepsConcurrentPeerTypingAndUndoInOneTransaction() throws {
        let (seed, _) = try fixture()
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed); try peer.applyUpdate(seed)
        let remote = try RelayMarkNativeRichTextMutation.replace(document: peer,
            path: [0, 0], start: 0, end: 0, text: "Peer ", attributes: [:])
        let peerBeforePaste = try RelayMarkNativeDocumentProjection.project(document: peer)
        let pasted = try RelayMarkNativeRichTextMutation.replace(document: native,
            path: [0, 0], start: 1, end: 5, runs: [
                ("bold", ["bold": [String: Any]()]),
                (" 👩🏽‍💻 ", [:]),
                ("italic", ["italic": [String: Any]()])])
        try peer.applyUpdate(pasted); try native.applyUpdate(remote)
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(after, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(after.blocks.map(\.id), peerBeforePaste.blocks.map(\.id))
        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(native.encodeUpdate())
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: reopened), after)
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), peerBeforePaste)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), peerBeforePaste)
        try peer.applyUpdate(try XCTUnwrap(native.redo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), after)
        let checkpoint = try native.encodeUpdate()
        XCTAssertThrowsError(try RelayMarkNativeRichTextMutation.replace(document: native,
            path: [0, 0], start: 0, end: 0, runs: [("good", [:]), ("bad", ["unknown": [:]])]))
        XCTAssertEqual(try native.encodeUpdate(), checkpoint)
    }

    func testExplicitTypingMarksReplaceAcrossRunsAndRejectInvalidMarksBeforeMutation() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "inline-marks-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed); try peer.applyUpdate(seed)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let update = try RelayMarkNativeRichTextMutation.replace(document: native,
            path: [0, 0], start: 5, end: 8, text: "NEW", attributes: ["underline": [String: Any]()])
        try peer.applyUpdate(update)
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(after, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(after.blocks.map(\.id), before.blocks.map(\.id))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        let blocks = try XCTUnwrap(root["children"] as? [[String: Any]])
        let children = try XCTUnwrap(blocks[0]["children"] as? [[String: Any]])
        let runs = try XCTUnwrap(children[0]["delta"] as? [[String: Any]])
        let inserted = try XCTUnwrap(runs.first { $0["insert"] as? String == "NEW" })
        XCTAssertEqual(Set(try XCTUnwrap(inserted["attributes"] as? [String: Any]).keys), ["underline"])
        let checkpoint = try native.encodeUpdate()
        for marks: [String: Any] in [["unknown": [:]], ["code": [:], "bold": [:]], ["highlight": ["color": "red"]]] {
            XCTAssertThrowsError(try RelayMarkNativeRichTextMutation.replace(document: native,
                path: [0, 0], start: 0, end: 0, text: "bad", attributes: marks))
            XCTAssertEqual(try native.encodeUpdate(), checkpoint)
        }
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)
        try peer.applyUpdate(try XCTUnwrap(native.redo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), after)
    }

    func testCrossMarkDeletionPreservesPeerTypingBlockIdentityAndSelectiveUndo() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "inline-marks-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let baseline = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(baseline); try peer.applyUpdate(baseline)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
        let blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
        let children = try XCTUnwrap(blocks[0]["children"] as? [[String: Any]])
        let runs = try XCTUnwrap(children[0]["delta"] as? [[String: Any]])
        let total = runs.compactMap { $0["insert"] as? String }.joined().utf16.count
        let peerUpdate = try RelayMarkNativeRichTextMutation.replace(
            document: peer, path: [0, 0], start: total, end: total, text: " peer")
        let peerBeforeDeletion = try RelayMarkNativeDocumentProjection.project(document: peer)
        let deletion = try RelayMarkNativeRichTextMutation.replace(
            document: native, path: [0, 0], start: 5, end: 8, text: "")
        try native.applyUpdate(peerUpdate); try peer.applyUpdate(deletion)
        let merged = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(merged, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(merged.blocks.map(\.id), before.blocks.map(\.id))
        XCTAssertEqual(merged.blocks[0].plainText,
            (peerBeforeDeletion.blocks[0].plainText as NSString).replacingCharacters(
                in: NSRange(location: 5, length: 3), with: ""))
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), peerBeforeDeletion)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), peerBeforeDeletion)
        try peer.applyUpdate(try XCTUnwrap(native.redo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), merged)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), merged)
    }

    func testCrossMarkDeletionRejectsSplitGraphemeBeforeMutating() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "inline-marks-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String))))
        _ = try native.insertText("👩🏽‍💻", at: 0, path: [0, 0])
        let before = try native.encodeUpdate()
        for range in [1..<2, 2..<4, 0..<6] {
            XCTAssertThrowsError(try RelayMarkNativeRichTextMutation.replace(document: native,
                path: [0, 0], start: range.lowerBound, end: range.upperBound, text: ""))
            XCTAssertEqual(try native.encodeUpdate(), before)
        }
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
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: unknown))

        let duplicate = try changed { blocks in
            var attrs = blocks[1]["attributes"] as! [String: Any]
            attrs["relaymarkId"] = (blocks[0]["attributes"] as! [String: Any])["relaymarkId"]
            blocks[1]["attributes"] = attrs
        }
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: duplicate))

        let marked = try changed { blocks in
            var leaves = blocks[0]["children"] as! [[String: Any]]
            var runs = leaves[0]["delta"] as! [[String: Any]]
            runs[0]["attributes"] = ["textStyle": [:]]
            leaves[0]["delta"] = runs
            blocks[0]["children"] = leaves
        }
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: marked))

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
        XCTAssertThrowsError(try RelayMarkNativeDocumentProjection.project(snapshot: deeper))
    }
}
