import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Semantic offsets only. Each native cell has a terminating paragraph separator;
/// that separator belongs to Apple's table representation, not a canonical leaf.
@MainActor
struct RelayNativeTableProjection {
    struct Cell {
        let model: RelayTableCellModel
        var native: NSRange
        let block: NSTextTableBlock
    }
    private(set) var cells: [Cell] = []
    private(set) var start = 0
    private(set) var supportsEditing = true
    private var nativeTable = NSTextTable()
    private var dirtyCells: Set<Int> = []
    private var invalidated = false

    mutating func updateStart(_ start: Int) { self.start = start }

    /// NSTextStorage reports character edits in UTF-16. Keep presentation ranges
    /// current until the shared engine returns its authoritative cell contents.
    mutating func noteNativeEdit(range: NSRange, delta: Int) {
        let old = NSRange(location: range.location, length: range.length - delta)
        guard old.length >= 0, let index = cells.firstIndex(where: {
            old.location >= $0.native.location && NSMaxRange(old) <= NSMaxRange($0.native)
        }) else { invalidated = true; return }
        dirtyCells.insert(index)
        cells[index].native.length += delta
        for later in cells.indices where later > index { cells[later].native.location += delta }
    }

    func nativeRange(forPaper range: NSRange) -> NSRange? {
        func position(_ offset: Int) -> Int? {
            for cell in cells {
                let paper = NSRange(location: start + cell.model.range.location, length: cell.model.range.length)
                if offset >= paper.location, offset <= NSMaxRange(paper) {
                    guard cell.native.length == paper.length else { return cell.native.location }
                    return cell.native.location + offset - paper.location
                }
            }
            return nil
        }
        guard let lower = position(range.location), let upper = position(NSMaxRange(range)) else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }

    func paperRange(forNative range: NSRange) -> NSRange? {
        func position(_ offset: Int) -> Int? {
            // Native Select All includes the final table paragraph separator.
            // It has no canonical character, so its endpoint is the last cell's
            // end. Editing still uses editablePaperRange's cell-only boundary.
            if let last = cells.last, offset == NSMaxRange(last.native) + 1 {
                return start + NSMaxRange(last.model.range)
            }
            for cell in cells where offset >= cell.native.location && offset <= NSMaxRange(cell.native) {
                guard cell.native.length == cell.model.range.length else { return start + cell.model.range.location }
                return start + cell.model.range.location + offset - cell.native.location
            }
            return nil
        }
        guard let lower = position(range.location), let upper = position(NSMaxRange(range)), upper >= lower else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }

    func editablePaperRange(forNative range: NSRange) -> NSRange? {
        guard supportsEditing, cells.contains(where: {
            range.location >= $0.native.location && NSMaxRange(range) <= NSMaxRange($0.native)
        }) else { return nil }
        return paperRange(forNative: range)
    }

    /// Retain native table/block identities during cell typing. Rebuild the
    /// representation only when canonical table structure changes.
    mutating func update(_ table: RelayTableAttachment, storage: NSTextStorage) {
        start = table.start
        let structureUnchanged = !invalidated && cells.count == table.cells.count && zip(cells, table.cells).allSatisfy {
            $0.model.row == $1.row && $0.model.column == $1.column &&
            $0.model.rowSpan == $1.rowSpan && $0.model.columnSpan == $1.columnSpan &&
            $0.model.header == $1.header && $0.model.columnWidths == $1.columnWidths
        }
        if !structureUnchanged {
            nativeTable = NSTextTable()
            nativeTable.numberOfColumns = table.columns
            nativeTable.collapsesBorders = true
            storage.setAttributedString(NSAttributedString())
            cells = []
        }
        supportsEditing = !table.cells.contains { cell in
            var containsAttachment = false
            cell.text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: cell.text.length)) { value, _, stop in
                if value != nil { containsAttachment = true; stop.pointee = true }
            }
            return containsAttachment
        }
        let previous = cells
        if structureUnchanged {
            for index in table.cells.indices.reversed() where dirtyCells.contains(index) || previous[index].model.text != table.cells[index].text {
                let cell = previous[index]
                storage.replaceCharacters(in: NSRange(location: cell.native.location, length: cell.native.length + 1),
                    with: attributed(table.cells[index], block: cell.block))
            }
        }
        var offset = 0
        cells = table.cells.enumerated().map { index, model in
            let block: NSTextTableBlock
            if structureUnchanged { block = previous[index].block }
            else {
                block = NSTextTableBlock(table: nativeTable, startingRow: model.row, rowSpan: model.rowSpan,
                    startingColumn: model.column, columnSpan: model.columnSpan)
                #if os(macOS)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setWidth(6, type: .absoluteValueType, for: .padding)
                block.setBorderColor(.separatorColor)
                if model.header { block.backgroundColor = .controlBackgroundColor }
                if let widths = model.columnWidths { block.setContentWidth(CGFloat(widths.reduce(0, +)), type: .absoluteValueType) }
                #else
                block.setWidth(1, type: .absolute, for: .border)
                block.setWidth(6, type: .absolute, for: .padding)
                block.setBorderColor(.separator)
                if model.header { block.backgroundColor = .secondarySystemBackground }
                if let widths = model.columnWidths { block.setContentWidth(CGFloat(widths.reduce(0, +)), type: .absolute) }
                #endif
            }
            let length: Int
            if supportsEditing { length = model.text.length }
            else { length = displayText(model.text).length }
            let cell = Cell(model: model, native: NSRange(location: offset, length: length), block: block)
            if !structureUnchanged { storage.append(attributed(model, block: block)) }
            offset += length + 1
            return cell
        }
        dirtyCells.removeAll()
        invalidated = false
    }

    private func attributed(_ cell: RelayTableCellModel, block: NSTextTableBlock) -> NSAttributedString {
        let result = displayText(cell.text)
        let trailing = result.length > 0 ? result.attributes(at: result.length - 1, effectiveRange: nil) : NativeProseCodec.attributed(AttributedString(" ")).attributes(at: 0, effectiveRange: nil)
        result.append(NSAttributedString(string: "\n", attributes: trailing))
        let snapshot = NSAttributedString(attributedString: result)
        snapshot.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: snapshot.length)) { value, range, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.textBlocks = [block]
            result.addAttribute(.paragraphStyle, value: style, range: range)
        }
        return result
    }

    private func displayText(_ text: NSAttributedString) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        var replacements: [(NSRange, String)] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard value is NSTextAttachment else { return }
            let label = (value as? any RelayTextAttachmentLabel)?.label ?? String(localized: "Attachment", bundle: .module)
            replacements.append((range, label))
        }
        for (range, label) in replacements.reversed() {
            var attributes = text.attributes(at: range.location, effectiveRange: nil)
            attributes[.attachment] = nil
            result.replaceCharacters(in: range, with: NSAttributedString(string: label, attributes: attributes))
        }
        return result
    }
}
