import Foundation
@testable import RelayMarkEditor
@testable import RelayMarkEditorCore
import RelayMarkNativeCollaboration
import RelayMarkProseProjection
import RelayMarkSwift
import SwiftUI
import Testing
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Standard attributed-string backgrounds distinguish blocks without changing document text.
@MainActor
struct RelayMarkEditorQuestionCardTests {
    static let source = """
    @Callout(tone: "info", emphasis: "soft") {
    Safe guidance
    }

    <!-- relay:question id="q-one" type="multiple_choice" -->
    Capital?
    - ( ) Paris
    - ( ) London
    - ( ) Rome
    <!-- /relay:question -->

    <!-- relay:question id="q-two" type="short_text" -->
    Name?
    <!-- /relay:question -->
    """

    private func session(editable: Bool = false) throws -> RelayMarkEditorSession {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(Self.source, namespace: "cards"))
        return try RelayMarkEditorSession(document: document, canEdit: { editable }, persist: { _ in })
    }

    private func render(_ session: RelayMarkEditorSession) -> NSAttributedString {
        NativeProseCodec.attributed(session.text, callouts: session.nativeCallouts, questions: session.nativeQuestions)
    }

    @Test func nativeBackgroundsPreserveQuestionAndCalloutText() throws {
        let session = try session()
        let text = render(session)
        for word in ["Capital?", "Paris", "London", "Rome", "Name?", "Safe guidance"] {
            let offset = (text.string as NSString).range(of: word).location
            #expect(text.attribute(.backgroundColor, at: offset, effectiveRange: nil) != nil)
        }
        #expect(text.string == String(session.text.characters))
        #expect(NativeProseCodec.value(text) == session.text)
    }
    @Test func calloutTintSurvivesLocalTypingAndRemoteLeafSplice() throws {
        let session = try session(editable: true)
        let storage = NSTextStorage(attributedString: render(session))
        let start = (storage.string as NSString).range(of: "Safe guidance").location
        let tint = try #require(storage.attribute(.backgroundColor, at: start, effectiveRange: nil) as? PlatformColor)
        let insertion = NSRange(location: start + 4, length: 0)
        #expect(session.typeNatively(range: insertion, replacement: " local"))
        storage.replaceCharacters(in: insertion, with: " local")
        NativeProseCodec.restyle(storage, range: NSRange(location: insertion.location, length: 6),
            from: session.text, taskItems: [])
        #expect((storage.attribute(.backgroundColor, at: insertion.location, effectiveRange: nil) as? PlatformColor) == tint)
        #expect(NativeProseCodec.value(storage) == session.text)

        let old = (storage.string as NSString).range(of: "Safe local guidance")
        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(session.document.encodeUpdate())
        let update = try RelayMarkNativeRichEditing.replace(document: peer,
            range: NSRange(location: NSMaxRange(old), length: 0), runs: [(" remotely", [:])],
            expectedSnapshot: peer.snapshot()).update
        try session.applyRemoteUpdate(update)
        let replacement = NSRange(location: old.location, length: old.length + 9)
        #expect(NativeProseCodec.splice(storage, replacing: old, with: session.text,
            range: replacement, taskItems: []))
        #expect((storage.attribute(.backgroundColor, at: NSMaxRange(replacement) - 1, effectiveRange: nil) as? PlatformColor) == tint)
        #expect(NativeProseCodec.value(storage) == session.text)
    }

    @Test func removingInlineHighlightRestoresIndependentBlockTint() throws {
        let session = try session()
        let storage = NSTextStorage(attributedString: render(session))
        let target = (storage.string as NSString).range(of: "Safe guidance")
        let tint = try #require(storage.attribute(.backgroundColor, at: target.location, effectiveRange: nil) as? PlatformColor)
        var highlighted = session.text
        let range = try #require(Range(target, in: highlighted))
        highlighted[range][RelayMarkOfferedMarksAttribute.self] = [.highlight]
        #expect(NativeProseCodec.splice(storage, replacing: target, with: highlighted, range: target, taskItems: []))
        #expect((storage.attribute(.backgroundColor, at: target.location, effectiveRange: nil) as? PlatformColor) != tint)
        #expect(NativeProseCodec.value(storage) == highlighted)
        #expect(NativeProseCodec.splice(storage, replacing: target, with: session.text, range: target, taskItems: []))
        #expect((storage.attribute(.backgroundColor, at: target.location, effectiveRange: nil) as? PlatformColor) == tint)
        #expect(NativeProseCodec.value(storage) == session.text)
    }

}
