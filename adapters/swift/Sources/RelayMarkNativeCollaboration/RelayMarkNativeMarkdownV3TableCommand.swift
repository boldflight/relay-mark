import Foundation

/// Selection-scoped community table operations following prosemirror-tables
/// (TipTap TableKit) semantics, including row and column spans. Anchors and
/// snapshots bind an operation to the displayed cells; host authorization
/// remains outside Mark.
///
/// Each operation is simulated on the XML snapshot and then reduced to the
/// change y-prosemirror emits: retained rows, cells and cell blocks keep their
/// identity, attribute-only changes stay attribute updates, and type changes
/// or moved cells become delete-and-insert copies.
@MainActor
public enum RelayMarkNativeMarkdownV3TableCommand {
    public enum Operation: Sendable, CaseIterable {
        case addRowBefore, addRowAfter, addColumnBefore, addColumnAfter
        case deleteRow, deleteColumn, deleteTable
        case toggleHeaderCell, toggleHeaderRow, toggleHeaderColumn
        case mergeCells, splitCell
    }
    private typealias XML = RelayMarkNativeMarkdownV3XML
    private typealias Failure = RelayMarkNativeDocument.Failure
    private typealias Replacement = RelayMarkNativeDocument.SnapshotNodeReplacement
    private typealias AttributeUpdate = RelayMarkNativeDocument.SnapshotAttributeUpdate

    /// `headAnchor` extends the selection to the rectangle between two cells,
    /// as a ProseMirror CellSelection does; `mergeCells` requires it.
    public static func canApply(_ operation: Operation, document: RelayMarkNativeDocument,
                                cellAnchor: Data, expectedCellID: String,
                                headAnchor: Data? = nil, expectedHeadCellID: String? = nil) -> Bool {
        availableOperations(document: document, cellAnchor: cellAnchor, expectedCellID: expectedCellID,
                            headAnchor: headAnchor, expectedHeadCellID: expectedHeadCellID).contains(operation)
    }

    /// Every operation the current selection permits, resolving the document
    /// once, like a toolbar asking ProseMirror `can()` for each command.
    public static func availableOperations(document: RelayMarkNativeDocument, cellAnchor: Data,
                                           expectedCellID: String, headAnchor: Data? = nil,
                                           expectedHeadCellID: String? = nil) -> Set<Operation> {
        guard let snapshot = try? document.snapshot(),
              let context = try? context(document: document, anchor: (cellAnchor, expectedCellID),
                                         head: headAnchor.map { ($0, expectedHeadCellID ?? "") },
                                         expectedSnapshot: snapshot) else { return [] }
        return Set(Operation.allCases.filter { (try? change($0, context: context)) != nil })
    }

    public static func apply(_ operation: Operation, document: RelayMarkNativeDocument,
                             cellAnchor: Data, expectedCellID: String,
                             headAnchor: Data? = nil, expectedHeadCellID: String? = nil,
                             expectedSnapshot: Data) throws -> Data {
        let context = try context(document: document, anchor: (cellAnchor, expectedCellID),
                                  head: headAnchor.map { ($0, expectedHeadCellID ?? "") },
                                  expectedSnapshot: expectedSnapshot)
        let change = try change(operation, context: context)
        return try XML.apply(document: document, tree: change.tree, edits: change.edits,
                             attributeUpdates: change.attributes)
    }

    private struct Change {
        let tree: [String: Any]
        var edits: [Replacement] = []
        var attributes: [AttributeUpdate] = []
    }

    private struct Context {
        let tree: [String: Any]
        let anchorPath: [Int], headPath: [Int], tablePath: [Int]
    }

