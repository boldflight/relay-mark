import Foundation
import OSLog
import Observation
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkProseProjection
import RelayMarkSwift
import SwiftUI

/// The native text view's editing contract: typing, structure, paste and
/// marks as range commands into the replica.
extension RelayMarkEditorSession: RelayPaperTextEditing {
    var nativeEmptyBlocks: [RelayEmptyProseBlock] {
            guard let projection = try? currentProjection() else { return [] }
            return emptyBlocks(of: projection)
        }

    func emptyBlocks(of projection: RelayMarkCollaborativeProse) -> [RelayEmptyProseBlock] {
            zip(projection.blockRanges, projection.blockIntents).compactMap { range, intent in
                guard range.length == 0 else { return nil }
                var block = RelayEmptyProseBlock(offset: range.location, intent: intent)
                if let storedTyping, storedTypingOffset() == range.location {
                    block.typingStyle = try? RelayMarkCollaborativeProse.attributedText(text: "x", attributes: storedTyping.attributes)
                }
                return block
            }
        }

    func edit(_ candidate: AttributedString, nativeReplacement: RelayNativeTextReplacement?,
              nativePaste: RelayNativePasteCommand?) {
        if nativePaste == nil, let command = nativeReplacement,
           typeNatively(range: command.range, replacement: command.replacement) { return }
        noteFallback("edit")
        let original = String(text.characters), proposed = String(candidate.characters)
        if let nativeReplacement, !nativeReplacement.matches(original: original, proposed: proposed) {
            retain(candidate, reason: String(localized: "The native replacement no longer matches this paper.", bundle: .module, comment: "Shown on the paper when an edit is kept for review."))
            return
        }
        if let nativePaste {
            guard let nativeReplacement, nativePaste.matches(nativeReplacement, current: text) else {
                retain(candidate, reason: String(localized: "The paste selection changed before it could be saved.", bundle: .module, comment: "Shown on the paper when a paste is kept for review."))
                return
            }
        }
        if nativePaste == nil, let command = nativeReplacement, command.replacement == "\n",
           command.range.length == 0, activeComposition == nil {
            handleRichStructuralReturn(candidate, command: command)
            return
        }
        if nativePaste == nil, let command = nativeReplacement, command.replacement == "\n",
           command.range.length > 0, activeComposition == nil {
            handleRichSelectionReturn(candidate, command: command)
            return
        }

        if nativePaste == nil,            let command = nativeReplacement,
           let boundary = RelayNativeRichEdit.boundaryKey(document: document, range: command.range,
                                                                replacement: command.replacement, caret: nativeSelection) {
            applyRichBoundaryKey(candidate, key: boundary.key, offset: boundary.offset)
            return
        }
        if let nativePaste, let nativeReplacement {
            guard let scoped = nativePaste.attributedCandidate(replacement: nativeReplacement,
                                                               rendered: candidate) else {
                retain(candidate, reason: String(localized: "The paste selection changed before it could be saved.", bundle: .module, comment: "Shown on the paper when a paste is kept for review."))
                return
            }
            storedTyping = nil
            replaceRichSelection(scoped, command: nativeReplacement)
        } else if let nativeReplacement {
            // TextKit owns the actual input range. Text equality cannot select
            // identity retention or erase an equal-value replacement command.
            replaceRichSelection(candidate, command: nativeReplacement)
        } else {
            edit(candidate)
        }
    }



    /// The video block selected as one unit, for host playback.
    public var selectedVideoID: String? {
        guard let selection = nativeSelection else { return nil }
        return nativeMediaAtoms.first { $0.kind == .videoEmbed && $0.range == selection }?.source
    }

    /// A reference or tag insertion bound to the selection shown when the
    /// picker opened; a changed paper or selection fails closed on insert.
    public struct ReferenceInsertion: Identifiable {
        public enum Kind { case entity, tag, image, video, videoFile, file }
        public let id = UUID()
        public let kind: Kind
        fileprivate let owner: UUID
        fileprivate let checkpoint: Data
        fileprivate let snapshot: Data
        fileprivate let range: NSRange
    }

    /// Capture the current native caret before an asynchronous host-owned picker.
    public func prepareEntityReferenceInsertion() throws -> ReferenceInsertion {
        try prepareReferenceInsertion(.entity)
    }

    public func prepareReferenceInsertion(_ kind: ReferenceInsertion.Kind) throws -> ReferenceInsertion {
        guard isEditable, pending == nil,
              activeComposition == nil, let range = nativeSelection,
              try currentProjection().blockRanges.contains(where: {
                  range.location >= $0.location && NSMaxRange(range) <= NSMaxRange($0)
              }) else { throw InlineAtomEditFailure.changed }
        return ReferenceInsertion(kind: kind, owner: compositionOwner, checkpoint: try document.encodeUpdate(),
                                  snapshot: try document.snapshot(), range: range)
    }

    /// TipTap insertTable({ rows: 3, cols: 3, withHeaderRow: true }).
    public func insertTable() {
        func cell(_ header: Bool) -> [String: Any] {
            ["type": header ? "tableHeader" : "tableCell", "content": [["type": "paragraph"]]]
        }
        insertBlock(["type": "table", "content": (0..<3).map { row -> [String: Any] in
            ["type": "tableRow", "content": (0..<3).map { _ in cell(row == 0) }]
        }], placement: .replaceSelection)
    }

    public func insertDivider() {
        insertBlock(["type": "horizontalRule"], placement: .insertContent)
    }

    public func insertCallout() {
        insertBlock(["type": "callout", "content": [["type": "paragraph"]]], placement: .insertContent)
    }

    public func insertCodeBlock() {
        insertBlock(["type": "codeBlock"], placement: .insertContent)
    }

    /// The picker owns no document mutation until its captured insertion is
    /// still current. Async uploads cannot apply to a changed owner or document.
    public func validateImageInsertion(_ edit: ReferenceInsertion) throws {
        guard edit.kind == .image, canInsertBlock, edit.owner == compositionOwner,
              nativeSelection == edit.range, edit.checkpoint == (try document.encodeUpdate()),
              edit.snapshot == (try document.snapshot()) else { throw InlineAtomEditFailure.changed }
    }

    func insertImage(_ url: URL, alt: String, using edit: ReferenceInsertion) {
        do { try insertImageSource(url.absoluteString, alt: alt, using: edit, addressInput: true) }
        catch { failure = error.localizedDescription }
    }

    /// Accepts an HTTPS address or the exact authorized canonical media source.
    public func insertImageSource(_ source: String, alt: String, using edit: ReferenceInsertion, operationID: UUID? = nil, addressInput: Bool = false) throws {
        try validateImageInsertion(edit)
        let canonical = source.hasPrefix("/m/") && UUID(uuidString: String(source.dropFirst(3))) != nil
        let external = URL(string: source).map { $0.scheme == "https" && $0.host?.isEmpty == false } == true
        guard canonical || external else { throw InlineAtomEditFailure.changed }
        guard !addressInput || external else { throw InlineAtomEditFailure.changed }
        let trimmed = alt.trimmingCharacters(in: .whitespacesAndNewlines)
        let original: RelayMarkDeclaredCommandInput? = addressInput || !trimmed.isEmpty
            ? .image(source: addressInput ? source : nil, alt: trimmed) : nil
        try original?.validate()
        var attrs: [String: Any] = ["src": source]
        if !trimmed.isEmpty { attrs["alt"] = trimmed }
        let revisionBefore = document.revision, textBefore = textRevision
        let change = try ownedChange({ try RelayMarkNativeRichEditing.insertBlock(document: document, range: edit.range,
            block: ["type": "image", "attrs": attrs], placement: .insertContent, expectedSnapshot: edit.snapshot) }, separateHistoryItem: true, operationID: operationID, update: { $0.update })
        try adoptRichChange(change, checkpoint: edit.checkpoint, revisionBefore: revisionBefore, textBefore: textBefore, fallback: edit.range.location, declaredInput: original)
    }

