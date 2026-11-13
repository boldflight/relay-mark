import Foundation
import RelayMarkEditorCore
import RelayMarkProseProjection

/// Native table views own input and layout. This boundary translates their text
/// ranges into the paper's existing commands, composition and collaboration history.
@MainActor
protocol RelayTableEditing: AnyObject {
    var isEditable: Bool { get }
    var isComposing: Bool { get }
    func shouldChange(range: NSRange, replacement: String) -> Bool
    func didChange()
    func selectionDidChange()
    func beginComposition()
    func declareMarkedInput(_ literal: String?, replacement: NSRange, selection: NSRange,
        platform: RelayDeclaredMarkedInput.Platform, suppliedReplacement: NSRange?,
        phase: RelayDeclaredMarkedInput.Phase) -> Bool
    func endComposition()
    func finishComposition() throws
    func cancelComposition()
    func undo()
    func redo()
    func toggleMark(_ mark: RelayMarkFormattingMark) -> Bool
    func performCommand(_ id: String) -> Bool
}

@MainActor
final class RelayTableEditor<Session: RelayPaperTextEditing>: RelayTableEditing {
    private weak var table: RelayTableAttachment?
    private weak var paperView: (any RelayPaperTextView)?
    private let session: Session
    private let refresh: () -> Void
    private var pendingTyping: (native: NSRange, paper: NSRange, text: String)?
    private var finishingComposition = false
    private struct CompositionState {
        let token: Session.Composition
        let original: AttributedString
        let paperCell: NSRange
        let nativeCell: NSRange
        let nativeLength: Int
    }
    private var composition: CompositionState?

    init(table: RelayTableAttachment, paperView: any RelayPaperTextView,
         session: Session, refresh: @escaping () -> Void) {
        self.table = table
        self.paperView = paperView
        self.session = session
        self.refresh = refresh
    }

    private var ownsView: Bool {
        guard let table, let paperView else { return false }
        return !paperView.retired && paperView.editingSession === session && !session.isInvalidated &&
            paperView.paper.tables.spans.contains(where: { $0.table === table })
    }
    var isEditable: Bool { ownsView && session.isEditable }
    var isComposing: Bool { composition != nil }

    func shouldChange(range: NSRange, replacement: String) -> Bool {
        guard isEditable, let table else { return false }
        pendingTyping = nil
        if let composition { return paperRange(range, during: composition) != nil }
        guard let paper = table.grid.projection.editablePaperRange(forNative: range) else {
            RelayPaperRefusal.feedback()
            return false
        }
        if session.applyInputRuleNatively(range: paper, replacement: replacement) {
            refresh()
            return false
        }
        if session.canTypeNatively(range: paper, replacement: replacement) {
            pendingTyping = (range, paper, replacement)
            return true
        }
        // Paragraph structure belongs to the universal engine. TextKit displays
        // its resulting splice, retaining the table/cell identities.
        if session.editStructureNatively(range: paper, replacement: replacement) ||
            !replacement.isEmpty && session.pastePlainTextNatively(range: paper, text: replacement) {
            refresh()
            return false
        }
        RelayPaperRefusal.feedback()
        return false
    }

    func didChange() {
        guard ownsView, let table, !table.grid.hasMarkedInput else { return }
        if composition != nil {
            endComposition()
            return
        }
        guard let pending = pendingTyping else {
            // UITextInput can insert without asking its delegate first. Adopt
            // the exact NSTextStorage character edit through the same engine
            // commands; never infer a replacement from the whole rendered table.
            let edit = table.grid.nativeEdit
            table.grid.clearNativeEdit()
            if isEditable, let edit {
                let applied = session.applyInputRuleNatively(range: edit.paper, replacement: edit.text) ||
                    (session.canTypeNatively(range: edit.paper, replacement: edit.text) &&
                     session.typeNatively(range: edit.paper, replacement: edit.text)) ||
                    session.editStructureNatively(range: edit.paper, replacement: edit.text) ||
                    (!edit.text.isEmpty && session.pastePlainTextNatively(range: edit.paper, text: edit.text))
                if applied { refresh(); return }
                RelayPaperRefusal.feedback()
            }
            table.grid.refresh()
            return
        }
        pendingTyping = nil
        table.grid.clearNativeEdit()
        let inserted = NSRange(location: pending.native.location, length: pending.text.utf16.count)
        let native = table.grid.nativeText
        guard isEditable, NSMaxRange(inserted) <= native.length,
              (native.string as NSString).substring(with: inserted) == pending.text,
              session.typeNatively(range: pending.paper, replacement: pending.text) else {
            table.grid.refresh()
            RelayPaperRefusal.feedback()
            return
        }
        refresh()
    }

    func selectionDidChange() {
        guard ownsView, pendingTyping == nil, composition == nil, let table,
              !table.grid.hasMarkedInput, table.grid.nativeEditCount == 0,
              let paper = table.grid.projection.paperRange(forNative: table.grid.nativeSelection) else { return }
        session.setNativeSelection(paper)
    }

