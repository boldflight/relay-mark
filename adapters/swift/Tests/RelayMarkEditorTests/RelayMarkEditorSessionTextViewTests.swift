#if os(macOS)
import AppKit
import Foundation
@testable import RelayMarkEditor
import RelayMarkCollaboration
import RelayMarkEditorCore
import RelayMarkNativeCollaboration
import RelayMarkSwift
import Testing

/// The session's native text view on AppKit; the session's own behavior is
/// tested headless in RelayMarkEditorCoreTests.
@MainActor @Suite("Native authored editor text view")
struct RelayMarkEditorSessionTextViewTests {
    private func initializeIfEmpty(_ document: RelayMarkNativeDocument) throws {
        let snapshot = try #require(try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
        if (snapshot["children"] as? [Any])?.isEmpty == true {
            _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("", namespace: "native-owner-test"))
        }
    }

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
}
#endif
