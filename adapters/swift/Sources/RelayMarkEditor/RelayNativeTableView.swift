import Foundation
import RelayMarkEditorCore
import RelayMarkProseProjection
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A single framework text view renders every cell. The surrounding paper owns
/// the viewport; this view contributes only the native table's fitted size.
@MainActor
final class RelayTableGridView: PlatformTableView {
    unowned let table: RelayTableAttachment
    let textView = RelayNativeTableTextView()
    private(set) var projection = RelayNativeTableProjection()
    private var updating = false
    private var proposedWidth: CGFloat = 0
    private var storageObserver: NSObjectProtocol?
    private(set) var nativeEditCount = 0
    private(set) var nativeEdit: (paper: NSRange, text: String)?
    var editing: (any RelayTableEditing)? { table.editing }
    var nativeText: NSAttributedString { textView.textStorageValue }
    var nativeSelection: NSRange { textView.nativeSelection }
    var hasMarkedInput: Bool { textView.hasMarkedInput }

    init(table: RelayTableAttachment) {
        self.table = table
        super.init(frame: .zero)
        textView.owner = self
        textView.delegate = self
        addSubview(textView)
        storageObserver = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification,
            object: textView.textStorageValue, queue: nil) { [weak self] notification in
            guard let storage = notification.object as? NSTextStorage else { return }
            let charactersChanged = storage.editedMask.contains(.editedCharacters)
            let range = storage.editedRange, delta = storage.changeInLength
            let replacement = NSMaxRange(range) <= storage.length
                ? (storage.string as NSString).substring(with: range) : nil
            MainActor.assumeIsolated {
                guard let self, !self.updating else { return }
                if charactersChanged {
                    self.nativeEditCount += 1
                    let old = NSRange(location: range.location, length: range.length - delta)
                    if self.nativeEditCount == 1, old.length >= 0, let replacement,
                       let paper = self.projection.editablePaperRange(forNative: old) {
                        self.nativeEdit = (paper, replacement)
                    } else { self.nativeEdit = nil }
                }
                self.projection.noteNativeEdit(range: range, delta: delta)
            }
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit {
        if let storageObserver { NotificationCenter.default.removeObserver(storageObserver) }
    }

    func unmarkText() { textView.unmarkText() }
    func clearNativeEdit() { nativeEditCount = 0; nativeEdit = nil }
    func updateStart(_ start: Int) { projection.updateStart(start) }

    func refreshAvailability() {
        let wasUpdating = updating
        updating = true
        textView.isEditable = editing?.isEditable == true && projection.supportsEditing
        updating = wasUpdating
    }

    func refresh() {
        guard !updating else { return }
        refreshAvailability()
        guard !hasMarkedInput else { return }
        clearNativeEdit()
        updating = true
        defer { updating = false }
        let storage = textView.textStorageValue
        storage.beginEditing()
        projection.update(table, storage: storage)
        storage.endEditing()
        textView.isEditable = editing?.isEditable == true && projection.supportsEditing
        if proposedWidth > 0 { layout(width: proposedWidth) }
    }

    func showSelection(paper: NSRange) {
        guard !hasMarkedInput, let native = projection.nativeRange(forPaper: paper),
              NSMaxRange(native) <= nativeText.length, native != nativeSelection else { return }
        updating = true
        textView.nativeSelection = native
        updating = false
    }

    func cellsReplaced(_ old: Range<Int>, count: Int) { refresh() }

    @discardableResult func layout(width: CGFloat) -> CGSize {
        proposedWidth = width
        let size = textView.nativeSize(at: width)
        if frame.size != size { frame.size = size }
        if textView.frame != bounds { textView.frame = bounds }
        return size
    }

    fileprivate func shouldChange(_ range: NSRange, replacement: String) -> Bool {
        guard !updating, projection.supportsEditing else { return false }
        return editing?.shouldChange(range: range, replacement: replacement) ?? false
    }
    fileprivate func changed() { if !updating { editing?.didChange() } }
    fileprivate func selected() { if !updating { editing?.selectionDidChange() } }
}

#if os(macOS)
extension RelayTableGridView: NSTextViewDelegate {
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString else { return false }
        return shouldChange(affectedCharRange, replacement: replacementString)
    }
    func textDidChange(_ notification: Notification) { changed() }
    func textViewDidChangeSelection(_ notification: Notification) { selected() }
    func textDidEndEditing(_ notification: Notification) { try? editing?.finishComposition() }
}

@MainActor
final class RelayNativeTableTextView: NSTextView {
    weak var owner: RelayTableGridView?
    private let collaborationUndo = CollaborationUndoManager()
    private var compositionCompletion: Task<Void, Never>?
    var textStorageValue: NSTextStorage { textStorage! }
    var nativeSelection: NSRange {
        get { selectedRange() }
        set { setSelectedRange(newValue) }
    }
    var hasMarkedInput: Bool { hasMarkedText() }

