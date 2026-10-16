import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeRichEditingTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "native-replace-v3", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func path(of id: String, in node: [String: Any], prefix: [Int] = []) -> [Int]? {
        if (node["attributes"] as? [String: Any])?["relaymarkId"] as? String == id { return prefix }
        for (index, child) in (node["children"] as? [[String: Any]] ?? []).enumerated() {
            if let found = path(of: id, in: child, prefix: prefix + [index]) { return found }
        }
        return nil
    }

    private func ids(_ node: [String: Any]) -> [String] {
        let own = ((node["attributes"] as? [String: Any])?["relaymarkId"] as? String).map { [$0] } ?? []
        return own + (node["children"] as? [[String: Any]] ?? []).flatMap(ids)
    }

    private func withoutIDs(_ value: Any) -> Any {
        if var object = value as? [String: Any] {
            if var attributes = object["attributes"] as? [String: Any], object["kind"] as? String == "element" {
                attributes["relaymarkId"] = nil
                object["attributes"] = attributes
            }
            return object.mapValues(withoutIDs)
        }
        if let array = value as? [Any] { return array.map(withoutIDs) }
        return value
    }

    private func canonical(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: withoutIDs(value), options: [.sortedKeys]),
               as: UTF8.self)
    }

    private func tree(_ document: RelayMarkNativeDocument) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
    }

    func testFormattingAcrossHardBreakKeepsCanonicalBreakAndPeerUndo() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            "left  \nright\n\n---\n\ntail", namespace: "native-format-break"))
        try peer.applyUpdate(document.encodeUpdate())
        let original = try document.authoredDocument()
        let projection = try document.richProseProjection()
        let effect = try XCTUnwrap(RelayMarkNativeRichEditing.format(document: document,
            range: NSRange(location: 0, length: String(projection.text.characters).utf16.count),
            mark: "bold", enabled: true, expectedSnapshot: document.snapshot()))
        try peer.applyUpdate(effect.update)
        func markedText(_ value: Any) -> Any {
            if let node = value as? [String: Any] {
                if node["type"] as? String == "text" { return ["type": "strong", "content": [node]] }
                return node.mapValues(markedText)
            }
            if let array = value as? [Any] { return array.map(markedText) }
            return value
        }
        let expected = try JSONSerialization.data(withJSONObject:
            markedText(JSONSerialization.jsonObject(with: original)), options: [.sortedKeys])
        XCTAssertEqual(try canonical(JSONSerialization.jsonObject(with: document.authoredDocument())),
            try canonical(JSONSerialization.jsonObject(with: expected)))
        XCTAssertEqual(try peer.authoredDocument(), try document.authoredDocument())
        let undo = try XCTUnwrap(document.undo())
        try peer.applyUpdate(undo)
        XCTAssertEqual(try document.authoredDocument(), original)
        XCTAssertEqual(try peer.authoredDocument(), original)
    }

    func testEmbeddedSchemaIsTheCanonicalSharedSchema() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let exported=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("spec/relaymark/editor-schema.json")))
        let embedded = try JSONSerialization.jsonObject(with: Data(RelayMarkNativeProseMirrorSchema.json.utf8))
        // The host registers PaperDocument at a different priority; paragraph
        // remains the shared default fill. Compare every serializable semantic
        // property by node/mark name rather than registration position.
        func namedSchema(_ value: Any) throws -> [String: Any] {
            var schema = try XCTUnwrap(value as? [String: Any])
            for key in ["nodes", "marks"] {
                let entries = try XCTUnwrap(schema[key] as? [[String: Any]])
                if key == "nodes" { XCTAssertEqual(entries.first?["name"] as? String, "paragraph") }
                schema[key] = entries.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
            }
            return schema
        }
        XCTAssertEqual(try canonical(namedSchema(embedded)), try canonical(namedSchema(exported)))
        XCTAssertNoThrow(try PMYXmlBridge.canonical())
    }

    /// Every case is replayed against actual ProseMirror output through the
    /// browser schema: same XML, same retained IDs, same caret, peer replay
    /// and exact undo.
    func testCrossContainerReplacementMatchesProseMirror() throws {
        let fixture = try fixture()
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String)))
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 93)
        var failures: [String] = []
        for (number, entry) in cases.enumerated() {
            let action = try XCTUnwrap(entry["action"] as? String)
            let from = try XCTUnwrap(entry["from"] as? [String: Any]), to = try XCTUnwrap(entry["to"] as? [String: Any])
            let label = "#\(number) \(action) \(from["id"]!)@\(from["offset"]!)→\(to["id"]!)@\(to["offset"]!)"
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try native.applyUpdate(seed)
            try peer.applyUpdate(seed)
            let before = try native.snapshot(), beforeTree = try tree(native)
            let prose = try native.richProseProjection()
            func location(_ endpoint: [String: Any]) throws -> Int {
                let blockPath = try XCTUnwrap(path(of: try XCTUnwrap(endpoint["id"] as? String), in: beforeTree))
                let block = try XCTUnwrap(prose.blockPaths.firstIndex(of: blockPath))
                return prose.blockRanges[block].location + (try XCTUnwrap(endpoint["offset"] as? Int))
            }
            let start = try location(from), end = try location(to)
            let runs: [(text: String, attributes: [String: Any])] = action == "delete" ? []
                : action == "insertText" ? [("X", [:])] : [("P1\nP2", [:])]
            let unchanged = (entry["update"] as? String).map { $0.count < 8 } ?? true
            let change: RelayMarkNativeRichEditing.Change
            do {
                if action == "insertTable" || action == "insertImage" {
                    func cell(_ header: Bool) -> [String: Any] {
                        ["type": header ? "tableHeader" : "tableCell", "content": [["type": "paragraph"]]]
                    }
                    let table: [String: Any] = ["type": "table", "content": (0..<3).map { row in
                        ["type": "tableRow", "content": (0..<3).map { _ in cell(row == 0) }] as [String: Any]
                    }]
                    let image: [String: Any] = ["type": "image", "attrs": ["src": "https://example.com/b.png", "alt": "B"]]
                    change = try RelayMarkNativeRichEditing.insertBlock(document: native,
                        range: NSRange(location: start, length: 0), block: action == "insertTable" ? table : image,
                        placement: action == "insertTable" ? .replaceSelection : .insertContent, expectedSnapshot: before)
                } else if action == "Backspace" || action == "Delete" {
                    let keyed = try RelayMarkNativeRichEditing.key(action == "Backspace" ? .backspace : .delete,
                        document: native, at: start, expectedSnapshot: before)
                    if unchanged {
                        if keyed != nil { failures.append("\(label): changed where the browser did not") }
                        if try native.snapshot() != before { failures.append("\(label): document changed") }
                        continue
                    }
                    guard let keyed else { failures.append("\(label): no change"); continue }
                    change = keyed
                } else {
                    change = try RelayMarkNativeRichEditing.replace(document: native,
                        range: NSRange(location: start, length: end - start), runs: runs,
                        inheritMarks: action == "insertText", expectedSnapshot: before)
                }
            } catch {
                failures.append("\(label): threw \(error)")
                continue
            }
            let after = try tree(native), expected = try XCTUnwrap(entry["after_xml"] as? [String: Any])
            guard try canonical(after) == canonical(expected) else {
                failures.append("\(label): XML differs\n native \(try canonical(after))\n browser \(try canonical(expected))")
                continue
            }
            let original = Set(ids(beforeTree)), nativeIDs = ids(after)
            if Set(nativeIDs).count != nativeIDs.count { failures.append("\(label): duplicate IDs") }
            if Set(nativeIDs).intersection(original) != Set(ids(expected)).intersection(original) {
                failures.append("\(label): retained IDs differ")
            }
            let selection = try XCTUnwrap(entry["selection_after"] as? [String: Any])
            if let id = selection["id"] as? String, let expectedPath = path(of: id, in: expected) {
                if change.caret != .init(blockPath: expectedPath, offset: try XCTUnwrap(selection["offset"] as? Int)) {
                    failures.append("\(label): caret \(String(describing: change.caret)) expected \(expectedPath)@\(selection["offset"]!)")
                }
            }
            try peer.applyUpdate(change.update)
            if try native.snapshot() != peer.snapshot() { failures.append("\(label): peer differs") }
            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            if try native.snapshot() != before || peer.snapshot() != before { failures.append("\(label): undo differs") }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of \(cases.count) cases failed:\n" + failures.joined(separator: "\n"))
    }
}