    private static func context(document: RelayMarkNativeDocument, anchor: (Data, String), head: (Data, String)?,
                                expectedSnapshot: Data) throws -> Context {
        guard document.integrationStatus().isComplete, try document.snapshot() == expectedSnapshot,
              try document.markdownV3ProseProjection().isEditable,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else {
            throw Failure.invalidAnchor
        }
        let anchorPath = try cellPath(anchor, document: document, tree: tree)
        let tablePath = Array(anchorPath.dropLast(2))
        var headPath = anchorPath
        if let head {
            headPath = try cellPath(head, document: document, tree: tree)
            guard Array(headPath.dropLast(2)) == tablePath else { throw Failure.unsupportedProseEdit }
        }
        return Context(tree: tree, anchorPath: anchorPath, headPath: headPath, tablePath: tablePath)
    }

    private static func change(_ operation: Operation, context: Context) throws -> Change {
        let (tree, anchorPath, headPath, tablePath) =
            (context.tree, context.anchorPath, context.headPath, context.tablePath)
        if operation == .deleteTable {
            let parentPath = Array(tablePath.dropLast())
            let siblings = try XML.children(XML.node(at: parentPath, in: tree))
            let paragraph: [String: Any] = ["kind": "element", "name": "paragraph",
                "attributes": ["relaymarkId": XML.freshID()], "children": [[String: Any]]()]
            // ProseMirror's replace fills a block+ container that would become empty.
            return Change(tree: tree, edits: [.init(parentPath: parentPath, start: tablePath.last!, count: 1,
                                                    nodes: siblings.count == 1 ? [paragraph] : [])])
        }
        let original = try XML.node(at: tablePath, in: tree)
        var table = annotated(original)
        let grid = try Grid(table)
        let anchorKey = Grid.Key(row: anchorPath[anchorPath.count - 2], index: anchorPath.last!)
        let headKey = Grid.Key(row: headPath[headPath.count - 2], index: headPath.last!)
        let rect = grid.rect(of: anchorKey).union(grid.rect(of: headKey))

        switch operation {
        case .addRowBefore: try addRow(&table, at: rect.top)
        case .addRowAfter: try addRow(&table, at: rect.bottom)
        case .addColumnBefore: try addColumn(&table, at: rect.left)
        case .addColumnAfter: try addColumn(&table, at: rect.right)
        case .deleteRow:
            guard rect.top > 0 || rect.bottom < grid.height else { throw Failure.unsupportedProseEdit }
            for row in (rect.top..<rect.bottom).reversed() { try removeRow(&table, row) }
        case .deleteColumn:
            guard rect.left > 0 || rect.right < grid.width else { throw Failure.unsupportedProseEdit }
            for column in (rect.left..<rect.right).reversed() { try removeColumn(&table, column) }
        case .toggleHeaderCell:
            // TipTap keeps prosemirror-tables' selection-based (deprecated) logic
            // for cells: selected headers become body cells, otherwise all
            // selected cells become headers.
            let keys = grid.cellsInRect(rect)
            let hasHeaders = keys.contains { grid.name(of: $0, in: table) == "tableHeader" }
            try setCellType(&table, keys: keys.filter { !hasHeaders || grid.name(of: $0, in: table) == "tableHeader" },
                            name: hasHeaders ? "tableCell" : "tableHeader")
        case .toggleHeaderRow, .toggleHeaderColumn:
            // Row/column toggles always address the first row/column and skip
            // the corner cell another enabled header already owns.
            let header = { (keys: [Grid.Key]) in keys.allSatisfy { grid.name(of: $0, in: table) == "tableHeader" } }
            let rowEnabled = header(grid.cellsInRect(.init(left: 0, top: 0, right: grid.width, bottom: 1)))
            let columnEnabled = header(grid.cellsInRect(.init(left: 0, top: 0, right: 1, bottom: grid.height)))
            let isRow = operation == .toggleHeaderRow
            let target: Grid.Rect = isRow
                ? .init(left: columnEnabled ? 1 : 0, top: 0, right: grid.width, bottom: 1)
                : .init(left: 0, top: rowEnabled ? 1 : 0, right: 1, bottom: grid.height)
            let enabled = isRow ? rowEnabled : columnEnabled
            try setCellType(&table, keys: grid.cellsInRect(target), name: enabled ? "tableCell" : "tableHeader")
        case .mergeCells:
            guard anchorKey != headKey else { throw Failure.unsupportedProseEdit }
            try merge(&table, grid: grid, rect: rect)
        case .splitCell:
            guard anchorKey == headKey else { throw Failure.unsupportedProseEdit }
            try split(&table, grid: grid, key: anchorKey)
        case .deleteTable:
            throw Failure.unsupportedProseEdit
        }
        // Browser order: tableEditing's fixTables, PaperTableRow, then
        // fixTables again for the appended transaction.
        try fixColumnWidths(&table)
        try removeCoveredRows(&table)
        try fixColumnWidths(&table)
        var change = Change(tree: tree)
        var levels: [[Replacement]] = [[], [], []]
        try diff(old: XML.children(original), new: XML.children(table), relative: [], tablePath: tablePath,
                 levels: &levels, updates: &change.attributes)
        // Deepest parents first, and descending indexes within each parent,
        // keep every path valid against the unedited document.
        change.edits = levels.reversed().flatMap { $0 }
        guard !change.edits.isEmpty || !change.attributes.isEmpty else { throw Failure.unsupportedProseEdit }
        return change
    }

