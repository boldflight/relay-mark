import Foundation
import RelayMarkProseProjection
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What the editor keeps beside TextKit's text for one paper view.
@MainActor
final class RelayPaperViewState {
    /// The session text revision, media revision and editability last shown.
    var renderedRevision: (text: Int, media: Int, editable: Bool)?
    /// The session task-state revision whose checkbox markers are drawn.
    var renderedTaskStateRevision = 0
    /// The session linked-task revision whose chips are drawn.
    var renderedLinkedTaskRevision = 0
    var tables = RelayTableSpans()
    var tableAttachments: [Int: RelayTableAttachment] = [:]
    /// Paper offsets, as the session gives them.
    var emptyBlocks: [RelayEmptyProseBlock] = []
    var taskItems: [RelayMarkCollaborativeProse.TaskItem] = []
    /// View offsets; peers' selections inside tables are not drawn.
    var remoteSelections: [RelayMarkRemoteSelection] = []
    /// The paragraphs the last viewport layout pass laid out; nil before the
    /// first pass. Markers are drawn for these only.
    var laidOut: NSTextRange?
    /// View offsets that folded sections hide, in order. TextKit does not lay out
    /// a paragraph that starts inside one; its text is unchanged.
    var hidden: [NSRange] = []
    /// Where a pointer can hover (macOS), heading disclosures show only on the
    /// hovered heading or the heading holding the caret, as on the web.
    var disclosuresFollowPointer = false
    /// The view offset of the heading under the pointer.
    var hoveredHeading: Int?

    func isHidden(_ offset: Int) -> Bool {
        var low = 0, high = hidden.count
        while low < high {
            let middle = (low + high) / 2
            if NSMaxRange(hidden[middle]) <= offset { low = middle + 1 } else { high = middle }
        }
        return low < hidden.count && hidden[low].location <= offset
    }

    /// Empty blocks at view offsets, for drawing.
    var viewEmptyBlocks: [RelayEmptyProseBlock] {
        guard !tables.spans.isEmpty else { return emptyBlocks }
        return emptyBlocks.compactMap { block in
            var block = block
            guard let offset = tables.view(block.offset) else { return nil }
            block.offset = offset
            return block
        }
    }
    /// Task items at view offsets, for drawing and hit-testing.
    var viewTaskItems: [RelayMarkCollaborativeProse.TaskItem] {
        guard !tables.spans.isEmpty else { return taskItems }
        return taskItems.compactMap { item in
            var item = item
            guard let range = tables.view(item.firstParagraphRange) else { return nil }
            item.firstParagraphRange = range
            return item
        }
    }
}

/// A heading's fold controls, in text-container coordinates: the chevron in the
/// paper's leading gutter, and when folded the expand control after its text.
struct RelayHeadingDisclosure {
    let heading: NSRange
    let chevron: CGRect
    let expand: CGRect?
    let folded: Bool
    /// Whether the chevron is drawn; it takes taps and clicks either way.
    let shown: Bool
}

/// The platform text view the editor drives: AppKit's or UIKit's paper view.
@MainActor
protocol RelayPaperTextView: AnyObject {
    var paper: RelayPaperViewState { get }
    var paperStorage: NSTextStorage { get }
    var textLayoutManager: NSTextLayoutManager? { get }
    var editingSession: (any RelayPaperTextEditing)? { get set }
    var retired: Bool { get }
    var isPaperEditable: Bool { get set }
    var hasMarkedInput: Bool { get }
    /// The selection in view offsets.
    var viewSelection: NSRange { get }
    /// The selection's ranges in view offsets, in order; a selection across
    /// mixed-direction text has several.
    var viewSelections: [NSRange] { get }
    /// The host's commands on the selection.
    var selectionActions: [RelayMarkSelectionAction] { get }
    /// Toggles the task whose first paragraph starts at a view offset.
    var onTaskCheckbox: ((Int) -> Bool)? { get }
    /// The session changed outside TextKit's own editing; the coordinator shows it.
    var onSessionEdit: (() -> Void)? { get }
    func showSelection(_ range: NSRange)
    func cancelCompositionCompletion()
    func unmarkPaperText()
    func applyEmptyTypingStyle()
    func paperNeedsDisplay()
    /// The whole text is about to be replaced: pending paste state no longer applies.
    func replaceAllText(_ text: NSAttributedString)
    /// Moves keyboard focus into a cell when the paper view has it.
    func focus(_ cell: RelayTableCellTextView, selecting range: NSRange)
    var tableUndoManager: UndoManager? { get }
}

extension RelayPaperTextView {
    var viewLength: Int { paperStorage.length }
    var paperLength: Int { paper.tables.paper(viewLength) }
    var paperSelection: NSRange { paper.tables.paper(viewSelection) }

