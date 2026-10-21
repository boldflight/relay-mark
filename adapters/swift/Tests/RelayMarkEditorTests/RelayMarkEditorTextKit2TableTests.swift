import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkSwift
import RelayMarkProseProjection
#if os(macOS)
import AppKit

/// A table is one attachment in the paper; its cells are standard TextKit 2 text
/// views in a grid, each editing its own cell through the paper's session.
@MainActor @Suite(.serialized)
struct RelayMarkEditorTextKit2TableTests {
    @MainActor private struct Mounted {
        let document: RelayMarkNativeDocument
        let editor: RelayMarkEditorSession
        let coordinator: RelayMarkEditorView.TextCoordinator
        let view: CollaborationTextView
        let window: NSWindow
        var geometry: RelayTextGeometry { RelayTextGeometry(view.textLayoutManager)! }
        var table: RelayTableAttachment { view.paper.tables.spans[0].table }
        var paperText: String { String(editor.text.characters) }
        func offset(_ needle: String) -> Int { (view.string as NSString).range(of: needle).location }
        /// The text view of the cell whose text starts with `prefix`.
        func cell(_ prefix: String) -> RelayTableCellTextView {
            let index = table.cells.firstIndex { $0.text.string.hasPrefix(prefix) }!
            return table.grid.cellView(index)
        }
        /// A cell's frame in the paper view.
        func frame(of prefix: String) -> CGRect { view.convert(cell(prefix).frame, from: table.grid) }
        func lineFrame(_ needle: String) -> CGRect {
            let range = (view.string as NSString).range(of: needle)
            let origin = view.textContainerOrigin
            return geometry.segmentFrames(range).reduce(CGRect.null) { $0.union($1) }.offsetBy(dx: origin.x, dy: origin.y)
        }
        func layout() {
            let manager = view.textLayoutManager!
            manager.ensureLayout(for: manager.documentRange)
            view.layoutSubtreeIfNeeded()
        }
        func retire() { coordinator.retire(view); window.contentView = nil; window.close() }
    }

