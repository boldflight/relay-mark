import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkCollaboration
import RelayMarkSwift
import RelayMarkNativeCollaboration

@MainActor
struct RelayMarkEditorBlockInsertionTests {
    struct Insertion: Sendable {
        let kind: String
        let position: String
    }
    nonisolated private static let operations = ["callout", "codeBlock"].flatMap { kind in
        ["middle", "selection", "empty"].map { Insertion(kind: kind, position: $0) }
    }
    private func document(empty: Bool = false) throws -> RelayMarkNativeDocument {
        let document = RelayMarkNativeDocument()
        var ast = try #require(JSONSerialization.jsonObject(with: RelayMarkSourceCodec.parseDocument(
            "Before 🌍\n\nAfter **Ω**", namespace: "native-block-insertion")) as? [String: Any])
        if empty {
            var blocks = try #require(ast["blocks"] as? [[String: Any]])
            blocks[0]["content"] = []; ast["blocks"] = blocks
        }
        _ = try document.initializeDocument(authoredAST: JSONSerialization.data(withJSONObject: ast))
        return document
    }
    private func insert(_ kind: String, into editor: RelayMarkEditorSession) {
        if kind == "callout" { editor.insertCallout() }
        else { editor.insertCodeBlock() }
    }

    @Test(arguments: operations)
    func insertedBlockPreservesPeerRichContentAndUndo(operation: Insertion) throws {
        let document = try document(empty: operation.position == "empty"), peer = RelayMarkNativeDocument()
        try peer.applyUpdate(document.encodeUpdate())
        var saved: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0) })
        let original = String(editor.text.characters)
        let originalTree = try #require(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
        let originalBlocks = try #require(originalTree["children"] as? [[String: Any]])
        let suffix = try #require(originalBlocks.last)
        let suffixID = try #require((suffix["attributes"] as? [String: Any])?["relaymarkId"] as? String)
        switch operation.position {
        case "selection": editor.setNativeSelection(NSRange(location: 0, length: "Before 🌍".utf16.count))
        case "empty": editor.setNativeSelection(NSRange(location: 0, length: 0))
        default: editor.setNativeSelection(NSRange(location: 2, length: 0))
        }
        insert(operation.kind, into: editor)
        #expect(editor.failure == nil && saved.count == 1)
        let command = try #require(saved.first)
        let snapshot = try #require(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
        let blocks = try #require(snapshot["children"] as? [[String: Any]])
        let inserted = try #require(blocks.first(where: { $0["name"] as? String == operation.kind }))
        let attributes = try #require(inserted["attributes"] as? [String: Any])
        #expect((attributes["relaymarkId"] as? String)?.isEmpty == false)
        #expect((attributes["relaymarkId"] as? String) != suffixID)
        let retainedSuffix = try #require(blocks.first { ($0["attributes"] as? [String: Any])?["relaymarkId"] as? String == suffixID })
        #expect(retainedSuffix as NSDictionary == suffix as NSDictionary)
        if operation.kind == "callout" {
            #expect(attributes["tone"] as? String == "neutral" && attributes["emphasis"] as? String == "soft")
            #expect((inserted["children"] as? [[String: Any]])?.first?["name"] as? String == "paragraph")
        } else {
            #expect(attributes["language"] == nil || attributes["language"] is NSNull)
        }
        let insertionIndex = try #require(blocks.firstIndex(where: { $0["name"] as? String == operation.kind }))
        let projection = try document.richProseProjection()
        // Actual maintained TipTap insertContentAt keeps the fitted suffix
        // caret for middle insertion; empty/selected paragraphs land inside.
        let insertionPath = operation.position == "middle" ? [insertionIndex + 1]
            : operation.kind == "callout" ? [insertionIndex, 0] : [insertionIndex]
        let insertionRow = try #require(projection.blockPaths.firstIndex(of: insertionPath))
        #expect(editor.nativeSelection == NSRange(location: projection.blockRanges[insertionRow].location, length: 0))
        if operation.position == "empty" { #expect(blocks.count == 2 && blocks[0]["name"] as? String == operation.kind) }
        try peer.applyUpdate(command.update)
        let offset = (String(try peer.richProseProjection().text.characters) as NSString).range(of: "After Ω").location
        let change = try RelayMarkNativeRichEditing.replace(document: peer, range: NSRange(location: offset, length: 0),
            runs: [(text: "Peer ", attributes: [:])], expectedSnapshot: peer.snapshot())
        try editor.applyRemoteUpdate(change.update)
        #expect(editor.text.runs.contains { String(editor.text[$0.range].characters).contains("Ω") && ($0.inlinePresentationIntent ?? []).contains(.stronglyEmphasized) })
        // Undo reverts only this editor's insertion; the peer's text stays.
        let restored = document, cold = editor
        cold.undo()
        #expect(cold.failure == nil && saved.count == 2)
        #expect(String(cold.text.characters) == original.replacingOccurrences(of: "After Ω", with: "Peer After Ω"))
        try peer.applyUpdate(try #require(saved.last).update)
        cold.redo()
        #expect(cold.failure == nil && saved.count == 3)
        try peer.applyUpdate(try #require(saved.last).update)
        #expect(try JSONSerialization.jsonObject(with: restored.snapshot()) as? NSDictionary == JSONSerialization.jsonObject(with: peer.snapshot()) as? NSDictionary)
        let markdown = try RelayMarkSourceCodec.projectDocumentMarkdown(RelayMarkSourceCodec.snapshotToDocument(restored.snapshot()))
        #expect(markdown.contains("Peer After **Ω**"))
        #expect(operation.kind == "callout" ? markdown.contains("@Callout(") : markdown.contains("```\n\n```"))

        if operation.position == "empty" {
            // New empty blocks must accept the next real native replacement;
            // editing an existing code leaf cannot establish this handoff.
            let beforeTyping = try restored.snapshot(), projected = try restored.richProseProjection()
            let path = operation.kind == "callout" ? [0, 0] : [0]
            let row = try #require(projected.blockPaths.firstIndex(of: path))
            let range = NSRange(location: projected.blockRanges[row].location, length: 0)
            let baseline = String(cold.text.characters), insertedText = "日本🌍"
            let expected = (baseline as NSString).replacingCharacters(in: range, with: insertedText)
            cold.setNativeSelection(range)
            cold.edit(AttributedString(expected), nativeReplacement: .init(baseline: baseline, range: range,
                replacement: insertedText), nativePaste: nil)
            #expect(cold.failure == nil && saved.count == 4)
            #expect(String(cold.text.characters) == expected)
            try peer.applyUpdate(try #require(saved.last).update)
            #expect(try JSONSerialization.jsonObject(with: restored.snapshot()) as? NSDictionary == JSONSerialization.jsonObject(with: peer.snapshot()) as? NSDictionary)
            cold.undo()
            #expect(cold.failure == nil && saved.count == 5)
            #expect(try JSONSerialization.jsonObject(with: restored.snapshot()) as? NSDictionary == JSONSerialization.jsonObject(with: beforeTyping) as? NSDictionary)
        }
    }

    @Test(arguments: ["callout", "codeBlock"])
    func readonlyAndComposingInsertionLeaveOriginalUntouched(kind: String) throws {
        let document = try document()
        var writes = 0
        let editor = try RelayMarkEditorSession(document: document, canEdit: { false }, persist: { _ in writes += 1 })
        editor.setNativeSelection(NSRange(location: 2, length: 0))
        let original = try document.encodeUpdate()
        insert(kind, into: editor)
        #expect(try document.encodeUpdate() == original && writes == 0)
        editor.invalidate()
        let composingDocument = try self.document()
        let composing = try RelayMarkEditorSession(document: composingDocument, persist: { _ in writes += 1 })
        composing.setNativeSelection(NSRange(location: 2, length: 0))
        let composingOriginal = try composingDocument.encodeUpdate()
        let token = try composing.beginComposition()
        insert(kind, into: composing)
        #expect(try composingDocument.encodeUpdate() == composingOriginal && writes == 0)
        composing.cancelComposition(token)
    }
}
