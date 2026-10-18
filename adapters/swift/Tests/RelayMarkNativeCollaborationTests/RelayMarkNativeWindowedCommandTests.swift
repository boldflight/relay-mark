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

    /// Generated identities differ between runs; everything else must not. A
    /// whole-paper command also gives every heading lacking an anchor one, while
    /// a window gives only its own, so heading anchors are left out.
    private func masked(_ value: Any) -> Any {
        if let object = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: object.compactMap { key, value in
                key == "headingId" ? nil : (key, key == "relaymarkId" ? "*" : masked(value))
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

    func testWindowedCommandsWriteWhatWholePaperCommandsWrite() throws {
        var compared = 0, refused = 0, changed: [Operation: Int] = [:]
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
                    let nodes = try XCTUnwrap(actual.topLevel, "\(operation) at \(offset)")
                    let partial = try windowed.richProseProjection(topLevel: nodes.after, identityBase: paper.identityLimit)
                    XCTAssertNotNil(paper.replaceTopLevelNodes(nodes.before, with: partial))
                    XCTAssertEqual(String(paper.text.characters), String(try windowed.richProseProjection().text.characters),
                                   "\(operation) at \(offset)")
                    XCTAssertEqual(paper.blockPaths, try windowed.richProseProjection().blockPaths, "\(operation) at \(offset)")
                }
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 60)
        for operation in Operation.allCases { XCTAssertGreaterThan(changed[operation] ?? 0, 0, "\(operation) never changed the paper") }
        XCTAssertLessThan(refused, compared / 4)
    }
}