    private func mount(_ markdown: String) throws -> Mounted {
        _ = NSApplication.shared
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "tables"))
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 480, height: 360),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 480, height: 360)
        window.orderFront(nil)
        let mounted = Mounted(document: document, editor: editor, coordinator: coordinator, view: view, window: window)
        mounted.layout()
        return mounted
    }

    private let table = """
    Before

    | Name | Note |
    | --- | --- |
    | left cell | right cell |
    | lower left | lower right |

    After
    """

    @Test func aTableIsOneAttachmentWithAGridOfCellViews() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        #expect(paper.view.textLayoutManager != nil)
        #expect(paper.view.string == "Before\n\u{FFFC}\nAfter", "The view shows the table as one character")
        #expect(paper.table.cells.map(\.text.string) == ["Name", "Note", "left cell", "right cell", "lower left", "lower right"])
        let left = paper.frame(of: "left"), right = paper.frame(of: "right"), lower = paper.frame(of: "lower left")
        #expect(right.minX >= left.maxX - 1 && abs(right.minY - left.minY) < 1, "Cells of one row share it")
        #expect(lower.minY >= left.maxY - 1)
        #expect(paper.lineFrame("After").minY >= paper.frame(of: "lower right").maxY - 1, "The next paragraph follows the table")
        #expect(paper.cell("left").textLayoutManager != nil, "A cell must edit on TextKit 2")
        // The paper keeps the cells' text; the view maps its offsets around the table.
        let after = paper.offset("After")
        #expect(paper.view.paper.tables.paper(after) == (paper.paperText as NSString).range(of: "After").location)
    }

    @Test func typingInACellGoesToTheSessionAndGrowsItsRow() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let before = paper.frame(of: "lower right"), afterLine = paper.lineFrame("After")
        let cell = paper.cell("right")
        cell.setSelectedRange(NSRange(location: 5, length: 0))
        for _ in 0..<3 { cell.insertText("words that wrap the cell onto another line ", replacementRange: cell.selectedRange()) }
        paper.layout()
        #expect(paper.editor.failure == nil && paper.editor.fallbackEdits == 0)
        #expect(paper.paperText.contains("rightwords that wrap"))
        #expect(paper.table.cells[3].text.string == cell.string, "The model and the cell view agree")
        #expect(paper.frame(of: "lower right").minY > before.minY, "The grown row did not push the next row down")
        #expect(paper.lineFrame("After").minY > afterLine.minY, "The paragraph after the table did not move down")
        paper.view.undoManager?.undo()
        #expect(!paper.paperText.contains("words that wrap the cell onto another line words"), "Undo goes through the paper's history")
    }

    @Test func returnInACellStacksParagraphsInsideIt() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let cell = paper.cell("right")
        cell.setSelectedRange(NSRange(location: 5, length: 0))
        cell.insertNewline(nil)
        paper.layout()
        #expect(paper.editor.failure == nil)
        #expect(paper.paperText.contains("right\n cell"), "Return did not split the cell's paragraph")
        #expect(paper.table.cells.count == 6, "Return in a cell keeps the table's cells: \(paper.table.cells.map { ($0.row, $0.column, $0.range, $0.text.string) }) \(paper.editor.nativeTableCells.map { ($0.row, $0.column, $0.range) })")
        #expect(paper.cell("right").string == "right\n cell")
        #expect(paper.view.string == "Before\n\u{FFFC}\nAfter")
    }

    @Test func tabMovesBetweenCells() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let left = paper.cell("left")
        paper.window.makeFirstResponder(left)
        left.insertTab(nil)
        #expect(paper.window.firstResponder === paper.cell("right"))
        paper.cell("right").insertBacktab(nil)
        #expect(paper.window.firstResponder === paper.cell("left"))
        #expect(paper.paperText.contains("left cell\nright cell"), "Tab must not insert a tab")
    }

    @Test func compositionInACellIsCommitted() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let cell = paper.cell("right")
        cell.setSelectedRange(NSRange(location: 5, length: 0))
        cell.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(cell.hasMarkedText() && !paper.paperText.contains("か"), "Marked text stays in the cell until committed")
        cell.insertText("家", replacementRange: cell.markedRange())
        #expect(paper.editor.failure == nil && paper.paperText.contains("right家 cell"))
    }

    @Test func peerEditsInACellKeepTheLocalCaret() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let caret = paper.offset("After") + 2
        paper.view.setSelectedRange(NSRange(location: caret, length: 0))
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(paper.document.encodeUpdate())
        let at = (paper.paperText as NSString).range(of: "left cell").location
        let path = try #require(try peer.richProseProjection().textPosition(replacing: NSRange(location: at, length: 0))).path
        try paper.editor.applyRemoteUpdate(try peer.typeText("Peer ", replacing: 0, at: 0, path: path).update)
        paper.coordinator.update(paper.view)
        paper.layout()
        #expect(paper.table.cells[2].text.string == "Peer left cell", "The cell does not show the peer's edit")
        #expect(paper.cell("Peer").string == "Peer left cell")
        #expect(paper.view.selectedRange() == NSRange(location: caret, length: 0), "The local caret moved")
        #expect(paper.view.paper.tables.paper(paper.offset("After")) == (paper.paperText as NSString).range(of: "After").location)
    }

    @Test func backspaceAfterATableSelectsItFirst() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let after = paper.offset("After")
        paper.view.setSelectedRange(NSRange(location: after, length: 0))
        paper.view.deleteBackward(nil)
        #expect(paper.view.selectedRange() == NSRange(location: after - 2, length: 1), "Backspace did not select the table")
        #expect(paper.paperText.contains("lower right\nAfter"), "Backspace must not join the paragraph into the table")
    }

    @Test func backspaceOnASelectedTableDeletesIt() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        paper.view.setSelectedRange(NSRange(location: paper.offset("After"), length: 0))
        paper.view.deleteBackward(nil)
        paper.view.deleteBackward(nil)
        #expect(paper.editor.failure == nil)
        #expect(!paper.paperText.contains("cell"), "The selected table was not deleted: \(paper.paperText)")
        #expect(paper.paperText.contains("Before") && paper.paperText.contains("After"))
        #expect(paper.view.paper.tables.spans.isEmpty && !paper.view.string.contains("\u{FFFC}"), "view: \(paper.view.string.debugDescription) spans: \(paper.view.paper.tables.spans.count) paper: \(paper.paperText.debugDescription)")
    }

    @Test func typingOverASelectedTableReplacesIt() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        paper.view.setSelectedRange(NSRange(location: paper.offset("After"), length: 0))
        paper.view.deleteBackward(nil)
        paper.view.insertText("Typed", replacementRange: paper.view.selectedRange())
        #expect(paper.editor.failure == nil)
        #expect(!paper.paperText.contains("cell") && paper.paperText.contains("Typed"), "\(paper.paperText)")
        #expect(paper.view.paper.tables.spans.isEmpty && !paper.view.string.contains("\u{FFFC}"))
    }

    @Test func anEditThePaperCannotTakeIsNotSilent() throws {
        let paper = try mount(table)
        defer { paper.retire(); RelayPaperRefusal.feedback = {} }
        var refusals = 0
        RelayPaperRefusal.feedback = { refusals += 1 }
        let besideTable = paper.view.paper.tables.spans[0].view + 1
        paper.view.setSelectedRange(NSRange(location: besideTable, length: 0))
        let before = paper.paperText
        paper.view.insertText("x", replacementRange: paper.view.selectedRange())
        #expect(paper.paperText == before)
        #expect(refusals == 1, "A refused edit gave no feedback")
    }

    @Test(arguments: ["", "x"])
    func editingASelectionAcrossATableReplacesTheWholeTable(replacement: String) throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let start = paper.offset("fore"), end = paper.offset("After") + 2
        paper.view.setSelectedRange(NSRange(location: start, length: end - start))
        if replacement.isEmpty { paper.view.deleteBackward(nil) } else { paper.view.insertText(replacement, replacementRange: paper.view.selectedRange()) }
        #expect(paper.editor.failure == nil)
        #expect(paper.paperText == "Be\(replacement)ter", "The edit across the table was refused or partial: \(paper.paperText)")
        #expect(paper.view.string == "Be\(replacement)ter" && paper.view.paper.tables.spans.isEmpty)
    }

    @Test func copyAndServicesTakeTheTableAsRows() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        paper.view.setSelectedRange(NSRange(location: 2, length: paper.offset("After") + 2 - 2))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("relay-table-services-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(paper.view.writeSelection(to: pasteboard, types: paper.view.writablePasteboardTypes))
        let written = try #require((pasteboard.readObjects(forClasses: [NSAttributedString.self]) as? [NSAttributedString])?.first)
        #expect(written.string == "fore\nName\tNote\nleft cell\tright cell\nlower left\tlower right\nAf")
        let ignored = paper.coordinator.textView(paper.view, writingToolsIgnoredRangesInEnclosingRange:
            NSRange(location: 0, length: (paper.view.string as NSString).length)).map(\.rangeValue)
        #expect(ignored == [NSRange(location: paper.offset("\u{FFFC}"), length: 1)], "Writing Tools works in each cell, not on the attachment")
    }

    @Test func findInPaperSelectsAMatchInsideACell() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let finder = paper.view.paperFinder
        let match = (finder.string as NSString).range(of: "lower right")
        #expect(match.location != NSNotFound, "The find bar searches the cells' text")
        var effective = NSRange()
        #expect(finder.contentView(at: match.location, effectiveCharacterRange: &effective) === paper.cell("lower right"))
        finder.selectedRanges = [NSValue(range: match)]
        #expect(paper.window.firstResponder === paper.cell("lower right"))
        #expect(paper.cell("lower right").selectedRange() == NSRange(location: 0, length: 11))
        #expect(finder.firstSelectedRange == match)
        #expect(finder.rects(forCharacterRange: match)?.isEmpty == false)
        let body = (finder.string as NSString).range(of: "After")
        finder.selectedRanges = [NSValue(range: body)]
        #expect(paper.view.selectedRange() == NSRange(location: paper.offset("After"), length: 5))
    }

    @Test func voiceOverReadsTheTableAsRowsAndCells() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let grid = paper.table.grid
        #expect(grid.accessibilityRole() == .table)
        #expect(grid.accessibilityRowCount() == 3 && grid.accessibilityColumnCount() == 2)
        let rows = try #require(grid.accessibilityRows() as? [NSAccessibilityElement])
        let cells = try #require(rows[1].accessibilityChildren() as? [NSAccessibilityElement])
        #expect(cells.map { $0.accessibilityValue() as? String } == ["left cell", "right cell"])
        #expect(cells[1].accessibilityColumnIndexRange() == NSRange(location: 1, length: 1))
        #expect(cells[1].accessibilityRowIndexRange() == NSRange(location: 1, length: 1))
    }

    @Test func aWidthChangeLaysTheGridOutAgain() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let wide = paper.frame(of: "right")
        paper.view.frame.size.width = 300
        paper.view.textContainer?.size = CGSize(width: 300 - 2 * paper.view.textContainerInset.width, height: .greatestFiniteMagnitude)
        paper.layout()
        let narrow = paper.frame(of: "right")
        #expect(narrow.minX < wide.minX - 20, "Columns did not follow the new width")
        #expect(paper.lineFrame("After").minY >= paper.frame(of: "lower right").maxY - 1)
    }

    @Test func agentWrittenTextInACellStaysGrey() throws {
        var text = AttributedString("x")
        let paper = try mount(table)
        defer { paper.retire() }
        text = paper.editor.text
        let source = String(text.characters) as NSString
        let range = source.range(of: "right cell")
        let bounds = try #require(Range(range, in: text))
        text[bounds][RelayMarkAIAuthoredAttribute.self] = "run-1"
        let rendered = NativeProseCodec.viewText(text, tableCells: paper.editor.nativeTableCells) { identity, start, cells in
            RelayTableAttachment(identity: identity, start: start, cells: cells)
        }
        let table = try #require(rendered.spans.first?.table)
        let cell = try #require(table.cells.first { $0.text.string == "right cell" })
        #expect(cell.text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .secondaryLabelColor)
    }

    @Test func headerCellsAreTinted() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        #expect(paper.cell("Name").drawsBackground && !paper.cell("left").drawsBackground)
    }

    private func raster(_ view: NSView) throws -> NSBitmapImageRep {
        let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        return image
    }

    private func color(_ image: NSBitmapImageRep, _ view: NSView, _ point: CGPoint) -> NSColor? {
        let scale = CGFloat(image.pixelsWide) / view.bounds.width
        let y = view.isFlipped ? point.y : view.bounds.height - point.y
        return image.colorAt(x: Int(point.x * scale), y: Int(y * scale))
    }

    @Test func calloutDrawsItsBlockOnTextKit2() throws {
        let document = RelayMarkNativeDocument()
        let url = try #require(Bundle.module.url(forResource: "rich-callout-v3-draft", withExtension: "json", subdirectory: "Fixtures"))
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let encoded = try #require(object["update"] as? String)
        try document.applyUpdate(try #require(Data(base64Encoded: encoded)))
        _ = NSApplication.shared
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Callout")
        defer { coordinator.retire(view) }
        view.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        let manager = try #require(view.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        let geometry = try #require(RelayTextGeometry(manager))
        let callout = try #require(editor.nativeCallouts.first)
        let body = geometry.segmentFrames(NSRange(location: callout.range.location, length: 1)).first ?? .zero
        let plain = geometry.segmentFrames(NSRange(location: 0, length: 1)).first ?? .zero
        #expect(body.minX > plain.minX, "Callout text is not inset inside its block")
        let image = try raster(view)
        let origin = view.textContainerOrigin
        let inside = CGPoint(x: origin.x + 400, y: origin.y + body.midY), outside = CGPoint(x: origin.x + 400, y: origin.y + plain.midY)
        #expect(color(image, view, inside) != color(image, view, outside), "The callout block is not drawn")
        #expect(view.textLayoutManager != nil)
    }
}
#endif