    private static func cellPath(_ reference: (Data, String), document: RelayMarkNativeDocument,
                                 tree: [String: Any]) throws -> [Int] {
        guard let position = try document.resolve(anchor: reference.0), position.index == 0,
              position.path.count >= 3 else { throw Failure.invalidAnchor }
        let cell = try XML.node(at: position.path, in: tree)
        let table = try XML.node(at: Array(position.path.dropLast(2)), in: tree)
        guard isCell(cell), attributes(cell)["relaymarkId"] as? String == reference.1,
              table["name"] as? String == "table" else { throw Failure.invalidAnchor }
        return position.path
    }

    // MARK: prosemirror-tables operations

    private static func addColumn(_ table: inout [String: Any], at column: Int) throws {
        let grid = try Grid(table)
        var reference: Int? = column > 0 ? -1 : 0
        if grid.columnIsHeader(column + (reference ?? 0), in: table) {
            reference = column == 0 || column == grid.width ? nil : 0
        }
        var rows = try XML.children(table)
        var row = 0
        while row < grid.height {
            let index = row * grid.width + column
            if column > 0, column < grid.width, grid.slots[index - 1] == grid.slots[index] {
                let key = grid.slots[index], span = grid.rect(of: key)
                try updateCell(&rows, key) { $0 = addColSpan($0, at: column - span.left, count: 1) }
                row += span.bottom - span.top
            } else {
                let name = reference.map { grid.name(of: grid.slots[index + $0], in: table) } ?? "tableCell"
                var cells = try XML.children(rows[row])
                cells.insert(emptyCell(name), at: grid.position(row: row, column: column))
                rows[row]["children"] = cells
                row += 1
            }
        }
        table["children"] = rows
    }

    private static func addRow(_ table: inout [String: Any], at row: Int) throws {
        let grid = try Grid(table)
        guard grid.height < 256 else { throw Failure.unsupportedProseEdit }
        var reference: Int? = row > 0 ? -1 : 0
        if grid.rowIsHeader(row + (reference ?? 0), in: table) {
            reference = row == 0 || row == grid.height ? nil : 0
        }
        var rows = try XML.children(table)
        var cells: [[String: Any]] = []
        var column = 0
        while column < grid.width {
            let index = row * grid.width + column
            if row > 0, row < grid.height, grid.slots[index] == grid.slots[index - grid.width] {
                let key = grid.slots[index], span = grid.rect(of: key)
                try updateCell(&rows, key) { $0["rowspan"] = span.bottom - span.top + 1 }
                column += span.right - span.left
            } else {
                let name = reference.map { grid.name(of: grid.slots[index + $0 * grid.width], in: table) }
                cells.append(emptyCell(name ?? "tableCell"))
                column += 1
            }
        }
        let inserted: [String: Any] = ["kind": "element", "name": "tableRow",
                                       "attributes": ["relaymarkId": XML.freshID()], "children": cells]
        rows.insert(inserted, at: row)
        table["children"] = rows
    }

