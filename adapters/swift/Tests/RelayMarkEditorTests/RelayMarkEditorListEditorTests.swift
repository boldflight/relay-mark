import Foundation
@testable import RelayMarkEditor
@testable import RelayMarkEditorCore
import Testing
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkSwift

@MainActor
struct RelayMarkEditorListEditorTests {
    // Chromium-produced bullet -> ordered(start:3) fixture from RelayMark ef0c008.
    private let seed = "AQ+K5uD9AgAHAQdkZWZhdWx0AwpidWxsZXRMaXN0BwCK5uD9AgADCGxpc3RJdGVtBwCK5uD9AgEDCXBhcmFncmFwaAcAiubg/QICBgQAiubg/QIDBU91dGVyh4rm4P0CAgMLb3JkZXJlZExpc3QHAIrm4P0CCQMIbGlzdEl0ZW0HAIrm4P0CCgMJcGFyYWdyYXBoBwCK5uD9AgsGBACK5uD9AgwQTmVzdGVkIPCfjI0gdGV4dCgAiubg/QIJBXN0YXJ0AX0Dh4rm4P0CAQMIbGlzdEl0ZW0HAIrm4P0CHAMJcGFyYWdyYXBoBwCK5uD9Ah0GBACK5uD9Ah4HU2libGluZwA="
    private func document(editable: Bool = false) throws -> RelayMarkNativeDocument {
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(try #require(Data(base64Encoded: seed)))
        return try editable ? canonicalStructuredFixture(document, namespace: "nested-list") : document
    }

    @Test func markersDepthStartAndNativeRoundtripKeepCanonicalOffsets() throws {
        let doc = try document(), projection = try doc.proseProjection()
        #expect(RelayNativeListStructure.supports(doc))
        #expect(String(projection.text.characters) == "Outer\nNested 🌍 text\nSibling")
        let context = NativeProseCodec.ListContext()
        let native = NativeProseCodec.attributed(projection.text, listContext: context)
        #expect(native.string == String(projection.text.characters))
        #expect(NativeProseCodec.value(native) == projection.text)
        #expect(NativeProseCodec.attributed(projection.text, listContext: context).isEqual(to: native))
        let lists = projection.blockRanges.map {
            (native.attribute(.paragraphStyle, at: $0.location, effectiveRange: nil) as! NSParagraphStyle).textLists
        }
        #expect(lists.map(\.count) == [1, 2, 1])
        #expect(lists[0][0] === lists[1][0] && lists[0][0] === lists[2][0])
        #expect(lists[1][1].startingItemNumber == 3)
        #expect(lists[1][1].marker(forItemNumber: 3) == "3.")
        #expect(lists[0][0].markerFormat == .disc)
        for range in projection.blockRanges {
            let position = try #require(projection.position(atUTF16: range.location + 1))
            #expect(projection.offset(path: position.path, index: position.index) == range.location + 1)
        }
    }

    @Test func orderedOuterStartsAtSevenAndNestedBulletKeepsItsOwnMarker() throws {
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(try #require(Data(base64Encoded: "AQ/xpb6KBAAHAQdkZWZhdWx0AwtvcmRlcmVkTGlzdAcA8aW+igQAAwhsaXN0SXRlbQcA8aW+igQBAwlwYXJhZ3JhcGgHAPGlvooEAgYEAPGlvooEAwVPdXRlcofxpb6KBAIDCmJ1bGxldExpc3QHAPGlvooECQMIbGlzdEl0ZW0HAPGlvooECgMJcGFyYWdyYXBoBwDxpb6KBAsGBADxpb6KBAwQTmVzdGVkIPCfjI0gdGV4dIfxpb6KBAEDCGxpc3RJdGVtBwDxpb6KBBsDCXBhcmFncmFwaAcA8aW+igQcBgQA8aW+igQdB1NpYmxpbmcoAPGlvooEAAVzdGFydAF9BwA=")))
        #expect(RelayNativeListStructure.supports(document))
        let projection = try document.proseProjection()
        let native = NativeProseCodec.attributed(projection.text)
        let lists = projection.blockRanges.map {
            (native.attribute(.paragraphStyle, at: $0.location, effectiveRange: nil) as! NSParagraphStyle).textLists
        }
        #expect(lists.map(\.count) == [1, 2, 1])
        #expect(lists[0][0] === lists[2][0])
        #expect(lists[0][0].startingItemNumber == 7)
        #expect(lists[1][1].markerFormat == .disc)
    }

    #if os(macOS)
    @Test func nativeViewKeepsBackingRangesWithoutMarkerCharacters() throws {
        _ = NSApplication.shared
        let native = NativeProseCodec.attributed(try document().proseProjection().text)
        let view = CollaborationTextView.textKit2(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        view.textStorage?.setAttributedString(native)
        let manager = try #require(view.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        #expect(!NSTextList.includesTextListMarkers)
        #expect(view.string == native.string)
        view.setSelectedRange(NSRange(location: 8, length: 0))
        #expect(view.selectedRange().location == 8)
    }
    #endif

    @Test func continuationParagraphDoesNotBecomeAnotherListItem() throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            "1. First\n\n   Continuation\n\n2. Second", namespace: "native-list-continuation"))
        let projection = try document.richProseProjection()
        let native = NativeProseCodec.attributed(projection.text)
        let lists = ["First", "Continuation", "Second"].map { word in
            (native.attribute(.paragraphStyle, at: (native.string as NSString).range(of: word).location,
                effectiveRange: nil) as! NSParagraphStyle).textLists
        }
        #expect(lists.map(\.count) == [1, 0, 1])
        #expect(lists[0][0] === lists[2][0])
        #expect(NativeProseCodec.value(native) == projection.text)
    }

    @Test func emptyItemsRetainNativeAdmission() throws {
        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(try document().encodeUpdate())
        let update = try peer.deleteText(at: 0, length: 5, path: [0, 0, 0, 0])
        let copy = try document()
        try copy.applyUpdate(update)
        #expect(RelayNativeListStructure.supports(copy))
    }

    @Test func nestedEditRemoteMergeUndoAndRedo() throws {
        let doc = try document(editable: true), peer = RelayMarkNativeDocument()
        try peer.applyUpdate(doc.encodeUpdate())
        var updates: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: doc, persist: { updates.append($0) })
        let before = try doc.encodeUpdate(), plain = String(editor.text.characters)
        #expect(editor.acceptsNativeReplacement(baseline: plain, range: NSRange(location: 0, length: 5), replacement: ""))
        #expect(try doc.encodeUpdate() == before)
        editor.edit(AttributedString(plain.replacingOccurrences(of: "Nested", with: "Nested native")))
        #expect(editor.failure == nil && updates.count == 1)
        try peer.applyUpdate(try #require(updates.last).update)
        editor.setNativeSelection(NSRange(location: 8, length: 0))
        try editor.applyRemoteUpdate(try peer.insertText("Peer ", at: 0, path: [0, 0, 1, 0, 0, 0]))
        #expect(editor.nativeSelection?.location == 13)
        #expect(String(editor.text.characters).contains("Peer Nested native 🌍 text"))
        editor.undo(); try peer.applyUpdate(try #require(updates.last).update)
        #expect(String(editor.text.characters).contains("Peer Nested 🌍 text"))
        editor.redo(); try peer.applyUpdate(try #require(updates.last).update)
        #expect(try JSONSerialization.jsonObject(with: doc.snapshot()) as? NSDictionary == JSONSerialization.jsonObject(with: peer.snapshot()) as? NSDictionary)
    }

}