    /// One compound insertion the host fitted as a clipboard slice: one
    /// owned Undo item, saved through `commit` instead of the session's journal.
    public func insertSlice(_ slice: Data, using edit: ReferenceInsertion, operationID: UUID,
                     commit: @escaping @MainActor (RelayMarkLocalTransaction) throws -> Void) throws {
        let revisionBefore = document.revision, textBefore = textRevision
        pendingCommit = (operationID, commit)
        defer { if pending == nil { pendingCommit = nil } }
        let change = try ownedChange({ try RelayMarkNativeRichEditing.insertDocumentSlice(document: document,
            range: edit.range, clipboardSlice: slice, expectedSnapshot: edit.snapshot) },
            separateHistoryItem: true, operationID: operationID, update: { $0.update })
        try adoptRichChange(change, checkpoint: edit.checkpoint, revisionBefore: revisionBefore, textBefore: textBefore, fallback: edit.range.location)
        if let failure { throw RelayMarkEditFailure(failure) }
    }

    /// The operation whose save waits on a host commit, while it is unsaved.
    public var pendingCommitOperationID: UUID? { pending == nil ? nil : pendingCommit?.operationID }

    public func validateFileInsertion(_ edit: ReferenceInsertion) throws {
        guard edit.kind == .file, canInsertBlock, edit.owner == compositionOwner,
              nativeSelection == edit.range, edit.checkpoint == (try document.encodeUpdate()),
              edit.snapshot == (try document.snapshot()) else { throw InlineAtomEditFailure.changed }
    }

    /// Library discovery is authorized by the existing media capability. Only
    /// its selected identity enters the paper; playback grants stay with media.
    public func validateVideoInsertion(_ edit: ReferenceInsertion) throws {
        guard (edit.kind == .video || edit.kind == .videoFile), canInsertBlock, edit.owner == compositionOwner,
              nativeSelection == edit.range, edit.checkpoint == (try document.encodeUpdate()),
              edit.snapshot == (try document.snapshot()) else { throw InlineAtomEditFailure.changed }
    }

    /// Library discovery is authorized by the existing media capability. Only
    /// its selected identity enters the paper; playback grants stay with media.
    public func insertVideo(id: String, using edit: ReferenceInsertion) throws {
        try validateVideoInsertion(edit)
        guard UUID(uuidString: id) != nil else { throw InlineAtomEditFailure.changed }
        let revisionBefore = document.revision, textBefore = textRevision
        let change = try ownedChange({ try RelayMarkNativeRichEditing.insertBlock(document: document, range: edit.range,
            block: ["type": "videoEmbed", "attrs": ["videoId": id]], placement: .insertContent,
            expectedSnapshot: edit.snapshot) }, separateHistoryItem: true, update: { $0.update })
        try adoptRichChange(change, checkpoint: edit.checkpoint, revisionBefore: revisionBefore, textBefore: textBefore, fallback: edit.range.location)
    }

    public var offersBlockInsertion: Bool { true }

    public var canInsertBlock: Bool {
        isEditable && pending == nil &&
            activeComposition == nil && nativeSelection != nil
    }