    private static func removeColumn(_ table: inout [String: Any], _ column: Int) throws {
        let grid = try Grid(table)
        var rows = try XML.children(table)
        var removals: [Grid.Key] = []
        var row = 0
        while row < grid.height {
            let key = grid.slots[row * grid.width + column], span = grid.rect(of: key)
            if span.right - span.left > 1 {
                try updateCell(&rows, key) { $0 = removeColSpan($0, at: column - span.left) }
            } else {
                removals.append(key)
            }
            row += span.bottom - span.top
        }
        for key in removals.reversed() {
            var cells = try XML.children(rows[key.row])
            cells.remove(at: key.index)
            rows[key.row]["children"] = cells
        }
        table["children"] = rows
    }

    private static func removeRow(_ table: inout [String: Any], _ row: Int) throws {
        let grid = try Grid(table)
        var rows = try XML.children(table)
        var moved: [(position: Int, cell: [String: Any])] = []
        var column = 0
        while column < grid.width {
            let index = row * grid.width + column, key = grid.slots[index], span = grid.rect(of: key)
            if row > 0, key == grid.slots[index - grid.width] {
                try updateCell(&rows, key) { $0["rowspan"] = span.bottom - span.top - 1 }
            } else if row + 1 < grid.height, key == grid.slots[index + grid.width] {
                // A cell continuing below moves down as a copy, like ProseMirror's insert.
                var copy = stripped(try XML.children(rows[key.row])[key.index])
                var attrs = attributes(copy)
                attrs["rowspan"] = span.bottom - span.top - 1
                copy["attributes"] = attrs
                moved.append((grid.position(row: row + 1, column: column), copy))
            }
            column = span.right
        }
        if !moved.isEmpty {
            var cells = try XML.children(rows[row + 1])
            for (offset, entry) in moved.enumerated() { cells.insert(entry.cell, at: entry.position + offset) }
            rows[row + 1]["children"] = cells
        }
        rows.remove(at: row)
        table["children"] = rows
    }

    /// RelayMark rows hold at least one cell. Merges and column deletion can
    /// leave a row covered entirely by rowspans; drop it and shorten those
    /// spans, as the browser's PaperTableRow normalization does.
    private static func removeCoveredRows(_ table: inout [String: Any]) throws {
        while true {
            let grid = try Grid(table)
            var rows = try XML.children(table)
            guard let row = rows.indices.first(where: { $0 > 0 && (try? XML.children(rows[$0]))?.isEmpty == true }) else {
                return
            }
            let covering = Set((0..<grid.width).map { grid.slots[row * grid.width + $0] })
            guard covering.allSatisfy({ $0.row < row }) else { throw Failure.unsupportedProseEdit }
            for key in covering {
                let span = grid.rect(of: key)
                try updateCell(&rows, key) { $0["rowspan"] = span.bottom - span.top - 1 }
            }
            rows.remove(at: row)
            table["children"] = rows
        }
    }

    private static func setCellType(_ table: inout [String: Any], keys: [Grid.Key], name: String) throws {
        var rows = try XML.children(table)
        for key in keys {
            var cells = try XML.children(rows[key.row])
            guard cells[key.index]["name"] as? String != name else { continue }
            // A type change is a new Yjs element, as y-prosemirror replaces it.
            var cell = stripped(cells[key.index])
            cell["name"] = name
            cells[key.index] = cell
            rows[key.row]["children"] = cells
        }
        table["children"] = rows
    }

