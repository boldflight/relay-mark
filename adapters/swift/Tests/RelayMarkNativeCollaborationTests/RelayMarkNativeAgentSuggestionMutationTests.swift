import Foundation
import XCTest
import RelayMarkCollaboration
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeAgentSuggestionMutationTests: XCTestCase {
    private let id = "b00000000000040008000000000000082"

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "agent-suggestion-v3-draft", withExtension: "json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(object["update"] as? String)))
    }

    private func dismiss(_ document: RelayMarkNativeDocument, index: Int = 1,
                         review: String = "ready", confidence: Double? = 0.88) throws -> RelayMarkNativeRichEditing.Change {
        try RelayMarkNativeAgentSuggestionMutation.dismiss(
            document: document, atRootIndex: index, expectedID: id,
            expectedReview: review, expectedKind: "note",
            expectedConfidence: confidence, expectedEvidence: [],
            expectedContent: "Check **this** source.")
    }

    private func accept(_ document: RelayMarkNativeDocument,
                        index: Int = 1, content: String = "Check **this** source.",
                        newID: String = "b00000000000040008000000000000084") throws -> RelayMarkNativeRichEditing.Change {
        try RelayMarkNativeAgentSuggestionMutation.accept(
            document: document, atRootIndex: index, expectedID: id,
            expectedReview: "ready", expectedKind: "note", expectedConfidence: 0.88,
            expectedEvidence: [], expectedContent: content, newBlockID: newID)
    }

    func testAcceptBrowserAuthoredBoldParagraphReplaysAndUndoesAsOneChange() throws {
        // The source and initial Yjs update are produced by the browser canonical fixture.
        // The browser Accept test replaces its atom with parsed Markdown, whose
        // first paragraph carries three text runs and a strong mark on "this".
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        let baseline = try fixture()
        for replica in [native, peer] { try replica.applyUpdate(baseline) }
        try browser.applyUpdate(baseline)
        let before = try native.snapshot()
        XCTAssertTrue(RelayMarkNativeAgentSuggestionMutation.canAccept("Check **this** source."))
        let update = try accept(native)
        try peer.applyUpdate(update.update)
        try browser.applyUpdate(update.update)
        XCTAssertEqual(try native.snapshot(), try peer.snapshot())
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeDocumentProjection.project(document: native))
        let ast = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(ast.blocks.map(\.id), ["b00000000000040008000000000000081",
                                              "b00000000000040008000000000000084",
                                              "b00000000000040008000000000000083"])
        XCTAssertEqual(ast.blocks[1].type, "paragraph")
        XCTAssertEqual(ast.blocks[1].content.compactMap {
            if case let .inline(value) = $0 { return value.type }
            return nil
        }, ["text", "strong", "text"])
        if case let .inline(strong) = ast.blocks[1].content[1] {
            XCTAssertEqual(strong.content.map(\.text), ["this"])
        } else { XCTFail("missing strong run") }
        XCTAssertEqual(String(try native.richProseProjection().text.characters),
                       "Before\nCheck this source.\nAfter")
        let restored = try XCTUnwrap(native.undo())
        try peer.applyUpdate(restored)
        try browser.applyUpdate(restored)
        XCTAssertEqual(try native.snapshot(), before)
        XCTAssertEqual(try peer.snapshot(), before)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeDocumentProjection.project(document: native))
    }

    func testAcceptOneHeadingKeepsBrowserHeadingShapeAndRestoresSuggestionOnUndo() throws {
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        let baseline = try fixture()
        for replica in [native, peer] { try replica.applyUpdate(baseline) }
        try browser.applyUpdate(baseline)
        let content = "## Shared **heading**"
        let changed = try RelayMarkNativeRichEditing.updateWidget(document: native, tree: JSONSerialization.jsonObject(with: native.snapshot()) as! [String: Any], id: id, attributes: ["content": content])
        try peer.applyUpdate(changed.update)
        try browser.applyUpdate(changed.update)
        let before = try native.snapshot()
        XCTAssertTrue(RelayMarkNativeAgentSuggestionMutation.canAccept(content))
        let accepted = try accept(native, content: content)
        try peer.applyUpdate(accepted.update)
        try browser.applyUpdate(accepted.update)
        XCTAssertEqual(try native.snapshot(), try peer.snapshot())
        let ast = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(ast.blocks.map(\.type), ["paragraph", "heading", "paragraph"])
        XCTAssertEqual(ast.blocks[1].id, "b00000000000040008000000000000084")
        XCTAssertEqual(ast.blocks[1].props["level"], .number(2))
        let anchor: String?
        if case let .string(value) = ast.blocks[1].props["headingId"] { anchor = value }
        else { anchor = nil }
        XCTAssertNotNil(anchor?.range(of: "^h-[0-9a-f]{8}-[0-9a-f-]{27}$", options: .regularExpression))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()), ast)
        let browserHeadingURL = try XCTUnwrap(Bundle.module.url(
            forResource: "markdown-blocks-v3-draft", withExtension: "json"))
        let browserHeadingFixture = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: browserHeadingURL)) as? [String: Any])
        let browserHeadingUpdate = try XCTUnwrap(Data(base64Encoded:
            try XCTUnwrap(browserHeadingFixture["update"] as? String)))
        let browserHeadingDocument = RelayMarkNativeDocument()
        try browserHeadingDocument.applyUpdate(browserHeadingUpdate)
        func headingAttributes(_ document: RelayMarkNativeDocument) throws -> [String: Any] {
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
            let children = try XCTUnwrap(root["children"] as? [[String: Any]])
            return try XCTUnwrap(children[1]["attributes"] as? [String: Any])
        }
        let browserAttributes = try headingAttributes(browserHeadingDocument)
        let acceptedAttributes = try headingAttributes(native)
        XCTAssertEqual(Set(acceptedAttributes.keys), Set(browserAttributes.keys))
        XCTAssertEqual(acceptedAttributes["level"] as? Int, browserAttributes["level"] as? Int)
        XCTAssertTrue(acceptedAttributes["headingId"] is String)
        let restored = try XCTUnwrap(native.undo())
        try peer.applyUpdate(restored)
        try browser.applyUpdate(restored)
        XCTAssertEqual(try native.snapshot(), before)
        XCTAssertEqual(try peer.snapshot(), before)
        XCTAssertEqual(try native.richProseProjection().suggestionAtoms.first?.content, content)
    }

    func testAcceptSingleQuoteCodeAndRuleMatchBrowserBlockShapesAndUndo() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "markdown-blocks-v3-draft",
                                                   withExtension: "json"))
        let fixtureObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: url)) as? [String: Any])
        let fixtureUpdate = try XCTUnwrap(Data(base64Encoded:
            try XCTUnwrap(fixtureObject["update"] as? String)))
        let browserBlocks = RelayMarkNativeDocument()
        try browserBlocks.applyUpdate(fixtureUpdate)
        let browserRoot = try XCTUnwrap(JSONSerialization.jsonObject(
            with: browserBlocks.snapshot()) as? [String: Any])
        let reference = try XCTUnwrap(browserRoot["children"] as? [[String: Any]])
        let cases: [(source: String, type: String, xmlName: String, referenceIndex: Int,
                     expectedText: String)] = [
            ("> Quoted **text**", "quote", "blockquote", 2, "Quoted text"),
            ("```swift\nlet earth = \"🌍\"\nprint(earth)\n```", "code", "codeBlock", 5,
             "let earth = \"🌍\"\nprint(earth)\n"),
            ("```\nplain code\n```", "code", "codeBlock", 5, "plain code\n"),
            ("---", "horizontal_rule", "horizontalRule", 6, "")
        ]
        for scenario in cases {
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            let browser = try RelayMarkCollaborationDocument()
            let baseline = try fixture()
            for replica in [native, peer] { try replica.applyUpdate(baseline) }
            try browser.applyUpdate(baseline)
            let changed = try RelayMarkNativeRichEditing.updateWidget(document: native, tree: JSONSerialization.jsonObject(with: native.snapshot()) as! [String: Any], id: id, attributes: ["content": scenario.source])
            try peer.applyUpdate(changed.update)
            try browser.applyUpdate(changed.update)
            let before = try native.snapshot()
            XCTAssertTrue(RelayMarkNativeAgentSuggestionMutation.canAccept(scenario.source))
            let update = try accept(native, content: scenario.source)
            try peer.applyUpdate(update.update)
            try browser.applyUpdate(update.update)
            XCTAssertEqual(try native.snapshot(), try peer.snapshot())
            let ast = try RelayMarkNativeDocumentProjection.project(document: native)
            XCTAssertEqual(ast.blocks[1].type, scenario.type)
            XCTAssertEqual(ast.blocks[1].plainText, scenario.expectedText)
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()), ast)
            let current = try XCTUnwrap(JSONSerialization.jsonObject(
                with: native.snapshot()) as? [String: Any])
            let nodes = try XCTUnwrap(current["children"] as? [[String: Any]])
            let node = nodes[1], browserNode = reference[scenario.referenceIndex]
            XCTAssertEqual(node["name"] as? String, scenario.xmlName)
            XCTAssertEqual(node["name"] as? String, browserNode["name"] as? String)
            XCTAssertEqual(Set((node["attributes"] as? [String: Any] ?? [:]).filter { !($0.value is NSNull) && $0.key != "language" }.keys),
                           Set((browserNode["attributes"] as? [String: Any] ?? [:]).filter { !($0.value is NSNull) && $0.key != "language" }.keys))
            if scenario.type == "code" {
                XCTAssertEqual((node["attributes"] as? [String: Any])?["language"] as? String, scenario.source.hasPrefix("```swift") ? "swift" : nil)
            }
            if scenario.type == "quote" {
                let child = try XCTUnwrap((node["children"] as? [[String: Any]])?.first)
                XCTAssertEqual(child["name"] as? String, "paragraph")
                XCTAssertNotNil((child["attributes"] as? [String: Any])?["relaymarkId"])
            } else if scenario.type == "horizontal_rule" {
                XCTAssertEqual((node["children"] as? [Any])?.count, 0)
            }
            let restored = try XCTUnwrap(native.undo())
            try peer.applyUpdate(restored)
            try browser.applyUpdate(restored)
            XCTAssertEqual(try native.snapshot(), before)
            XCTAssertEqual(try peer.snapshot(), before)
        }
    }

    func testAcceptFlatBulletAndOrderedListsMatchBrowserShapeReplayAndUndo() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "markdown-blocks-v3-draft",
                                                   withExtension: "json"))
        let fixtureObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: url)) as? [String: Any])
        let fixtureUpdate = try XCTUnwrap(Data(base64Encoded:
            try XCTUnwrap(fixtureObject["update"] as? String)))
        let browserBlocks = RelayMarkNativeDocument()
        try browserBlocks.applyUpdate(fixtureUpdate)
        let browserRoot = try XCTUnwrap(JSONSerialization.jsonObject(
            with: browserBlocks.snapshot()) as? [String: Any])
        let reference = try XCTUnwrap(browserRoot["children"] as? [[String: Any]])
        let cases: [(source: String, name: String, fixtureIndex: Int, start: Int?)] = [
            ("- First\n- **Second**", "bulletList", 3, nil),
            ("7. First\n8. Second", "orderedList", 4, 7),
            ("1. One", "orderedList", 4, 1)
        ]
        for scenario in cases {
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            let browser = try RelayMarkCollaborationDocument()
            let baseline = try fixture()
            for replica in [native, peer] { try replica.applyUpdate(baseline) }
            try browser.applyUpdate(baseline)
            let changed = try RelayMarkNativeRichEditing.updateWidget(document: native, tree: JSONSerialization.jsonObject(with: native.snapshot()) as! [String: Any], id: id, attributes: ["content": scenario.source])
            try peer.applyUpdate(changed.update)
            try browser.applyUpdate(changed.update)
            let before = try native.snapshot()
            XCTAssertTrue(RelayMarkNativeAgentSuggestionMutation.canAccept(scenario.source))
            let update = try accept(native, content: scenario.source)
            try peer.applyUpdate(update.update)
            try browser.applyUpdate(update.update)
            XCTAssertEqual(try native.snapshot(), try peer.snapshot())
            let ast = try RelayMarkNativeDocumentProjection.project(document: native)
            XCTAssertEqual(ast.blocks[1].type, "list")
            XCTAssertEqual(ast.blocks[1].props["kind"], .string(scenario.start == nil ? "bullet" : "ordered"))
            if let start = scenario.start { XCTAssertEqual(ast.blocks[1].props["start"], .number(Double(start))) }
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()), ast)
            let current = try XCTUnwrap(JSONSerialization.jsonObject(
                with: native.snapshot()) as? [String: Any])
            let nodes = try XCTUnwrap(current["children"] as? [[String: Any]])
            let list = nodes[1], browserList = reference[scenario.fixtureIndex]
            XCTAssertEqual(list["name"] as? String, scenario.name)
            XCTAssertEqual(Set((list["attributes"] as? [String: Any] ?? [:]).keys),
                           Set((browserList["attributes"] as? [String: Any] ?? [:]).keys))
            let items = try XCTUnwrap(list["children"] as? [[String: Any]])
            XCTAssertEqual(items.count, scenario.source.contains("Second") ? 2 : 1)
            for item in items {
                XCTAssertEqual(item["name"] as? String, "listItem")
                let paragraphs = try XCTUnwrap(item["children"] as? [[String: Any]])
                XCTAssertEqual(paragraphs.count, 1)
                XCTAssertEqual(paragraphs[0]["name"] as? String, "paragraph")
                XCTAssertNotNil((item["attributes"] as? [String: Any])?["relaymarkId"])
                XCTAssertNotNil((paragraphs[0]["attributes"] as? [String: Any])?["relaymarkId"])
            }
            let acceptedCheckpoint = try native.encodeUpdate()
            XCTAssertThrowsError(try accept(native, content: scenario.source))
            XCTAssertEqual(try native.encodeUpdate(), acceptedCheckpoint)
            let restored = try XCTUnwrap(native.undo())
            try peer.applyUpdate(restored)
            try browser.applyUpdate(restored)
            XCTAssertEqual(try native.snapshot(), before)
            XCTAssertEqual(try peer.snapshot(), before)
        }
    }

    func testAcceptedRichFragmentUsesTheFullCanonicalGrammar() throws {
        let content = """
        @Callout(tone: "warning") {
        Read **carefully**
        }

        | Name | Count |
        | --- | --- |
        | Alpha | 2 |

        ![Diagram](https://example.com/diagram.png)
        """
        XCTAssertTrue(RelayMarkNativeAgentSuggestionMutation.canAccept(content),
            "Rich suggestions must not disappear behind the reduced single-block converter")
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(fixture())
        _ = try RelayMarkNativeRichEditing.updateWidget(document: native,
            tree: JSONSerialization.jsonObject(with: native.snapshot()) as! [String: Any], id: id,
            attributes: ["content": content])
        let before = try native.snapshot()
        try peer.applyUpdate(native.encodeUpdate())
        let accepted = try accept(native, content: content)
        let steps = try XCTUnwrap(JSONSerialization.jsonObject(with: accepted.steps) as? [[String: Any]])
        XCTAssertEqual(steps.first?["stepType"] as? String, "replace")
        try peer.applyUpdate(accepted.update)
        let ast = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(ast.blocks.map(\.type), ["paragraph", "relay.callout", "table", "image", "paragraph"])
        XCTAssertEqual(ast.blocks[1].id, "b00000000000040008000000000000084")
        XCTAssertEqual(try peer.authoredDocument(), try native.authoredDocument())
        let undo = try XCTUnwrap(native.undo()); try peer.applyUpdate(undo)
        XCTAssertEqual(try native.snapshot(), before)
        XCTAssertEqual(try peer.snapshot(), before)
    }

    func testAcceptRejectsUnsupportedOrStaleContentAndDuplicateIDWithoutMutation() throws {
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(fixture())
        let before = try native.encodeUpdate()
        XCTAssertTrue(RelayMarkNativeAgentSuggestionMutation.canAccept(
            "Read *carefully*, **please**, then use `code` and [source](https://example.com)."))
        for source in ["First\n\nSecond", "![image](https://example.com/a.png)",
                       "<b>HTML</b>", "- [x] task", "- Parent\n  - Nested"] {
            XCTAssertTrue(RelayMarkNativeAgentSuggestionMutation.canAccept(source), source)
        }
        XCTAssertTrue(RelayMarkNativeAgentSuggestionMutation.canAccept("[unsafe](javascript:alert(1))")) // Shared importer preserves this as literal text.
        var metadataAST = try XCTUnwrap(JSONSerialization.jsonObject(with:
            RelayMarkSourceCodec.parseDocument("Body", namespace: "proposal-envelope")) as? [String: Any])
        metadataAST["meta"] = ["review": "needed"]
        let metadata = try RelayMarkSourceCodec.serializeDocument(JSONSerialization.data(withJSONObject: metadataAST))
        XCTAssertFalse(RelayMarkNativeAgentSuggestionMutation.canAccept(metadata))
        XCTAssertThrowsError(try accept(native, content: "Changed"))
        XCTAssertThrowsError(try accept(native, index: 0))
        XCTAssertThrowsError(try accept(native, newID: "b00000000000040008000000000000000083"))
        XCTAssertEqual(try native.encodeUpdate(), before)
    }

    func testDismissReplaysAndOneUndoRestoresSuggestionBetweenAdjacentProse() throws {
        let update = try fixture()
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        try native.applyUpdate(update)
        try peer.applyUpdate(update)
        try browser.applyUpdate(update)

        let before = try native.snapshot()
        let removed = try dismiss(native)
        try peer.applyUpdate(removed.update)
        try browser.applyUpdate(removed.update)
        XCTAssertEqual(try native.snapshot(), try peer.snapshot())
        XCTAssertEqual(try native.richProseProjection().suggestionAtoms, [])
        XCTAssertEqual(String(try native.richProseProjection().text.characters), "Before\nAfter")
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeDocumentProjection.project(document: native))

        let restored = try XCTUnwrap(native.undo())
        try peer.applyUpdate(restored)
        try browser.applyUpdate(restored)
        XCTAssertEqual(try native.snapshot(), before)
        XCTAssertEqual(try peer.snapshot(), before)
        XCTAssertEqual(try native.richProseProjection().suggestionAtoms.first?.id, id)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeDocumentProjection.project(document: native))
    }

    func testStaleSelectionAndChangedAuthoredStateDoNotMutate() throws {
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(fixture())
        let before = try native.encodeUpdate()
        XCTAssertThrowsError(try dismiss(native, index: 0))
        XCTAssertThrowsError(try dismiss(native, review: "draft"))
        XCTAssertThrowsError(try dismiss(native, confidence: nil))
        XCTAssertEqual(try native.encodeUpdate(), before)

        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(before)
        _ = try dismiss(peer)
        try native.applyUpdate(peer.encodeUpdate())
        let afterPeer = try native.encodeUpdate()
        XCTAssertThrowsError(try dismiss(native))
        XCTAssertEqual(try native.encodeUpdate(), afterPeer)
    }
}