@MainActor
final class RelayMarkNativeRichInlineInsertionTests: XCTestCase {
    /// A #tag reference and a linked entity label insert at a caret inside a
    /// list item, as the browser's tag and entity suggestions insert them.
    func testTagAndEntityLinkInsertInOneTransaction() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "native-replace-v3", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try native.snapshot()
        let prose = try native.richProseProjection()
        let text = String(prose.text.characters) as NSString
        let bullet = text.range(of: "Bullet one")
        let caret = NSRange(location: bullet.location + 6, length: 0)
        let tagID = "11111111-2222-4333-8444-555555555555", entityID = "66666666-7777-4888-8999-aaaaaaaaaaaa"
        let link: [String: Any] = ["href": "relay:entity/\(entityID)", "target": "_blank",
                                   "rel": "noopener noreferrer nofollow", "class": NSNull(), "title": NSNull()]
        let change = try RelayMarkNativeRichEditing.insert(document: native, range: caret, content: [
            .node("relayTag", attributes: ["id": tagID, "name": "native-proof",
                                           "source": "[[Tag: \(tagID) | #native-proof]]"]),
            .text(" "),
            .text("Alex", attributes: ["link": link]),
            .text(" "),
        ], expectedSnapshot: before)
        let after = try native.richProseProjection()
        XCTAssertTrue(String(after.text.characters).contains("Bullet\u{FFFC} Alex  one"))
        XCTAssertEqual(after.inlineAtoms.filter { $0.id == tagID }.count, 1)
        let block = try XCTUnwrap(after.blockRanges.firstIndex { NSLocationInRange(bullet.location, $0) })
        XCTAssertEqual(change.caret, .init(blockPath: after.blockPaths[block], offset: 13))
        try peer.applyUpdate(change.update)
        XCTAssertEqual(try native.snapshot(), try peer.snapshot())
        XCTAssertThrowsError(try RelayMarkNativeRichEditing.insert(document: native, range: caret,
            content: [.node("relayTag", attributes: ["color": "red"])], expectedSnapshot: native.snapshot()))
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try native.snapshot(), before)
        XCTAssertEqual(try peer.snapshot(), before)
    }
}