    init() {
        let storage = NSTextStorage(), manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        textContainerInset = .zero
        isRichText = true; isSelectable = true; allowsUndo = true
        isHorizontallyResizable = false; isVerticallyResizable = false
        drawsBackground = false
        collaborationUndo.undoAction = { [weak self] in self?.owner?.editing?.undo() }
        collaborationUndo.redoAction = { [weak self] in self?.owner?.editing?.redo() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var undoManager: UndoManager? { collaborationUndo }
    @objc func undo(_ sender: Any?) { collaborationUndo.undo() }
    @objc func redo(_ sender: Any?) { collaborationUndo.redo() }

    func nativeSize(at width: CGFloat) -> CGSize {
        guard let container = textContainer, let manager = layoutManager else { return .zero }
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        var used = manager.usedRect(for: container)
        if manager.extraLineFragmentTextContainer === container { used = used.union(manager.extraLineFragmentRect) }
        return CGSize(width: width, height: used.maxY + textContainerInset.height * 2)
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        guard let window, let document = enclosingScrollView?.documentView else { return }
        layoutManager?.ensureLayout(forCharacterRange: range)
        let screen = firstRect(forCharacterRange: range, actualRange: nil)
        document.scrollToVisible(document.convert(window.convertFromScreen(screen), from: nil))
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard isEditable, let editing = owner?.editing else { return }
        compositionCompletion?.cancel()
        if !hasMarkedText() { editing.beginComposition() }
        let literal = (string as? NSAttributedString)?.string ?? (string as? String)
        let effective = replacementRange.location == NSNotFound ? (hasMarkedText() ? markedRange() : self.selectedRange()) : replacementRange
        guard editing.declareMarkedInput(literal, replacement: effective, selection: selectedRange,
            platform: .appKit, suppliedReplacement: replacementRange, phase: .marked) else { return }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard isEditable else { return }
        if let editing = owner?.editing, editing.isComposing {
            let literal = (insertString as? NSAttributedString)?.string ?? (insertString as? String)
            let effective = replacementRange.location == NSNotFound ? (hasMarkedText() ? markedRange() : selectedRange()) : replacementRange
            guard editing.declareMarkedInput(literal, replacement: effective, selection: selectedRange(),
                platform: .appKit, suppliedReplacement: replacementRange, phase: .final) else { return }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }
    override func unmarkText() {
        let wasMarked = hasMarkedText()
        super.unmarkText()
        if wasMarked {
            compositionCompletion?.cancel()
            compositionCompletion = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, !self.hasMarkedText() else { return }
                self.owner?.editing?.endComposition()
            }
        }
    }
    override func underline(_ sender: Any?) { _ = owner?.editing?.performCommand("editor.mark.underline") }
    override func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager,
              let font = typingAttributes[.font] as? NSFont else { return }
        let before = manager.traits(of: font), after = manager.traits(of: manager.convert(font))
        if before.contains(.boldFontMask) != after.contains(.boldFontMask) { _ = owner?.editing?.toggleMark(.bold) }
        else if before.contains(.italicFontMask) != after.contains(.italicFontMask) { _ = owner?.editing?.toggleMark(.italic) }
        else { RelayPaperRefusal.feedback() }
    }
    override func orderFrontTablePanel(_ sender: Any?) { RelayPaperRefusal.feedback() }
}
#else
extension RelayTableGridView: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        shouldChange(range, replacement: text)
    }
    func textViewDidChange(_ textView: UITextView) { changed() }
    func textViewDidChangeSelection(_ textView: UITextView) { selected() }
    func textViewDidEndEditing(_ textView: UITextView) { try? editing?.finishComposition() }
}

@MainActor
final class RelayNativeTableTextView: UITextView {
    weak var owner: RelayTableGridView?
    private let collaborationUndo = CollaborationUndoManager()
    private var compositionCompletion: Task<Void, Never>?
    var textStorageValue: NSTextStorage { textStorage }
    var nativeSelection: NSRange {
        get { selectedRange }
        set { selectedRange = newValue }
    }
    var hasMarkedInput: Bool { markedTextRange != nil }

    init() {
        let storage = NSTextStorage(), manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        textContainerInset = .zero
        isScrollEnabled = false; isSelectable = true
        backgroundColor = .clear
        collaborationUndo.undoAction = { [weak self] in self?.owner?.editing?.undo() }
        collaborationUndo.redoAction = { [weak self] in self?.owner?.editing?.redo() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var undoManager: UndoManager? { collaborationUndo }

    func nativeSize(at width: CGFloat) -> CGSize {
        let fitted = sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: fitted.height)
    }

    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView, scroll.isScrollEnabled {
                scroll.scrollRectToVisible(convert(rect, to: scroll), animated: animated)
                return
            }
            ancestor = view.superview
        }
    }

    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        guard isEditable, let editing = owner?.editing else { return }
        compositionCompletion?.cancel()
        if markedTextRange == nil { editing.beginComposition() }
        guard let target = markedTextRange ?? selectedTextRange else { return }
        let range = NSRange(location: offset(from: beginningOfDocument, to: target.start), length: offset(from: target.start, to: target.end))
        guard editing.declareMarkedInput(markedText, replacement: range, selection: selectedRange,
            platform: .uiKit, suppliedReplacement: nil, phase: .marked) else { return }
        super.setMarkedText(markedText, selectedRange: selectedRange)
    }
    override func insertText(_ text: String) {
        guard isEditable else { return }
        if let editing = owner?.editing, editing.isComposing {
            guard let target = markedTextRange ?? selectedTextRange else { return }
            let range = NSRange(location: offset(from: beginningOfDocument, to: target.start), length: offset(from: target.start, to: target.end))
            guard editing.declareMarkedInput(text, replacement: range, selection: selectedRange,
                platform: .uiKit, suppliedReplacement: nil, phase: .final) else { return }
        }
        super.insertText(text)
    }
    override func unmarkText() {
        let wasMarked = markedTextRange != nil
        super.unmarkText()
        if wasMarked {
            compositionCompletion?.cancel()
            compositionCompletion = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, self.markedTextRange == nil else { return }
                self.owner?.editing?.endComposition()
            }
        }
    }
    override func toggleBoldface(_ sender: Any?) { _ = owner?.editing?.toggleMark(.bold) }
    override func toggleItalics(_ sender: Any?) { _ = owner?.editing?.toggleMark(.italic) }
    override func toggleUnderline(_ sender: Any?) { _ = owner?.editing?.performCommand("editor.mark.underline") }
}
#endif
