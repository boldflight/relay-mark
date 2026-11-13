import Foundation
import SwiftUI
import RelayMarkEditorCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// One table cell as the paper shows it: its place in the grid, the canonical
/// paper range of its text, and that text as rendered.
struct RelayTableCellModel {
    var row: Int
    var column: Int
    var rowSpan: Int
    var columnSpan: Int
    var header: Bool
    var columnWidths: [Int]?
    /// Relative to the table's first paper offset; a cell of several paragraphs
    /// includes the separators between them.
    var range: NSRange
    var text: NSAttributedString
}

/// One preserved attachment in the TextKit 2 paper, with its own Apple TextKit 1
/// view for native table layout and interaction.
@MainActor
final class RelayTableAttachment: NSTextAttachment {
    var editing: (any RelayTableEditing)?
    let identity: Int
    /// The paper offset of the table's first cell; cell ranges count from it.
    var start: Int { didSet { loadedGrid?.updateStart(start) } }
    private(set) var cells: [RelayTableCellModel]
    private var loadedGrid: RelayTableGridView?
    var grid: RelayTableGridView {
        if let loadedGrid { return loadedGrid }
        let grid = RelayTableGridView(table: self)
        loadedGrid = grid
        return grid
    }
    var isGridLoaded: Bool { loadedGrid != nil }

    init(identity: Int, start: Int, cells: [RelayTableCellModel]) {
        self.identity = identity; self.start = start; self.cells = cells
        super.init(data: nil, ofType: nil)
        #if !os(macOS)
        accessibilityLabel = String(localized: "Table", bundle: .module, comment: "VoiceOver label of a table in the paper.")
        #endif
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var columns: Int { max(1, cells.map { $0.column + $0.columnSpan }.max() ?? 1) }
    var rows: Int { max(0, cells.map { $0.row + $0.rowSpan }.max() ?? 0) }
    /// The table's text in the paper, from its first cell to the end of its last.
    var canonicalRange: NSRange { NSRange(location: start, length: NSMaxRange(cells.last?.range ?? NSRange())) }
    /// A cell's text in the paper.
    func paperRange(of index: Int) -> NSRange {
        NSRange(location: start + cells[index].range.location, length: cells[index].range.length)
    }
    /// The cell holding a paper offset, its ends included.
    func cell(containing offset: Int) -> Int? {
        let local = offset - start
        return cells.firstIndex { local >= $0.range.location && local <= NSMaxRange($0.range) }
    }
    /// One cell's text was edited in place: it and the cells after it take `delta`.
    func cellEdited(_ index: Int, text: NSAttributedString, delta: Int) {
        cells[index].text = text
        cells[index].range.length += delta
        for later in cells.indices where later > index { cells[later].range.location += delta }
    }
    /// Takes a newly rendered table: unchanged cells keep their views' text.
    func update(start: Int, cells: [RelayTableCellModel]) {
        self.start = start
        guard cells.count != self.cells.count || zip(cells, self.cells).contains(where: { !$0.sameCell(as: $1) }) else {
            self.cells = cells
            loadedGrid?.refreshAvailability()
            return
        }
        let old = self.cells.count
        self.cells = cells
        loadedGrid?.cellsReplaced(0..<old, count: cells.count)
    }
    /// The table as rows of tab-separated cells, as copied out of the paper.
    var readable: NSAttributedString {
        let result = NSMutableAttributedString()
        for row in 0..<rows {
            if row > 0 { result.append(NSAttributedString(string: "\n")) }
            for (index, cell) in cells.filter({ $0.row == row }).sorted(by: { $0.column < $1.column }).enumerated() {
                if index > 0 { result.append(NSAttributedString(string: "\t")) }
                let text = NSMutableAttributedString(attributedString: cell.text)
                text.mutableString.replaceOccurrences(of: "\n", with: " ", range: NSRange(location: 0, length: text.length))
                result.append(text)
            }
        }
        return result
    }

    /// Re-projected rows: `replacement` (paper offsets) takes the place of the
    /// cells that spanned the same text before the change, and later cells move by `delta`.
    func replaceCells(meeting old: NSRange, delta: Int, with replacement: [RelayTableCellModel]) {
        let relative = replacement.map { cell -> RelayTableCellModel in
            var cell = cell; cell.range.location -= start; return cell
        }
        let lower = relative.first?.range.location ?? (old.location - start)
        let upper = relative.last.map { NSMaxRange($0.range) - delta } ?? (NSMaxRange(old) - start)
        let first = cells.firstIndex { $0.range.location >= lower } ?? cells.count
        var last = first
        while last < cells.count, NSMaxRange(cells[last].range) <= upper { last += 1 }
        for index in last..<cells.count { cells[index].range.location += delta }
        cells.replaceSubrange(first..<last, with: relative)
        loadedGrid?.cellsReplaced(first..<last, count: relative.count)
    }

    override func viewProvider(for parentView: PlatformTableView?, location: any NSTextLocation,
                               textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let provider = RelayTableAttachmentViewProvider(textAttachment: self, parentView: parentView,
                                                        textLayoutManager: textContainer?.textLayoutManager, location: location)
        // The grid's size, asked again whenever the table's paragraph is laid out.
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

#if os(macOS)
typealias PlatformTableView = NSView
#else
typealias PlatformTableView = UIView
#endif

/// Hosts the table's grid in the paper and sizes the attachment to it.
final class RelayTableAttachmentViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let attachment = textAttachment as? RelayTableAttachment else { return }
        nonisolated(unsafe) let table = attachment
        view = MainActor.assumeIsolated { table.grid }
    }
    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation,
                                   textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        guard let attachment = textAttachment as? RelayTableAttachment else { return .zero }
        nonisolated(unsafe) let table = attachment
        let width = max(1, proposedLineFragment.width - 2 * (textContainer?.lineFragmentPadding ?? 0))
        let size = MainActor.assumeIsolated { table.grid.layout(width: width) }
        return CGRect(origin: .zero, size: size)
    }
}

