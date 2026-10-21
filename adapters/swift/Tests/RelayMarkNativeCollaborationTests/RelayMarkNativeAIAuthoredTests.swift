import Foundation
import XCTest
import RelayMarkSwift
import RelayMarkProseProjection
@testable import RelayMarkNativeCollaboration

/// Agent-written text carries ai_authored{run_id} (plan M5c). Native text shows
/// it and keeps it through peers, Return and undo; text a person types or
/// pastes inside it is theirs.
@MainActor
final class RelayMarkNativeAIAuthoredTests: XCTestCase {
    private let run = "4f1c2b7a-5d6e-4f80-9a1b-2c3d4e5f6a7b"

    private func fixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("spec/relaymark/collaboration/fixtures/ai-authored-mark.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// "Mine, then " + bold "generated" + " notes"; the last two are the agent's.
    private func seeded() throws -> RelayMarkNativeDocument {
        let document = RelayMarkNativeDocument()
        try document.initializeDocument(authoredAST: JSONSerialization.data(withJSONObject: try XCTUnwrap(fixture()["ast"])))
        return document
    }

    /// The contiguous runs of agent text, as a reader sees them grey.
    private func grey(_ document: RelayMarkNativeDocument) throws -> [String] {
        let text = try document.richProseProjection().text
        var result: [String] = [], previous = false
        for item in text.runs {
            let id = item[RelayMarkAIAuthoredAttribute.self]
            if let id {
                XCTAssertEqual(id, run)
                let words = String(text[item.range].characters)
                if previous { result[result.count - 1] += words } else { result.append(words) }
            }
            previous = id != nil
        }
        return result
    }

    func testTheSharedFixtureProjectsShowsAndReachesPeers() throws {
        let native = try seeded()
        let expected = try RelayMarkDocument.decodeJSON(JSONSerialization.data(withJSONObject: try XCTUnwrap(fixture()["ast"])))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), expected)
        XCTAssertEqual(try RelayMarkDocument.decodeJSON(native.authoredDocument()), expected)
        XCTAssertEqual(try grey(native), ["generated notes"])

        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(native.encodeUpdate())
        XCTAssertEqual(try grey(peer), ["generated notes"])
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), expected)
    }

    /// A generation built on the device is the agent's: all its text but code
    /// is grey, and the marked document is the one the paper holds.
    func testMarkingAGeneratedDocumentMarksAllItsTextButCode() throws {
        let source = "## Decisions\n\n- Ship **Friday** with [notes](https://example.com/n)\n- Run `make`\n\n```\nlet x = 1\n```\n\nDone."
        let marked = try RelayMarkAgentAuthorship.markDocument(
            RelayMarkSourceCodec.parseDocument(source, namespace: "device-draft"), runID: run)
        let native = RelayMarkNativeDocument()
        try native.initializeDocument(authoredAST: marked)
        XCTAssertEqual(try RelayMarkDocument.decodeJSON(native.authoredDocument()), try RelayMarkDocument.decodeJSON(marked))
        let text = try native.richProseProjection().text
        let plain = text.runs.filter { $0[RelayMarkAIAuthoredAttribute.self] == nil }
            .map { String(text[$0.range].characters) }.joined()
        XCTAssertEqual(plain.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }, ["make", "let", "x", "=", "1"])
        XCTAssertThrowsError(try RelayMarkAgentAuthorship.markDocument(marked, runID: String(repeating: "r", count: 65)))
    }

    func testTypedAndPastedTextInsideAgentTextIsUnmarked() throws {
        let native = try seeded()
        // Typing inherits the surrounding bold, but not the agent's mark.
        _ = try RelayMarkNativeRichEditing.replace(document: native, range: NSRange(location: 15, length: 0),
            runs: [("X", [:])], inheritMarks: true, expectedSnapshot: native.snapshot())
        XCTAssertEqual(String(try native.richProseProjection().text.characters), "Mine, then geneXrated notes")
        XCTAssertEqual(try grey(native), ["gene", "rated notes"])

        // Plain paste carrying the mark, as copied agent text would.
        _ = try RelayMarkNativeRichEditing.replace(document: native, range: NSRange(location: 23, length: 0),
            runs: [("Y", ["ai_authored": ["run_id": run]])], expectedSnapshot: native.snapshot())
        XCTAssertEqual(try grey(native), ["gene", "rated n", "otes"])

        // Rich paste of a slice with the mark.
        let slice = try JSONSerialization.data(withJSONObject: [
            "slice": ["content": [["type": "paragraph", "content": [["type": "text", "text": "Z",
                "marks": [["type": "ai_authored", "attrs": ["run_id": run]]]]]]],
                      "openStart": 1, "openEnd": 1],
            "normalizations": [[String: Any]]()])
        _ = try RelayMarkNativeRichEditing.insertDocumentSlice(document: native, range: NSRange(location: 25, length: 0),
            clipboardSlice: slice, expectedSnapshot: native.snapshot())
        XCTAssertEqual(String(try native.richProseProjection().text.characters), "Mine, then geneXrated nYoZtes")
        XCTAssertEqual(try grey(native), ["gene", "rated n", "o", "tes"])
    }

    func testLeafTypingInsideAgentTextIsUnmarked() throws {
        let native = try seeded()
        // "generated" is the second run of the paragraph's one text leaf.
        let typed = try native.typeText("X", replacing: 0, at: 15, path: [0, 0])
        XCTAssertNil(typed.attributes["ai_authored"])
        XCTAssertEqual(try grey(native), ["gene", "rated notes"])
        let styled = try native.typeText("Y", replacing: 0, at: 23, path: [0, 0],
                                         attributes: ["ai_authored": ["run_id": run]])
        XCTAssertNil(styled.attributes["ai_authored"])
        XCTAssertEqual(try grey(native), ["gene", "rated n", "otes"])
        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(native.encodeUpdate())
        XCTAssertEqual(try grey(peer), ["gene", "rated n", "otes"])
    }

    func testReturnAndUndoKeepAgentText() throws {
        let native = try seeded()
        _ = try RelayMarkNativeRichReturn.apply(document: native, blockPath: [0], utf16Offset: 15,
                                                expectedSnapshot: native.snapshot())
        XCTAssertEqual(String(try native.richProseProjection().text.characters), "Mine, then gene\nrated notes")
        XCTAssertEqual(try grey(native), ["gene", "rated notes"])

        let typed = try seeded()
        _ = try RelayMarkNativeRichEditing.replace(document: typed, range: NSRange(location: 15, length: 0),
            runs: [("X", [:])], inheritMarks: true, expectedSnapshot: typed.snapshot())
        XCTAssertNotNil(try typed.undo())
        XCTAssertEqual(String(try typed.richProseProjection().text.characters), "Mine, then generated notes")
        XCTAssertEqual(try grey(typed), ["generated notes"])
    }
}
