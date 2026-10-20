import Foundation
import RelayMarkCollaboration
import RelayMarkProseProjection
import SwiftUI

func relayPaperInlineSemantics(_ value: AttributedString) -> AttributedString {
    var result = value
    for run in value.runs {
        result[run.range].setAttributes(AttributeContainer())
        let intent = run.inlinePresentationIntent ?? []
        result[run.range].inlinePresentationIntent = intent.isEmpty ? nil : intent
        result[run.range].link = run.link
    }
    return result
}

/// A single native replacement request, not an authorship assertion. Only use it
/// while its exact baseline and resulting candidate still match the editor.
struct RelayNativeTextReplacement {
    let baseline: String
    let range: NSRange
    let replacement: String

    func matches(original: String, proposed: String) -> Bool {
        guard baseline == original, range.location >= 0, range.length >= 0,
            range.location <= baseline.utf16.count,
            range.length <= baseline.utf16.count - range.location,
            let swiftRange = Range(range, in: baseline),
            NSRange(swiftRange, in: baseline) == range,
            swiftRange.lowerBound.samePosition(in: baseline.unicodeScalars) != nil,
            swiftRange.upperBound.samePosition(in: baseline.unicodeScalars) != nil else { return false }
        return baseline.replacingCharacters(in: swiftRange, with: replacement) == proposed
    }
}

/// Present only during an actual native font command, never a generic change notification.
/// One bold/italic/strike/code change a candidate makes over a projected range.
struct RelayNativeFormattingChange: Equatable {
    let startUTF16: Int
    let lengthUTF16: Int
    let mark: RelayMarkFormattingMark
    let enabled: Bool
}

struct RelayNativeFormattingCommand {
    let baseline: AttributedString
    let range: NSRange
    /// AppKit's font command may toggle either trait; UIKit supplies the exact selector.
    let mark: RelayMarkFormattingMark?
}

extension RelayMarkFormattingMark {
    var inlineIntent: InlinePresentationIntent {
        switch self {
        case .bold: .stronglyEmphasized
        case .italic: .emphasized
        case .strike: .strikethrough
        case .code: .code
        }
    }
}

/// Captured by an explicit native paste command, never inferred from replacement text.
struct RelayNativePasteCommand {
    let id: UUID
    let baseline: AttributedString
    let range: NSRange
    let preservesFormatting: Bool

    init(baseline: AttributedString, range: NSRange, preservesFormatting: Bool = false) {
        id = UUID(); self.baseline = baseline; self.range = range
        self.preservesFormatting = preservesFormatting
    }

    func matches(_ replacement: RelayNativeTextReplacement, current: AttributedString) -> Bool {
        baseline == current && range == replacement.range &&
            replacement.baseline == String(baseline.characters)
    }

    func plainCandidate(replacement: RelayNativeTextReplacement, rendered: String) -> AttributedString? {
        candidate(replacement: replacement, rendered: rendered,
                  inserted: AttributedString(replacement.replacement), usesDestinationIntent: false)
    }

    func attributedCandidate(replacement: RelayNativeTextReplacement,
                             rendered: AttributedString) -> AttributedString? {
        let plain = String(rendered.characters)
        guard let raw = Range(NSRange(location: range.location,
                                      length: replacement.replacement.utf16.count), in: plain),
              let lower = AttributedString.Index(raw.lowerBound, within: rendered),
              let upper = AttributedString.Index(raw.upperBound, within: rendered) else { return nil }
        return candidate(replacement: replacement, rendered: plain,
                         inserted: AttributedString(rendered[lower..<upper]), usesDestinationIntent: true)
    }

    private func candidate(replacement: RelayNativeTextReplacement, rendered: String,
                           inserted: AttributedString, usesDestinationIntent: Bool) -> AttributedString? {
        let original = String(baseline.characters)
        guard range == replacement.range, replacement.matches(original: original, proposed: rendered),
              let raw = Range(range, in: original),
              let lower = AttributedString.Index(raw.lowerBound, within: baseline),
              let upper = AttributedString.Index(raw.upperBound, within: baseline) else { return nil }
        var insertion = inserted
        // Paragraph/list/table presentation belongs to the destination host;
        // imported inline marks belong to the pasted text. Keep the original
        // baseline outside the exact native replacement, even if AppKit changes
        // paragraph attributes elsewhere in its text storage during import.
        if usesDestinationIntent && !baseline.characters.isEmpty {
            let point = lower == baseline.endIndex ? baseline.characters.index(before: lower) : lower
            let next = baseline.characters.index(after: point)
            insertion.presentationIntent = baseline[point..<next].presentationIntent
        } else if usesDestinationIntent {
            insertion.presentationIntent = nil
        }
        var result = baseline
        result.replaceSubrange(lower..<upper, with: insertion)
        return result
    }
}

/// The editor kept its pending update unsaved; the message says why.
public struct RelayMarkEditFailure: Error, LocalizedError {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public var errorDescription: String? { reason }
}

