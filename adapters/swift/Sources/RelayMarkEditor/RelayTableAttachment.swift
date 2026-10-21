import Foundation
#if os(macOS)
import AppKit
private typealias GridColor = NSColor
#else
import UIKit
private typealias GridColor = UIColor
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

/// Edits made in a table's cells go to the paper's session through its editor.
@MainActor
protocol RelayTableEditing: AnyObject {
    var tablesEditable: Bool { get }
    var tableUndoManager: UndoManager? { get }
    func tableCellDidChange(_ table: RelayTableAttachment, at index: Int, text: NSAttributedString)
    func tableCellDidSelect(_ table: RelayTableAttachment, at index: Int, range: NSRange)
    /// The host's commands on the selection, run on the paper's selection in a cell.
    var cellSelectionActions: [(name: String, perform: () -> Bool)] { get }
}

/// A table is one attachment character in the paper's text. Its cells are
/// small standard text views in a grid; only the rows near the screen have one.
@MainActor
final class RelayTableAttachment: NSTextAttachment {
    let identity: Int
    /// The paper offset of the table's first cell; cell ranges count from it.
    var start: Int
    private(set) var cells: [RelayTableCellModel]
    weak var editor: RelayTableEditing?
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
            self.cells = cells; return
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

/// Column edges and row tops of a table at one width, from the cells' text.
/// Each cell's measured height is kept, so an edit measures only its own cell.
struct RelayTableGeometry {
    var columnX: [CGFloat] = [0]
    var rowTops: [CGFloat] = [0]
    private var heights: [CGFloat] = []
    static let padding: CGFloat = 4

    init() {}
    init(cells: [RelayTableCellModel], columns: Int, rows: Int, width: CGFloat) {
        var authored = [CGFloat?](repeating: nil, count: columns)
        for cell in cells {
            guard let widths = cell.columnWidths, widths.count == cell.columnSpan else { continue }
            for (index, value) in widths.enumerated() where cell.column + index < columns && value > 0 {
                authored[cell.column + index] = CGFloat(min(value, 4_096))
            }
        }
        let fixed = authored.compactMap { $0 }.reduce(0, +)
        let flexible = authored.filter { $0 == nil }.count
        let share = flexible > 0 ? max(48, (width - fixed) / CGFloat(flexible)) : 0
        var resolved = authored.map { $0 ?? share }
        let total = resolved.reduce(0, +)
        if total > width, total > 0 { resolved = resolved.map { $0 * width / total } }
        columnX = [0]
        for value in resolved { columnX.append(columnX.last! + value) }
        heights = cells.map { height(of: $0) }
        placeRows(cells, rows: rows)
    }

    /// Cells `old` were replaced by `count` cells, now at the same place in `cells`.
    mutating func replace(_ old: Range<Int>, count: Int, in cells: [RelayTableCellModel], rows: Int) {
        guard heights.count - old.count + count == cells.count else {
            heights = cells.map { height(of: $0) }; placeRows(cells, rows: rows); return
        }
        heights.replaceSubrange(old, with: cells[old.lowerBound..<(old.lowerBound + count)].map { height(of: $0) })
        placeRows(cells, rows: rows)
    }

    /// One cell's text changed. Returns whether any row moved.
    mutating func remeasure(_ index: Int, in cells: [RelayTableCellModel], rows: Int) -> Bool {
        guard heights.indices.contains(index) else { return false }
        let height = height(of: cells[index])
        guard height != heights[index] else { return false }
        heights[index] = height
        let before = rowTops
        placeRows(cells, rows: rows)
        return rowTops != before
    }

    private mutating func placeRows(_ cells: [RelayTableCellModel], rows: Int) {
        var rowHeights = [CGFloat](repeating: 0, count: rows)
        for (index, cell) in cells.enumerated() where cell.rowSpan == 1 && cell.row < rows {
            rowHeights[cell.row] = max(rowHeights[cell.row], heights[index])
        }
        for (index, cell) in cells.enumerated() where cell.rowSpan > 1 && cell.row < rows {
            let last = min(rows - 1, cell.row + cell.rowSpan - 1)
            let have = rowHeights[cell.row...last].reduce(0, +)
            if heights[index] > have { rowHeights[last] += heights[index] - have }
        }
        rowTops = [0]
        rowTops.reserveCapacity(rows + 1)
        for value in rowHeights { rowTops.append(rowTops.last! + value) }
    }

    var size: CGSize { CGSize(width: columnX.last ?? 0, height: rowTops.last ?? 0) }

