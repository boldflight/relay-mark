import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkSwift
import RelayMarkProseProjection
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
struct RelayMarkEditorCollaborativeTextViewTests {
    private func document(_ source: String) throws -> RelayMarkNativeDocument {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "native-text-view"))
        return document
    }

    private func multiblockDocument() throws -> RelayMarkNativeDocument {
        try document("## Summary\n\nThe client 😀\n\nNext Ω")
    }

    @Test func nativeMultiblockRoundtripPreservesAbsentSeparatorIntent() throws {
        let document = try multiblockDocument()
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let text = editor.text
        #expect(String(text.characters) == "Summary\nThe client 😀\nNext Ω")
        #expect(text.runs.contains { String(text[$0.range].characters) == "\n" && $0.inlinePresentationIntent == nil })
        #expect(NativeProseCodec.value(NativeProseCodec.attributed(text)) == text)
    }

    @Test func nativeMultiblockFormattingPreservesTextAndItemIdentity() throws {
        let document = try multiblockDocument()
        var transactions: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { transactions.append($0) })
        let before = editor.text
        // An anchor inside the untouched prefix still resolves there only if its items survived.
        let prefixLength = "The client 😀".utf16.count, identities = try document.anchor(path: [1, 0], index: prefixLength - 1)
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Multiblock paper")
        let range = (String(before.characters) as NSString).range(of: "The client")
        #if os(macOS)
        view.setSelectedRange(range)
        let manager = NSFontManager.shared
        let oldTarget = manager.target, oldAction = manager.action
        defer { manager.target = oldTarget; manager.action = oldAction }
        manager.target = view; manager.action = #selector(NSTextView.changeFont(_:))
        manager.setSelectedFont(try #require(view.attributedString().attribute(.font, at: range.location, effectiveRange: nil) as? NSFont), isMultiple: false)
        let item = NSMenuItem(title: "Bold", action: nil, keyEquivalent: "")
        item.tag = Int(NSFontTraitMask.boldFontMask.rawValue)
        manager.addFontTrait(item)
        #else
        view.selectedRange = range
        view.toggleBoldface(nil)
        #endif
        try editor.finishNativeComposition()
        #expect(transactions.count == 1)
        #expect(editor.failure == nil)
        #expect(editor.text != before)
        #expect(String(editor.text.characters) == String(before.characters))
        #expect(try document.resolve(anchor: identities) == .init(path: [1, 0], index: prefixLength - 1))
        #expect(NativeProseCodec.value(NativeProseCodec.attributed(editor.text)) == editor.text)
        coordinator.retire(view)
    }

    private func session(_ value: String, canEdit: @escaping () -> Bool = { true },
                         persistTransaction: ((RelayMarkLocalTransaction) throws -> Void)? = nil,
                         persist: @escaping ([Data]) throws -> Void = { _ in }) throws -> RelayMarkEditorSession {
        let document = try document(value)
        return try RelayMarkEditorSession(document: document, canEdit: canEdit,
            persist: { transaction in
                try persistTransaction?(transaction)
                try persist([transaction.update])
            })
    }

    @Test(arguments: [RelayMarkFormattingMark.bold, .italic])
    func nativeFontCommandCarriesExplicitEvidenceButMarkedInputDoesNot(mark formatting: RelayMarkFormattingMark) throws {
        var transactions: [RelayMarkLocalTransaction] = []
        let editor = try session("Hello", persistTransaction: { transactions.append($0) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        #if os(macOS)
        view.setSelectedRange(NSRange(location: 0, length: 5))
        let manager = NSFontManager.shared
        let oldTarget = manager.target, oldAction = manager.action
        defer { manager.target = oldTarget; manager.action = oldAction }
        manager.target = view; manager.action = #selector(NSTextView.changeFont(_:))
        manager.setSelectedFont(try #require(view.font), isMultiple: false)
        let item = NSMenuItem(title: formatting.rawValue, action: nil, keyEquivalent: "")
        item.tag = Int((formatting == .bold ? NSFontTraitMask.boldFontMask : .italicFontMask).rawValue)
        manager.addFontTrait(item)
        #else
        view.selectedRange = NSRange(location: 0, length: 5)
        if formatting == .bold { view.toggleBoldface(nil) } else { view.toggleItalics(nil) }
        #endif
        #expect(transactions.count == 1)
        mark(view)
        #if os(macOS)
        manager.addFontTrait(item)
        #else
        if formatting == .bold { view.toggleBoldface(nil) } else { view.toggleItalics(nil) }
        #endif
        #expect(transactions.count == 1)
        #expect(String(editor.text.characters) == "Hello")
        coordinator.retire(view)
    }

    @Test func finishingEmptyNativeCompositionDoesNotPermanentlySuppressFormattingHistory() throws {
        var receipts: [RelayMarkLocalTransaction] = []
        let editor = try session("Hello", persistTransaction: { receipts.append($0) })
        let before = editor.text
        var formatted = before; formatted.inlinePresentationIntent = .stronglyEmphasized
        editor.editFormatting(formatted, command: .init(baseline: before, range: NSRange(location: 0, length: 5), mark: .bold))
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        #if os(macOS)
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #else
        view.selectedRange = NSRange(location: 5, length: 0)
        view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        #endif
        try coordinator.finishComposition(view)
        #if os(macOS)
        let undoItem = NSMenuItem(title: "Undo", action: #selector(CollaborationTextView.undo(_:)), keyEquivalent: "z")
        #expect(view.validateMenuItem(undoItem))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        #expect(window.makeFirstResponder(view))
        #expect(view.tryToPerform(#selector(CollaborationTextView.undo(_:)), with: nil))
        #else
        view.undoManager?.undo()
        #endif
        #expect(receipts.count == 2)
        #expect(editor.text == before)
        #if os(macOS)
        #expect(view.tryToPerform(#selector(CollaborationTextView.redo(_:)), with: nil))
        #else
        view.undoManager?.redo()
        #endif
        #expect(receipts.count == 3)
        #expect(editor.text == formatted)
        coordinator.retire(view)
    }

    private func mark(_ view: CollaborationTextView) {
        #if os(macOS)
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #else
        view.selectedRange = NSRange(location: 5, length: 0)
        view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0))
        #endif
    }

    private func insert(_ text: String, into view: CollaborationTextView) {
        #if os(macOS)
        view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        #else
        view.insertText(text)
        #endif
    }

    @Test func nativeParagraphReturnThenEmojiCarriesExactEvidenceAndCaret() throws {
        var receipts: [RelayMarkLocalTransaction] = []
        let editor = try session("Hello😀", persistTransaction: { receipts.append($0) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paragraph paper")
        #if os(macOS)
        view.setSelectedRange(NSRange(location: 7, length: 0))
        view.insertNewline(nil)
        #else
        view.selectedRange = NSRange(location: 7, length: 0)
        // Programmatic UIKeyInput insertion bypasses UIKit's keyboard delegate
        // preflight; as the keyboard does, ask it first. Return is applied by
        // the coordinator itself, so UIKit inserts nothing.
        if coordinator.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: "\n") { view.insertText("\n") }
        #endif
        try editor.finishNativeComposition()
        #expect(receipts.count == 1)
        #expect(String(editor.text.characters) == "Hello😀\n")
        #if os(macOS)
        insert("Next 🌍", into: view)
        #else
        // The first text of the new paragraph is applied by the coordinator itself.
        if coordinator.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: "Next 🌍") { insert("Next 🌍", into: view) }
        #endif
        try editor.finishNativeComposition()
        #expect(receipts.count == 2)
        #expect(String(editor.text.characters) == "Hello😀\nNext 🌍")
        #expect(editor.failure == nil)
        coordinator.retire(view)
    }

    #if os(macOS)
    @Test func nativePlainMultilinePasteProducesOneReceipt() throws {
        var receipts: [RelayMarkLocalTransaction] = []
        let editor = try session("Hello😀", persistTransaction: { receipts.append($0) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paste paper")
        defer { coordinator.retire(view) }
        let board = NSPasteboard.general
        let prior = board.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        } ?? []
        defer {
            board.clearContents()
            let items = prior.map { data in let item = NSPasteboardItem(); for (key, value) in data { item.setData(value, forType: key) }; return item }
            board.writeObjects(items)
        }
        board.clearContents(); board.setString("One\n\nTwo 🌍\n", forType: .string)
        view.setSelectedRange(NSRange(location: 7, length: 0))
        view.pasteAsPlainText(nil)
        #expect(receipts.count == 1)
        #expect(String(editor.text.characters) == "Hello😀One\n\nTwo 🌍\n")
        #expect(editor.failure == nil)
        let beforeInline = editor.text
        board.clearContents(); board.setString("End", forType: .string)
        view.pasteAsPlainText(nil)
        #expect(receipts.count == 2)
        #expect(String(editor.text.characters) == "Hello😀One\n\nTwo 🌍\nEnd")
        var retained = editor.text
        let endStart = retained.characters.index(retained.endIndex, offsetBy: -3)
        retained.replaceSubrange(endStart..<retained.endIndex, with: AttributedString())
        #expect(retained == beforeInline)
        let beforeOversized = editor.text, nativeBefore = view.string
        board.clearContents(); board.setString(String(repeating: "x", count: 131_073), forType: .string)
        view.pasteAsPlainText(nil)
        #expect(receipts.count == 2)
        #expect(board.string(forType: .string) == String(repeating: "x", count: 131_073))
        #expect(editor.text == beforeOversized && view.string == nativeBefore)
    }
    #endif

    #if !os(macOS)
    @MainActor private final class PasteItem: NSObject, UITextPasteItem {
        let itemProvider: NSItemProvider
        let localObject: Any? = nil
        let defaultAttributes: [NSAttributedString.Key: Any] = [:]
        let completion = AsyncStream<Void>.makeStream()
        var result: NSAttributedString?
        init(_ text: String) { itemProvider = NSItemProvider(object: text as NSString) }
        func setResult(string: String) { setResult(attributedString: NSAttributedString(string: string)) }
        func setResult(attributedString: NSAttributedString) { result = attributedString; completion.continuation.yield(()); completion.continuation.finish() }
        func setResult(attachment: NSTextAttachment) { setNoResult() }
        func setNoResult() { completion.continuation.yield(()); completion.continuation.finish() }
        func setDefaultResult() { setNoResult() }
        func completed() async { for await _ in completion.stream { break } }
    }

    @Test func asyncPasteRetirementAndLateMixedResultsPreserveExactOwner() async throws {
        var receipts: [RelayMarkLocalTransaction] = []
        let editor = try session("Hello", persistTransaction: { receipts.append($0) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paste lifetime")
        view.selectedRange = NSRange(location: 5, length: 0)
        view.paste(itemProviders: [])
        let old = PasteItem("Old\n")
        coordinator.textPasteConfigurationSupporting(view, transform: old)
        await old.completed()
        let tagged = try #require(old.result)
        view.paste(itemProviders: [])
        let newer = PasteItem("New\n")
        coordinator.textPasteConfigurationSupporting(view, transform: newer)
        await newer.completed()
        let mixed = NSMutableAttributedString(attributedString: tagged)
        mixed.append(NSAttributedString(string: "untagged"))
        let range = try #require(view.selectedTextRange)
        _ = coordinator.textPasteConfigurationSupporting(view, performPasteOf: mixed, to: range)
        #expect(receipts.isEmpty)
        #expect(String(editor.text.characters) == "Hello" && coordinator.pendingPasteCount == 1)
        _ = coordinator.textPasteConfigurationSupporting(view, performPasteOf: try #require(newer.result), to: range)
        #expect(receipts.count == 1 && String(editor.text.characters) == "HelloNew\n")
        view.paste(itemProviders: [])
        let retired = PasteItem("Retired\n")
        coordinator.textPasteConfigurationSupporting(view, transform: retired)
        coordinator.retire(view)
        await retired.completed()
        #expect(retired.result == nil && coordinator.pendingPasteCount == 0 && view.pasteDelegate == nil)
        #expect(receipts.count == 1)
    }

    @Test func nativeAsyncPlainMultilinePasteUsesActualPasteDelegate() async throws {
        var receipts: [RelayMarkLocalTransaction] = []
        let editor = try session("Hello😀", persistTransaction: { receipts.append($0) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paste paper")
        defer { coordinator.retire(view) }
        view.selectedRange = NSRange(location: 7, length: 0)
        view.paste(itemProviders: [NSItemProvider(object: "One\n\nTwo 🌍\n" as NSString)])
        // Generous deadlines: other suites' main-actor work can delay delivery; each wait ends when it arrives.
        let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(30))
        while receipts.isEmpty, editor.failure == nil, clock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(receipts.count == 1)
        #expect(String(editor.text.characters) == "Hello😀One\n\nTwo 🌍\n")
        #expect(editor.failure == nil)
        #expect(!view.attributedText.description.contains("RelayTransientPasteToken"))
        let beforeInline = editor.text
        view.paste(itemProviders: [NSItemProvider(object: "End" as NSString)])
        let inlineDeadline = clock.now.advanced(by: .seconds(30))
        while receipts.count < 2, editor.failure == nil, clock.now < inlineDeadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(receipts.count == 2)
        var retained = editor.text
        let endStart = retained.characters.index(retained.endIndex, offsetBy: -3)
        retained.replaceSubrange(endStart..<retained.endIndex, with: AttributedString())
        #expect(retained == beforeInline)
        let beforeOversized = editor.text, nativeBefore = view.text
        view.paste(itemProviders: [NSItemProvider(object: String(repeating: "\n", count: 4097) as NSString)])
        let oversizedDeadline = clock.now.advanced(by: .seconds(30))
        while editor.failure == nil, clock.now < oversizedDeadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(editor.failure != nil && receipts.count == 2 && coordinator.pendingPasteCount == 0)
        #expect(editor.text == beforeOversized && view.text == nativeBefore)
    }

    @Test func mountedInvalidationErasesPendingPasteBeforeProviderCompletion() async throws {
        var receipts: [RelayMarkLocalTransaction] = []
        let editor = try session("Private", persistTransaction: { receipts.append($0) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paste retirement")
        defer { coordinator.retire(view) }
        view.selectedRange = NSRange(location: 7, length: 0)
        view.paste(itemProviders: [])
        let item = PasteItem("Late private\n")
        coordinator.textPasteConfigurationSupporting(view, transform: item)
        #expect(coordinator.pendingPasteCount == 1)
        editor.invalidate()
        #expect(coordinator.pendingPasteCount == 0 && view.pasteDelegate == nil)
        #expect(view.text.isEmpty && editor.text.characters.isEmpty)
        await item.completed()
        #expect(item.result == nil && receipts.isEmpty)
        #expect(coordinator.pendingPasteCount == 0 && view.text.isEmpty)
    }

    @Test func mixedPasteTokensCannotTransferCandidateToReplacementSession() async throws {
        let first = try session("Same"), second = try session("Same")
        let coordinator = RelayMarkEditorView.TextCoordinator(session: first)
        let view = coordinator.makeTextView(accessibilityLabel: "Paste ownership")
        defer { coordinator.retire(view) }
        view.selectedRange = NSRange(location: 4, length: 0)
        view.paste(itemProviders: [])
        let old = PasteItem("Old private\n")
        coordinator.textPasteConfigurationSupporting(view, transform: old); await old.completed()
        coordinator.session = second; view.editingSession = second
        view.paste(itemProviders: [])
        let fresh = PasteItem("New private\n")
        coordinator.textPasteConfigurationSupporting(view, transform: fresh); await fresh.completed()
        let mixed = NSMutableAttributedString(attributedString: try #require(old.result))
        mixed.append(try #require(fresh.result))
        _ = coordinator.textPasteConfigurationSupporting(view, performPasteOf: mixed, to: try #require(view.selectedTextRange))
        #expect(String(first.text.characters) == "Same" && String(second.text.characters) == "Same" && view.text == "Same")
    }
    #endif

    private func plain(_ view: CollaborationTextView) -> String {
        #if os(macOS)
        view.string
        #else
        view.text
        #endif
    }

    @Test func nativeDelegateRetainsOneReplacementAndClearsItOnProjectionRefresh() throws {
        let editor = try session("Hello")
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        let range = NSRange(location: 0, length: 0)
        #if os(macOS)
        #expect(coordinator.textView(view, shouldChangeTextIn: range, replacementString: "Hello"))
        // Formatting-only delegate callbacks must not replace pending text intent.
        #expect(coordinator.textView(view, shouldChangeTextIn: range, replacementString: nil))
        #else
        #expect(coordinator.textView(view, shouldChangeTextIn: range, replacementText: "Hello"))
        #endif
        // A keystroke inside one text leaf is held as typing, not as a whole-paper replacement.
        #expect(coordinator.pendingTyping?.range == range && coordinator.pendingTyping?.text == "Hello")
        coordinator.update(view)
        #expect(coordinator.pendingTyping == nil)
        coordinator.retire(view)
    }

    private func retiringMarkedOwner(editable: Bool) throws {
        var writesA = 0, writesB = 0
        let a = try session("Alpha", persist: { _ in writesA += 1 })
        let b = try session("Bravo", persist: { _ in writesB += 1 })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: a)
        let old = coordinator.makeTextView(accessibilityLabel: "Paper")
        mark(old)
        #expect(writesA == 0)
        if !editable { a.invalidate() }
        coordinator.retire(old)
        #expect(String(a.text.characters) == (editable ? "Alphaに" : ""))
        #expect(writesA == (editable ? 1 : 0))
        #expect(plain(old).isEmpty)
        #expect(old.delegate == nil)
        coordinator.session = b
        let replacement = coordinator.makeTextView(accessibilityLabel: "Paper")
        insert("late", into: old); old.unmarkText(); old.undoManager?.undo()
        coordinator.endComposition(old)
        #expect(String(b.text.characters) == "Bravo")
        #expect(writesB == 0)
        #expect(plain(old).isEmpty)
        coordinator.retire(replacement)
    }

    #if os(macOS)
    @Test("AppKit final IME text admits one exact replacement while marked candidates stay private", arguments: [false, true])
    func appKitFinalCompositionHasExactItemEvidence(replacing: Bool) async throws {
        let document = try document("Alpha tail")
        let initialState = try document.encodeUpdate()
        let retainedPrefix = try document.anchor(path: [0, 0], index: 4)
        var receipts: [RelayMarkLocalTransaction] = []
        var directWrites = 0
        let owner = try RelayMarkEditorSession(document: document,
            persist: { receipt in receipts.append(receipt); directWrites += 1 })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: owner)
        let view = coordinator.makeTextView(accessibilityLabel: "IME completion")
        defer { owner.invalidate(); coordinator.retire(view) }
        let start = replacing ? 6 : 5
        let removed = replacing ? "tail" : ""
        view.setSelectedRange(NSRange(location: start, length: removed.utf16.count))
        view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        view.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.hasMarkedText())
        #expect(receipts.isEmpty)
        #expect(directWrites == 0)
        #expect(String(owner.text.characters) == "Alpha tail")
        #expect(try document.encodeUpdate() == initialState)

        let committed = "日本🌍"
        view.insertText(committed, replacementRange: NSRange(location: NSNotFound, length: 0))
        for _ in 0..<8 { await Task.yield() }
        try owner.finishNativeComposition()
        #expect(!view.hasMarkedText())
        #expect(owner.failure == nil)
        #expect(directWrites == 1)
        #expect(receipts.count == 1)
        let receipt = try #require(receipts.first)
        #expect(!receipt.update.isEmpty)
        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(initialState); try peer.applyUpdate(receipt.update)
        #expect(try peer.authoredDocument() == document.authoredDocument())
        #expect(try document.resolve(anchor: retainedPrefix) == .init(path: [0, 0], index: 4))
        let expected = replacing ? "Alpha 日本🌍" : "Alpha日本🌍 tail"
        #expect(String(owner.text.characters) == expected)
        #expect(view.string == expected)
        #expect(view.selectedRange() == NSRange(location: start + committed.utf16.count, length: 0))
        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(document.encodeUpdate())
        #expect(try reopened.authoredDocument() == document.authoredDocument())
        try owner.finishNativeComposition()
        #expect(receipts.count == 1)
        #expect(directWrites == 1)
    }
    #endif

    @Test("Retirement commits only a still-editable old owner's marked input", arguments: [true, false])
    func retiringMarkedOwnerCases(editable: Bool) throws { try retiringMarkedOwner(editable: editable) }

    @Test("The new native undo target is the new owner, and retired unregister cannot erase its finalizer")
    func replacementUndoAndFinalizerUseCurrentOwner() throws {
        let a = try session("Alpha"), b = try session("Bravo")
        let coordinator = RelayMarkEditorView.TextCoordinator(session: a)
        let old = coordinator.makeTextView(accessibilityLabel: "Paper")
        a.edit(AttributedString("Alpha old"))
        coordinator.retire(old)
        coordinator.session = b
        let current = coordinator.makeTextView(accessibilityLabel: "Paper")
        b.edit(AttributedString("Bravo new")); coordinator.update(current)
        current.undoManager?.undo()
        coordinator.update(current)
        #expect(String(b.text.characters) == "Bravo")
        #expect(String(a.text.characters) == "Alpha old")
        mark(current)
        try b.finishNativeComposition()
        #expect(String(b.text.characters) == "Bravoに")
        coordinator.retire(old)
        coordinator.retire(current)
    }

    @Test("A queued old unmark completion cannot finish the replacement owner's composition")
    func lateUnmarkDoesNotCommitReplacement() async throws {
        var writesB = 0
        let a = try session("Alpha"), b = try session("Bravo", persist: { _ in writesB += 1 })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: a)
        let old = coordinator.makeTextView(accessibilityLabel: "Paper")
        mark(old); old.unmarkText()
        coordinator.retire(old)
        coordinator.session = b
        let current = coordinator.makeTextView(accessibilityLabel: "Paper")
        mark(current)
        for _ in 0..<4 { await Task.yield() }
        #expect(writesB == 0)
        #expect(String(b.text.characters) == "Bravo")
        try b.finishNativeComposition()
        #expect(String(b.text.characters) == "Bravoに")
        coordinator.retire(current)
    }
    @Test("A clean readonly native owner does not block ordinary navigation")
    func cleanReadonlyFinalizerIsNoOp() throws {
        let owner = try session("Alpha", canEdit: { false })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: owner)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        try owner.finishNativeComposition()
        #expect(String(owner.text.characters) == "Alpha")
        coordinator.retire(view)
    }

    @Test("Losing edit permission cancels native marked text without publishing it")
    func readonlyMarkedFinalizerCancelsInput() throws {
        var editable = true, writes = 0
        let owner = try session("Alpha", canEdit: { editable }, persist: { _ in writes += 1 })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: owner)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        mark(view)
        editable = false
        try owner.finishNativeComposition()
        #expect(String(owner.text.characters) == "Alpha")
        #expect(plain(view) == "Alpha")
        #expect(writes == 0)
        coordinator.retire(view)
    }

    @Test("Native history updates the input buffer before the next synchronous insertion")
    func historyThenImmediateInputUsesCurrentBuffer() throws {
        let owner = try session("Alpha")
        let coordinator = RelayMarkEditorView.TextCoordinator(session: owner)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        owner.edit(AttributedString("Alpha old")); coordinator.update(view)
        view.undoManager?.undo()
        #expect(plain(view) == "Alpha")
        view.undoManager?.redo()
        #expect(plain(view) == "Alpha old")
        view.undoManager?.undo()
        #if os(macOS)
        view.setSelectedRange(NSRange(location: 5, length: 0))
        #else
        view.selectedRange = NSRange(location: 5, length: 0)
        #endif
        insert(" new", into: view)
        #expect(plain(view) == "Alpha new")
        #expect(String(owner.text.characters) == "Alpha new")
        coordinator.retire(view)
    }

    @Test("Remote delivery refreshes the native buffer before immediate input without a render pass")
    func remoteThenImmediateInputPreservesRemoteText() throws {
        let document = try document("Hello")
        let remote = RelayMarkNativeDocument()
        try remote.applyUpdate(document.encodeUpdate())
        let owner = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: owner)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        #if os(macOS)
        view.setSelectedRange(NSRange(location: 5, length: 0))
        #else
        view.selectedRange = NSRange(location: 5, length: 0)
        #endif
        owner.setNativeSelection(NSRange(location: 5, length: 0))
        let update = try RelayMarkNativeRichTextMutation.replace(document: remote, path: [0,0],
            start: 0, end: 0, text: "Remote ", attributes: [:])
        try owner.applyRemoteUpdate(update)
        #expect(plain(view) == "Remote Hello")
        insert("X", into: view)
        #expect(plain(view) == "Remote HelloX")
        #expect(String(owner.text.characters) == "Remote HelloX")
        coordinator.retire(view)
    }

}
