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

/// Tables use a system-laid-out read-only attachment, preserving their canonical tree.
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

    private func mount(_ markdown: String) throws -> Mounted {
        _ = NSApplication.shared
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "tables"))
        return try mount(document: document)
    }

    private func mount(document: RelayMarkNativeDocument) throws -> Mounted {
        _ = NSApplication.shared
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

    @Test func aTableIsOnePreservedAttachmentWithSystemLayout() throws {
        let paper = try mount(table)
        defer { paper.retire() }
        #expect(paper.view.textLayoutManager != nil)
        #expect(paper.view.string == "Before\n\u{FFFC}\nAfter", "The view shows the table as one character")
        #expect(paper.table.cells.map(\.text.string) == ["Name", "Note", "left cell", "right cell", "lower left", "lower right"])
        let size = paper.table.grid.layout(width: 400)
        #expect(size.width > 0 && size.height > 0)
        #expect(paper.table.readable.string == "Name\tNote\nleft cell\tright cell\nlower left\tlower right")
        // The paper keeps the cells' text; the view maps its offsets around the table.
        let after = paper.offset("After")
        #expect(paper.view.paper.tables.paper(after) == (paper.paperText as NSString).range(of: "After").location)
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
        // The portable engine still accepts tables from other clients even though
        // native menus do not offer creating an uneditable empty table.
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