@MainActor
final class RelayMarkNativeUndoGroupingTests: XCTestCase {
    /// Deleting a selection and splitting at the caret, as Return over a
    /// selection does in ProseMirror, undoes as one step.
    func testGroupedDeleteAndReturnUndoTogether() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "native-replace-v3", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String)))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        let before = try native.snapshot(), vector = native.stateVector()
        let prose = try native.richProseProjection()
        let alpha = (String(prose.text.characters) as NSString).range(of: "Alpha one")
        try native.groupingUndo {
            let deleted = try RelayMarkNativeRichEditing.replace(document: native,
                range: NSRange(location: alpha.location + 2, length: 3), runs: [], expectedSnapshot: native.snapshot())
            let caret = try XCTUnwrap(deleted.caret)
            _ = try RelayMarkNativeRichReturn.apply(document: native, blockPath: caret.blockPath,
                utf16Offset: caret.offset, expectedSnapshot: native.snapshot())
        }
        let text = String(try native.richProseProjection().text.characters)
        XCTAssertTrue(text.hasPrefix("Al\n one\n"))
        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(seed)
        try peer.applyUpdate(try native.encodeUpdate(since: vector))
        XCTAssertEqual(try native.snapshot(), try peer.snapshot())
        _ = try XCTUnwrap(native.undo())
        XCTAssertEqual(try native.snapshot(), before)
    }
}

@MainActor
final class RelayMarkNativeEmptyParagraphPasteTests: XCTestCase {
    /// A lone newline pastes two empty open paragraphs; ProseMirror's
    /// replaceRange tolerates the empty open level instead of failing.
    func testNewlineOverSelectionSplitsTheParagraph() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "native-replace-v3", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String))))
        let before = try native.snapshot()
        let prose = try native.richProseProjection()
        let alpha = (String(prose.text.characters) as NSString).range(of: "Alpha one")
        _ = try RelayMarkNativeRichEditing.replace(document: native,
            range: NSRange(location: alpha.location + 2, length: 3), runs: [("\n", [:])], expectedSnapshot: before)
        XCTAssertTrue(String(try native.richProseProjection().text.characters).hasPrefix("Al\n one\n"))
        _ = try XCTUnwrap(native.undo())
        XCTAssertEqual(try native.snapshot(), before)
    }
}
