import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkSwift
#if os(iOS)
import UIKit
import UniformTypeIdentifiers

/// The UIKit editor shares the TextKit 2 stack: UITextView switches itself to
/// TextKit 1 for NSTextTable and NSTextBlock, so these paths must never use them.
@MainActor @Suite(.serialized)
struct RelayMarkEditorTextKit2UIKitTests {
    private let markdown = """
    Before

    | Name | Note |
    | --- | --- |
    | left cell | right cell |
    | lower left | lower right |

    After
    """

    private func mount() throws -> (RelayMarkEditorSession,
        RelayMarkEditorView.TextCoordinator, CollaborationTextView) {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "uikit"))
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        view.layoutIfNeeded()
        let manager = try #require(view.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        return (editor, coordinator, view)
    }

    @Test func tablesAreAttachmentsOfCellViewsOnTextKit2() throws {
        let (editor, coordinator, view) = try mount()
        defer { coordinator.retire(view) }
        #expect(view.textLayoutManager != nil, "UITextView fell back to TextKit 1")
        #expect(view.text == "Before\n\u{FFFC}\nAfter")
        let table = try #require(view.paper.tables.spans.first?.table)
        func cell(_ prefix: String) throws -> RelayTableCellTextView {
            table.grid.cellView(try #require(table.cells.firstIndex { $0.text.string.hasPrefix(prefix) }))
        }
        let left = try cell("left"), right = try cell("right"), lower = try cell("lower left")
        #expect(right.frame.minX >= left.frame.maxX - 1 && abs(right.frame.minY - left.frame.minY) < 1)
        #expect(lower.frame.minY >= left.frame.maxY - 1)
        #expect(left.textLayoutManager != nil, "A cell must edit on TextKit 2")
        // Typing in a cell goes to the paper's session.
        right.selectedRange = NSRange(location: 5, length: 0)
        right.insertText("x")
        #expect(editor.failure == nil && String(editor.text.characters).contains("rightx cell"))
        // Find in paper finds a match inside a cell and highlights it there.
        let search = try #require(view.findInteraction?.delegate as? RelayPaperTextSearch)
        let match = (String(editor.text.characters) as NSString).range(of: "lower right")
        search.decorate(foundTextRange: RelayPaperTextRange(match), document: nil, usingStyle: .highlighted)
        #expect(search.decorations[match] == .highlighted)
        #expect(try cell("lower right").layer.sublayers?.contains { $0.name == "relay.found" } == true)
        // VoiceOver reads the grid as a data table.
        #expect(table.grid.accessibilityRowCount() == 3 && table.grid.accessibilityColumnCount() == 2)
        let element = try #require(table.grid.accessibilityDataTableCellElement(forRow: 1, column: 1))
        #expect((element as? UIAccessibilityElement)?.accessibilityLabel == "rightx cell")
        // Copy across the table gives its rows of cells; Writing Tools works in the cells.
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        view.copyPasteboard = pasteboard
        view.selectedRange = NSRange(location: 2, length: (view.text as NSString).range(of: "After").location)
        view.copy(nil)
        #expect(pasteboard.string == "fore\nName\tNote\nleft cell\trightx cell\nlower left\tlower right\nAf")
        let ignored = coordinator.textView(view, writingToolsIgnoredRangesInEnclosingRange:
            NSRange(location: 0, length: (view.text as NSString).length)).map(\.rangeValue)
        #expect(ignored == [NSRange(location: 7, length: 1)])
        #expect(view.textLayoutManager != nil, "An editor path switched UITextView to TextKit 1")
    }

    /// The task-checkbox tap must not win over UITextView's own taps, or a tap
    /// in the paper never places the caret and the keyboard never appears.
    @Test func taskTapLeavesTheTextViewsOwnTapsWorking() throws {
        let (_, coordinator, view) = try mount()
        defer { coordinator.retire(view) }
        let recognizers = view.gestureRecognizers ?? []
        let task = try #require(recognizers.first { $0.name == RelayMarkEditorView.taskTapName })
        let others = recognizers.filter { $0 !== task }
        #expect(!others.isEmpty)
        for other in others {
            #expect(task.delegate?.gestureRecognizer?(task, shouldRecognizeSimultaneouslyWith: other) == true)
        }
    }

    /// List markers, task checkboxes, peers' cursors and find highlights are drawn
    /// by the paper view over the paragraphs TextKit laid out. Scrolling moves the
    /// text but not that drawing, so each viewport layout pass must redraw it.
    @Test func scrollingRedrawsTheMarkersForTheParagraphsLaidOut() throws {
        let markdown = (1...120).map { "- item \($0) with some words" }.joined(separator: "\n")
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "scroll"))
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        defer { coordinator.retire(view) }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        window.addSubview(view)
        view.frame = window.bounds
        window.isHidden = false
        view.layoutIfNeeded()
        view.layer.displayIfNeeded()
        #expect(!view.layer.needsDisplay())
        view.setContentOffset(CGPoint(x: 0, y: 1500), animated: false)
        view.layoutIfNeeded()
        #expect(view.layer.needsDisplay(), "markers stay where the text was")
        // The markers drawn are those of the paragraphs now on screen.
        let geometry = try #require(RelayTextGeometry(view.textLayoutManager))
        let shown = geometry.range(try #require(view.paper.laidOut))
        let middle = CGPoint(x: 60, y: 1500 + 300 - view.textContainerInset.top)
        let offset = try #require(geometry.nearestCharacter(at: middle))
        #expect(offset > 1000 && NSLocationInRange(offset, shown))
    }

    /// The table cost gate on UIKit: typing and Return in a cell's text view and
    /// in body text, Bold and Undo, in a 1 MB paper whose 2,000-cell table is one
    /// attachment, cost at most four times their 1 KB cost plus 20 ms.
    /// Both papers are edited in alternating rounds, so a load spike on the
    /// machine falls on both, and each operation is compared by its median over
    /// the rounds, never against one fast 1 KB sample.
    @Test func tableEditsCostTheSameInASmallAndALargePaper() throws {
        func paper(bytes: Int) throws -> RelayMarkNativeDocument {
            let columns = 8, filler = String(repeating: "w", count: 40)
            let row = { (r: Int) in "| " + (0..<columns).map { "\(filler) r\(r)c\($0)." }.joined(separator: " | ") + " |" }
            let rows = max(2, min(255, bytes / row(0).utf8.count))
            var markdown = (["| " + (0..<columns).map { "h\($0)" }.joined(separator: " | ") + " |",
                "| " + Array(repeating: "---", count: columns).joined(separator: " | ") + " |"] + (0..<rows).map(row)).joined(separator: "\n")
            let paragraph = String(repeating: "Lorem ipsum dolor sit amet. ", count: 4)
            markdown += String(repeating: "\n\n" + paragraph, count: max(4, (bytes - markdown.utf8.count) / (paragraph.utf8.count + 2)))
            let document = RelayMarkNativeDocument()
            _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "cost"))
            return document
        }
        struct Paper {
            let editor: RelayMarkEditorSession
            let coordinator: RelayMarkEditorView.TextCoordinator
            let view: CollaborationTextView
            let table: RelayTableAttachment
            var samples: [String: [Duration]] = [:]
        }
        func mount(bytes: Int) throws -> Paper {
            let editor = try RelayMarkEditorSession(document: try paper(bytes: bytes), persist: { _ in })
            let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
            let view = coordinator.makeTextView(accessibilityLabel: "Cost")
            view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
            view.layoutIfNeeded()
            return Paper(editor: editor, coordinator: coordinator, view: view, table: try #require(view.paper.tables.spans.first?.table))
        }
        let clock = ContinuousClock()
        func round(_ paper: inout Paper, _ index: Int) throws {
            let (editor, coordinator, view, table) = (paper.editor, paper.coordinator, paper.view, paper.table)
            var samples = paper.samples
            func measure(_ name: String, _ work: () -> Void) {
                let start = clock.now; work(); view.layoutIfNeeded(); samples[name, default: []].append(clock.now - start)
            }
            // As the keyboard does: the delegate decides, then UIKit inserts.
            func key(_ text: String) {
                if coordinator.textView(view, shouldChangeTextInRanges: [NSValue(range: view.selectedRange)], replacementText: text) {
                    view.insertText(text)
                }
            }
            let marker = " r1c\(1 + index % 4 * 2)."
            let cell = table.grid.cellView(try #require(table.cells.firstIndex { $0.text.string.contains(marker) }))
            cell.selectedRange = NSRange(location: (cell.text as NSString).range(of: marker).location, length: 0)
            measure("cell type") { cell.insertText("x") }
            measure("cell return") { cell.insertText("\n") }
            measure("undo") { editor.undo(); coordinator.update(view) }
            let found = (String(editor.text.characters) as NSString).range(of: marker)
            measure("bold") { _ = editor.toggleMarkNatively(.bold, range: NSRange(location: found.location - 4, length: 4)); coordinator.update(view) }
            // Body edits land in the third paragraph after the table. An edit in the
            // table's neighbour rehearses the whole table (the command window holds one
            // top-level node each side); that cost is separate from this gate.
            let text = view.text as NSString
            var body = text.range(of: "Lorem")
            for _ in 0..<2 { body = text.range(of: "Lorem", range: NSRange(location: NSMaxRange(body), length: text.length - NSMaxRange(body))) }
            view.selectedRange = NSRange(location: body.location + 2 + index % 4, length: 0)
            measure("body type") { key("x") }
            measure("body return") { key("\n") }
            paper.samples = samples
        }
        var small = try mount(bytes: 1_024), large = try mount(bytes: 1_048_576)
        defer { small.coordinator.retire(small.view); large.coordinator.retire(large.view) }
        for index in 0..<7 {
            try round(&small, index)
            try round(&large, index)
        }
        for paper in [small, large] {
            #expect(paper.editor.failure == nil && paper.view.paperString == String(paper.editor.text.characters))
            #expect(paper.editor.fallbackEdits == 0, "a whole-paper path ran")
            #expect(paper.view.textLayoutManager != nil)
        }
        // Scrolling a page at a time through the table and past it.
        var scrolls: [Duration] = []
        for page in 1...8 {
            let start = clock.now
            large.view.setContentOffset(CGPoint(x: 0, y: CGFloat(page) * 600), animated: false)
            large.view.layoutIfNeeded()
            scrolls.append(clock.now - start)
        }
        print("UIKit table 1 MB scroll page median \(scrolls.sorted()[scrolls.count / 2]), live cells \(large.table.isGridLoaded ? large.table.grid.live.count : 0)")
        func median(_ samples: [Duration]) -> Duration { samples.sorted()[samples.count / 2] }
        for name in small.samples.keys.sorted() {
            let a = median(try #require(small.samples[name])), b = median(try #require(large.samples[name]))
            print("UIKit table \(name) median: 1 KB \(a), 1 MB \(b)")
            #expect(b <= a * 4 + .milliseconds(20), "\(name)")
        }
    }
}
#endif