    private func insertBlock(_ block: [String: Any], placement: RelayMarkNativeRichEditing.BlockPlacement) {
        do {
            guard canInsertBlock, let range = nativeSelection else { throw InlineAtomEditFailure.changed }
            let checkpoint = try document.encodeUpdate(), revisionBefore = document.revision, textBefore = textRevision
            let change = try ownedChange({ try RelayMarkNativeRichEditing.insertBlock(document: document, range: range,
                block: block, placement: placement, expectedSnapshot: document.snapshot()) }, separateHistoryItem: true, update: { $0.update })
            try adoptRichChange(change, checkpoint: checkpoint, revisionBefore: revisionBefore, textBefore: textBefore, fallback: range.location)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Insert an already-resolved canonical entity identity through the same
    /// native selection fence, persistence journal and undo transaction.
    public func insertEntityReference(id: String, label: String, using edit: ReferenceInsertion) {
        guard UUID(uuidString: id) != nil, edit.kind == .entity else {
            failure = InlineAtomEditFailure.changed.localizedDescription
            return
        }
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let link: [String: Any] = ["href": "relay:entity/\(id)", "target": "_blank",
                                   "rel": "noopener noreferrer nofollow", "class": NSNull(), "title": NSNull()]
        insertReferenceContent([.text(label.isEmpty ? id : label, attributes: ["link": link]), .text(" ")],
                               using: edit)
    }

    /// Inserts a stable #tag reference with its RelayMark source spelling.
    public func insertTag(id: String, name: String, using edit: ReferenceInsertion) {
        insertReferenceContent([.node("relayTag", attributes: ["id": id, "name": name,
                                                               "source": "[[Tag: \(id) | #\(name)]]"]),
                                .text(" ")], using: edit)
    }

    private func insertReferenceContent(_ content: [RelayMarkNativeRichEditing.Inline],
                                        using edit: ReferenceInsertion) {
        do {
            guard isEditable, pending == nil, activeComposition == nil,
                  edit.owner == compositionOwner, nativeSelection == edit.range,
                  edit.checkpoint == (try document.encodeUpdate()), edit.snapshot == (try document.snapshot()) else {
                throw InlineAtomEditFailure.changed
            }
            let revisionBefore = document.revision, textBefore = textRevision
            let change = try ownedChange({ try RelayMarkNativeRichEditing.insert(document: document, range: edit.range,
                                                                     content: content, expectedSnapshot: edit.snapshot) }, separateHistoryItem: true, update: { $0.update })
            try adoptRichChange(change, checkpoint: edit.checkpoint, revisionBefore: revisionBefore, textBefore: textBefore, fallback: edit.range.location)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Adopts a ProseMirror-engine change: projected text, mapped caret, and
    /// the regular persistence and undo journal.
    private func adoptRichChange(_ change: RelayMarkNativeRichEditing.Change, checkpoint: Data,
                                 revisionBefore: Int, textBefore: Int, fallback: Int,
                                 declaredInput: RelayMarkDeclaredCommandInput? = nil) throws {
        let expected = try show(change.update, after: revisionBefore, textBefore: textBefore)
        let caret = change.caret.flatMap { caret in
            expected.blockPaths.firstIndex(of: caret.blockPath).map { expected.blockRanges[$0].location + caret.offset }
        }
        setNativeSelection(NSRange(location: caret ?? min(fallback, String(text.characters).utf16.count), length: 0))
        pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: change.update,
            inputIntent: declaredInput.map { .declaredCommand($0) })
        retryPersistence()
    }

    /// Backspace or Delete at a block boundary through ProseMirror's keymap
    /// chain: joins, list and quote lifts, or no change where the browser
    /// makes none (for example at an isolating table cell).
    /// `candidate` is the text the view shows when it already applied the key;
    /// nil when it showed no change, so a key that changes nothing re-renders nothing.
    private func applyRichBoundaryKey(_ candidate: AttributedString?,
                                            key: RelayMarkNativeRichEditing.Key, offset: Int) {
        guard isEditable, pending == nil, activeComposition == nil else { return }
        do {
            let original = text, revisionBefore = document.revision, textBefore = textRevision
            guard let change = try ownedChange({ try RelayMarkNativeRichEditing.key(key, document: document, at: offset,
                                                                         expectedSnapshot: document.snapshot()) }, separateHistoryItem: true, update: { $0?.update ?? Data([0, 0]) }) else {
                if candidate != nil { text = original }
                setNativeSelection(NSRange(location: offset, length: 0))
                return
            }
            let expected = try show(change.update, after: revisionBefore, textBefore: textBefore)
            let caret = change.caret.flatMap { caret in
                expected.blockPaths.firstIndex(of: caret.blockPath).map { expected.blockRanges[$0].location + caret.offset }
            }
            setNativeSelection(NSRange(location: caret ?? min(offset, String(text.characters).utf16.count), length: 0))
            pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: change.update)
            retryPersistence()
        } catch {
            let reason = String(localized: "This join could not be applied without changing unsupported structure.", bundle: .module, comment: "Shown on the paper when a join is kept for review.")
            if let candidate { retain(candidate, reason: reason) } else { failure = reason }
        }
    }

    /// Cross-block and multi-line replacement through ProseMirror's own
    /// algorithm. The native view adopts ProseMirror's resulting text and
    /// caret, which can differ from a plain text splice across containers.
    private func replaceRichSelection(_ candidate: AttributedString, command: RelayNativeTextReplacement) {
        guard isEditable, pending == nil, activeComposition == nil else { return }
        do {
            let before = String(text.characters)
            let typing = storedTyping.flatMap { context -> Data? in
                command.range.length == 0 && storedTypingOffset() == command.range.location ? context.attributes : nil
            }
            // Typing over a selection starts a new undo item; typing that follows joins it.
            if command.range.length > 0 { document.closeUndoItem() }
            let result = try ownedChange({ try RelayNativeRichEdit.replaceSelection(document: document, range: command.range,
                candidate: candidate, insertedLength: command.replacement.utf16.count, storedTextAttributes: typing) }, update: { $0.update })
            text = result.text
            setNativeSelection(NSRange(location: result.caret ?? command.range.location, length: 0))
            try retainTypingContext(typing, caret: result.caret ?? command.range.location)
            pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: result.update,
                inputIntent: .nativeReplacement(startUTF16: command.range.location,
                    removed: (before as NSString).substring(with: command.range), inserted: command.replacement))
            retryPersistence()
        } catch {
            retain(candidate, reason: String(localized: "This selection could not be replaced without changing unsupported structure.", bundle: .module, comment: "Shown on the paper when a replacement is kept for review."))
        }
    }

    /// Whether a typed replacement stays inside one text leaf, the case the
    /// typing path handles without reading the whole paper.
    func canTypeNatively(range: NSRange, replacement: String) -> Bool {
        guard isEditable, pending == nil, activeComposition == nil,
              replacement.utf16.count <= 131_072,
              !replacement.unicodeScalars.contains(where: { "\n\r\u{2028}\u{2029}\u{FFFC}".unicodeScalars.contains($0) }),
              let projection = try? currentProjection() else { return false }
        return projection.textPosition(replacing: range) != nil
    }

    func scheduleWordCount() {
        wordCountTask?.cancel()
        wordCountTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            wordCount = Self.words(in: String(text.characters))
        }
    }

    /// Types or deletes inside one text leaf. Only that leaf changes in the
    /// replica and the projection is updated in place, so the cost does not
    /// grow with the paper. Returns false when the edit needs the general path.
    @discardableResult func typeNatively(range: NSRange, replacement: String) -> Bool {
        guard canTypeNatively(range: range, replacement: replacement),
              let position = (try? currentProjection())?.textPosition(replacing: range),
              let selected = Range(range, in: text) else { return false }
        let revisionBefore = document.revision
        let stored = storedTyping.flatMap { context -> (data: Data, value: [String: Any])? in
            guard range.length == 0, storedTypingOffset() == range.location,
                  let value = try? JSONSerialization.jsonObject(with: context.attributes) as? [String: Any] else { return nil }
            return (context.attributes, value)
        }
        let removed = String(text[selected].characters)
        // Typing over a selection starts a new undo item; typing that follows joins it.
        if range.length > 0, !removed.isEmpty, replacement.isEmpty == false { document.closeUndoItem() }
        let typed: (update: Data, attributes: [String: Any])
        do {
            typed = try ownedChange({ try document.typeText(replacement, replacing: range.length, at: position.index,
                path: position.path, attributes: stored?.value) }, typingPath: position.path, update: { $0.update })
        } catch { return false }
        // The leaf has changed; from here the edit is committed and only its presentation remains.
        // The cache is the projection's only owner here, so it updates in place.
        if var next = projectionCache?.value, projectionCache?.revision == revisionBefore {
            projectionCache = nil
            if next.replaceText(in: range, with: replacement, attributes: typed.attributes) {
                projectionCache = (document.revision, next)
                text = next.text
            } else if let projected = try? currentProjection() { text = projected.text }
        } else if let projected = try? currentProjection() {
            text = projected.text
        }
        let caret = range.location + replacement.utf16.count
        setNativeSelection(NSRange(location: caret, length: 0))
        if let stored { try? retainTypingContext(stored.data, caret: caret) }
        pending = RelayMarkLocalTransaction(id: preparedLocalOperationID ?? UUID(), update: typed.update,
            inputIntent: .nativeReplacement(startUTF16: range.location, removed: removed, inserted: replacement))
        retryPersistence()
        return true
    }

