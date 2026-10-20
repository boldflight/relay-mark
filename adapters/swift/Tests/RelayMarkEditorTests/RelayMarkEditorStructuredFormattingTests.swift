import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkCollaboration
import RelayMarkSwift
import RelayMarkNativeCollaboration

@MainActor
struct RelayMarkEditorStructuredFormattingTests {
    // Existing real Chromium fixtures from RelayMark structured-v1.json.
    private let seeds: [String: String] = [
        "headings": "AR6lvbWuAwAHAQdkZWZhdWx0AwdoZWFkaW5nBwClvbWuAwAGBAClvbWuAwEOSGVhZGluZyAxIPCfjI0oAKW9ta4DAAVsZXZlbAF9ASgApb21rgMACWhlYWRpbmdJZAF3CHN0YWJsZS0xh6W9ta4DAAMHaGVhZGluZwcApb21rgMQBgQApb21rgMRDkhlYWRpbmcgMiDwn4yNKAClvbWuAxAFbGV2ZWwBfQIoAKW9ta4DEAloZWFkaW5nSWQBdwhzdGFibGUtMoelvbWuAxADB2hlYWRpbmcHAKW9ta4DIAYEAKW9ta4DIQ5IZWFkaW5nIDMg8J+MjSgApb21rgMgBWxldmVsAX0DKAClvbWuAyAJaGVhZGluZ0lkAXcIc3RhYmxlLTOHpb21rgMgAwdoZWFkaW5nBwClvbWuAzAGBAClvbWuAzEOSGVhZGluZyA0IPCfjI0oAKW9ta4DMAVsZXZlbAF9BCgApb21rgMwCWhlYWRpbmdJZAF3CHN0YWJsZS00h6W9ta4DMAMHaGVhZGluZwcApb21rgNABgQApb21rgNBDkhlYWRpbmcgNSDwn4yNKAClvbWuA0AFbGV2ZWwBfQUoAKW9ta4DQAloZWFkaW5nSWQBdwhzdGFibGUtNYelvbWuA0ADB2hlYWRpbmcHAKW9ta4DUAYEAKW9ta4DUQ5IZWFkaW5nIDYg8J+MjSgApb21rgNQBWxldmVsAX0GKAClvbWuA1AJaGVhZGluZ0lkAXcIc3RhYmxlLTYA",
        "bullet-ordered": "AQ+K5uD9AgAHAQdkZWZhdWx0AwpidWxsZXRMaXN0BwCK5uD9AgADCGxpc3RJdGVtBwCK5uD9AgEDCXBhcmFncmFwaAcAiubg/QICBgQAiubg/QIDBU91dGVyh4rm4P0CAgMLb3JkZXJlZExpc3QHAIrm4P0CCQMIbGlzdEl0ZW0HAIrm4P0CCgMJcGFyYWdyYXBoBwCK5uD9AgsGBACK5uD9AgwQTmVzdGVkIPCfjI0gdGV4dCgAiubg/QIJBXN0YXJ0AX0Dh4rm4P0CAQMIbGlzdEl0ZW0HAIrm4P0CHAMJcGFyYWdyYXBoBwCK5uD9Ah0GBACK5uD9Ah4HU2libGluZwA=",
        "ordered-bullet": "AQ/xpb6KBAAHAQdkZWZhdWx0AwtvcmRlcmVkTGlzdAcA8aW+igQAAwhsaXN0SXRlbQcA8aW+igQBAwlwYXJhZ3JhcGgHAPGlvooEAgYEAPGlvooEAwVPdXRlcofxpb6KBAIDCmJ1bGxldExpc3QHAPGlvooECQMIbGlzdEl0ZW0HAPGlvooECgMJcGFyYWdyYXBoBwDxpb6KBAsGBADxpb6KBAwQTmVzdGVkIPCfjI0gdGV4dIfxpb6KBAEDCGxpc3RJdGVtBwDxpb6KBBsDCXBhcmFncmFwaAcA8aW+igQcBgQA8aW+igQdB1NpYmxpbmcoAPGlvooEAAVzdGFydAF9BwA=",
    ]
    private func document(_ name: String) throws -> RelayMarkNativeDocument {
        let document = RelayMarkNativeDocument()
        let seed = try #require(seeds[name])
        try document.applyUpdate(try #require(Data(base64Encoded: seed)))
        return try canonicalStructuredFixture(document, namespace: "structured-" + name)
    }
    private func structure(_ document: RelayMarkNativeDocument) throws -> Data {
        func strip(_ node: [String: Any]) -> [String: Any] {
            var result = node; result.removeValue(forKey: "delta")
            if let children = node["children"] as? [[String: Any]] { result["children"] = children.map(strip) }
            return result
        }
        return try JSONSerialization.data(withJSONObject: strip(try #require(try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])), options: [.sortedKeys])
    }

    @Test(arguments: ["headings", "bullet-ordered", "ordered-bullet"])
    func existingStructuredTextFormattingIMEAndRemoteUndo(name: String) throws {
        let document = try document(name), peer = RelayMarkNativeDocument()
        try peer.applyUpdate(document.encodeUpdate())
        let projection = try document.proseProjection(), row = name == "headings" ? 0 : 1
        let range = projection.blockRanges[row], path = projection.blockPaths[row] + [0]
        let anchor = try document.anchor(path: path, index: 4)
        let baselineStructure = try structure(document)
        var saved: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0) })
        editor.setNativeSelection(range)
        #expect(editor.canFormatInlineSelection && editor.canFormatInlineCodeSelection)
        editor.toggleInlineMark(.strike); editor.toggleInlineMark(.code)
        #expect(editor.failure == nil && saved.count == 2)
        #expect(editor.nativeSelection == range)
        for update in saved { try peer.applyUpdate(update.update) }
        let token = try editor.beginComposition()
        var candidate = editor.text
        let plain = String(candidate.characters)
        let replacement = try #require(Range(NSRange(location: range.location + 1, length: 1), in: plain))
        let lower = try #require(AttributedString.Index(replacement.lowerBound, within: candidate))
        let upper = try #require(AttributedString.Index(replacement.upperBound, within: candidate))
        var inserted = AttributedString("あ"); inserted.inlinePresentationIntent = .code
        inserted.presentationIntent = candidate[lower..<upper].presentationIntent
        candidate.replaceSubrange(lower..<upper, with: inserted)
        try editor.commitComposition(candidate, from: token)
        #expect(editor.failure == nil && saved.count == 3)
        try peer.applyUpdate(try #require(saved.last).update)
        #expect(try document.resolve(anchor: anchor)?.path == path)
        #expect(try document.resolve(anchor: anchor)?.index == 4)
        #expect(try structure(document) == baselineStructure)
        #expect(NativeProseCodec.value(NativeProseCodec.attributed(editor.text)) == editor.text)
        // A peer edits another existing item/heading while local undo remains
        // scoped to our formatting and composition transactions.
        let peerPath = try #require(projection.blockPaths.last) + [0]
        try editor.applyRemoteUpdate(try peer.insertText("Peer ", at: 0, path: peerPath))
        editor.undo(); try peer.applyUpdate(try #require(saved.last).update)
        #expect(String(editor.text.characters).contains("Peer "))
        #expect(try structure(document) == baselineStructure)
        editor.undo(); try peer.applyUpdate(try #require(saved.last).update)
        #expect(editor.text.runs.contains { ($0.inlinePresentationIntent ?? []).contains(.strikethrough) })
        #expect(String(editor.text.characters).contains("Peer "))
        #expect(try structure(document) == baselineStructure)
        editor.redo(); try peer.applyUpdate(try #require(saved.last).update)
        editor.redo(); try peer.applyUpdate(try #require(saved.last).update)
        #expect(editor.failure == nil)
        #expect(try JSONSerialization.jsonObject(with: document.snapshot()) as? NSDictionary == JSONSerialization.jsonObject(with: peer.snapshot()) as? NSDictionary)
    }


}

// Historical browser bytes remain unchanged above. Editable session tests use
// the existing finite importer to install their identified canonical document.
@MainActor
func canonicalStructuredFixture(_ original: RelayMarkNativeDocument, namespace: String) throws -> RelayMarkNativeDocument {
    let imported = try #require(try JSONSerialization.jsonObject(with:
        RelayMarkSourceCodec.importDocumentSnapshot(original.snapshot(), namespace: namespace)) as? [String: Any])
    let authored = try #require(imported["document"] as? [String: Any])
    let document = RelayMarkNativeDocument()
    _ = try document.initializeDocument(authoredAST: JSONSerialization.data(withJSONObject: authored))
    return document
}