    private static func merge(_ table: inout [String: Any], grid: Grid, rect: Grid.Rect) throws {
        guard !grid.cellsOverlap(rect) else { throw Failure.unsupportedProseEdit }
        var rows = try XML.children(table)
        var seen = Set<Grid.Key>(), target: Grid.Key?
        var content: [[String: Any]] = [], removals: [Grid.Key] = []
        for row in rect.top..<rect.bottom {
            for column in rect.left..<rect.right {
                let key = grid.slots[row * grid.width + column]
                guard seen.insert(key).inserted else { continue }
                if target == nil { target = key; continue }
                let cell = try XML.children(rows[key.row])[key.index]
                if !isEmpty(cell) { content += try XML.children(cell).map(stripped) }
                removals.append(key)
            }
        }
        guard let target, !removals.isEmpty else { throw Failure.unsupportedProseEdit }
        let span = grid.rect(of: target)
        try updateCell(&rows, target) { attrs in
            attrs = addColSpan(attrs, at: span.right - span.left, count: rect.right - rect.left - (span.right - span.left))
            attrs["rowspan"] = rect.bottom - rect.top
        }
        if !content.isEmpty {
            var cells = try XML.children(rows[target.row])
            cells[target.index]["children"] = (isEmpty(cells[target.index]) ? [] : try XML.children(cells[target.index])) + content
            rows[target.row]["children"] = cells
        }
        for key in removals.sorted(by: { ($0.row, $0.index) > ($1.row, $1.index) }) {
            var cells = try XML.children(rows[key.row])
            cells.remove(at: key.index)
            rows[key.row]["children"] = cells
        }
        table["children"] = rows
    }

    private static func split(_ table: inout [String: Any], grid: Grid, key: Grid.Key) throws {
        let rect = grid.rect(of: key)
        guard rect.right - rect.left > 1 || rect.bottom - rect.top > 1 else { throw Failure.unsupportedProseEdit }
        var rows = try XML.children(table)
        let cell = try XML.children(rows[key.row])[key.index]
        let name = cell["name"] as? String ?? "tableCell"
        var base = attributes(cell)
        base["colspan"] = 1
        base["rowspan"] = 1
        let widths = (base["colwidth"] as? [Any])?.map { ($0 as? NSNumber)?.intValue ?? 0 }
        let columnAttributes = (0..<(rect.right - rect.left)).map { index -> [String: Any] in
            var attrs = base
            if let widths {
                attrs["colwidth"] = index < widths.count && widths[index] > 0 ? [widths[index]] as Any : nil
            }
            return attrs
        }
        for row in rect.top..<rect.bottom {
            var position = grid.position(row: row, column: rect.left) + (row == rect.top ? 1 : 0)
            var cells = try XML.children(rows[row])
            for (index, attrs) in columnAttributes.enumerated() where row != rect.top || index > 0 {
                var inserted = emptyCell(name)
                var fresh = attrs
                fresh["relaymarkId"] = XML.freshID()
                inserted["attributes"] = fresh
                cells.insert(inserted, at: position)
                position += 1
            }
            rows[row]["children"] = cells
        }
        try updateCell(&rows, key) { attrs in
            let identity = attrs["relaymarkId"]
            attrs = columnAttributes[0]
            attrs["relaymarkId"] = identity
        }
        table["children"] = rows
    }

    // MARK: attributes and nodes

    fileprivate static func isCell(_ node: [String: Any]) -> Bool {
        ["tableCell", "tableHeader"].contains(node["name"] as? String ?? "")
    }

    fileprivate static func attributes(_ node: [String: Any]) -> [String: Any] {
        node["attributes"] as? [String: Any] ?? [:]
    }

    fileprivate static func span(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 1
    }

