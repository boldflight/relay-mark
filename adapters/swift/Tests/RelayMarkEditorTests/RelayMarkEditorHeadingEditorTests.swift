import Foundation
import Testing
import RelayMarkCollaboration
import RelayMarkSwift
import RelayMarkNativeCollaboration
@testable import RelayMarkEditor
#if os(macOS)
import AppKit
import SwiftUI
#endif

@MainActor
struct RelayMarkEditorHeadingEditorTests {
    // Actual Chromium fixtures from RelayMark ef0c008 structured-v1.json.
    private let headingSeed = "AR6lvbWuAwAHAQdkZWZhdWx0AwdoZWFkaW5nBwClvbWuAwAGBAClvbWuAwEOSGVhZGluZyAxIPCfjI0oAKW9ta4DAAVsZXZlbAF9ASgApb21rgMACWhlYWRpbmdJZAF3CHN0YWJsZS0xh6W9ta4DAAMHaGVhZGluZwcApb21rgMQBgQApb21rgMRDkhlYWRpbmcgMiDwn4yNKAClvbWuAxAFbGV2ZWwBfQIoAKW9ta4DEAloZWFkaW5nSWQBdwhzdGFibGUtMoelvbWuAxADB2hlYWRpbmcHAKW9ta4DIAYEAKW9ta4DIQ5IZWFkaW5nIDMg8J+MjSgApb21rgMgBWxldmVsAX0DKAClvbWuAyAJaGVhZGluZ0lkAXcIc3RhYmxlLTOHpb21rgMgAwdoZWFkaW5nBwClvbWuAzAGBAClvbWuAzEOSGVhZGluZyA0IPCfjI0oAKW9ta4DMAVsZXZlbAF9BCgApb21rgMwCWhlYWRpbmdJZAF3CHN0YWJsZS00h6W9ta4DMAMHaGVhZGluZwcApb21rgNABgQApb21rgNBDkhlYWRpbmcgNSDwn4yNKAClvbWuA0AFbGV2ZWwBfQUoAKW9ta4DQAloZWFkaW5nSWQBdwhzdGFibGUtNYelvbWuA0ADB2hlYWRpbmcHAKW9ta4DUAYEAKW9ta4DUQ5IZWFkaW5nIDYg8J+MjSgApb21rgNQBWxldmVsAX0GKAClvbWuA1AJaGVhZGluZ0lkAXcIc3RhYmxlLTYA"
    private let listSeed = "AQ+K5uD9AgAHAQdkZWZhdWx0AwpidWxsZXRMaXN0BwCK5uD9AgADCGxpc3RJdGVtBwCK5uD9AgEDCXBhcmFncmFwaAcAiubg/QICBgQAiubg/QIDBU91dGVyh4rm4P0CAgMLb3JkZXJlZExpc3QHAIrm4P0CCQMIbGlzdEl0ZW0HAIrm4P0CCgMJcGFyYWdyYXBoBwCK5uD9AgsGBACK5uD9AgwQTmVzdGVkIPCfjI0gdGV4dCgAiubg/QIJBXN0YXJ0AX0Dh4rm4P0CAQMIbGlzdEl0ZW0HAIrm4P0CHAMJcGFyYWdyYXBoBwCK5uD9Ah0GBACK5uD9Ah4HU2libGluZwA="
    private enum SaveFailure: Error { case disk }

    private func document() throws -> RelayMarkNativeDocument {
        let document = RelayMarkNativeDocument()
        let source = (1...6).map { String(repeating: "#", count: $0) + " Heading \($0) 🌍" }.joined(separator: "\n\n")
        var ast = try #require(JSONSerialization.jsonObject(with: RelayMarkSourceCodec.parseDocument(source, namespace: "canonical-heading-operations")) as? [String: Any])
        var blocks = try #require(ast["blocks"] as? [[String: Any]])
        for index in blocks.indices {
            var props = try #require(blocks[index]["props"] as? [String: Any])
            props["headingId"] = "stable-\(index + 1)"; blocks[index]["props"] = props
        }
        ast["blocks"] = blocks
        _ = try document.initializeDocument(authoredAST: JSONSerialization.data(withJSONObject: ast))
        return document
    }
    private func headingAttributes(_ document: RelayMarkNativeDocument) throws -> [String: Any] {
        let tree = try #require(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
        let children = try #require(tree["children"] as? [[String: Any]])
        return try #require(children[0]["attributes"] as? [String: Any])
    }