    func x(_ column: Int) -> CGFloat { columnX[min(max(0, column), columnX.count - 1)] }
    func top(_ row: Int) -> CGFloat { rowTops[min(max(0, row), rowTops.count - 1)] }
    func frame(of cell: RelayTableCellModel) -> CGRect {
        CGRect(x: x(cell.column), y: top(cell.row), width: x(cell.column + cell.columnSpan) - x(cell.column),
               height: top(cell.row + cell.rowSpan) - top(cell.row))
    }
    func textWidth(of cell: RelayTableCellModel) -> CGFloat {
        max(1, x(cell.column + cell.columnSpan) - x(cell.column) - 2 * Self.padding)
    }
    func height(of cell: RelayTableCellModel) -> CGFloat {
        Self.textHeight(cell.text, width: textWidth(of: cell)) + 2 * Self.padding
    }
    static func textHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        let font = text.length > 0 ? text.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont : nil
        let line = font ?? PlatformFont.systemFont(ofSize: 15)
        let minimum = ceil(line.ascender - line.descender + line.leading)
        guard text.length > 0 else { return minimum }
        let measured = text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height
        return max(minimum, ceil(measured))
    }
}

#if os(macOS)
/// One cell's text, edited in a standard TextKit 2 text view.
final class RelayTableCellTextView: NSTextView {
    /// VoiceOver in a cell reaches the paper's selection commands.
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        (super.accessibilityCustomActions() ?? []) + (grid?.table.editor?.cellSelectionActions ?? []).map { action in
            NSAccessibilityCustomAction(name: action.name) { action.perform() }
        }
    }
    /// A Genmoji has no RelayMark node: inserted, it would be lost on the next render.
    override var supportsAdaptiveImageGlyph: Bool { get { false } set {} }
    var index = 0
    weak var grid: RelayTableGridView?
    override var undoManager: UndoManager? { grid?.table.editor?.tableUndoManager ?? super.undoManager }
    override func insertTab(_ sender: Any?) { if grid?.moveFocus(from: index, backward: false) != true { super.insertTab(sender) } }
    override func insertBacktab(_ sender: Any?) { if grid?.moveFocus(from: index, backward: true) != true { super.insertBacktab(sender) } }
    /// Find in a cell is Find in the whole paper.
    override func performTextFinderAction(_ sender: Any?) {
        guard let paper = sequence(first: superview, next: { $0?.superview }).compactMap({ $0 as? CollaborationTextView }).first
        else { return super.performTextFinderAction(sender) }
        paper.performTextFinderAction(sender)
    }
}
#else
/// One cell's text, edited in a standard TextKit 2 text view.
final class RelayTableCellTextView: UITextView {
    var index = 0
    weak var grid: RelayTableGridView?
    override var textInputContextIdentifier: String? { CollaborationTextView.keyboardContext }
    /// VoiceOver in a cell reaches the paper's selection commands in its Edit rotor.
    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            (super.accessibilityCustomActions ?? []) + (grid?.table.editor?.cellSelectionActions ?? []).map { action in
                let custom = UIAccessibilityCustomAction(name: action.name) { _ in action.perform() }
                custom.category = UIAccessibilityCustomAction.editCategory
                return custom
            }
        }
        set { super.accessibilityCustomActions = newValue }
    }
    /// VoiceOver's lines rotor and read-all go on to the neighbouring cell in reading order.
    override var accessibilityPreviousTextNavigationElement: Any? {
        get { index > 0 ? grid?.cellView(index - 1) : nil }
        set {}
    }
    override var accessibilityNextTextNavigationElement: Any? {
        get { grid.flatMap { index + 1 < $0.table.cells.count ? $0.cellView(index + 1) : nil } }
        set {}
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        assert(textLayoutManager != nil, "A table cell switched to TextKit 1 compatibility mode")
    }
    override var undoManager: UndoManager? { grid?.table.editor?.tableUndoManager ?? super.undoManager }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.count == 1, let key = presses.first?.key, key.charactersIgnoringModifiers == "\t",
           key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty,
           grid?.moveFocus(from: index, backward: key.modifierFlags.contains(.shift)) == true { return }
        super.pressesBegan(presses, with: event)
    }
}
#endif

/// The grid of a table's cells. Cell text views exist only for the rows near
/// the visible part of the paper; the others are recycled.
@MainActor
final class RelayTableGridView: PlatformTableView {
    unowned let table: RelayTableAttachment
    private(set) var geometry = RelayTableGeometry()
    private var width: CGFloat = 0
    private(set) var live: [Int: RelayTableCellTextView] = [:]
    private var pool: [RelayTableCellTextView] = []
    private var shown = CGRect.null
    /// Rows outside the visible part of the paper that still have text views.
    static let margin: CGFloat = 400