    private static func updateCell(_ rows: inout [[String: Any]], _ key: Grid.Key,
                                   _ change: (inout [String: Any]) -> Void) throws {
        var cells = try XML.children(rows[key.row])
        var attrs = attributes(cells[key.index])
        change(&attrs)
        cells[key.index]["attributes"] = attrs
        rows[key.row]["children"] = cells
    }

    private static func widths(_ attrs: [String: Any]) -> [Int]? {
        (attrs["colwidth"] as? [Any])?.map { ($0 as? NSNumber)?.intValue ?? 0 }
    }

    /// prosemirror-tables addColSpan. Its zero placeholders are not valid
    /// RelayMark widths, so the final projection refuses such a result.
    private static func addColSpan(_ attrs: [String: Any], at position: Int, count: Int) -> [String: Any] {
        var result = attrs
        result["colspan"] = span(attrs["colspan"]) + count
        if var list = widths(attrs) {
            list.insert(contentsOf: Array(repeating: 0, count: count), at: min(max(position, 0), list.count))
            result["colwidth"] = list
        }
        return result
    }

    private static func removeColSpan(_ attrs: [String: Any], at position: Int) -> [String: Any] {
        var result = attrs
        result["colspan"] = span(attrs["colspan"]) - 1
        if var list = widths(attrs) {
            if list.indices.contains(position) { list.remove(at: position) }
            result["colwidth"] = list.contains { $0 > 0 } ? list : nil
        }
        return result
    }

    /// The colwidth repair of prosemirror-tables' fixTables (computeMap and
    /// findBadColWidths). The browser applies it to every table change,
    /// including received ones, so native output must already satisfy it.
    private static func fixColumnWidths(_ table: inout [String: Any]) throws {
        let grid = try Grid(table)
        var rows = try XML.children(table)
        var known = [(width: Int, count: Int)?](repeating: nil, count: grid.width)
        for (row, rowNode) in rows.enumerated() {
            for index in try XML.children(rowNode).indices {
                let key = Grid.Key(row: row, index: index), rect = grid.rect(of: key)
                guard let list = widths(attributes(try XML.children(rowNode)[index])) else { continue }
                for _ in rect.top..<rect.bottom {
                    for offset in 0..<(rect.right - rect.left) where offset < list.count && list[offset] != 0 {
                        let column = rect.left + offset, value = list[offset]
                        if let previous = known[column], previous.width == value {
                            known[column] = (value, previous.count + 1)
                        } else if known[column] == nil || known[column]!.count == 1 {
                            known[column] = (value, 1)
                        }
                    }
                }
            }
        }
        guard known.contains(where: { $0 != nil && $0!.count < grid.height }) else { return }
        var seen = Set<Grid.Key>()
        for (slot, key) in grid.slots.enumerated() where seen.insert(key).inserted {
            let attrs = attributes(try XML.children(rows[key.row])[key.index])
            let colspan = span(attrs["colspan"]), current = widths(attrs)
            var updated: [Int]?
            for offset in 0..<colspan {
                guard let width = known[(slot + offset) % grid.width]?.width else { continue }
                if current == nil || offset >= current!.count || current![offset] != width {
                    if updated == nil { updated = current ?? Array(repeating: 0, count: colspan) }
                    if offset < updated!.count { updated![offset] = width } else { updated!.append(width) }
                }
            }
            if let updated { try updateCell(&rows, key) { $0["colwidth"] = updated } }
        }
        table["children"] = rows
    }

    private static func emptyCell(_ name: String) -> [String: Any] {
        let paragraph: [String: Any] = ["kind": "element", "name": "paragraph",
                                        "attributes": ["relaymarkId": XML.freshID()], "children": [[String: Any]]()]
        let attributes: [String: Any] = ["relaymarkId": XML.freshID(), "colspan": 1, "rowspan": 1]
        return ["kind": "element", "name": name, "attributes": attributes, "children": [paragraph]]
    }

