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

/// A form paper's questions are bordered cards drawn over the unchanged document text. These
/// tests drive the shared codec and the macOS paper view.
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

    @Test func eachQuestionIsOneCardAcrossItsLabelAndOptionsAndTheTextIsUntouched() throws {
        let session = try session()
        let text = render(session)
        func style(at word: String) -> RelayBlockStyle? {
            text.attribute(.relayBlock, at: (text.string as NSString).range(of: word).location, effectiveRange: nil) as? RelayBlockStyle
        }
        let capital = try #require(style(at: "Capital?"))
        #expect(capital.appearance == .card)
        #expect([style(at: "Paris"), style(at: "London"), style(at: "Rome")].allSatisfy { $0?.identity == capital.identity })
        #expect(style(at: "Name?")?.identity != capital.identity)
        #expect(style(at: "Safe guidance")?.appearance == .callout(tone: "info", strong: false))
        #expect(text.string == String(session.text.characters))
        #expect(NativeProseCodec.value(text) == session.text)
    }

    #if os(macOS)
    private func mount(_ session: RelayMarkEditorSession) throws -> (RelayMarkEditorView.TextCoordinator, CollaborationTextView, NSWindow) {
        _ = NSApplication.shared
        let coordinator = RelayMarkEditorView.TextCoordinator(session: session)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 480, height: 800),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 480, height: 800)
        let manager = try #require(view.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        return (coordinator, view, window)
    }

    private func fragments(_ view: CollaborationTextView) throws -> [RelayBlockFragment] {
        let manager = try #require(view.textLayoutManager)
        var found: [RelayBlockFragment] = []
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
            if let block = fragment as? RelayBlockFragment { found.append(block) }
            return true
        }
        return found
    }

    @Test func adjacentCalloutAndCardsKeepTheirOwnFirstAndLastMargins() throws {
        let session = try session()
        let (coordinator, view, window) = try mount(session)
        defer { coordinator.retire(view); window.contentView = nil; window.close() }
        let blocks = try fragments(view)
        // One callout paragraph, the question's label and three options, then the second question's label.
        #expect(blocks.count == 6)
        let callout = blocks[0], card = Array(blocks[1...4]), second = blocks[5]
        #expect(callout.isFirst && callout.isLast)
        #expect(card.map(\.isFirst) == [true, false, false, false])
        #expect(card.map(\.isLast) == [false, false, false, true])
        #expect(second.isFirst && second.isLast)
        // Only a card's ends carry the margin around it; its middle paragraphs touch.
        let style = card[0].block
        #expect(card[0].topMargin == style.padding + style.outerGap)
        #expect(card[1].topMargin == 0 && card[1].bottomMargin == 0)
        #expect(card[3].bottomMargin == style.padding + style.outerGap)
        #expect(callout.topMargin == callout.block.padding && callout.bottomMargin == callout.block.padding)
    }
    #endif
}