    /// The paper's text: the view's, with each table's cells from the session.
    var paperString: String {
        let view = paperStorage.string as NSString
        guard !paper.tables.spans.isEmpty, let text = editingSession?.text else { return view as String }
        var result = "", copied = 0
        for span in paper.tables.spans {
            result += view.substring(with: NSRange(location: copied, length: span.view - copied))
            if let bounds = Range(span.table.canonicalRange, in: text) { result += String(text[bounds].characters) }
            copied = span.view + 1
        }
        return result + view.substring(from: copied)
    }

    func paperSubstring(_ range: NSRange) -> String? {
        if let view = paper.tables.view(range), NSMaxRange(view) <= viewLength {
            return (paperStorage.string as NSString).substring(with: view)
        }
        let whole = paperString as NSString
        return NSMaxRange(range) <= whole.length ? whole.substring(with: range) : nil
    }

    /// The paper's rich text as the session reads it.
    func paperValue(inferFontChanges: Bool = false) -> AttributedString? {
        guard !paper.tables.spans.isEmpty else { return NativeProseCodec.value(paperStorage, inferFontChanges: inferFontChanges) }
        guard let text = editingSession?.text else { return nil }
        var result = AttributedString(), copied = 0
        for span in paper.tables.spans {
            result += NativeProseCodec.value(paperStorage.attributedSubstring(from: NSRange(location: copied, length: span.view - copied)),
                                             inferFontChanges: inferFontChanges)
            guard let bounds = Range(span.table.canonicalRange, in: text) else { return nil }
            result += AttributedString(text[bounds])
            copied = span.view + 1
        }
        return result + NativeProseCodec.value(paperStorage.attributedSubstring(from: NSRange(location: copied, length: viewLength - copied)),
                                               inferFontChanges: inferFontChanges)
    }

    /// Changes the view's text storage outside TextKit's own editing as one
    /// content-storage transaction, so layout and the viewport see one change.
    func performPaperEdit<T>(_ edit: () -> T) -> T {
        guard let content = textLayoutManager?.textContentManager else { return edit() }
        var result: T?
        content.performEditingTransaction { result = edit() }
        return result!
    }

    /// Toggles an inline mark over every selected range together: on unless
    /// every range has it already. A caret toggles the mark for the next typing.
    func toggleMark(_ mark: RelayMarkFormattingMark) -> Bool {
        guard let session = editingSession else { return false }
        let ranges = viewSelections.map(paper.tables.paper).filter { $0.length > 0 }
        guard ranges.count > 1 else { return session.toggleMarkNatively(mark, range: paperSelection) }
        let text = session.text, flag = mark.inlineIntent
        return setMark(mark, enabled: !ranges.allSatisfy { range in
            Range(range, in: text).map { text[$0].runs.allSatisfy { ($0.inlinePresentationIntent ?? []).contains(flag) } } ?? false
        })
    }

    /// Runs the paper command a platform action names (the system's underline
    /// key or panel button), or refuses it when it does not apply here.
    @discardableResult
    func performPaperCommand(_ id: String) -> Bool {
        guard let session = editingSession, let command = RelayMarkEditorCommand.command(id: id),
              session.canPerform(command) else { RelayPaperRefusal.feedback(); return false }
        session.perform(command)
        onSessionEdit?()
        return true
    }

    /// Sets or removes an inline mark over every selected range.
    func setMark(_ mark: RelayMarkFormattingMark, enabled: Bool) -> Bool {
        guard let session = editingSession else { return false }
        let ranges = viewSelections.map(paper.tables.paper).filter { $0.length > 0 }
        var changed = false
        for range in ranges.reversed() { changed = session.formatNatively(range: range, mark: mark, enabled: enabled) || changed }
        return changed
    }

    /// What VoiceOver says about the checklist item at the caret, whose checkbox
    /// is drawn rather than read: a draft Task or a linked Task; VoiceOver reads it with the line.
    func paperAccessibilityContent() -> [(label: String, value: String)] {
        guard !retired, let session = editingSession, let item = paper.viewTaskItems.first(where: {
            NSLocationInRange(viewSelection.location, $0.firstParagraphRange) || NSMaxRange($0.firstParagraphRange) == viewSelection.location }) else { return [] }
        // A plain checklist item says nothing extra; only the two states that matter are heard.
        let value = item.entityID != nil ? String(localized: "Task", bundle: .module, comment: "VoiceOver value of a checklist item linked to a Relay Task.")
            : session.armedTaskDrafts.contains(item.id) ? String(localized: "Draft task", bundle: .module, comment: "VoiceOver value of a checklist item that becomes a Task when finished.")
            : nil
        return value.map { [(String(localized: "Checklist item", bundle: .module, comment: "VoiceOver label for the checklist item at the caret."), $0)] } ?? []
    }