    init(table: RelayTableAttachment) {
        self.table = table
        super.init(frame: .zero)
        #if os(macOS)
        wantsLayer = true
        setAccessibilityRole(.table)
        setAccessibilityLabel(String(localized: "Table", bundle: .module, comment: "VoiceOver label of a table in the paper."))
        #else
        accessibilityContainerType = .dataTable
        #endif
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    #if os(macOS)
    override var isFlipped: Bool { true }
    #endif

    /// The grid's size at `width`; lays the cells out again when the width changed.
    @discardableResult func layout(width: CGFloat) -> CGSize {
        if abs(width - self.width) >= 0.5 || geometry.rowTops.count != table.rows + 1 {
            self.width = width
            geometry = RelayTableGeometry(cells: table.cells, columns: table.columns, rows: table.rows, width: width)
            placeLiveCells()
        }
        frame.size = geometry.size
        return geometry.size
    }

    /// One cell's text changed: its row may grow or shrink. Returns whether the table's height changed.
    @discardableResult func cellDidChange(_ index: Int) -> Bool {
        let before = geometry.size.height
        guard geometry.remeasure(index, in: table.cells, rows: table.rows) else { return false }
        placeLiveCells()
        frame.size = geometry.size
        return geometry.size.height != before
    }

    /// Cells were replaced in the model: live views show the new text.
    func cellsReplaced(_ old: Range<Int>, count: Int) {
        let delta = count - old.count
        var moved: [Int: RelayTableCellTextView] = [:]
        for (index, view) in live {
            if index < old.lowerBound { moved[index] = view }
            else if index >= old.upperBound { moved[index + delta] = view }
            else if index < old.lowerBound + count { moved[index] = view }
            else { recycle(view) }
        }
        live = moved
        for (index, view) in live where index >= old.lowerBound && index < old.lowerBound + count {
            show(index, in: view)
        }
        if geometry.rowTops.count == table.rows + 1 {
            geometry.replace(old, count: count, in: table.cells, rows: table.rows)
        } else {
            geometry = RelayTableGeometry(cells: table.cells, columns: table.columns, rows: table.rows, width: width)
        }
        placeLiveCells()
        frame.size = geometry.size
    }

    /// Shows a cell's current model text in its live view, keeping its selection where it can.
    func refresh(_ index: Int) {
        guard let view = live[index] else { return }
        show(index, in: view)
    }

    /// Text views for the cells in `rect`, in grid coordinates.
    func updateVisible(in rect: CGRect) {
        guard geometry.rowTops.count > 1 else { return }
        let band = rect.insetBy(dx: 0, dy: -Self.margin).intersection(CGRect(origin: .zero, size: geometry.size))
        shown = band
        let wanted = band.isNull ? Set<Int>() : Set(table.cells.indices.filter { geometry.frame(of: table.cells[$0]).intersects(band) })
        for (index, view) in live where !wanted.contains(index) && !isEditing(view) {
            live[index] = nil; recycle(view)
        }
        for index in wanted where live[index] == nil { _ = cellView(index) }
    }

    /// The text view of a cell, made live when it is not.
    @discardableResult func cellView(_ index: Int) -> RelayTableCellTextView {
        if let view = live[index] { return view }
        let view = pool.popLast() ?? make()
        live[index] = view
        show(index, in: view)
        addSubview(view)
        return view
    }

    /// Tab moves to the next cell, Shift-Tab to the previous; at the table's edge, nothing.
    @discardableResult func moveFocus(from index: Int, backward: Bool) -> Bool {
        let next = index + (backward ? -1 : 1)
        guard table.cells.indices.contains(next) else { return true }
        let view = cellView(next)
        #if os(macOS)
        window?.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        #else
        view.becomeFirstResponder()
        view.selectedRange = NSRange(location: view.text.utf16.count, length: 0)
        #endif
        return true
    }

    private func isEditing(_ view: RelayTableCellTextView) -> Bool {
        #if os(macOS)
        window?.firstResponder === view
        #else
        view.isFirstResponder
        #endif
    }

    private func recycle(_ view: RelayTableCellTextView) {
        view.removeFromSuperview()
        pool.append(view)
    }

    private func placeLiveCells() {
        for (index, view) in live where table.cells.indices.contains(index) {
            view.frame = geometry.frame(of: table.cells[index])
        }
    }

    private var updating = false

    #if !os(macOS)
    /// Find matches in cells, by cell, in cell text offsets.
    var found: [Int: [(range: NSRange, highlighted: Bool)]] = [:] {
        didSet { for (index, view) in live { decorate(view, index) } }
    }
    private func decorate(_ view: RelayTableCellTextView, _ index: Int) {
        view.layer.sublayers?.filter { $0.name == "relay.found" }.forEach { $0.removeFromSuperlayer() }
        guard let matches = found[index], let manager = view.textLayoutManager, let content = manager.textContentManager else { return }
        for match in matches {
            guard let start = content.location(content.documentRange.location, offsetBy: match.range.location),
                  let end = content.location(start, offsetBy: match.range.length),
                  let range = NSTextRange(location: start, end: end) else { continue }
            manager.enumerateTextSegments(in: range, type: .standard, options: []) { _, frame, _, _ in
                let layer = CALayer()
                layer.name = "relay.found"
                layer.backgroundColor = GridColor.systemYellow.withAlphaComponent(match.highlighted ? 0.6 : 0.3).cgColor
                layer.frame = frame.offsetBy(dx: view.textContainerInset.left, dy: view.textContainerInset.top)
                view.layer.addSublayer(layer)
                return true
            }
        }
    }
    #endif

    private func show(_ index: Int, in view: RelayTableCellTextView) {
        let cell = table.cells[index]
        updating = true
        defer { updating = false }
        view.index = index
        view.frame = geometry.frame(of: cell)
        #if os(macOS)
        let selection = view.selectedRange()
        if view.attributedString() != cell.text { view.textStorage?.setAttributedString(cell.text) }
        if NSMaxRange(selection) <= cell.text.length { view.setSelectedRange(selection) }
        view.backgroundColor = cell.header ? GridColor.systemGray.withAlphaComponent(0.12) : .clear
        view.drawsBackground = cell.header
        view.isEditable = table.editor?.tablesEditable ?? false
        view.setAccessibilityLabel(cell.text.string)
        #else
        let selection = view.selectedRange
        if view.attributedText != cell.text { view.attributedText = cell.text }
        if NSMaxRange(selection) <= cell.text.length { view.selectedRange = selection }
        view.backgroundColor = cell.header ? GridColor.systemGray.withAlphaComponent(0.12) : .clear
        view.isEditable = table.editor?.tablesEditable ?? false
        view.accessibilityTraits = cell.header ? [.header] : []
        decorate(view, index)
        #endif
    }

    private func make() -> RelayTableCellTextView {
        #if os(macOS)
        let view = RelayTableCellTextView(usingTextLayoutManager: true)
        #if DEBUG
        RelayTextKit1Guard.install()
        #endif
        view.isRichText = true
        view.isVerticallyResizable = false; view.isHorizontallyResizable = false
        view.textContainerInset = NSSize(width: RelayTableGeometry.padding, height: RelayTableGeometry.padding)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.wantsLayer = true
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = GridColor.systemGray.withAlphaComponent(0.35).cgColor
        view.allowsUndo = true
        view.delegate = self
        #else
        let view = RelayTableCellTextView(usingTextLayoutManager: true)
        view.isScrollEnabled = false
        view.textContainerInset = UIEdgeInsets(top: RelayTableGeometry.padding, left: RelayTableGeometry.padding,
                                               bottom: RelayTableGeometry.padding, right: RelayTableGeometry.padding)
        view.textContainer.lineFragmentPadding = 0
        view.layer.borderWidth = 0.5
        view.layer.borderColor = GridColor.systemGray.withAlphaComponent(0.35).cgColor
        view.adjustsFontForContentSizeCategory = true
        view.delegate = self
        #endif
        view.grid = self
        return view
    }

    fileprivate func cellChanged(_ view: RelayTableCellTextView) {
        guard !updating, live[view.index] === view else { return }
        #if os(macOS)
        guard !view.hasMarkedText(), let text = view.textStorage else { return }
        #else
        guard view.markedTextRange == nil else { return }
        let text = view.textStorage
        #endif
        table.editor?.tableCellDidChange(table, at: view.index, text: NSAttributedString(attributedString: text))
    }

    fileprivate func cellSelected(_ view: RelayTableCellTextView) {
        guard !updating, live[view.index] === view else { return }
        #if os(macOS)
        table.editor?.tableCellDidSelect(table, at: view.index, range: view.selectedRange())
        #else
        table.editor?.tableCellDidSelect(table, at: view.index, range: view.selectedRange)
        #endif
    }
}

#if os(macOS)
extension RelayTableGridView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let view = notification.object as? RelayTableCellTextView else { return }
        cellChanged(view)
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        guard let view = notification.object as? RelayTableCellTextView else { return }
        cellSelected(view)
    }
    func undoManager(for view: NSTextView) -> UndoManager? { table.editor?.tableUndoManager }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        guard let clip = enclosingScrollView?.contentView else { updateVisible(in: visibleRect); return }
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: clip)
        updateVisible(in: visibleRect)
    }
    @objc private func scrolled() { updateVisible(in: visibleRect) }
}
#else
extension RelayTableGridView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        guard let view = textView as? RelayTableCellTextView else { return }
        cellChanged(view)
    }
    func textViewDidChangeSelection(_ textView: UITextView) {
        guard let view = textView as? RelayTableCellTextView else { return }
        cellSelected(view)
    }
}
#endif
