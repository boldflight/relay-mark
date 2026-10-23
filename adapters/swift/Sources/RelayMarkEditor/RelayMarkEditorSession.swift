import Foundation
import OSLog
import Observation
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkProseProjection
import RelayMarkSwift
import SwiftUI

/// An ordinary authored-prose editor over one native Yrs replica. The host
/// persists each exact update through its existing account-bound journal.
@MainActor @Observable
public final class RelayMarkEditorSession {
    public internal(set) var text: AttributedString { didSet { textRevision &+= 1; scheduleWordCount() } }
    /// Counted after typing pauses, so a footer never reads the whole paper per keystroke.
    public internal(set) var wordCount = 0
    @ObservationIgnored var wordCountTask: Task<Void, Never>?
    /// Advances when a command changes task checkboxes without changing `text`, so a view
    /// observing the session shows the new state.
    public internal(set) var taskStateRevision = 0
    /// Advances whenever `text` is replaced; a text view compares it instead of the text.
    @ObservationIgnored public private(set) var textRevision = 0
    /// Set when a peer's text-only update re-projected just its leaves.
    @ObservationIgnored var textSplice: RelayTextSplice?
    /// Edits that reached a whole-paper path because no fast path took them.
    /// Kept on this device only, so real editing shows whether it happens.
    @ObservationIgnored private(set) var fallbackEdits = 0

    func noteFallback(_ path: StaticString) {
        fallbackEdits += 1
        Logger(subsystem: "RelayMarkEditor", category: "Editing")
            .debug("Whole-paper edit path \(path, privacy: .public) (\(self.fallbackEdits, privacy: .public) this session)")
    }
    public private(set) var isSupported: Bool
    public internal(set) var failure: String?
    var storedTyping: (anchor: Data, attributes: Data)?
    /// The native selection in UTF-16 offsets of `text`.
    @ObservationIgnored private var selectedRange: NSRange?
    /// The document projection, kept for the document revision it describes.
    @ObservationIgnored var projectionCache: (revision: Int, value: RelayMarkCollaborativeProse)?
    /// Sections of the text revision they were read from.
    @ObservationIgnored var sectionCache: (revision: Int, sections: [RelayPaperSection])?
    /// A host's request to move keyboard focus into the paper, until a view takes it.
    @ObservationIgnored var focusRequest: RelayPaperFocus?
    @ObservationIgnored var onFocusRequest: (() -> Void)?
    /// Folded sections by destination name: this session's view state, never saved or synced.
    public internal(set) var foldedSections: Set<String> = []
    public var onSelectionChange: (() -> Void)?
    public private(set) var remoteSelections: [RelayMarkRemoteSelection] = []
    public var isTaskList: Bool { false }
    var nativeTableCells: [RelayMarkCollaborativeProse.TableCell] {
        return (try? currentProjection().tableCells) ?? []
    }
    var nativeCallouts: [RelayMarkCollaborativeProse.Callout] {
        return (try? currentProjection().callouts) ?? []
    }
    public var nativeTaskItems: [RelayMarkCollaborativeProse.TaskItem] {
        guard let projection = try? currentProjection() else { return [] }
        return projection.taskItems
    }
    public var nativeInlineAtoms: [RelayMarkCollaborativeProse.InlineAtom] {
        return (try? currentProjection().inlineAtoms) ?? []
    }
    public var nativeBlockAtoms: [RelayMarkCollaborativeProse.BlockAtom] {
        return (try? currentProjection().blockAtoms) ?? []
    }
    public var nativeEntityReferenceAtoms: [RelayMarkCollaborativeProse.EntityReferenceAtom] {
        return (try? currentProjection().entityReferenceAtoms) ?? []
    }
    /// A reference opens the existing authorized host preview, including on a
    /// read-only paper. Its document node never grants access to the target.
    public var selectedEntityReferenceID: String? {
        guard isSupported, !invalidated, let selection = nativeSelection else { return nil }
        func contains(_ range: NSRange) -> Bool {
            selection.location >= range.location && selection.location < NSMaxRange(range) &&
                NSMaxRange(selection) <= NSMaxRange(range)
        }
        if let atom = nativeEntityReferenceAtoms.first(where: { contains($0.range) }) { return atom.entityID }
        // Only the selected runs are read, so the cost follows the selection, not the paper.
        let probe = selection.length == 0
            ? NSRange(location: selection.location, length: selection.location < text.utf16.count ? 1 : 0) : selection
        guard probe.length > 0, let range = Range(probe, in: text) else { return nil }
        var selectedIDs = Set<String>()
        for run in text[range].runs {
            guard let link = run.link, link.scheme == "relay", link.path.hasPrefix("entity/"),
                  let id = UUID(uuidString: String(link.path.dropFirst("entity/".count))) else { return nil }
            selectedIDs.insert(id.uuidString.lowercased())
        }
        return selectedIDs.count == 1 ? selectedIDs.first : nil
    }

    private var declaredMarkedInput: RelayDeclaredMarkedInput?

    /// OS producer admission, before native view mutation. No candidate/baseline extraction.
    func declareMarkedInput(_ literal: String?, replacement: NSRange, selection: NSRange,
        platform: RelayDeclaredMarkedInput.Platform, suppliedReplacement: NSRange?, phase: RelayDeclaredMarkedInput.Phase, from token: Composition) -> Bool {
        guard !invalidated, canEdit(), activeComposition?.id == token.id, token.owner == compositionOwner else { return false }
        do {
            let prior = declaredMarkedInput?.tokenID == token.id ? declaredMarkedInput : nil
            guard prior?.revision != Int.max, prior == nil || prior?.platform == platform else { throw AuthoredBlockEditFailure.changed }
            declaredMarkedInput = try .init(tokenID: token.id, ownerID: token.owner,
                revision: (prior?.revision ?? 0) + 1, platform: platform, literal: literal,
                initialReplacement: prior?.initialReplacement ?? replacement, replacement: replacement, selection: selection, suppliedReplacement: suppliedReplacement,
                phase: phase, previousMarkedLiteral: phase == .final ? (prior?.phase == .marked ? prior?.literal : prior?.previousMarkedLiteral) : nil)
            return true
        } catch { failure = error.localizedDescription; return false }
    }

