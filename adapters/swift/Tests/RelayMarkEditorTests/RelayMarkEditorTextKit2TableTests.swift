import Foundation
@testable import RelayMarkEditor
@testable import RelayMarkEditorCore
import Testing
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkSwift
import RelayMarkProseProjection
#if os(macOS)
import AppKit

/// Each table has a native TextKit 1 editor inside the paper's TextKit 2 attachment.
@MainActor @Suite(.serialized)
struct RelayMarkEditorTextKit2TableTests {
    @MainActor private struct Mounted {
        let document: RelayMarkNativeDocument
        let editor: RelayMarkEditorSession
        let coordinator: RelayMarkEditorView.TextCoordinator
        let view: CollaborationTextView
        let window: NSWindow
        var table: RelayTableAttachment { view.paper.tables.spans[0].table }
        var paperText: String { String(editor.text.characters) }
        func offset(_ needle: String) -> Int { (view.string as NSString).range(of: needle).location }
        func layout() {
            let manager = view.textLayoutManager!
            manager.ensureLayout(for: manager.documentRange)
            view.layoutSubtreeIfNeeded()
        }
        func retire() { coordinator.retire(view); window.contentView = nil; window.close() }
    }

    private func mount(_ markdown: String, canEdit: @escaping () -> Bool = { true }) throws -> Mounted {
        _ = NSApplication.shared
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "tables"))
        return try mount(document: document, canEdit: canEdit)
    }

    private func mount(document: RelayMarkNativeDocument, canEdit: @escaping () -> Bool = { true }) throws -> Mounted {
        _ = NSApplication.shared
        let editor = try RelayMarkEditorSession(document: document, canEdit: canEdit, persist: { _ in })
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

    private func focus(_ range: NSRange, in paper: Mounted) throws -> RelayNativeTableTextView {
        let grid = paper.table.grid
        grid.layout(width: 400)
        paper.window.displayIfNeeded()
        let native = try #require(grid.projection.nativeRange(forPaper: range))
        #expect(paper.window.makeFirstResponder(grid.textView))
        grid.textView.setSelectedRange(native)
        return grid.textView
    }

    private func cellIDs(_ document: RelayMarkNativeDocument) throws -> [String] {
        let tree = try #require(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
        func visit(_ node: [String: Any]) -> [String] {
            let children = (node["children"] as? [[String: Any]] ?? []).flatMap(visit)
            guard ["tableCell", "tableHeader"].contains(node["name"] as? String ?? ""),
                  let id = (node["attributes"] as? [String: Any])?["relaymarkId"] as? String else { return children }
            return [id] + children
        }
        return visit(tree)
    }

    @Test func aTableIsOnePreservedAttachmentWithSystemLayout() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        #expect(paper.view.textLayoutManager != nil)
        #expect(paper.view.string == "Before\n\u{FFFC}\nAfter", "The view shows the table as one character")
        #expect(paper.table.cells.map(\.text.string) == ["Name", "Note", "left cell", "right cell", "lower left", "lower right"])
        let size = paper.table.grid.layout(width: 400)
        #expect(size.width > 0 && size.height > 0)
        #expect(paper.table.grid.textView.textLayoutManager == nil, "Only the native table view uses TextKit 1")
        #expect(paper.view.textLayoutManager != nil, "Loading the table must not downgrade the paper")
        #expect(paper.table.readable.string == "Name\tNote\nleft cell\tright cell\nlower left\tlower right")
        // The paper keeps the cells' text; the view maps its offsets around the table.
        let after = paper.offset("After")
        #expect(paper.view.paper.tables.paper(after) == (paper.paperText as NSString).range(of: "After").location)
    }

    @Test func nativeTableEditabilityTracksThePaperWithoutChangingContent() throws {
        var editable = true
        let paper = try mount(table, canEdit: { editable })
        defer { paper.retire() }
        let native = paper.table.grid.textView
        #expect(native.isEditable)
        editable = false
        paper.coordinator.update(paper.view)
        #expect(!native.isEditable)
        editable = true
        paper.coordinator.update(paper.view)
        #expect(native.isEditable)
        #expect(paper.view.textLayoutManager != nil && native.textLayoutManager == nil)
    }

    @Test func nativeHitTestingMapsTheIntendedTableCellToCanonicalText() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let canonical = (paper.paperText as NSString).range(of: "lower right")
        let initial = (paper.paperText as NSString).range(of: "Name")
        let native = try focus(NSRange(location: initial.location, length: 0), in: paper)
        let range = try #require(paper.table.grid.projection.nativeRange(forPaper: canonical))
        let rect = native.firstRect(forCharacterRange: range, actualRange: nil)
        #expect(rect.width > 0 && rect.height > 0)
        let point = paper.window.convertPoint(fromScreen: NSPoint(x: rect.midX, y: rect.midY))
        let superview = try #require(paper.view.superview)
        let target = try #require(paper.view.hitTest(superview.convert(point, from: nil)))
        try #require(target === native, "The paper attachment must deliver the native text view's own mouse events")
        // AppKit owns the insertion-point hit test; the adapter only maps its
        // character offset back to the canonical document.
        let insertion = native.characterIndexForInsertion(at: native.convert(point, from: nil))
        native.setSelectedRange(NSRange(location: insertion, length: 0))
        let selected = try #require(paper.editor.nativeSelection)
        #expect(selected.location >= canonical.location && NSMaxRange(selected) <= NSMaxRange(canonical))
        #expect(paper.view.textLayoutManager != nil && native.textLayoutManager == nil)
    }

    @Test func nativeCellTypingUsesSharedDocumentHistoryAndPreservesCellIdentities() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let before = paper.paperText
        let originalIDs = try cellIDs(paper.document)
        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(paper.document.encodeUpdate())
        let insertion = (before as NSString).range(of: "left cell").location + 4
        let native = try focus(NSRange(location: insertion, length: 0), in: paper)
        native.insertText(" edited", replacementRange: native.selectedRange())
        paper.coordinator.update(paper.view)
        #expect(paper.editor.failure == nil)
        #expect(paper.paperText.contains("left edited cell"))
        #expect(native.string.contains("left edited cell"))
        #expect(try cellIDs(paper.document) == originalIDs)
        try peer.applyUpdate(paper.document.encodeUpdate())
        #expect(String(try peer.richProseProjection().text.characters) == paper.paperText)
        #expect(paper.view.textLayoutManager != nil && native.textLayoutManager == nil)

        // The changed cell length must also move the following cell's mapping.
        let nextCell = (paper.paperText as NSString).range(of: "right cell").location + 2
        _ = try focus(NSRange(location: nextCell, length: 0), in: paper)
        #expect(paper.editor.nativeSelection == NSRange(location: nextCell, length: 0))
        native.moveRight(nil)
        #expect(paper.editor.nativeSelection == NSRange(location: nextCell + 1, length: 0))
        native.moveLeft(nil)
        #expect(paper.editor.nativeSelection == NSRange(location: nextCell, length: 0))

        try #require(native.undoManager).undo()
        paper.coordinator.update(paper.view)
        #expect(paper.paperText == before, "The cell must use collaboration-owned undo")
        #expect(native.string.contains("left cell") && !native.string.contains("edited"))
        #expect(try cellIDs(paper.document) == originalIDs)
        try peer.applyUpdate(paper.document.encodeUpdate())
        #expect(String(try peer.richProseProjection().text.characters) == before)
    }

    @Test func unsupportedNativeFormattingRestoresCanonicalCellAttributes() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let canonical = (paper.paperText as NSString).range(of: "left cell")
        let native = try focus(canonical, in: paper)
        let range = try #require(paper.table.grid.projection.nativeRange(forPaper: canonical))
        let storage = try #require(native.textStorage)
        let original = storage.attributedSubstring(from: range)
        let snapshot = try paper.document.snapshot()

        // A native attribute edit does not have a text replacement to journal.
        // Unsupported styling must not survive outside the shared document.
        storage.addAttribute(.foregroundColor, value: NSColor.systemPink, range: range)
        native.didChangeText()

        #expect(storage.attributedSubstring(from: range).isEqual(to: original))
        #expect(try paper.document.snapshot() == snapshot)
        #expect(paper.view.textLayoutManager != nil && native.textLayoutManager == nil)
    }

    @Test func aPeerEditMapsTheFocusedNativeCellCaret() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let start = (paper.paperText as NSString).range(of: "left cell").location
        let native = try focus(NSRange(location: start + 3, length: 0), in: paper)
        let oldCaret = native.selectedRange()
        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(paper.document.encodeUpdate())
        let position = try #require(try peer.richProseProjection().textPosition(replacing: NSRange(location: start, length: 0)))
        try paper.editor.applyRemoteUpdate(try peer.typeText("Peer ", replacing: 0, at: 0, path: position.path).update)
        paper.coordinator.update(paper.view)
        #expect(native.string.contains("Peer left cell"))
        #expect(native.selectedRange() == NSRange(location: oldCaret.location + 5, length: 0))
        #expect(paper.window.firstResponder === native)
        #expect(paper.view.textLayoutManager != nil)
    }

    @Test func nativeCellSelectionDrivesTheSharedRowCommand() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let originalIDs = try cellIDs(paper.document)
        let start = (paper.paperText as NSString).range(of: "left cell").location
        let native = try focus(NSRange(location: start + 1, length: 0), in: paper)
        #expect(try paper.editor.prepareTableEdit().available.contains(.addRowAfter))
        paper.editor.performSelectedTableCommand(.addRowAfter)
        paper.coordinator.update(paper.view)
        #expect(paper.editor.failure == nil)
        #expect(paper.table.rows == 4)
        #expect(Set(originalIDs).isSubset(of: Set(try cellIDs(paper.document))))
        #expect(paper.table.cells.filter { !$0.text.string.isEmpty }.map(\.text.string) ==
            ["Name", "Note", "left cell", "right cell", "lower left", "lower right"])
        #expect(native.string.contains("lower right"))
        #expect(paper.view.textLayoutManager != nil && native.textLayoutManager == nil)
    }

    @Test func markedCellTextStaysPrivateUntilItsNativeCommit() async throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let before = paper.paperText
        let initial = try paper.document.encodeUpdate()
        let insertion = (before as NSString).range(of: "right cell").location
        let native = try focus(NSRange(location: insertion, length: 0), in: paper)
        native.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        native.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(native.hasMarkedText())
        #expect(paper.paperText == before)
        #expect(try paper.document.encodeUpdate() == initial)
        native.insertText("日本", replacementRange: NSRange(location: NSNotFound, length: 0))
        for _ in 0..<8 { await Task.yield() }
        try paper.editor.finishNativeComposition()
        paper.coordinator.update(paper.view)
        #expect(!native.hasMarkedText())
        #expect(paper.editor.failure == nil)
        #expect(paper.paperText.contains("日本right cell"))
        #expect(native.string.contains("日本right cell"))
        #expect(paper.view.textLayoutManager != nil)
    }

    @Test func aCanonicalMergedCellUsesApplesRowSpan() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let source = paper.paperText as NSString
        let start = source.range(of: "Name").location
        let end = source.range(of: "left cell").location
        _ = try focus(NSRange(location: start, length: end - start), in: paper)
        #expect(try paper.editor.prepareTableEdit().available.contains(.mergeCells))
        paper.editor.performSelectedTableCommand(.mergeCells)
        paper.coordinator.update(paper.view)
        #expect(paper.editor.failure == nil)
        let model = try #require(paper.table.cells.first { $0.rowSpan == 2 })
        let range = try #require(paper.table.grid.projection.nativeRange(forPaper:
            NSRange(location: paper.table.start + model.range.location, length: 0)))
        let attributes = paper.table.grid.textView.textStorage!.attributes(at: range.location, effectiveRange: nil)
        let style = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)
        let block = try #require(style.textBlocks.last as? NSTextTableBlock)
        #expect(block.rowSpan == 2 && block.columnSpan == 1)
        #expect(block.startingRow == 0 && block.startingColumn == 0)
        #expect(paper.view.textLayoutManager != nil)
    }

    @Test func nativeSelectAllMapsTheLastCellBeforeSharedTableCommands() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let originalCellTexts = paper.table.cells.map(\.text.string)
        let previousCaret = (paper.paperText as NSString).range(of: "left cell").location
        let native = try focus(NSRange(location: previousCaret, length: 0), in: paper)

        native.selectAll(nil)

        #expect(native.selectedRange() == NSRange(location: 0, length: native.string.utf16.count))
        #expect(paper.editor.nativeSelection == paper.table.canonicalRange,
            "The final native separator must not leave a stale canonical caret")
        #expect(paper.table.grid.projection.editablePaperRange(forNative: native.selectedRange()) == nil,
            "Mapping selection must not allow native replacement across cell boundaries")
        #expect(try paper.editor.prepareTableEdit().available.contains(.mergeCells))
        paper.editor.performSelectedTableCommand(.mergeCells)
        paper.coordinator.update(paper.view)
        #expect(paper.editor.failure == nil)
        #expect(paper.table.cells.count == 1)
        // The canonical engine removes rows covered entirely by the merged cell.
        #expect(paper.table.cells.first?.rowSpan == 1)
        #expect(paper.table.cells.first?.columnSpan == 2)
        for text in originalCellTexts {
            #expect(paper.table.cells.first?.text.string.contains(text) == true)
        }
        #expect(paper.view.textLayoutManager != nil && native.textLayoutManager == nil)
    }

    @Test func nativeTextReplacementCannotConsumeACellBoundary() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let before = try paper.document.snapshot()
        let first = (paper.paperText as NSString).range(of: "left cell")
        let second = (paper.paperText as NSString).range(of: "right cell")
        let native = try focus(NSRange(location: first.location, length: 0), in: paper)
        let start = try #require(paper.table.grid.projection.nativeRange(forPaper: first)).location
        let end = NSMaxRange(try #require(paper.table.grid.projection.nativeRange(forPaper: second)))
        let originalNativeText = native.string
        native.setSelectedRange(NSRange(location: start, length: end - start))
        native.insertText("Replacement", replacementRange: native.selectedRange())
        #expect(try paper.document.snapshot() == before)
        #expect(native.string == originalNativeText)
        #expect(paper.table.cells.count == 6)
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
        #expect(ignored == [NSRange(location: paper.offset("\u{FFFC}"), length: 1)], "Writing Tools excludes the preserved attachment")
    }

    @Test func findInPaperSelectsThePreservedTableForACellMatch() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        let finder = paper.view.paperFinder
        let match = (finder.string as NSString).range(of: "lower right")
        #expect(match.location != NSNotFound)
        var effective = NSRange()
        #expect(finder.contentView(at: match.location, effectiveCharacterRange: &effective) === paper.view)
        #expect(effective == paper.table.canonicalRange)
        finder.selectedRanges = [NSValue(range: match)]
        #expect(paper.view.selectedRange() == NSRange(location: paper.offset("\u{FFFC}"), length: 1))
        #expect(finder.rects(forCharacterRange: match)?.isEmpty == false)
    }

    @Test func aRemoteTableSpliceMapsPieceOffsetsOnceAfterAnEarlierTable() throws {
        let paper = try mount(table + "\n\nMiddle one\n\nMiddle two\n\nInsert here\n\nEnd")
        defer { paper.retire() }
        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(paper.document.encodeUpdate())
        var updates: [Data] = []
        let peerEditor = try RelayMarkEditorSession(document: peer, persist: { updates.append($0.update) })
        peerEditor.setNativeSelection((String(peerEditor.text.characters) as NSString).range(of: "Insert here"))
        // A peer inserts through the same portable table command as native controls.
        peerEditor.insertTable()
        #expect(peerEditor.failure == nil)
        try paper.editor.applyRemoteUpdate(try #require(updates.last))
        paper.coordinator.update(paper.view)
        paper.layout()
        let source = paper.view.string as NSString
        let attachments = (0..<source.length).filter { source.character(at: $0) == 0xFFFC }
        #expect(attachments.count == 2)
        #expect(paper.view.paper.tables.spans.map(\.view) == attachments)
        let end = source.range(of: "End").location
        #expect(paper.view.paper.tables.paper(end) == (paper.paperText as NSString).range(of: "End").location)
        paper.view.setSelectedRange(NSRange(location: end + 1, length: 0))
        paper.view.insertText("x", replacementRange: paper.view.selectedRange())
        #expect(paper.editor.failure == nil && paper.paperText.contains("Exnd"))
        #expect(paper.view.paper.tables.spans.count == 2)
        #expect(paper.table.readable.string == "Name\tNote\nleft cell\tright cell\nlower left\tlower right")
    }

    @Test(arguments: [false, true])
    func editingProsePreservesTheCompleteTableTree(mixedTable: Bool) throws {
        let paper: Mounted
        if mixedTable {
            let url = try #require(Bundle.module.url(forResource: "table-mixed-v3-draft", withExtension: "json", subdirectory: "Fixtures"))
            let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let encoded = try #require(object["update"] as? String)
            let document = RelayMarkNativeDocument()
            try document.applyUpdate(try #require(Data(base64Encoded: encoded)))
            paper = try mount(document: document)
        } else {
            paper = try mount(table)
        }
        defer { paper.retire() }
        func tableTree() throws -> Data {
            let snapshot = try #require(JSONSerialization.jsonObject(with: paper.document.snapshot()) as? [String: Any])
            let children = try #require(snapshot["children"] as? [[String: Any]])
            return try JSONSerialization.data(withJSONObject: try #require(children.first { $0["name"] as? String == "table" }), options: [.sortedKeys])
        }
        let before = try tableTree()
        paper.view.setSelectedRange(NSRange(location: paper.offset("After") + 2, length: 0))
        paper.view.insertText("x", replacementRange: paper.view.selectedRange())
        #expect(paper.paperText.contains("Afxter"))
        #expect(try tableTree() == before)
        paper.view.undoManager?.undo()
        #expect(try tableTree() == before)
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

}
#endif
