import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
@testable import RelayMarkSwift

@MainActor @Suite("Native authored editor")
struct RelayMarkEditorAuthoredEditorSessionTests {
    @Test("An uploaded image authors the retained insertion UUID and a failed journal save retries the same exact mutation")
    func originalImageInsertionUsesExactJournalOperation() throws {
        enum FailedSave: Error { case stopped }
        let document = RelayMarkNativeDocument(guid: "00000000-0000-4000-8000-000000000068")
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("Original caret.", namespace: "image-journal-owner"))
        let original = UUID(uuidString: "00000000-0000-4000-8000-000000000067")!
        var attempts: [RelayMarkLocalTransaction] = [], reject = true
        let editor = try RelayMarkEditorSession(document: document, persist: { transaction in
            attempts.append(transaction)
            if reject { throw FailedSave.stopped }
        })
        editor.setNativeSelection(NSRange(location: 3, length: 0))
        let selection = try editor.prepareReferenceInsertion(.image)
        try editor.insertImageSource("/m/00000000-0000-4000-8000-000000000069", alt: "Original description", using: selection, operationID: original)
        let first = try #require(attempts.first)
        #expect(first.id == original && editor.hasUnpersistedTransaction)
        let beforeRetry = try document.encodeUpdate()
        reject = false; editor.retryPersistence()
        #expect(attempts.count == 2 && !editor.hasUnpersistedTransaction)
        let retried = try #require(attempts.last)
        #expect(retried == first)
        #expect(try document.encodeUpdate() == beforeRetry)
    }

    private func replaceRich(_ document: RelayMarkNativeDocument, start: Int, end: Int, text: String) throws -> Data {
        try RelayMarkNativeRichEditing.replace(document: document, range: NSRange(location: start, length: end - start),
            runs: text.isEmpty ? [] : [(text, [:])], expectedSnapshot: document.snapshot()).update
    }

    private func initializeIfEmpty(_ document: RelayMarkNativeDocument) throws {
        let snapshot = try #require(try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
        if (snapshot["children"] as? [Any])?.isEmpty == true {
            _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("", namespace: "native-owner-test"))
        }
    }

    enum SaveFailure: Error { case disk }

    @Test("Atomic paragraph edits and session undo persist portable Yjs updates")
    func editUndo() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        var saved: [RelayMarkLocalTransaction] = []
        try initializeIfEmpty(document)
        try peer.applyUpdate(document.encodeUpdate())
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0) })
        editor.edit(AttributedString("Hello\nWorld"))
        #expect(editor.failure == nil, "\(editor.failure ?? "unknown")")
        #expect(saved.count == 1)
        try peer.applyUpdate(try #require(saved.first).update)
        #expect(String(try peer.richProseProjection().text.characters) == "Hello\nWorld")
        editor.undo()
        #expect(editor.failure == nil, "\(editor.failure ?? "unknown")")
        #expect(saved.count == 2)
        try peer.applyUpdate(try #require(saved.last).update)
        #expect(String(editor.text.characters).isEmpty)
        #expect(String(try peer.richProseProjection().text.characters).isEmpty)
        editor.redo()
        #expect(editor.failure == nil && saved.count == 3)
        try peer.applyUpdate(try #require(saved.last).update)
        #expect(String(try peer.richProseProjection().text.characters) == "Hello\nWorld")
    }

    @Test("Retry persists the exact pending original before replaying an isolated peer update")
    func retry() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("Base", namespace: "pending-replay"))
        try peer.applyUpdate(document.encodeUpdate())
        _ = try replaceRich(peer, start: 0, end: 0, text: "Peer ")
        let incoming = try peer.encodeUpdate()
        var fail = true, attempts: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: {
            attempts.append($0)
            if fail { throw SaveFailure.disk }
        })
        editor.edit(AttributedString("Base Draft"))
        let original = try #require(attempts.first)
        #expect(editor.hasUnpersistedTransaction && attempts.count == 1)
        // The peer update waits behind the unsaved local edit instead of rebasing it.
        try editor.applyRemoteUpdate(incoming)
        #expect(String(editor.text.characters) == "Base Draft")
        // A still-failing save must not replay over, replace or discard its original.
        editor.retryPersistence()
        #expect(attempts.count == 2 && attempts.allSatisfy { $0 == original })
        #expect(editor.hasUnpersistedTransaction && String(editor.text.characters) == "Base Draft")
        fail = false
        editor.retryPersistence()
        #expect(editor.failure == nil && !editor.hasUnpersistedTransaction)
        #expect(attempts.count == 3 && attempts.allSatisfy { $0 == original })
        #expect(String(editor.text.characters) == "Peer Base Draft")
        editor.retryPersistence()
        #expect(attempts.count == 3)
    }

    @Test("Session undo and redo preserve a peer's later edit")
    func remoteUndo() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument( "A", namespace: "native-owner-test"))
        try peer.applyUpdate(seed)
        var saved: [RelayMarkLocalTransaction] = []
        try initializeIfEmpty(document)
        try peer.applyUpdate(document.encodeUpdate())
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0) })
        editor.edit(AttributedString("AB"))
        try peer.applyUpdate(try #require(saved.last).update)
        let remote = try replaceRich(peer, start: 0, end: 0, text: "C")
        try editor.applyRemoteUpdate(remote)
        editor.undo()
        #expect(editor.failure == nil)
        try peer.applyUpdate(try #require(saved.last).update)
        #expect(String(editor.text.characters) == "CA")
        #expect(String(try peer.richProseProjection().text.characters) == "CA")
        editor.redo()
        #expect(editor.failure == nil && saved.count == 3)
        try peer.applyUpdate(try #require(saved.last).update)
        #expect(String(editor.text.characters) == "CAB")
        #expect(String(try peer.richProseProjection().text.characters) == "CAB")
    }

    @Test("A cross-paragraph native mark saves once and undo preserves a concurrent peer edit")
    func formattingWithPeerEdit() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("Hello\n\nWorld", namespace: "native-owner-test"))
        try peer.applyUpdate(seed)
        var saved: [RelayMarkLocalTransaction] = []
        try initializeIfEmpty(document)
        try peer.applyUpdate(document.encodeUpdate())
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0) })
        let baseline = editor.text
        var candidate = baseline
        candidate.inlinePresentationIntent = .stronglyEmphasized
        editor.editFormatting(candidate, command: .init(baseline: baseline,
            range: NSRange(location: 0, length: 11), mark: .bold))
        #expect(editor.failure == nil && saved.count == 1, "\(editor.failure ?? "unknown")")
        try peer.applyUpdate(try #require(saved.first).update)
        let formatted = try peer.richProseProjection().text
        #expect(RelayNativeRichEdit.formattingComparable(relayPaperInlineSemantics(formatted)) ==
            RelayNativeRichEdit.formattingComparable(relayPaperInlineSemantics(candidate)))
        try editor.applyRemoteUpdate(replaceRich(peer, start: 11, end: 11, text: "!"))
        editor.undo()
        #expect(editor.failure == nil && saved.count == 2)
        try peer.applyUpdate(try #require(saved.last).update)
        let afterUndo = try peer.richProseProjection().text
        #expect(String(afterUndo.characters) == "Hello\nWorld!")
        #expect(relayPaperInlineSemantics(afterUndo) == relayPaperInlineSemantics(AttributedString("Hello\nWorld!")))
        editor.redo()
        #expect(editor.failure == nil && saved.count == 3)
        try peer.applyUpdate(try #require(saved.last).update)
        #expect(String(editor.text.characters) == "Hello\nWorld!")
        let afterRedo = try peer.richProseProjection().text
        #expect(relayPaperInlineSemantics(afterRedo) == relayPaperInlineSemantics(editor.text))
    }

    @Test("Native selection and peer awareness use portable Yjs anchors")
    func selectionPresence() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument( "Hello", namespace: "native-owner-test"))
        try peer.applyUpdate(seed)
        try initializeIfEmpty(document)
        try peer.applyUpdate(document.encodeUpdate())
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        editor.setNativeSelection(NSRange(location: 1, length: 2))
        let range = try #require(try editor.selectionRelativeRange())
        #expect(try editor.resolveRelativeRange(range) == NSRange(location: 1, length: 2))
        let anchor = try peer.anchor(path: [0, 0], index: 2)
        let update = try peer.presence.setPresence(name: "Peer", anchor: anchor, head: anchor)
        try document.presence.applyPresence(update, origin: "channel")
        try editor.refreshPresence()
        #expect(editor.remoteSelections.count == 1)
        #expect(editor.remoteSelections.first?.caretLocation == 2)
        try document.presence.removePresence(origin: "channel")
        try editor.refreshPresence()
        #expect(editor.remoteSelections.isEmpty)
    }

    @Test("Marked text remains private until one committed native update")
    func compositionCommit() throws {
        let document = RelayMarkNativeDocument()
        var saved: [RelayMarkLocalTransaction] = []
        try initializeIfEmpty(document)
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0) })
        let token = try editor.beginComposition()
        #expect(String(try document.richProseProjection().text.characters).isEmpty)
        try editor.commitComposition(AttributedString("こんにちは"), from: token)
        #expect(saved.count == 1 && editor.failure == nil)
        #expect(String(try document.richProseProjection().text.characters) == "こんにちは")
    }

    @Test("An update missing its predecessors waits read-only and completes when they arrive")
    func incompleteRemoteUpdate() throws {
        let source = RelayMarkNativeDocument()
        let seed = try source.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("Human", namespace: "peer-missing-seed"))
        let suffix = try replaceRich(source, start: 5, end: 5, text: "!")
        let document = RelayMarkNativeDocument()
        try initializeIfEmpty(document)
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let shown = editor.text
        try editor.applyRemoteUpdate(suffix)
        #expect(!editor.isEditable && editor.text == shown)
        try editor.applyRemoteUpdate(seed)
        #expect(document.integrationStatus().isComplete)
        #expect(String(editor.text.characters).contains("Human!"))
    }

    #if os(macOS)
    @Test("The shared native text view mounts a native authored editor")
    func nativeTextViewMount() throws {
        let document = RelayMarkNativeDocument()
        try initializeIfEmpty(document)
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Authored paper")
        #expect(view.editingSession === editor)
        #expect(view.string.isEmpty)
        coordinator.retire(view)
        #expect(view.editingSession == nil)
    }

    @Test("AppKit marked candidates stay private and final input saves once")
    func nativeTextViewComposition() async throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument( "Alpha", namespace: "native-owner-test"))
        let baseline = try document.encodeUpdate()
        var saved: [RelayMarkLocalTransaction] = []
        try initializeIfEmpty(document)
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Authored IME")
        defer { editor.invalidate(); coordinator.retire(view) }
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(saved.isEmpty)
        #expect(try document.encodeUpdate() == baseline)
        view.insertText("日本🌍", replacementRange: NSRange(location: NSNotFound, length: 0))
        for _ in 0..<8 { await Task.yield() }
        try editor.finishNativeComposition()
        #expect(editor.failure == nil && saved.count == 1)
        #expect(String(try document.richProseProjection().text.characters) == "Alpha日本🌍")
    }
    #endif

    @Test("Fresh canonical paragraphs support authored rich marks")
    func freshRichFormatting() throws {
        let document = RelayMarkNativeDocument()
        try initializeIfEmpty(document)
        var saved: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0) })
        var candidate = AttributedString("Bold")
        candidate.inlinePresentationIntent = .stronglyEmphasized
        editor.edit(candidate)
        #expect(editor.failure == nil && saved.count == 1)
        #expect(String(editor.text.characters) == "Bold")
        #expect(editor.text.runs.first?.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
    }
}
