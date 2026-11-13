import Foundation
import RelayMarkCollaboration
import RelayMarkProseProjection

/// Presentation for a real zero-length paragraph; never part of the CRDT text.
package struct RelayEmptyProseBlock {
    package var offset: Int
    package let intent: PresentationIntent
    package var inlineIntent: InlinePresentationIntent = []
    package var link: URL? = nil
    package var typingStyle: AttributedString? = nil
}

/// Text spans a change re-projected in place. A view still showing the text of
/// revision `from` replaces each `old` range, in order, with `new` of `text`.
/// Leaf splices keep their block's presentation; a node splice carries the
/// replaced top-level nodes' presentation metadata.
package struct RelayTextSplice {
    package let from: Int
    package let to: Int
    package let ranges: [(old: NSRange, new: NSRange)]
    package var nodes: RelayNativeRegion? = nil
}

/// Presentation metadata of some top-level nodes, in paper offsets.
package struct RelayNativeRegion {
    /// The replaced nodes' span before the change: metadata before it stays,
    /// inside it is replaced by this region's, and after it moves.
    package var content = NSRange(location: 0, length: 0)
    package var emptyBlocks: [RelayEmptyProseBlock] = []
    package var tableCells: [RelayMarkCollaborativeProse.TableCell] = []
    package var callouts: [RelayMarkCollaborativeProse.Callout] = []
    package var questions: [RelayMarkCollaborativeProse.Question] = []
    package var taskItems: [RelayMarkCollaborativeProse.TaskItem] = []
    package var inlineAtoms: [RelayMarkCollaborativeProse.InlineAtom] = []
    package var blockAtoms: [RelayMarkCollaborativeProse.BlockAtom] = []
    package var authoredWidgets: [RelayMarkCollaborativeProse.AuthoredWidget] = []
    package var entityReferenceAtoms: [RelayMarkCollaborativeProse.EntityReferenceAtom] = []
    package var mediaAtoms: [RelayMarkCollaborativeProse.MediaAtom] = []
    package var suggestionAtoms: [RelayMarkCollaborativeProse.SuggestionAtom] = []
}

/// Only the native text view's editing contract. Transport and storage remain
/// owned by the session implementation.
@MainActor
package protocol RelayPaperTextEditing: AnyObject {
    associatedtype Composition
    var text: AttributedString { get }
    var isEditable: Bool { get }
    var isSupported: Bool { get }
    var isInvalidated: Bool { get }
    var remoteSelections: [RelayMarkRemoteSelection] { get }
    var nativeSelection: NSRange? { get }
    var nativeEmptyBlocks: [RelayEmptyProseBlock] { get }
    var nativeTableCells: [RelayMarkCollaborativeProse.TableCell] { get }
    var nativeCallouts: [RelayMarkCollaborativeProse.Callout] { get }
    var nativeQuestions: [RelayMarkCollaborativeProse.Question] { get }
    var nativeTaskItems: [RelayMarkCollaborativeProse.TaskItem] { get }
    /// Advances when task checkboxes change without the text changing.
    var taskStateRevision: Int { get }
    /// Advances when linked Tasks' statuses may have changed; chips redraw.
    var linkedTaskRevision: Int { get }
    /// The status a linked item's Task chip shows, when the host has one.
    func linkedTaskStatus(entityID: String, checked: Bool) -> RelayMarkTaskGlyph?
    /// The unlinked task items a person started as draft Tasks (M10).
    var armedTaskDrafts: [String] { get }
    var nativeInlineAtoms: [RelayMarkCollaborativeProse.InlineAtom] { get }
    var nativeBlockAtoms: [RelayMarkCollaborativeProse.BlockAtom] { get }
    var nativeAuthoredWidgets: [RelayMarkCollaborativeProse.AuthoredWidget] { get }
    var nativeEntityReferenceAtoms: [RelayMarkCollaborativeProse.EntityReferenceAtom] { get }
    var nativeMediaAtoms: [RelayMarkCollaborativeProse.MediaAtom] { get }
    var nativeSuggestionAtoms: [RelayMarkCollaborativeProse.SuggestionAtom] { get }
    func setNativeSelection(_ range: NSRange)
    /// The paper's sections, those folded, and the paper ranges folding hides.
    var sections: [RelayPaperSection] { get }
    var foldedSections: Set<String> { get }
    var hiddenSectionRanges: [NSRange] { get }
    @discardableResult func toggleSection(_ id: String) -> Bool
    /// Advances whenever `text` is replaced.
    var textRevision: Int { get }
    /// Whether a keystroke stays inside one text leaf, so `typeNatively` can apply it.
    func canTypeNatively(range: NSRange, replacement: String) -> Bool
    /// Applies such a keystroke at a cost independent of the paper's length.
    func typeNatively(range: NSRange, replacement: String) -> Bool
    /// How the last replacement of `text` can be applied without a full render.
    var textSplice: RelayTextSplice? { get }
    /// Return, or removing one block separator, applied at the cost of the blocks it touches.
    func editStructureNatively(range: NSRange, replacement: String) -> Bool
    /// A keystroke completing a typed Markdown shortcut, applied as one command.
    func applyInputRuleNatively(range: NSRange, replacement: String) -> Bool
    /// Plain text pasted over a selection, at the cost of the blocks it touches.
    func pastePlainTextNatively(range: NSRange, text: String) -> Bool
    /// Rich text pasted over a selection, with its marks, at the cost of the blocks it touches.
    func pasteNatively(range: NSRange, piece: AttributedString) -> Bool
    /// Adds or removes one inline mark over a selection at the cost of the blocks it touches.
    func formatNatively(range: NSRange, mark: RelayMarkFormattingMark, enabled: Bool) -> Bool
    /// Toggles one inline mark over a selection the same way.
    func toggleMarkNatively(_ mark: RelayMarkFormattingMark, range: NSRange) -> Bool
    func handleNativeListIndent(backward: Bool) -> Bool
    /// Whether a paper command applies to the selection, and running it.
    func canPerform(_ command: RelayMarkEditorCommand) -> Bool
    func perform(_ command: RelayMarkEditorCommand)
    /// Deletes the whole table whose text starts at `paperLocation`, as one command.
    func deleteTableNatively(at paperLocation: Int) -> Bool
    /// Backspace at the start or Delete at the end, where the text view has
    /// nothing to remove but the document structure may still change.
    func handleNativeEdgeDeletion(backward: Bool) -> Bool
    func edit(_ candidate: AttributedString, nativeReplacement: RelayNativeTextReplacement?, nativePaste: RelayNativePasteCommand?)
    func editFormatting(_ candidate: AttributedString, command: RelayNativeFormattingCommand)
    func acceptsNativePastePayload(_ value: String) -> Bool
    func acceptsNativeReplacement(baseline: String, range: NSRange, replacement: String) -> Bool
    func preserveRejectedPaste(_ candidate: AttributedString, id: UUID)
    func undo()
    func redo()
    func beginComposition() throws -> Composition
    func declareMarkedInput(_ literal: String?, replacement: NSRange, selection: NSRange,
        platform: RelayDeclaredMarkedInput.Platform, suppliedReplacement: NSRange?,
        phase: RelayDeclaredMarkedInput.Phase, from composition: Composition) -> Bool
    func commitComposition(_ proposed: AttributedString, from composition: Composition) throws
    /// Commits declared marked input in place when it stays inside one text leaf.
    func commitCompositionNatively(from composition: Composition, renderedLength: Int,
                                   rendered: (NSRange) -> String?) -> (range: NSRange, text: String)?
    func cancelComposition(_ composition: Composition)
    func registerNativeCompositionFinalizer(_ finish: @escaping () throws -> Void, refresh: @escaping () -> Void) -> UUID
    func unregisterNativeCompositionFinalizer(_ registration: UUID)
}

