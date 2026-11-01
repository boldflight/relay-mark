import Foundation
import RelayMarkProseProjection
import SwiftUI

/// A respondent's answers, supplied by the host for a read-only form paper. The editor draws
/// each question's card from the authored paper and lays these over it: the chosen options
/// are marked, the other options recede, and the answer sits under the question. Nothing here
/// reaches the document: setting answers re-applies presentation and never changes the text.
public struct RelayMarkFormAnswers: Equatable, Sendable {
    /// A file or video the respondent attached. The host leases and shows it.
    public struct Attachment: Equatable, Sendable {
        public enum Kind: Sendable { case file, video }
        public let index: Int
        public let kind: Kind
        public let filename: String
        public let isImage: Bool
        public let size: Int?
        public init(index: Int, kind: Kind, filename: String, isImage: Bool, size: Int? = nil) {
            self.index = index; self.kind = kind; self.filename = filename; self.isImage = isImage; self.size = size
        }
    }

    public struct Entry: Equatable, Sendable {
        public var values: [String]
        public var attachments: [Attachment]
        /// The server cut the text at its bound.
        public var truncated: Bool
        public init(values: [String] = [], attachments: [Attachment] = [], truncated: Bool = false) {
            self.values = values; self.attachments = attachments; self.truncated = truncated
        }

        /// Whether the respondent chose this option: a value equal to its text or its id.
        public func selects(optionID: String, optionText: String) -> Bool {
            values.contains { $0 == optionText || $0 == optionID }
        }

        /// The values that name no option, for a question that has options. A question without
        /// options shows every value.
        func freeText(options: [(id: String, text: String)]) -> [String] {
            guard !options.isEmpty else { return values }
            return values.filter { value in !options.contains { $0.id == value || $0.text == value } }
        }
    }

    /// Answers by question id.
    public var entries: [String: Entry]
    /// A host advances this when what it shows in the answer slots changes without the entries
    /// changing, such as renewed file leases.
    public var hostRevision: Int
    public init(entries: [String: Entry], hostRevision: Int = 0) { self.entries = entries; self.hostRevision = hostRevision }
}

/// What a host puts under a question for attached files and video: its own SwiftUI view,
/// and the height it needs, since the paper lays the card out around it.
public struct RelayMarkAnswerSlot {
    public let height: CGFloat
    public let content: AnyView
    public init(height: CGFloat, content: AnyView) { self.height = height; self.content = content }
}

public typealias RelayMarkAnswerSlotProvider = @MainActor (_ questionID: String, _ entry: RelayMarkFormAnswers.Entry) -> RelayMarkAnswerSlot?

/// Answers laid over a paper being drawn, with the height each host slot asked for.
struct RelayFormPresentation {
    let answers: RelayMarkFormAnswers
    let hostHeights: [String: CGFloat]
}

extension RelayMarkCollaborativeProse.Question {
    /// How a card is presented: its block style and each option's state, read from the rendered text.
    func presentation(in text: NSString, local: (NSRange) -> NSRange, form: RelayFormPresentation?)
        -> (style: RelayBlockStyle, options: [(range: NSRange, selected: Bool)])? {
        let range = local(self.range)
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= text.length else { return nil }
        let texts = options.map { option -> (id: String, text: String)? in
            let r = local(option.range)
            guard r.location >= 0, NSMaxRange(r) <= text.length else { return nil }
            return (option.id, text.substring(with: r))
        }
        guard !texts.contains(where: { $0 == nil }) else { return nil }
        let known = texts.compactMap { $0 }
        guard let form else {
            return (RelayBlockStyle(identity: relaymarkID.hashValue, appearance: .card), [])
        }
        let entry = form.answers.entries[id] ?? RelayMarkFormAnswers.Entry()
        let chosen = zip(options, known).map { option, named in
            (range: local(option.range), selected: entry.selects(optionID: named.id, optionText: named.text))
        }
        let isChoice = !known.isEmpty
        let hostHeight = entry.attachments.isEmpty ? 0 : form.hostHeights[id] ?? 0
        var rows: [RelayAnswerSlot.Row] = entry.freeText(options: known).map { .text($0) }
        if entry.truncated, !rows.isEmpty {
            rows.append(.chip(String(localized: "Truncated", bundle: .module, comment: "Marker on a form answer the server cut short.")))
        }
        if entry.attachments.isEmpty, rows.isEmpty, !(isChoice && !entry.values.isEmpty) {
            rows.append(.subdued(String(localized: "No answer", bundle: .module, comment: "Shown under a form question the respondent did not answer.")))
        }
        let slot = rows.isEmpty && hostHeight == 0 ? nil : RelayAnswerSlot(questionID: id, rows: rows, hostHeight: hostHeight)
        return (RelayBlockStyle(identity: relaymarkID.hashValue, appearance: .card, answer: slot), chosen)
    }
}