    /// Commands VoiceOver offers on the paper: toggling the task at the caret,
    /// whose checkbox is drawn rather than read, and the host's commands on the
    /// selection, which belong in the Edit rotor (`edits`).
    func paperAccessibilityActions() -> [(name: String, edits: Bool, perform: () -> Bool)] {
        guard !retired else { return [] }
        var actions: [(name: String, edits: Bool, perform: () -> Bool)] = []
        let caret = viewSelection.location
        if let section = sectionAtCaret, let session = editingSession {
            let folded = session.foldedSections.contains(section.id)
            let name = folded ? String(localized: "Expand section", bundle: .module, comment: "VoiceOver action that shows a folded section's content.")
                : String(localized: "Collapse section", bundle: .module, comment: "VoiceOver action that hides a section's content under its heading.")
            actions.append((name, false, { [weak self] in self?.toggleSection(section.id) ?? false }))
        }
        guard isPaperEditable else { return actions }
        if let toggle = onTaskCheckbox, let item = paper.viewTaskItems.first(where: {
            NSLocationInRange(caret, $0.firstParagraphRange) || NSMaxRange($0.firstParagraphRange) == caret }) {
            let name = item.checked ? String(localized: "Mark as not done", bundle: .module, comment: "VoiceOver action that unchecks the task at the caret.") : String(localized: "Mark as done", bundle: .module, comment: "VoiceOver action that checks the task at the caret.")
            actions.append((name, false, { toggle(item.firstParagraphRange.location) }))
        }
        for action in selectionActions {
            actions.append((action.name, true, { [weak self] in self.map { action.perform($0.paperSelection) } ?? false }))
        }
        return actions
    }

    /// The section whose heading holds the caret.
    var sectionAtCaret: RelayPaperSection? {
        guard let heading = headingParagraph(at: viewSelection.location) else { return nil }
        let start = paper.tables.paper(heading.location)
        return editingSession?.sections.first { $0.heading.location == start }
    }

    /// Folds or unfolds a section and shows the result.
    @discardableResult func toggleSection(_ id: String) -> Bool {
        guard let session = editingSession, session.toggleSection(id) else { return false }
        refreshFolding()
        onSessionEdit?()
        return true
    }

    /// Hides what the session's folded sections hold, and shows what they no
    /// longer hold: only the paragraphs whose visibility changed are laid out again.
    func refreshFolding() {
        let hidden = (editingSession?.hiddenSectionRanges ?? []).compactMap { paper.tables.view($0) }
        guard hidden != paper.hidden else { return }
        let changed = (paper.hidden + hidden).reduce(nil as NSRange?) { union, range in union.map { NSUnionRange($0, range) } ?? range }
        paper.hidden = hidden
        if let changed, let manager = textLayoutManager, let range = RelayTextGeometry(manager)?.textRange(
            NSRange(location: changed.location, length: min(changed.length, viewLength - changed.location))) {
            manager.invalidateLayout(for: range)
            manager.textViewportLayoutController.layoutViewport()
        }
        paperNeedsDisplay()
    }

    /// The viewport finished a layout pass, for a scroll, an edit or a resize:
    /// markers and overlays are drawn again over the paragraphs it laid out.
    /// TextKit allows reading the controller's state only here.
    func viewportDidLayout(_ controller: NSTextViewportLayoutController) {
        paper.laidOut = controller.viewportRange
        paperNeedsDisplay()
    }

    /// The table's attachment character is laid out again, at its grid's new size.
    func tableChanged(_ table: RelayTableAttachment) {
        guard let span = paper.tables.spans.first(where: { $0.table === table }), let manager = textLayoutManager,
              let content = manager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: span.view),
              let end = content.location(start, offsetBy: 1), let range = NSTextRange(location: start, end: end) else { return }
        manager.invalidateLayout(for: range)
    }
}

/// The editing logic shared by the AppKit and UIKit paper views: every edit is
/// a range command into the session, and its result comes back as a splice.
@MainActor
final class RelayPaperEditor<Session: RelayPaperTextEditing>: RelayTableEditing {
    var session: Session
    var mediaImages: RelayMarkImageStore?
    var updating = false
    var composition: Session.Composition?
    /// A keystroke inside one text leaf, applied without reading the whole paper.
    var pendingTyping: (view: NSRange, paper: NSRange, text: String)?
    private weak var view: (any RelayPaperTextView)?
    var attachedView: (any RelayPaperTextView)? { view }
    /// The last change TextKit made to the view's characters on its own.
    private var textKitEdit: (range: NSRange, delta: Int)?
    private var storageObserver: NSObjectProtocol?

    init(session: Session) { self.session = session }

    private var mediaRevision: Int { mediaImages?.revision ?? 0 }
    private func owns(_ view: any RelayPaperTextView) -> Bool {
        !view.retired && (view.editingSession == nil || view.editingSession === session)
    }