    private static func isEmpty(_ cell: [String: Any]) -> Bool {
        guard let children = cell["children"] as? [[String: Any]], children.count == 1,
              ["paragraph", "heading", "codeBlock"].contains(children[0]["name"] as? String ?? "") else { return false }
        let content = children[0]["children"] as? [[String: Any]] ?? []
        return content.allSatisfy { child in
            let runs = child["delta"] as? [[String: Any]] ?? []
            return child["kind"] as? String == "text" && runs.allSatisfy { ($0["insert"] as? String)?.isEmpty == true }
        }
    }

    // MARK: identity-preserving diff

    private static let originKey = "__relaymarkTableOrigin"

    /// Marks rows, cells and cell blocks with their original table-relative path.
    private static func annotated(_ table: [String: Any]) -> [String: Any] {
        func mark(_ node: [String: Any], _ path: [Int]) -> [String: Any] {
            var result = node
            result[originKey] = path
            if path.count < 3, let children = node["children"] as? [[String: Any]] {
                result["children"] = children.enumerated().map { mark($1, path + [$0]) }
            }
            return result
        }
        var result = table
        result["children"] = (table["children"] as? [[String: Any]] ?? []).enumerated().map { mark($1, [$0]) }
        return result
    }

    private static func stripped(_ node: [String: Any]) -> [String: Any] {
        var result = node
        result[originKey] = nil
        if let children = node["children"] as? [[String: Any]] { result["children"] = children.map(stripped) }
        return result
    }

    private static func diff(old: [[String: Any]], new: [[String: Any]], relative: [Int], tablePath: [Int],
                             levels: inout [[Replacement]], updates: inout [AttributeUpdate]) throws {
        var kept: [(old: Int, new: Int)] = []
        for (index, node) in new.enumerated() {
            guard let origin = node[originKey] as? [Int], Array(origin.dropLast()) == relative,
                  let source = origin.last, old.indices.contains(source) else { continue }
            guard kept.last.map({ $0.old < source }) ?? true else { throw Failure.unsupportedProseEdit }
            kept.append((source, index))
        }
        var gaps: [Replacement] = []
        var previous = (old: -1, new: -1)
        for pair in kept + [(old.count, new.count)] {
            let inserted = new[(previous.new + 1)..<pair.new].map(stripped)
            let removed = pair.old - previous.old - 1
            if removed > 0 || !inserted.isEmpty {
                gaps.append(.init(parentPath: tablePath + relative, start: previous.old + 1,
                                  count: removed, nodes: inserted))
            }
            previous = pair
        }
        levels[relative.count].append(contentsOf: gaps.reversed())
        for pair in kept {
            let before = old[pair.old], after = new[pair.new]
            guard before["name"] as? String == after["name"] as? String else { throw Failure.unsupportedProseEdit }
            let oldAttrs = attributes(before), newAttrs = attributes(after)
            var changed: [String: Any] = [:]
            for key in Set(oldAttrs.keys).union(newAttrs.keys) {
                let a = oldAttrs[key] is NSNull ? nil : oldAttrs[key] as? NSObject
                let b = newAttrs[key] is NSNull ? nil : newAttrs[key] as? NSObject
                if a != b { changed[key] = b ?? NSNull() }
            }
            if !changed.isEmpty {
                updates.append(.init(path: tablePath + relative + [pair.old], attributes: changed))
            }
            if relative.count < 2 {
                try diff(old: XML.children(before), new: XML.children(after), relative: relative + [pair.old],
                         tablePath: tablePath, levels: &levels, updates: &updates)
            }
        }
    }
}

/// Rectangular cell map equivalent to prosemirror-tables' TableMap. Tables
/// ProseMirror would first repair with fixTables are refused.
@MainActor
private struct Grid {
    typealias Command = RelayMarkNativeMarkdownV3TableCommand
    struct Key: Hashable { let row: Int; let index: Int }
    struct Rect {
        let left: Int, top: Int, right: Int, bottom: Int
        func union(_ other: Rect) -> Rect {
            .init(left: min(left, other.left), top: min(top, other.top),
                  right: max(right, other.right), bottom: max(bottom, other.bottom))
        }
    }
    let width: Int, height: Int
    let slots: [Key]
    private let rects: [Key: Rect]

