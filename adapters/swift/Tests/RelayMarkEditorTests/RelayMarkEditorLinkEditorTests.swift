import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkSwift

@MainActor
struct RelayMarkEditorLinkEditorTests {
    // Real Chromium community schemas before Link.setLink, retaining bold Unicode text.
    private let seeds: [String: String] = [
        "paragraph": "AQXlxbiTCQAHAQdkZWZhdWx0AwlwYXJhZ3JhcGgHAOXFuJMJAAYGAOXFuJMJAQRib2xkAnt9hOXFuJMJAhBMaW5rZWQg8J+MjSB0ZXh0huXFuJMJEARib2xkBG51bGwA",
        "heading": "AQbV85u6BQAHAQdkZWZhdWx0AwdoZWFkaW5nBwDV85u6BQAGBgDV85u6BQEEYm9sZAJ7fYTV85u6BQIQTGlua2VkIPCfjI0gdGV4dIbV85u6BRAEYm9sZARudWxsKADV85u6BQAFbGV2ZWwBfQIA",
        "bullet": "AQer5OHhCAAHAQdkZWZhdWx0AwpidWxsZXRMaXN0BwCr5OHhCAADCGxpc3RJdGVtBwCr5OHhCAEDCXBhcmFncmFwaAcAq+Th4QgCBgYAq+Th4QgDBGJvbGQCe32Eq+Th4QgEEExpbmtlZCDwn4yNIHRleHSGq+Th4QgSBGJvbGQEbnVsbAA=",
        "ordered": "AQjumazkDwAHAQdkZWZhdWx0AwtvcmRlcmVkTGlzdAcA7pms5A8AAwhsaXN0SXRlbQcA7pms5A8BAwlwYXJhZ3JhcGgHAO6ZrOQPAgYGAO6ZrOQPAwRib2xkAnt9hO6ZrOQPBBBMaW5rZWQg8J+MjSB0ZXh0hu6ZrOQPEgRib2xkBG51bGwoAO6ZrOQPAAVzdGFydAF9AwA="
    ]
    private func document(_ name: String = "paragraph") throws -> RelayMarkNativeDocument {
        let doc = RelayMarkNativeDocument()
        let source: String
        switch name {
        case "heading": source = "## **Linked 🌍 text**"
        case "bullet": source = "- **Linked 🌍 text**"
        case "ordered": source = "3. **Linked 🌍 text**"
        default: source = "**Linked 🌍 text**"
        }
        _ = try doc.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "canonical-link-" + name))
        return doc
    }
    private func format(_ doc: RelayMarkNativeDocument, range: NSRange, mark: String,
        attributes: [String: Any] = [:], enabled: Bool = true) throws {
        _ = try RelayMarkNativeRichEditing.format(document: doc, range: range, mark: mark,
            attributes: attributes, enabled: enabled, expectedSnapshot: doc.snapshot())
    }
    private let entity = "relay:entity/12345678-1234-4234-8234-123456789abc"

    @Test func sharedHostAuthoringPolicyFixtures() throws {
        struct Case: Decodable { let name: String; let input: String; let accepted: Bool }
        struct Fixture: Decodable { let version: Int; let cases: [Case] }
        let url = try #require(Bundle.module.url(forResource: "link-authoring-policy-v1", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        #expect(fixture.version == 1)
        for item in fixture.cases {
            #expect((RelayMarkLinkDestination.accepted(item.input) == item.input) == item.accepted, "\(item.name)")
        }
    }

    @Test(arguments: ["paragraph", "heading", "bullet", "ordered"])
    func linkDestinationEditRemovalPreservesMarksAnchorsUndoAndPeer(name: String) throws {
        let doc = try document(name), peer = RelayMarkNativeDocument()
        try peer.applyUpdate(doc.encodeUpdate())
        let projection = try doc.richProseProjection(), range = try #require(projection.blockRanges.first)
        let path = try #require(projection.textRanges(in: range).first).path
        let anchor = try doc.anchor(path: path, index: 10)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: doc, persist: { saved.append($0.update) })
        editor.setNativeSelection(range)
        try editor.applyLink(entity, review: editor.prepareLinkEdit())
        #expect(saved.count == 1 && editor.failure == nil)
        #expect(editor.text.runs.allSatisfy { $0.link?.absoluteString == entity && ($0.inlinePresentationIntent ?? []).contains(.stronglyEmphasized) })
        #expect(NativeProseCodec.value(NativeProseCodec.attributed(editor.text)) == editor.text)
        try editor.applyLink("https://example.org/changed", review: editor.prepareLinkEdit())
        try editor.applyLink(nil, review: editor.prepareLinkEdit())
        #expect(editor.text.runs.allSatisfy { $0.link == nil && ($0.inlinePresentationIntent ?? []).contains(.stronglyEmphasized) })
        for update in saved { try peer.applyUpdate(update) }
        #expect(try doc.resolve(anchor: anchor)?.path == path)
        #expect(try doc.resolve(anchor: anchor)?.index == 10)
        editor.undo(); try peer.applyUpdate(try #require(saved.last))
        #expect(editor.text.runs.allSatisfy { $0.link?.absoluteString == "https://example.org/changed" })
        editor.undo(); try peer.applyUpdate(try #require(saved.last))
        #expect(editor.text.runs.allSatisfy { $0.link?.absoluteString == entity })
        editor.redo(); try peer.applyUpdate(try #require(saved.last))
        #expect(try JSONSerialization.jsonObject(with: doc.snapshot()) as? NSDictionary == JSONSerialization.jsonObject(with: peer.snapshot()) as? NSDictionary)
    }

    @Test func staleSelectionRemoteEditAccountAndIMENeverMutate() throws {
        let doc = try document(), peer = RelayMarkNativeDocument()
        try peer.applyUpdate(doc.encodeUpdate())
        var allowed = true, saved = 0
        let editor = try RelayMarkEditorSession(document: doc, canEdit: { allowed }, persist: { _ in saved += 1 })
        editor.setNativeSelection(NSRange(location: 0, length: 6))
        let review = try editor.prepareLinkEdit(), original = try doc.encodeUpdate()
        for bad in ["javascript:alert(1)", "data:text/html,x", "//example.org", "https://user:password@example.org", "relay:entity/123", "relay:entity/12345678-1234-4234-8234-123456789ABC", "https://example.org/\n"] {
            #expect(throws: (any Error).self) { try editor.applyLink(bad, review: review) }
        }
        #expect(try doc.encodeUpdate() == original && saved == 0)
        let composition = try editor.beginComposition()
        #expect(throws: (any Error).self) { try editor.applyLink(entity, review: review) }
        editor.cancelComposition(composition)
        allowed = false
        #expect(throws: (any Error).self) { try editor.applyLink(entity, review: review) }
        allowed = true
        editor.setNativeSelection(NSRange(location: 1, length: 3))
        #expect(throws: (any Error).self) { try editor.applyLink(entity, review: review) }
        editor.setNativeSelection(NSRange(location: 0, length: 6))
        let change = try RelayMarkNativeRichEditing.replace(document: peer, range: NSRange(location: 0, length: 0),
            runs: [(text: "Peer ", attributes: ["bold": [:]])], expectedSnapshot: peer.snapshot())
        try editor.applyRemoteUpdate(change.update)
        let changed = try doc.encodeUpdate()
        #expect(throws: (any Error).self) { try editor.applyLink(entity, review: review) }
        #expect(try doc.encodeUpdate() == changed && saved == 0)
    }

    @Test func unsupportedLinkRequiresRecoveryWithoutChangingCanonicalContent() throws {
        let doc = try document(), original = try doc.encodeUpdate()
        #expect(throws: (any Error).self) {
            try format(doc, range: NSRange(location: 0, length: 14), mark: "link", attributes: ["href": "ftp://example.org/file"])
        }
        #expect(try doc.encodeUpdate() == original)
        let editor = try RelayMarkEditorSession(document: doc, persist: { _ in })
        editor.setNativeSelection(NSRange(location: 0, length: 14))
        let review = try editor.prepareLinkEdit()
        #expect(throws: (any Error).self) { try editor.applyLink("ftp://example.org/file", review: review) }
        #expect(try doc.encodeUpdate() == original)
        try editor.applyLink(entity, review: review)
        try editor.applyLink(nil, review: editor.prepareLinkEdit())
        #expect(editor.text.runs.allSatisfy { $0.link == nil && ($0.inlinePresentationIntent ?? []).contains(.stronglyEmphasized) })
    }

    @Test func exactLinkSaveRetryAndIMEReplacementPreserveDestination() throws {
        let doc = try document()
        var fail = true, attempts: [Data] = []
        let editor = try RelayMarkEditorSession(document: doc, persist: {
            attempts.append($0.update)
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
        })
        editor.setNativeSelection(NSRange(location: 0, length: 14))
        try editor.applyLink(entity, review: editor.prepareLinkEdit())
        #expect(editor.hasUnpersistedTransaction && !editor.isEditable)
        fail = false; editor.retryPersistence()
        #expect(attempts.count == 2 && attempts[0] == attempts[1])
        let composition = try editor.beginComposition()
        var candidate = editor.text
        let upper = candidate.characters.index(after: candidate.startIndex)
        var replacement = AttributedString("日")
        replacement.inlinePresentationIntent = .stronglyEmphasized
        replacement.link = URL(string: entity)
        replacement.presentationIntent = candidate[candidate.startIndex..<upper].presentationIntent
        candidate.replaceSubrange(candidate.startIndex..<upper, with: replacement)
        try editor.commitComposition(candidate, from: composition)
        #expect(editor.failure == nil && attempts.count == 3)
        #expect(editor.text.runs.allSatisfy { $0.link?.absoluteString == entity && ($0.inlinePresentationIntent ?? []).contains(.stronglyEmphasized) })
        editor.undo()
        #expect(String(editor.text.characters) == "Linked 🌍 text")
        #expect(editor.text.runs.allSatisfy { $0.link?.absoluteString == entity })
    }

    @Test func inlineCodeAndMixedLinkTargetsAreNotFlattened() throws {
        let doc = try document()
        try format(doc, range: NSRange(location: 0, length: 14), mark: "bold", enabled: false)
        try format(doc, range: NSRange(location: 0, length: 14), mark: "code")
        let editor = try RelayMarkEditorSession(document: doc, persist: { _ in })
        editor.setNativeSelection(NSRange(location: 0, length: 14))
        let before = try doc.encodeUpdate(), review = try editor.prepareLinkEdit()
        #expect(throws: (any Error).self) { try editor.applyLink(entity, review: review) }
        #expect(try doc.encodeUpdate() == before)
        let mixed = try document()
        try format(mixed, range: NSRange(location: 0, length: 6), mark: "link", attributes: ["href": "https://one.example"])
        try format(mixed, range: NSRange(location: 6, length: 8), mark: "link", attributes: ["href": "https://two.example"])
        let mixedEditor = try RelayMarkEditorSession(document: mixed, persist: { _ in })
        mixedEditor.setNativeSelection(NSRange(location: 0, length: 14))
        let mixedBefore = try mixed.encodeUpdate()
        #expect(throws: (any Error).self) { try mixedEditor.prepareLinkEdit() }
        #expect(try mixed.encodeUpdate() == mixedBefore)
        for url in ["http://example.org", "https://example.org/a?q=x#h", "mailto:person@example.org", entity] {
            #expect(RelayMarkLinkDestination.accepted(url) == url)
        }
    }
}