    @Test func sourceHeadingIdentitySurvivesNativeImportAndMarkdownReload() throws {
        let namespace = "native-source-heading-identity"
        let source = "## Original 🌍 {#h-stable}\n\n### **Renamed Ω** {#h-second}\n\n[Jump](#h-second)"
        let original = try RelayMarkSourceCodec.parseDocument(source, namespace: namespace)
        let ast = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        let blocks = try #require(ast["blocks"] as? [[String: Any]])
        #expect((blocks[0]["props"] as? [String: Any])?["headingId"] as? String == "h-stable")
        #expect((blocks[1]["props"] as? [String: Any])?["headingId"] as? String == "h-second")
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: original)
        let retained = try RelayMarkSourceCodec.snapshotToDocument(document.snapshot())
        #expect(try JSONSerialization.jsonObject(with: retained) as? NSDictionary == ast as NSDictionary)
        let markdown = try RelayMarkSourceCodec.projectDocumentMarkdown(retained)
        let reimported = try RelayMarkSourceCodec.parseDocument(markdown, namespace: namespace)
        #expect(try JSONSerialization.jsonObject(with: reimported) as? NSDictionary == ast as NSDictionary)
        let rendered = try RelayMarkSourceCodec.renderDocument(reimported)
        #expect(rendered.contains("<h2 id=\"h-stable\""))
        #expect(rendered.contains("<h3 id=\"h-second\""))
        #expect(!rendered.contains("{#"))
        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(document.encodeUpdate())
        #expect(try JSONSerialization.jsonObject(with: reopened.snapshot()) as? NSDictionary == JSONSerialization.jsonObject(with: document.snapshot()) as? NSDictionary)
        for literal in [#"## Literal \{#plain\}"#, "## `Code {#plain}`", "## **Marked {#plain}**"] {
            let parsed = try RelayMarkSourceCodec.parseDocument(literal, namespace: "literal-source-heading")
            let object = try #require(JSONSerialization.jsonObject(with: parsed) as? [String: Any])
            let heading = try #require((object["blocks"] as? [[String: Any]])?.first)
            #expect((heading["props"] as? [String: Any])?["headingId"] is NSNull)
            #expect(try JSONSerialization.jsonObject(with: RelayMarkSourceCodec.parseDocument(RelayMarkSourceCodec.projectDocumentMarkdown(parsed), namespace: "literal-source-heading")) as? NSDictionary == object as NSDictionary)
        }
    }

    @Test(arguments: ["#chapter", "#%63hapter"])
    func authoredHeadingFragmentLinkPreservesCommandPeerAndUndo(destination: String) throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            "## Chapter 🌍 {#chapter}\n\n**Jump 🌍**", namespace: "native-authored-fragment"))
        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(document.encodeUpdate())
        var saved: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0) })
        let range = (String(editor.text.characters) as NSString).range(of: "Jump 🌍")
        editor.setNativeSelection(range)
        let review = try editor.prepareLinkEdit(), before = try document.encodeUpdate()
        for invalid in ["#", "#bad target", "#<unsafe>", "#%", "#%00"] {
            #expect(throws: (any Error).self) { try editor.applyLink(invalid, review: review) }
        }
        #expect(try document.encodeUpdate() == before && saved.isEmpty)
        try editor.applyLink(destination, review: review)
        #expect(saved.count == 1 && editor.failure == nil)
        #expect(editor.text.runs.contains { $0.link?.absoluteString == destination && ($0.inlinePresentationIntent ?? []).contains(.stronglyEmphasized) })
        try peer.applyUpdate(try #require(saved.last).update)
        let peerChange = try RelayMarkNativeRichEditing.replace(document: peer,
            range: NSRange(location: 0, length: 0), runs: [(text: "Peer ", attributes: [:])], expectedSnapshot: peer.snapshot())
        try editor.applyRemoteUpdate(peerChange.update)
        editor.undo()
        #expect(String(editor.text.characters).hasPrefix("Peer Chapter 🌍"))
        #expect(editor.text.runs.allSatisfy { $0.link == nil })
        try peer.applyUpdate(try #require(saved.last).update)
        editor.redo()
        try peer.applyUpdate(try #require(saved.last).update)
        #expect(try JSONSerialization.jsonObject(with: document.snapshot()) as? NSDictionary == JSONSerialization.jsonObject(with: peer.snapshot()) as? NSDictionary)
        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(document.encodeUpdate())
        let retained = try RelayMarkSourceCodec.snapshotToDocument(reopened.snapshot())
        let html = try RelayMarkSourceCodec.renderDocument(retained)
        #expect(html.contains("id=\"chapter\""))
        #expect(html.contains("href=\"\(destination)\""))
        let markdown = try RelayMarkSourceCodec.projectDocumentMarkdown(retained)
        let reimported = try RelayMarkSourceCodec.parseDocument(markdown, namespace: "native-authored-fragment-roundtrip")
        #expect(try RelayMarkSourceCodec.renderDocument(reimported).contains("href=\"\(destination)\""))
    }


    @Test func textEditingAndNativeBoundarySupportPreserveHeadingIdentity() throws {
        let document = try document()
        var saved: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0) })
        let baseline = String(editor.text.characters)
        let before = try document.encodeUpdate()
        #expect(editor.acceptsNativeReplacement(baseline: baseline, range: NSRange(location: 2, length: 0), replacement: "\n"))
        #expect(editor.acceptsNativeReplacement(baseline: baseline, range: NSRange(location: 0, length: baseline.utf16.count), replacement: "Replace selection"))
        #expect(try document.encodeUpdate() == before && saved.isEmpty)
        #expect(editor.acceptsNativeReplacement(baseline: baseline, range: NSRange(location: 0, length: 7), replacement: "Section"))
        editor.edit(AttributedString(baseline.replacingOccurrences(of: "Heading 1", with: "Section 1")))
        #expect(editor.failure == nil && saved.count == 1)
        #expect(try headingAttributes(document)["headingId"] as? String == "stable-1")
        #expect(try headingAttributes(document)["level"] as? Int == 1)
        #expect(NativeProseCodec.value(NativeProseCodec.attributed(editor.text)) == editor.text)
    }

    @Test func headingLevelSaveFailureRetriesExactBytesAndUndo() throws {
        let document = try document(), peer = RelayMarkNativeDocument()
        try peer.applyUpdate(document.encodeUpdate())
        var fail = true, attempts: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: {
            attempts.append($0); if fail { throw SaveFailure.disk }
        })
        editor.setNativeSelection(NSRange(location: 1, length: 0))
        #expect(editor.selectedHeadingLevel == 1)
        editor.setSelectedHeadingLevel(4)
        #expect(editor.hasUnpersistedTransaction && attempts.count == 1)

        fail = false; editor.retryPersistence()
        #expect(attempts.count == 2 && attempts[0] == attempts[1] && editor.failure == nil)
        try peer.applyUpdate(try #require(attempts.last).update)
        #expect(try headingAttributes(document)["level"] as? Int == 4)
        #expect(try headingAttributes(document)["headingId"] as? String == "stable-1")
        editor.undo(); try peer.applyUpdate(try #require(attempts.last).update)
        #expect(try headingAttributes(document)["level"] as? Int == 1)
        editor.redo(); try peer.applyUpdate(try #require(attempts.last).update)
        #expect(try headingAttributes(document)["level"] as? Int == 4)
        #expect(try JSONSerialization.jsonObject(with: document.snapshot()) as? NSDictionary == JSONSerialization.jsonObject(with: peer.snapshot()) as? NSDictionary)
    }

    @Test func remoteHeadingTextAndUnsupportedListUpdateUseSameAdmissionFence() throws {
        let document = try document(), peer = RelayMarkNativeDocument()
        try peer.applyUpdate(document.encodeUpdate())
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        editor.setNativeSelection(NSRange(location: 2, length: 0))
        let update = try RelayMarkNativeRichTextMutation.replace(document: peer, path: [0,0], start: 0, end: 0, text: "Peer ")
        try editor.applyRemoteUpdate(update)
        #expect(editor.nativeSelection?.location == 7)
        #expect(String(editor.text.characters).hasPrefix("Peer Heading 1"))
        #expect(editor.isEditable)
        // The replica integrates a structure it cannot edit and stops accepting input.
        let list = try #require(Data(base64Encoded: listSeed))
        try editor.applyRemoteUpdate(list)
        #expect(!editor.isEditable)
    }

    @Test func markedHeadingInputCommitsThroughSameDispatcher() throws {
        let document = try document()
        var saved: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0) })
        let before = try document.encodeUpdate()
        let token = try editor.beginComposition()
        let candidate = AttributedString(String(editor.text.characters).replacingOccurrences(of: "Heading 1", with: "見出し"))
        #expect(try document.encodeUpdate() == before && saved.isEmpty)
        try editor.commitComposition(candidate, from: token)
        #expect(saved.count == 1 && editor.failure == nil)
        #expect(try headingAttributes(document)["headingId"] as? String == "stable-1")
        #expect(String(editor.text.characters) == String(candidate.characters))
    }
}
