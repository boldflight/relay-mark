import Foundation
import XCTest
import RelayMarkProseProjection
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

/// Typing updates the projection in place; the result must equal a full re-projection.
@MainActor
final class RelayMarkNativeTypingProjectionTests: XCTestCase {
    private let source = """
    # Heading **bold**

    Plain **bold** and [a link](https://relay.example/x) end.

    - First item
    - [ ] Open task
    - [x] Done task

    | Name | Value |
    | --- | --- |
    | left | right |

    ```swift
    let code = 1
    ```

    Last paragraph.
    """

    private func assertMatches(_ incremental: RelayMarkCollaborativeProse, _ full: RelayMarkCollaborativeProse,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(incremental.text, full.text, file: file, line: line)
        XCTAssertEqual(incremental.blockRanges, full.blockRanges, file: file, line: line)
        XCTAssertEqual(incremental.blockPaths, full.blockPaths, file: file, line: line)
        XCTAssertEqual(incremental.tableCells, full.tableCells, file: file, line: line)
        XCTAssertEqual(incremental.callouts, full.callouts, file: file, line: line)
        XCTAssertEqual(incremental.inlineAtoms, full.inlineAtoms, file: file, line: line)
        XCTAssertEqual(incremental.taskItems, full.taskItems, file: file, line: line)
        XCTAssertEqual(incremental.authoredWidgets, full.authoredWidgets, file: file, line: line)
        let length = String(full.text.characters).utf16.count
        for offset in 0...length {
            XCTAssertEqual(incremental.position(atUTF16: offset).map { "\($0)" }, full.position(atUTF16: offset).map { "\($0)" },
                           "position \(offset)", file: file, line: line)
        }
    }

    func testTypingAndDeletingAnywhereMatchesFullProjection() throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "typing"))
        var projection = try document.richProseProjection()
        let length = String(projection.text.characters).utf16.count
        var edits = 0
        for offset in stride(from: 0, through: length, by: 3) {
            for (removed, inserted) in [(0, "x"), (1, ""), (1, "yz")] {
                let range = NSRange(location: offset, length: removed)
                guard NSMaxRange(range) <= String(projection.text.characters).utf16.count,
                      let position = projection.textPosition(replacing: range) else { continue }
                let typed = try document.typeText(inserted, replacing: removed, at: position.index, path: position.path)
                guard let next = projection.replacingText(in: range, with: inserted, attributes: typed.attributes) else {
                    projection = try document.richProseProjection(); continue
                }
                assertMatches(next, try document.richProseProjection())
                projection = next
                // Settling at an arbitrary pause must not change what the projection says.
                if edits % 7 == 0 {
                    var settled = next; settled.settle()
                    assertMatches(settled, try document.richProseProjection())
                    projection = settled
                }
                edits += 1
            }
        }
        XCTAssertGreaterThan(edits, 30)
    }

    func testTypedMarksFollowTheStoredMarkRules() throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            "a **bold** [link](https://relay.example/x) z", namespace: "marks"))
        let projection = try document.richProseProjection()
        func typed(after needle: String) throws -> [String: Any] {
            let offset = (String(try document.richProseProjection().text.characters) as NSString).range(of: needle)
            let range = NSRange(location: NSMaxRange(offset), length: 0)
            let position = try XCTUnwrap(try document.richProseProjection().textPosition(replacing: range))
            return try document.typeText("_", replacing: 0, at: position.index, path: position.path).attributes
        }
        _ = projection
        XCTAssertNotNil(try typed(after: "bold")["bold"], "Bold continues at its end")
        XCTAssertNil(try typed(after: "link")["link"], "A link does not extend past its end")
        XCTAssertTrue(try typed(after: "a ").isEmpty)
    }

    func testRevisionAdvancesOnEveryChange() throws {
        let document = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("Hello", namespace: "rev"))
        let start = document.revision
        let position = try XCTUnwrap(try document.richProseProjection().textPosition(replacing: NSRange(location: 5, length: 0)))
        _ = try document.typeText("!", replacing: 0, at: position.index, path: position.path)
        XCTAssertGreaterThan(document.revision, start)
        let deleting = document.revision
        _ = try document.typeText("", replacing: 1, at: position.index, path: position.path)
        XCTAssertGreaterThan(document.revision, deleting, "A delete advances the revision though the state vector does not")
        let peer = RelayMarkNativeDocument(); let before = peer.revision
        try peer.applyUpdate(seed)
        XCTAssertGreaterThan(peer.revision, before)
    }

    func testPeerTextEditsReprojectOnlyTheirLeaves() throws {
        let document = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "remote"))
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(seed)
        var projection = try document.richProseProjection()
        let length = String(projection.text.characters).utf16.count
        var spliced = 0
        for offset in stride(from: 0, through: length, by: 5) {
            let peerProjection = try peer.richProseProjection()
            guard let position = peerProjection.textPosition(replacing: NSRange(location: offset, length: 0)) else { continue }
            let update: Data
            switch offset % 3 {
            case 0: update = try peer.typeText("p", replacing: 0, at: position.index, path: position.path).update
            case 1:
                guard position.index > 0 else { continue }
                update = try peer.typeText("", replacing: 1, at: position.index - 1, path: position.path).update
            default:
                // Code blocks carry no marks.
                guard position.index > 0, position.path.first != 4 else { continue }
                update = try peer.formatText(at: 0, length: position.index, attributes: ["bold": [:]], path: position.path)
            }
            try document.applyUpdate(update)
            let leaves = try XCTUnwrap(document.textLeavesTouchedByLastUpdate())
            XCTAssertEqual(leaves, [position.path])
            for leaf in leaves {
                let runs = try document.textRuns(path: leaf)
                XCTAssertTrue(projection.replaceLeaf(path: leaf, runs: runs), "\(offset % 3) \(leaf) \(runs.map { ($0.text, $0.attributes) })")
            }
            assertMatches(projection, try document.richProseProjection())
            spliced += 1
        }
        XCTAssertGreaterThan(spliced, 20)
        // Inserting nodes changes structure; the host re-projects the paper.
        let structural = try RelayMarkNativeDocument().initializeDocument(
            authoredAST: RelayMarkSourceCodec.parseDocument("New paragraph.", namespace: "other"))
        try document.applyUpdate(structural)
        XCTAssertNil(document.textLeavesTouchedByLastUpdate())
    }

    func testOneDeleteRangeSpanningTextAndANodeIsStructural() throws {
        let document = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("Hello", namespace: "span"))
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(seed)
        // The peer's "x" and hard break take consecutive clocks, so deleting both is one range.
        try document.applyUpdate(try RelayMarkNativeRichEditing.insert(
            document: peer, range: NSRange(location: 5, length: 0), content: [.text("x"), .node("hardBreak")],
            expectedSnapshot: peer.snapshot()).update)
        try document.applyUpdate(try RelayMarkNativeRichEditing.replace(
            document: peer, range: NSRange(location: 5, length: 2), runs: [], expectedSnapshot: peer.snapshot()).update)
        XCTAssertEqual(String(try document.richProseProjection().text.characters), "Hello")
        XCTAssertNil(document.textLeavesTouchedByLastUpdate(), "Removing the break node changed structure")
    }
}