    public var hasUnpersistedTransaction: Bool { pending != nil }
    /// A failure message does not block typing; an unsaved update does.
    public var isEditable: Bool {
        isSupported && !invalidated && pending == nil && canEdit()
    }
    public var isInvalidated: Bool { invalidated }

    /// Marked input stays outside the CRDT until the OS commits it. Peer updates
    /// that arrive meanwhile wait and merge after the commit.
    struct Composition {
        fileprivate let owner: UUID
        let id: UUID
        fileprivate let original: AttributedString
    }

    @ObservationIgnored public let document: RelayMarkNativeDocument
    @ObservationIgnored let canEdit: () -> Bool
    @ObservationIgnored private let persist: (RelayMarkLocalTransaction) throws -> Void
    @ObservationIgnored var previousOwnedTextPath: [Int]?
    @ObservationIgnored var preparedLocalOperationID: UUID?
    @ObservationIgnored var pending: RelayMarkLocalTransaction?
    @ObservationIgnored let compositionOwner = UUID()
    @ObservationIgnored var activeComposition: Composition?
    @ObservationIgnored private var deferredRemoteUpdates: [Data] = []
    /// A host command whose save goes through its own commit instead of `persist`.
    @ObservationIgnored var pendingCommit: (operationID: UUID, commit: @MainActor (RelayMarkLocalTransaction) throws -> Void)?
    @ObservationIgnored private var nativeCompositionFinalizer: (id: UUID, finish: () throws -> Void, refresh: () -> Void)?
    @ObservationIgnored var invalidated = false

    public init(document: RelayMarkNativeDocument,
                canEdit: @escaping () -> Bool = { true },
                persist: @escaping (RelayMarkLocalTransaction) throws -> Void) throws {
        guard document.integrationStatus().isComplete else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let projection = try document.richProseProjection()
        guard projection.isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        self.document = document
        self.canEdit = canEdit
        self.persist = persist
        text = projection.text
        projectionCache = (document.revision, projection)
        wordCount = Self.words(in: String(projection.text.characters))
        isSupported = true // The shared projector validated a canonical identified document.
    }

    /// Runs a complete candidate through a scratch replica first. A proposal
    /// requiring unimplemented mark changes never partially edits the live CRDT.
    public func edit(_ candidate: AttributedString) {
        guard isEditable, pending == nil, activeComposition == nil else { return }
        editRich(candidate)
    }

