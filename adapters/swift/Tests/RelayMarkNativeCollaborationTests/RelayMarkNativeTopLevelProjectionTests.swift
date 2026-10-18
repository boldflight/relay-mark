import Foundation
import XCTest
import RelayMarkProseProjection
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

/// A peer's structural edit re-projects only the top-level nodes it touched;
/// the result must say what a full projection says, up to identity numbering.
@MainActor
final class RelayMarkNativeTopLevelProjectionTests: XCTestCase {
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

    ```swift
    let code = 1
    ```

    > Quoted line

    Last paragraph.
    """

    /// Presentation identities only need to be unique, so they are compared by
    /// order of first appearance.
    private func canonical(_ projection: RelayMarkCollaborativeProse) -> [String] {
        var identities: [Int: Int] = [:]
        func intent(_ value: PresentationIntent?) -> String {
            (value?.components ?? []).map { component in
                let identity = identities[component.identity] ?? identities.count
                identities[component.identity] = identity
                return "\(component.kind)#\(identity)"
            }.joined(separator: "<")
        }
        var lines = projection.text.runs.map { run in
            "\(String(projection.text[run.range].characters).debugDescription) \(intent(run.presentationIntent)) " +
            "\(run.inlinePresentationIntent?.rawValue ?? 0) \(run.link?.absoluteString ?? "")"
        }
        lines += projection.blockIntents.map(intent)
        lines += zip(projection.blockRanges, projection.blockPaths).map { "block \($0) \($1)" }
        var tables: [Int: Int] = [:]
        lines += projection.tableCells.map { cell in
            let table = tables[cell.tableIdentity] ?? tables.count
            tables[cell.tableIdentity] = table
            return "cell \(table) \(cell.range) \(cell.row) \(cell.column) \(cell.header)"
        }
        lines += projection.callouts.map { "callout \($0)" } + projection.inlineAtoms.map { "atom \($0)" }
        lines += projection.taskItems.map { "task \($0)" } + projection.authoredWidgets.map { "widget \($0)" }
        let length = String(projection.text.characters).utf16.count
        lines += (0...length).map { "position \($0) \(projection.position(atUTF16: $0).map { "\($0)" } ?? "nil")" }
        lines.append("editable \(projection.isEditable)")
        return lines
    }

    private func assertEquivalent(_ incremental: RelayMarkCollaborativeProse, _ full: RelayMarkCollaborativeProse,
                                  _ message: String, document: RelayMarkNativeDocument? = nil,
                                  file: StaticString = #filePath, line: UInt = #line) {
        // The uniqueness index follows the splices exactly.
        if let document, let snapshot = try? JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any] {
            var ids: [String] = [], anchors: [String] = []
            func visit(_ node: [String: Any]) {
                let attributes = node["attributes"] as? [String: Any] ?? [:]
                if let id = attributes["relaymarkId"] as? String { ids.append(id) }
                if node["name"] as? String == "heading", let anchor = attributes["headingId"] as? String { anchors.append(anchor) }
                for child in node["children"] as? [[String: Any]] ?? [] { visit(child) }
            }
            visit(snapshot)
            for id in Set(ids) { XCTAssertEqual(incremental.identityCount(id), ids.filter { $0 == id }.count, message, file: file, line: line) }
            for anchor in Set(anchors) {
                XCTAssertEqual(incremental.anchorCount(anchor), anchors.filter { $0 == anchor }.count, message, file: file, line: line)
            }
        }
        let lhs = canonical(incremental), rhs = canonical(full)
        XCTAssertEqual(lhs.count, rhs.count, message, file: file, line: line)
        for (left, right) in zip(lhs, rhs) where left != right {
            XCTFail("\(message): \(left) != \(right)", file: file, line: line); return
        }
    }

    func testPeerStructuralEditsReprojectOnlyTheirTopLevelNodes() throws {
        let document = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "structure"))
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(seed)
        var projection = try document.richProseProjection()
        var applied = 0
        let length = String(projection.text.characters).utf16.count
        for offset in stride(from: 1, to: length - 2, by: 3) {
            let peerProjection = try peer.richProseProjection()
            guard offset < String(peerProjection.text.characters).utf16.count - 2 else { break }
            let update: Data
            do {
                switch offset % 4 {
                case 0: // a new paragraph, as pasting two lines does
                    update = try RelayMarkNativeRichEditing.replace(document: peer, range: NSRange(location: offset, length: 0),
                        runs: [("one\ntwo", [:])], expectedSnapshot: peer.snapshot()).update
                case 1: // a deletion across the following separator joins blocks
                    update = try RelayMarkNativeRichEditing.replace(document: peer, range: NSRange(location: offset, length: 2),
                        runs: [], expectedSnapshot: peer.snapshot()).update
                case 2:
                    guard let change = try RelayMarkNativeRichEditing.key(.backspace, document: peer, at: offset,
                                                                         expectedSnapshot: peer.snapshot()) else { continue }
                    update = change.update
                default:
                    guard let position = peerProjection.textPosition(replacing: NSRange(location: offset, length: 0)) else { continue }
                    update = try peer.typeText("t", replacing: 0, at: position.index, path: position.path).update
                }
            } catch { continue }
            try document.applyUpdate(update)
            let touched = try XCTUnwrap(document.topLevelNodesTouchedByLastUpdate(), "offset \(offset)")
            let partial = try document.richProseProjection(topLevel: touched.after, identityBase: projection.identityLimit)
            XCTAssertNotNil(projection.replaceTopLevelNodes(touched.before, with: partial), "offset \(offset)")
            assertEquivalent(projection, try document.richProseProjection(), "offset \(offset) case \(offset % 4)", document: document)
            applied += 1
        }
        XCTAssertGreaterThan(applied, 15)
    }

    func testAttributeChangesAndWholeNodeRemovalsAreLocated() throws {
        let document = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "located"))
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(seed)
        var projection = try document.richProseProjection()
        func apply(_ update: Data, within after: Range<Int>, file: StaticString = #filePath, line: UInt = #line) throws {
            try document.applyUpdate(update)
            let touched = try XCTUnwrap(document.topLevelNodesTouchedByLastUpdate(), file: file, line: line)
            XCTAssertTrue(after.contains(touched.after.lowerBound) && touched.after.upperBound <= after.upperBound,
                          "\(touched.after)", file: file, line: line)
            let partial = try document.richProseProjection(topLevel: touched.after, identityBase: projection.identityLimit)
            XCTAssertNotNil(projection.replaceTopLevelNodes(touched.before, with: partial), file: file, line: line)
            assertEquivalent(projection, try document.richProseProjection(), "\(after)", file: file, line: line)
        }
        let level = try peer.setRichHeadingLevel(anchor: peer.anchor(path: [0], index: 0),
                                                 expectedHeadingID: try headingIdentifier(peer), level: 2)
        try apply(level.update, within: 0..<1)
        // Removing the whole second paragraph touches only it and its neighbour.
        let paragraph = try peer.richProseProjection().blockRanges[1]
        let removal = try RelayMarkNativeRichEditing.replace(document: peer,
            range: NSRange(location: paragraph.location - 1, length: paragraph.length + 1), runs: [],
            expectedSnapshot: peer.snapshot())
        try apply(removal.update, within: 0..<2)
    }

    private func headingIdentifier(_ document: RelayMarkNativeDocument) throws -> String? {
        let snapshot = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any]
        let heading = (snapshot?["children"] as? [[String: Any]])?.first
        return (heading?["attributes"] as? [String: Any])?["headingId"] as? String
    }

    func testPeerEditsInsideAListReprojectOnlyTheirItems() throws {
        let markdown = "Intro\n\n" + (0..<40).map { "- [ ] Task \($0)" }.joined(separator: "\n") + "\n\nOutro"
        let document = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "list"))
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(seed)
        var projection = try document.richProseProjection()
        XCTAssertEqual(projection.itemCount(ofTopLevel: 1), 40)
        var spliced = 0
        for (step, item) in stride(from: 2, to: 36, by: 3).enumerated() {
            let peerProjection = try peer.richProseProjection()
            let range = try XCTUnwrap(peerProjection.blockRange(path: [1, item, 0]))
            let update: Data
            switch step % 4 {
            case 0: update = try peer.typeText("z", replacing: 0, at: 2, path: [1, item, 0, 0]).update
            case 1: update = try RelayMarkNativeRichReturn.apply(document: peer, blockPath: [1, item, 0], utf16Offset: 3,
                                                                  expectedSnapshot: peer.snapshot()).change.update
            case 2: update = try RelayMarkNativeRichEditing.replace(document: peer, range: NSRange(location: NSMaxRange(range) - 2, length: 5),
                                                                    runs: [], expectedSnapshot: peer.snapshot()).update
            default: update = try peer.changeRichListDepth(paragraphPath: [1, item, 0], change: .indent, expectedSnapshot: peer.snapshot()).update
            }
            try document.applyUpdate(update)
            guard let touched = document.itemsTouchedByLastUpdate() else {
                // Lifting an item out of the list splits it: the paper's top level changed.
                let nodes = try XCTUnwrap(document.topLevelNodesTouchedByLastUpdate())
                let partial = try document.richProseProjection(topLevel: nodes.after, identityBase: projection.identityLimit)
                XCTAssertNotNil(projection.replaceTopLevelNodes(nodes.before, with: partial))
                assertEquivalent(projection, try document.richProseProjection(), "step \(step)", document: document)
                break
            }
            XCTAssertEqual(touched.node, 1)
            XCTAssertLessThanOrEqual(touched.after.count, 3, "step \(step) touched \(touched.after)")
            XCTAssertEqual(projection.listAttributes(ofTopLevel: 1), document.listAttributes(ofTopLevel: 1))
            let count = try XCTUnwrap(projection.itemCount(ofTopLevel: 1))
            let before = touched.after.lowerBound..<(count - (touched.count - touched.after.upperBound))
            let items = try XCTUnwrap(document.richProseProjection(items: touched.after, ofTopLevel: 1, paper: projection,
                                                                   identityBase: projection.identityLimit))
            XCTAssertNotNil(projection.replaceItems(before, ofTopLevel: 1, with: items), "step \(step)")
            assertEquivalent(projection, try document.richProseProjection(), "step \(step)", document: document)
            spliced += 1
        }
        XCTAssertGreaterThanOrEqual(spliced, 10)
    }
}
