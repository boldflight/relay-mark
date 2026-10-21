import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
/// A table reads to VoiceOver as rows of cells; a cell with a live text view holds it.
extension RelayTableGridView {
    override func accessibilityRole() -> NSAccessibility.Role? { .table }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRowCount() -> Int { table.rows }
    override func accessibilityColumnCount() -> Int { table.columns }
    override func accessibilityRows() -> [Any]? { accessibilityRowElements() }
    override func accessibilityChildren() -> [Any]? { accessibilityRowElements() }

    private func accessibilityRowElements() -> [NSAccessibilityElement] {
        (0..<table.rows).map { row in
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.row)
            element.setAccessibilityParent(self)
            element.setAccessibilityIndex(row)
            let cells = table.cells.indices.filter { table.cells[$0].row == row }.map { index -> NSAccessibilityElement in
                let cell = table.cells[index]
                let item = NSAccessibilityElement()
                item.setAccessibilityRole(.cell)
                item.setAccessibilityParent(element)
                item.setAccessibilityValue(cell.text.string)
                item.setAccessibilityLabel(cell.header ? String(localized: "Header: \(cell.text.string)", bundle: .module, comment: "VoiceOver label of a table header cell; the placeholder is its text.") : cell.text.string)
                item.setAccessibilityRowIndexRange(NSRange(location: cell.row, length: cell.rowSpan))
                item.setAccessibilityColumnIndexRange(NSRange(location: cell.column, length: cell.columnSpan))
                item.setAccessibilityFrameInParentSpace(geometry.frame(of: cell))
                if let view = live[index] { item.setAccessibilityChildren([view]) }
                return item
            }
            element.setAccessibilityChildren(cells)
            element.setAccessibilityFrameInParentSpace(cells.reduce(CGRect.null) { $0.union($1.accessibilityFrame()) })
            return element
        }
    }
}
#else
/// A cell's place in its table, as VoiceOver reads it. Activating it edits the cell.
final class RelayTableAccessibilityCell: UIAccessibilityElement, UIAccessibilityContainerDataTableCell {
    let index: Int
    private let rows: NSRange, columns: NSRange
    private weak var grid: RelayTableGridView?
    init(grid: RelayTableGridView, index: Int, cell: RelayTableCellModel) {
        self.index = index; self.grid = grid
        rows = NSRange(location: cell.row, length: cell.rowSpan)
        columns = NSRange(location: cell.column, length: cell.columnSpan)
        super.init(accessibilityContainer: grid)
        accessibilityLabel = cell.text.string
        accessibilityTraits = cell.header ? [.header, .staticText] : [.staticText]
        accessibilityFrameInContainerSpace = grid.geometry.frame(of: cell)
    }
    func accessibilityRowRange() -> NSRange { rows }
    func accessibilityColumnRange() -> NSRange { columns }
    override func accessibilityActivate() -> Bool {
        guard let grid else { return false }
        return grid.cellView(index).becomeFirstResponder()
    }
}

extension RelayTableGridView: @preconcurrency UIAccessibilityContainerDataTable {
    func accessibilityDataTableCellElement(forRow row: Int, column: Int) -> (any UIAccessibilityContainerDataTableCell)? {
        guard let index = table.cells.firstIndex(where: {
            NSLocationInRange(row, NSRange(location: $0.row, length: $0.rowSpan)) &&
                NSLocationInRange(column, NSRange(location: $0.column, length: $0.columnSpan)) }) else { return nil }
        return RelayTableAccessibilityCell(grid: self, index: index, cell: table.cells[index])
    }
    func accessibilityRowCount() -> Int { table.rows }
    func accessibilityColumnCount() -> Int { table.columns }
    override var accessibilityElements: [Any]? {
        get { table.cells.indices.map { RelayTableAccessibilityCell(grid: self, index: $0, cell: table.cells[$0]) } }
        set {}
    }
}

#endif
