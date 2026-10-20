import Foundation
#if os(macOS)
import AppKit

/// Find in paper on AppKit. The find bar searches the paper's text, so a
/// match inside a table cell is found, selected in its cell and scrolled to.
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

    /// The selection in paper offsets, in the paper view or in the cell being edited.
    var firstSelectedRange: NSRange {
        guard let view else { return NSRange(location: 0, length: 0) }
        if let cell = view.window?.firstResponder as? RelayTableCellTextView, let grid = cell.grid,
           grid.table.cells.indices.contains(cell.index) {
            let range = grid.table.paperRange(of: cell.index), selection = cell.selectedRange()
            return NSRange(location: range.location + selection.location, length: selection.length)
        }
        return view.paperSelection
    }
    var selectedRanges: [NSValue] {
        get { [NSValue(range: firstSelectedRange)] }
        set {
            guard let view, let range = newValue.first?.rangeValue else { return }
            if let shown = view.paper.tables.view(range) {
                view.window?.makeFirstResponder(view)
                view.setSelectedRange(shown)
            } else if let hit = view.paper.tables.table(holding: range) {
                let cell = hit.table.grid.cellView(hit.cell)
                view.window?.makeFirstResponder(cell)
                cell.setSelectedRange(NSRange(location: range.location - hit.table.paperRange(of: hit.cell).location, length: range.length))
            }
        }
    }

    func scrollRangeToVisible(_ range: NSRange) {
        guard let view else { return }
        if let shown = view.paper.tables.view(range) { view.scrollRangeToVisible(shown); return }
        guard let hit = view.paper.tables.table(holding: range) else { return }
        let cell = hit.table.grid.cellView(hit.cell)
        view.scrollToVisible(view.convert(cell.frame, from: hit.table.grid).insetBy(dx: 0, dy: -24))
    }

    /// The paper view for body text, or a cell's text view for text in a table.
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
               let cell = span.table.cell(containing: index) {
                outRange.pointee = span.table.paperRange(of: cell)
                return span.table.grid.cellView(cell)
            }
            start = NSMaxRange(table)
        }
        outRange.pointee = NSRange(location: start, length: max(0, view.paperLength - start))
        return view
    }

    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        guard let view else { return nil }
        if let shown = view.paper.tables.view(range), let geometry = RelayTextGeometry(view.textLayoutManager) {
            let origin = view.textContainerOrigin
            return geometry.segmentFrames(shown).map { NSValue(rect: $0.offsetBy(dx: origin.x, dy: origin.y)) }
        }
        guard let hit = view.paper.tables.table(holding: range) else { return nil }
        let cell = hit.table.grid.cellView(hit.cell)
        guard let geometry = RelayTextGeometry(cell.textLayoutManager) else { return nil }
        let local = NSRange(location: range.location - hit.table.paperRange(of: hit.cell).location, length: range.length)
        let origin = cell.textContainerOrigin
        return geometry.segmentFrames(local).map { NSValue(rect: $0.offsetBy(dx: origin.x, dy: origin.y)) }
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
/// table cells are found, highlighted in their cells and scrolled to.
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

    /// Matches in cells are drawn by their tables; the paper view draws the rest.
    private func showDecorations() {
        guard let view else { return }
        for span in view.paper.tables.spans where span.table.isGridLoaded {
            var found: [Int: [(range: NSRange, highlighted: Bool)]] = [:]
            for (range, style) in decorations {
                guard let cell = span.table.cell(containing: range.location) else { continue }
                let paper = span.table.paperRange(of: cell)
                guard NSMaxRange(range) <= NSMaxRange(paper) else { continue }
                found[cell, default: []].append((NSRange(location: range.location - paper.location, length: range.length), style == .highlighted))
            }
            span.table.grid.found = found
        }
        view.setNeedsDisplay()
    }

    func scrollRangeToVisible(_ range: UITextRange, inDocument document: AnyHashable??) {
        guard let view, let found = self.range(range) else { return }
        if let shown = view.paper.tables.view(found) { view.scrollRangeToVisible(shown); return }
        guard let hit = view.paper.tables.table(holding: found) else { return }
        let cell = hit.table.grid.cellView(hit.cell)
        view.scrollRectToVisible(view.convert(cell.frame, from: hit.table.grid).insetBy(dx: 0, dy: -24), animated: true)
        showDecorations()
    }

    func findInteraction(_ interaction: UIFindInteraction, sessionFor view: UIView) -> UIFindSession? {
        UITextSearchingFindSession(searchableObject: self)
    }
}
#endif