    func beginComposition() {
        guard isEditable, composition == nil, let table,
              let selection = table.grid.projection.editablePaperRange(forNative: table.grid.nativeSelection),
              let cell = table.cell(containing: selection.location),
              let native = table.grid.projection.nativeRange(forPaper: table.paperRange(of: cell)) else { return }
        session.setNativeSelection(selection)
        guard let token = try? session.beginComposition() else { return }
        pendingTyping = nil
        composition = CompositionState(token: token, original: session.text,
            paperCell: table.paperRange(of: cell), nativeCell: native, nativeLength: table.grid.nativeText.length)
    }

    /// Only the composing cell changes locally while the shared session defers
    /// peer updates. Native lengths translate its exact OS-produced fragments;
    /// no diff or replacement text is inferred from rendered geometry.
    private func paperRange(_ native: NSRange, during state: CompositionState) -> NSRange? {
        guard let table, native.location != NSNotFound, native.length >= 0 else { return nil }
        let delta = table.grid.nativeText.length - state.nativeLength
        let length = state.nativeCell.length + delta
        guard length >= 0, native.location >= state.nativeCell.location,
              native.location <= state.nativeCell.location + length,
              native.length <= state.nativeCell.location + length - native.location else { return nil }
        return NSRange(location: state.paperCell.location + native.location - state.nativeCell.location,
                       length: native.length)
    }

    func declareMarkedInput(_ literal: String?, replacement: NSRange, selection: NSRange,
        platform: RelayDeclaredMarkedInput.Platform, suppliedReplacement: NSRange?,
        phase: RelayDeclaredMarkedInput.Phase) -> Bool {
        guard isEditable, let state = composition,
              let paper = paperRange(replacement, during: state) else { return false }
        let supplied: NSRange?
        if let suppliedReplacement, suppliedReplacement.location != NSNotFound {
            guard let mapped = paperRange(suppliedReplacement, during: state) else { return false }
            supplied = mapped
        } else { supplied = suppliedReplacement }
        return session.declareMarkedInput(literal, replacement: paper, selection: selection,
            platform: platform, suppliedReplacement: supplied, phase: phase, from: state.token)
    }

    func endComposition() {
        guard !finishingComposition, let table, !table.grid.hasMarkedInput else { return }
        do { try commitComposition() }
        catch { RelayPaperRefusal.feedback() }
    }

    func finishComposition() throws {
        guard composition != nil, !finishingComposition else { return }
        finishingComposition = true
        defer { finishingComposition = false }
        table?.grid.unmarkText()
        try commitComposition()
    }

    private func commitComposition() throws {
        guard let state = composition, let table else { return }
        composition = nil
        defer { session.cancelComposition(state.token); refresh() }
        guard isEditable else { throw CancellationError() }
        let native = table.grid.nativeText
        let delta = native.length - state.nativeLength
        let cell = NSRange(location: state.nativeCell.location, length: state.nativeCell.length + delta)
        guard cell.length >= 0, NSMaxRange(cell) <= native.length else { throw CancellationError() }
        if session.commitCompositionNatively(from: state.token,
            renderedLength: state.original.utf16.count + delta, rendered: { paper in
                guard paper.location >= state.paperCell.location,
                      NSMaxRange(paper) <= state.paperCell.location + cell.length else { return nil }
                let range = NSRange(location: cell.location + paper.location - state.paperCell.location, length: paper.length)
                return (native.string as NSString).substring(with: range)
            }) != nil { return }
        // Existing guarded composition handling covers a composition crossing
        // paragraphs. Preserve the canonical paper outside this single cell.
        var candidate = state.original
        guard let range = Range(state.paperCell, in: candidate) else { throw CancellationError() }
        candidate.replaceSubrange(range, with: NativeProseCodec.value(native.attributedSubstring(from: cell)))
        try session.commitComposition(candidate, from: state.token)
    }

    func cancelComposition() {
        let state = composition
        composition = nil
        pendingTyping = nil
        guard let state else { return }
        session.cancelComposition(state.token)
        table?.grid.unmarkText()
    }

    func undo() {
        guard ownsView else { return }
        do { try finishComposition() } catch { return }
        session.undo()
        refresh()
    }
    func redo() {
        guard ownsView else { return }
        do { try finishComposition() } catch { return }
        session.redo()
        refresh()
    }
    func toggleMark(_ mark: RelayMarkFormattingMark) -> Bool {
        guard isEditable, composition == nil, let table,
              let range = table.grid.projection.editablePaperRange(forNative: table.grid.nativeSelection) else { return false }
        let applied = session.toggleMarkNatively(mark, range: range)
        if applied { refresh() }
        return applied
    }
    func performCommand(_ id: String) -> Bool {
        guard isEditable, composition == nil, let table,
              let range = table.grid.projection.editablePaperRange(forNative: table.grid.nativeSelection),
              let command = RelayMarkEditorCommand.command(id: id) else { return false }
        session.setNativeSelection(range)
        guard session.canPerform(command) else { return false }
        session.perform(command)
        refresh()
        return true
    }
}