    func attach(_ view: any RelayPaperTextView) {
        self.view = view
        if let storageObserver { NotificationCenter.default.removeObserver(storageObserver) }
        storageObserver = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification,
            object: view.paperStorage, queue: nil) { [weak self] notification in
            guard let storage = notification.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) else { return }
            let range = storage.editedRange, delta = storage.changeInLength
            MainActor.assumeIsolated {
                guard let self, !self.updating else { return }
                self.textKitEdit = (range, delta)
            }
        }
    }

    // MARK: Input

    /// Decides a replacement TextKit is about to make in the paper view.
    func shouldChange(_ view: any RelayPaperTextView, range: NSRange, replacement: String, pasting: Bool) -> Bool {
        guard !updating, owns(view), session.isEditable, NSMaxRange(range) <= view.viewLength else { return false }
        pendingTyping = nil
        let tables = view.paper.tables
        // Backspace after a table or Delete before one selects the whole table first.
        if replacement.isEmpty, range.length == 1, let span = tables.spans.first(where: {
            range.location == $0.view + 1 || NSMaxRange(range) == $0.view }) {
            view.showSelection(NSRange(location: span.view, length: 1))
            return false
        }
        // A selected table, as Notes treats one: Delete removes it, and typing replaces it.
        if range.length == 1, let span = tables.span(atView: range.location) {
            replaceTable(span, with: replacement, in: view)
            return false
        }
        if tables.touchesTableLine(range) { refuse(); return false }
        let paper = tables.paper(range)
        // A keystroke completing a typed Markdown shortcut becomes its structure or mark.
        if composition == nil, !view.hasMarkedInput, !pasting,
           session.applyInputRuleNatively(range: paper, replacement: replacement) {
            update(view)
            return false
        }
        if composition == nil, !view.hasMarkedInput, !pasting,
           session.canTypeNatively(range: paper, replacement: replacement) {
            pendingTyping = (range, paper, replacement)
            return true
        }
        // Return and joining blocks run as one windowed command; the view
        // shows its splice instead of TextKit's own edit.
        if composition == nil, !view.hasMarkedInput, !pasting,
           session.editStructureNatively(range: paper, replacement: replacement) {
            update(view)
            return false
        }
        // Other inserted text (dictation, Services, a multi-line insertion) is
        // inserted as plain text is pasted, at the cost of the blocks it touches.
        if !replacement.isEmpty, composition == nil, !view.hasMarkedInput, !pasting,
           session.pastePlainTextNatively(range: paper, text: replacement) {
            update(view)
            return false
        }
        // No range command takes it: the paper is unchanged, and says so. Marked input
        // is the exception; it stays in the view until the input method commits it.
        if composition != nil || view.hasMarkedInput { return true }
        refuse()
        return false
    }

    /// Decides a replacement over every range of the selection. A selection
    /// across mixed-direction text has several: the text replaces the first and
    /// the others are deleted, last first, never the text between them.
    func shouldChange(_ view: any RelayPaperTextView, ranges: [NSRange], replacement: String) -> Bool {
        let ranges = ranges.sorted { $0.location < $1.location }
        guard ranges.count > 1 else {
            return shouldChange(view, range: ranges.first ?? view.viewSelection, replacement: replacement, pasting: false)
        }
        guard !updating, owns(view), session.isEditable, composition == nil, !view.hasMarkedInput,
              ranges.allSatisfy({ NSMaxRange($0) <= view.viewLength }) else { return false }
        pendingTyping = nil
        let tables = view.paper.tables
        guard !ranges.contains(where: tables.touchesTableLine) else { refuse(); return false }
        for (index, range) in ranges.enumerated().reversed() {
            let paper = tables.paper(range), text = index == 0 ? replacement : ""
            let applied = session.canTypeNatively(range: paper, replacement: text) && session.typeNatively(range: paper, replacement: text)
                || session.editStructureNatively(range: paper, replacement: text)
            guard applied else { refuse(); break }
        }
        let first = tables.paper(ranges[0])
        session.setNativeSelection(NSRange(location: first.location + replacement.utf16.count, length: 0))
        update(view)
        return false
    }

    private func refuse() { RelayPaperRefusal.feedback() }

    private func replaceTable(_ span: RelayTableSpan, with replacement: String, in view: any RelayPaperTextView) {
        guard session.deleteTableNatively(at: span.table.canonicalRange.location) else { refuse(); return }
        if !replacement.isEmpty, let caret = session.nativeSelection,
           !session.editStructureNatively(range: caret, replacement: replacement) { refuse() }
        update(view)
    }

    /// TextKit changed the paper view's text: a keystroke the session takes in
    /// place, or marked input the input method committed.
    func didChange(_ view: any RelayPaperTextView) {
        guard !updating, owns(view) else { return }
        if view.hasMarkedInput { return }
        let unannounced = textKitEdit
        textKitEdit = nil
        if let typing = pendingTyping {
            pendingTyping = nil
            if composition == nil, typed(typing, in: view) { return }
        }
        // Committed marked input inside one leaf, or as a block's first text, is adopted as typing.
        if let token = composition, adopt(in: view, {
            session.commitCompositionNatively(from: token, renderedLength: view.paperLength) { range in view.paperSubstring(range) }
        }) {
            composition = nil
            return
        }
        guard let composition else {
            // TextKit changed the text without asking (a programmatic insertion):
            // the same change goes to the session as a range command.
            if let edit = unannounced {
                if apply(edit, in: view) { return }
                refuse()
            }
            view.paper.renderedRevision = nil
            update(view)
            return
        }
        // Marked input committed across leaves goes through the session's composition commit.
        view.paper.tables.resync(view.paperStorage)
        guard let proposed = view.paperValue() else { update(view); return }
        let selection = view.paperSelection
        do {
            try session.commitComposition(proposed, from: composition)
            session.setNativeSelection(selection)
        } catch { /* The session retains a conflicted composition for review. */ }
        self.composition = nil
        update(view)
    }

    private func apply(_ edit: (range: NSRange, delta: Int), in view: any RelayPaperTextView) -> Bool {
        let old = NSRange(location: edit.range.location, length: edit.range.length - edit.delta)
        guard old.length >= 0, NSMaxRange(edit.range) <= view.viewLength, !view.paper.tables.touchesTableLine(old) else { return false }
        let replacement = (view.paperStorage.string as NSString).substring(with: edit.range)
        let paper = view.paper.tables.paper(old)
        if session.canTypeNatively(range: paper, replacement: replacement),
           typed((view: old, paper: paper, text: replacement), in: view) { return true }
        // The view shows TextKit's version; the session's version replaces it.
        guard session.editStructureNatively(range: paper, replacement: replacement) ||
              !replacement.isEmpty && session.pastePlainTextNatively(range: paper, text: replacement) else { return false }
        view.paper.renderedRevision = nil
        update(view)
        return true
    }

    func selectionDidChange(_ view: any RelayPaperTextView) {
        // A keystroke TextKit is inserting moves the caret before the session types it;
        // the session places the caret itself, keeping marks stored for that keystroke.
        guard !updating, owns(view), !view.hasMarkedInput, pendingTyping == nil else { return }
        session.setNativeSelection(view.paperSelection)
        view.refreshFolding()
        // The heading holding the caret shows its chevron where chevrons follow the pointer.
        if view.paper.disclosuresFollowPointer { view.paperNeedsDisplay() }
        view.applyEmptyTypingStyle()
    }

    /// Ends a composition with the paper the view shows.
    func finishComposition(_ view: any RelayPaperTextView) throws {
        guard !view.retired, view.editingSession === session else { throw CancellationError() }
        guard let token = composition else { return }
        let wasUpdating = updating
        updating = true
        defer { updating = wasUpdating }
        composition = nil
        defer { session.cancelComposition(token) }
        view.unmarkPaperText()
        view.cancelCompositionCompletion()
        view.paper.tables.resync(view.paperStorage)
        if session.isEditable, let candidate = view.paperValue() {
            let selection = view.paperSelection
            try session.commitComposition(candidate, from: token)
            session.setNativeSelection(selection)
        }
        update(view)
    }

    // MARK: Showing the session

    func update(_ view: any RelayPaperTextView) {
        guard owns(view) else { return }
        pendingTyping = nil
        if view.editingSession == nil { view.editingSession = session }
        let wasUpdating = updating
        updating = true
        defer { updating = wasUpdating }
        view.isPaperEditable = session.isEditable
        if view.hasMarkedInput, view.isPaperEditable { return }
        if !view.isPaperEditable {
            if let composition { session.cancelComposition(composition) }
            composition = nil; view.cancelCompositionCompletion(); view.unmarkPaperText()
        }
        // Observed, so a host tick (which changes a task's state, not the paper's text) re-renders;
        // compared as one number, never by reading every task item per update.
        let taskState = session.taskStateRevision
        // A Task's status draws in its chip only: a redraw, never a re-render of the text.
        if view.paper.renderedLinkedTaskRevision != session.linkedTaskRevision {
            view.paper.renderedLinkedTaskRevision = session.linkedTaskRevision
            view.paperNeedsDisplay()
        }
        let revision = (text: session.textRevision, media: mediaRevision, editable: session.isEditable)
        if let rendered = view.paper.renderedRevision, rendered == revision {
            if view.paper.renderedTaskStateRevision == taskState {
                syncSelection(view)
                return
            }
            view.paper.renderedRevision = nil
        }
        if let rendered = view.paper.renderedRevision, let splice = session.textSplice,
           rendered == (splice.from, revision.media, revision.editable), splice.to == revision.text, view.performPaperEdit({ applied(splice, to: view) }) {
            view.paper.renderedRevision = revision
            syncSelection(view)
            return
        }
        view.paper.renderedRevision = revision
        view.paper.renderedTaskStateRevision = taskState
        view.paper.emptyBlocks = session.nativeEmptyBlocks
        view.paper.taskItems = session.nativeTaskItems
        let rendered = NativeProseCodec.viewText(session.text, emptyBlocks: view.paper.emptyBlocks,
            tableCells: session.nativeTableCells, callouts: session.nativeCallouts, taskItems: view.paper.taskItems,
            inlineAtoms: session.nativeInlineAtoms, blockAtoms: session.nativeBlockAtoms,
            authoredWidgets: session.nativeAuthoredWidgets, entityReferenceAtoms: session.nativeEntityReferenceAtoms,
            mediaAtoms: session.nativeMediaAtoms, suggestionAtoms: session.nativeSuggestionAtoms,
            mediaImages: mediaImages) { [unowned view] in self.table(in: view, identity: $0, start: $1, cells: $2) }
        view.paper.tables = RelayTableSpans(spans: rendered.spans)
        let shown = Set(rendered.spans.map(\.table.identity))
        view.paper.tableAttachments = view.paper.tableAttachments.filter { shown.contains($0.key) }
        if view.paperStorage != rendered.text { view.replaceAllText(rendered.text) }
        syncSelection(view)
    }

    private func table(in view: any RelayPaperTextView, identity: Int, start: Int, cells: [RelayTableCellModel]) -> RelayTableAttachment {
        if let table = view.paper.tableAttachments[identity] {
            table.update(start: start, cells: cells)
            return table
        }
        let table = RelayTableAttachment(identity: identity, start: start, cells: cells)
        table.editor = self
        view.paper.tableAttachments[identity] = table
        return table
    }

    private func syncSelection(_ view: any RelayPaperTextView) {
        let tables = view.paper.tables
        if let range = session.nativeSelection {
            if let hit = tables.table(holding: range) {
                let cell = hit.table.paperRange(of: hit.cell)
                view.focus(hit.table.grid.cellView(hit.cell), selecting: NSRange(location: range.location - cell.location, length: range.length))
            } else if let shown = tables.view(range), NSMaxRange(shown) <= view.viewLength, view.viewSelection != shown {
                view.showSelection(shown)
            }
        }
        view.applyEmptyTypingStyle()
        view.paper.remoteSelections = tables.spans.isEmpty ? session.remoteSelections : session.remoteSelections.compactMap { peer in
            guard let range = tables.view(peer.range), let caret = tables.view(peer.caretLocation) else { return nil }
            return RelayMarkRemoteSelection(id: peer.id, name: peer.name, color: peer.color, range: range, caretLocation: caret)
        }
        view.refreshFolding()
        view.paperNeedsDisplay()
    }

    /// Paper metadata moves with an in-place edit; no paper-wide read.
    private func shift(_ view: any RelayPaperTextView, replacing range: NSRange, by delta: Int) {
        let end = NSMaxRange(range)
        view.paper.taskItems = view.paper.taskItems.map { item in
            var item = item, paragraph = item.firstParagraphRange
            if paragraph.location <= range.location && NSMaxRange(paragraph) >= end { paragraph.length += delta }
            else if paragraph.location >= end { paragraph.location += delta }
            item.firstParagraphRange = paragraph
            return item
        }
        view.paper.emptyBlocks = view.paper.emptyBlocks.map { block in
            var block = block
            if block.offset >= end { block.offset += delta }
            return block
        }
    }

    /// A peer's update or a command replaces just its leaves, rows or top-level nodes.
    private func applied(_ splice: RelayTextSplice, to view: any RelayPaperTextView) -> Bool {
        let storage = view.paperStorage
        storage.beginEditing()
        defer { storage.endEditing() }
        if let nodes = splice.nodes {
            guard splice.ranges.count == 1, let (old, new) = splice.ranges.first else { return false }
            let delta = new.length - old.length, content = nodes.content
            func place(_ location: Int) -> Int? {
                location < content.location ? location : location >= NSMaxRange(content) ? location + delta : nil
            }
            func placeMetadata() {
                view.paper.taskItems = view.paper.taskItems.compactMap { item in
                    var item = item
                    guard let location = place(item.firstParagraphRange.location) else { return nil }
                    item.firstParagraphRange.location = location
                    return item
                } + nodes.taskItems
                view.paper.taskItems.sort { $0.firstParagraphRange.location < $1.firstParagraphRange.location }
                view.paper.emptyBlocks = view.paper.emptyBlocks.compactMap { block in
                    var block = block
                    guard let offset = place(block.offset) else { return nil }
                    block.offset = offset
                    return block
                } + nodes.emptyBlocks
                view.paper.emptyBlocks.sort { $0.offset < $1.offset }
            }
            if let index = view.paper.tables.table(containing: old) {
                let table = view.paper.tables.spans[index].table
                guard replaceRows(of: table, old: old, new: new, nodes: nodes) else { return false }
                view.paper.tables.paperEdited(inTable: index, delta: delta)
                placeMetadata()
                view.tableChanged(table)
                return true
            }
            guard let shown = view.paper.tables.view(old), NSMaxRange(shown) <= storage.length,
                  let bounds = Range(new, in: session.text) else { return false }
            let piece = NativeProseCodec.viewText(AttributedString(session.text[bounds]), emptyBlocks: nodes.emptyBlocks,
                tableCells: nodes.tableCells, callouts: nodes.callouts, taskItems: nodes.taskItems,
                inlineAtoms: nodes.inlineAtoms, blockAtoms: nodes.blockAtoms, authoredWidgets: nodes.authoredWidgets,
                entityReferenceAtoms: nodes.entityReferenceAtoms, mediaAtoms: nodes.mediaAtoms,
                suggestionAtoms: nodes.suggestionAtoms, mediaImages: mediaImages, startingAt: new.location) { [unowned view] in
                    self.table(in: view, identity: $0, start: $1, cells: $2)
                }
            storage.replaceCharacters(in: shown, with: piece.text)
            view.paper.tables.replace(view: shown, paperDelta: delta, viewLength: piece.text.length,
                                      with: piece.spans.map { RelayTableSpan(view: $0.view + shown.location, table: $0.table) })
            for span in piece.spans { view.tableChanged(span.table) }
            placeMetadata()
            return true
        }
        for (old, new) in splice.ranges {
            let delta = new.length - old.length
            if let hit = view.paper.tables.table(holding: old),
               let index = view.paper.tables.spans.firstIndex(where: { $0.table === hit.table }) {
                let cell = hit.table.paperRange(of: hit.cell)
                let edited = NSRange(location: cell.location, length: cell.length + delta)
                guard let bounds = Range(edited, in: session.text) else { return false }
                let text = NativeProseCodec.attributed(AttributedString(session.text[bounds]), startingAt: edited.location)
                hit.table.cellEdited(hit.cell, text: text, delta: delta)
                if hit.table.isGridLoaded {
                    hit.table.grid.refresh(hit.cell)
                    if hit.table.grid.cellDidChange(hit.cell) { view.tableChanged(hit.table) }
                }
                view.paper.tables.paperEdited(inTable: index, delta: delta)
                shift(view, replacing: old, by: delta)
                continue
            }
            guard let shown = view.paper.tables.view(old) else { return false }
            shift(view, replacing: old, by: delta)
            view.paper.tables.viewEdited(at: NSMaxRange(shown), delta: delta)
            guard NativeProseCodec.splice(storage, replacing: shown, with: session.text, range: new,
                                          taskItems: view.paper.taskItems) else { return false }
        }
        return true
    }

    /// Rows of a table re-projected in place, when the new text is only this table's cells.
    private func replaceRows(of table: RelayTableAttachment, old: NSRange, new: NSRange, nodes: RelayNativeRegion) -> Bool {
        guard let bounds = Range(new, in: session.text) else { return false }
        let piece = NativeProseCodec.attributed(AttributedString(session.text[bounds]), tableCells: nodes.tableCells,
            callouts: nodes.callouts, inlineAtoms: nodes.inlineAtoms, blockAtoms: nodes.blockAtoms,
            authoredWidgets: nodes.authoredWidgets, entityReferenceAtoms: nodes.entityReferenceAtoms,
            mediaAtoms: nodes.mediaAtoms, suggestionAtoms: nodes.suggestionAtoms, mediaImages: mediaImages,
            startingAt: new.location)
        let groups = NativeProseCodec.tableModels(nodes.tableCells, in: piece, base: new.location)
        guard groups.count == 1, let group = groups.first, group.identity == table.identity else { return false }
        // Outside its cells the new text may hold only the separators between rows.
        let text = piece.string as NSString
        let inner = NSRange(location: group.range.location - new.location, length: group.range.length)
        guard text.substring(to: inner.location).allSatisfy({ $0 == "\n" }),
              text.substring(from: NSMaxRange(inner)).allSatisfy({ $0 == "\n" }) else { return false }
        table.replaceCells(meeting: old, delta: new.length - old.length, with: group.cells.map { cell in
            var cell = cell; cell.range.location += group.range.location; return cell
        })
        return true
    }

    // MARK: Typing adopted in place

    private func typed(_ typing: (view: NSRange, paper: NSRange, text: String), in view: any RelayPaperTextView) -> Bool {
        adopt(in: view) {
            session.typeNatively(range: typing.paper, replacement: typing.text) ? (typing.paper, typing.text) : nil
        }
    }

    /// Adopts an edit TextKit already shows, which the session applied inside one leaf.
    /// TextKit shows the typed characters; only they are restyled.
    private func adopt(in view: any RelayPaperTextView, _ edit: () -> (range: NSRange, text: String)?) -> Bool {
        let shown = view.paper.renderedRevision?.text == session.textRevision
        guard let typing = edit() else { return false }
        if shown, let location = view.paper.tables.view(typing.range.location) {
            view.paper.renderedRevision = (session.textRevision, mediaRevision, session.isEditable)
            let delta = typing.text.utf16.count - typing.range.length
            shift(view, replacing: typing.range, by: delta)
            view.paper.tables.viewEdited(at: location + typing.range.length, delta: delta)
            view.performPaperEdit {
                NativeProseCodec.restyle(view.paperStorage, range: NSRange(location: location, length: typing.text.utf16.count),
                                         paper: typing.range.location, from: session.text, taskItems: view.paper.taskItems)
            }
        }
        session.setNativeSelection(view.paperSelection)
        update(view)
        return true
    }

    // MARK: Table cells

    var tablesEditable: Bool { session.isEditable && !(view?.retired ?? true) }
    var tableUndoManager: UndoManager? { view?.tableUndoManager }

    /// A cell's text view changed: the one replacement it made goes to the
    /// session as typing, or as a structural command, at the cell's paper offsets.
    func tableCellDidChange(_ table: RelayTableAttachment, at index: Int, text: NSAttributedString) {
        guard !updating, let view, owns(view), session.isEditable, table.cells.indices.contains(index) else { return }
        let before = table.cells[index].text.string as NSString, after = text.string as NSString
        var prefix = 0
        while prefix < before.length, prefix < after.length, before.character(at: prefix) == after.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < before.length - prefix, suffix < after.length - prefix,
              before.character(at: before.length - 1 - suffix) == after.character(at: after.length - 1 - suffix) { suffix += 1 }
        let local = NSRange(location: prefix, length: before.length - prefix - suffix)
        let replacement = after.substring(with: NSRange(location: prefix, length: after.length - prefix - suffix))
        guard local.length > 0 || !replacement.isEmpty else { return }
        let cell = table.paperRange(of: index)
        let paper = NSRange(location: cell.location + local.location, length: local.length)
        let shown = view.paper.renderedRevision?.text == session.textRevision
        let wasUpdating = updating
        updating = true
        defer { updating = wasUpdating }
        if !replacement.contains("\n"), session.canTypeNatively(range: paper, replacement: replacement),
           session.typeNatively(range: paper, replacement: replacement) {
            let delta = replacement.utf16.count - local.length
            let typed = NSTextStorage(attributedString: text)
            NativeProseCodec.restyle(typed, range: NSRange(location: local.location, length: replacement.utf16.count),
                                     paper: paper.location, from: session.text, taskItems: [])
            table.cellEdited(index, text: typed, delta: delta)
            if let span = view.paper.tables.spans.firstIndex(where: { $0.table === table }) {
                view.paper.tables.paperEdited(inTable: span, delta: delta)
            }
            shift(view, replacing: paper, by: delta)
            if shown { view.paper.renderedRevision = (session.textRevision, mediaRevision, session.isEditable) }
            table.grid.refresh(index)
            if table.grid.cellDidChange(index) { view.tableChanged(table) }
            session.setNativeSelection(NSRange(location: paper.location + replacement.utf16.count, length: 0))
            updating = wasUpdating
            if !shown { update(view) }
            return
        }
        session.setNativeSelection(paper)
        if !session.editStructureNatively(range: paper, replacement: replacement),
           replacement.isEmpty || !session.pastePlainTextNatively(range: paper, text: replacement) {
            // The paper did not take it: the cell shows the paper's text again.
            table.grid.refresh(index)
            return
        }
        updating = wasUpdating
        update(view)
    }

    var cellSelectionActions: [(name: String, perform: () -> Bool)] {
        guard let view, owns(view) else { return [] }
        return view.selectionActions.map { action in
            (action.name, { [weak self] in
                guard let self, let selection = self.session.nativeSelection else { return false }
                return action.perform(selection)
            })
        }
    }

    func tableCellDidSelect(_ table: RelayTableAttachment, at index: Int, range: NSRange) {
        guard !updating, let view, owns(view), table.cells.indices.contains(index) else { return }
        let cell = table.paperRange(of: index)
        session.setNativeSelection(NSRange(location: cell.location + range.location, length: range.length))
    }
}

/// Feedback for an edit the paper cannot take; an edit is never dropped silently.
@MainActor enum RelayPaperRefusal {
    static var feedback: () -> Void = {
        #if os(macOS)
        NSSound.beep()
        #endif
    }
}
