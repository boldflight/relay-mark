import Foundation
import XCTest
import RelayMarkProseProjection
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

/// A command run on a window of top-level nodes must write what the same
/// command writes when it reads the whole paper.
@MainActor
final class RelayMarkNativeWindowedCommandTests: XCTestCase {
    private let source = """
    # Heading **bold**

    Plain **bold** and [a link](https://relay.example/x) end.

    - First item
    - Second item

    - [ ] Open task
    - [x] Done task

    | Name | Value |
    | --- | --- |
    | left | right |

    > Quoted line

    Last paragraph.
    """

    /// Generated identities differ between runs; everything else must not,
    /// including which headings have an anchor.
    private func masked(_ value: Any) -> Any {
        if let object = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: object.map { key, value in
                (key, ["relaymarkId", "headingId"].contains(key) && !(value is NSNull) ? "*" : masked(value))
            })
        }
        if let array = value as? [Any] { return array.map(masked) }
        return value
    }

    private func shape(_ document: RelayMarkNativeDocument) throws -> String {
        let object = try JSONSerialization.jsonObject(with: document.snapshot())
        return String(data: try JSONSerialization.data(withJSONObject: masked(object), options: [.sortedKeys]), encoding: .utf8)!
    }

    private func replicas() throws -> (whole: RelayMarkNativeDocument, windowed: RelayMarkNativeDocument) {
        let whole = RelayMarkNativeDocument()
        let seed = try whole.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "window"))
        let windowed = RelayMarkNativeDocument(); try windowed.applyUpdate(seed)
        return (whole, windowed)
    }

    private enum Operation: CaseIterable { case returnKey, backspace, delete, lines, deletion, bold, indent, outdent }

    private func run(_ operation: Operation, at offset: Int, on document: RelayMarkNativeDocument,
                     paper: RelayMarkCollaborativeProse?) throws -> RelayMarkNativeRichEditing.Change? {
        let projection = try document.richProseProjection()
        switch operation {
        case .returnKey:
            guard let block = projection.blockRanges.firstIndex(where: { offset >= $0.location && offset <= NSMaxRange($0) }) else { return nil }
            let path = projection.blockPaths[block], local = offset - projection.blockRanges[block].location
            if let paper {
                return try RelayMarkNativeRichReturn.apply(document: document, blockPath: path, utf16Offset: local, paper: paper).change
            }
            return try RelayMarkNativeRichReturn.apply(document: document, blockPath: path, utf16Offset: local,
                                                       expectedSnapshot: document.snapshot()).change
        case .backspace, .delete:
            let key: RelayMarkNativeRichEditing.Key = operation == .backspace ? .backspace : .delete
            if let paper { return try RelayMarkNativeRichEditing.key(key, document: document, at: offset, paper: paper) }
            return try RelayMarkNativeRichEditing.key(key, document: document, at: offset, expectedSnapshot: document.snapshot())
        case .lines, .deletion:
            let range = NSRange(location: offset, length: operation == .lines ? 0 : 3)
            let runs: [(text: String, attributes: [String: Any])] = operation == .lines ? [("one\ntwo", [:])] : []
            if let paper { return try RelayMarkNativeRichEditing.replace(document: document, range: range, runs: runs, paper: paper) }
            return try RelayMarkNativeRichEditing.replace(document: document, range: range, runs: runs,
                                                          expectedSnapshot: document.snapshot())
        case .indent, .outdent:
            guard let block = projection.blockRanges.firstIndex(where: { offset >= $0.location && offset <= NSMaxRange($0) }),
                  document.isRichListParagraph(path: projection.blockPaths[block]) else { return nil }
            let path = projection.blockPaths[block], change: RelayMarkNativeListDepthChange = operation == .indent ? .indent : .outdent
            if let paper { return try document.changeRichListDepth(paragraphPath: path, change: change, paper: paper) }
            return try document.changeRichListDepth(paragraphPath: path, change: change, expectedSnapshot: document.snapshot())
        case .bold:
            let range = NSRange(location: offset, length: 3)
            if let paper {
                return try RelayMarkNativeRichEditing.format(document: document, range: range, mark: "bold", enabled: true, paper: paper)
            }
            return try RelayMarkNativeRichEditing.format(document: document, range: range, mark: "bold", enabled: true,
                                                         expectedSnapshot: document.snapshot())
        }
    }

    /// The window holds the list, so the list's own identity is not taken
    /// from it; a renamed list would rewrite the whole list instead.
    func testCommandsInsideALongListRunOnTheirItems() throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            (1...9).map { "- item \($0)" }.joined(separator: "\n"), namespace: "list"))
        let offset = String(try document.richProseProjection().text.characters).utf16.count / 2
        for operation in [Operation.returnKey, .bold, .indent, .lines] {
            let change = try XCTUnwrap(run(operation, at: offset, on: document, paper: document.richProseProjection()))
            XCTAssertNotNil(change.items, "\(operation)")
        }
    }

    func testWindowedCommandsWriteWhatWholePaperCommandsWrite() throws {
        var compared = 0, refused = 0, changed: [Operation: Int] = [:], itemWindows = 0
        let length = String(try replicas().whole.richProseProjection().text.characters).utf16.count
        for operation in Operation.allCases {
            for offset in stride(from: 0, to: length - 3, by: 4) {
                let (whole, windowed) = try replicas()
                var paper = try windowed.richProseProjection()
                let expected = try? run(operation, at: offset, on: whole, paper: nil)
                let actual: RelayMarkNativeRichEditing.Change?
                do { actual = try run(operation, at: offset, on: windowed, paper: paper) } catch {
                    // A window may only refuse what the whole paper refuses too.
                    XCTAssertNil(expected, "\(operation) at \(offset) refused: \(error)"); refused += 1; continue
                }
                XCTAssertEqual(try shape(windowed), try shape(whole), "\(operation) at \(offset)")
                XCTAssertEqual(actual?.caret, expected?.caret, "\(operation) at \(offset)")
                if let actual {
                    changed[operation, default: 0] += 1
                    if let items = actual.items {
                        itemWindows += 1
                        let partial = try XCTUnwrap(windowed.richProseProjection(items: items.after, ofTopLevel: items.node,
                                                                                 paper: paper, identityBase: paper.identityLimit))
                        if paper.replaceItems(items.before, ofTopLevel: items.node, with: partial) == nil {
                            // An ordered list renumbers its items: the host re-projects the whole list.
                            let whole = try windowed.richProseProjection(topLevel: items.node..<(items.node + 1), identityBase: paper.identityLimit)
                            XCTAssertNotNil(paper.replaceTopLevelNodes(items.node..<(items.node + 1), with: whole))
                        }
                    } else {
                        let nodes = try XCTUnwrap(actual.topLevel, "\(operation) at \(offset)")
                        let partial = try windowed.richProseProjection(topLevel: nodes.after, identityBase: paper.identityLimit)
                        XCTAssertNotNil(paper.replaceTopLevelNodes(nodes.before, with: partial))
                    }
                    XCTAssertEqual(String(paper.text.characters), String(try windowed.richProseProjection().text.characters),
                                   "\(operation) at \(offset)")
                    XCTAssertEqual(paper.blockPaths, try windowed.richProseProjection().blockPaths, "\(operation) at \(offset)")
                }
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 60)
        XCTAssertGreaterThan(itemWindows, 5, "commands inside lists ran on item windows")
        for operation in Operation.allCases { XCTAssertGreaterThan(changed[operation] ?? 0, 0, "\(operation) never changed the paper") }
        XCTAssertLessThan(refused, compared / 4)
    }

    /// Every block identity and destination name in the paper, in order.
    private func identities(_ document: RelayMarkNativeDocument) throws -> (ids: [String], anchors: [String]) {
        var ids: [String] = [], anchors: [String] = []
        func visit(_ node: [String: Any]) {
            let attributes = node["attributes"] as? [String: Any] ?? [:]
            if let id = attributes["relaymarkId"] as? String { ids.append(id) }
            if node["name"] as? String == "heading", let anchor = attributes["headingId"] as? String { anchors.append(anchor) }
            for child in node["children"] as? [[String: Any]] ?? [] { visit(child) }
        }
        visit(try XCTUnwrap(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any]))
        return (ids, anchors)
    }

    func testPastingACopyOfABlockElsewhereKeepsIdentitiesUnique() throws {
        let (whole, windowed) = try replicas()
        // An edit gives the first heading an anchor; both replicas then hold the same paper.
        let named = try RelayMarkNativeRichEditing.replace(document: whole, range: NSRange(location: 1, length: 0),
            runs: [("x", [:])], expectedSnapshot: whole.snapshot())
        try windowed.applyUpdate(named.update)
        let heading = try XCTUnwrap((try JSONSerialization.jsonObject(with: whole.snapshot()) as? [String: Any])?["children"]
            as? [[String: Any]]).first?["attributes"] as? [String: Any]
        let id = try XCTUnwrap(heading?["relaymarkId"] as? String), anchor = try XCTUnwrap(heading?["headingId"] as? String)
        let copy: [String: Any] = ["slice": ["content": [["type": "heading", "attrs": ["level": 1, "headingId": anchor, "relaymarkId": id],
                                                          "content": [["type": "text", "text": "Copy"]]]],
                                             "openStart": 0, "openEnd": 0], "normalizations": [[String: Any]]()]
        let slice = try JSONSerialization.data(withJSONObject: copy)
        // Pasted into the last paragraph, far from the original heading's window.
        let end = String(try windowed.richProseProjection().text.characters).utf16.count
        let paper = try windowed.richProseProjection()
        let range = NSRange(location: end - 3, length: 0)
        XCTAssertFalse(paper.topLevelIndex(atUTF16: range.location).map { $0 <= 1 } ?? true)
        _ = try RelayMarkNativeRichEditing.insertDocumentSlice(document: whole, range: range, clipboardSlice: slice,
                                                               expectedSnapshot: whole.snapshot())
        let pasted = try RelayMarkNativeRichEditing.insertDocumentSlice(document: windowed, range: range, clipboardSlice: slice, paper: paper)
        XCTAssertNotNil(pasted.topLevel, "the paste ran on a window")
        XCTAssertEqual(try shape(windowed), try shape(whole))
        let result = try identities(windowed)
        XCTAssertEqual(Set(result.ids).count, result.ids.count, "a block identity is duplicated")
        XCTAssertEqual(Set(result.anchors).count, result.anchors.count, "a heading anchor is duplicated")
        XCTAssertTrue(result.anchors.contains(anchor) && result.ids.contains(id), "the original keeps its identity")
    }
}
