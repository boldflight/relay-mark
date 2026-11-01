import Foundation
@testable import RelayMarkEditor
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

/// A form paper's questions are bordered cards; a host's answers restyle them without touching
/// the document. These tests drive the shared codec and the macOS paper view.
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

    private func render(_ session: RelayMarkEditorSession, form: RelayFormPresentation? = nil) -> NSAttributedString {
        NativeProseCodec.attributed(session.text, callouts: session.nativeCallouts, questions: session.nativeQuestions, form: form)
    }

    private func answers(_ entries: [String: RelayMarkFormAnswers.Entry]) -> RelayFormPresentation {
        RelayFormPresentation(answers: RelayMarkFormAnswers(entries: entries), hostHeights: [:])
    }

    private func optionStates(_ text: NSAttributedString) -> [String: Bool] {
        var found: [String: Bool] = [:]
        text.enumerateAttribute(.relayOptionState, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let value = value as? NSNumber { found[(text.string as NSString).substring(with: range)] = value.boolValue }
        }
        return found
    }

    @Test func overlayLeavesTheCanonicalTextAndRoundtripUnchanged() throws {
        let session = try session()
        let plain = render(session)
        let shown = render(session, form: answers(["q-one": .init(values: ["London"]), "q-two": .init(values: ["Ada"], truncated: true)]))
        #expect(shown.string == plain.string)
        #expect(String(NativeProseCodec.value(shown).characters) == String(session.text.characters))
        #expect(NativeProseCodec.value(shown) == NativeProseCodec.value(plain))
        #expect(optionStates(plain).isEmpty)
    }

    @Test func aChosenOptionMatchesByTextOrIdAndTheOthersRecede() throws {
        let session = try session()
        let question = try #require(session.nativeQuestions.first)
        // By text, and by an option's id, as the web does.
        let byText = optionStates(render(session, form: answers(["q-one": .init(values: ["London"])])))
        #expect(byText == ["Paris": false, "London": true, "Rome": false])
        let rome = question.options[2].id
        let byID = optionStates(render(session, form: answers(["q-one": .init(values: [rome])])))
        #expect(byID == ["Paris": false, "London": false, "Rome": true])
        // An unknown value selects nothing; it is shown as text under the question instead.
        let unknown = render(session, form: answers(["q-one": .init(values: ["Madrid"])]))
        #expect(optionStates(unknown) == ["Paris": false, "London": false, "Rome": false])
        let slot = try #require((unknown.attribute(.relayBlock, at: (unknown.string as NSString).range(of: "Rome").location, effectiveRange: nil) as? RelayBlockStyle)?.answer)
        #expect(slot.rows == [.text("Madrid")])
    }

    @Test func noAnswerShowsOnlyWhenThereAreNoValuesOrFiles() throws {
        let session = try session()
        let text = render(session, form: answers(["q-one": .init(values: ["Paris"]), "q-two": .init()]))
        func slot(at word: String) -> RelayAnswerSlot? {
            (text.attribute(.relayBlock, at: (text.string as NSString).range(of: word).location, effectiveRange: nil) as? RelayBlockStyle)?.answer
        }
        // A chosen option needs no line; an unanswered question says so.
        #expect(slot(at: "Rome") == nil)
        #expect(slot(at: "Name?")?.rows == [.subdued("No answer")])
        let withFile = render(session, form: RelayFormPresentation(
            answers: RelayMarkFormAnswers(entries: ["q-two": .init(attachments: [.init(index: 0, kind: .file, filename: "a.png", isImage: true)])]),
            hostHeights: ["q-two": 80]))
        let file = (withFile.attribute(.relayBlock, at: (withFile.string as NSString).range(of: "Name?").location, effectiveRange: nil) as? RelayBlockStyle)?.answer
        #expect(file == RelayAnswerSlot(questionID: "q-two", rows: [], hostHeight: 80))
    }

    @Test func aReadOnlyFormSessionTakesAnswersWithoutBecomingEditable() throws {
        let session = try session()
        #expect(!session.isEditable)
        let before = String(session.text.characters)
        session.setFormAnswers(RelayMarkFormAnswers(entries: ["q-one": .init(values: ["Paris"])]))
        #expect(!session.isEditable)
        #expect(String(session.text.characters) == before)
        #expect(session.formAnswersRevision == 1)
        session.setFormAnswers(RelayMarkFormAnswers(entries: ["q-one": .init(values: ["Paris"])]))
        #expect(session.formAnswersRevision == 1)
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

    @Test func theViewMarksTheChosenOptionAndKeepsTheDocumentUntouched() throws {
        let session = try session()
        let snapshot = try session.document.snapshot()
        let (coordinator, view, window) = try mount(session)
        defer { coordinator.retire(view); window.contentView = nil; window.close() }
        session.setFormAnswers(RelayMarkFormAnswers(entries: ["q-one": .init(values: ["Paris"]), "q-two": .init()]))
        coordinator.update(view)
        let text = view.paperStorage
        #expect(optionStates(text) == ["Paris": true, "London": false, "Rome": false])
        #expect(try session.document.snapshot() == snapshot)
        #expect(!view.isPaperEditable)
        // VoiceOver hears what the drawn marker and answer say.
        view.setSelectedRange(NSRange(location: (text.string as NSString).range(of: "Paris").location, length: 0))
        let heard = view.paperAccessibilityContent().first
        #expect(heard?.label == "Capital?")
        #expect(heard?.value == "Selected: Paris")
    }
    #endif
}
