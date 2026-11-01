import Foundation
import RelayMarkProseProjection
import SwiftUI
#if os(macOS)
import AppKit
typealias RelayHostedView = NSView
#else
import UIKit
typealias RelayHostedView = UIView
#endif

/// A paper view's form answers: the presentation its cards were drawn with, and the host's own
/// views for attached files and video, placed in the room each card leaves under its question.
/// The views sit over the text and are not part of it; no character stands for them.
@MainActor
final class RelayAnswerSlotHost {
    private(set) var presentation: RelayFormPresentation?
    private(set) var questions: [RelayMarkCollaborativeProse.Question] = []
    private var slots: [String: RelayMarkAnswerSlot] = [:]
    private var views: [String: RelayHostedView] = [:]
    /// Paper offset of the paragraph under which each question's slot sits.
    private var anchors: [String: Int] = [:]

    /// Asks the host for its slot views and returns what the cards are drawn with. The views are
    /// shown by the next `layout`.
    func prepare(questions: [RelayMarkCollaborativeProse.Question], answers: RelayMarkFormAnswers?,
                 provider: RelayMarkAnswerSlotProvider?) -> RelayFormPresentation? {
        self.questions = answers == nil ? [] : questions
        slots = [:]; anchors = [:]
        guard let answers else { presentation = nil; return nil }
        var heights: [String: CGFloat] = [:]
        for question in questions {
            guard let entry = answers.entries[question.id], !entry.attachments.isEmpty,
                  let slot = provider?(question.id, entry) else { continue }
            slots[question.id] = slot; heights[question.id] = slot.height
            anchors[question.id] = (question.options.last?.range ?? question.labelRange).location
        }
        presentation = RelayFormPresentation(answers: answers, hostHeights: heights)
        return presentation
    }

    /// Puts each slot's view in the room its card left, hiding any whose card is not laid out.
    func layout(in view: any RelayPaperTextView) {
        for id in views.keys where slots[id] == nil {
            views[id]?.removeFromSuperview(); views[id] = nil
        }
        guard let geometry = RelayTextGeometry(view.textLayoutManager) else { return }
        let origin = view.paperContentOrigin
        for (id, slot) in slots {
            let hosted = views[id] ?? mount(slot, in: view, id: id)
            update(hosted, with: slot)
            guard let offset = anchors[id].flatMap({ view.paper.tables.view(NSRange(location: $0, length: 0))?.location }),
                  let location = geometry.location(offset),
                  view.paper.laidOut?.contains(location) == true,
                  let fragment = geometry.manager.textLayoutFragment(for: location) as? RelayBlockFragment,
                  let frame = fragment.hostFrame else { hosted.isHidden = true; continue }
            let place = fragment.layoutFragmentFrame.origin
            hosted.frame = frame.offsetBy(dx: place.x + origin.x, dy: place.y + origin.y)
            hosted.isHidden = false
        }
    }

    func retire() {
        for hosted in views.values { hosted.removeFromSuperview() }
        views = [:]; slots = [:]
    }

    /// The host's content fills the room the card left, leading and top aligned.
    private func filled(_ slot: RelayMarkAnswerSlot) -> AnyView {
        AnyView(slot.content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
    }

    private func mount(_ slot: RelayMarkAnswerSlot, in view: any RelayPaperTextView, id: String) -> RelayHostedView {
        #if os(macOS)
        let hosted: RelayHostedView = NSHostingView(rootView: filled(slot))
        #else
        let hosted: RelayHostedView = UIHostingConfiguration { filled(slot) }.margins(.all, 0).makeContentView()
        #endif
        view.addPaperSubview(hosted)
        views[id] = hosted
        return hosted
    }

    private func update(_ hosted: RelayHostedView, with slot: RelayMarkAnswerSlot) {
        #if os(macOS)
        (hosted as? NSHostingView<AnyView>)?.rootView = filled(slot)
        #else
        (hosted as? UIContentView)?.configuration = UIHostingConfiguration { filled(slot) }.margins(.all, 0)
        #endif
    }

    /// What VoiceOver says for the question holding `offset`: which options were chosen and the
    /// answer, since the chosen marker and the answer are drawn rather than read.
    func summary(at offset: Int, text: NSString) -> (label: String, value: String)? {
        guard let answers = presentation?.answers,
              let question = questions.first(where: { NSLocationInRange(offset, $0.range) || NSMaxRange($0.range) == offset }),
              NSMaxRange(question.range) <= text.length else { return nil }
        let entry = answers.entries[question.id] ?? RelayMarkFormAnswers.Entry()
        let options = question.options.map { (id: $0.id, text: text.substring(with: $0.range)) }
        let chosen = options.filter { entry.selects(optionID: $0.id, optionText: $0.text) }.map(\.text)
        var parts: [String] = []
        if !chosen.isEmpty {
            parts.append(String(localized: "Selected: \(chosen.formatted(.list(type: .and, width: .narrow)))", bundle: .module,
                comment: "VoiceOver: the options a respondent chose; the placeholder is the list of options."))
        }
        parts += entry.freeText(options: options)
        if !entry.attachments.isEmpty {
            parts.append(String(localized: "\(entry.attachments.count) attachments", bundle: .module,
                comment: "VoiceOver: how many files a respondent attached to an answer."))
        }
        if parts.isEmpty { parts.append(String(localized: "No answer", bundle: .module, comment: "Shown under a form question the respondent did not answer.")) }
        return (text.substring(with: question.labelRange), parts.joined(separator: ". "))
    }
}
