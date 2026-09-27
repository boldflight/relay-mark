import Foundation
import XCTest
import RelayMarkCollaboration
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
                         review: String = "ready", confidence: Double? = 0.88) throws -> Data {
        try RelayMarkNativeAgentSuggestionMutation.dismiss(
            document: document, atRootIndex: index, expectedID: id,
            expectedReview: review, expectedKind: "note",
            expectedConfidence: confidence, expectedEvidence: [],
            expectedContent: "Check **this** source.")
    }

    private func accept(_ document: RelayMarkNativeDocument,
                        index: Int = 1, content: String = "Check **this** source.",
                        newID: String = "b00000000000040008000000000000084") throws -> Data {
        try RelayMarkNativeAgentSuggestionMutation.accept(
            document: document, atRootIndex: index, expectedID: id,
            expectedReview: "ready", expectedKind: "note", expectedConfidence: 0.88,
            expectedEvidence: [], expectedContent: content, newBlockID: newID)
    }

    func testAcceptBrowserAuthoredBoldParagraphReplaysAndUndoesAsOneChange() throws {
        // The source and initial Yjs update are produced by the browser v3 fixture.
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
        try peer.applyUpdate(update)
        try browser.applyUpdate(update)
        XCTAssertEqual(try native.snapshot(), try peer.snapshot())
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native))
        let ast = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
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
        XCTAssertEqual(String(try native.markdownV3ProseProjection().text.characters),
                       "Before\nCheck this source.\nAfter")
        let restored = try XCTUnwrap(native.undo())
        try peer.applyUpdate(restored)
        try browser.applyUpdate(restored)
        XCTAssertEqual(try native.snapshot(), before)
        XCTAssertEqual(try peer.snapshot(), before)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native))
    }

    func testAcceptOneHeadingKeepsBrowserV3HeadingShapeAndRestoresSuggestionOnUndo() throws {
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        let baseline = try fixture()
        for replica in [native, peer] { try replica.applyUpdate(baseline) }
        try browser.applyUpdate(baseline)
        let content = "## Shared **heading**"
        let changed = try native.mutatePaperControl(at: 1, change: .update(
            tag: "agentSuggestion", expectedID: id, attributes: ["content": content]))
        try peer.applyUpdate(changed)
        try browser.applyUpdate(changed)
        let before = try native.snapshot()
        XCTAssertTrue(RelayMarkNativeAgentSuggestionMutation.canAccept(content))
        let accepted = try accept(native, content: content)
        try peer.applyUpdate(accepted)
        try browser.applyUpdate(accepted)
        XCTAssertEqual(try native.snapshot(), try peer.snapshot())
        let ast = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        XCTAssertEqual(ast.blocks.map(\.type), ["paragraph", "heading", "paragraph"])
        XCTAssertEqual(ast.blocks[1].id, "b00000000000040008000000000000084")
        XCTAssertEqual(ast.blocks[1].props["level"], .number(2))
        let anchor: String?
        if case let .string(value) = ast.blocks[1].props["headingId"] { anchor = value }
        else { anchor = nil }
        XCTAssertNotNil(anchor?.range(of: #"^h-[0-9a-f]{8}-[0-9a-f-]{27}$"#,
                                      options: .regularExpression))
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()), ast)
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
        let nullable = try RelayMarkNativeMarkdownV3SingleBlock.parse(content)
        XCTAssertTrue(nullable.attributes(id: "b00000000000040008000000000000084",
                                          headingID: nil)["headingId"] is NSNull)
        let restored = try XCTUnwrap(native.undo())
        try peer.applyUpdate(restored)
        try browser.applyUpdate(restored)
        XCTAssertEqual(try native.snapshot(), before)
        XCTAssertEqual(try peer.snapshot(), before)
        XCTAssertEqual(try native.markdownV3ProseProjection().suggestionAtoms.first?.content, content)
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
             "let earth = \"🌍\"\nprint(earth)"),
            ("```\nplain code\n```", "code", "codeBlock", 5, "plain code"),
            ("---", "horizontal_rule", "horizontalRule", 6, "")
        ]
        for scenario in cases {
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            let browser = try RelayMarkCollaborationDocument()
            let baseline = try fixture()
            for replica in [native, peer] { try replica.applyUpdate(baseline) }
            try browser.applyUpdate(baseline)
            let changed = try native.mutatePaperControl(at: 1, change: .update(
                tag: "agentSuggestion", expectedID: id, attributes: ["content": scenario.source]))
            try peer.applyUpdate(changed)
            try browser.applyUpdate(changed)
            let before = try native.snapshot()
            XCTAssertTrue(RelayMarkNativeAgentSuggestionMutation.canAccept(scenario.source))
            let update = try accept(native, content: scenario.source)
            try peer.applyUpdate(update)
            try browser.applyUpdate(update)
            XCTAssertEqual(try native.snapshot(), try peer.snapshot())
            let ast = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
            XCTAssertEqual(ast.blocks[1].type, scenario.type)
            XCTAssertEqual(ast.blocks[1].plainText, scenario.expectedText)
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()), ast)
            let current = try XCTUnwrap(JSONSerialization.jsonObject(
                with: native.snapshot()) as? [String: Any])
            let nodes = try XCTUnwrap(current["children"] as? [[String: Any]])
            let node = nodes[1], browserNode = reference[scenario.referenceIndex]
            XCTAssertEqual(node["name"] as? String, scenario.xmlName)
            XCTAssertEqual(node["name"] as? String, browserNode["name"] as? String)
            XCTAssertEqual(Set((node["attributes"] as? [String: Any] ?? [:]).keys),
                           Set((browserNode["attributes"] as? [String: Any] ?? [:]).keys))
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

    func testAcceptRejectsUnsupportedOrStaleContentAndDuplicateIDWithoutMutation() throws {
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(fixture())
        let before = try native.encodeUpdate()
        XCTAssertTrue(RelayMarkNativeAgentSuggestionMutation.canAccept(
            "Read *carefully*, **please**, then use `code` and [source](https://example.com)."))
        for source in ["First\n\nSecond", "![image](https://example.com/a.png)",
                       "<b>HTML</b>", "- list", "[unsafe](javascript:alert(1))",
                       "# Heading {#manual-anchor}", "> First\n>\n> Second",
                       "```swift extra\nprint(1)\n```", "```\n```"] {
            XCTAssertFalse(RelayMarkNativeAgentSuggestionMutation.canAccept(source), source)
        }
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
        try peer.applyUpdate(removed)
        try browser.applyUpdate(removed)
        XCTAssertEqual(try native.snapshot(), try peer.snapshot())
        XCTAssertEqual(try native.markdownV3ProseProjection().suggestionAtoms, [])
        XCTAssertEqual(String(try native.markdownV3ProseProjection().text.characters), "Before\nAfter")
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native))

        let restored = try XCTUnwrap(native.undo())
        try peer.applyUpdate(restored)
        try browser.applyUpdate(restored)
        XCTAssertEqual(try native.snapshot(), before)
        XCTAssertEqual(try peer.snapshot(), before)
        XCTAssertEqual(try native.markdownV3ProseProjection().suggestionAtoms.first?.id, id)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: browser.snapshot()),
                       try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native))
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