    /// Return over a selection: ProseMirror deletes the selection, then splits
    /// at the caret, in one transaction and one undo step.
    private func handleRichSelectionReturn(_ candidate: AttributedString, command: RelayNativeTextReplacement) {
        guard isEditable, pending == nil, activeComposition == nil else { return }
        do {
            let checkpoint = try document.encodeUpdate()
            let scratch = RelayMarkNativeDocument(); try scratch.applyUpdate(checkpoint)
            _ = try RelayNativeRichEdit.structuralReturn(document: scratch, at: command.range.location,
                selectionEnd: NSMaxRange(command.range))
            let expected = try scratch.richProseProjection()
            guard expected.isEditable else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            let result = try ownedChange({ try RelayNativeRichEdit.structuralReturn(document: document,
                at: command.range.location, selectionEnd: NSMaxRange(command.range)) },
                separateHistoryItem: true, update: { $0.change.update })
            text = expected.text
            let caret = result.change.caret.flatMap { value in
                expected.blockPaths.firstIndex(of: value.blockPath).map { expected.blockRanges[$0].location + value.offset }
            } ?? min(command.range.location + 1, String(text.characters).utf16.count)
            setNativeSelection(NSRange(location: caret, length: 0))
            try retainTypingContext(result.change.storedTextAttributes, caret: caret)
            pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: result.change.update)
            retryPersistence()
        } catch { retain(candidate, reason: String(localized: "This Return needs a supported structural boundary.", bundle: .module, comment: "Shown on the paper when a Return is kept for review.")) }
    }

    private func retainTypingContext(_ attributes: Data?, caret: Int) throws {
        guard let attributes else { storedTyping = nil; return }
        let projection = try currentProjection()
        guard let position = projection.position(atUTF16: caret) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        storedTyping = (anchor: try document.anchor(path: position.path, index: position.index), attributes: attributes)
    }

    func storedTypingOffset() -> Int? {
        guard let storedTyping, let position = try? document.resolve(anchor: storedTyping.anchor) else { return nil }
        return try? projectionOffset(path: position.path, index: position.index)
    }

    /// Return, or removing one block separator, as one windowed command over
    /// the top-level nodes it touches: no candidate text, rehearsal or
    /// re-projection covers the rest of the paper. False leaves the edit to
    /// the general path.
    /// Plain text pasted over a selection as ProseMirror pastes text: one line
    /// takes the marks where it lands and several lines become paragraphs, at
    /// the cost of the blocks the selection touches.
    public func pastePlainTextNatively(range: NSRange, text pasted: String) -> Bool {
        let normalized = pasted.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.isEmpty, acceptsNativePastePayload(normalized) else { return false }
        return editStructureNatively(range: range, replacement: normalized, pasting: true)
    }

    /// Rich text pasted over a selection, with its marks, the same way.
    func pasteNatively(range: NSRange, piece: AttributedString) -> Bool {
        var normalized = piece
        let plain = String(piece.characters)
        if plain.contains("\r\n") { normalized = AttributedString(plain.replacingOccurrences(of: "\r\n", with: "\n")) }
        let text = String(normalized.characters)
        guard !text.isEmpty, acceptsNativePastePayload(text),
              let runs = try? RelayNativeRichEdit.runs(of: normalized, document: document) else { return false }
        return editStructureNatively(range: range, replacement: text, pasting: true, runs: runs)
    }

    func editStructureNatively(range: NSRange, replacement: String) -> Bool {
        editStructureNatively(range: range, replacement: replacement, pasting: false)
    }

    private func editStructureNatively(range: NSRange, replacement: String, pasting: Bool,
                                       runs pasted: [(text: String, attributes: [String: Any])]? = nil) -> Bool {
        guard isEditable, pending == nil, activeComposition == nil else { return false }
        let revisionBefore = document.revision, textBefore = textRevision
        var exit = false, removed: String?
        // The first text typed where no text leaf exists yet, as in an empty
        // paragraph or cell, takes the stored marks there.
        let stored = storedTyping.flatMap { context -> (data: Data, value: [String: Any])? in
            guard range.length == 0, storedTypingOffset() == range.location,
                  let value = try? JSONSerialization.jsonObject(with: context.attributes) as? [String: Any] else { return nil }
            return (context.attributes, value)
        }
        let edited: (change: RelayMarkNativeRichEditing.Change, rewrites: Rewritten?)?
        do {
            edited = try reading { paper -> (RelayMarkNativeRichEditing.Change, Rewritten?)? in
                let change: RelayMarkNativeRichEditing.Change
                if replacement == "\n", !pasting {
                    guard let start = paper.block(containingUTF16: range.location),
                          let end = paper.block(containingUTF16: NSMaxRange(range)) else { return nil }
                    let selectionEnd = range.length > 0
                        ? RelayMarkNativeRichEditing.Caret(blockPath: end.path, offset: NSMaxRange(range) - end.range.location) : nil
                    let result = try ownedChange({ try RelayMarkNativeRichReturn.apply(document: document, blockPath: start.path,
                        utf16Offset: range.location - start.range.location, selectionEnd: selectionEnd, paper: paper) },
                        separateHistoryItem: true, update: { $0.change.update })
                    change = result.change; exit = result.kind == .exit
                } else if replacement.isEmpty, range.length == 1, !pasting,
                          let before = paper.block(containingUTF16: range.location), NSMaxRange(before.range) == range.location,
                          paper.block(containingUTF16: NSMaxRange(range))?.range.location == NSMaxRange(range) {
                    // A block separator: TextKit's Backspace removes the one before the caret, Delete the one after it.
                    let key: RelayMarkNativeRichEditing.Key = nativeSelection?.location == range.location ? .delete : .backspace
                    let offset = key == .backspace ? NSMaxRange(range) : range.location
                    guard let joined = try ownedChange({ try RelayMarkNativeRichEditing.key(key, document: document, at: offset, paper: paper) },
                        separateHistoryItem: true, update: { $0?.update ?? Data([0, 0]) }) else { return nil }
                    change = joined
                } else if range.length > 0 || pasting, let bounds = Range(range, in: text),
                          !replacement.unicodeScalars.contains(where: { "\r\u{2028}\u{2029}\u{FFFC}".unicodeScalars.contains($0) }),
                          pasting || !replacement.contains("\n") {
                    // Typing over, or deleting, a selection that spans blocks, or a
                    // paste; a single line takes the marks at the selection's start.
                    removed = String(text[bounds].characters)
                    if range.length > 0 || pasting { document.closeUndoItem() }
                    change = try ownedChange({ try RelayMarkNativeRichEditing.replace(document: document, range: range,
                        runs: replacement.isEmpty ? [] : pasted ?? [(replacement, [:])], inheritMarks: pasted == nil, paper: paper) },
                        separateHistoryItem: pasting, update: { $0.update })
                } else if range.length == 0, !pasting, !replacement.isEmpty,
                          !replacement.unicodeScalars.contains(where: { "\n\r\u{2028}\u{2029}\u{FFFC}".unicodeScalars.contains($0) }) {
                    removed = ""
                    change = try ownedChange({ try RelayMarkNativeRichEditing.replace(document: document, range: range,
                        runs: [(replacement, stored?.value ?? [:])], inheritMarks: stored == nil, paper: paper) },
                        update: { $0.update })
                } else { return nil }
                return (change, rewritten(change, paper: paper))
            }
        } catch { return false }
        guard let (change, rewrites) = edited else { return false }
        // The command has applied; only its presentation can fall back to a full projection.
        let splice = rewrites.flatMap { splice($0, after: revisionBefore) }
        guard let projection = try? currentProjection() else { return true }
        text = projection.text
        // Return at a caret lands after the split, or on the block an empty item exits to.
        let caret: Int?
        if replacement == "\n", range.length == 0 {
            caret = exit ? projection.emptyBlock(atOrAfterUTF16: range.location) ?? range.location : range.location + 1
        } else {
            caret = change.caret.flatMap { caret in projection.blockRange(path: caret.blockPath).map { $0.location + caret.offset } }
        }
        let selection = min(caret ?? range.location, text.utf16.count)
        setNativeSelection(NSRange(location: selection, length: 0))
        try? retainTypingContext(stored?.data ?? change.storedTextAttributes, caret: selection)
        // The view's empty-block styles include the typing context just retained.
        if let splice, let restricted = splice.restricted {
            var region = self.region(of: restricted)
            region.content = splice.nodes?.content ?? region.content
            textSplice = RelayTextSplice(from: textBefore, to: textRevision, ranges: splice.ranges, nodes: region)
        }
        pending = RelayMarkLocalTransaction(id: preparedLocalOperationID ?? UUID(), update: change.update,
            inputIntent: removed.map { .nativeReplacement(startUTF16: range.location, removed: $0, inserted: replacement) })
        retryPersistence()
        return true
    }

    /// A keystroke that completes a typed Markdown shortcut (`- `, `[ ] `,
    /// `**bold**`), applied as the web's input rules apply it: the shortcut's
    /// text becomes the structure or mark, as one undo step, and the keystroke
    /// itself is not typed. Only a rule's last character costs more than a
    /// set lookup; marked (IME) input never reaches here.
    func applyInputRuleNatively(range: NSRange, replacement: String) -> Bool {
        guard isEditable, pending == nil, activeComposition == nil, range.length == 0,
              let last = replacement.last, RelayMarkContentEditCodec.inputRuleTriggers.contains(last) else { return false }
        let revisionBefore = document.revision, textBefore = textRevision
        let applied: (change: RelayMarkNativeRichEditing.Change, rule: String, rewrites: Rewritten?)?
        do {
            applied = try reading { paper in
                guard let block = paper.block(containingUTF16: range.location) else { return nil }
                let offset = range.location - block.range.location
                let window = NSRange(location: block.range.location + max(0, offset - 500), length: min(offset, 500))
                guard let bounds = Range(window, in: text),
                      RelayMarkNativeInputRule.mayComplete(before: String(text[bounds].characters), typing: replacement),
                      let result = try ownedChange({ try RelayMarkNativeInputRule.apply(document: document, blockPath: block.path,
                          utf16Offset: offset, text: replacement, paper: paper) },
                          separateHistoryItem: true, update: { $0?.change.update ?? Data([0, 0]) }) else { return nil }
                return (result.change, result.rule, rewritten(result.change, paper: paper))
            }
        } catch { return false }
        guard let (change, rule, rewrites) = applied else { return false }
        let splice = rewrites.flatMap { splice($0, after: revisionBefore) }
        guard let projection = try? currentProjection() else { return true }
        text = projection.text
        let caret = change.caret.flatMap { caret in projection.blockRange(path: caret.blockPath).map { $0.location + caret.offset } }
        let selection = min(caret ?? range.location, text.utf16.count)
        setNativeSelection(NSRange(location: selection, length: 0))
        try? retainTypingContext(change.storedTextAttributes, caret: selection)
        if let splice, let restricted = splice.restricted {
            var region = self.region(of: restricted)
            region.content = splice.nodes?.content ?? region.content
            textSplice = RelayTextSplice(from: textBefore, to: textRevision, ranges: splice.ranges, nodes: region)
        }
        pending = RelayMarkLocalTransaction(id: preparedLocalOperationID ?? UUID(), update: change.update, inputIntent: nil)
        retryPersistence()
        onTypedShortcut?(rule)
        return true
    }

    func handleNativeEdgeDeletion(backward: Bool) -> Bool {
        guard isEditable, pending == nil,
              activeComposition == nil, let selection = nativeSelection, selection.length == 0 else { return false }
        let length = String(text.characters).utf16.count
        guard backward ? selection.location == 0 : selection.location == length else { return false }
        applyRichBoundaryKey(nil, key: backward ? .backspace : .delete, offset: selection.location)
        return true
    }

    private func handleRichStructuralReturn(_ candidate: AttributedString,
                                                  command: RelayNativeTextReplacement) {
        guard isEditable, pending == nil, activeComposition == nil else { return }
        do {
            var unchanged = candidate
            let source = String(candidate.characters)
            let lower = AttributedString.Index(String.Index(utf16Offset: command.range.location, in: source),
                                               within: candidate)
            let upper = AttributedString.Index(String.Index(utf16Offset: command.range.location + 1, in: source),
                                               within: candidate)
            guard let lower, let upper else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            unchanged.removeSubrange(lower..<upper)
            guard relayPaperInlineSemantics(unchanged) == relayPaperInlineSemantics(text) else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            let checkpoint = try document.encodeUpdate(), scratch = RelayMarkNativeDocument()
            try scratch.applyUpdate(checkpoint)
            let result = try RelayNativeRichEdit.structuralReturn(document: scratch,
                                                                         at: command.range.location)
            let expected = try scratch.richProseProjection()
            let expectedSource = result.kind == .exit ? String(text.characters) : source
            guard expected.isEditable, String(expected.text.characters) == expectedSource else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            let changed = try ownedChange({ try RelayNativeRichEdit.structuralReturn(document: document,
                                                                         at: command.range.location) }, separateHistoryItem: true, update: { $0.change.update })
            text = expected.text
            let selection = result.kind == .exit
                ? (expected.blockRanges.first(where: {
                    $0.length == 0 && $0.location >= command.range.location
                })?.location ?? command.range.location)
                : command.range.location + 1
            setNativeSelection(NSRange(location: selection, length: 0))
            try retainTypingContext(changed.change.storedTextAttributes, caret: selection)
            pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: changed.change.update)
            retryPersistence()
        } catch { retain(candidate, reason: String(localized: "This Return needs a supported structural boundary.", bundle: .module, comment: "Shown on the paper when a Return is kept for review.")) }
    }



    public struct LinkEdit: Identifiable {
        public let id = UUID()
        fileprivate let owner: UUID
        fileprivate let checkpoint: Data
        fileprivate let range: NSRange
        fileprivate let attributes: [String: String]
        public var destination: String { attributes["href"] ?? "" }
        public var hasLink: Bool { attributes["href"] != nil }
    }

    enum LinkEditFailure: LocalizedError {
        case selectionChanged, unsupportedDestination, incompatibleCode
        var errorDescription: String? {
            switch self {
            case .selectionChanged: "The paper or selection changed. Select the text and open Link again."
            case .unsupportedDestination: "Use an absolute http, https, mailto, or canonical relay:entity/UUID link."
            case .incompatibleCode: "Remove inline code before adding a link."
            }
        }
    }

    public func prepareLinkEdit() throws -> LinkEdit {
        guard canFormatInlineSelection, let selection = nativeSelection,
              let projection = try? proseProjection(document) else { throw LinkEditFailure.selectionChanged }
        let slices = projection.textRanges(in: selection)
        guard slices.count == 1, let slice = slices.first, slice.length == selection.length,
              var node = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any] else {
            throw LinkEditFailure.selectionChanged
        }
        for index in slice.path {
            guard let children = node["children"] as? [[String: Any]], children.indices.contains(index) else {
                throw LinkEditFailure.selectionChanged
            }
            node = children[index]
        }
        guard let runs = node["delta"] as? [[String: Any]] else { throw LinkEditFailure.selectionChanged }
        var position = 0, seen: [[String: String]] = []
        for run in runs {
            guard let inserted = run["insert"] as? String else { throw LinkEditFailure.selectionChanged }
            let next = position + inserted.utf16.count
            if position < slice.index + slice.length && next > slice.index {
                let marks = run["attributes"] as? [String: Any] ?? [:]
                if let link = marks["link"] {
                    guard let attrs = link as? [String: Any], let href = attrs["href"] as? String else {
                        throw LinkEditFailure.selectionChanged
                    }
                    guard Set(attrs.keys) == Set(["href", "target", "rel", "class", "title"]),
                          attrs["target"] as? String == "_blank",
                          attrs["rel"] as? String == "noopener noreferrer nofollow",
                          attrs["class"] is NSNull, attrs["title"] is NSNull else {
                        throw LinkEditFailure.selectionChanged
                    }
                    seen.append(["href": href])
                } else { seen.append([:]) }
            }
            position = next
        }
        guard let attrs = seen.first, seen.allSatisfy({ $0 == attrs }) else { throw LinkEditFailure.selectionChanged }
        return LinkEdit(owner: compositionOwner, checkpoint: try document.encodeUpdate(), range: selection, attributes: attrs)
    }

    public func applyLink(_ destination: String?, review: LinkEdit) throws {
        guard isEditable, pending == nil, activeComposition == nil,
              review.owner == compositionOwner, nativeSelection == review.range, review.checkpoint == (try document.encodeUpdate()) else {
            throw LinkEditFailure.selectionChanged
        }
        var attrs = review.attributes
        if let destination {
            guard let accepted = RelayMarkLinkDestination.accepted(destination) else { throw LinkEditFailure.unsupportedDestination }
            attrs["href"] = accepted
        }
        if destination == nil && !review.hasLink { return }
        if destination != nil && attrs == review.attributes { return }
        let linkAttributes: [String: Any] = ["href": attrs["href"] ?? "", "target": "_blank",
            "rel": "noopener noreferrer nofollow", "class": NSNull(), "title": NSNull()]
        let original = RelayMarkDeclaredCommandInput.link(destination: destination == nil ? nil : attrs["href"])
        try original.validate()
        let change: [String: Any] = ["link": destination == nil ? NSNull() : linkAttributes]
        do {
            var candidate = text
            let source = String(text.characters)
            guard let selected = Range(review.range, in: source),
                  let lower = AttributedString.Index(selected.lowerBound, within: candidate),
                  let upper = AttributedString.Index(selected.upperBound, within: candidate) else {
                throw LinkEditFailure.selectionChanged
            }
            candidate[lower..<upper].link = destination.flatMap(URL.init(string:))
            do {
                let revisionBefore = document.revision, textBefore = textRevision
                let result = try ownedChange({ try RelayNativeRichEdit.format(document: document,
                    candidate: candidate, range: review.range, attributes: change) }, separateHistoryItem: true, update: { $0.update })
                try show(result.update, after: revisionBefore, textBefore: textBefore)
                setNativeSelection(review.range)
                pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: result.update,
                    inputIntent: .declaredCommand(original))
                retryPersistence()
            } catch { throw LinkEditFailure.incompatibleCode }
            return
        }}

    /// Structured formatting stays inside one existing heading or list paragraph;
    /// it never converts, splits or joins containers. Ordinary paragraph ranges
    /// retain their existing cross-paragraph formatting behavior.
    public var canFormatInlineSelection: Bool {
        guard isEditable, pending == nil, activeComposition == nil,               let selection = nativeSelection else { return false }
        return supportsFormattingRange(selection)
    }

    private func supportsFormattingRange(_ selection: NSRange) -> Bool {
            guard let projection = try? currentProjection() else { return false }
            return RelayNativeRichEdit.supportsFormatting(projection, range: selection)
        }

    public var canFormatInlineCodeSelection: Bool {
        guard canFormatInlineSelection, let range = nativeSelection,
              let selected = Range(range, in: String(text.characters)) else { return false }
        return !String(text.characters)[selected].contains(where: { $0 == "\n" || $0 == "\u{2028}" })
    }

    public func toggleInlineMark(_ mark: RelayMarkFormattingMark) {
        if let range = nativeSelection, toggleMarkNatively(mark, range: range) { return }
        guard canFormatInlineSelection, let range = nativeSelection,
              let stringRange = Range(range, in: String(text.characters)),
              let lower = AttributedString.Index(stringRange.lowerBound, within: text),
              let upper = AttributedString.Index(stringRange.upperBound, within: text) else { return }
        // Inline code is a single-line portable mark. Never turn paragraph
        // separators into an apparent multiline code span.
        if mark == .code && !canFormatInlineCodeSelection { return }
        let flag = mark.inlineIntent
        let enable = !text[lower..<upper].runs.allSatisfy { ($0.inlinePresentationIntent ?? []).contains(flag) }
        var candidate = text
        for run in text[lower..<upper].runs {
            var intent = run.inlinePresentationIntent ?? []
            if enable {
                if mark == .code {
                    intent.remove([.stronglyEmphasized, .emphasized, .strikethrough])
                    candidate[run.range].link = nil
                } else { intent.remove(.code) }
                intent.insert(flag)
            } else { intent.remove(flag) }
            candidate[run.range].inlinePresentationIntent = intent
        }
        editFormatting(candidate, command: .init(baseline: text, range: range, mark: mark))
    }

    /// One document command for TipTap's additional empty-attribute inline marks.
    /// The existing scratch validator, Yrs transaction and persistence journal
    /// remain the owners of the actual edit.
    public var offersInlineMarks: Bool { true }

    /// Adds `mark` unless the whole selection already has it, then removes it.
    /// At a caret it toggles the mark for the next text typed there.
    func toggleMarkNatively(_ mark: RelayMarkFormattingMark, range: NSRange) -> Bool {
        if range.length == 0 { return toggleTypingMark(mark, at: range.location) }
        guard let bounds = Range(range, in: text) else { return false }
        if mark == .code, text[bounds].characters.contains(where: { $0 == "\n" || $0 == "\u{2028}" }) { return false }
        let flag = mark.inlineIntent
        let enabled = !text[bounds].runs.allSatisfy { ($0.inlinePresentationIntent ?? []).contains(flag) }
        return formatNatively(range: range, mark: mark, enabled: enabled)
    }

    /// The marks the next text typed at `caret` takes: a stored mark change made
    /// there, else the marks of the text before it (the start of a leaf takes the text after).
    func typingMarks(at caret: Int) -> [String: Any]? {
        if let stored = storedTyping, storedTypingOffset() == caret,
           let value = try? JSONSerialization.jsonObject(with: stored.attributes) as? [String: Any] { return value }
        guard let position = (try? currentProjection())?.position(atUTF16: caret),
              let runs = try? document.textRuns(path: position.path) else { return nil }
        var offset = 0
        for run in runs {
            let end = offset + run.text.utf16.count
            if position.index > offset && position.index <= end || position.index == 0 { return run.attributes }
            offset = end
        }
        return [:]
    }

    /// Stored marks, as ProseMirror keeps them: no document change until text is typed.
    private func toggleTypingMark(_ mark: RelayMarkFormattingMark, at caret: Int) -> Bool {
        guard isEditable, pending == nil, activeComposition == nil, var marks = typingMarks(at: caret) else { return false }
        if marks[mark.rawValue] != nil { marks[mark.rawValue] = nil }
        else {
            // Code is exclusive with the other marks, as when formatting a selection.
            for other in (mark == .code ? ["bold", "italic", "strike", "link"] : ["code"]) { marks[other] = nil }
            marks[mark.rawValue] = [String: Any]()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: marks, options: [.sortedKeys]),
              (try? retainTypingContext(data, caret: caret)) != nil else { return false }
        return true
    }

    /// Adds or removes one inline mark over a selection with windowed
    /// commands, reading only the blocks the selection touches. Code is
    /// exclusive with the other marks, as in the browser. False leaves the
    /// edit to the general path.
    func formatNatively(range: NSRange, mark: RelayMarkFormattingMark, enabled: Bool) -> Bool {
        guard isEditable, pending == nil, activeComposition == nil,
              range.length > 0, (try? reading({ paper in
                  let blocks = paper.blocks(intersecting: range)
                  return !blocks.isEmpty && !paper.textRanges(in: range).isEmpty &&
                      !blocks.contains(where: { $0.intent.components.contains(where: {
                          if case .codeBlock = $0.kind { true } else { false } }) })
              })) == true else { return false }
        var marks: [(name: String, enabled: Bool)] = []
        if enabled {
            let exclusive = mark == .code ? ["bold", "italic", "strike", "link"] : ["code"]
            marks = exclusive.sorted().map { ($0, false) } + [(mark.rawValue, true)]
        } else { marks = [(mark.rawValue, false)] }
        let textBefore = textRevision
        var updates: [Data] = [], splices: [Splice] = [], complete = true
        do {
            _ = try ownedChange({ () throws -> Bool in
                for (name, on) in marks {
                    let revisionBefore = document.revision
                    guard let (change, rewrites) = try reading({ paper in
                        try RelayMarkNativeRichEditing.format(document: document, range: range, mark: name, enabled: on, paper: paper)
                            .map { ($0, rewritten($0, paper: paper)) }
                    }) else { continue }
                    updates.append(change.update)
                    // Marks change no structure, so each window re-projects in place.
                    guard let done = rewrites.flatMap({ splice($0, after: revisionBefore) }) else {
                        complete = false; continue
                    }
                    splices.append(done)
                }
                return true
            }, separateHistoryItem: true, update: { _ in Data([0, 0]) })
        } catch { return false }
        guard !updates.isEmpty, let update = try? document.mergeUpdates(updates),
              let projection = try? currentProjection() else { return !updates.isEmpty }
        text = projection.text
        // Marks keep the text's length, so the one rewritten span covering every
        // command's span is spliced once; its presentation is the last command's,
        // read again over that span.
        if complete, let first = splices.first, let lower = splices.compactMap({ $0.ranges.first?.old.location }).min(),
           let upper = splices.compactMap({ $0.ranges.first.map { NSMaxRange($0.old) } }).max(),
           let contentLower = splices.compactMap({ $0.nodes?.content.location }).min(),
           let contentUpper = splices.compactMap({ $0.nodes.map { NSMaxRange($0.content) } }).max(),
           splices.allSatisfy({ $0.ranges.count == 1 }) {
            let replaced = NSRange(location: lower, length: upper - lower)
            let content = NSRange(location: contentLower, length: contentUpper - contentLower)
            // The content span ends one past its last unit; the units it covers are the rewritten ones.
            var region = region(of: splices.count == 1 ? first.restricted ?? projection.restricted(covering: content)
                                    : projection.restricted(covering: NSRange(location: content.location, length: max(0, content.length - 1))))
            region.content = content
            textSplice = RelayTextSplice(from: textBefore, to: textRevision, ranges: [(replaced, replaced)], nodes: region)
        }
        setNativeSelection(range)
        pending = RelayMarkLocalTransaction(id: preparedLocalOperationID ?? UUID(), update: update, inputIntent: .derived)
        retryPersistence()
        return true
    }


    public func toggleOfferedMark(_ mark: RelayMarkOfferedMark) {
        guard isEditable, pending == nil,
              activeComposition == nil, canFormatInlineSelection,
              let range = nativeSelection,
              let selected = Range(range, in: String(text.characters)),
              let lower = AttributedString.Index(selected.lowerBound, within: text),
              let upper = AttributedString.Index(selected.upperBound, within: text) else { return }
        let runs = Array(text[lower..<upper].runs)
        guard !runs.isEmpty,
              runs.allSatisfy({ !(($0.inlinePresentationIntent ?? []).contains(.code)) }) else { return }
        let enable = !runs.allSatisfy { ($0[RelayMarkOfferedMarksAttribute.self] ?? []).contains(mark) }
        var candidate = text
        for run in runs {
            var marks = run[RelayMarkOfferedMarksAttribute.self] ?? []
            if enable { marks.insert(mark) } else { marks.remove(mark) }
            candidate[run.range][RelayMarkOfferedMarksAttribute.self] = marks.isEmpty ? nil : marks
        }
        do {
            let revisionBefore = document.revision, textBefore = textRevision
            let result = try ownedChange({ try RelayNativeRichEdit.format(document: document,
                candidate: candidate, range: range,
                attributes: [mark.rawValue: enable ? [:] : NSNull()]) }, separateHistoryItem: true, update: { $0.update })
            try show(result.update, after: revisionBefore, textBefore: textBefore)
            setNativeSelection(range)
            pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: result.update, inputIntent: .derived)
            retryPersistence()
        } catch { retain(candidate, reason: error.localizedDescription) }
    }

    func editFormatting(_ candidate: AttributedString, command: RelayNativeFormattingCommand) {
        guard isEditable, pending == nil, activeComposition == nil else { return }
        noteFallback("formatting")
        guard command.baseline == text else {
            retain(candidate, reason: String(localized: "The formatting selection changed before it could be saved.", bundle: .module, comment: "Shown on the paper when formatting is kept for review."))
            return
        }
        guard supportsFormattingRange(command.range) else {
            retain(candidate, reason: String(localized: "This selection contains an unsupported formatting target. Your candidate is retained.", bundle: .module, comment: "Shown on the paper when formatting is kept for review."))
            return
        }
        guard let formatting = RelayNativeRichEdit.formattingChange(
            before: text, after: candidate, range: command.range, mark: command.mark, exclusiveCode: true) else {
            edit(candidate)
            return
        }
        do {
            var attributes: [String: Any] = [formatting.mark.rawValue: formatting.enabled ? [:] : NSNull()]
            if formatting.enabled {
                if formatting.mark == .code {
                    for mark in ["bold", "italic", "strike", "link"] { attributes[mark] = NSNull() }
                } else { attributes["code"] = NSNull() }
            }
            let start = formatting.startUTF16, end = start + formatting.lengthUTF16
            do {
                let result = try ownedChange({ try RelayNativeRichEdit.format(document: document,
                    candidate: candidate, range: NSRange(location: start, length: end - start),
                    attributes: attributes) }, separateHistoryItem: true, update: { $0.update })
                text = result.text
                setNativeSelection(command.range)
                pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: result.update, inputIntent: .derived)
                retryPersistence()
                return
            }
        } catch {
            retain(candidate, reason: error.localizedDescription)
        }
    }

    /// The paper is unchanged since capture when its revision is.
    public struct StructuredPasteCapture {
        public let id: UUID
        fileprivate let owner: UUID
        fileprivate let revision: Int
        fileprivate let range: NSRange
    }
    public func captureStructuredPaste() throws -> StructuredPasteCapture {
        guard canInsertBlock, let range = nativeSelection else { throw InlineAtomEditFailure.changed }
        return StructuredPasteCapture(id: UUID(), owner: compositionOwner, revision: document.revision, range: range)
    }
    private func validateStructuredPasteCapture(_ capture: StructuredPasteCapture) throws {
        guard canInsertBlock, capture.owner == compositionOwner, nativeSelection == capture.range,
              capture.revision == document.revision else {
            throw InlineAtomEditFailure.changed
        }
    }
    /// Captured clipboard material is recovery input, never a document grant.
    public struct StructuredPaste: Identifiable {
        public let id: UUID
        let originalHTML: String
        fileprivate var originalHTMLItems: [String]? = nil
        fileprivate var orderedHTML: [String] { originalHTMLItems ?? [originalHTML] }
        fileprivate let owner: UUID
        fileprivate let revision: Int
        fileprivate let range: NSRange
        fileprivate enum Material {
            case document(ast: Data, openStart: Int, openEnd: Int)
            case clipboard(slice: Data)
            case clipboards(slices: [Data])
            var stagingMaterials: [Data] {
                switch self {
                case .document(let ast, _, _): return [ast]
                case .clipboard(let slice): return [slice]
                case .clipboards(let slices): return slices
                }
            }
        }
        fileprivate let material: Material
    }

    func prepareStructuredPaste(html: String, openStart: Int, openEnd: Int) throws -> StructuredPaste {
        try prepareStructuredPaste(html: html, capture: captureStructuredPaste(), openStart: openStart, openEnd: openEnd)
    }
    func prepareStructuredPaste(html: String, capture: StructuredPasteCapture, openStart: Int, openEnd: Int) throws -> StructuredPaste {
        try validateStructuredPasteCapture(capture)
        let operation = capture.id
        let imported = try RelayMarkContentEditCodec.importDocumentHTML(html, namespace: operation.uuidString.lowercased())
        guard let result = try JSONSerialization.jsonObject(with: imported) as? [String: Any],
              let ast = result["document"] as? [String: Any] else { throw InlineAtomEditFailure.changed }
        return StructuredPaste(id: operation, originalHTML: html, owner: compositionOwner,
            revision: capture.revision, range: capture.range,
            material: .document(ast: try JSONSerialization.data(withJSONObject: ast, options: [.sortedKeys]),
                                openStart: openStart, openEnd: openEnd))
    }

    /// OS clipboard geometry comes from the shared maintained HTML Slice parser.
    /// Explicit authored-document/recovery imports keep their separate entrypoint.
    func prepareStructuredClipboard(html: String, capture: StructuredPasteCapture) throws -> StructuredPaste {
        try validateStructuredPasteCapture(capture)
        let imported = try RelayMarkContentEditCodec.importClipboardHTML(html, namespace: capture.id.uuidString.lowercased())
        guard let result = try JSONSerialization.jsonObject(with: imported) as? [String: Any],
              Set(result.keys) == Set(["slice", "normalizations"]),
              let slice = result["slice"] as? [String: Any],
              Set(slice.keys) == Set(["content", "openStart", "openEnd"]),
              slice["content"] is [[String: Any]], result["normalizations"] is [[String: Any]] else {
            throw InlineAtomEditFailure.changed
        }
        return StructuredPaste(id: capture.id, originalHTML: html, owner: compositionOwner,
            revision: capture.revision, range: capture.range,
            material: .clipboard(slice: imported))
    }

    public func prepareStructuredClipboards(html: [String], capture: StructuredPasteCapture) throws -> StructuredPaste {
        guard !html.isEmpty, html.count <= 4096 else { throw InlineAtomEditFailure.changed }
        if html.count == 1 { return try prepareStructuredClipboard(html: html[0], capture: capture) }
        var slices: [Data] = []
        for (index, value) in html.enumerated() {
            try validateStructuredPasteCapture(capture)
            // Separate parser namespaces, one actual paste operation/owner.
            let bytes = try RelayMarkContentEditCodec.importClipboardHTML(value,
                namespace: capture.id.uuidString.lowercased() + ":" + String(index))
            guard let result = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  Set(result.keys) == Set(["slice", "normalizations"]), result["slice"] is [String: Any],
                  result["normalizations"] is [[String: Any]] else { throw InlineAtomEditFailure.changed }
            slices.append(bytes)
        }
        return StructuredPaste(id: capture.id, originalHTML: html[0], originalHTMLItems: html,
            owner: compositionOwner, revision: capture.revision,
            range: capture.range, material: .clipboards(slices: slices))
    }

    private func validateStructuredPaste(_ edit: StructuredPaste) throws {
        guard canInsertBlock, edit.owner == compositionOwner, nativeSelection == edit.range,
              edit.revision == document.revision else {
            throw InlineAtomEditFailure.changed
        }
    }

    /// Inserts parsed clipboard material as one ordinary edit, after the host
    /// authorizes any media it references.
    public func insertStructuredPaste(_ edit: StructuredPaste, authorize: @MainActor (Data) async throws -> Void) async throws {
        try validateStructuredPaste(edit)
        for material in edit.material.stagingMaterials {
            try await authorize(material)
            try Task.checkCancellation()
            try validateStructuredPaste(edit)
        }
        // Clipboard material is fitted on a window of the paper; an authored
        // document import reads the whole paper.
        let revisionBefore = document.revision, textBefore = textRevision
        let (change, rewrites) = try reading { paper in
            let change = try ownedChange({
                switch edit.material {
                case .document(let ast, let start, let end):
                    return try RelayMarkNativeRichEditing.insertDocumentSlice(document: document,
                        range: edit.range, authoredAST: ast, openStart: start, openEnd: end,
                        expectedSnapshot: document.snapshot())
                case .clipboard(let slice):
                    return try RelayMarkNativeRichEditing.insertDocumentSlice(document: document,
                        range: edit.range, clipboardSlice: slice, paper: paper)
                case .clipboards(let slices):
                    return try RelayMarkNativeRichEditing.insertDocumentSlice(document: document,
                        range: edit.range, clipboardSlices: slices, paper: paper)
                }
            }, separateHistoryItem: true, operationID: edit.id, update: { $0.update })
            return (change, rewritten(change, paper: paper))
        }
        let splice = rewrites.flatMap { splice($0, after: revisionBefore) }
        let projection = try currentProjection()
        text = projection.text
        if let splice { textSplice = RelayTextSplice(from: textBefore, to: textRevision, ranges: splice.ranges, nodes: splice.nodes) }
        let caret = change.caret.flatMap { caret in projection.blockRange(path: caret.blockPath).map { $0.location + caret.offset } }
        setNativeSelection(NSRange(location: min(caret ?? edit.range.location, text.utf16.count), length: 0))
        pending = RelayMarkLocalTransaction(id: try preparedOperationID(), update: change.update)
        retryPersistence()
    }

    func acceptsNativePastePayload(_ value: String) -> Bool {
        !isInvalidated && canEdit() && value.utf16.count <= 131_072 &&
            !value.unicodeScalars.contains { $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}" }
    }

    func acceptsNativeReplacement(baseline: String, range: NSRange, replacement: String) -> Bool {
            if canTypeNatively(range: range, replacement: replacement) { return true }
            if replacement == "\n", activeComposition != nil { return false }
            if activeComposition == nil, baseline == String(text.characters),
               RelayNativeRichEdit.boundaryKey(document: document, range: range, replacement: replacement,
                                                     caret: nativeSelection) != nil { return isEditable }
            return RelayNativeRichEdit.supportsNativeReplacement(
                document: document, baseline: baseline, range: range, replacement: replacement)
        }

    func preserveRejectedPaste(_ candidate: AttributedString, id: UUID) {
        guard !isInvalidated else { return }
        retain(candidate, reason: String(localized: "This pasted input could not be inserted.", bundle: .module, comment: "Shown on the paper when a paste is kept for review."))
    }
}