public struct RelayMarkPasteUnavailable: LocalizedError {
    public init() {}
    public var errorDescription: String? { "This clipboard content can't be pasted here." }
}

/// Ephemeral captured delivery closure; checkpoint and selection are captured
/// before an asynchronous OS provider is asked for bytes.
@MainActor
public final class RelayMarkPasteIntake {
    private let receiveBytes: @MainActor (Int, Data) -> Void
    private let reportFailure: @MainActor (String) -> Void
    private let itemCount: Int
    private var completed = Set<Int>()
    public init(itemCount: Int = 1, receive: @escaping @MainActor (Int, Data) -> Void, failure: @escaping @MainActor (String) -> Void) {
        self.itemCount = itemCount; receiveBytes = receive; reportFailure = failure
    }
    public convenience init(receive: @escaping @MainActor (Data) -> Void, failure: @escaping @MainActor (String) -> Void) {
        self.init(itemCount: 1, receive: { _, bytes in receive(bytes) }, failure: failure)
    }
    public func receive(_ data: Data?, at index: Int = 0) {
        guard index >= 0, index < itemCount, !completed.contains(index) else { reportFailure("The clipboard provider delivered an invalid item."); return }
        guard let data, !data.isEmpty, data.count <= 4_194_304 else {
            reportFailure("The HTML clipboard payload could not be read within the supported input limit."); return
        }
        completed.insert(index); receiveBytes(index, data)
    }
}

/// An actual single-image OS gesture; its durable reservation precedes delivery.
@MainActor
public final class RelayMarkImageIntake {
    private let receiveBytes: (Data) -> Void
    private let reportFailure: (String) -> Void
    private let maximumBytes: Int
    private var delivered = false
    public init(maximumBytes: Int, receive: @escaping (Data) -> Void, failure: @escaping (String) -> Void) {
        self.maximumBytes = maximumBytes; receiveBytes = receive; reportFailure = failure
    }
    public func receive(_ bytes: Data?) {
        guard !delivered else { reportFailure("The image provider delivered the same input twice."); return }
        guard let bytes, !bytes.isEmpty, bytes.count <= maximumBytes else {
            reportFailure("The image could not be read within the supported input limit."); return
        }
        delivered = true; receiveBytes(bytes)
    }
}


public struct RelayMarkRemoteSelection: Identifiable, Equatable, Sendable {
    public let id: UInt64
    public let name: String
    public let color: String
    public let range: NSRange
    public let caretLocation: Int
}

/// Exact OS-declared marked literal, not an edit proof, baseline or Apply anchor.
struct RelayDeclaredMarkedInput: Equatable, Sendable {
    /// Bounds an OS-declared literal, with any earlier marked literal it replaces.
    static let byteLimit = 32 * 1024 * 1024
    struct Invalid: Error {}
    enum Platform: String, Sendable { case appKit, uiKit }
    enum Phase: String, Sendable { case marked, final }
    let tokenID: UUID
    let ownerID: UUID
    let revision: Int
    let platform: Platform
    let phase: Phase
    let previousMarkedLiteral: String?
    let literal: String? // nil is explicit OS cancellation.
    let initialReplacement: NSRange
    let replacement: NSRange
    let selection: NSRange
    let suppliedReplacement: NSRange?
    init(tokenID: UUID, ownerID: UUID, revision: Int, platform: Platform, literal: String?,
        initialReplacement: NSRange, replacement: NSRange, selection: NSRange, suppliedReplacement: NSRange?, phase: Phase = .marked, previousMarkedLiteral: String? = nil) throws {
        func valid(_ range: NSRange) -> Bool {
            range.location >= 0 && range.location != NSNotFound && range.length >= 0 && range.length <= Int.max - range.location
        }
        guard (platform == .appKit ? suppliedReplacement != nil : suppliedReplacement == nil),
              revision > 0, valid(initialReplacement), valid(replacement), valid(selection),
              (suppliedReplacement == nil || suppliedReplacement.map { $0.location == NSNotFound ? $0.length == 0 : valid($0) } == true),
              literal.map({ value in
                  let remaining = RelayDeclaredMarkedInput.byteLimit - value.utf8.count
                  return remaining >= 0 && (previousMarkedLiteral?.utf8.count ?? 0) <= remaining &&
                      (phase == .final || (selection.location <= value.utf16.count && selection.length <= value.utf16.count - selection.location))
              }) ?? (phase == .marked && previousMarkedLiteral == nil) else {
            throw Invalid()
        }
        self.tokenID = tokenID; self.ownerID = ownerID; self.revision = revision; self.platform = platform
        self.phase = phase; self.previousMarkedLiteral = previousMarkedLiteral
        self.literal = literal; self.initialReplacement = initialReplacement; self.replacement = replacement; self.selection = selection; self.suppliedReplacement = suppliedReplacement
    }
}