    private func editRich(_ candidate: AttributedString) {
        if text == candidate { return }
        do {
            let result = try ownedChange({ try RelayNativeRichEdit.apply(document: document, candidate: candidate) }, update: { $0.update })
            text = result.text
            pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: result.update)
            retryPersistence()
        } catch {
            retain(candidate, reason: String(localized: "This edit contains unsupported structure or marks.", bundle: .module, comment: "Shown on the paper when an edit is kept for review."))
        }
    }

    func proseProjection(_ replica: RelayMarkNativeDocument) throws -> RelayMarkCollaborativeProse {
        replica === document ? try currentProjection() : try replica.richProseProjection()
    }

    func supportsCurrentSchema(_ replica: RelayMarkNativeDocument) -> Bool {
        (try? proseProjection(replica).isEditable) == true
    }

    /// Every change advances the document revision, so a cached projection is
    /// reused only while it still describes the replica.
    /// Runs `body` on the projection as it is now. The read ends when `body`
    /// returns, so a splice after it mutates the cached projection in place
    /// rather than copying the whole paper.
    func reading<Value>(_ body: (RelayMarkCollaborativeProse) throws -> Value) throws -> Value {
        try body(currentProjection())
    }

    func currentProjection() throws -> RelayMarkCollaborativeProse {
        if let projectionCache, projectionCache.revision == document.revision { return projectionCache.value }
        let value = try document.richProseProjection()
        projectionCache = (document.revision, value)
        return value
    }

    private static func supportsCanonical(_ document: RelayMarkNativeDocument) -> Bool {
        (try? document.richProseProjection().isEditable) == true
    }

    /// A task item bound to an entity, whose checkbox the host changes through
    /// that entity's own update; nil, or false from it, leaves it unchanged.
    @ObservationIgnored public var onLinkedTaskItem: ((RelayMarkCollaborativeProse.TaskItem) -> Bool)?
    /// The glyph of a linked item's Task, given the Task's entity and the item's
    /// checkbox, drawn in its task chip; nil when the host has none, and the chip
    /// shows the checkbox state.
    @ObservationIgnored public var linkedTaskStatus: ((_ entityID: String, _ checked: Bool) -> RelayMarkTaskGlyph?)? {
        didSet { linkedTasksChanged() }
    }
    /// Advances when linked Tasks' statuses may have changed; the view redraws its chips.
    public internal(set) var linkedTaskRevision = 0
    /// Each Task's status as the host last answered, until it reports a change.
    @ObservationIgnored var linkedTaskStatuses: [LinkedTaskKey: RelayMarkTaskGlyph?] = [:]
    struct LinkedTaskKey: Hashable { let entityID: String; let checked: Bool }
    /// Whether new checklist items start as draft Tasks. A host turns it on for
    /// a paper whose checklist items it can make into Tasks.
    @ObservationIgnored public var createsTaskDrafts = false
    /// The draft Tasks this person started on purpose, by block identity: this
    /// editor's own state, never stored in or sent with the document.
    @ObservationIgnored public internal(set) var armedTaskDrafts: [String] = []
    /// The armed item that held the caret, which leaving finishes.
    @ObservationIgnored var caretTaskDraft: String?
    /// Drafts a person finished by Return, leaving the item or ticking it. They
    /// are no longer armed: the host makes them into Tasks, or arms them again.
    @ObservationIgnored public var onTaskDraftsFinished: (([RelayTaskDraft]) -> Void)?
    /// While true, Undo and Redo wait, as for a host's command in flight.
    @ObservationIgnored public var pausesHistory = false

    /// The checkbox is an explicit command against a stable task-item anchor;
    /// a linked item goes to the host.
    @discardableResult public func toggleTaskItem(atUTF16 offset: Int) -> Bool {
        guard isEditable, pending == nil, activeComposition == nil,
              let item = nativeTaskItems.first(where: { $0.firstParagraphRange.location == offset }) else { return false }
        if item.entityID != nil {
            guard let onLinkedTaskItem else {
                failure = String(localized: "This task is linked to an item its host updates, and no host is handling it. The checkbox has not changed.", bundle: .module, comment: "Shown when a linked task's checkbox cannot change.")
                return false
            }
            return onLinkedTaskItem(item)
        }
        do {
            _ = try toggleTaskItems(item)
            finishTaskDraftOnCheckbox(item.id)
            return failure == nil
        } catch { failure = error.localizedDescription; return false }
    }

    /// Checks or unchecks `item` and the `items` reviewed with it as one
    /// command; `beforeMutation` runs once the change is known to apply.
    public func toggleTaskItems(_ item: RelayMarkCollaborativeProse.TaskItem,
        items reviewedItems: [RelayMarkCollaborativeProse.TaskItem]? = nil,
        beforeMutation: (UUID) throws -> Void = { _ in }) throws -> UUID {
        let checkpoint = try document.encodeUpdate(), snapshot = try document.snapshot()
        let items = reviewedItems ?? [item]
        let targets = items.map { RelayMarkNativeDocument.TaskItemCheckTarget(path: $0.path, expectedID: $0.id,
            expectedEntityID: $0.entityID, expectedChecked: $0.checked) }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(checkpoint)
        _ = try scratch.setRichTaskItemsChecked(items: targets, checked: !item.checked, expectedSnapshot: snapshot)
        let expected = try scratch.richProseProjection()
        // A projection spliced in place numbers its presentation identities
        // differently from a full one, so the toggle is checked to keep the characters.
        guard expected.isEditable, String(expected.text.characters) == String(text.characters) else {
            throw AuthoredBlockEditFailure.changed
        }
        let operation = UUID()
        try beforeMutation(operation)
        let change = try ownedChange({ try document.setRichTaskItemsChecked(items: targets, checked: !item.checked, expectedSnapshot: snapshot) },
            separateHistoryItem: true, operationID: operation, update: { $0.update })
        taskStateRevision &+= 1
        pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: change.update, inputIntent: .derived)
        retryPersistence()
        return operation
    }

    public func toggleSelectedTaskItem() {
        guard let offset = nativeSelection?.location else { return }
        if let item = nativeTaskItems.first(where: {
            offset >= $0.firstParagraphRange.location && offset <= NSMaxRange($0.firstParagraphRange)
        }) {
            _ = toggleTaskItem(atUTF16: item.firstParagraphRange.location)
        }
    }

    public struct TaskListInsertion {
        fileprivate let owner: UUID
        fileprivate let checkpoint: Data
        fileprivate let snapshot: Data
        fileprivate let range: NSRange
        fileprivate let anchor: Data
        fileprivate let paragraphPath: [Int]
    }

    enum TaskListInsertionFailure: LocalizedError {
        case changed
        public var errorDescription: String? {
            String(localized: "The paper or selection changed. Place the cursor at the end of a paragraph and try again.", bundle: .module, comment: "Shown when an insertion's target moved.")
        }
    }

    public func prepareTaskListInsertion() throws -> TaskListInsertion {
        guard isEditable, pending == nil,
              activeComposition == nil, let range = nativeSelection, range.length == 0 else {
            throw TaskListInsertionFailure.changed
        }
        let projection = try currentProjection()
        let candidates = projection.blockRanges.enumerated().filter { index, block in
            projection.blockPaths[index].count == 1 && range.location == NSMaxRange(block)
        }
        guard candidates.count == 1 else { throw TaskListInsertionFailure.changed }
        let path = projection.blockPaths[candidates[0].offset]
        let snapshot = try document.snapshot()
        guard let root = try JSONSerialization.jsonObject(with: snapshot) as? [String: Any],
              let children = root["children"] as? [[String: Any]], children.indices.contains(path[0]),
              children[path[0]]["name"] as? String == "paragraph" else {
            throw TaskListInsertionFailure.changed
        }
        return TaskListInsertion(owner: compositionOwner, checkpoint: try document.encodeUpdate(),
            snapshot: snapshot, range: range, anchor: try document.anchor(path: path, index: 0),
            paragraphPath: path)
    }

    func insertTaskList(using edit: TaskListInsertion) throws {
        guard isEditable, pending == nil,
              activeComposition == nil, edit.owner == compositionOwner,
              nativeSelection == edit.range, edit.checkpoint == (try document.encodeUpdate()),
              edit.snapshot == (try document.snapshot()) else { throw TaskListInsertionFailure.changed }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(edit.checkpoint)
        _ = try scratch.insertEmptyRichTaskList(after: edit.anchor, expectedSnapshot: edit.snapshot)
        let expected = try scratch.richProseProjection()
        let path = [edit.paragraphPath[0] + 1, 0, 0]
        guard expected.isEditable, let target = expected.blockPaths.firstIndex(of: path),
              expected.blockRanges[target].length == 0 else { throw TaskListInsertionFailure.changed }
        let revisionBefore = document.revision, textBefore = textRevision
        let change = try ownedChange({ try document.insertEmptyRichTaskList(after: edit.anchor,
            expectedSnapshot: edit.snapshot).change }, separateHistoryItem: true, update: { $0.update })
        try show(change.update, after: revisionBefore, textBefore: textBefore)
        setNativeSelection(NSRange(location: expected.blockRanges[target].location, length: 0))
        pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: change.update,
            inputIntent: .derived)
        retryPersistence()
    }

    public func insertTaskListAfterSelectedParagraph() {
        do { try insertTaskList(using: prepareTaskListInsertion()) }
        catch { failure = error.localizedDescription }
    }

    /// An undo or redo, saved as `operationID`, with the task items it
    /// rewrote as they were before and are after.
    public struct HistoryChange {
        public let operationID: UUID
        public let taskItemsBefore: [RelayMarkCollaborativeProse.TaskItem]
        public let taskItemsAfter: [RelayMarkCollaborativeProse.TaskItem]
    }
    @ObservationIgnored public var onHistory: ((HistoryChange) -> Void)?

    public func undo() { history(redo: false) }
    public func redo() { history(redo: true) }

    private func history(redo: Bool) {
        guard isEditable, pending == nil, activeComposition == nil, !pausesHistory else { return }
        do {
            guard let (operation, splice, paper) = try performHistory(redo: redo) else { return }
            // Only the items or nodes the undo rewrote can have changed a checkbox;
            // an undo of text alone changed none.
            let before: [RelayMarkCollaborativeProse.TaskItem], after: [RelayMarkCollaborativeProse.TaskItem]
            if let splice {
                guard let previous = splice.previous, let restricted = splice.restricted else { return }
                before = previous.taskItems; after = restricted.taskItems
            } else {
                guard let paper else { return }
                before = paper.taskItems; after = try currentProjection().taskItems
            }
            onHistory?(.init(operationID: operation, taskItemsBefore: before, taskItemsAfter: after))
        } catch { failure = error.localizedDescription }
    }

    /// Runs one editor command on the replica. Typing in the same text block
    /// joins the current undo item; a structural command is its own item.
    func ownedChange<Value>(_ command: () throws -> Value, separateHistoryItem: Bool = false,
        operationID suppliedOperationID: UUID? = nil, typingPath: [Int]? = nil,
        update: (Value) throws -> Data) throws -> Value {
        storedTyping = nil
        preparedLocalOperationID = nil
        // A separate history item needs no typing path to group with.
        let path = separateHistoryItem ? nil : typingPath ?? nativeSelection.flatMap { range -> [Int]? in
            guard let projection = try? currentProjection(),
                let position = projection.position(atUTF16: range.location) else { return nil }
            // An empty identified block gains its first text child when typing.
            // That initialization must not create an artificial history boundary.
            return projection.blockRange(path: position.path) != nil ? position.path + [0] : position.path
        }
        if !separateHistoryItem, previousOwnedTextPath != nil, path != previousOwnedTextPath { document.closeUndoItem() }
        let result = try document.editorCommand(separateUndoItem: separateHistoryItem, command)
        preparedLocalOperationID = suppliedOperationID ?? UUID()
        previousOwnedTextPath = separateHistoryItem ? nil : path
        return result
    }

    func preparedOperationID() throws -> UUID {
        guard let id = preparedLocalOperationID else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return id
    }

    public var nativeMediaAtoms: [RelayMarkCollaborativeProse.MediaAtom] {
        return (try? currentProjection().mediaAtoms) ?? []
    }

    public var nativeSuggestionAtoms: [RelayMarkCollaborativeProse.SuggestionAtom] {
        return (try? currentProjection().suggestionAtoms) ?? []
    }

    public var nativeAuthoredWidgets: [RelayMarkCollaborativeProse.AuthoredWidget] {
        (try? currentProjection().authoredWidgets) ?? []
    }

    /// Plain Yrs undo of this editor's own edits. The resulting update is saved like any edit.
    /// Returns its splice, or when it could not be located the paper as it was before it.
    private func performHistory(redo: Bool) throws -> (UUID, Splice?, RelayMarkCollaborativeProse?)? {
        storedTyping = nil
        let revisionBefore = document.revision, textBefore = textRevision
        guard let update = try redo ? document.redo() : document.undo() else { return nil }
        // The undo's own update locates what it changed, as a peer's does.
        let splice = spliceTouchedLeaves(after: revisionBefore) ?? spliceTouchedItems(after: revisionBefore)
            ?? spliceTouchedNodes(after: revisionBefore)
        let paper = splice == nil && projectionCache?.revision == revisionBefore ? projectionCache?.value : nil
        text = try proseProjection(document).text
        textSplice = splice.map { RelayTextSplice(from: textBefore, to: textRevision, ranges: $0.ranges, nodes: $0.nodes) }
        isSupported = supportsCurrentSchema(document)
        previousOwnedTextPath = nil
        let operation = UUID()
        pending = RelayMarkLocalTransaction(id: operation, update: update, inputIntent: redo ? .redo : .undo)
        retryPersistence()
        return (operation, splice, paper)
    }

    /// Appends the pending update to the host journal. A failed save keeps it
    /// pending and blocks further edits until Retry succeeds.
    public func retryPersistence() {
        guard !invalidated, let pending else { return }
        do {
            if let pendingCommit {
                guard pending.id == pendingCommit.operationID else { throw CancellationError() }
                try pendingCommit.commit(pending)
                self.pendingCommit = nil
            } else { try persist(pending) }
            self.pending = nil
            failure = nil
            applyDeferredRemoteUpdates()
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Integrates a peer's or sibling window's update. During marked input the
    /// update waits, so the composition commits against the text it started on.
    public func applyRemoteUpdate(_ update: Data) throws {
        guard !invalidated else { throw CancellationError() }
        guard pending == nil, activeComposition == nil else {
            deferredRemoteUpdates.append(update)
            return
        }
        // An editor waiting on missing predecessors has no projectable selection.
        let anchors = (try? selectionAnchors()) ?? []
        // A replica never refuses a peer's update. Until missing predecessors
        // arrive, or while the paper holds a structure this editor cannot
        // edit, it keeps showing its last text and stops accepting input.
        let revisionBefore = document.revision, textBefore = textRevision
        try document.applyUpdate(update)
        guard document.integrationStatus().isComplete else {
            // Updates that wait on a missing predecessor are located together once it arrives.
            awaitingPredecessor = (awaitingPredecessor?.revision ?? revisionBefore, (awaitingPredecessor?.updates ?? []) + [update])
            isSupported = false
            return
        }
        // A text-only update re-projects just its leaves, a structural one just
        // its top-level nodes; an update that cannot be located re-projects the paper.
        let splice: Splice?
        if let waiting = awaitingPredecessor {
            awaitingPredecessor = nil
            splice = spliceAwaited(waiting.updates + [update], after: waiting.revision)
        } else {
            splice = spliceTouchedLeaves(after: revisionBefore) ?? spliceTouchedItems(after: revisionBefore)
                ?? spliceTouchedNodes(after: revisionBefore)
        }
        guard let projected = try? proseProjection(document) else {
            isSupported = false
            return
        }
        text = projected.text
        textSplice = splice.map { RelayTextSplice(from: textBefore, to: textRevision, ranges: $0.ranges, nodes: $0.nodes) }
        isSupported = supportsCurrentSchema(document)
        if let first = anchors.first, let start = try document.resolve(anchor: first),
           let startOffset = try projectionOffset(path: start.path, index: start.index) {
            let endOffset: Int
            if anchors.count > 1, let end = try document.resolve(anchor: anchors[1]) {
                endOffset = try projectionOffset(path: end.path, index: end.index) ?? startOffset
            } else { endOffset = startOffset }
            setNativeSelection(NSRange(location: min(startOffset, endOffset), length: abs(endOffset - startOffset)))
        }
        try refreshPresence()
        nativeCompositionFinalizer?.refresh()
    }

    /// Updates applied while a predecessor was missing, and the revision before the first.
    @ObservationIgnored private var awaitingPredecessor: (revision: Int, updates: [Data])?

    /// Re-projects the nodes that updates integrated together touched, located
    /// from their merged update against the paper as it was before them.
    private func spliceAwaited(_ updates: [Data], after revisionBefore: Int) -> Splice? {
        guard let merged = try? document.mergeUpdates(updates) else { return nil }
        let rewrites: Rewritten? = {
            guard let paper = projectionCache?.value, projectionCache?.revision == revisionBefore else { return nil }
            return rewritten(update: merged, paper: paper)
        }()
        return rewrites.flatMap { splice($0, after: revisionBefore) }
    }

    /// A change re-projected in place: its text ranges, and for rewritten
    /// nodes or items their presentation and the restricted projection it came from.
    struct Splice {
        var ranges: [(old: NSRange, new: NSRange)]
        var nodes: RelayNativeRegion?
        var restricted: RelayMarkCollaborativeProse?
        /// What the rewritten items or nodes projected before the change.
        var previous: RelayMarkCollaborativeProse? = nil
    }

    /// What a change rewrote: some items of one top-level list, or top-level nodes.
    enum Rewritten {
        case items(node: Int, before: Range<Int>, after: Range<Int>)
        case nodes(before: Range<Int>, after: Range<Int>)
    }

    /// Located from the change's own update when it touched only one list's
    /// items, else from the command's window.
    func rewritten(_ change: RelayMarkNativeRichEditing.Change, paper: RelayMarkCollaborativeProse) -> Rewritten? {
        if let items = touchedItems(document.itemsTouched(by: change.update), paper: paper) { return items }
        if let items = change.items { return .items(node: items.node, before: items.before, after: items.after) }
        return touchedNodes(change, rootCountBefore: paper.topLevelCount).map { .nodes(before: $0.before, after: $0.after) }
    }

    /// The same for a host command, from its update alone.
    func rewritten(update: Data, paper: RelayMarkCollaborativeProse) -> Rewritten? {
        if let items = touchedItems(document.itemsTouched(by: update), paper: paper) { return items }
        return document.topLevelNodesTouched(by: update, rootCountBefore: paper.topLevelCount)
            .map { .nodes(before: $0.before, after: $0.after) }
    }

    /// Shows a local command's change: only the nodes its update touched are
    /// projected again, and the view replaces just those; a change that cannot
    /// be located re-projects the paper.
    @discardableResult
    func show(_ update: Data, after revisionBefore: Int, textBefore: Int) throws -> RelayMarkCollaborativeProse {
        let rewrites: Rewritten? = {
            guard let paper = projectionCache?.value, projectionCache?.revision == revisionBefore else { return nil }
            return rewritten(update: update, paper: paper)
        }()
        let splice = rewrites.flatMap { splice($0, after: revisionBefore) }
        let projection = try currentProjection()
        text = projection.text
        if let splice { textSplice = RelayTextSplice(from: textBefore, to: textRevision, ranges: splice.ranges, nodes: splice.nodes) }
        return projection
    }

    /// Items of a list `paper` projects by item, unless the list's own attributes changed.
    private func touchedItems(_ touched: (node: Int, after: Range<Int>, count: Int)?,
                              paper: RelayMarkCollaborativeProse) -> Rewritten? {
        guard let touched, let count = paper.itemCount(ofTopLevel: touched.node),
              paper.listAttributes(ofTopLevel: touched.node) == document.listAttributes(ofTopLevel: touched.node) else { return nil }
        let before = touched.after.lowerBound..<(count - (touched.count - touched.after.upperBound))
        guard before.lowerBound <= before.upperBound else { return nil }
        return .items(node: touched.node, before: before, after: touched.after)
    }

    func splice(_ rewritten: Rewritten, after revisionBefore: Int) -> Splice? {
        switch rewritten {
        case .nodes(let before, let after): return spliceNodes((before, after), after: revisionBefore)
        case .items(let node, let before, let after): return spliceItems(node: node, before: before, after: after, after: revisionBefore)
        }
    }

    private func spliceTouchedItems(after revisionBefore: Int) -> Splice? {
        guard let items = cachedTouchedItems(after: revisionBefore) else { return nil }
        return splice(items, after: revisionBefore)
    }

    /// Read in its own scope, so the splice after it owns the cached projection.
    private func cachedTouchedItems(after revisionBefore: Int) -> Rewritten? {
        guard let paper = projectionCache?.value, projectionCache?.revision == revisionBefore else { return nil }
        return touchedItems(document.itemsTouchedByLastUpdate(), paper: paper)
    }

    /// Re-projects just some items of a top-level list or rows of a table; when
    /// the node cannot take them on their own, as an ordered list renumbering
    /// or rows changing a table's columns, the whole node.
    private func spliceItems(node: Int, before: Range<Int>, after: Range<Int>, after revisionBefore: Int) -> Splice? {
        // The cached projection is read in its own scope, so either splice below owns it.
        let projected: RelayMarkCollaborativeProse?? = {
            guard let paper = projectionCache?.value, projectionCache?.revision == revisionBefore else { return nil }
            return .some(try? document.richProseProjection(items: after, ofTopLevel: node, paper: paper,
                                                           identityBase: paper.identityLimit))
        }()
        guard let projected else { return nil }
        return projected.flatMap { replaceCachedItems(before, of: node, with: $0, after: after, revisionBefore: revisionBefore) }
            ?? spliceNodes((node..<(node + 1), node..<(node + 1)), after: revisionBefore)
    }

    /// Nil, with the projection cached as it was, when the list cannot take the items.
    private func replaceCachedItems(_ before: Range<Int>, of node: Int, with items: RelayMarkCollaborativeProse,
                                    after: Range<Int>, revisionBefore: Int) -> Splice? {
        guard var next = projectionCache?.value, projectionCache?.revision == revisionBefore else { return nil }
        projectionCache = nil
        let previous = next.restricted(toItems: before, of: node)
        guard let replaced = next.replaceItems(before, ofTopLevel: node, with: items) else {
            projectionCache = (revisionBefore, next)
            return nil
        }
        projectionCache = (document.revision, next)
        let restricted = next.restricted(toItems: after, of: node)
        var region = region(of: restricted)
        region.content = replaced.content
        return Splice(ranges: [(replaced.old, replaced.new)], nodes: region, restricted: restricted, previous: previous)
    }

    private func spliceTouchedLeaves(after revisionBefore: Int) -> Splice? {
        guard var next = projectionCache?.value, projectionCache?.revision == revisionBefore,
              let leaves = document.textLeavesTouchedByLastUpdate() else { return nil }
        // The cache hands its projection over, so the splice mutates it without copying.
        projectionCache = nil
        var ranges: [(old: NSRange, new: NSRange)] = []
        for leaf in leaves {
            guard let runs = try? document.textRuns(path: leaf),
                  let old = next.replaceLeaf(path: leaf, runs: runs) else { return nil }
            ranges.append((old, NSRange(location: old.location, length: runs.reduce(0) { $0 + $1.text.utf16.count })))
        }
        projectionCache = (document.revision, next)
        return Splice(ranges: ranges, nodes: nil, restricted: nil)
    }

    private func spliceTouchedNodes(after revisionBefore: Int) -> Splice? {
        guard let touched = document.topLevelNodesTouchedByLastUpdate() else { return nil }
        return spliceNodes(touched, after: revisionBefore)
    }

    /// The nodes a local command rewrote: those its own update touched, so its
    /// window's untouched neighbours keep their presentation, else the window.
    private func touchedNodes(_ change: RelayMarkNativeRichEditing.Change,
                              rootCountBefore: Int) -> (before: Range<Int>, after: Range<Int>)? {
        document.topLevelNodesTouched(by: change.update, rootCountBefore: rootCountBefore) ?? change.topLevel
    }

    /// Re-projects just the top-level nodes a change rewrote into the cached projection.
    private func spliceNodes(_ touched: (before: Range<Int>, after: Range<Int>), after revisionBefore: Int) -> Splice? {
        guard var next = projectionCache?.value, projectionCache?.revision == revisionBefore,
              let nodes = try? document.richProseProjection(topLevel: touched.after, identityBase: next.identityLimit)
        else { return nil }
        projectionCache = nil
        let previous = next.restricted(toTopLevel: touched.before)
        guard let replaced = next.replaceTopLevelNodes(touched.before, with: nodes) else {
            // Unchanged, the projection stays cached as the paper before the change.
            projectionCache = (revisionBefore, next)
            return nil
        }
        projectionCache = (document.revision, next)
        let restricted = next.restricted(toTopLevel: touched.after)
        var region = region(of: restricted)
        region.content = replaced.content
        return Splice(ranges: [(replaced.old, replaced.new)], nodes: region, restricted: restricted, previous: previous)
    }

    /// Presentation metadata of a restricted projection, in paper offsets.
    func region(of projection: RelayMarkCollaborativeProse) -> RelayNativeRegion {
        RelayNativeRegion(emptyBlocks: emptyBlocks(of: projection), tableCells: projection.tableCells,
            callouts: projection.callouts, taskItems: projection.taskItems, inlineAtoms: projection.inlineAtoms,
            blockAtoms: projection.blockAtoms, authoredWidgets: projection.authoredWidgets,
            entityReferenceAtoms: projection.entityReferenceAtoms, mediaAtoms: projection.mediaAtoms,
            suggestionAtoms: projection.suggestionAtoms)
    }

    private func applyDeferredRemoteUpdates() {
        guard pending == nil, activeComposition == nil, !deferredRemoteUpdates.isEmpty else { return }
        let updates = deferredRemoteUpdates
        deferredRemoteUpdates = []
        do { try applyRemoteUpdate(document.mergeUpdates(updates)) }
        catch { failure = error.localizedDescription }
    }

    public func setNativeSelection(_ range: NSRange) {
        guard !invalidated else { return }
        if storedTyping != nil, storedTypingOffset() != range.location || range.length != 0 { storedTyping = nil }
        let length = text.utf16.count
        guard range.location >= 0, range.length >= 0,
              range.location <= length, range.length <= length - range.location else { return }
        selectedRange = range
        revealSections(holding: range.location)
        noteTaskDraftCaret(range.location)
        onSelectionChange?()
    }

    public var nativeSelection: NSRange? {
        guard !invalidated, let range = selectedRange else { return nil }
        let length = text.utf16.count
        let location = min(range.location, length)
        return NSRange(location: location, length: min(range.length, length - location))
    }

    public func selectionAnchors() throws -> [Data] {
        guard !invalidated else { return [] }
        guard let range = nativeSelection else { return [] }
        let offsets = range.length == 0 ? [range.location] : [range.location, NSMaxRange(range)]
        let projection = try proseProjection(document)
        return try offsets.compactMap { offset in
            guard let position = projection.position(atUTF16: offset) else { return nil }
            return try document.anchor(path: position.path, index: position.index)
        }
    }

    func projectionOffset(path: [Int], index: Int) throws -> Int? {
        return try proseProjection(document).offset(path: path, index: index)
    }

    public func selectionRelativeRange() throws -> RelayMarkRelativeRange? {
        guard !invalidated, isSupported else { return nil }
        let anchors = try selectionAnchors()
        guard let first = anchors.first else { return nil }
        return try .init(anchor: first, head: anchors.last ?? first)
    }

    public func resolveRelativeRange(_ range: RelayMarkRelativeRange) throws -> NSRange? {
        guard !invalidated, isSupported, pending == nil else { return nil }
        guard let anchor = try document.resolve(anchor: range.anchor),
              let head = try document.resolve(anchor: range.head),
              let start = try projectionOffset(path: anchor.path, index: anchor.index),
              let end = try projectionOffset(path: head.path, index: head.index) else { return nil }
        return NSRange(location: min(start, end), length: abs(end - start))
    }

    public func refreshPresence() throws {
        guard !invalidated else { return }
        remoteSelections = try document.presence.collaborators().compactMap { collaborator in
            guard let anchor = collaborator.anchor, let head = collaborator.head,
                  let start = try document.resolve(anchor: anchor), let end = try document.resolve(anchor: head),
                  let first = try projectionOffset(path: start.path, index: start.index),
                  let last = try projectionOffset(path: end.path, index: end.index) else { return nil }
            return RelayMarkRemoteSelection(id: collaborator.id, name: collaborator.name, color: collaborator.color,
                range: NSRange(location: min(first, last), length: abs(last - first)), caretLocation: last)
        }
    }

    private func projectedText() throws -> AttributedString {
        return try proseProjection(document).text
    }

    /// Marked input remains outside the CRDT until the OS commits it.
    func beginComposition() throws -> Composition {
        guard isEditable, pending == nil, activeComposition == nil else { throw CancellationError() }
        let token = Composition(owner: compositionOwner, id: UUID(), original: text)
        activeComposition = token
        declaredMarkedInput = nil
        return token
    }

    func cancelComposition(_ token: Composition) {
        guard activeComposition?.id == token.id, token.owner == compositionOwner else { return }
        activeComposition = nil
        declaredMarkedInput = nil
        applyDeferredRemoteUpdates()
    }

    /// Applies the committed text as one edit against the text the composition
    /// started from; peer updates that waited merge afterwards.
    func commitComposition(_ proposed: AttributedString, from token: Composition) throws {
        guard !invalidated, canEdit(), activeComposition?.id == token.id,
              token.owner == compositionOwner else { throw CancellationError() }
        noteFallback("composition")
        defer {
            if activeComposition?.id == token.id { activeComposition = nil }
            declaredMarkedInput = nil
            applyDeferredRemoteUpdates()
        }
        if let declared = declaredMarkedInput, declared.tokenID == token.id, declared.ownerID == token.owner {
            let original = String(token.original.characters), candidate = String(proposed.characters)
            // An empty marked range is a completed composition, not a body edit.
            // Keep exact attributed equality: a formatting change is not a no-op.
            if proposed == token.original, declared.literal == nil || (declared.literal?.isEmpty == true && declared.initialReplacement.length == 0) {
                return
            }
            guard let literal = declared.literal else { throw AuthoredBlockEditFailure.changed }
            let command = RelayNativeTextReplacement(baseline: original,
                range: declared.initialReplacement, replacement: literal)
            // Keep actual OS fragments; never infer a replacement from a diff.
            guard command.matches(original: original, proposed: candidate) else { throw AuthoredBlockEditFailure.changed }
            activeComposition = nil
            edit(proposed, nativeReplacement: command, nativePaste: nil)
        } else {
            activeComposition = nil
            edit(proposed)
        }
    }

    /// Commits declared marked input as typing inside one text leaf when the
    /// view shows exactly that literal in place, so the commit reads only the
    /// leaf. Returns the replaced range and committed text; nil leaves the
    /// commit to `commitComposition`.
    func commitCompositionNatively(from token: Composition, renderedLength: Int,
                                   rendered: (NSRange) -> String?) -> (range: NSRange, text: String)? {
        guard !invalidated, canEdit(), activeComposition?.id == token.id, token.owner == compositionOwner,
              let declared = declaredMarkedInput, declared.tokenID == token.id, declared.ownerID == token.owner,
              let literal = declared.literal else { return nil }
        let range = declared.initialReplacement, length = literal.utf16.count
        guard renderedLength == text.utf16.count - range.length + length,
              rendered(NSRange(location: range.location, length: length)) == literal else { return nil }
        activeComposition = nil
        // Marked text committed where no text leaf exists yet, as in an empty
        // paragraph, is the first text of that block.
        guard length == 0 && range.length == 0 || typeNatively(range: range, replacement: literal) ||
              range.length == 0 && editStructureNatively(range: range, replacement: literal) else {
            activeComposition = token
            return nil
        }
        declaredMarkedInput = nil
        applyDeferredRemoteUpdates()
        return (range, literal)
    }

    func registerNativeCompositionFinalizer(_ finish: @escaping () throws -> Void, refresh: @escaping () -> Void) -> UUID {
        let id = UUID()
        guard !invalidated else { return id }
        nativeCompositionFinalizer = (id, finish, refresh)
        return id
    }

    func unregisterNativeCompositionFinalizer(_ registration: UUID) {
        if nativeCompositionFinalizer?.id == registration { nativeCompositionFinalizer = nil }
    }

    /// Commits any marked input before the host reads or detaches this editor.
    public func finishNativeComposition() throws {
        guard !invalidated else { throw CancellationError() }
        try nativeCompositionFinalizer?.finish()
    }

    public func invalidate(reason: String? = nil) {
        let reason = reason ?? String(localized: "This editing session is no longer active.", bundle: .module, comment: "Shown when the paper's editing session has ended.")
        invalidated = true
        storedTyping = nil
        let refresh = nativeCompositionFinalizer?.refresh
        nativeCompositionFinalizer = nil
        text = AttributedString()
        isSupported = false
        remoteSelections = []
        selectedRange = nil
        onSelectionChange = nil
        onLinkedTaskItem = nil
        linkedTaskStatus = nil
        onHistory = nil
        pending = nil
        activeComposition = nil
        deferredRemoteUpdates = []
        awaitingPredecessor = nil
        pendingCommit = nil
        failure = reason
        refresh?()
    }

    /// The native view showed input the document refused; show the document again.
    func retain(_ candidate: AttributedString, reason: String) {
        if let projected = try? projectedText() { text = projected }
        failure = reason
    }
}

/// What a host builds its own commands from: the replica, its projection and
/// one way to change it.
extension RelayMarkEditorSession {
    /// Words in `text`, as the footer counts them.
    public static func words(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "\u{FFFC}" }).count
    }

    /// Identifies this session in reviews a host captures before an
    /// asynchronous choice, so a review never applies to another session.
    public var ownerID: UUID { compositionOwner }
    /// Whether marked input is open; commands wait until it commits.
    public var isComposing: Bool { activeComposition != nil }
    /// The projection of the replica as it is now.
    public func projection() throws -> RelayMarkCollaborativeProse { try currentProjection() }
    /// Shows a host command's failure where the editor shows its own.
    public func report(_ failure: String?) { self.failure = failure }

    public enum InlineAtomEditFailure: LocalizedError {
        case changed
        public var errorDescription: String? {
            String(localized: "The paper or selection changed. Select the reference or insertion point and try again.", bundle: .module, comment: "Shown when a reference's target moved.")
        }
    }

    public enum AuthoredBlockEditFailure: LocalizedError {
        case changed
        public var errorDescription: String? {
            String(localized: "The paper or selection changed. Select the authored block or insertion point and try again.", bundle: .module, comment: "Shown when an authored block's target moved.")
        }
    }

    /// Applies a host command to the replica as its own undo item and saves
    /// its update. Only the nodes the update touched are projected again, so
    /// the view replaces just those; `select` places the caret afterwards.
    @discardableResult
    public func perform<Value>(inputIntent: RelayMarkLocalTransaction.InputIntent? = .derived,
                               operationID: UUID? = nil,
                               select: ((RelayMarkCollaborativeProse) -> NSRange?)? = nil,
                               _ command: (RelayMarkNativeDocument) throws -> Value,
                               update: (Value) throws -> Data) throws -> Value {
        guard isEditable, pending == nil, activeComposition == nil else { throw AuthoredBlockEditFailure.changed }
        let revisionBefore = document.revision, textBefore = textRevision
        let value = try ownedChange({ try command(document) }, separateHistoryItem: true,
                                    operationID: operationID, update: update)
        let projection = try show(try update(value), after: revisionBefore, textBefore: textBefore)
        if let range = select?(projection) { setNativeSelection(range) }
        pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: try update(value), inputIntent: inputIntent)
        retryPersistence()
        return value
    }
}
