import Foundation
@testable import RelayMarkEditor
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkProseProjection
import RelayMarkSwift
import Testing
#if os(macOS)
import AppKit
#endif

@MainActor @Suite("Canonical native document session")
struct RelayMarkEditorRichSessionTests {
    private func update(_ name: String = "markdown-blocks-v3-draft") throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name,
                                                 withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let encoded = try #require(fixture["update"] as? String)
        return try #require(Data(base64Encoded: encoded))
    }

    // This committed prerelease fixture is conversion input, never live admission.
    private func mediaFixtureUpdate(_ name: String) throws -> Data {
        let original = try update(name)
        guard name == "rich-video-v3-draft" else { return original }
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(original)
        let snapshot = try document.snapshot()
        let anchor = try document.anchor(path: [0, 0], index: 2, association: 0)
        #expect(throws: (any Error).self) { try document.authoredDocument() }
        let prepared = try RelayMarkNativeSnapshotImport.prepare(document: document,
            namespace: "recorded-video-fixture", expectedSnapshot: snapshot)
        // Retain the original CRDT and recorded conversion result before install.
        let recoveryEvidence = [prepared.originalState, prepared.result]
        #expect(try recoveryEvidence[0] == document.encodeUpdate())
        #expect(!recoveryEvidence[1].isEmpty)
        _ = try RelayMarkNativeSnapshotImport.install(document: document, prepared: prepared)
        #expect(try document.anchor(path: [0, 0], index: 2, association: 0) == anchor)
        _ = try document.authoredDocument()
        return try document.encodeUpdate()
    }

    private func tableUpdate() throws -> Data { try update("table-mixed-v3-draft") }

    #if os(macOS)
    /// The text view of the table cell holding a paper offset, and the offset inside that cell.
    private func cell(_ view: CollaborationTextView, at paper: Int) throws -> (view: RelayTableCellTextView, offset: Int) {
        let hit = try #require(view.paper.tables.table(holding: NSRange(location: paper, length: 0)))
        return (hit.table.grid.cellView(hit.cell), paper - hit.table.paperRange(of: hit.cell).location)
    }
    #endif

    @Test("TextKit repeated Unicode and equal replacement retain actual input identities across peer undo", arguments: [false, true])
    func explicitRepeatedNativeInput(insert: Bool) throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("🌍", namespace: "repeated-native-input"))
        try peer.applyUpdate(seed)
        var transactions: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { transactions.append($0) })
        let baseline = String(editor.text.characters)
        let range = NSRange(location: 0, length: insert ? 0 : 2)
        let candidate = AttributedString((baseline as NSString).replacingCharacters(in: range, with: "🌍"))
        editor.setNativeSelection(NSRange(location: 2, length: 0))
        editor.edit(candidate, nativeReplacement: .init(baseline: baseline, range: range, replacement: "🌍"), nativePaste: nil)
        #expect(editor.failure == nil && transactions.count == 1)
        try peer.applyUpdate(try #require(transactions.first).update)
        #expect(try document.authoredDocument() == peer.authoredDocument())
        let restored = document, reopened = editor
        let remote = try RelayMarkNativeRichTextMutation.replace(document: peer, path: [0,0], start: 0, end: 0, text: "Peer ")
        try reopened.applyRemoteUpdate(remote)
        reopened.undo()
        #expect(reopened.failure == nil)
        // Maintained Yjs on the exact seed/replacement/peer bytes restores the
        // original item before a peer anchored to the equal replacement item.
        #expect(String(reopened.text.characters) == (insert ? "Peer 🌍" : "🌍Peer "))
        try peer.applyUpdate(try #require(transactions.last).update)
        #expect(try restored.authoredDocument() == peer.authoredDocument())
        reopened.redo()
        #expect(reopened.failure == nil && String(reopened.text.characters) == (insert ? "Peer 🌍🌍" : "Peer 🌍"))
        try peer.applyUpdate(try #require(transactions.last).update)
        #expect(try restored.authoredDocument() == peer.authoredDocument())
    }

    @Test("Code block formatting stays disabled while typing and peer undo retain its authored identity")
    func codeBlockFormattingAndPeerUndo() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST:
            RelayMarkSourceCodec.parseDocument("```swift\nlet value = 1\n```", namespace: "code-command"))
        try peer.applyUpdate(seed)
        let original = try document.authoredDocument()
        var saved: [Data] = [], transactions: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update); transactions.append($0) })
        editor.setNativeSelection(NSRange(location: 0, length: 3))
        #expect(!editor.canFormatInlineSelection)
        #expect(!editor.canFormatInlineCodeSelection)
        let before = try document.encodeUpdate()
        editor.toggleInlineMark(.bold)
        #expect(try document.encodeUpdate() == before && saved.isEmpty && editor.failure == nil)
        editor.edit(AttributedString("let value = 1\n// native あ"))
        #expect(editor.failure == nil && saved.count == 1)
        let restored = try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: JSONEncoder().encode(transactions[0]))
        try peer.applyUpdate(try #require(saved.last))
        let remote = try RelayMarkNativeRichTextMutation.replace(document: peer, path: [0,0], start: 0, end: 0,
            text: "// peer\n", attributes: [:])
        try editor.applyRemoteUpdate(remote)
        editor.undo()
        #expect(editor.failure == nil && saved.count == 2)
        try peer.applyUpdate(try #require(saved.last))
        #expect(String(editor.text.characters) == "// peer\nlet value = 1\n")
        #expect(try document.authoredDocument() == peer.authoredDocument())
        let old = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        let new = try #require(JSONSerialization.jsonObject(with: document.authoredDocument()) as? [String: Any])
        let oldBlock = try #require((old["blocks"] as? [[String: Any]])?.first)
        let newBlock = try #require((new["blocks"] as? [[String: Any]])?.first)
        #expect(oldBlock["id"] as? String == newBlock["id"] as? String)
        #expect(newBlock["type"] as? String == "code")
    }

    @Test("Block style changes retain marked content and actual copy evidence without new human text")
    func blockStyleCommandEvidence() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            "Kept **🌍** text", namespace: "canonical-block-style"))
        try peer.applyUpdate(seed)
        let original = try document.authoredDocument()
        var transactions: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { transactions.append($0) })
        editor.setNativeSelection(NSRange(location: 1, length: 0))
        editor.setSelectedBlockStyle(.heading(3))
        #expect(editor.failure == nil && transactions.count == 1)
        #expect(String(editor.text.characters) == "Kept 🌍 text" && editor.nativeSelection == NSRange(location: 1, length: 0))
        try peer.applyUpdate(try #require(transactions.first).update)
        #expect(try document.authoredDocument() == peer.authoredDocument())
        editor.undo()
        #expect(editor.failure == nil && transactions.count == 2)
        try peer.applyUpdate(try #require(transactions.last).update)
        #expect(try document.authoredDocument() == original && peer.authoredDocument() == original)
    }

    @Test("Native task creation keeps adjacent prose and image while peer replay and undo converge")
    func insertTaskListAfterParagraph() throws {
        let seed = try update("rich-image-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try RelayMarkNativeDocumentProjection.project(document: document)
        var saved: [Data] = [], transactions: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update); transactions.append($0) })
        editor.setNativeSelection(NSRange(location: "Before image".utf16.count, length: 0))
        let stale = try editor.prepareTaskListInsertion()
        editor.setNativeSelection(NSRange(location: 0, length: 0))
        #expect(throws: RelayMarkEditorSession.TaskListInsertionFailure.self) {
            try editor.insertTaskList(using: stale)
        }
        #expect(saved.isEmpty)
        editor.setNativeSelection(NSRange(location: "Before image".utf16.count, length: 0))
        editor.insertTaskListAfterSelectedParagraph()
        #expect(editor.failure == nil)
        #expect(saved.count == 1)
        let taskItem = try #require(editor.nativeTaskItems.first)
        #expect(taskItem.checked == false)
         #expect(taskItem.entityID == nil)
        #expect(editor.nativeSelection?.location == taskItem.firstParagraphRange.location)
        try peer.applyUpdate(try #require(saved.last))
        let after = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(after == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        #expect(after.blocks[0] == before.blocks[0])
        #expect(after.blocks[1].type == "task_list")
        #expect(after.blocks[2] == before.blocks[1])
        editor.undo()
        #expect(editor.failure == nil && saved.count == 2)
        try peer.applyUpdate(try #require(saved.last))
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) == before)
        #expect(try RelayMarkNativeDocumentProjection.project(document: peer) == before)
    }

    @Test("A checkbox toggles after Return re-rendered just the blocks it split")
    func taskToggleAfterSplice() throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            "First paragraph.\n\n- [ ] Open task\n\nLast.", namespace: "toggle-after-splice"))
        var saved = 0
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in saved += 1 })
        let first = (String(editor.text.characters) as NSString).range(of: "First")
        #expect(editor.editStructureNatively(range: NSRange(location: NSMaxRange(first), length: 0), replacement: "\n"))
        #expect(editor.textSplice?.nodes != nil, "Return re-rendered only its blocks")
        let item = try #require(editor.nativeTaskItems.first)
        #expect(editor.toggleTaskItem(atUTF16: item.firstParagraphRange.location))
        #expect(editor.failure == nil && saved == 2 && editor.nativeTaskItems.map(\.checked) == [true])
    }

    @Test("Community v3 flat tasks use the unified native prose map and exact Yrs journal")
    func flatTaskEditing() throws {
        let seed = try update("task-list-flat-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let initial = try RelayMarkNativeDocumentProjection.project(document: document)
        var saved: [Data] = [], transactions: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update); transactions.append($0) })
        #expect(!editor.isTaskList && editor.isEditable)
        #expect(String(editor.text.characters) == "Done today\nNext")
        #expect(editor.nativeTaskItems.map(\.checked) == [true, false])
        let checkpoint = try document.encodeUpdate()
        let display = NativeProseCodec.attributed(editor.text, taskItems: editor.nativeTaskItems)
        #expect(NativeProseCodec.value(display) == editor.text)
        #expect(saved.isEmpty)
        #expect(try document.encodeUpdate() == checkpoint)
        let second = try #require(editor.nativeTaskItems.last).firstParagraphRange.location
        #expect(editor.toggleTaskItem(atUTF16: second))
        #expect(editor.failure == nil && saved.count == 1)
        try peer.applyUpdate(try #require(saved.last))
        #expect(String(editor.text.characters) == "Done today\nNext")
        #expect(editor.nativeTaskItems.map(\.checked) == [true, true])
        let after = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(after == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        #expect(after.blocks[0].id == initial.blocks[0].id)
        #expect(after.blocks[0].childBlocks.map(\.id) == initial.blocks[0].childBlocks.map(\.id))
        editor.undo()
        #expect(editor.failure == nil && saved.count == 2)
        try peer.applyUpdate(try #require(saved.last))
        #expect(editor.nativeTaskItems.map(\.checked) == [true, false])
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) ==
            RelayMarkNativeDocumentProjection.project(document: peer))
    }

    #if os(macOS)
    @Test("Native TextKit exits empty secondary list paragraphs through the regular persisted session")
    func emptySecondaryListReturn() throws {
        _ = NSApplication.shared
        let url = try #require(Bundle.module.url(forResource: "list-exit-v3", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for receipt in try #require(fixture["receipts"] as? [[String: Any]]) {
            let encoded = try #require(receipt["seed"] as? String)
            let seed = try #require(Data(base64Encoded: encoded))
            let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try document.applyUpdate(seed); try peer.applyUpdate(seed)
            let before = try document.snapshot(), projection = try document.richProseProjection()
            let path = try #require(receipt["path"] as? [Int])
            let row = try #require(projection.blockPaths.firstIndex(of: path))
            var saved: [Data] = []
            let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
            let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
            let view = coordinator.makeTextView(accessibilityLabel: "Rich list paper")
            defer { editor.invalidate(); coordinator.retire(view) }
            editor.setNativeSelection(NSRange(location: projection.blockRanges[row].location, length: 0))
            coordinator.update(view)
            view.insertNewline(nil)
            #expect(editor.failure == nil && saved.count == 1, "\(receipt["name"] ?? "")")
            #expect(String(editor.text.characters) == String(projection.text.characters))
            try peer.applyUpdate(try #require(saved.last))
            #expect(try peer.snapshot() == document.snapshot())
            editor.undo()
            try peer.applyUpdate(try #require(saved.last))
            #expect(try peer.snapshot() == before && document.snapshot() == before)
        }
    }

    @Test("One native rich task/cell editor keeps linked identity and deep checkbox/Return journals")
    func richTaskAndCellInput() throws {
        _ = NSApplication.shared
        let seed = try update("rich-containers-v3")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed); try peer.applyUpdate(seed)
        let initial = try document.snapshot()
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        #expect(editor.isEditable && editor.nativeTaskItems.count == 2 && editor.nativeTableCells.count == 5)
        let inner = try #require(editor.nativeTaskItems.first { $0.path.count > 2 })
        #expect(editor.toggleTaskItem(atUTF16: inner.firstParagraphRange.location))
        #expect(editor.failure == nil && saved.count == 1)
        try peer.applyUpdate(try #require(saved.last))
        let prose = try document.richProseProjection()
        let row = try #require(prose.blockPaths.firstIndex(of: [0, 0, 3, 0, 0, 0]))
        let range = NSRange(location: prose.blockRanges[row].location + 4, length: 0)
        let source = String(editor.text.characters)
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Rich task and cell paper")
        defer { editor.invalidate(); coordinator.retire(view) }
        editor.setNativeSelection(range)
        coordinator.update(view)
        let (cell, inside) = try self.cell(view, at: range.location)
        #expect(cell.selectedRange() == NSRange(location: inside, length: 0), "The session's selection reaches the cell")
        cell.insertNewline(nil)
        #expect(editor.failure == nil && saved.count == 2)
        #expect(String(editor.text.characters) == (source as NSString).replacingCharacters(in: range, with: "\n"))
        #expect(editor.nativeTaskItems.allSatisfy { $0.checked })
        try peer.applyUpdate(try #require(saved.last))
        #expect(try peer.snapshot() == document.snapshot())
        editor.undo()
        try peer.applyUpdate(try #require(saved.last))
        editor.undo()
        try peer.applyUpdate(try #require(saved.last))
        #expect(try peer.snapshot() == initial && document.snapshot() == initial)
    }
    #endif

    #if os(macOS)
    @Test("One native rich quote editor keeps nested content while TextKit Return persists and replays")
    func richQuotedHeadingReturn() throws {
        _ = NSApplication.shared
        let seed = try update("rich-quote-v3")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed); try peer.applyUpdate(seed)
        let snapshot = try document.snapshot()
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        #expect(editor.isEditable && editor.nativeMediaAtoms.count == 1 && editor.nativeCallouts.count == 1)
        let source = String(editor.text.characters), range = NSRange(location: 6, length: 0)
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Rich quote paper")
        defer { editor.invalidate(); coordinator.retire(view) }
        editor.setNativeSelection(range)
        coordinator.update(view)
        view.insertNewline(nil)
        #expect(editor.failure == nil && saved.count == 1)
        #expect(String(editor.text.characters) == (source as NSString).replacingCharacters(in: range, with: "\n"))
        #expect(editor.nativeMediaAtoms.count == 1 && editor.nativeCallouts.count == 1)
        try peer.applyUpdate(try #require(saved.last))
        #expect(try peer.snapshot() == document.snapshot())
        editor.undo()
        try peer.applyUpdate(try #require(saved.last))
        #expect(try peer.snapshot() == snapshot && document.snapshot() == snapshot)
    }
    #endif

    #if os(macOS)
    @Test("Native RTF clipboard paste retains inline styles, paragraphs and selection scope",
          arguments: [(0, false), (5, false), (0, true), (5, true)])
    func nativeRichClipboardPaste(_ parameters: (Int, Bool)) throws {
        let (selectedLength, multiline) = parameters
        _ = NSApplication.shared
        let seed = try update("inline-offered-marks-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed); try peer.applyUpdate(seed)
        let before = try RelayMarkNativeDocumentProjection.project(document: document)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let baseline = String(editor.text.characters)
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Rich clipboard paper")
        defer { editor.invalidate(); coordinator.retire(view) }
        let firstText = multiline ? "bold\n\n" : "bold "
        let pasted = NSMutableAttributedString(string: firstText, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 15)])
        pasted.append(NSAttributedString(string: multiline ? "italic\n" : "italic", attributes: [
            .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 15), toHaveTrait: .italicFontMask),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .link: URL(string: "https://example.com/paste")!]))
        let encoded = try pasted.data(from: NSRange(location: 0, length: pasted.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let board = NSPasteboard.general
        let previous = board.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
        defer {
            board.clearContents()
            let items = previous.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { board.writeObjects(items) }
        }
        board.clearContents()
        #expect(board.setData(encoded, forType: .rtf))
        let selection = NSRange(location: 8, length: selectedLength)
        view.setSelectedRange(selection)
        view.paste(nil)
        #expect(editor.failure == nil && saved.count == 1)
        #expect(view.string == (baseline as NSString).replacingCharacters(in: selection, with: pasted.string))
        let lower = editor.text.characters.index(editor.text.startIndex, offsetBy: 8)
        let boldEnd = editor.text.characters.index(lower, offsetBy: 4)
        let middle = editor.text.characters.index(lower, offsetBy: firstText.count)
        let end = editor.text.characters.index(middle, offsetBy: 6)
        #expect(editor.text[lower..<boldEnd].inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        #expect(editor.text[middle..<end].inlinePresentationIntent?.contains(.emphasized) == true)
        #expect(editor.text[middle..<end][RelayMarkOfferedMarksAttribute.self]?.contains(.underline) == true)
        #expect(editor.text[middle..<end].link == URL(string: "https://example.com/paste"))
        try peer.applyUpdate(try #require(saved.last))
        let after = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(after == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        let beforeIDs = before.blocks.map(\.id)
        #expect(after.blocks.filter { beforeIDs.contains($0.id) }.map(\.id) == beforeIDs)
        #expect(after.blocks.count == before.blocks.count + (multiline ? 3 : 0))
        editor.undo()
        try peer.applyUpdate(try #require(saved.last))
        #expect(try RelayMarkNativeDocumentProjection.project(document: peer) == before)
    }

    @Test("Native mixed-run insertion preserves styles, including paste with identical characters", arguments: [false, true])
    func mixedRunPaste(_ identicalCharacters: Bool) throws {
        let seed = try update("inline-offered-marks-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed); try peer.applyUpdate(seed)
        let before = try RelayMarkNativeDocumentProjection.project(document: document)
        var attempts: [Data] = []
        var failSave = true
        struct SaveFailure: Error {}
        let editor = try RelayMarkEditorSession(document: document, persist: {
                attempts.append($0.update)
                if failSave { throw SaveFailure() }
            })
        let range = NSRange(location: 8, length: 5)
        var candidate = editor.text
        let lower = candidate.characters.index(candidate.startIndex, offsetBy: range.location)
        let upper = candidate.characters.index(lower, offsetBy: range.length)
        let original = String(candidate[lower..<upper].characters)
        let insertedText = identicalCharacters ? original : "bold 👩🏽‍💻 italic"
        var inserted = AttributedString(insertedText)
        inserted.presentationIntent = candidate.runs.first?.presentationIntent
        let boundary = inserted.characters.index(inserted.startIndex, offsetBy: 2)
        inserted[inserted.startIndex..<boundary].inlinePresentationIntent = .stronglyEmphasized
        inserted[boundary..<inserted.endIndex].inlinePresentationIntent = .emphasized
        candidate.replaceSubrange(lower..<upper, with: inserted)
        editor.edit(candidate)
        #expect(attempts.count == 1 && editor.failure != nil)
        failSave = false
        editor.retryPersistence()
        #expect(editor.failure == nil && attempts.count == 2 && attempts[0] == attempts[1])
        try peer.applyUpdate(try #require(attempts.last))
        let after = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(after == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        #expect(after.blocks.map(\.id) == before.blocks.map(\.id))
        #expect(String(editor.text.characters) == String(candidate.characters))
        #expect(editor.text == (try document.richProseProjection().text))
        editor.undo()
        try peer.applyUpdate(try #require(attempts.last))
        #expect(try RelayMarkNativeDocumentProjection.project(document: peer) == before)
        editor.redo()
        try peer.applyUpdate(try #require(attempts.last))
        #expect(try RelayMarkNativeDocumentProjection.project(document: peer) == after)
    }

    @Test("Native typing uses explicit marks at boundaries and across selected formatting")
    func explicitTypingAcrossMarks() throws {
        let seed = try update("inline-offered-marks-v3-draft")
        for range in [NSRange(location: 8, length: 5),
                      NSRange(location: 0, length: 0), NSRange(location: 10, length: 0)] {
            let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try document.applyUpdate(seed); try peer.applyUpdate(seed)
            let before = try RelayMarkNativeDocumentProjection.project(document: document)
            var saved: [Data] = []
            let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
            let baseline = String(editor.text.characters)
            #expect(editor.acceptsNativeReplacement(baseline: baseline, range: range, replacement: "typed"))
            var candidate = editor.text
            let lower = candidate.characters.index(candidate.startIndex, offsetBy: range.location)
            let upper = candidate.characters.index(lower, offsetBy: range.length)
            var inserted = AttributedString("typed")
            inserted.presentationIntent = candidate.runs.first?.presentationIntent
            inserted[RelayMarkOfferedMarksAttribute.self] = [.highlight]
            candidate.replaceSubrange(lower..<upper, with: inserted)
            editor.edit(candidate)
            #expect(editor.failure == nil && saved.count == 1)
            #expect(String(editor.text.characters) == (baseline as NSString).replacingCharacters(in: range, with: "typed"))
            try peer.applyUpdate(try #require(saved.last))
            let after = try RelayMarkNativeDocumentProjection.project(document: document)
            #expect(after == (try RelayMarkNativeDocumentProjection.project(document: peer)))
            #expect(after.blocks.map(\.id) == before.blocks.map(\.id))
            editor.undo()
            try peer.applyUpdate(try #require(saved.last))
            #expect(try RelayMarkNativeDocumentProjection.project(document: peer) == before)
            editor.redo()
            try peer.applyUpdate(try #require(saved.last))
            #expect(try RelayMarkNativeDocumentProjection.project(document: peer) == after)
        }
    }

    @Test("Mounted native replacement crosses formatting runs without dropping surviving marks", arguments: ["", "typed"])
    func mountedCrossMarkReplacement(_ replacement: String) throws {
        _ = NSApplication.shared
        let seed = try update("inline-offered-marks-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try RelayMarkNativeDocumentProjection.project(document: document)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let baseline = String(editor.text.characters)
        // Select across underline, unmarked spacing, and highlight in one XmlText.
        let selection = NSRange(location: 8, length: 5)
        #expect(editor.acceptsNativeReplacement(baseline: baseline,
            range: selection, replacement: replacement))
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Formatted paper")
        defer { editor.invalidate(); coordinator.retire(view) }
        view.setSelectedRange(selection)
        view.insertText(replacement, replacementRange: selection)
        #expect(editor.failure == nil && saved.count == 1)
        #expect(view.string == (baseline as NSString).replacingCharacters(in: selection, with: replacement))
        try peer.applyUpdate(try #require(saved.last))
        let after = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(after == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        #expect(after.blocks.map(\.id) == before.blocks.map(\.id))
        #expect(editor.text == (try document.richProseProjection().text))
        editor.undo()
        #expect(editor.failure == nil && saved.count == 2)
        try peer.applyUpdate(try #require(saved.last))
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) == before)
        #expect(try RelayMarkNativeDocumentProjection.project(document: peer) == before)
        editor.redo()
        #expect(editor.failure == nil && saved.count == 3)
        try peer.applyUpdate(try #require(saved.last))
        #expect(try RelayMarkNativeDocumentProjection.project(document: peer) == after)
    }

    @Test("The unified TextKit view edits identified v3 task text")
    func mountedFlatTaskText() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let seed = try update("task-list-flat-v3-draft")
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Task paper")
        defer { editor.invalidate(); coordinator.retire(view) }
        #expect(view.string == "Done today\nNext")
        let caret = NSRange(location: "Done".utf16.count, length: 0)
        view.setSelectedRange(caret)
        view.insertText(" again", replacementRange: caret)
        #expect(editor.failure == nil && saved.count == 1)
        try peer.applyUpdate(try #require(saved.last))
        #expect(view.string == "Done again today\nNext")
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) ==
            RelayMarkNativeDocumentProjection.project(document: peer))
    }
    @Test("Mounted v3 paragraph Return splits identified prose beside media and replays to a peer")
    func v3TopLevelParagraphReturn() throws {
        _ = NSApplication.shared
        let seed = try update("rich-image-v3-draft")
        for offset in [6, 12] {
            let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try document.applyUpdate(seed)
            try peer.applyUpdate(seed)
            let before = try RelayMarkNativeDocumentProjection.project(document: document)
            var saved: [Data] = []
            let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
            let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
            let view = coordinator.makeTextView(accessibilityLabel: "Paper")
            defer { coordinator.retire(view) }
            let caret = NSRange(location: offset, length: 0)
            #expect(editor.acceptsNativeReplacement(baseline: String(editor.text.characters),
                range: caret, replacement: "\n"))
            view.setSelectedRange(caret)
            view.insertText("\n", replacementRange: caret)
            #expect(editor.failure == nil && saved.count == 1,
                    "\(editor.failure ?? "Paragraph Return was not saved")")
            try peer.applyUpdate(try #require(saved.last))
            let after = try RelayMarkNativeDocumentProjection.project(document: document)
            #expect(after == (try RelayMarkNativeDocumentProjection.project(document: peer)))
            #expect(after.blocks[0].id == before.blocks[0].id)
            #expect(after.blocks[1].type == "paragraph" && after.blocks[1].id != before.blocks[0].id)
            #expect(after.blocks[2] == before.blocks[1])
            editor.undo()
            try peer.applyUpdate(try #require(saved.last))
            #expect(before == (try RelayMarkNativeDocumentProjection.project(document: document)))
            #expect(before == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        }
    }

    @Test("Native block reference remains one accessible unit while adjacent prose edits")
    func v3BlockEntityReferencePresentation() throws {
        _ = NSApplication.shared
        let seed = try update("entity-reference-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try RelayMarkNativeDocumentProjection.project(document: document)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        #expect(editor.isEditable)
        let atom = try #require(editor.nativeEntityReferenceAtoms.first)
        #expect(atom.label == "Ada Lovelace" && atom.path == [1])
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        defer { coordinator.retire(view) }
        #expect(view.attributedString().attribute(.attachment, at: atom.range.location,
            effectiveRange: nil) != nil)
        let caret = NSRange(location: 6, length: 0)
        view.setSelectedRange(caret)
        view.insertText("!", replacementRange: caret)
        #expect(editor.failure == nil && saved.count == 1)
        try peer.applyUpdate(try #require(saved.last))
        let after = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(after == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        #expect(after.blocks[1] == before.blocks[1])
    }
    #endif

    @Test("An existing v3 callout appearance is one guarded Yrs update with peer replay and undo")
    func calloutAppearanceCommand() throws {
        let seed = try update("rich-callout-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        var saved: [Data] = [], transactions: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update); transactions.append($0) })
        let original = try #require(editor.nativeCallouts.first)
        editor.setNativeSelection(NSRange(location: original.range.location + 1, length: 0))
        let review = try editor.prepareCalloutAppearanceEdit()
        #expect(review.calloutID == original.id)
        #expect(review.tone == "warning" && review.emphasis == "strong")
        #expect(throws: RelayMarkEditorSession.CalloutAppearanceFailure.self) {
            try editor.applyCalloutAppearance(tone: "arbitrary", emphasis: "soft", review: review)
        }
        #expect(saved.isEmpty)
        try editor.applyCalloutAppearance(tone: "success", emphasis: "soft", review: review)
        #expect(editor.failure == nil && saved.count == 1)
        try peer.applyUpdate(try #require(saved.last))
        let changed = try #require(editor.nativeCallouts.first)
        #expect(changed.id == original.id && changed.tone == "success" && changed.emphasis == "soft")
        #expect(String(editor.text.characters) == String((try peer.richProseProjection()).text.characters))
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) ==
                RelayMarkNativeDocumentProjection.project(document: peer))
        #expect(throws: RelayMarkEditorSession.CalloutAppearanceFailure.self) {
            try editor.applyCalloutAppearance(tone: "error", emphasis: "strong", review: review)
        }
        editor.undo()
        #expect(editor.failure == nil && saved.count == 2)
        try peer.applyUpdate(try #require(saved.last))
        #expect(editor.nativeCallouts.first == original)
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) ==
                RelayMarkNativeDocumentProjection.project(document: peer))
    }

    @Test("Add title to a callout with a nested list preserves content and exact command evidence on retry")
    func calloutAddTitleCommand() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            "Before\n\n@Callout(tone: \"info\", emphasis: \"soft\") {\n- Nested **body**\n}", namespace: "canonical-title-retry"))
        try peer.applyUpdate(seed)
        var attempts: [Data] = [], transactions: [RelayMarkLocalTransaction] = []
        var fail = true
        let editor = try RelayMarkEditorSession(document: document, persist: {
                attempts.append($0.update); transactions.append($0)
                if fail { throw CancellationError() }
            })
        let before = try RelayMarkNativeDocumentProjection.project(document: document)
        let untitled = try #require(editor.nativeCallouts.first)
        #expect(untitled.titleRange == nil)
        editor.setNativeSelection(NSRange(location: untitled.range.location + 1, length: 0))
        let stale = try editor.prepareCalloutTitleInsertion()
        #expect(stale.calloutID == untitled.id)
        editor.setNativeSelection(NSRange(location: 0, length: 0))
        #expect(throws: RelayMarkEditorSession.CalloutTitleFailure.self) {
            try editor.addCalloutTitle(using: stale)
        }
        #expect(attempts.isEmpty)
        editor.setNativeSelection(NSRange(location: untitled.range.location + 1, length: 0))
        let command = try editor.prepareCalloutTitleInsertion()
        try editor.addCalloutTitle(using: command)
        #expect(editor.hasUnpersistedTransaction && attempts.count == 1)

        #expect(throws: RelayMarkEditorSession.CalloutTitleFailure.self) {
            try editor.addCalloutTitle(using: command)
        }
        editor.addSelectedCalloutTitle()
        #expect(editor.failure != nil)
        let title = try #require(editor.nativeCallouts.first?.titleRange)
        #expect(title.length == 5 && editor.nativeSelection == title)
        #expect((String(editor.text.characters) as NSString).substring(with: title) == "Title")
        let after = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(after.blocks.map(\.id) == before.blocks.map(\.id))
        #expect(after.blocks[1].childBlocks[1] == before.blocks[1].childBlocks[0])
        #expect(after.blocks[1].childBlocks[0].plainText == "Title")
        fail = false
        editor.retryPersistence()
        #expect(editor.failure == nil && !editor.hasUnpersistedTransaction)
        #expect(attempts.count == 2 && attempts[0] == attempts[1] && transactions[0] == transactions[1])
        try peer.applyUpdate(try #require(attempts.last))
        #expect(after == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        editor.undo()
        try peer.applyUpdate(try #require(attempts.last))
        #expect(before == (try RelayMarkNativeDocumentProjection.project(document: document)))
        #expect(before == (try RelayMarkNativeDocumentProjection.project(document: peer)))
    }

    @Test("Browser empty callout title types without replacing its stable ID or body")
    func emptyCalloutTitleTyping() throws {
        let url = try #require(Bundle.module.url(forResource: "callout-add-title-v3-draft",
                                                 withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let encoded = try #require(fixture["empty_title_update"] as? String)
        let seed = try #require(Data(base64Encoded: encoded))
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let before = try RelayMarkNativeDocumentProjection.project(document: document)
        let title = try #require(editor.nativeCallouts.first?.titleRange)
        #expect(title.length == 0)
        editor.setNativeSelection(title)
        let baseline = String(editor.text.characters)
        #expect(editor.acceptsNativeReplacement(baseline: baseline, range: title, replacement: "Named"))
        #if os(macOS)
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Callout")
        defer { coordinator.retire(view) }
        #expect(view.paper.emptyBlocks.contains { $0.offset == title.location })
        view.setSelectedRange(title)
        view.insertText("Named", replacementRange: title)
        #expect(editor.failure == nil && saved.count == 1, "\(editor.failure ?? "No saved title edit")")
        try peer.applyUpdate(try #require(saved.last))
        let after = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(after == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        #expect(after.blocks[1].childBlocks[0].plainText == "Named")
        #expect(after.blocks[1].childBlocks.map(\.id) == before.blocks[1].childBlocks.map(\.id))
        #expect(after.blocks[1].childBlocks[1] == before.blocks[1].childBlocks[1])
        #endif
    }

    #if os(macOS)
    @Test("Clearing Add title's selected default remains editable with one stable title ID")
    func clearAddedCalloutTitleAndRetype() throws {
        _ = NSApplication.shared
        let seed = try update("callout-add-title-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let callout = try #require(editor.nativeCallouts.first)
        editor.setNativeSelection(NSRange(location: callout.range.location + 1, length: 0))
        try editor.addCalloutTitle(using: editor.prepareCalloutTitleInsertion())
        try peer.applyUpdate(try #require(saved.last))
        let inserted = try RelayMarkNativeDocumentProjection.project(document: document)
        let titleID = inserted.blocks[1].childBlocks[0].id
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Callout")
        defer { coordinator.retire(view) }
        let title = try #require(editor.nativeCallouts.first?.titleRange)
        coordinator.update(view)
        view.setSelectedRange(title)
        view.insertText("", replacementRange: title)
        #expect(editor.failure == nil && saved.count == 2, "\(editor.failure ?? "No title clear saved")")
        try peer.applyUpdate(try #require(saved.last))
        let empty = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(empty.blocks[1].childBlocks[0].id == titleID)
        #expect(empty.blocks[1].childBlocks[0].plainText == "")
        let caret = try #require(editor.nativeCallouts.first?.titleRange)
        coordinator.update(view)
        view.setSelectedRange(caret)
        view.insertText("Custom", replacementRange: caret)
        #expect(editor.failure == nil && saved.count == 3, "\(editor.failure ?? "No replacement title saved")")
        try peer.applyUpdate(try #require(saved.last))
        let after = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(after == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        #expect(after.blocks[1].childBlocks[0].id == titleID)
        #expect(after.blocks[1].childBlocks[0].plainText == "Custom")
        #expect(after.blocks[1].childBlocks[1] == inserted.blocks[1].childBlocks[1])
    }

    @Test("Browser-shaped interior Return and empty-item exit survive native retry, peer replay and undo")
    func v3ListInteriorAndExitReturn() throws {
        _ = NSApplication.shared
        let url = try #require(Bundle.module.url(forResource: "list-operations-v3",
                                                 withExtension: "json", subdirectory: "Fixtures"))
        let fixtures = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for (name, path, relativeOffset, resultingPath, isExit) in [
            ("interior_flat_ordered", [0, 1, 0], 3, [0, 2, 0], false),
            ("interior_nested_ordered", [0, 0, 1, 0, 0], 3, [0, 0, 1, 1, 0], false),
            ("exit_flat_ordered", [0, 1, 0], 0, [1], true),
            ("exit_flat_bullet", [0, 1, 0], 0, [1], true),
            ("exit_nested_ordered", [0, 0, 1, 0, 0], 0, [0, 1, 0], true),
            ("exit_nested_bullet", [0, 0, 1, 0, 0], 0, [0, 1, 0], true)
        ] {
            let fixture = try #require(fixtures[name] as? [String: Any])
            let encoded = try #require(fixture["seed"] as? String)
            let seed = try #require(Data(base64Encoded: encoded))
            let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try document.applyUpdate(seed)
            try peer.applyUpdate(seed)
            let before = try RelayMarkNativeDocumentProjection.project(document: document)
            let projection = try document.richProseProjection()
            let row = try #require(projection.blockPaths.firstIndex(of: path))
            let offset = projection.blockRanges[row].location + relativeOffset
            var fail = true, attempts: [Data] = []
            let editor = try RelayMarkEditorSession(document: document, persist: {
                    attempts.append($0.update)
                    if fail { throw CancellationError() }
                })
            let baseline = String(editor.text.characters)
            #expect(editor.acceptsNativeReplacement(baseline: baseline,
                range: NSRange(location: offset, length: 0), replacement: "\n"), "\(name)")
            let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
            let view = coordinator.makeTextView(accessibilityLabel: "List")
            defer { coordinator.retire(view) }
            let caret = NSRange(location: offset, length: 0)
            view.setSelectedRange(caret)
            view.insertText("\n", replacementRange: caret)
            #expect(editor.hasUnpersistedTransaction && attempts.count == 1,
                    "\(name): \(editor.failure ?? "Return was not saved")")
            let after = try RelayMarkNativeDocumentProjection.project(document: document)
            let afterProjection = try document.richProseProjection()
            let newRow = try #require(afterProjection.blockPaths.firstIndex(of: resultingPath))
            #expect(String(editor.text.characters) ==
                    (isExit ? baseline : (baseline as NSString).replacingCharacters(
                        in: NSRange(location: offset, length: 0), with: "\n")), "\(name)")
            // An exit leaves the caret in the lifted empty item, as the browser keymap does.
            #expect(editor.nativeSelection == NSRange(location: offset + (isExit ? 0 : 1), length: 0), "\(name)")
            #expect(afterProjection.blockRanges[newRow].length == (isExit ? 0 :
                    6), "\(name)")
            #expect(after.blocks[0].id == before.blocks[0].id, "\(name)")
            fail = false
            editor.retryPersistence()
            #expect(editor.failure == nil && attempts.count == 2 && attempts[0] == attempts[1], "\(name)")
            try peer.applyUpdate(try #require(attempts.last))
            #expect(after == (try RelayMarkNativeDocumentProjection.project(document: peer)), "\(name)")
            editor.undo()
            try peer.applyUpdate(try #require(attempts.last))
            #expect(before == (try RelayMarkNativeDocumentProjection.project(document: document)), "\(name)")
            #expect(before == (try RelayMarkNativeDocumentProjection.project(document: peer)), "\(name)")
        }
    }

    @Test("Mounted v3 quote Return appends, exits and splits without losing authored IDs")
    func v3QuoteReturn() throws {
        _ = NSApplication.shared
        let seed = try update()
        for operation in ["end-and-exit", "interior"] {
            let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try document.applyUpdate(seed)
            try peer.applyUpdate(seed)
            let before = try RelayMarkNativeDocumentProjection.project(document: document)
            var saved: [Data] = []
            let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
            let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
            let view = coordinator.makeTextView(accessibilityLabel: "Quote")
            defer { coordinator.retire(view) }
            let projection = try document.richProseProjection()
            let path = operation == "interior" ? [2, 0] : [2, 1]
            let row = try #require(projection.blockPaths.firstIndex(of: path))
            let offset = operation == "interior"
                ? projection.blockRanges[row].location + 5 : NSMaxRange(projection.blockRanges[row])
            let caret = NSRange(location: offset, length: 0)
            #expect(editor.acceptsNativeReplacement(baseline: String(editor.text.characters),
                range: caret, replacement: "\n"))
            view.setSelectedRange(caret)
            view.insertText("\n", replacementRange: caret)
            #expect(editor.failure == nil && saved.count == 1, "\(operation): \(editor.failure ?? "No quote update")")
            try peer.applyUpdate(try #require(saved.last))
            let first = try RelayMarkNativeDocumentProjection.project(document: document)
            #expect(first == (try RelayMarkNativeDocumentProjection.project(document: peer)))
            #expect(first.blocks[2].id == before.blocks[2].id)
            #expect(first.blocks[2].childBlocks.count == 3)
            if operation == "interior" {
                #expect(first.blocks[2].childBlocks.map(\.plainText) == ["First", " quote", "Second quote"])
                #expect(first.blocks[2].childBlocks[0].id == before.blocks[2].childBlocks[0].id)
                #expect(first.blocks[2].childBlocks[2].id == before.blocks[2].childBlocks[1].id)
            } else {
                #expect(first.blocks[2].childBlocks.map(\.plainText) == ["First quote", "Second quote", ""])
                let emptyID = first.blocks[2].childBlocks[2].id
                coordinator.update(view)
                let next = try document.richProseProjection()
                let emptyRow = try #require(next.blockPaths.firstIndex(of: [2, 2]))
                let emptyCaret = NSRange(location: next.blockRanges[emptyRow].location, length: 0)
                #expect(editor.acceptsNativeReplacement(baseline: String(editor.text.characters),
                    range: emptyCaret, replacement: "\n"))
                view.setSelectedRange(emptyCaret)
                view.insertText("\n", replacementRange: emptyCaret)
                #expect(editor.failure == nil && saved.count == 2)
                try peer.applyUpdate(try #require(saved.last))
                let exited = try RelayMarkNativeDocumentProjection.project(document: document)
                #expect(exited == (try RelayMarkNativeDocumentProjection.project(document: peer)))
                #expect(exited.blocks[2] == before.blocks[2])
                #expect(exited.blocks[3].id == emptyID && exited.blocks[3].type == "paragraph")
                editor.undo()
                try peer.applyUpdate(try #require(saved.last))
                #expect(first == (try RelayMarkNativeDocumentProjection.project(document: document)))
            }
            editor.undo()
            try peer.applyUpdate(try #require(saved.last))
            #expect(before == (try RelayMarkNativeDocumentProjection.project(document: document)))
            #expect(before == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        }
    }
    #endif

    private func replacingFirstWord(in editor: RelayMarkEditorSession) -> AttributedString {
        var candidate = editor.text
        let end = candidate.characters.index(candidate.startIndex, offsetBy: 6)
        var replacement = AttributedString("After")
        replacement.presentationIntent = candidate.runs.first?.presentationIntent
        candidate.replaceSubrange(candidate.startIndex..<end, with: replacement)
        return candidate
    }

    @Test("The existing native session edits and persists one v3 text leaf over Yrs")
    func textEditUndoAndPeerReplay() throws {
        let seed = try update()
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })

        editor.edit(replacingFirstWord(in: editor))
        #expect(editor.failure == nil, "\(editor.failure ?? "unknown")")
        #expect(saved.count == 1)
        try peer.applyUpdate(try #require(saved.last))
        #expect(try RelayMarkNativeDocumentProjection.project(document: peer) ==
                RelayMarkNativeDocumentProjection.project(document: document))

        editor.undo()
        #expect(editor.failure == nil)
        #expect(saved.count == 2)
        try peer.applyUpdate(try #require(saved.last))
        #expect(String(editor.text.characters).contains("Before 🌍"))
        #expect(try RelayMarkNativeDocumentProjection.project(document: peer) ==
                RelayMarkNativeDocumentProjection.project(document: document))

        let remote = try RelayMarkNativeRichTextMutation.replace(
            document: peer, path: [0, 0], start: 0, end: 6, text: "Remote")
        try editor.applyRemoteUpdate(remote)
        #expect(editor.failure == nil)
        #expect(String(editor.text.characters).contains("Remote 🌍"))
    }

    @Test("A v3 inline mark is one Yrs update and cannot span structural blocks")
    func formattingAndStructuralFence() throws {
        let seed = try update()
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        editor.setNativeSelection(NSRange(location: 0, length: 6))
        #expect(editor.canFormatInlineSelection)
        editor.toggleInlineMark(.bold)
        #expect(editor.failure == nil && saved.count == 1)
        try peer.applyUpdate(try #require(saved.last))
        #expect(try RelayMarkNativeDocumentProjection.project(document: peer) ==
                RelayMarkNativeDocumentProjection.project(document: document))
        #expect(editor.text.runs.first?.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)

        editor.setNativeSelection(NSRange(location: 0, length: String(editor.text.characters).utf16.count))
        #expect(!editor.canFormatInlineSelection)
        editor.toggleInlineMark(.italic)
        #expect(saved.count == 1)
    }

    @Test("A v3 link round-trips through normalized Yjs metadata")
    func linkRoundTrip() throws {
        let seed = try update()
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        editor.setNativeSelection(NSRange(location: 0, length: 6))
        let first = try editor.prepareLinkEdit()
        try editor.applyLink("relay:entity/751dd285-78bf-4ae1-bcd6-bf4772400be8", review: first)
        #expect(editor.failure == nil && saved.count == 1)
        try peer.applyUpdate(try #require(saved.last))
        #expect(try RelayMarkNativeDocumentProjection.project(document: peer) ==
                RelayMarkNativeDocumentProjection.project(document: document))
        let second = try editor.prepareLinkEdit()
        #expect(second.hasLink)
        try editor.applyLink(nil, review: second)
        #expect(editor.failure == nil && saved.count == 2)
        try peer.applyUpdate(try #require(saved.last))
        #expect(try RelayMarkNativeDocumentProjection.project(document: peer) ==
                RelayMarkNativeDocumentProjection.project(document: document))
    }

    @Test("The existing native session edits a spanned table cell without rebuilding the grid")
    func tableCellEditAndPeerReplay() throws {
        let seed = try tableUpdate()
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let cells = editor.nativeTableCells
        #expect(cells.first?.columnSpan == 2)
        #expect(cells.filter { $0.row == 1 }.map(\.column) == [0, 1])
        let rendered = NativeProseCodec.viewText(editor.text, tableCells: cells) { identity, start, cells in
            RelayTableAttachment(identity: identity, start: start, cells: cells)
        }
        let table = try #require(rendered.spans.first?.table)
        let header = try #require(table.cells.first)
        #expect(header.columnSpan == 2 && header.row == 0 && header.column == 0 && header.header)
        #expect(header.columnWidths == [120, 180])
        let body = try #require(table.cells.first { $0.row == 1 && $0.column == 0 })
        #expect(body.columnWidths == [120] && !body.header)
        #expect(table.canonicalRange == NSRange(location: try #require(cells.first).range.location,
            length: NSMaxRange(try #require(cells.last).range) - (try #require(cells.first).range.location)))
        #if os(macOS)
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Shared paper")
        defer { coordinator.retire(view) }
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let mounted = try #require(view.paper.tables.spans.first?.table)
        #expect(mounted.cells.first?.columnSpan == 2)
        _ = mounted.grid.layout(width: 600)
        let aliceView = mounted.grid.cellView(try #require(mounted.cells.firstIndex { $0.row == 1 && $0.column == 0 }))
        let bobView = mounted.grid.cellView(try #require(mounted.cells.firstIndex { $0.row == 1 && $0.column == 1 }))
        #expect(bobView.frame.minX > aliceView.frame.minX && abs(bobView.frame.minY - aliceView.frame.minY) < 1)
        #endif
        let before = try RelayMarkNativeDocumentProjection.project(document: document)
        let source = String(editor.text.characters)
        let alice = (source as NSString).range(of: "Alice")
        let start = try #require(AttributedString.Index(String.Index(utf16Offset: alice.location, in: source), within: editor.text))
        let end = try #require(AttributedString.Index(String.Index(utf16Offset: NSMaxRange(alice), in: source), within: editor.text))
        var candidate = editor.text
        var replacement = AttributedString("Alicia")
        replacement.presentationIntent = candidate[start..<end].runs.first?.presentationIntent
        candidate.replaceSubrange(start..<end, with: replacement)
        editor.edit(candidate)
        #expect(editor.failure == nil && saved.count == 1, "\(editor.failure ?? "No saved table edit")")
        try peer.applyUpdate(try #require(saved.last))
        let after = try RelayMarkNativeDocumentProjection.project(document: document)
        let peerAfter = try RelayMarkNativeDocumentProjection.project(document: peer)
        #expect(after == peerAfter)
        #expect(after.blocks[1].childBlocks[1].childBlocks[0].plainText == "Alicia")
        #expect(after.blocks[1].childBlocks[0] == before.blocks[1].childBlocks[0])
        #expect(after.blocks[1].childBlocks[1].childBlocks[1] == before.blocks[1].childBlocks[1].childBlocks[1])
    }

    @Test("Tab travels between cell views without a Yrs update")
    func tableCellKeyboardNavigation() throws {
        #if os(macOS)
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(tableUpdate())
        var saved = 0
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in saved += 1 })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 640, height: 480),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        window.orderFront(nil)
        defer { coordinator.retire(view); window.contentView = nil; window.close() }
        let manager = try #require(view.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        view.layoutSubtreeIfNeeded()
        let table = try #require(view.paper.tables.spans.first?.table)
        let before = try document.encodeUpdate()
        let first = table.grid.cellView(0)
        window.makeFirstResponder(first)
        first.insertTab(nil)
        #expect(window.firstResponder === table.grid.cellView(1))
        table.grid.cellView(1).insertBacktab(nil)
        #expect(window.firstResponder === first)
        let last = table.grid.cellView(table.cells.count - 1)
        window.makeFirstResponder(last)
        last.insertTab(nil)
        #expect(window.firstResponder === last, "Tab at the table's last cell stays there")
        #expect(saved == 0)
        #expect(try document.encodeUpdate() == before)
        #endif
    }

    @Test("Delete Row maps the caret to the next surviving block")
    func deleteTableRowMapsSelection() throws {
        let url = try #require(Bundle.module.url(forResource: "table-add-row-v3",
                                                 withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let encoded = try #require(fixture["seed"] as? String)
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(try #require(Data(base64Encoded: encoded)))
        var captured: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { captured.append($0) })
        let alpha = (String(editor.text.characters) as NSString).range(of: "Alpha")
        editor.setNativeSelection(NSRange(location: alpha.location + 2, length: 0))
        editor.performSelectedTableCommand(.deleteRow)
        #expect(editor.failure == nil)
        let command = try #require(captured.first)
        #expect(!String(editor.text.characters).contains("Alpha"))
        let selection = try #require(editor.nativeSelection)
        let prose = try document.richProseProjection()
        #expect(prose.blockRanges.contains { NSLocationInRange(selection.location, $0) || NSMaxRange($0) == selection.location })
    }

    #if os(macOS)
    @Test("Mounted TextKit input delivers one table-cell edit to the same Yrs session")
    func mountedTableCellInput() throws {
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(tableUpdate())
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Shared paper")
        defer { coordinator.retire(view) }
        let alice = (String(editor.text.characters) as NSString).range(of: "Alice")
        let (cell, offset) = try self.cell(view, at: alice.location)
        cell.insertText("Alicia", replacementRange: NSRange(location: offset, length: alice.length))
        #expect(editor.failure == nil, "\(editor.failure ?? "No failure")")
        #expect(saved.count == 1)
        #expect(String(editor.text.characters).contains("Alicia"))
        #expect(view.paperString == String(editor.text.characters))
        let end = offset + 6
        cell.insertText("!", replacementRange: NSRange(location: end, length: 0))
        #expect(editor.failure == nil && saved.count == 2)
        #expect(String(editor.text.characters).contains("Alicia!"))
    }

    @Test("Mounted TextKit input seeds an empty Yjs table cell")
    func mountedEmptyTableCellInput() throws {
        enum SaveFailure: Error { case disk }
        let seed = try tableUpdate()
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try RelayMarkNativeDocumentProjection.project(document: document)
        var fail = true
        var attempts: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: {
                attempts.append($0.update)
                if fail { throw SaveFailure.disk }
            })
        let projection = try document.richProseProjection()
        let index = try #require(projection.blockPaths.firstIndex(of: [1, 2, 0, 0]))
        let offset = projection.blockRanges[index].location
        #expect(projection.blockRanges[index].length == 0)
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Shared paper")
        defer { coordinator.retire(view) }
        #expect(view.paper.emptyBlocks.contains { $0.offset == offset })
        let (cell, inside) = try self.cell(view, at: offset)
        cell.insertText("First", replacementRange: NSRange(location: inside, length: 0))
        #expect(editor.hasUnpersistedTransaction && attempts.count == 1)
        #expect(String(editor.text.characters).contains("First"))
        editor.undo()
        #expect(attempts.count == 1 && editor.hasUnpersistedTransaction)
        fail = false
        editor.retryPersistence()
        #expect(editor.failure == nil && !editor.hasUnpersistedTransaction)
        #expect(attempts.count == 2 && attempts[0] == attempts[1])
        try peer.applyUpdate(try #require(attempts.last))
        let after = try RelayMarkNativeDocumentProjection.project(document: document)
        let peerAfter = try RelayMarkNativeDocumentProjection.project(document: peer)
        #expect(after == peerAfter)
        #expect(after.blocks[1].childBlocks[2].childBlocks[0].plainText == "First")
        #expect(after.blocks[1].childBlocks[2].childBlocks[0].id ==
                before.blocks[1].childBlocks[2].childBlocks[0].id)
        #expect(after.blocks[1].childBlocks[0] == before.blocks[1].childBlocks[0])
        #expect(after.blocks[1].childBlocks[1] == before.blocks[1].childBlocks[1])
        #expect(after.blocks[1].childBlocks[2].childBlocks[1] == before.blocks[1].childBlocks[2].childBlocks[1])
        editor.undo()
        #expect(editor.failure == nil && attempts.count == 3)
        try peer.applyUpdate(try #require(attempts.last))
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) == before)
        #expect(try RelayMarkNativeDocumentProjection.project(document: peer) == before)
    }

    @Test("Re-projected rows stay in their table's text table")
    func rowSpliceKeepsOneTextTable() throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            (["| a | b |", "| --- | --- |"] + (1...6).map { "| cell \($0) | other \($0) |" }).joined(separator: "\n"),
            namespace: "rows"))
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Shared paper")
        defer { coordinator.retire(view) }
        #if os(macOS)
        let at = (String(editor.text.characters) as NSString).range(of: "cell 3").location + 4
        let (cell, inside) = try self.cell(view, at: at)
        cell.setSelectedRange(NSRange(location: inside, length: 0))
        cell.insertNewline(nil)
        #expect(editor.failure == nil && editor.fallbackEdits == 0)
        #expect(view.paper.tables.spans.count == 1)
        let table = try #require(view.paper.tables.spans.first?.table)
        #expect(Set(table.cells.map(\.row)) == Set(0...6) && table.cells.contains { $0.text.string == "cell\n 3" })
        #endif
    }

    @Test("Typing at the end of a table-only document targets its final empty cell")
    func trailingEmptyCellInput() throws {
        let seed = try update("table-only-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let last = try #require(editor.nativeTableCells.last)
        let offset = String(editor.text.characters).utf16.count
        #expect(last.range.length == 0 && last.range.location == offset)
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Shared paper")
        defer { coordinator.retire(view) }
        #expect(view.string == "\u{FFFC}", "A table-only paper shows one table attachment")
        #expect(view.paperValue() == editor.text)
        #expect(!coordinator.textView(view, shouldChangeTextIn: NSRange(location: 1, length: 0), replacementString: "Outside"))
        #expect(saved.isEmpty)
        let (cell, inside) = try self.cell(view, at: offset)
        cell.insertText("Tail", replacementRange: NSRange(location: inside, length: 0))
        #expect(editor.failure == nil && saved.count == 1, "\(editor.failure ?? "No saved final-cell edit")")
        #expect(view.paperString == String(editor.text.characters))
        try peer.applyUpdate(try #require(saved.last))
        let after = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(after == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        #expect(after.blocks[0].childBlocks.last?.childBlocks.last?.plainText == "Tail")
    }

    @Test("Mixed tasks and references enter the same native v3 editor without altering Yrs XML")
    func mixedStructuresEnterNativeEditor() throws {
        for (fixture, atom) in [("task-list-v3-draft", "task_list"),
                                ("entity-reference-v3-draft", "relay.entity_reference")] {
            let document = RelayMarkNativeDocument()
            try document.applyUpdate(update(fixture))
            let ast = try RelayMarkNativeDocumentProjection.project(document: document)
            #expect(ast.blocks.map(\.type) == ["paragraph", atom, "paragraph"])
            let checkpoint = try document.encodeUpdate()
            var saved: [Data] = []
            let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
            #expect(editor.isEditable && !editor.isTaskList)
            if atom == "task_list" {
                let items = editor.nativeTaskItems
                #expect(items.map(\.path) == [[1, 0], [1, 0, 2, 0], [1, 1]])
                let display = NativeProseCodec.attributed(editor.text,
                    emptyBlocks: editor.nativeEmptyBlocks, taskItems: items)
                #expect(NativeProseCodec.value(display) == editor.text)
                for (item, marker) in zip(items, ["☑", "☐", "☐"]) {
                    let rendered = display.attribute(NSAttributedString.Key("RelayListMarker"),
                        at: item.firstParagraphRange.location, effectiveRange: nil) as? String
                    #expect(rendered == marker)
                }
            } else {
                #expect(editor.nativeEntityReferenceAtoms.count == 1)
            }
            #expect(saved.isEmpty)
            #expect(try document.encodeUpdate() == checkpoint)
        }
    }

    @Test("Nested mixed-document checkbox is one guarded Yrs update with peer replay and undo")
    func nestedMixedTaskToggle() throws {
        let seed = try update("task-list-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let nested = try #require(editor.nativeTaskItems.first(where: { $0.path == [1, 0, 2, 0] }))
        #expect(editor.toggleTaskItem(atUTF16: nested.firstParagraphRange.location))
        #expect(saved.count == 1 && editor.failure == nil)
        try peer.applyUpdate(try #require(saved.last))
        #expect(editor.nativeTaskItems.map(\.checked) == [true, true, false])
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) ==
            RelayMarkNativeDocumentProjection.project(document: peer))
        editor.undo()
        #expect(saved.count == 2 && editor.failure == nil)
        try peer.applyUpdate(try #require(saved.last))
        #expect(editor.nativeTaskItems.map(\.checked) == [true, false, false])
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) ==
            RelayMarkNativeDocumentProjection.project(document: peer))
    }

    @Test("Adjacent prose edits replay while image and video identities remain protected")
    func mediaAdjacentProseEditing() throws {
        for fixture in ["rich-image-v3-draft", "rich-video-v3-draft"] {
            let seed = try mediaFixtureUpdate(fixture)
            let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try document.applyUpdate(seed)
            try peer.applyUpdate(seed)
            var saved: [Data] = []
            let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
            let media = try #require(editor.nativeMediaAtoms.first)
            #expect(editor.isEditable)
            let baseline = String(editor.text.characters)
            #expect(!editor.acceptsNativeReplacement(baseline: baseline,
                range: media.range, replacement: ""))
            let checkpoint = try document.encodeUpdate()
            editor.edit(replacingFirstWord(in: editor))
            #expect(editor.failure == nil && saved.count == 1)
            #expect(try document.encodeUpdate() != checkpoint)
            try peer.applyUpdate(try #require(saved.last))
            #expect(editor.nativeMediaAtoms.map(\.id) == [media.id])
            #expect(editor.nativeMediaAtoms.map(\.source) == [media.source])
            #expect(editor.nativeMediaAtoms.first?.range.location == media.range.location - 1)
            #expect(try RelayMarkNativeDocumentProjection.project(document: document) ==
                    RelayMarkNativeDocumentProjection.project(document: peer))
            editor.undo()
            #expect(editor.failure == nil && saved.count == 2)
            try peer.applyUpdate(try #require(saved.last))
            #expect(try document.snapshot() == peer.snapshot())
        }
    }

    @Test("Mounted TextKit edits prose beside media and refuses an atom deletion as text")
    func mountedMediaAdjacentInput() throws {
        let seed = try update("rich-image-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Shared paper")
        defer { coordinator.retire(view) }
        #expect(view.isEditable)
        let firstWord = (view.string as NSString).range(of: "Before")
        view.setSelectedRange(firstWord)
        view.insertText("After", replacementRange: firstWord)
        #expect(editor.failure == nil && saved.count == 1)
        try peer.applyUpdate(try #require(saved.last))
        let media = try #require(editor.nativeMediaAtoms.first)
        let checkpoint = try document.encodeUpdate()
        view.setSelectedRange(media.range)
        view.insertText("", replacementRange: media.range)
        #expect(saved.count == 1 && editor.failure == nil)
        #expect(try document.encodeUpdate() == checkpoint)
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) ==
                RelayMarkNativeDocumentProjection.project(document: peer))
    }

    @Test("Paper controls are inert native atoms; adjacent prose edits replay without changing their identity")
    func paperControlsRemainStableDuringProseEditing() throws {
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        let seed = try update("paper-controls-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(before.blocks.map(\.type) == ["paragraph", "relay.paper_control", "relay.paper_control",
                                             "relay.paper_control", "relay.paper_control", "relay.paper_control", "paragraph"])
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let atoms = editor.nativeBlockAtoms
        #expect(atoms.count == 5 && atoms.allSatisfy { $0.range.length == 1 })
        #expect(atoms.map(\.control) == [.anchor, .button, .button, .button, .connection])
        let displayed = NativeProseCodec.attributed(editor.text, blockAtoms: atoms)
        #expect(NativeProseCodec.value(displayed) == editor.text)
        for atom in atoms {
            #expect(displayed.attribute(.attachment, at: atom.range.location, effectiveRange: nil) != nil)
            #expect(!editor.acceptsNativeReplacement(baseline: String(editor.text.characters),
                range: atom.range, replacement: "removed"))
        }
        let text = String(editor.text.characters)
        let range = (text as NSString).range(of: "Before")
        #expect(range.location != NSNotFound)
        let start = try #require(AttributedString.Index(String.Index(utf16Offset: range.location, in: text), within: editor.text))
        let end = try #require(AttributedString.Index(String.Index(utf16Offset: NSMaxRange(range), in: text), within: editor.text))
        var candidate = editor.text
        var replacement = AttributedString("Before both peers")
        replacement.presentationIntent = candidate[start..<end].runs.first?.presentationIntent
        candidate.replaceSubrange(start..<end, with: replacement)
        editor.edit(candidate)
        #expect(editor.failure == nil && saved.count == 1)
        try peer.applyUpdate(try #require(saved.last))
        let after = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(after == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        #expect(after.blocks[0].plainText == "Before both peers")
        #expect(Array(after.blocks[1...5]) == Array(before.blocks[1...5]))
        #expect(editor.nativeBlockAtoms.map(\.id) == atoms.map(\.id))
    }

    @Test("Browser v3 offered marks display, edit through Yrs, retry exact bytes, replay and undo")
    func offeredMarksEditAndReplay() throws {
        enum SaveFailure: Error { case disk }
        let seed = try update("inline-offered-marks-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let original = try RelayMarkNativeDocumentProjection.project(document: document)
        var fail = true
        var attempts: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: {
                attempts.append($0.update)
                if fail { throw SaveFailure.disk }
            })
        let baseline = String(editor.text.characters)
        let selected = (baseline as NSString).range(of: "All offered")
        #expect(selected.location != NSNotFound)
        let display = NativeProseCodec.attributed(editor.text)
        #expect(NativeProseCodec.value(display) == editor.text)
        #expect((display.attribute(.underlineStyle, at: selected.location, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue)
        #expect(display.attribute(.backgroundColor, at: selected.location, effectiveRange: nil) != nil)
        #expect(display.attribute(.baselineOffset, at: selected.location, effectiveRange: nil) != nil)

        for (index, mark) in RelayMarkOfferedMark.allCases.enumerated() {
            editor.setNativeSelection(selected)
            editor.toggleOfferedMark(mark)
            if index == 0 {
                #expect(editor.hasUnpersistedTransaction && attempts.count == 1)
                editor.undo()
                #expect(attempts.count == 1)
                fail = false
                editor.retryPersistence()
                #expect(!editor.hasUnpersistedTransaction && attempts.count == 2)
                #expect(attempts[0] == attempts[1])
            } else { #expect(editor.failure == nil) }
            try peer.applyUpdate(try #require(attempts.last))
            #expect(try RelayMarkNativeDocumentProjection.project(document: document) ==
                    RelayMarkNativeDocumentProjection.project(document: peer))
        }
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) != original)
        for _ in RelayMarkOfferedMark.allCases {
            editor.undo()
            #expect(editor.failure == nil)
            try peer.applyUpdate(try #require(attempts.last))
        }
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) == original)
        #expect(try RelayMarkNativeDocumentProjection.project(document: peer) == original)
    }

    @Test("Native cross-paragraph Delete and inline atom removal persist once and undo on peers")
    func crossParagraphJoinAndAtomRemoval() throws {
        let seed = try update("inline-atoms-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed); try peer.applyUpdate(seed)
        let original = try document.snapshot()
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let initial = String(editor.text.characters), atoms = editor.nativeInlineAtoms.map(\.id)
        let range = NSRange(location: try document.richProseProjection().blockRanges[0].length, length: 1)
        #expect(editor.acceptsNativeReplacement(baseline: initial, range: range, replacement: ""))
        func deleting(_ range: NSRange, from value: AttributedString) throws -> AttributedString {
            let source = String(value.characters)
            let lower = try #require(AttributedString.Index(String.Index(utf16Offset: range.location, in: source), within: value))
            let upper = try #require(AttributedString.Index(String.Index(utf16Offset: NSMaxRange(range), in: source), within: value))
            var result = value
            result.removeSubrange(lower..<upper)
            return result
        }
        editor.edit(try deleting(range, from: editor.text))
        #expect(editor.failure == nil && saved.count == 1)
        #expect(String(editor.text.characters) == (initial as NSString).replacingCharacters(in: range, with: ""))
        #expect(editor.nativeInlineAtoms.map(\.id) == atoms)
        try peer.applyUpdate(try #require(saved.last))
        #expect(try peer.snapshot() == document.snapshot())
        #expect(try RelayMarkNativeDocumentProjection.project(document: document).blocks.count == 1)
        editor.undo()
        try peer.applyUpdate(try #require(saved.last))
        #expect(try document.snapshot() == original && peer.snapshot() == original)
        let atom = try #require(editor.nativeInlineAtoms.first)
        editor.edit(try deleting(atom.range, from: editor.text))
        #expect(editor.failure == nil && saved.count == 3)
        #expect(editor.nativeInlineAtoms.map(\.id) == Array(atoms.dropFirst()))
        try peer.applyUpdate(try #require(saved.last))
        #expect(try peer.snapshot() == document.snapshot())
        editor.undo()
        #expect(try document.snapshot() == original)
    }

    @Test("Existing reference and tag atoms display as one unit; adjacent typing and undo preserve peer XML")
    func inlineAtomAdjacentEditingAndPeerReplay() throws {
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        let seed = try update("inline-atoms-v3-draft")
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let original = try RelayMarkNativeDocumentProjection.project(document: document)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let atoms = editor.nativeInlineAtoms
        #expect(atoms.count == 3)
        #expect(atoms.allSatisfy { $0.range.length == 1 })
        #expect(atoms.map(\.label) == ["Ada Lovelace", "#today", "Prepare review"])
        let displayed = NativeProseCodec.attributed(editor.text, inlineAtoms: atoms)
        #expect(NativeProseCodec.value(displayed) == editor.text)
        for atom in atoms {
            #expect(displayed.attribute(.attachment, at: atom.range.location, effectiveRange: nil) != nil)
            #expect(editor.acceptsNativeReplacement(baseline: String(editor.text.characters),
                range: atom.range, replacement: "removed"))
        }
        #expect(editor.acceptsNativeReplacement(baseline: String(editor.text.characters),
            range: NSRange(location: atoms[0].range.location, length: 0), replacement: "dear "))
        #if os(macOS)
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "References")
        editor.setNativeSelection(NSRange(location: atoms[0].range.location, length: 0))
        coordinator.update(view)
        view.insertText("dear ", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.failure == nil && saved.count == 1)
        try peer.applyUpdate(try #require(saved.last))
        let afterFirst = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(afterFirst == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        #expect(afterFirst.blocks[0].plainText.contains("Meet dear "))
        #expect(editor.nativeInlineAtoms.map(\.id) == atoms.map(\.id))

        let moved = try #require(editor.nativeInlineAtoms.first)
        editor.setNativeSelection(NSRange(location: NSMaxRange(moved.range), length: 0))
        coordinator.update(view)
        view.insertText("again ", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.failure == nil && saved.count == 2)
        try peer.applyUpdate(try #require(saved.last))
        let afterSecond = try RelayMarkNativeDocumentProjection.project(document: document)
        #expect(afterSecond == (try RelayMarkNativeDocumentProjection.project(document: peer)))
        #expect(afterSecond.blocks[0].plainText.contains("again  for"))

        let selected = try #require(editor.nativeInlineAtoms.first)
        editor.setNativeSelection(selected.range)
        coordinator.update(view)
        view.insertText("replace", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.failure == nil && saved.count == 3)
        #expect(editor.nativeInlineAtoms.map(\.id) == Array(atoms.map(\.id).dropFirst()))
        try peer.applyUpdate(try #require(saved.last))
        #expect(try peer.snapshot() == document.snapshot())

        editor.undo()
        #expect(editor.failure == nil && saved.count == 4)
        try peer.applyUpdate(try #require(saved.last))
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) == afterSecond)
        #expect(editor.nativeInlineAtoms.map(\.id) == atoms.map(\.id))
        editor.undo()
        #expect(editor.failure == nil && saved.count == 5)
        try peer.applyUpdate(try #require(saved.last))
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) == afterFirst)
        editor.undo()
        #expect(editor.failure == nil && saved.count == 6)
        try peer.applyUpdate(try #require(saved.last))
        #expect(try RelayMarkNativeDocumentProjection.project(document: document) == original)
        #expect(try RelayMarkNativeDocumentProjection.project(document: peer) == original)
        #endif
    }

    #endif

    @Test("Cross-block candidates replace through ProseMirror; unsupported input leaves the document unchanged")
    func unsupportedEdit() throws {
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(update())
        var saved = [Data]()
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let checkpoint = try document.encodeUpdate()
        let unsupported = AttributedString("Object \u{FFFC} replacement")
        editor.edit(unsupported)
        #expect(editor.failure != nil && saved.isEmpty)
        #expect(try document.encodeUpdate() == checkpoint)

        let replacedDocument = RelayMarkNativeDocument()
        try replacedDocument.applyUpdate(update())
        let replacing = try RelayMarkEditorSession(document: replacedDocument, persist: { saved.append($0.update) })
        let whole = AttributedString("Replacing all Markdown blocks")
        replacing.edit(whole)
        #expect(replacing.failure == nil && saved.count == 1)
        #expect(String(try replacedDocument.richProseProjection().text.characters) == String(whole.characters))
        replacing.undo()
        #expect(String(try replacedDocument.richProseProjection().text.characters) ==
                String(try document.richProseProjection().text.characters))
    }

}