extension RelayTableCellModel {
    func sameCell(as other: RelayTableCellModel) -> Bool {
        row == other.row && column == other.column && rowSpan == other.rowSpan && columnSpan == other.columnSpan &&
            header == other.header && columnWidths == other.columnWidths && range == other.range && text == other.text
    }
}

/// Where a table's attachment character is in the view's text.
struct RelayTableSpan {
    var view: Int
    let table: RelayTableAttachment
}

/// The view shows each table as one character; the paper holds its cells' text.
/// These map offsets between the two, and are the identity without tables.
@MainActor
struct RelayTableSpans {
    var spans: [RelayTableSpan] = []

    /// The paper offset of a view offset. Just before a table is its first cell's
    /// start; just after it, its last cell's end.
    func paper(_ offset: Int) -> Int {
        var delta = 0
        for span in spans {
            guard span.view < offset else { break }
            delta += span.table.canonicalRange.length - 1
        }
        return offset + delta
    }
    func paper(_ range: NSRange) -> NSRange {
        let start = paper(range.location)
        return NSRange(location: start, length: paper(NSMaxRange(range)) - start)
    }
    /// The view offset of a paper offset, or nil when it is inside a table.
    func view(_ offset: Int) -> Int? {
        var delta = 0
        for span in spans {
            let range = span.table.canonicalRange
            if offset <= range.location { break }
            if offset < NSMaxRange(range) { return nil }
            delta += range.length - 1
        }
        return offset - delta
    }
    func view(_ range: NSRange) -> NSRange? {
        guard let start = view(range.location), let end = view(NSMaxRange(range)) else { return nil }
        return NSRange(location: start, length: end - start)
    }
    /// The table whose paper text holds `range` within one of its cells.
    func table(holding range: NSRange) -> (table: RelayTableAttachment, cell: Int)? {
        for span in spans {
            let table = span.table, whole = table.canonicalRange
            guard range.location >= whole.location, NSMaxRange(range) <= NSMaxRange(whole),
                  let cell = table.cell(containing: range.location),
                  NSMaxRange(range) <= NSMaxRange(table.paperRange(of: cell)) else { continue }
            return (table, cell)
        }
        return nil
    }
    /// The table whose paper text contains `range` entirely, ends included.
    func table(containing range: NSRange) -> Int? {
        spans.firstIndex { span in
            let whole = span.table.canonicalRange
            return range.location >= whole.location && NSMaxRange(range) <= NSMaxRange(whole)
        }
    }
    /// A view edit of `delta` characters at `viewOffset`, outside every table.
    mutating func viewEdited(at viewOffset: Int, delta: Int) {
        for index in spans.indices where spans[index].view >= viewOffset {
            spans[index].view += delta
            spans[index].table.start += delta
        }
    }
    /// A paper edit of `delta` inside the table at `index`: tables after it move in the paper only.
    func paperEdited(inTable index: Int, delta: Int) {
        for later in spans.indices where later > index { spans[later].table.start += delta }
    }
    /// Top-level nodes at view range `old` were replaced by `viewLength`
    /// characters holding the tables `inserted`; later tables move.
    mutating func replace(view old: NSRange, paperDelta: Int, viewLength: Int, with inserted: [RelayTableSpan]) {
        let viewDelta = viewLength - old.length
        let kept = spans.filter { !NSLocationInRange($0.view, old) }
        for span in kept where span.view >= NSMaxRange(old) { span.table.start += paperDelta }
        spans = kept.map { span in
            var span = span
            if span.view >= NSMaxRange(old) { span.view += viewDelta }
            return span
        } + inserted
        spans.sort { $0.view < $1.view }
    }
    /// TextKit changed the view's text on its own (a general edit or a paste):
    /// the tables are where their attachment characters now are.
    mutating func resync(_ text: NSAttributedString) {
        guard !spans.isEmpty else { return }
        var found: [RelayTableSpan] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let table = value as? RelayTableAttachment else { return }
            found.append(RelayTableSpan(view: range.location, table: table))
        }
        spans = found
    }
    /// Whether a view range would put text beside a table on its own line.
    func touchesTableLine(_ range: NSRange) -> Bool {
        spans.contains { span in
            range.length == 0 ? (range.location == span.view || range.location == span.view + 1)
                : NSIntersectionRange(range, NSRange(location: span.view, length: 1)).length > 0 &&
                    !(range.location <= span.view && NSMaxRange(range) >= span.view + 1)
        }
    }
    func span(atView offset: Int) -> RelayTableSpan? { spans.first { $0.view == offset } }
    /// A view selection holding tables as a reader takes it: each table as rows
    /// of tab-separated cells. Nil when the selection holds no table.
    func readable(_ text: NSAttributedString, range: NSRange) -> NSAttributedString? {
        let inside = spans.filter { NSLocationInRange($0.view, range) }
        guard !inside.isEmpty, NSMaxRange(range) <= text.length else { return nil }
        let result = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
        for span in inside.reversed() {
            result.replaceCharacters(in: NSRange(location: span.view - range.location, length: 1), with: span.table.readable)
        }
        return result
    }
}
