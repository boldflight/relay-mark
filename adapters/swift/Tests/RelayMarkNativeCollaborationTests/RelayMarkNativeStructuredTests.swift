import Foundation
import XCTest
import RelayMarkCollaboration
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeStructuredTests: XCTestCase {
    private func pair(_ name: String) throws -> (RelayMarkNativeDocument, RelayMarkCollaborationDocument) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "structured-v1", withExtension: "json"))
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(value["cases"] as? [[String: Any]])
        let item = try XCTUnwrap(cases.first { $0["name"] as? String == name })
        let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(item["update"] as? String)))
        let native = RelayMarkNativeDocument(), browser = try RelayMarkCollaborationDocument()
        try native.applyUpdate(bytes); try browser.applyUpdate(bytes)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       item["snapshot"] as? NSDictionary)
        return (native, browser)
    }

    private func equal(_ native: RelayMarkNativeDocument, _ browser: RelayMarkCollaborationDocument) throws {
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary)
    }

    private func structure(_ document: RelayMarkNativeDocument) throws -> Data {
        func strip(_ node: [String: Any]) -> [String: Any] {
            var copy = node; copy.removeValue(forKey: "delta")
            if let children = node["children"] as? [[String: Any]] { copy["children"] = children.map(strip) }
            return copy
        }
        let tree = try XCTUnwrap(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
        return try JSONSerialization.data(withJSONObject: strip(tree), options: [.sortedKeys])
    }

    func testHeadingAndNestedListFormattingPreservesStructureAnchorsAndIMEStyle() throws {
        for name in ["headings", "bullet-ordered", "ordered-bullet"] {
            let (native, browser) = try pair(name)
            XCTAssertTrue(native.supportsInlineFormatting())
            let projection = try native.proseProjection()
            let index = name == "headings" ? 0 : 1
            let range = projection.blockRanges[index], paragraphPath = projection.blockPaths[index]
            let leafPath = paragraphPath + [0]
            let anchor = try native.anchor(path: leafPath, index: 4)
            let structuralBefore = try structure(native)
            try browser.applyUpdate(native.formatProse(start: range.location, end: NSMaxRange(range), attributes: ["strike": [:]]))
            try browser.applyUpdate(native.formatProse(start: range.location, end: NSMaxRange(range), attributes: ["code": [:], "strike": NSNull()]))
            let beforeReplacement = try native.snapshot()
            let replacement: Data
            if name == "headings" {
                replacement = try native.replaceBasicMarkdownProse(start: range.location + 1, end: range.location + 2, text: "あ")
            } else {
                replacement = try native.replaceListParagraphText(anchor: native.anchor(path: paragraphPath, index: 0), start: 1, end: 2, text: "あ")
            }
            try browser.applyUpdate(replacement)
            let marked = try native.proseProjection().text
            let plain = String(marked.characters)
            let selected = try XCTUnwrap(Range(range, in: plain))
            let lower = try XCTUnwrap(AttributedString.Index(selected.lowerBound, within: marked))
            let upper = try XCTUnwrap(AttributedString.Index(selected.upperBound, within: marked))
            XCTAssertTrue(marked[lower..<upper].runs.allSatisfy { $0.inlinePresentationIntent == .code })
            XCTAssertEqual(try native.resolve(anchor: anchor)?.path, leafPath)
            XCTAssertEqual(try native.resolve(anchor: anchor)?.index, 4)
            XCTAssertEqual(try structure(native), structuralBefore)
            try equal(native, browser)
            try browser.applyUpdate(XCTUnwrap(native.undo()))
            XCTAssertEqual(try native.snapshot(), beforeReplacement)
            try browser.applyUpdate(XCTUnwrap(native.redo()))
            try equal(native, browser)
            let bytes = try native.encodeUpdate()
            XCTAssertThrowsError(try native.formatProse(start: range.location, end: NSMaxRange(range), attributes: ["unknown": [:]]))
            XCTAssertEqual(try native.encodeUpdate(), bytes)
        }
    }

    func testAllHeadingLevelsPreserveIdentityAndUndo() throws {
        for level in 1...6 {
            let (native, browser) = try pair("headings")
            let index = level % 6 // Start from a different level so undo is observable.
            let anchor = try native.anchor(path: [index], index: 0)
            let textAnchor = try native.anchor(path: [index, 0], index: 2)
            let before = try native.snapshot()
            let update = try native.setHeadingLevel(anchor: anchor, expectedHeadingID: "stable-\(index + 1)", level: level)
            try browser.applyUpdate(update)
            try equal(native, browser)
            let tree = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
            let headings = try XCTUnwrap(tree["children"] as? [[String: Any]])
            let attrs = try XCTUnwrap(headings[index]["attributes"] as? [String: Any])
            XCTAssertEqual(attrs["level"] as? Int, level)
            XCTAssertEqual(attrs["headingId"] as? String, "stable-\(index + 1)")
            XCTAssertEqual(try native.resolve(anchor: textAnchor)?.path, [index, 0])
            try browser.applyUpdate(XCTUnwrap(native.undo()))
            XCTAssertEqual(try native.snapshot(), before)
            try equal(native, browser)
            try browser.applyUpdate(XCTUnwrap(native.redo()))
            try equal(native, browser)
        }
    }

    func testHeadingInvalidLevelIdentityShapeAndForeignAnchorAreNonmutating() throws {
        let (native, _) = try pair("headings")
        let anchor = try native.anchor(path: [0], index: 0)
        let (foreign, _) = try pair("bullet-ordered")
        let foreignAnchor = try foreign.anchor(path: [0, 0, 0], index: 0)
        let before = try native.encodeUpdate()
        for level in [0, 7, -1] {
            XCTAssertThrowsError(try native.setHeadingLevel(anchor: anchor, expectedHeadingID: "stable-1", level: level))
        }
        XCTAssertThrowsError(try native.setHeadingLevel(anchor: anchor, expectedHeadingID: "another", level: 2))
        XCTAssertThrowsError(try native.setHeadingLevel(anchor: foreignAnchor, expectedHeadingID: nil, level: 2))
        XCTAssertEqual(try native.encodeUpdate(), before)

        for attributes in ["{\"level\":true}", "{\"level\":7}", "{\"level\":2,\"unknown\":true}"] {
            let reference = try RelayMarkCollaborationDocument()
            _ = try reference.edit(Data("{\"kind\":\"insertNodes\",\"path\":[],\"index\":0,\"nodes\":[{\"kind\":\"element\",\"name\":\"heading\",\"attributes\":\(attributes),\"children\":[{\"kind\":\"text\",\"delta\":[{\"insert\":\"x\"}]}]}]}".utf8))
            let invalid = RelayMarkNativeDocument(); try invalid.applyUpdate(reference.encodeUpdate())
            let saved = try invalid.encodeUpdate()
            XCTAssertThrowsError(try invalid.setHeadingLevel(anchor: invalid.anchor(path: [0], index: 0), expectedHeadingID: nil, level: 1))
            XCTAssertEqual(try invalid.encodeUpdate(), saved)
        }
    }

    func testNestedListsEditByStableParagraphAnchorAndUndoOnlyLocalText() throws {
        for name in ["bullet-ordered", "ordered-bullet"] {
            let (native, browser) = try pair(name)
            let anchor = try native.anchor(path: [0, 0, 1, 0, 0], index: 0)
            let textAnchor = try native.anchor(path: [0, 0, 1, 0, 0, 0], index: 10)
            // A remote insertion changes all numeric root paths before local editing.
            for update in try browser.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"Remote"}]}]}]}"#.utf8)) {
                try native.applyUpdate(update)
            }
            let before = try native.snapshot()
            let beforeBytes = try native.encodeUpdate()
            XCTAssertThrowsError(try native.replaceListParagraphText(anchor: anchor, start: 8, end: 9, text: "broken surrogate"))
            XCTAssertThrowsError(try native.replaceListParagraphText(anchor: anchor, start: 0, end: 0, text: "new\nitem"))
            XCTAssertEqual(try native.encodeUpdate(), beforeBytes)
            try browser.applyUpdate(native.replaceListParagraphText(anchor: anchor, start: 7, end: 9, text: "moon"))
            XCTAssertEqual(try native.resolve(anchor: anchor)?.path, [1, 0, 1, 0, 0])
            XCTAssertEqual(try native.resolve(anchor: textAnchor)?.index, 12)
            XCTAssertEqual(String(decoding: try native.snapshot(), as: UTF8.self),
                           String(decoding: before, as: UTF8.self).replacingOccurrences(of: "Nested 🌍 text", with: "Nested moon text"))
            try equal(native, browser)
            try browser.applyUpdate(XCTUnwrap(native.undo()))
            XCTAssertEqual(try native.snapshot(), before) // Includes untouched remote paragraph and ordered-list start.
            try equal(native, browser)
            try browser.applyUpdate(XCTUnwrap(native.redo()))
            try equal(native, browser)
            for update in try browser.edit(Data(#"{"kind":"deleteNodes","path":[1,0,1],"index":0,"length":1}"#.utf8)) {
                try native.applyUpdate(update)
            }
            let deleted = try native.encodeUpdate()
            XCTAssertThrowsError(try native.replaceListParagraphText(anchor: anchor, start: 0, end: 0, text: "orphan"))
            XCTAssertEqual(try native.encodeUpdate(), deleted)
        }
    }
    func testNestedListForeignAnchorAndMultipleTextLeavesFailWithoutMutation() throws {
        let (native, browser) = try pair("bullet-ordered")
        let anchor = try native.anchor(path: [0, 0, 1, 0, 0], index: 0)
        let (foreign, _) = try pair("headings")
        var before = try native.encodeUpdate()
        XCTAssertThrowsError(try native.replaceListParagraphText(anchor: foreign.anchor(path: [0], index: 0), start: 0, end: 0, text: "foreign"))
        XCTAssertEqual(try native.encodeUpdate(), before)
        for update in try browser.edit(Data(#"{"kind":"insertNodes","path":[0,0,1,0,0],"index":1,"nodes":[{"kind":"text","delta":[{"insert":"Another leaf"}]}]}"#.utf8)) {
            try native.applyUpdate(update)
        }
        before = try native.encodeUpdate()
        XCTAssertThrowsError(try native.replaceListParagraphText(anchor: anchor, start: 0, end: 0, text: "unsupported"))
        XCTAssertEqual(try native.encodeUpdate(), before)
    }

}
