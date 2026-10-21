import Foundation
import OSLog
import Observation
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkProseProjection
import RelayMarkSwift
import SwiftUI

/// Block structure commands: list starts and depth, callouts, tables, block
/// styles and headings.
extension RelayMarkEditorSession {
    public struct ListStartEdit: Identifiable {
        public let id = UUID()
        fileprivate let owner: UUID
        fileprivate let checkpoint: Data
        fileprivate let range: NSRange
        fileprivate let anchor: Data
        public let start: Int
    }

    enum ListStartFailure: LocalizedError {
        case selectionChanged, invalidStart
        var errorDescription: String? {
            switch self {
            case .selectionChanged: "The paper or selection changed. Select an ordered-list item and try again."
            case .invalidStart: "Enter a whole number from 1 to 1,000,000."
            }
        }
    }

    public func prepareListStartEdit() throws -> ListStartEdit {
        guard isEditable, pending == nil, activeComposition == nil,
                            let selection = nativeSelection, selection.location >= 0, selection.length >= 0 else {
            throw ListStartFailure.selectionChanged
        }
        let projection = try currentProjection()
        guard let row = projection.blockRanges.firstIndex(where: {
            selection.location >= $0.location && NSMaxRange(selection) <= NSMaxRange($0)
        }), var node = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any] else {
            throw ListStartFailure.selectionChanged
        }
        // The immediate containing list owns numbering. A nested bullet item
        // must not accidentally edit the numbering of its ordered ancestor.
        let listPath = Array(projection.blockPaths[row].dropLast(2))
        for index in listPath {
            guard let children = node["children"] as? [[String: Any]], children.indices.contains(index) else {
                throw ListStartFailure.selectionChanged
            }
            node = children[index]
        }
        guard node["name"] as? String == "orderedList" else { throw ListStartFailure.selectionChanged }
        let attrs = node["attributes"] as? [String: Any] ?? [:]
        return ListStartEdit(owner: compositionOwner, checkpoint: try document.encodeUpdate(), range: selection,
                             anchor: try document.anchor(path: listPath, index: 0), start: attrs["start"] as? Int ?? 1)
    }

    public func applyListStart(_ start: Int, review: ListStartEdit) throws {
        guard isEditable, pending == nil, activeComposition == nil, review.owner == compositionOwner,
              nativeSelection == review.range, review.checkpoint == (try document.encodeUpdate()) else {
            throw ListStartFailure.selectionChanged
        }
        guard (1...1_000_000).contains(start) else { throw ListStartFailure.invalidStart }
        guard start != review.start else { return }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(review.checkpoint)
        do {
            _ = try scratch.setRichOrderedListStart(anchor: review.anchor, expectedStart: review.start, start: start)
        }
        let expected = try scratch.richProseProjection().text
        guard supportsCurrentSchema(scratch), String(expected.characters) == String(text.characters) else {
            throw ListStartFailure.selectionChanged
        }
        let original = RelayMarkDeclaredCommandInput.orderedListStart(start: start)
        try original.validate()
        let revisionBefore = document.revision, textBefore = textRevision
        let change = try ownedChange({ try document.setRichOrderedListStart(anchor: review.anchor, expectedStart: review.start, start: start) }, separateHistoryItem: true, update: { $0.update })
        try show(change.update, after: revisionBefore, textBefore: textBefore)
        setNativeSelection(review.range)
        pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: change.update, inputIntent: .declaredCommand(original))
        retryPersistence()
    }

    public struct CalloutAppearanceEdit: Identifiable {
        public let id = UUID()
        fileprivate let owner: UUID
        fileprivate let checkpoint: Data
        fileprivate let range: NSRange
        fileprivate let anchor: Data
        public let calloutID: String
        public let tone: String
        public let emphasis: String
    }

    enum CalloutAppearanceFailure: LocalizedError {
        case changed, invalidAppearance
        var errorDescription: String? {
            switch self {
            case .changed: "The paper or selection changed. Select the callout and try again."
            case .invalidAppearance: "Choose a supported callout tone and emphasis."
            }
        }
    }

    public static let calloutTones = ["neutral", "primary", "secondary", "accent", "info", "success", "warning", "error"]
    public static let calloutEmphases = ["soft", "strong"]

    public struct CalloutTitleEdit {
        fileprivate let owner: UUID
        fileprivate let checkpoint: Data
        fileprivate let snapshot: Data
        fileprivate let range: NSRange
        fileprivate let anchor: Data
        public let calloutID: String
    }

    public typealias TableOperation = RelayMarkNativeRichTableCommand.Operation

    /// A table command bound to the displayed cells. A text selection that
    /// ends in another cell of the same table acts as a rectangular cell
    /// selection, as a ProseMirror CellSelection does for merging.
    public struct TableStructureEdit {
        fileprivate let owner: UUID
        fileprivate let checkpoint: Data
        fileprivate let snapshot: Data
        fileprivate let range: NSRange
        fileprivate let anchor: Data
        fileprivate let cellID: String
        fileprivate let head: Data?
        fileprivate let headCellID: String?
        fileprivate let selection: [Data]
        public let available: Set<TableOperation>
    }

    enum TableCommandFailure: LocalizedError, Equatable {
        case changed, unavailable(TableOperation)
        var errorDescription: String? {
            switch self {
            case .changed: "The paper or selection changed. Select a table cell and try again."
            case .unavailable(.mergeCells): "Select two or more cells forming a rectangle to merge them."
            case .unavailable(.splitCell): "Only a merged cell can be split."
            case .unavailable(.deleteRow): "A table keeps at least one row. Delete the table instead."
            case .unavailable(.deleteColumn): "A table keeps at least one column. Delete the table instead."
            case .unavailable: "This table operation is not available for the selected cells."
            }
        }
    }

    var hasTableSelection: Bool { (try? selectedTableCells()) != nil }

    /// Resolves the selection once and reports every permitted operation.
    public func prepareTableEdit() throws -> TableStructureEdit { try selectedTableCells() }

    func prepareTableCommand(_ operation: TableOperation) throws -> TableStructureEdit {
        let edit = try selectedTableCells()
        guard edit.available.contains(operation) else { throw TableCommandFailure.unavailable(operation) }
        return edit
    }

    private func selectedTableCells() throws -> TableStructureEdit {
        guard isEditable, pending == nil,
              activeComposition == nil, let selection = nativeSelection else {
            throw TableCommandFailure.changed
        }
        let projection = try currentProjection()
        let snapshot = try document.snapshot()
        guard let tree = try JSONSerialization.jsonObject(with: snapshot) as? [String: Any],
              let anchorCell = tableCell(at: selection.location, projection: projection, tree: tree) else {
            throw TableCommandFailure.changed
        }
        var headCell: (path: [Int], id: String)?
        if selection.length > 0, let end = tableCell(at: NSMaxRange(selection), projection: projection, tree: tree),
           end.id != anchorCell.id, end.path.dropLast(2) == anchorCell.path.dropLast(2) {
            headCell = end
        }
        let anchor = try document.anchor(path: anchorCell.path, index: 0)
        let head = try headCell.map { try document.anchor(path: $0.path, index: 0) }
        let available = RelayMarkNativeRichTableCommand.availableOperations(document: document,
            cellAnchor: anchor, expectedCellID: anchorCell.id, headAnchor: head, expectedHeadCellID: headCell?.id)
        return TableStructureEdit(owner: compositionOwner, checkpoint: try document.encodeUpdate(),
                                  snapshot: snapshot, range: selection, anchor: anchor, cellID: anchorCell.id,
                                  head: head, headCellID: headCell?.id, selection: try selectionAnchors(),
                                  available: available)
    }

    /// The innermost table cell containing the projected block at `location`.
    private func tableCell(at location: Int, projection: RelayMarkCollaborativeProse,
                           tree: [String: Any]) -> (path: [Int], id: String)? {
        let candidates = projection.blockRanges.indices.filter { index in
            location >= projection.blockRanges[index].location && location <= NSMaxRange(projection.blockRanges[index])
        }
        guard candidates.count == 1 else { return nil }
        var node = tree, prefix: [Int] = [], found: (path: [Int], id: String)?
        for index in projection.blockPaths[candidates[0]] {
            guard let children = node["children"] as? [[String: Any]], children.indices.contains(index) else { return nil }
            node = children[index]
            prefix.append(index)
            if ["tableCell", "tableHeader"].contains(node["name"] as? String ?? ""),
               let id = (node["attributes"] as? [String: Any])?["relaymarkId"] as? String {
                found = (prefix, id)
            }
        }
        guard let found, found.path.count >= 3 else { return nil }
        return found
    }

    func performTableCommand(_ operation: TableOperation, using edit: TableStructureEdit) throws {
        guard isEditable, pending == nil,
              activeComposition == nil, edit.owner == compositionOwner,
              nativeSelection == edit.range, edit.checkpoint == (try document.encodeUpdate()),
              edit.snapshot == (try document.snapshot()) else { throw TableCommandFailure.changed }
        guard edit.available.contains(operation) else { throw TableCommandFailure.unavailable(operation) }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(edit.checkpoint)
        do {
            _ = try RelayMarkNativeRichTableCommand.apply(operation, document: scratch,
                cellAnchor: edit.anchor, expectedCellID: edit.cellID, headAnchor: edit.head,
                expectedHeadCellID: edit.headCellID, expectedSnapshot: edit.snapshot)
        } catch { throw TableCommandFailure.unavailable(operation) }
        let expected = try scratch.richProseProjection()
        guard expected.isEditable else { throw TableCommandFailure.unavailable(operation) }
        let original = RelayMarkDeclaredCommandInput.table(operation: operation)
        try original.validate()
        let revisionBefore = document.revision, textBefore = textRevision
        let change = try ownedChange({ try RelayMarkNativeRichTableCommand.apply(operation, document: document,
            cellAnchor: edit.anchor, expectedCellID: edit.cellID, headAnchor: edit.head,
            expectedHeadCellID: edit.headCellID, expectedSnapshot: edit.snapshot) }, separateHistoryItem: true, update: { $0.update })
        try show(change.update, after: revisionBefore, textBefore: textBefore)
        // Map the caret through the change as ProseMirror maps its selection;
        // text removed with a row, column or table falls back to the nearest block.
        let mapped = try edit.selection.first.flatMap { try document.resolve(anchor: $0) }
            .flatMap { try projectionOffset(path: $0.path, index: $0.index) }
        let nearest = expected.blockRanges.first { NSMaxRange($0) >= edit.range.location }?.location
            ?? expected.blockRanges.last.map(NSMaxRange) ?? 0
        setNativeSelection(NSRange(location: mapped ?? nearest, length: 0))
        pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: change.update, inputIntent: .declaredCommand(original))
        retryPersistence()
    }

    func deleteTableNatively(at paperLocation: Int) -> Bool {
        setNativeSelection(NSRange(location: paperLocation, length: 0))
        do { try performTableCommand(.deleteTable, using: prepareTableCommand(.deleteTable)); return true }
        catch { return false }
    }

    public func performSelectedTableCommand(_ operation: TableOperation) {
        do { try performTableCommand(operation, using: prepareTableCommand(operation)) }
        catch { failure = error.localizedDescription }
    }

    enum CalloutTitleFailure: LocalizedError {
        case changed
        var errorDescription: String? {
            String(localized: "The paper or selection changed. Select an untitled callout and try again.", bundle: .module, comment: "Shown when a callout's target moved.")
        }
    }

    private func richNodePath(_ node: [String: Any], name: String, id: String, path: [Int] = []) -> [Int]? {
        if node["name"] as? String == name,
           (node["attributes"] as? [String: Any])?["relaymarkId"] as? String == id { return path }
        for (index, child) in (node["children"] as? [[String: Any]] ?? []).enumerated() {
            if let found = richNodePath(child, name: name, id: id, path: path + [index]) { return found }
        }
        return nil
    }

    public func prepareCalloutTitleInsertion() throws -> CalloutTitleEdit {
        guard isEditable, pending == nil,
              activeComposition == nil, let selection = nativeSelection,
              let callout = nativeCallouts.first(where: {
                  $0.titleRange == nil && selection.location >= $0.range.location &&
                      NSMaxRange(selection) <= NSMaxRange($0.range)
              }),
              let root = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any],
              let path = richNodePath(root, name: "callout", id: callout.id) else {
            throw CalloutTitleFailure.changed
        }
        return CalloutTitleEdit(owner: compositionOwner, checkpoint: try document.encodeUpdate(),
                                snapshot: try document.snapshot(), range: selection,
                                anchor: try document.anchor(path: path, index: 0), calloutID: callout.id)
    }

    func addCalloutTitle(using edit: CalloutTitleEdit) throws {
        guard isEditable, pending == nil,
              activeComposition == nil, edit.owner == compositionOwner,
              nativeSelection == edit.range, edit.checkpoint == (try document.encodeUpdate()),
              edit.snapshot == (try document.snapshot()) else { throw CalloutTitleFailure.changed }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(edit.checkpoint)
        _ = try scratch.addCalloutTitle(anchor: edit.anchor, expectedID: edit.calloutID,
                                       expectedSnapshot: edit.snapshot)
        let expected = try scratch.richProseProjection()
        guard expected.isEditable,
              let title = expected.callouts.first(where: { $0.id == edit.calloutID })?.titleRange,
              title.length == 5 else { throw CalloutTitleFailure.changed }
        let revisionBefore = document.revision, textBefore = textRevision
        let change = try ownedChange({ try document.addCalloutTitle(anchor: edit.anchor, expectedID: edit.calloutID,
                                                   expectedSnapshot: edit.snapshot).change }, separateHistoryItem: true, update: { $0.update })
        try show(change.update, after: revisionBefore, textBefore: textBefore)
        setNativeSelection(title)
        pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: change.update,
            inputIntent: .derived)
        retryPersistence()
    }

    public func addSelectedCalloutTitle() {
        do { try addCalloutTitle(using: prepareCalloutTitleInsertion()) }
        catch { failure = error.localizedDescription }
    }

    public func prepareCalloutAppearanceEdit() throws -> CalloutAppearanceEdit {
        guard isEditable, pending == nil,
              activeComposition == nil, let selection = nativeSelection,
              let callout = nativeCallouts.first(where: {
                  selection.location >= $0.range.location && NSMaxRange(selection) <= NSMaxRange($0.range)
              }),
              let root = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any] else {
            throw CalloutAppearanceFailure.changed
        }
        guard let path = richNodePath(root, name: "callout", id: callout.id) else { throw CalloutAppearanceFailure.changed }
        return CalloutAppearanceEdit(owner: compositionOwner, checkpoint: try document.encodeUpdate(),
            range: selection, anchor: try document.anchor(path: path, index: 0),
            calloutID: callout.id, tone: callout.tone, emphasis: callout.emphasis)
    }

    public func applyCalloutAppearance(tone: String, emphasis: String, review: CalloutAppearanceEdit) throws {
        guard isEditable, pending == nil,
              activeComposition == nil, review.owner == compositionOwner,
              nativeSelection == review.range, review.checkpoint == (try document.encodeUpdate()) else {
            throw CalloutAppearanceFailure.changed
        }
        guard Self.calloutTones.contains(tone), Self.calloutEmphases.contains(emphasis) else {
            throw CalloutAppearanceFailure.invalidAppearance
        }
        guard tone != review.tone || emphasis != review.emphasis else { return }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(review.checkpoint)
        _ = try scratch.setCalloutAppearance(anchor: review.anchor, expectedID: review.calloutID,
            expectedTone: review.tone, expectedEmphasis: review.emphasis, tone: tone, emphasis: emphasis)
        let expected = try scratch.richProseProjection()
        guard expected.isEditable, String(expected.text.characters) == String(text.characters),
              expected.callouts.contains(where: { $0.id == review.calloutID && $0.tone == tone && $0.emphasis == emphasis }) else {
            throw CalloutAppearanceFailure.changed
        }
        let revisionBefore = document.revision, textBefore = textRevision
        let change = try ownedChange({ try document.setCalloutAppearance(anchor: review.anchor, expectedID: review.calloutID,
            expectedTone: review.tone, expectedEmphasis: review.emphasis, tone: tone, emphasis: emphasis) }, separateHistoryItem: true, update: { $0.update })
        try show(change.update, after: revisionBefore, textBefore: textBefore)
        setNativeSelection(review.range)
        pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: change.update, inputIntent: .derived)
        retryPersistence()
    }

    private func selectedRichTextBlock() throws -> (index: Int, range: NSRange, name: String, level: Int?)? {
        guard isEditable, pending == nil,
              activeComposition == nil, let selection = nativeSelection else { return nil }
        let projection = try currentProjection()
        guard let row = projection.blockRanges.enumerated().first(where: { index, range in
            projection.blockPaths[index].count == 1 && selection.location >= range.location &&
                NSMaxRange(selection) <= NSMaxRange(range)
        }), let tree = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any],
              let blocks = tree["children"] as? [[String: Any]] else { return nil }
        let index = projection.blockPaths[row.offset][0]
        guard blocks.indices.contains(index), let name = blocks[index]["name"] as? String,
              ["paragraph", "heading"].contains(name) else { return nil }
        return (index, selection, name, (blocks[index]["attributes"] as? [String: Any])?["level"] as? Int)
    }

    public var canSetSelectedBlockStyle: Bool { (try? selectedRichTextBlock()) != nil }

    public func setSelectedBlockStyle(_ style: RelayMarkNativeBlockStyle) {
        guard isEditable else { return }
        do {
            guard let selected = try selectedRichTextBlock() else { return }
            if (style == .paragraph && selected.name == "paragraph") ||
                (selected.name == "heading" && style == .heading(selected.level ?? 1)) { return }
            let before = try document.snapshot()
            let revisionBefore = document.revision, textBefore = textRevision
            let change = try ownedChange({ try document.setRichBlockStyle(at: selected.index, style: style,
                                                              expectedSnapshot: before) }, separateHistoryItem: true, update: { $0.update })
            try show(change.update, after: revisionBefore, textBefore: textBefore)
            setNativeSelection(selected.range)
            pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: change.update, inputIntent: .derived)
            retryPersistence()
        } catch { failure = error.localizedDescription }
    }

    /// The selected list item's first paragraph, read from its own top-level node.
    private func selectedRichListParagraph() throws -> [Int]? {
        guard isEditable, pending == nil,
              activeComposition == nil, let selection = nativeSelection else { return nil }
        let projection = try currentProjection()
        guard let block = projection.block(containingUTF16: selection.location),
              NSMaxRange(selection) <= NSMaxRange(block.range),
              document.isRichListParagraph(path: block.path) else { return nil }
        return block.path
    }

    func handleNativeListIndent(backward: Bool) -> Bool {
        guard (try? selectedRichListParagraph()) != nil else { return false }
        if backward ? canOutdentSelectedListItem : canIndentSelectedListItem {
            changeSelectedListDepth(backward ? .outdent : .indent)
        }
        // At a list boundary, consume Tab without inserting a literal tab into prose.
        return true
    }

    public var canIndentSelectedListItem: Bool {
        guard let path = try? selectedRichListParagraph(), let paper = try? currentProjection() else { return false }
        return document.canChangeRichListDepth(paragraphPath: path, change: .indent, paper: paper)
    }

    public var canOutdentSelectedListItem: Bool {
        guard let path = try? selectedRichListParagraph(), let paper = try? currentProjection() else { return false }
        return document.canChangeRichListDepth(paragraphPath: path, change: .outdent, paper: paper)
    }

    public func changeSelectedListDepth(_ change: RelayMarkNativeListDepthChange) {
        do {
            guard let path = try selectedRichListParagraph(), let selection = nativeSelection else { return }
            let original = RelayMarkDeclaredCommandInput.listDepth(change: change)
            try original.validate()
            let revisionBefore = document.revision, textBefore = textRevision
            let (result, rewrites) = try reading { paper in
                let result = try ownedChange({ try document.changeRichListDepth(paragraphPath: path, change: change, paper: paper) },
                                             separateHistoryItem: true, update: { $0.update })
                return (result, rewritten(result, paper: paper))
            }
            // Only the items or nodes it rewrote are re-projected and re-rendered.
            let splice = rewrites.flatMap { self.splice($0, after: revisionBefore) }
            let projection = try currentProjection()
            text = projection.text
            setNativeSelection(selection)
            if let splice { textSplice = RelayTextSplice(from: textBefore, to: textRevision, ranges: splice.ranges, nodes: splice.nodes) }
            pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: result.update, inputIntent: .declaredCommand(original))
            retryPersistence()
        } catch { failure = error.localizedDescription }
    }

    private func selectedHeading() throws -> (anchor: Data, id: String?, level: Int)? {
        guard let selection = nativeSelection else { return nil }
        let projection = try currentProjection()
        guard let index = projection.blockRanges.firstIndex(where: {
            selection.location >= $0.location && NSMaxRange(selection) <= NSMaxRange($0)
        }), projection.blockPaths[index].count == 1,
            let tree = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any],
            let children = tree["children"] as? [[String: Any]] else { return nil }
        let path = projection.blockPaths[index]
        guard children.indices.contains(path[0]), children[path[0]]["name"] as? String == "heading",
            let attributes = children[path[0]]["attributes"] as? [String: Any],
            let level = attributes["level"] as? Int else { return nil }
        return (try document.anchor(path: path, index: 0), attributes["headingId"] as? String, level)
    }

    public var selectedHeadingLevel: Int? { (try? selectedHeading())?.level }

    /// An explicit block command, distinct from a text replacement. Persistence
    /// failure retains the exact pending transaction for the normal retry path.
    public func setSelectedHeadingLevel(_ level: Int) {
        guard isEditable, pending == nil, activeComposition == nil else { return }
        do {
            guard let heading = try selectedHeading(), heading.level != level else { return }
            let checkpoint = try document.encodeUpdate()
            let scratch = RelayMarkNativeDocument()
            try scratch.applyUpdate(checkpoint)
            do {
                _ = try scratch.setRichHeadingLevel(anchor: heading.anchor, expectedHeadingID: heading.id, level: level)
            }
            guard supportsCurrentSchema(scratch) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            let original = RelayMarkDeclaredCommandInput.heading(level: level)
            try original.validate()
            let revisionBefore = document.revision, textBefore = textRevision
            let change = try ownedChange({ try document.setRichHeadingLevel(anchor: heading.anchor, expectedHeadingID: heading.id, level: level) }, separateHistoryItem: true, update: { $0.update })
            try show(change.update, after: revisionBefore, textBefore: textBefore)
            pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: change.update, inputIntent: .declaredCommand(original))
            retryPersistence()
        } catch { failure = error.localizedDescription }
    }

}