    init(_ table: [String: Any]) throws {
        let rows = table["children"] as? [[String: Any]] ?? []
        guard (1...256).contains(rows.count), rows.allSatisfy({ $0["name"] as? String == "tableRow" }) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let cellsByRow = rows.map { $0["children"] as? [[String: Any]] ?? [] }
        guard cellsByRow.allSatisfy({ $0.allSatisfy(Command.isCell) }) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let width = cellsByRow[0].reduce(0) { $0 + Command.span(Command.attributes($1)["colspan"]) }
        guard (1...256).contains(width) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        var slots = [Key?](repeating: nil, count: width * rows.count)
        var rects: [Key: Rect] = [:]
        for (row, cells) in cellsByRow.enumerated() {
            var column = 0
            for (index, cell) in cells.enumerated() {
                while column < width, slots[row * width + column] != nil { column += 1 }
                let attrs = Command.attributes(cell)
                let colspan = Command.span(attrs["colspan"]), rowspan = Command.span(attrs["rowspan"])
                guard colspan >= 1, rowspan >= 1, column + colspan <= width, row + rowspan <= rows.count else {
                    throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
                }
                let key = Key(row: row, index: index)
                for r in row..<(row + rowspan) {
                    for c in column..<(column + colspan) {
                        guard slots[r * width + c] == nil else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                        slots[r * width + c] = key
                    }
                }
                rects[key] = Rect(left: column, top: row, right: column + colspan, bottom: row + rowspan)
                column += colspan
            }
        }
        let complete = slots.compactMap { $0 }
        guard complete.count == slots.count else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        self.width = width
        self.height = rows.count
        self.slots = complete
        self.rects = rects
    }

    func rect(of key: Key) -> Rect { rects[key]! }

    func name(of key: Key, in table: [String: Any]) -> String {
        let rows = table["children"] as? [[String: Any]] ?? []
        let cells = rows[key.row]["children"] as? [[String: Any]] ?? []
        return cells[key.index]["name"] as? String ?? "tableCell"
    }

    func columnIsHeader(_ column: Int, in table: [String: Any]) -> Bool {
        (0..<height).allSatisfy { name(of: slots[$0 * width + column], in: table) == "tableHeader" }
    }

    func rowIsHeader(_ row: Int, in table: [String: Any]) -> Bool {
        (0..<width).allSatisfy { name(of: slots[row * width + $0], in: table) == "tableHeader" }
    }

    /// Child index before the first cell starting in `row` at or after `column`.
    func position(row: Int, column: Int) -> Int {
        Set((0..<column).map { slots[row * width + $0] }).filter { $0.row == row }.count
    }

    func cellsInRect(_ rect: Rect) -> [Key] {
        var seen = Set<Key>(), result: [Key] = []
        for row in rect.top..<rect.bottom {
            for column in rect.left..<rect.right {
                let index = row * width + column, key = slots[index]
                guard seen.insert(key).inserted else { continue }
                if column == rect.left, column > 0, slots[index - 1] == key { continue }
                if row == rect.top, row > 0, slots[index - width] == key { continue }
                result.append(key)
            }
        }
        return result
    }

    func cellsOverlap(_ rect: Rect) -> Bool {
        var seen = Set<Key>()
        for row in rect.top..<rect.bottom {
            for column in rect.left..<rect.right {
                let key = slots[row * width + column]
                guard seen.insert(key).inserted else { continue }
                let span = self.rect(of: key)
                if span.left < rect.left || span.top < rect.top || span.right > rect.right || span.bottom > rect.bottom {
                    return true
                }
            }
        }
        return false
    }
}