extension RelayPaperTextEditing {
    package var nativeEmptyBlocks: [RelayEmptyProseBlock] { [] }
    package var nativeTableCells: [RelayMarkCollaborativeProse.TableCell] { [] }
    package var nativeCallouts: [RelayMarkCollaborativeProse.Callout] { [] }
    package var nativeQuestions: [RelayMarkCollaborativeProse.Question] { [] }
    package var nativeTaskItems: [RelayMarkCollaborativeProse.TaskItem] { [] }
    package var taskStateRevision: Int { 0 }
    package var linkedTaskRevision: Int { 0 }
    package func linkedTaskStatus(entityID: String, checked: Bool) -> RelayMarkTaskGlyph? { nil }
    package var nativeInlineAtoms: [RelayMarkCollaborativeProse.InlineAtom] { [] }
    package var nativeBlockAtoms: [RelayMarkCollaborativeProse.BlockAtom] { [] }
    package var nativeAuthoredWidgets: [RelayMarkCollaborativeProse.AuthoredWidget] { [] }
    package var nativeEntityReferenceAtoms: [RelayMarkCollaborativeProse.EntityReferenceAtom] { [] }
    package var nativeMediaAtoms: [RelayMarkCollaborativeProse.MediaAtom] { [] }
    package var nativeSuggestionAtoms: [RelayMarkCollaborativeProse.SuggestionAtom] { [] }
    package var textSplice: RelayTextSplice? { nil }
    package var sections: [RelayPaperSection] { [] }
    package var foldedSections: Set<String> { [] }
    package var hiddenSectionRanges: [NSRange] { [] }
    @discardableResult package func toggleSection(_ id: String) -> Bool { false }
    package func editStructureNatively(range: NSRange, replacement: String) -> Bool { false }
    package func applyInputRuleNatively(range: NSRange, replacement: String) -> Bool { false }
    package func pastePlainTextNatively(range: NSRange, text: String) -> Bool { false }
    package func pasteNatively(range: NSRange, piece: AttributedString) -> Bool { false }
    package func formatNatively(range: NSRange, mark: RelayMarkFormattingMark, enabled: Bool) -> Bool { false }
    package func toggleMarkNatively(_ mark: RelayMarkFormattingMark, range: NSRange) -> Bool { false }
    package func commitCompositionNatively(from composition: Composition, renderedLength: Int,
                                   rendered: (NSRange) -> String?) -> (range: NSRange, text: String)? { nil }
    package func declareMarkedInput(_ literal: String?, replacement: NSRange, selection: NSRange,
        platform: RelayDeclaredMarkedInput.Platform, suppliedReplacement: NSRange?,
        phase: RelayDeclaredMarkedInput.Phase, from composition: Composition) -> Bool { false }
    package func acceptsNativeReplacement(baseline: String, range: NSRange, replacement: String) -> Bool { true }
    package func handleNativeListIndent(backward: Bool) -> Bool { false }
    package func deleteTableNatively(at paperLocation: Int) -> Bool { false }
    package func handleNativeEdgeDeletion(backward: Bool) -> Bool { false }
    package func edit(_ candidate: AttributedString, nativeReplacement: RelayNativeTextReplacement?) {
        edit(candidate, nativeReplacement: nativeReplacement, nativePaste: nil)
    }
}
