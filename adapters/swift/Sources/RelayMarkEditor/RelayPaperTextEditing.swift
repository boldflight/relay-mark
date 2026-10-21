import Foundation
import RelayMarkCollaboration
import RelayMarkProseProjection
import SwiftUI

/// Presentation for a real zero-length paragraph; never part of the CRDT text.
struct RelayEmptyProseBlock {
    var offset: Int
    let intent: PresentationIntent
    var inlineIntent: InlinePresentationIntent = []
    var link: URL? = nil
    var typingStyle: AttributedString? = nil
}

/// Text spans a change re-projected in place. A view still showing the text of
/// revision `from` replaces each `old` range, in order, with `new` of `text`.
/// Leaf splices keep their block's presentation; a node splice carries the
/// replaced top-level nodes' presentation metadata.
struct RelayTextSplice {
    let from: Int
    let to: Int
    let ranges: [(old: NSRange, new: NSRange)]
    var nodes: RelayNativeRegion? = nil
}

/// Presentation metadata of some top-level nodes, in paper offsets.
struct RelayNativeRegion {
    /// The replaced nodes' span before the change: metadata before it stays,
    /// inside it is replaced by this region's, and after it moves.
    var content = NSRange(location: 0, length: 0)
    var emptyBlocks: [RelayEmptyProseBlock] = []
    var tableCells: [RelayMarkCollaborativeProse.TableCell] = []
    var callouts: [RelayMarkCollaborativeProse.Callout] = []
    var taskItems: [RelayMarkCollaborativeProse.TaskItem] = []
    var inlineAtoms: [RelayMarkCollaborativeProse.InlineAtom] = []
    var blockAtoms: [RelayMarkCollaborativeProse.BlockAtom] = []
    var authoredWidgets: [RelayMarkCollaborativeProse.AuthoredWidget] = []
    var entityReferenceAtoms: [RelayMarkCollaborativeProse.EntityReferenceAtom] = []
    var mediaAtoms: [RelayMarkCollaborativeProse.MediaAtom] = []
    var suggestionAtoms: [RelayMarkCollaborativeProse.SuggestionAtom] = []
}

/// Only the native text view's editing contract. Transport and storage remain
/// owned by the session implementation.
@MainActor
protocol RelayPaperTextEditing: AnyObject {
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
    var nativeTaskItems: [RelayMarkCollaborativeProse.TaskItem] { get }
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
    func commitComposition(_ proposed: AttributedString, from composition: Composition) throws
    /// Commits declared marked input in place when it stays inside one text leaf.
    func commitCompositionNatively(from composition: Composition, renderedLength: Int,
                                   rendered: (NSRange) -> String?) -> (range: NSRange, text: String)?
    func cancelComposition(_ composition: Composition)
    func registerNativeCompositionFinalizer(_ finish: @escaping () throws -> Void, refresh: @escaping () -> Void) -> UUID
    func unregisterNativeCompositionFinalizer(_ registration: UUID)
}

extension RelayPaperTextEditing {
    var nativeEmptyBlocks: [RelayEmptyProseBlock] { [] }
    var nativeTableCells: [RelayMarkCollaborativeProse.TableCell] { [] }
    var nativeCallouts: [RelayMarkCollaborativeProse.Callout] { [] }
    var nativeTaskItems: [RelayMarkCollaborativeProse.TaskItem] { [] }
    var nativeInlineAtoms: [RelayMarkCollaborativeProse.InlineAtom] { [] }
    var nativeBlockAtoms: [RelayMarkCollaborativeProse.BlockAtom] { [] }
    var nativeAuthoredWidgets: [RelayMarkCollaborativeProse.AuthoredWidget] { [] }
    var nativeEntityReferenceAtoms: [RelayMarkCollaborativeProse.EntityReferenceAtom] { [] }
    var nativeMediaAtoms: [RelayMarkCollaborativeProse.MediaAtom] { [] }
    var nativeSuggestionAtoms: [RelayMarkCollaborativeProse.SuggestionAtom] { [] }
    var textSplice: RelayTextSplice? { nil }
    var sections: [RelayPaperSection] { [] }
    var foldedSections: Set<String> { [] }
    var hiddenSectionRanges: [NSRange] { [] }
    @discardableResult func toggleSection(_ id: String) -> Bool { false }
    func editStructureNatively(range: NSRange, replacement: String) -> Bool { false }
    func pastePlainTextNatively(range: NSRange, text: String) -> Bool { false }
    func pasteNatively(range: NSRange, piece: AttributedString) -> Bool { false }
    func formatNatively(range: NSRange, mark: RelayMarkFormattingMark, enabled: Bool) -> Bool { false }
    func toggleMarkNatively(_ mark: RelayMarkFormattingMark, range: NSRange) -> Bool { false }
    func commitCompositionNatively(from composition: Composition, renderedLength: Int,
                                   rendered: (NSRange) -> String?) -> (range: NSRange, text: String)? { nil }
    func acceptsNativeReplacement(baseline: String, range: NSRange, replacement: String) -> Bool { true }
    func handleNativeListIndent(backward: Bool) -> Bool { false }
    func deleteTableNatively(at paperLocation: Int) -> Bool { false }
    func handleNativeEdgeDeletion(backward: Bool) -> Bool { false }
    func edit(_ candidate: AttributedString, nativeReplacement: RelayNativeTextReplacement?) {
        edit(candidate, nativeReplacement: nativeReplacement, nativePaste: nil)
    }
}
