import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkSwift

@MainActor
struct RelayMarkEditorListStartEditorTests {
    private func document() throws -> RelayMarkNativeDocument {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            "- Outer\n\n  3. Nested 🌍 text\n\n- Sibling", namespace: "canonical-list-start"))
        return document
    }
    private func selectNested(_ editor: RelayMarkEditorSession, _ document: RelayMarkNativeDocument) throws {
        editor.setNativeSelection(NSRange(location: try document.richProseProjection().blockRanges[1].location + 2, length: 0))
    }
    @Test func startChangePersistsMarkersAnchorsSelectionAndUndo() throws {
        let document = try document(), peer = RelayMarkNativeDocument()
        let seed = try document.encodeUpdate(); try peer.applyUpdate(seed)
        let anchor = try document.anchor(path: [0, 0, 1, 0, 0, 0], index: 10)
        var updates: [Data] = [], transactions: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { updates.append($0.update); transactions.append($0) })
        try selectNested(editor, document)
        let selected = editor.nativeSelection, original = String(editor.text.characters)
        let review = try editor.prepareListStartEdit()
        #expect(review.start == 3)
        try editor.applyListStart(7, review: review)
        #expect(updates.count == 1 && editor.failure == nil)

        #expect(String(editor.text.characters) == original && editor.nativeSelection == selected)
        #expect(editor.text.runs.compactMap { NativeProseCodec.listMarker($0.presentationIntent)?.label } == ["•", "7.", "•"])
        #expect(NativeProseCodec.value(NativeProseCodec.attributed(editor.text)) == editor.text)
        #expect(try document.resolve(anchor: anchor)?.index == 10)
        #expect(try document.resolve(anchor: anchor)?.path == [0, 0, 1, 0, 0, 0])
        try peer.applyUpdate(updates[0])
        #expect(try JSONSerialization.jsonObject(with: peer.snapshot()) as? NSDictionary == JSONSerialization.jsonObject(with: document.snapshot()) as? NSDictionary)
        editor.undo(); try selectNested(editor, document); #expect(try editor.prepareListStartEdit().start == 3)
        editor.redo(); try selectNested(editor, document); #expect(try editor.prepareListStartEdit().start == 7)
        let reopened = RelayMarkNativeDocument(); try reopened.applyUpdate(seed)
        for update in updates { try reopened.applyUpdate(update) }
        #expect(try reopened.snapshot() == document.snapshot())
    }
    @Test func staleSelectionPeerUpdateRevocationAndIMEAreNonmutating() throws {
        let doc = try document()
        var allowed = true, updates: [Data] = []
        let editor = try RelayMarkEditorSession(document: doc, canEdit: { allowed }, persist: { updates.append($0.update) })
        try selectNested(editor, doc)
        let review = try editor.prepareListStartEdit(), before = try doc.encodeUpdate()
        for start in [0, -1, 1_000_001] { #expect(throws: (any Error).self) { try editor.applyListStart(start, review: review) } }
        editor.setNativeSelection(NSRange(location: 1, length: 0))
        #expect(throws: (any Error).self) { try editor.prepareListStartEdit() }
        #expect(throws: (any Error).self) { try editor.applyListStart(7, review: review) }
        try selectNested(editor, doc)
        let composition = try editor.beginComposition()
        #expect(throws: (any Error).self) { try editor.applyListStart(7, review: review) }
        editor.cancelComposition(composition)
        allowed = false
        #expect(throws: (any Error).self) { try editor.applyListStart(7, review: review) }
        #expect(try doc.encodeUpdate() == before && updates.isEmpty)
        allowed = true
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(before)
        try editor.applyRemoteUpdate(peer.insertText("Peer ", at: 0, path: [0, 1, 0, 0]))
        let afterRemote = try doc.encodeUpdate()
        #expect(throws: (any Error).self) { try editor.applyListStart(7, review: review) }
        #expect(try doc.encodeUpdate() == afterRemote && updates.isEmpty)
        let fresh = try editor.prepareListStartEdit()
        editor.invalidate()
        #expect(throws: (any Error).self) { try editor.applyListStart(7, review: fresh) }
    }
    @Test func rootOrderedListUsesDefaultStartAndNestedBulletDoesNotSelectAncestor() throws {
        let doc = RelayMarkNativeDocument()
        _ = try doc.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            "1. Outer\n\n   - Nested 🌍 text\n\n2. Sibling", namespace: "canonical-root-list"))
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: doc, persist: { saved.append($0.update) })
        try selectNested(editor, doc)
        #expect(throws: (any Error).self) { try editor.prepareListStartEdit() }
        editor.setNativeSelection(NSRange(location: 1, length: 0))
        let review = try editor.prepareListStartEdit()
        #expect(review.start == 1)
        try editor.applyListStart(1, review: review)
        #expect(saved.isEmpty)
        try editor.applyListStart(12, review: review)
        #expect(editor.text.runs.compactMap { NativeProseCodec.listMarker($0.presentationIntent)?.label } == ["12.", "•", "13."])
        #expect(saved.count == 1)
    }

    @Test func failedPersistenceRetainsExactAttributeUpdateForRetry() throws {
        struct DiskFailure: Error {}
        let doc = try document(), seed = try doc.encodeUpdate()
        var attempts: [Data] = [], fail = true
        let editor = try RelayMarkEditorSession(document: doc, persist: {
            attempts.append($0.update); if fail { throw DiskFailure() }
        })
        try selectNested(editor, doc)
        let review = try editor.prepareListStartEdit()
        try editor.applyListStart(9, review: review)
        #expect(editor.failure != nil && attempts.count == 1)
        #expect(throws: (any Error).self) { try editor.applyListStart(10, review: review) }
        fail = false; editor.retryPersistence()
        #expect(attempts.count == 2 && attempts[0] == attempts[1] && editor.failure == nil)
        let reopened = RelayMarkNativeDocument(); try reopened.applyUpdate(seed); try reopened.applyUpdate(attempts[1])
        #expect(try reopened.snapshot() == doc.snapshot())
    }
}
