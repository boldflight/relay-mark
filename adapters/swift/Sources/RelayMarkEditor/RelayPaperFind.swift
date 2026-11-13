import Foundation
import RelayMarkEditorCore
#if os(macOS)
import AppKit

/// Find in paper on AppKit. The find bar searches the paper's text, so a
/// match inside a preserved table selects and reveals the whole attachment.
@MainActor
final class RelayPaperFinder: NSObject, @preconcurrency NSTextFinderClient {
    weak var view: CollaborationTextView?
    let finder = NSTextFinder()

    init(view: CollaborationTextView) {
        self.view = view
        super.init()
        finder.client = self
        finder.isIncrementalSearchingEnabled = true
    }

    var isSelectable: Bool { true }
    var allowsMultipleSelection: Bool { false }
    var isEditable: Bool { false }
    var string: String { view?.paperString ?? "" }

    /// The native selection mapped to canonical paper offsets.
    var firstSelectedRange: NSRange { view?.paperSelection ?? NSRange(location: 0, length: 0) }
    var selectedRanges: [NSValue] {
        get { [NSValue(range: firstSelectedRange)] }
        set {
            guard let view, let range = newValue.first?.rangeValue else { return }
            if let shown = view.paper.tables.view(range) {
                view.window?.makeFirstResponder(view)
                view.setSelectedRange(shown)
            } else if let span = view.paper.tables.spans.first(where: {
                NSIntersectionRange($0.table.canonicalRange, range).length > 0
            }) {
                view.window?.makeFirstResponder(view)
                view.setSelectedRange(NSRange(location: span.view, length: 1))
            }
        }
    }

    func scrollRangeToVisible(_ range: NSRange) {
        guard let view else { return }
        if let shown = view.paper.tables.view(range) { view.scrollRangeToVisible(shown); return }
        guard let span = view.paper.tables.spans.first(where: {
            NSIntersectionRange($0.table.canonicalRange, range).length > 0
        }) else { return }
        view.scrollRangeToVisible(NSRange(location: span.view, length: 1))
    }

    /// Both prose and preserved tables belong to the one native paper text view.
    func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer) -> NSView {
        guard let view else { return NSView() }
        var start = 0
        for span in view.paper.tables.spans {
            let table = span.table.canonicalRange
            if index < table.location {
                outRange.pointee = NSRange(location: start, length: table.location - start)
                return view
            }
            if index < NSMaxRange(table) || (index == NSMaxRange(table) && table.length == 0),
               span.table.cell(containing: index) != nil {
                outRange.pointee = table
                return view
            }
            start = NSMaxRange(table)
        }
        outRange.pointee = NSRange(location: start, length: max(0, view.paperLength - start))
        return view
    }

    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        guard let view else { return nil }
        if let shown = view.paper.tables.view(range), let geometry = RelayTextKitRanges(view.textLayoutManager) {
            let origin = view.textContainerOrigin
            return geometry.segmentFrames(shown).map { NSValue(rect: $0.offsetBy(dx: origin.x, dy: origin.y)) }
        }
        guard let span = view.paper.tables.spans.first(where: {
            NSIntersectionRange($0.table.canonicalRange, range).length > 0
        }), let geometry = RelayTextKitRanges(view.textLayoutManager) else { return nil }
        let origin = view.textContainerOrigin
        return geometry.segmentFrames(NSRange(location: span.view, length: 1)).map {
            NSValue(rect: $0.offsetBy(dx: origin.x, dy: origin.y))
        }
    }

    var visibleCharacterRanges: [NSValue] { [NSValue(range: NSRange(location: 0, length: view?.paperLength ?? 0))] }
}
#else
import UIKit

/// A range of the paper's text, table cells included, for Find in paper.
final class RelayPaperTextPosition: UITextPosition {
    let offset: Int
    init(_ offset: Int) { self.offset = offset }
}
final class RelayPaperTextRange: UITextRange {
    let range: NSRange
    init(_ range: NSRange) { self.range = range }
    override var start: UITextPosition { RelayPaperTextPosition(range.location) }
    override var end: UITextPosition { RelayPaperTextPosition(NSMaxRange(range)) }
    override var isEmpty: Bool { range.length == 0 }
}

