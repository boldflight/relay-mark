import Foundation
@testable import RelayMarkEditor
import Testing
#if os(macOS)
import AppKit
#endif
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkSwift

@MainActor
struct RelayMarkEditorQuoteEditorTests {
    private func document(includePeerParagraph: Bool = false) throws -> RelayMarkNativeDocument {
        let doc = RelayMarkNativeDocument()
        _ = try doc.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            "> **Quoted 🌍 text**" + (includePeerParagraph ? "\n\nOther" : ""), namespace: "canonical-quote-editor"))
        return doc
    }
    private func bold(_ text: String) -> AttributedString {
        var result = AttributedString(text); result.inlinePresentationIntent = .stronglyEmphasized; return result
    }



    #if os(macOS)


    @Test func nativeEndReturnThenTypingPreservesQuoteMarksAnchorsAndReopens() throws {
        _ = NSApplication.shared
        let doc = try document(), seed = try doc.encodeUpdate()
        let anchor = try doc.anchor(path: [0, 0, 0], index: 12)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: doc, persist: { saved.append($0.update) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Quote")
        editor.setNativeSelection(NSRange(location: 14, length: 0)); coordinator.update(view)
        view.insertNewline(nil)
        #expect(editor.failure == nil && saved.count == 1)
        #expect(String(editor.text.characters) == "Quoted 🌍 text\n")
        #expect(editor.nativeSelection == NSRange(location: 15, length: 0))
        coordinator.update(view)
        view.insertText("Next Ω", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.failure == nil && saved.count == 2, "\(editor.failure ?? "none")")
        #expect(String(editor.text.characters) == "Quoted 🌍 text\nNext Ω")
        #expect(editor.text.runs.last?.inlinePresentationIntent == .stronglyEmphasized)
        #expect(editor.fallbackEdits == 0, "The first text in the new paragraph took a whole-paper path")
        #expect(try doc.resolve(anchor: anchor)?.path == [0, 0, 0] && doc.resolve(anchor: anchor)?.index == 12)
        editor.undo(); #expect(String(editor.text.characters) == "Quoted 🌍 text\n")
        editor.undo(); #expect(String(editor.text.characters) == "Quoted 🌍 text")
        editor.redo(); editor.redo()
        let reopened = RelayMarkNativeDocument(); try reopened.applyUpdate(seed)
        for update in saved { try reopened.applyUpdate(update) }
        #expect(try reopened.snapshot() == doc.snapshot() && reopened.richProseProjection().isEditable)
        let before = try doc.encodeUpdate()
        coordinator.update(view); view.insertNewline(nil)
        #expect(try doc.encodeUpdate() != before)
    }

    @Test func markedTextCommittedInANewParagraphIsItsFirstText() async throws {
        _ = NSApplication.shared
        let doc = try document()
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: doc, persist: { saved.append($0.update) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Quote")
        defer { coordinator.retire(view) }
        editor.setNativeSelection(NSRange(location: 14, length: 0)); coordinator.update(view)
        view.insertNewline(nil)
        view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.insertText("日本", replacementRange: NSRange(location: NSNotFound, length: 0))
        for _ in 0..<8 { await Task.yield() }
        try editor.finishNativeComposition()
        #expect(editor.failure == nil && String(editor.text.characters) == "Quoted 🌍 text\n日本")
        #expect(editor.fallbackEdits == 0, "Committed marked text in an empty paragraph took a whole-paper path")
        #expect(view.string == String(editor.text.characters))
    }

    @Test func quotedTypingMarksSurviveAnUnrelatedPeerEdit() throws {
        _ = NSApplication.shared
        let doc = try document(includePeerParagraph: true), peer = RelayMarkNativeDocument()
        try peer.applyUpdate(doc.encodeUpdate())
        var saved: [Data] = [], transactions: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: doc, persist: { saved.append($0.update); transactions.append($0) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Quote")
        editor.setNativeSelection(NSRange(location: 14, length: 0)); coordinator.update(view)
        view.insertNewline(nil)
        let peerText = String(try peer.richProseProjection().text.characters) as NSString
        let other = peerText.range(of: "Other")
        let change = try RelayMarkNativeRichEditing.replace(document: peer,
            range: NSRange(location: other.location, length: 0), runs: [("Peer ", [:])], expectedSnapshot: peer.snapshot())
        try editor.applyRemoteUpdate(change.update); coordinator.update(view)
        view.insertText("Next Ω", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.failure == nil && saved.count == 2)
        #expect(String(editor.text.characters) == "Quoted 🌍 text\nNext Ω\nPeer Other")
        #expect(editor.text.runs.contains { String(editor.text[$0.range].characters).contains("Next Ω") && $0.inlinePresentationIntent == .stronglyEmphasized })
        editor.setNativeSelection(NSRange(location: String(editor.text.characters).utf16.count, length: 0))
        coordinator.update(view); view.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.failure == nil && String(editor.text.characters).hasSuffix("Peer Other!"))
        #expect(editor.text.runs.last?.inlinePresentationIntent?.contains(.stronglyEmphasized) != true)

    }

    @Test func nativeEmptyQuoteCanBeRetypedWithoutUnwrapping() throws {
        _ = NSApplication.shared
        let doc = try document(), quote = try doc.anchor(path: [0], index: 0)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: doc, persist: { saved.append($0.update) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Quote")
        editor.setNativeSelection(NSRange(location: 0, length: String(editor.text.characters).utf16.count)); coordinator.update(view)
        view.deleteBackward(nil)
        #expect(editor.failure == nil && saved.count == 1)
        coordinator.update(view)
        view.insertText("New Ω", replacementRange: NSRange(location: 0, length: 0))
        #expect(editor.failure == nil && saved.count == 2)
        #expect(String(editor.text.characters) == "New Ω")
        let tree = try #require(JSONSerialization.jsonObject(with: doc.snapshot()) as? [String: Any])
        let blocks = try #require(tree["children"] as? [[String: Any]])
        #expect(blocks.count == 1 && blocks[0]["name"] as? String == "blockquote")
        #expect(try doc.resolve(anchor: quote)?.path == [0])
    }


    #endif
}