/// Find in paper on UIKit. It searches the paper's text, so matches inside
/// tables are found, and UIKit highlights and reveals their attachment.
@MainActor
final class RelayPaperTextSearch: NSObject, @preconcurrency UITextSearching, UIFindInteractionDelegate {
    typealias DocumentIdentifier = AnyHashable?
    weak var view: CollaborationTextView?
    /// Paper ranges of the matches shown, with their style.
    private(set) var decorations: [NSRange: UITextSearchFoundTextStyle] = [:]

    var selectedTextRange: UITextRange? { view.map { RelayPaperTextRange($0.paperSelection) } }

    private func range(_ range: UITextRange) -> NSRange? {
        if let range = range as? RelayPaperTextRange { return range.range }
        guard let view else { return nil }
        return view.paper.tables.paper(view.viewRange(range))
    }

    func compare(_ foundRange: UITextRange, toRange: UITextRange, document: AnyHashable??) -> ComparisonResult {
        guard let from = range(foundRange)?.location, let to = range(toRange)?.location else { return .orderedSame }
        return from < to ? .orderedAscending : from > to ? .orderedDescending : .orderedSame
    }

    func performTextSearch(queryString: String, options: UITextSearchOptions, resultAggregator: UITextSearchAggregator<AnyHashable?>) {
        guard let view, !queryString.isEmpty else { resultAggregator.finishedSearching(); return }
        let source = view.paperString as NSString
        var compare: NSString.CompareOptions = []
        if options.stringCompareOptions.contains(.caseInsensitive) { compare.insert(.caseInsensitive) }
        var location = 0
        while location < source.length {
            let found = source.range(of: queryString, options: compare, range: NSRange(location: location, length: source.length - location))
            guard found.location != NSNotFound else { break }
            resultAggregator.foundRange(RelayPaperTextRange(found), searchString: queryString, document: nil)
            location = NSMaxRange(found)
        }
        resultAggregator.finishedSearching()
    }

    func decorate(foundTextRange: UITextRange, document: AnyHashable??, usingStyle style: UITextSearchFoundTextStyle) {
        guard let found = range(foundTextRange) else { return }
        decorations[found] = style == .normal ? nil : style
        showDecorations()
    }

    func clearAllDecoratedFoundText() {
        decorations = [:]
        showDecorations()
    }

    /// UIKit owns search decoration. A match inside a read-only table is
    /// represented by its attachment rather than a fabricated cell rectangle.
    private func showDecorations() {
        guard let view else { return }
        view.clearAllDecoratedFoundText()
        for (range, style) in decorations {
            guard let shown = shownRange(range, in: view),
                  let start = view.position(from: view.beginningOfDocument, offset: shown.location),
                  let end = view.position(from: start, offset: shown.length),
                  let native = view.textRange(from: start, to: end) else { continue }
            view.decorate(foundTextRange: native, document: nil, usingStyle: style)
        }
    }

    private func shownRange(_ range: NSRange, in view: CollaborationTextView) -> NSRange? {
        if let shown = view.paper.tables.view(range) { return shown }
        return view.paper.tables.spans.first(where: {
            NSIntersectionRange($0.table.canonicalRange, range).length > 0
        }).map { NSRange(location: $0.view, length: 1) }
    }

    func scrollRangeToVisible(_ range: UITextRange, inDocument document: AnyHashable??) {
        guard let view, let found = self.range(range), let shown = shownRange(found, in: view) else { return }
        view.scrollRangeToVisible(shown)
    }

    func findInteraction(_ interaction: UIFindInteraction, sessionFor view: UIView) -> UIFindSession? {
        UITextSearchingFindSession(searchableObject: self)
    }
}
#endif
