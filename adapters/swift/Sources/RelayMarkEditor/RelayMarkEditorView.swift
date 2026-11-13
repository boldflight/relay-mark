import Accessibility
import Foundation
import RelayMarkCollaboration
import RelayMarkEditorCore
import UniformTypeIdentifiers
import RelayMarkProseProjection
import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
#endif

/// The images a host accepts from paste and drop, as pasteboard types.
struct RelayNativeImageRepresentation {
    var accepted: Set<String> = []
    var maximumBytes = 0
    var acceptedIdentifiers: [String] {
        accepted.sorted().flatMap {
            UTType.types(tag: $0, tagClass: .mimeType, conformingTo: .image).map(\.identifier)
        }
    }
    static func isImage(_ identifier: String) -> Bool { UTType(identifier)?.conforms(to: .image) == true }
    func mime(_ identifier: String) -> String? {
        guard let type = UTType(identifier), type.conforms(to: .image), let mime = type.preferredMIMEType,
              accepted.contains(mime)
        else { return nil }
        return mime
    }
    static func filename(_ suggested: String?, identifier: String) -> String {
        if let suggested, !suggested.isEmpty { return suggested }
        return "Clipboard image." + (UTType(identifier)?.preferredFilenameExtension ?? "image")
    }
}

final class CollaborationUndoManager: UndoManager, @unchecked Sendable {
    override init() { super.init(); disableUndoRegistration() }
    @MainActor var undoAction: (() -> Void)?
    @MainActor var redoAction: (() -> Void)?
    override var canUndo: Bool { true }
    override var canRedo: Bool { true }
    override func undo() { MainActor.assumeIsolated { undoAction?() } }
    override func redo() { MainActor.assumeIsolated { redoAction?() } }
}

#if os(macOS)
@MainActor
/// The paper's text view: TextKit 2 over one editor session.
public struct RelayMarkEditorView: NSViewRepresentable {
    typealias Session = RelayMarkEditorSession
    var session: Session
    var accessibilityLabel: String
    var services = RelayMarkEditorServices()

    public init(session: RelayMarkEditorSession, accessibilityLabel: String, services: RelayMarkEditorServices = .init()) {
        self.session = session; self.accessibilityLabel = accessibilityLabel; self.services = services
    }

    public func makeCoordinator() -> Coordinator { Coordinator(text: TextCoordinator(session: session)) }
    /// Owns the view's text system for SwiftUI; its members are internal.
    @MainActor public final class Coordinator {
        let text: TextCoordinator
        init(text: TextCoordinator) { self.text = text }
    }
    public func makeNSView(context: Context) -> CollaborationTextContainer {
        context.coordinator.text.services = services
        let container = CollaborationTextContainer()
        container.install(context.coordinator.text.makeTextView(accessibilityLabel: accessibilityLabel))
        container.configure(services)
        return container
    }
    public func updateNSView(_ container: CollaborationTextContainer, context: Context) {
        _ = services.imageStore?.revision
        context.coordinator.text.services = services
        if context.coordinator.text.session !== session {
            let previous = container.textView
            let wasFocused = previous.map { $0.window?.firstResponder === $0 } ?? false
            if let previous { context.coordinator.text.retire(previous) }
            context.coordinator.text.session = session
            let replacement = context.coordinator.text.makeTextView(accessibilityLabel: accessibilityLabel)
            container.install(replacement)
            if wasFocused { container.window?.makeFirstResponder(replacement) }
        } else if let view = container.textView { context.coordinator.text.update(view) }
        container.configure(services)
    }
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: CollaborationTextContainer, context: Context) -> CGSize? {
        proposal.width.flatMap { nsView.contentSize(at: $0) }
    }
    public static func dismantleNSView(_ container: CollaborationTextContainer, coordinator: Coordinator) {
        if let view = container.textView { coordinator.text.retire(view) }
    }
    @MainActor final class TextCoordinator: NSObject, NSTextViewDelegate {
        /// The host's services; tests may set the closures below directly.
        var services = RelayMarkEditorServices() {
            didSet {
                mediaImages = services.imageStore
                onActivatePaperButton = services.paperControls.map { controls in { controls.activatePaperButton(id: $0) } }
                onActivateFragmentLink = services.links.map { links in { links.activateFragmentLink($0) } }
                onImageInputFailure = services.inputRefused
                onBeginImageInput = services.images.map { images in { images.beginImageInput(at: $0, filename: $1, contentType: $2) } }
                onBeginImageBatchInputs = services.images.map { images in { images.beginImageInputs(at: $0, files: $1) } }
                onBeginStructuredPaste = services.paste.map { paste in { paste.beginStructuredPaste(at: $0, itemCount: $1, plainText: $2) } }
            }
        }
        var mediaImages: RelayMarkImageStore? {
            get { editor.mediaImages }
            set { editor.mediaImages = newValue }
        }
        var onActivatePaperButton: ((String) -> Void)?
        var onActivateFragmentLink: ((String) -> Void)?
        var onImageInputFailure: ((String) -> Void)?
        var onBeginImageBatchInputs: ((NSRange, [RelayMarkImageFile]) -> [RelayMarkImageIntake]?)?
        var onBeginImageInput: ((NSRange, String, String) -> RelayMarkImageIntake?)?
        var onBeginStructuredPaste: ((NSRange, Int, String?) -> RelayMarkPasteIntake?)?
        let editor: RelayPaperEditor<Session>
        var session: Session {
            get { editor.session }
            set { editor.session = newValue }
        }
        var composition: Session.Composition? {
            get { editor.composition }
            set { editor.composition = newValue }
        }
        /// A keystroke inside one text leaf, applied without reading the whole paper.
        var pendingTyping: (range: NSRange, text: String)? { editor.pendingTyping.map { ($0.paper, $0.text) } }
        init(session: Session) { editor = RelayPaperEditor(session: session) }
        func makeTextView(accessibilityLabel: String) -> CollaborationTextView {
            let view = CollaborationTextView.textKit2()
            // Enable AppKit responder routing; the custom manager keeps only canonical history.
            view.allowsUndo = true
            view.editingSession = session
            apply(services, to: view)
            editor.attach(view)
            view.onImageInputFailure = { [weak self, weak view] message in
                guard let self, let view, view.editingSession === session, !session.isInvalidated else { return }
                onImageInputFailure?(message)
            }
            view.onBeginImageInput = { [weak self, weak view] range, filename, contentType in
                guard let self, let view, !view.retired, view.editingSession === session,
                      !session.isInvalidated, session.isEditable else { return nil }
                return onBeginImageInput?(view.paper.tables.paper(range), filename, contentType)
            }
            view.onBeginImageBatchInputs = { [weak self, weak view] range, files in
                guard let self, let view, !view.retired, view.editingSession === session,
                      !session.isInvalidated, session.isEditable else { return nil }
                return onBeginImageBatchInputs?(view.paper.tables.paper(range), files)
            }
            view.onBeginStructuredPaste = { [weak self, weak view] range, itemCount, plainText in
                guard let self, let view, !view.retired, view.editingSession === session,
                      !session.isInvalidated, session.isEditable else { return nil }
                return onBeginStructuredPaste?(view.paper.tables.paper(range), itemCount, plainText)
            }
            view.delegate = self
            view.onPaperButton = { [weak self, weak view] offset in
                guard let self, let view, view.editingSession === session, !session.isInvalidated,
                      let activate = onActivatePaperButton else { return false }
                let paper = view.paper.tables.paper(offset)
                guard let atom = session.nativeBlockAtoms.first(where: { $0.control == .button && NSLocationInRange(paper, $0.range) }) else { return false }
                activate(atom.id)
                return true
            }
            view.onCompositionStart = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                composition = try? session.beginComposition()
            }
            view.onDeclaredMarkedInput = { [weak self, weak view] literal, replacement, selection, supplied, final in
                guard let self, let view, !view.retired, view.editingSession === session,
                      let token = self.composition else { return false }
                let tables = view.paper.tables
                return session.declareMarkedInput(literal, replacement: tables.paper(replacement), selection: selection,
                    platform: .appKit, suppliedReplacement: supplied.map { $0.location == NSNotFound ? $0 : tables.paper($0) },
                    phase: final ? .final : .marked, from: token)
            }
            view.onCompositionEnd = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                endComposition(view)
            }
            view.registerForDraggedTypes(Array(Set(view.registeredDraggedTypes + [.fileURL] +
                view.imagePolicy.acceptedIdentifiers.map { NSPasteboard.PasteboardType($0) })))
            view.isRichText = true; view.drawsBackground = false
            view.isVerticallyResizable = true; view.isHorizontallyResizable = false
            view.minSize = .zero
            view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            view.autoresizingMask = [.width]
            view.textContainer?.widthTracksTextView = true
            view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            // Native symmetric insets; no origin override or synthetic gutter.
            view.textContainerInset = NSSize(width: (RelayPaperMargins.leading + RelayPaperMargins.trailing) / 2, height: 20)
            view.setAccessibilityLabel(accessibilityLabel)
            view.onSessionEdit = { [weak self, weak view] in
                guard let self, let view, !view.retired else { return }
                self.update(view)
            }
            session.onFocusRequest = { [weak self, weak view] in
                guard let self, let view else { return }
                takeFocusIfRequested(view)
            }
            view.onMovedToWindow = { [weak self, weak view] in
                guard let self, let view else { return }
                takeFocusIfRequested(view)
            }
            view.onTaskCheckbox = { [weak self, weak view] offset in
                guard let self, let view, view.editingSession === session else { return false }
                // A tap mid-composition commits the composed title first, so the
                // draft finishes with the words typed (Douglas, M10).
                if view.hasMarkedInput { do { try finishComposition(view) } catch { return false } }
                guard session.toggleTaskItem(atUTF16: view.paper.tables.paper(offset)) else { return false }
                self.update(view)
                return true
            }
            view.collaborationUndo.undoAction = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                session.undo(); self.update(view)
            }
            view.collaborationUndo.redoAction = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                session.redo(); self.update(view)
            }
            view.finalizerRegistration = session.registerNativeCompositionFinalizer({ [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                try finishComposition(view)
            }, refresh: { [weak self, weak view] in
                guard let self, let view, !view.retired, view.editingSession === session else { return }
                self.update(view)
            })
            update(view)
            return view
        }
        func finishComposition(_ view: CollaborationTextView) throws { try editor.finishComposition(view) }
        func retire(_ view: CollaborationTextView) {
            guard !view.retired else { return }
            editor.updating = true
            defer { editor.updating = false }
            if view.editingSession === session, session.isEditable { try? finishComposition(view) }
            editor.retireTables(view)
            if let composition, view.editingSession === session { session.cancelComposition(composition) }
            composition = nil
            if let registration = view.finalizerRegistration { view.editingSession?.unregisterNativeCompositionFinalizer(registration) }
            view.finalizerRegistration = nil
            view.retireInput()
            view.delegate = nil
            view.unmarkText()
            view.isEditable = false
            if view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
            view.textStorage?.setAttributedString(NSAttributedString(string: ""))
            view.paper.tables = RelayTableSpans(); view.paper.tableAttachments = [:]
            view.setSelectedRange(NSRange(location: 0, length: 0))
            view.paper.remoteSelections = []
            view.unlinkPreviousTextElement()
            if view.editingSession === session { session.onFocusRequest = nil }
            view.editingSession = nil
        }
        /// Section links lead the context menu; the paper's Format commands follow the system's items.
        func textView(_ textView: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            guard let view = textView as? CollaborationTextView, !view.retired else { return menu }
            let entries = view.sectionMenuEntries(link: services.sectionLink)
            if !entries.isEmpty {
                menu.insertItem(.separator(), at: 0)
                for entry in entries.reversed() { menu.insertItem(RelayMenuAction.item(entry.title, entry.run), at: 0) }
            }
            if view.editingSession === session, session.isEditable {
                menu.addItem(.separator())
                menu.addItem(RelayMarkEditorCommandMenus.format(session: session) { [weak view] in view?.onSessionEdit?() })
            }
            return menu
        }
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let href = (link as? URL)?.absoluteString ?? (link as? String), href.hasPrefix("#"),
                  let activate = onActivateFragmentLink,
                  let view = textView as? CollaborationTextView, !view.retired,
                  view.editingSession === session, !session.isInvalidated else { return false }
            activate(href)
            update(view)
            view.scrollRangeToVisible(view.viewSelection)
            return true
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !editor.updating, let view = textView as? CollaborationTextView, !view.retired,
                view.editingSession == nil || view.editingSession === session else { return false }
            // A formatting-only callback (no replacement string) keeps the pending keystroke.
            guard let replacementString else {
                return session.isEditable && NSMaxRange(affectedCharRange) <= view.viewLength
            }
            return editor.shouldChange(view, range: affectedCharRange, replacement: replacementString, pasting: false)
        }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? CollaborationTextView else { return }
            editor.didChange(view)
        }
        func endComposition(_ view: CollaborationTextView) {
            guard !editor.updating, !view.retired, composition != nil, !view.hasMarkedText(),
                view.editingSession == nil || view.editingSession === session else { return }
            textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        }
        /// Writing Tools rewrites prose; structured table attachments are excluded.
        func textView(_ textView: NSTextView, writingToolsIgnoredRangesInEnclosingRange enclosingRange: NSRange) -> [NSValue] {
            guard let view = textView as? CollaborationTextView else { return [] }
            return view.paper.tables.spans.filter { NSLocationInRange($0.view, enclosingRange) }
                .map { NSValue(range: NSRange(location: $0.view, length: 1)) }
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? CollaborationTextView else { return }
            editor.selectionDidChange(view)
        }
        func update(_ view: CollaborationTextView) {
            apply(services, to: view)
            editor.update(view)
        }
        /// The host asked for focus in the paper: the view takes it, with the
        /// session's selection, once it is in a window.
        func takeFocusIfRequested(_ view: CollaborationTextView) {
            guard session.focusRequest != nil, !view.retired, view.editingSession === session, let window = view.window else { return }
            session.focusRequest = nil
            update(view)
            window.makeFirstResponder(view)
            view.scrollRangeToVisible(view.viewSelection)
        }
        private func apply(_ services: RelayMarkEditorServices, to view: CollaborationTextView) {
            view.editorLayout = services.layout
            view.imagePolicy = .init(accepted: services.images?.acceptedImageTypes ?? [],
                                     maximumBytes: services.images?.maximumImageBytes ?? 0)
            view.collaboratorColor = services.collaboratorColor
            view.selectionActions = services.selectionActions
            view.previousTextElement = services.previousTextElement
            view.linkPreviousTextElement()
        }
    }
}

/// Keeps the native input client stable while the host chooses its scroll owner.
@MainActor public final class CollaborationTextContainer: NSView {
    private(set) var textView: CollaborationTextView?
    private(set) var scrollView: NSScrollView?
    private var sizing = RelayEditorContentLayout()
    override public var isFlipped: Bool { true }

    func install(_ view: CollaborationTextView) {
        textView?.onContentLayoutChange = nil
        textView?.removeFromSuperview()
        textView = view
        view.onContentLayoutChange = { [weak self] in self?.scheduleContentMeasurement() }
        configureLayout()
    }
    func configure(_ services: RelayMarkEditorServices) {
        guard let view = textView else { return }
        view.editorLayout = services.layout
        configureLayout()
        scrollView?.contentInsets.bottom = services.bottomContentInset ?? 0
        sizing.viewportDidChange(layout: services.layout, revision: services.contentViewportRevision) { [weak self] in
            guard let self else { return }
            layoutSubtreeIfNeeded()
            guard let view = textView, !view.retired, view.editorLayout == .content,
                  view.window?.firstResponder === view else { return }
            view.scrollRangeToVisible(view.viewSelection)
        }
        scheduleContentMeasurement()
    }
    private func configureLayout() {
        guard let view = textView else { return }
        if view.editorLayout == .viewport {
            if scrollView == nil {
                view.removeFromSuperview()
                let scroll = NSScrollView()
                scroll.hasVerticalScroller = true; scroll.drawsBackground = false
                scroll.automaticallyAdjustsContentInsets = false
                scrollView = scroll; addSubview(scroll)
            }
            if scrollView?.documentView !== view { scrollView?.documentView = view }
        } else {
            if let scrollView { scrollView.documentView = nil; scrollView.removeFromSuperview(); self.scrollView = nil }
            if view.superview !== self { addSubview(view) }
        }
        needsLayout = true
    }
    override public func layout() {
        super.layout()
        if let scrollView { scrollView.frame = bounds }
        else {
            textView?.frame = bounds; scheduleContentMeasurement()
        }
    }
    func contentSize(at width: CGFloat) -> CGSize? {
        guard let view = textView, view.editorLayout == .content, width.isFinite, width > 0 else { return nil }
        // SwiftUI may probe a width it never assigns. NSTextView's native fitting
        // mutates its frame, so restore the live layout after measuring a proposal.
        let originalFrame = view.frame
        defer {
            let changedWidth = view.frame.width != originalFrame.width
            if view.frame != originalFrame { view.frame = originalFrame }
            if changedWidth, originalFrame.width > 0,
               let manager = view.textLayoutManager, let content = manager.textContentManager {
                // Restore preceding native fragment positions as well as width.
                // A target-only reveal can otherwise observe estimated positions
                // left by the rejected proposal in this full-height editor.
                manager.ensureLayout(for: content.documentRange)
            }
        }
        return CGSize(width: width, height: view.contentHeight(at: width))
    }
    override public var intrinsicContentSize: NSSize {
        contentSize(at: bounds.width).map { NSSize(width: NSView.noIntrinsicMetric, height: $0.height) } ?? super.intrinsicContentSize
    }
    private func scheduleContentMeasurement() {
        guard textView?.editorLayout == .content else { return }
        sizing.schedule { [weak self] in
            guard let self, let size = contentSize(at: bounds.width) else { return nil }
            return size.height
        } changed: { [weak self] in
            self?.invalidateIntrinsicContentSize()
        }
    }
}

/// A menu item that runs a closure.
@MainActor final class RelayMenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func perform(_ sender: Any?) { run() }
    static func item(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let action = RelayMenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(perform(_:)), keyEquivalent: "")
        item.target = action; item.representedObject = action
        return item
    }
}

@MainActor
final class CollaborationTextView: NSTextView, RelayPaperTextView, NSTextContentStorageDelegate, AXCustomContentProvider {
    var editorLayout: RelayMarkEditorLayout = .viewport
    var onContentLayoutChange: (() -> Void)?
    override func scrollRangeToVisible(_ range: NSRange) {
        guard editorLayout == .content else { return super.scrollRangeToVisible(range) }
        guard let document = enclosingScrollView?.documentView,
              let ranges = RelayTextKitRanges(textLayoutManager), let nativeRange = ranges.textRange(range) else { return }
        // An explicit reveal must lay out its target after native width changes;
        // the host-owned scroll bypasses NSTextView's usual reveal/layout work.
        ranges.manager.ensureLayout(for: nativeRange)
        // TextKit supplies the selection segment, including an empty terminal
        // caret. Converting its container coordinates is the only adjustment.
        ranges.manager.enumerateTextSegments(in: nativeRange, type: .selection, options: []) { _, frame, _, _ in
            document.scrollToVisible(convert(frame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y), to: document))
            return false
        }
    }
    func contentHeight(at width: CGFloat) -> CGFloat {
        if frame.width != width { setFrameSize(NSSize(width: width, height: frame.height)) }
        guard let manager = textLayoutManager, let content = manager.textContentManager else { return 0 }
        // The single host scroll needs the document height. Ask TextKit at this
        // sizing boundary; never infer a final line or lay out while drawing.
        manager.ensureLayout(for: content.documentRange)
        return manager.usageBoundsForTextContainer.height + 2 * textContainerInset.height
    }
    /// The host's image capability and collaborator colors, from its services.
    var imagePolicy = RelayNativeImageRepresentation()
    var collaboratorColor: (String) -> Color = RelayMarkEditorServices.hexColor
    /// The only way to make the editor: Relay's TextKit 2 stack. A subclass
    /// built with `init(frame:)` starts in TextKit 1 compatibility mode.
    static func textKit2(frame: CGRect = .zero) -> CollaborationTextView {
        let storage = NSTextContentStorage(), manager = NSTextLayoutManager()
        storage.addTextLayoutManager(manager)
        let container = NSTextContainer(size: CGSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude))
        manager.textContainer = container
        let view = Self(frame: frame, textContainer: container)
        view.contentStorage = storage
        // Folded sections' paragraphs are skipped from layout, never removed from the text.
        storage.delegate = view
        // A table's grid stays with its attachment, wherever its paragraph is laid out.
        view.register([.onScrollingOutOfViewport, .onEditingInlineParagraphs],
                      forTextAttachmentViewProviderType: RelayTableAttachmentViewProvider.self)
        #if DEBUG
        RelayTextKit1Guard.install()
        #endif
        return view
    }
    /// The view does not own its content storage; this keeps the stack alive.
    private var contentStorage: NSTextContentStorage?
    let paper = RelayPaperViewState()
    var paperStorage: NSTextStorage { textStorage ?? NSTextStorage() }
    var selectionActions: [RelayMarkSelectionAction] = []
    var viewSelections: [NSRange] { selectedRanges.map(\.rangeValue) }
    /// A Genmoji has no RelayMark node: inserted, it would be lost on the next render.
    override var supportsAdaptiveImageGlyph: Bool { get { false } set {} }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        (super.accessibilityCustomActions() ?? []) + paperAccessibilityActions().map { action in
            NSAccessibilityCustomAction(name: action.name) { action.perform() }
        }
    }
    nonisolated var accessibilityCustomContent: [AXCustomContent]! {
        get {
            let content = MainActor.assumeIsolated { paperAccessibilityContent() }
            return content.map { let item = AXCustomContent(label: $0.label, value: $0.value); item.importance = .high; return item }
        }
        set {}
    }
    var isPaperEditable: Bool {
        get { isEditable }
        set { isEditable = newValue }
    }
    var hasMarkedInput: Bool { hasMarkedText() }
    var viewSelection: NSRange { selectedRange() }
    func showSelection(_ range: NSRange) {
        setSelectedRange(range)
        if editorLayout == .viewport || window?.firstResponder === self { scrollRangeToVisible(range) }
    }
    func unmarkPaperText() { unmarkText() }
    func paperNeedsDisplay() { needsDisplay = true }
    func replaceAllText(_ text: NSAttributedString) {
        performPaperEdit { textStorage?.setAttributedString(text) }
    }

    /// Find in paper searches the paper's text, table cells included.
    private(set) lazy var paperFinder = RelayPaperFinder(view: self)
    override func performTextFinderAction(_ sender: Any?) {
        guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag, let action = NSTextFinder.Action(rawValue: tag) else { return }
        paperFinder.finder.findBarContainer = enclosingScrollView
        paperFinder.finder.performAction(action)
    }
    /// Format menu actions with no mark in the paper. TextKit would apply them to the
    /// view alone and the next redraw would undo them, so they are disabled and refused.
    static let unsupportedFormatting: Set<Selector> = [
        #selector(changeColor(_:)), #selector(changeAttributes(_:)),
        #selector(alignLeft(_:)), #selector(alignCenter(_:)), #selector(alignRight(_:)),
        #selector(alignJustified(_:)),
        #selector(unscript(_:)),
        #selector(raiseBaseline(_:)), #selector(lowerBaseline(_:)),
        #selector(useStandardKerning(_:)), #selector(turnOffKerning(_:)),
        #selector(tightenKerning(_:)), #selector(loosenKerning(_:)),
        #selector(useStandardLigatures(_:)), #selector(turnOffLigatures(_:)), #selector(useAllLigatures(_:)),
        #selector(pasteFont(_:)), #selector(pasteRuler(_:)),
        #selector(makeBaseWritingDirectionLeftToRight(_:)), #selector(makeBaseWritingDirectionRightToLeft(_:)),
        #selector(makeBaseWritingDirectionNatural(_:)), #selector(makeTextWritingDirectionLeftToRight(_:)),
        #selector(makeTextWritingDirectionRightToLeft(_:)), #selector(makeTextWritingDirectionNatural(_:)),
    ]
    override func underline(_ sender: Any?) { performPaperCommand("editor.mark.underline") }
    override func changeColor(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func changeAttributes(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func alignLeft(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func alignCenter(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func alignRight(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func alignJustified(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func superscript(_ sender: Any?) { performPaperCommand("editor.mark.superscript") }
    override func `subscript`(_ sender: Any?) { performPaperCommand("editor.mark.subscript") }
    override func unscript(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func raiseBaseline(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func lowerBaseline(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func useStandardKerning(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func turnOffKerning(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func tightenKerning(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func loosenKerning(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func useStandardLigatures(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func turnOffLigatures(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func useAllLigatures(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func pasteFont(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func pasteRuler(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func makeBaseWritingDirectionLeftToRight(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func makeBaseWritingDirectionRightToLeft(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func makeBaseWritingDirectionNatural(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func makeTextWritingDirectionLeftToRight(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func makeTextWritingDirectionRightToLeft(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func makeTextWritingDirectionNatural(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if let action = item.action, Self.unsupportedFormatting.contains(action) { return false }
        if item.action == #selector(performTextFinderAction(_:)) {
            paperFinder.finder.findBarContainer = enclosingScrollView
            return NSTextFinder.Action(rawValue: item.tag).map { paperFinder.finder.validateAction($0) } ?? false
        }
        return super.validateUserInterfaceItem(item)
    }
    private func changeListDepth(backward: Bool) -> Bool {
        guard !retired, isEditable, !hasMarkedText(), compositionCompletion == nil,
              let session = editingSession, session.isEditable else { return false }
        session.setNativeSelection(paperSelection)
        return session.handleNativeListIndent(backward: backward)
    }
    override func insertTab(_ sender: Any?) {
        if !changeListDepth(backward: false) { super.insertTab(sender) }
    }
    /// At the text's start or end there is no character to remove, but the
    /// browser keymaps can still lift or join blocks there.
    private func deleteAtEdge(backward: Bool) -> Bool {
        let selection = selectedRange()
        guard !retired, isEditable, !hasMarkedText(), compositionCompletion == nil, selection.length == 0,
              backward ? selection.location == 0 : selection.location == viewLength,
              let session = editingSession, session.isEditable else { return false }
        session.setNativeSelection(paperSelection)
        return session.handleNativeEdgeDeletion(backward: backward)
    }
    override func deleteBackward(_ sender: Any?) {
        if !deleteAtEdge(backward: true) { super.deleteBackward(sender) }
    }
    override func deleteForward(_ sender: Any?) {
        if !deleteAtEdge(backward: false) { super.deleteForward(sender) }
    }
    /// Copy, drags and Services write a selection holding tables with each
    /// table as rows of tab-separated cells.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let visible = paper.tables.readable(paperStorage, range: selectedRange()) else {
            return super.writeSelection(to: pboard, types: types)
        }
        pboard.clearContents()
        return pboard.writeObjects([visible])
    }
    override func copy(_ sender: Any?) {
        guard paper.tables.readable(paperStorage, range: selectedRange()) != nil else { return super.copy(sender) }
        _ = writeSelection(to: copyPasteboard, types: writablePasteboardTypes)
    }
    /// Where Copy writes; tests use a private pasteboard.
    var copyPasteboard: NSPasteboard = .general
    override func insertBacktab(_ sender: Any?) {
        if !changeListDepth(backward: true) { super.insertBacktab(sender) }
    }
    var onPaperButton: ((Int) -> Bool)?
    var onTaskCheckbox: ((Int) -> Bool)?
    /// The session changed outside TextKit's own editing; the coordinator shows it.
    var onSessionEdit: (() -> Void)?
    /// The view entered a window, where it can take keyboard focus.
    var onMovedToWindow: (() -> Void)?
    /// The host's text read before the paper. The paper holds it weakly; the title
    /// holds the paper, so VoiceOver reads them as one shared text.
    var previousTextElement: (() -> AnyObject?)?
    override func accessibilitySharedTextUIElements() -> [Any]? {
        guard let previous = previousTextElement?() else { return super.accessibilitySharedTextUIElements() }
        return [previous, self]
    }
    func linkPreviousTextElement() {
        guard let title = previousTextElement?() as? NSView else { return }
        title.setAccessibilitySharedTextUIElements([title, self])
    }
    func unlinkPreviousTextElement() {
        guard let title = previousTextElement?() as? NSView,
              (title.accessibilitySharedTextUIElements() ?? []).contains(where: { $0 as AnyObject === self }) else { return }
        title.setAccessibilitySharedTextUIElements(nil)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onMovedToWindow?()
    }
    override func mouseDown(with event: NSEvent) {
        // Semantic attachment activation uses AppKit hit testing. Text selection
        // is entirely NSTextView's; there is no gutter hit-testing layer.
        if activatePaperButton(at: convert(event.locationInWindow, from: nil)) { return }
        super.mouseDown(with: event)
    }
    func activatePaperButton(at point: CGPoint) -> Bool {
        guard !retired, !hasMarkedText(), let onPaperButton,
              let offset = characterOffset(at: point) else { return false }
        return onPaperButton(offset)
    }
    func characterOffset(at point: CGPoint) -> Int? {
        guard let window, let ranges = RelayTextKitRanges(textLayoutManager) else { return nil }
        // NSTextInputClient resolves a character, whereas insertion hit testing
        // returns the boundary after an attachment when its trailing half is hit.
        let screenPoint = window.convertPoint(toScreen: convert(point, to: nil))
        let index = characterIndex(for: screenPoint)
        guard index >= 0, index < ranges.length,
              let frame = ranges.characterFrame(at: index) else { return nil }
        // Native character hit testing can return the nearest character outside
        // its bounds. Activate only inside the segment TextKit actually rendered.
        return frame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y).contains(point) ? index : nil
    }
    var onImageInputFailure: ((String) -> Void)? = nil
    var onBeginImageInput: ((NSRange, String, String) -> RelayMarkImageIntake?)?
    var onBeginImageBatchInputs: ((NSRange, [RelayMarkImageFile]) -> [RelayMarkImageIntake]?)?
    var onBeginStructuredPaste: ((NSRange, Int, String?) -> RelayMarkPasteIntake?)?
    private func imageFile(_ item: NSPasteboardItem) -> (URL, String?)? {
        guard let literal = item.string(forType: .fileURL), let file = URL(string: literal), file.isFileURL,
              let values = try? file.resourceValues(forKeys: [.contentTypeKey]),
              let type = values.contentType, type.conforms(to: .image) else { return nil }
        return (file, imagePolicy.mime(type.identifier))
    }
    private func hasImage(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.pasteboardItems?.contains(where: { imageFile($0) != nil ||
            $0.types.contains(where: { RelayNativeImageRepresentation.isImage($0.rawValue) }) }) == true
    }
    private func receiveImage(_ pasteboard: NSPasteboard, range: NSRange) -> Bool {
        guard hasImage(pasteboard), let items = pasteboard.pasteboardItems else { return false }
        if items.count > 1 {
            guard items.count <= 4096 else { onImageInputFailure?(String(localized: "Too many images in this paste. No item was inserted.", bundle: .module, comment: "Shown when a paste holds more images than the paper accepts.")); return true }
            var files: [RelayMarkImageFile] = []
            var reads: [() -> Data?] = []; let maximumBytes = imagePolicy.maximumBytes
            for item in items {
                if let (file, possibleMime) = imageFile(item), let mime = possibleMime {
                    files.append(.init(filename: file.lastPathComponent, contentType: mime))
                    reads.append {
                        let access = file.startAccessingSecurityScopedResource()
                        defer { if access { file.stopAccessingSecurityScopedResource() } }
                        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        guard size > 0, size <= maximumBytes else { return nil }
                        return try? Data(contentsOf: file)
                    }
                } else if let type = item.types.first(where: { imagePolicy.mime($0.rawValue) != nil }),
                          let mime = imagePolicy.mime(type.rawValue) {
                    files.append(.init(filename: RelayNativeImageRepresentation.filename(nil, identifier: type.rawValue), contentType: mime))
                    reads.append { item.data(forType: type) }
                } else {
                    onImageInputFailure?(String(localized: "Every item must be a supported image. No subset was inserted.", bundle: .module, comment: "Shown when some pasted or dropped items are not supported images.")); return true
                }
            }
            // Every reservation precedes the first file/provider byte read.
            guard let intakes = onBeginImageBatchInputs?(range, files), intakes.count == reads.count else { return true }
            for (index, read) in reads.enumerated() { intakes[index].receive(read()) }
            return true
        }
        guard let item = items.first else { return true }
        if let (file, possibleMime) = imageFile(item) {
            guard let mime = possibleMime else { onImageInputFailure?(String(localized: "This image type is not supported. No image was inserted.", bundle: .module, comment: "Shown when a pasted or dropped image type is not supported.")); return true }
            guard let intake = onBeginImageInput?(range, file.lastPathComponent, mime) else { return true }
            let access = file.startAccessingSecurityScopedResource()
            defer { if access { file.stopAccessingSecurityScopedResource() } }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 0, size <= imagePolicy.maximumBytes else { intake.receive(nil); return true }
            intake.receive(try? Data(contentsOf: file)); return true
        }
        guard let type = item.types.first(where: { imagePolicy.mime($0.rawValue) != nil }) else {
            onImageInputFailure?(String(localized: "This image type is not supported. No image was inserted.", bundle: .module, comment: "Shown when a pasted or dropped image type is not supported.")); return true
        }
        guard let mime = imagePolicy.mime(type.rawValue),
              let intake = onBeginImageInput?(range, RelayNativeImageRepresentation.filename(nil, identifier: type.rawValue), mime)
        else { return true }
        intake.receive(item.data(forType: type)); return true
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !retired, isEditable else { return [] }
        if hasImage(sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !retired, isEditable, !hasMarkedText(), compositionCompletion == nil else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        let offset = characterIndexForInsertion(at: point)
        if hasImage(sender.draggingPasteboard) {
            guard offset <= viewLength, !paper.tables.touchesTableLine(NSRange(location: offset, length: 0)) else { return false }
            setSelectedRange(NSRange(location: offset, length: 0))
            return receiveImage(sender.draggingPasteboard, range: selectedRange())
        }
        return super.performDragOperation(sender)
    }
    override func paste(_ sender: Any?) {
        guard !retired, isEditable, !hasMarkedText(), compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange()) <= viewLength else { return }
        if NSPasteboard.general.types?.contains(.html) == true {
            // Snapshot ordered item handles before reserving or requesting bytes.
            let items = NSPasteboard.general.pasteboardItems ?? []
            guard !items.isEmpty, items.allSatisfy({ $0.types.contains(.html) }) else {
                onImageInputFailure?(String(localized: "Mixed clipboard representations cannot be inserted as a subset. No item was inserted.", bundle: .module, comment: "Shown when a paste mixes formatted and other items.")); return
            }
            guard let intake = onBeginStructuredPaste?(selectedRange(), items.count, NSPasteboard.general.string(forType: .string)) else { return }
            for (index, item) in items.enumerated() { intake.receive(item.data(forType: .html), at: index) }
            return
        }
        if receiveImage(NSPasteboard.general, range: selectedRange()) { return }
        if pastePlainText(richer: true) || pasteRichText() { return }
        NSSound.beep()
    }
    /// Formatted clipboard text becomes one windowed command with its marks.
    private func pasteRichText() -> Bool {
        let pasteboard = NSPasteboard.general
        guard let session = editingSession,
              let rich = pasteboard.data(forType: .rtfd).flatMap({ NSAttributedString(rtfd: $0, documentAttributes: nil) })
                ?? pasteboard.data(forType: .rtf).flatMap({ NSAttributedString(rtf: $0, documentAttributes: nil) }),
              session.pasteNatively(range: paperSelection, piece: NativeProseCodec.value(rich, inferFontChanges: true)) else { return false }
        onSessionEdit?()
        return true
    }
    /// Plain clipboard text becomes one windowed command; `richer` refuses
    /// when the clipboard also carries a formatted representation.
    private func pastePlainText(richer: Bool) -> Bool {
        let pasteboard = NSPasteboard.general
        guard let session = editingSession, let value = pasteboard.string(forType: .string),
              !richer || !(pasteboard.types ?? []).contains(where: { [.rtf, .rtfd, .html].contains($0) }),
              session.pastePlainTextNatively(range: paperSelection, text: value) else { return false }
        onSessionEdit?()
        return true
    }
    override func pasteAsRichText(_ sender: Any?) {
        guard !retired, isEditable, !hasMarkedText(), compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange()) <= viewLength else { return }
        if NSPasteboard.general.types?.contains(.html) == true {
            // Snapshot ordered item handles before reserving or requesting bytes.
            let items = NSPasteboard.general.pasteboardItems ?? []
            guard !items.isEmpty, items.allSatisfy({ $0.types.contains(.html) }) else {
                onImageInputFailure?(String(localized: "Mixed clipboard representations cannot be inserted as a subset. No item was inserted.", bundle: .module, comment: "Shown when a paste mixes formatted and other items.")); return
            }
            guard let intake = onBeginStructuredPaste?(selectedRange(), items.count, NSPasteboard.general.string(forType: .string)) else { return }
            for (index, item) in items.enumerated() { intake.receive(item.data(forType: .html), at: index) }
            return
        }
        if receiveImage(NSPasteboard.general, range: selectedRange()) { return }
        if pasteRichText() || pastePlainText(richer: false) { return }
        NSSound.beep()
    }
    override func pasteAsPlainText(_ sender: Any?) {
        guard !retired, isEditable, !hasMarkedText(), compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange()) <= viewLength else { return }
        if !pastePlainText(richer: false) { NSSound.beep() }
    }
    /// Bold and italic from the font menu or panel are the paper's marks; other
    /// font changes are not part of the paper.
    override func changeFont(_ sender: Any?) {
        guard !retired, isEditable, !hasMarkedText(), compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange()) <= viewLength else { return }
        // A font change with no mark in the paper (a size or family) is refused, not shown and undone.
        if let manager = sender as? NSFontManager, !formatNatively(convert: manager.convert) { RelayPaperRefusal.feedback() }
    }
    /// Bold or italic toggled through the font menu or panel becomes one
    /// windowed mark command when `convert` changes exactly that trait.
    func formatNatively(convert: (NSFont) -> NSFont) -> Bool {
        let selection = selectedRange()
        // At a caret the font is the one the next typed text takes.
        let shown = selection.length > 0 ? textStorage?.attribute(.font, at: selection.location, effectiveRange: nil) : typingAttributes[.font]
        guard let session = editingSession, let font = shown as? NSFont else { return false }
        let before = font.fontDescriptor.symbolicTraits, after = convert(font).fontDescriptor.symbolicTraits
        let changed = [(RelayMarkFormattingMark.bold, NSFontDescriptor.SymbolicTraits.bold), (.italic, .italic)]
            .filter { before.contains($0.1) != after.contains($0.1) }
        guard changed.count == 1, after.subtracting([.bold, .italic]) == before.subtracting([.bold, .italic]) else { return false }
        if selection.length == 0 {
            guard session.toggleMarkNatively(changed[0].0, range: paper.tables.paper(selection)) else { return false }
            typingAttributes[.font] = convert(font)
            return true
        }
        guard session.formatNatively(range: paper.tables.paper(selection), mark: changed[0].0, enabled: after.contains(changed[0].1)) else { return false }
        onSessionEdit?()
        return true
    }
    fileprivate let collaborationUndo = CollaborationUndoManager()
    weak var editingSession: (any RelayPaperTextEditing)?
    fileprivate var finalizerRegistration: UUID?
    private(set) var retired = false
    private var compositionGeneration = UUID()
    private var compositionCompletion: Task<Void, Never>?
    func cancelCompositionCompletion() {
        compositionGeneration = UUID()
        compositionCompletion?.cancel(); compositionCompletion = nil
    }
    func retireInput() {
        retired = true
        onTaskCheckbox = nil
        onSessionEdit = nil
        cancelCompositionCompletion()
        onCompositionStart = nil; onCompositionEnd = nil; onDeclaredMarkedInput = nil
        collaborationUndo.undoAction = nil; collaborationUndo.redoAction = nil
    }
    func applyEmptyTypingStyle() {
        let selection = paperSelection
        if selection.length == 0, let block = paper.emptyBlocks.first(where: { $0.offset == selection.location }) {
            var attributes = NativeProseCodec.emptyAttributes(block.intent, inlineIntent: block.inlineIntent, link: block.link,
                typingStyle: block.typingStyle, listContext: paper.nativeLists)
            if let task = paper.taskItems.first(where: { $0.firstParagraphRange.location == block.offset }) {
                attributes[.paragraphStyle] = NativeProseCodec.emptyParagraphStyle(block.intent, checked: task.checked,
                    listContext: paper.nativeLists)
            }
            typingAttributes = attributes
        }
    }
    var onDeclaredMarkedInput: ((String?, NSRange, NSRange, NSRange?, Bool) -> Bool)?
    var onCompositionStart: (() -> Void)?
    var onCompositionEnd: (() -> Void)?
    override var undoManager: UndoManager? { collaborationUndo }
    @objc func undo(_ sender: Any?) {
        guard !retired, isEditable else { return }
        collaborationUndo.undo()
    }
    @objc func redo(_ sender: Any?) {
        guard !retired, isEditable else { return }
        collaborationUndo.redo()
    }
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard !retired, isEditable else { return }
        if !hasMarkedText() { cancelCompositionCompletion(); onCompositionStart?() }
        if let onDeclaredMarkedInput {
            let literal: String
            if let attributed = string as? NSAttributedString { literal = attributed.string }
            else if let value = string as? String { literal = value }
            else { return }
            let effective = replacementRange.location == NSNotFound ? (hasMarkedText() ? markedRange() : self.selectedRange()) : replacementRange
            guard onDeclaredMarkedInput(literal, effective, selectedRange, replacementRange, false) else { return }
        }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }
    override func unmarkText() {
        let wasMarked = hasMarkedText()
        super.unmarkText()
        if wasMarked, !retired {
            let generation = compositionGeneration
            compositionCompletion = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, !self.retired, generation == self.compositionGeneration, !self.hasMarkedText() else { return }
                self.compositionCompletion = nil
                self.onCompositionEnd?()
            }
        }
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard !retired, isEditable else { return }
        if (hasMarkedText() || compositionCompletion != nil), let onDeclaredMarkedInput {
            let literal: String
            if let value = insertString as? NSAttributedString { literal = value.string }
            else if let value = insertString as? String { literal = value }
            else { return }
            let effective = replacementRange.location == NSNotFound ? (hasMarkedText() ? markedRange() : selectedRange()) : replacementRange
            guard onDeclaredMarkedInput(literal, effective, selectedRange(), replacementRange, true) else { return }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }
    override func textViewportLayoutControllerDidLayout(_ controller: NSTextViewportLayoutController) {
        super.textViewportLayoutControllerDidLayout(controller)
        viewportDidLayout(controller)
        onContentLayoutChange?()
    }

    nonisolated func textContentManager(_ textContentManager: NSTextContentManager, shouldEnumerate textElement: NSTextElement,
                                        options: NSTextContentManager.EnumerationOptions) -> Bool {
        nonisolated(unsafe) let element = textElement
        return MainActor.assumeIsolated { paperShows(element) }
    }

}
#else
@MainActor
/// The paper's text view: TextKit 2 over one editor session.
public struct RelayMarkEditorView: UIViewRepresentable {
    typealias Session = RelayMarkEditorSession
    /// Names the editor's task-checkbox tap among the text view's recognizers.
    static let taskTapName = "relaymark.task-checkbox"
    var session: Session
    var accessibilityLabel: String
    var services = RelayMarkEditorServices()

    public init(session: RelayMarkEditorSession, accessibilityLabel: String, services: RelayMarkEditorServices = .init()) {
        self.session = session; self.accessibilityLabel = accessibilityLabel; self.services = services
    }
    public func makeCoordinator() -> Coordinator { Coordinator(text: TextCoordinator(session: session)) }
    /// Owns the view's text system for SwiftUI; its members are internal.
    @MainActor public final class Coordinator {
        let text: TextCoordinator
        init(text: TextCoordinator) { self.text = text }
    }
    public func makeUIView(context: Context) -> CollaborationTextContainer {
        context.coordinator.text.services = services
        let container = CollaborationTextContainer()
        container.install(context.coordinator.text.makeTextView(accessibilityLabel: accessibilityLabel))
        container.configure(services)
        return container
    }
    public func updateUIView(_ container: CollaborationTextContainer, context: Context) {
        _ = services.imageStore?.revision
        context.coordinator.text.services = services
        if context.coordinator.text.session !== session {
            let previous = container.textView
            let wasFocused = previous?.isFirstResponder == true
            if let previous { previous.attach(header: nil); context.coordinator.text.retire(previous) }
            context.coordinator.text.session = session
            let replacement = context.coordinator.text.makeTextView(accessibilityLabel: accessibilityLabel)
            container.install(replacement)
            if wasFocused { replacement.becomeFirstResponder() }
        } else if let view = container.textView { context.coordinator.text.update(view) }
        container.configure(services)
    }
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: CollaborationTextContainer, context: Context) -> CGSize? {
        proposal.width.flatMap { uiView.contentSize(at: $0) }
    }
    public static func dismantleUIView(_ container: CollaborationTextContainer, coordinator: Coordinator) {
        if let view = container.textView { view.attach(header: nil); coordinator.text.retire(view) }
    }
    @MainActor final class TextCoordinator: NSObject, UITextViewDelegate, UITextPasteDelegate, UITextFormattingViewController.Delegate {
        /// The host's services; tests may set the closures below directly.
        var services = RelayMarkEditorServices() {
            didSet {
                mediaImages = services.imageStore
                onActivatePaperButton = services.paperControls.map { controls in { controls.activatePaperButton(id: $0) } }
                onActivateFragmentLink = services.links.map { links in { links.activateFragmentLink($0) } }
                onImageInputFailure = services.inputRefused
                onBeginImageInput = services.images.map { images in { images.beginImageInput(at: $0, filename: $1, contentType: $2) } }
                onBeginImageBatchInputs = services.images.map { images in { images.beginImageInputs(at: $0, files: $1) } }
                onBeginStructuredPaste = services.paste.map { paste in { paste.beginStructuredPaste(at: $0, itemCount: $1, plainText: $2) } }
            }
        }
        var mediaImages: RelayMarkImageStore? {
            get { editor.mediaImages }
            set { editor.mediaImages = newValue }
        }
        var onActivatePaperButton: ((String) -> Void)?
        var onActivateFragmentLink: ((String) -> Void)?
        var onImageInputFailure: ((String) -> Void)?
        var onBeginImageBatchInputs: ((NSRange, [RelayMarkImageFile]) -> [RelayMarkImageIntake]?)?
        var onBeginImageInput: ((NSRange, String, String) -> RelayMarkImageIntake?)?
        var onBeginStructuredPaste: ((NSRange, Int, String?) -> RelayMarkPasteIntake?)?
        let editor: RelayPaperEditor<Session>
        var session: Session {
            get { editor.session }
            set { editor.session = newValue }
        }
        var composition: Session.Composition? {
            get { editor.composition }
            set { editor.composition = newValue }
        }
        private var updating: Bool {
            get { editor.updating }
            set { editor.updating = newValue }
        }
        /// A keystroke inside one text leaf, applied without reading the whole paper.
        var pendingTyping: (range: NSRange, text: String)? { editor.pendingTyping.map { ($0.paper, $0.text) } }
        private var pasteCommands: [String: (command: RelayNativePasteCommand, owner: ObjectIdentifier, preservesFormatting: Bool)] = [:]
        var pendingPasteCount: Int { pasteCommands.count }
        init(session: Session) { editor = RelayPaperEditor(session: session) }
        func makeTextView(accessibilityLabel: String) -> CollaborationTextView {
            let view = CollaborationTextView.textKit2()
            view.editingSession = session
            apply(services, to: view)
            editor.attach(view)
            // Find in paper, including text inside table cells.
            view.installFind()
            view.onImageInputFailure = { [weak self, weak view] message in
                guard let self, let view, view.editingSession === session, !session.isInvalidated else { return }
                onImageInputFailure?(message)
            }
            view.onBeginImageInput = { [weak self, weak view] range, filename, contentType in
                guard let self, let view, !view.retired, view.editingSession === session,
                      !session.isInvalidated, session.isEditable else { return nil }
                return onBeginImageInput?(view.paper.tables.paper(range), filename, contentType)
            }
            view.onBeginImageBatchInputs = { [weak self, weak view] range, files in
                guard let self, let view, !view.retired, view.editingSession === session,
                      !session.isInvalidated, session.isEditable else { return nil }
                return onBeginImageBatchInputs?(view.paper.tables.paper(range), files)
            }
            view.onBeginStructuredPaste = { [weak self, weak view] range, itemCount, plainText in
                guard let self, let view, !view.retired, view.editingSession === session,
                      !session.isInvalidated, session.isEditable else { return nil }
                return onBeginStructuredPaste?(view.paper.tables.paper(range), itemCount, plainText)
            }
            view.delegate = self
            view.onPaperButton = { [weak self, weak view] offset in
                guard let self, let view, view.editingSession === session, !session.isInvalidated,
                      let activate = onActivatePaperButton else { return false }
                let paper = view.paper.tables.paper(offset)
                guard let atom = session.nativeBlockAtoms.first(where: { $0.control == .button && NSLocationInRange(paper, $0.range) }) else { return false }
                activate(atom.id)
                return true
            }
            view.textDropDelegate = view
            view.textDragDelegate = view
            view.pasteDelegate = self
            view.onCompositionStart = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                composition = try? session.beginComposition()
            }
            view.onDeclaredMarkedInput = { [weak self, weak view] literal, replacement, selection, supplied, final in
                guard let self, let view, !view.retired, view.editingSession === session,
                      let token = self.composition else { return false }
                let tables = view.paper.tables
                return session.declareMarkedInput(literal, replacement: tables.paper(replacement), selection: selection,
                    platform: .uiKit, suppliedReplacement: supplied.map { $0.location == NSNotFound ? $0 : tables.paper($0) },
                    phase: final ? .final : .marked, from: token)
            }
            view.onCompositionEnd = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                endComposition(view)
            }
            view.backgroundColor = .clear
            view.textContainerInset = UIEdgeInsets(top: view.baseTopInset, left: RelayPaperMargins.leading, bottom: 8, right: RelayPaperMargins.trailing)
            view.allowsEditingTextAttributes = true
            view.textFormattingConfiguration = CollaborationTextView.formattingPanel
            view.adjustsFontForContentSizeCategory = true
            view.accessibilityLabel = accessibilityLabel
            view.onSessionEdit = { [weak self, weak view] in
                guard let self, let view, !view.retired else { return }
                self.update(view)
            }
            session.onFocusRequest = { [weak self, weak view] in
                guard let self, let view else { return }
                takeFocusIfRequested(view)
            }
            view.onMovedToWindow = { [weak self, weak view] in
                guard let self, let view else { return }
                takeFocusIfRequested(view)
            }
            view.onTaskCheckbox = { [weak self, weak view] offset in
                guard let self, let view, view.editingSession === session else { return false }
                // A tap mid-composition commits the composed title first, so the
                // draft finishes with the words typed (Douglas, M10).
                if view.hasMarkedInput { do { try finishComposition(view) } catch { return false } }
                guard session.toggleTaskItem(atUTF16: view.paper.tables.paper(offset)) else { return false }
                self.update(view)
                return true
            }
            let tap = UITapGestureRecognizer(target: view, action: #selector(CollaborationTextView.handleTaskTap(_:)))
            tap.cancelsTouchesInView = false
            tap.name = RelayMarkEditorView.taskTapName
            // Recognized alongside UITextView's own taps, which place the caret.
            tap.delegate = view.taskTapDelegate
            view.addGestureRecognizer(tap)
            view.collaborationUndo.undoAction = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                session.undo(); self.update(view)
            }
            view.collaborationUndo.redoAction = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                session.redo(); self.update(view)
            }
            view.finalizerRegistration = session.registerNativeCompositionFinalizer({ [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                try finishComposition(view)
            }, refresh: { [weak self, weak view] in
                guard let self, let view, !view.retired, view.editingSession === session else { return }
                self.update(view)
            })
            update(view)
            return view
        }
        func finishComposition(_ view: CollaborationTextView) throws { try editor.finishComposition(view) }
        func retire(_ view: CollaborationTextView) {
            guard !view.retired else { return }
            updating = true
            defer { updating = false }
            if view.editingSession === session, session.isEditable { try? finishComposition(view) }
            editor.retireTables(view)
            if let composition, view.editingSession === session { session.cancelComposition(composition) }
            composition = nil
            if let registration = view.finalizerRegistration { view.editingSession?.unregisterNativeCompositionFinalizer(registration) }
            view.finalizerRegistration = nil
            view.retireInput()
            view.delegate = nil
            view.pasteDelegate = nil
            pasteCommands.removeAll()
            view.unmarkText()
            view.isEditable = false
            view.resignFirstResponder()
            view.attributedText = NSAttributedString(string: "")
            view.paper.tables = RelayTableSpans(); view.paper.tableAttachments = [:]
            view.selectedRange = NSRange(location: 0, length: 0)
            view.paper.remoteSelections = []
            view.unlinkPreviousTextElement()
            if view.editingSession === session { session.onFocusRequest = nil }
            view.editingSession = nil
        }
        func textView(_ textView: UITextView, editMenuForTextInRanges ranges: [NSValue],
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let view = textView as? CollaborationTextView, !view.retired else { return nil }
            var children = suggestedActions
            let entries = view.sectionMenuEntries(link: services.sectionLink)
            if !entries.isEmpty {
                children.append(UIMenu(options: .displayInline, children: entries.map { entry in UIAction(title: entry.title) { _ in entry.run() } }))
            }
            // The paper's Format commands follow the system's edit menu items.
            if view.editingSession === session, session.isEditable {
                children.append(RelayMarkEditorCommandMenus.format(session: session) { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.update(view)
                })
            }
            return children.count == suggestedActions.count ? nil : UIMenu(children: children)
        }
        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content, url.absoluteString.hasPrefix("#"),
                  let view = textView as? CollaborationTextView,
                  let activate = onActivateFragmentLink else { return defaultAction }
            let href = url.absoluteString
            let owner = ObjectIdentifier(session)
            return UIAction { [weak self, weak view] _ in
                guard let self, let view, !view.retired, view.editingSession === session,
                      ObjectIdentifier(session) == owner, !session.isInvalidated else { return }
                activate(href)
                update(view)
                view.scrollRangeToVisible(view.viewSelection)
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextInRanges ranges: [NSValue], replacementText text: String) -> Bool {
            guard !updating, let view = textView as? CollaborationTextView, !view.retired,
                view.editingSession == nil || view.editingSession === session else { return false }
            view.pasteCommand = nil
            return editor.shouldChange(view, ranges: ranges.map(\.rangeValue), replacement: text)
        }
        private static var pasteToken: NSAttributedString.Key { NSAttributedString.Key("RelayTransientPasteToken") }
        func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
                                             transform item: any UITextPasteItem) {
            // HTML may only use the scope captured by the explicit paste
            // command before UIKit begins asynchronous provider delivery.
            if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.html.identifier) {
                item.setNoResult()
                guard let view = textPasteConfigurationSupporting as? CollaborationTextView,
                      let intake = view.structuredPasteIntake else { return }
                view.structuredPasteIntake = nil
                item.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.html.identifier) { data, _ in
                    Task { @MainActor in intake.receive(data) }
                }
                return
            }
            guard let view = textPasteConfigurationSupporting as? CollaborationTextView,
                  !view.retired, view.editingSession === session, let command = view.pasteCommand else {
                item.setDefaultResult(); return
            }
            let rich = item.itemProvider.hasItemConformingToTypeIdentifier(UTType.rtf.identifier)
            guard rich || item.itemProvider.registeredTypeIdentifiers.allSatisfy({ UTType($0)?.conforms(to: .plainText) == true }) else {
                item.setDefaultResult(); return
            }
            let tokenID = command.id.uuidString
            let preservesFormatting = rich || pasteCommands[tokenID]?.preservesFormatting == true
            pasteCommands[tokenID] = (command, ObjectIdentifier(session), preservesFormatting)
            let complete: @MainActor @Sendable (NSAttributedString?) -> Void = { [weak self, weak view] payload in
                guard let self, let view else { item.setNoResult(); return }
                guard !view.retired, !self.session.isInvalidated, view.editingSession === self.session,
                      self.pasteCommands[tokenID]?.owner == ObjectIdentifier(self.session) else {
                    self.pasteCommands[tokenID] = nil
                    item.setNoResult(); return
                }
                guard let payload else { self.pasteCommands[tokenID] = nil; item.setNoResult(); return }
                let tagged = NSMutableAttributedString(attributedString: payload)
                tagged.addAttribute(Self.pasteToken, value: tokenID, range: NSRange(location: 0, length: tagged.length))
                item.setResult(attributedString: tagged)
            }
            // Decode with Foundation on the main actor. Provider callbacks carry
            // only Sendable bytes/text; the captured token retains exact owner,
            // baseline and selection fences for acceptance or draft recovery.
            if rich {
                item.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.rtf.identifier) { data, _ in
                    Task { @MainActor in
                        guard let data, data.count <= 4_194_304 else { complete(nil); return }
                        let decoded = try? NSAttributedString(data: data,
                            options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
                        complete(decoded)
                    }
                }
            } else {
                item.itemProvider.loadObject(ofClass: NSString.self) { value, _ in
                    let string = value as? String
                    Task { @MainActor in complete(string.map { NSAttributedString(string: $0) }) }
                }
            }
        }
        func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
                                             performPasteOf attributedString: NSAttributedString, to textRange: UITextRange) -> UITextRange {
            guard let view = textPasteConfigurationSupporting as? CollaborationTextView,
                  !updating, !view.retired, view.editingSession === session, session.isEditable else { return textRange }
            let range = NSRange(location: view.offset(from: view.beginningOfDocument, to: textRange.start),
                length: view.offset(from: textRange.start, to: textRange.end))
            let paperRange = view.paper.tables.paper(range)
            var tokens = Set<String>()
            var missingToken = false
            attributedString.enumerateAttribute(Self.pasteToken, in: NSRange(location: 0, length: attributedString.length)) { value, _, _ in
                if let value = value as? String { tokens.insert(value) } else { missingToken = true }
            }
            let token = view.pasteCommand
            let accepted = !missingToken && tokens.count == 1 && tokens.first == token?.id.uuidString &&
                pasteCommands[token?.id.uuidString ?? ""]?.owner == ObjectIdentifier(session) &&
                token?.baseline == view.paperValue() && token?.range == paperRange &&
                view.markedTextRange == nil && composition == nil
            // Unknown/foreign tokens cannot transfer any candidate into this owner.
            guard tokens.allSatisfy({ pasteCommands[$0]?.owner == ObjectIdentifier(session) }) else {
                return view.selectedTextRange ?? textRange
            }
            guard session.acceptsNativePastePayload(attributedString.string) else {
                for value in tokens { pasteCommands[value] = nil }
                if tokens.contains(view.pasteCommand?.id.uuidString ?? "") { view.pasteCommand = nil }
                return view.selectedTextRange ?? textRange
            }
            let richImport = tokens.contains { pasteCommands[$0]?.preservesFormatting == true }
            let clean = NSMutableAttributedString(attributedString: attributedString)
            clean.removeAttribute(Self.pasteToken, range: NSRange(location: 0, length: clean.length))
            if !accepted, !tokens.isEmpty {
                let entries = tokens.compactMap { pasteCommands[$0] }
                guard entries.count == tokens.count, let first = entries.first,
                      entries.allSatisfy({ $0.owner == ObjectIdentifier(session) &&
                          $0.command.baseline == first.command.baseline && $0.command.range == first.command.range }) else { return view.selectedTextRange ?? textRange }
                // Preserve each original paste scope without changing the active
                // view/selection or consuming a newer command's token.
                for value in tokens {
                    guard let entry = pasteCommands.removeValue(forKey: value), entry.owner == ObjectIdentifier(session) else { continue }
                    let original = entry.command
                    let candidate = NSMutableAttributedString(attributedString: NativeProseCodec.attributed(
                        original.baseline, tableCells: session.nativeTableCells,
                        callouts: session.nativeCallouts, inlineAtoms: session.nativeInlineAtoms,
                        blockAtoms: session.nativeBlockAtoms,
                                                      authoredWidgets: session.nativeAuthoredWidgets,
                        entityReferenceAtoms: session.nativeEntityReferenceAtoms,
                        mediaAtoms: session.nativeMediaAtoms,
                        suggestionAtoms: session.nativeSuggestionAtoms))
                    guard NSMaxRange(original.range) <= candidate.length else { continue }
                    // Mixed provider results are unproven, but every byte must
                    // remain reviewable, including untagged provider portions.
                    candidate.replaceCharacters(in: original.range, with: clean)
                    let rendered = NativeProseCodec.value(candidate, inferFontChanges: entry.preservesFormatting)
                    let replacement = RelayNativeTextReplacement(baseline: String(original.baseline.characters),
                        range: original.range, replacement: clean.string)
                    let scoped = entry.preservesFormatting
                        ? original.attributedCandidate(replacement: replacement, rendered: rendered)
                        : original.plainCandidate(replacement: replacement, rendered: String(rendered.characters))
                    session.preserveRejectedPaste(scoped ?? rendered, id: original.id)
                }
                return view.selectedTextRange ?? textRange
            }
            guard range.location >= 0, NSMaxRange(range) <= view.viewLength else { return view.selectedTextRange ?? textRange }
            if tokens.contains(view.pasteCommand?.id.uuidString ?? "") { view.pasteCommand = nil }
            for value in tokens { pasteCommands[value] = nil }
            // The paste is one windowed command over the selection, with its marks when it is rich.
            let pasted = richImport
                ? session.pasteNatively(range: paperRange, piece: NativeProseCodec.value(clean, inferFontChanges: true))
                : session.pastePlainTextNatively(range: paperRange, text: clean.string)
            if !pasted {
                // A paste the paper cannot take is kept for review and reported, never dropped.
                let baseline = view.paperString
                let replacement = RelayNativeTextReplacement(baseline: baseline, range: paperRange, replacement: clean.string)
                let rendered = (baseline as NSString).replacingCharacters(in: paperRange, with: clean.string)
                session.preserveRejectedPaste(token?.plainCandidate(replacement: replacement, rendered: rendered)
                    ?? AttributedString(rendered), id: token?.id ?? UUID())
            }
            update(view)
            return view.selectedTextRange ?? textRange
        }
        func textViewDidChange(_ textView: UITextView) {
            guard let view = textView as? CollaborationTextView else { return }
            editor.didChange(view)
        }
        func endComposition(_ view: CollaborationTextView) {
            guard !updating, !view.retired, composition != nil, view.markedTextRange == nil,
                view.editingSession == nil || view.editingSession === session else { return }
            textViewDidChange(view)
        }
        /// Writing Tools rewrites prose; structured table attachments are excluded.
        func textView(_ textView: UITextView, writingToolsIgnoredRangesInEnclosingRange enclosingRange: NSRange) -> [NSValue] {
            guard let view = textView as? CollaborationTextView else { return [] }
            return view.paper.tables.spans.filter { NSLocationInRange($0.view, enclosingRange) }
                .map { NSValue(range: NSRange(location: $0.view, length: 1)) }
        }
        /// The formatting panel's changes are the paper's marks, applied by the
        /// session; a change the paper has no mark for is refused, never shown and lost.
        func textView(_ textView: UITextView, willBeginFormattingWith viewController: UITextFormattingViewController) {
            viewController.delegate = self
        }
        func textFormattingViewController(_ viewController: UITextFormattingViewController,
                                          didChangeValue changeValue: UITextFormattingViewController.ChangeValue) {
            guard let view = editor.attachedView as? CollaborationTextView, !view.retired, !updating, view.markedTextRange == nil,
                  view.editingSession === session, session.isEditable else { return }
            let applied: Bool
            switch changeValue {
            case .bold(let on): applied = view.setMark(.bold, enabled: on)
            case .italic(let on): applied = view.setMark(.italic, enabled: on)
            case .strikethrough(let on): applied = view.setMark(.strike, enabled: on)
            case .underline: applied = view.performPaperCommand("editor.mark.underline")
            default: applied = false
            }
            guard applied else { RelayPaperRefusal.feedback(); return }
            update(view)
            viewController.formattingDescriptor = .init(string: view.textStorage, range: view.selectedRange)
        }
        func textViewDidChangeSelection(_ view: UITextView) {
            guard !updating, let view = view as? CollaborationTextView, !view.retired, view.markedTextRange == nil,
                view.editingSession == nil || view.editingSession === session else { return }
            if view.pasteCommand?.range != view.paperSelection { view.pasteCommand = nil }
            editor.selectionDidChange(view)
        }
        func update(_ view: CollaborationTextView) {
            guard !view.retired, view.editingSession == nil || view.editingSession === session else { return }
            if session.isInvalidated { pasteCommands.removeAll(); view.pasteCommand = nil; view.pasteDelegate = nil }
            apply(services, to: view)
            editor.update(view)
        }
        /// The host asked for focus in the paper: the view takes it, with the
        /// session's selection, once it is in a window.
        func takeFocusIfRequested(_ view: CollaborationTextView) {
            guard session.focusRequest != nil, !view.retired, view.editingSession === session, view.window != nil else { return }
            session.focusRequest = nil
            update(view)
            view.becomeFirstResponder()
            view.scrollRangeToVisible(view.viewSelection)
        }
        private func apply(_ services: RelayMarkEditorServices, to view: CollaborationTextView) {
            view.editorLayout = services.layout
            view.imagePolicy = .init(accepted: services.images?.acceptedImageTypes ?? [],
                                     maximumBytes: services.images?.maximumImageBytes ?? 0)
            view.collaboratorColor = services.collaboratorColor
            view.selectionActions = services.selectionActions
            view.previousTextElement = services.previousTextElement
            view.linkPreviousTextElement()
        }
    }
}
/// Only the native input client changes with the paper; SwiftUI keeps its layout host.
@MainActor
public final class CollaborationTextContainer: UIView {
    private(set) var textView: CollaborationTextView?
    private var sizing = RelayEditorContentLayout()
    /// VoiceOver reads a hosted header before the paper's text.
    override public var accessibilityElements: [Any]? {
        get { textView.map { view in [view.headerView, view].compactMap { $0 } } }
        set {}
    }
    func install(_ view: CollaborationTextView) {
        textView?.onContentLayoutChange = nil
        textView?.removeFromSuperview()
        textView = view
        view.onContentLayoutChange = { [weak self] in self?.scheduleContentMeasurement() }
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    func configure(_ services: RelayMarkEditorServices) {
        guard let view = textView else { return }
        view.editorLayout = services.layout
        view.isScrollEnabled = services.layout == .viewport
        if services.layout == .content, view.contentOffset != .zero { view.setContentOffset(.zero, animated: false) }
        let behavior: UIScrollView.ContentInsetAdjustmentBehavior = services.layout == .content || services.bottomContentInset != nil ? .never : .automatic
        view.contentInsetAdjustmentBehavior = behavior
        view.contentInset.bottom = services.layout == .viewport ? services.bottomContentInset ?? 0 : 0
        view.verticalScrollIndicatorInsets.bottom = view.contentInset.bottom
        view.attach(header: services.layout == .viewport ? services.header : nil)
        sizing.viewportDidChange(layout: services.layout, revision: services.contentViewportRevision) { [weak self] in
            guard let self else { return }
            layoutIfNeeded()
            guard let view = textView, !view.retired, view.editorLayout == .content, view.isFirstResponder else { return }
            view.scrollRangeToVisible(view.viewSelection)
        }
        scheduleContentMeasurement()
    }
    override public func layoutSubviews() {
        super.layoutSubviews()
        scheduleContentMeasurement()
    }
    func contentSize(at width: CGFloat) -> CGSize? {
        guard let view = textView, view.editorLayout == .content, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: view.contentHeight(at: width))
    }
    override public var intrinsicContentSize: CGSize {
        contentSize(at: bounds.width).map { CGSize(width: UIView.noIntrinsicMetric, height: $0.height) } ?? super.intrinsicContentSize
    }
    private func scheduleContentMeasurement() {
        guard textView?.editorLayout == .content else { return }
        sizing.schedule { [weak self] in
            guard let self, let size = contentSize(at: bounds.width) else { return nil }
            return size.height
        } changed: { [weak self] in
            self?.invalidateIntrinsicContentSize()
        }
    }
}
@MainActor
final class CollaborationTextView: UITextView, UITextDropDelegate, UITextDragDelegate, RelayPaperTextView, NSTextContentStorageDelegate, AXCustomContentProvider {
    var editorLayout: RelayMarkEditorLayout = .viewport
    var onContentLayoutChange: (() -> Void)?
    func contentHeight(at width: CGFloat) -> CGFloat {
        sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }
    override func scrollRangeToVisible(_ range: NSRange) {
        guard editorLayout == .content else { return super.scrollRangeToVisible(range) }
        guard let position = position(from: beginningOfDocument, offset: NSMaxRange(range)) else { return }
        scrollRectToVisible(caretRect(for: position), animated: false)
    }
    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        guard editorLayout == .content else { return super.scrollRectToVisible(rect, animated: animated) }
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView, scroll.isScrollEnabled {
                scroll.scrollRectToVisible(convert(rect, to: scroll), animated: animated)
                return
            }
            ancestor = view.superview
        }
    }
    /// Lets the task-checkbox tap recognize together with the text view's own
    /// taps. Without it the checkbox tap wins and a tap never focuses the paper.
    final class SimultaneousTapDelegate: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
    let taskTapDelegate = SimultaneousTapDelegate()
    /// The host's image capability and collaborator colors, from its services.
    var imagePolicy = RelayNativeImageRepresentation()
    var collaboratorColor: (String) -> Color = RelayMarkEditorServices.hexColor
    /// The only way to make the editor: Relay's TextKit 2 stack. A subclass
    /// built with `init(frame:)` starts in TextKit 1 compatibility mode.
    static func textKit2(frame: CGRect = .zero) -> CollaborationTextView {
        let storage = NSTextContentStorage(), manager = NSTextLayoutManager()
        storage.addTextLayoutManager(manager)
        let container = NSTextContainer(size: CGSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude))
        manager.textContainer = container
        let view = Self(frame: frame, textContainer: container)
        view.contentStorage = storage
        // Folded sections' paragraphs are skipped from layout, never removed from the text.
        storage.delegate = view
        // A table's grid stays with its attachment, wherever its paragraph is laid out.
        view.register([.onScrollingOutOfViewport, .onEditingInlineParagraphs],
                      forTextAttachmentViewProviderType: RelayTableAttachmentViewProvider.self)
        return view
    }
    /// The view does not own its content storage; this keeps the stack alive.
    private var contentStorage: NSTextContentStorage?
    let paper = RelayPaperViewState()
    var paperStorage: NSTextStorage { textStorage }
    /// The host's text read before the paper. The paper holds it weakly; the title
    /// holds the paper, so VoiceOver's line reading crosses from one to the other.
    var previousTextElement: (() -> AnyObject?)?
    override var accessibilityPreviousTextNavigationElement: Any? {
        get { previousTextElement?() ?? super.accessibilityPreviousTextNavigationElement }
        set { super.accessibilityPreviousTextNavigationElement = newValue }
    }
    func linkPreviousTextElement() {
        (previousTextElement?() as? NSObject)?.accessibilityNextTextNavigationElement = self
    }
    func unlinkPreviousTextElement() {
        guard let title = previousTextElement?() as? NSObject,
              title.accessibilityNextTextNavigationElement as AnyObject? === self else { return }
        title.accessibilityNextTextNavigationElement = nil
    }
    /// The keyboard keeps its language per context; the paper and its cells are one.
    static let keyboardContext = "relay.paper"
    override var textInputContextIdentifier: String? { Self.keyboardContext }
    var selectionActions: [RelayMarkSelectionAction] = []
    var viewSelections: [NSRange] { selectedRanges }
    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            (super.accessibilityCustomActions ?? []) + paperAccessibilityActions().map { action in
                let custom = UIAccessibilityCustomAction(name: action.name) { _ in action.perform() }
                if action.edits { custom.category = UIAccessibilityCustomAction.editCategory }
                return custom
            }
        }
        set { super.accessibilityCustomActions = newValue }
    }
    nonisolated var accessibilityCustomContent: [AXCustomContent]! {
        get {
            let content = MainActor.assumeIsolated { paperAccessibilityContent() }
            return content.map { let item = AXCustomContent(label: $0.label, value: $0.value); item.importance = .high; return item }
        }
        set {}
    }
    override func toggleUnderline(_ sender: Any?) {
        guard !retired, isEditable, markedTextRange == nil, compositionCompletion == nil else { return }
        performPaperCommand("editor.mark.underline")
    }
    /// The formatting panel offers only the paper's marks: bold, italic, underline
    /// and strikethrough. Fonts, sizes, colours and alignment are not paper.
    static var formattingPanel: UITextFormattingViewController.Configuration {
        UITextFormattingViewController.Configuration(groups: [.group([.component(.fontAttributes, .automatic)])])
    }
    var isPaperEditable: Bool {
        get { isEditable }
        set { isEditable = newValue }
    }
    var hasMarkedInput: Bool { markedTextRange != nil }
    var viewSelection: NSRange { selectedRange }
    func showSelection(_ range: NSRange) {
        selectedRange = range
        if editorLayout == .viewport || isFirstResponder { scrollRangeToVisible(range) }
    }
    func unmarkPaperText() { unmarkText() }
    func paperNeedsDisplay() { setNeedsDisplay() }
    func replaceAllText(_ text: NSAttributedString) {
        pasteCommand = nil
        attributedText = text
    }

    /// The paper remains on TextKit 2 while table attachments own their native views.
    override func layoutSubviews() {
        super.layoutSubviews()
        assert(textLayoutManager != nil, "The paper switched to TextKit 1 compatibility mode")
        layOutHeader()
        onContentLayoutChange?()
    }
    private func changeListDepth(backward: Bool) -> Bool {
        guard !retired, isEditable, markedTextRange == nil, compositionCompletion == nil,
              let session = editingSession, session.isEditable else { return false }
        session.setNativeSelection(paperSelection)
        return session.handleNativeListIndent(backward: backward)
    }
    /// A drag holding tables carries each as rows of tab-separated cells.
    func textDraggableView(_ textDraggableView: UIView & UITextDraggable, itemsForDrag dragRequest: UITextDragRequest) -> [UIDragItem] {
        guard let visible = paper.tables.readable(textStorage, range: viewRange(dragRequest.dragRange)) else {
            return dragRequest.suggestedItems
        }
        return [UIDragItem(itemProvider: NSItemProvider(object: visible))]
    }
    override func copy(_ sender: Any?) {
        guard let visible = paper.tables.readable(textStorage, range: selectedRange) else { return super.copy(sender) }
        var item: [String: Any] = [UTType.utf8PlainText.identifier: visible.string]
        if let rtf = try? visible.data(from: NSRange(location: 0, length: visible.length),
                                       documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            item[UTType.rtf.identifier] = rtf
        }
        copyPasteboard.items = [item]
    }
    /// Where Copy writes; tests use a private pasteboard.
    var copyPasteboard: UIPasteboard = .general
    override func deleteBackward() {
        if !retired, isEditable, markedTextRange == nil, compositionCompletion == nil,
           selectedRange.length == 0, selectedRange.location == 0,
           let session = editingSession, session.isEditable {
            session.setNativeSelection(paperSelection)
            if session.handleNativeEdgeDeletion(backward: true) { return }
        }
        super.deleteBackward()
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.count == 1, let key = presses.first?.key,
           key.charactersIgnoringModifiers == "\t",
           key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty,
           changeListDepth(backward: key.modifierFlags.contains(.shift)) { return }
        super.pressesBegan(presses, with: event)
    }
    fileprivate var pasteCommand: RelayNativePasteCommand?
    fileprivate var structuredPasteIntake: RelayMarkPasteIntake?
    private var dispatchingStructuredPaste = false
    var onImageInputFailure: ((String) -> Void)? = nil
    var onBeginImageInput: ((NSRange, String, String) -> RelayMarkImageIntake?)?
    var onBeginImageBatchInputs: ((NSRange, [RelayMarkImageFile]) -> [RelayMarkImageIntake]?)?
    var onBeginStructuredPaste: ((NSRange, Int, String?) -> RelayMarkPasteIntake?)?
    var onPaperButton: ((Int) -> Bool)?
    var onTaskCheckbox: ((Int) -> Bool)?
    /// The session changed outside TextKit's own editing; the coordinator shows it.
    var onSessionEdit: (() -> Void)?
    /// The view entered a window, where it can take keyboard focus.
    var onMovedToWindow: (() -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        adoptHeaderHost()
        onMovedToWindow?()
    }

    // MARK: A host's header above the text, in this view's own scroll

    /// The space above the text without a header.
    var baseTopInset: CGFloat = 20 { didSet { updateTopInset() } }
    private(set) weak var header: RelayMarkEditorHeader?
    private var headerContainer: HeaderContainer?
    /// The header's laid-out view, for accessibility order and tests.
    var headerView: UIView? { headerContainer == nil ? nil : header?.host?.view }
    var headerHeight: CGFloat { headerContainer == nil ? 0 : header?.height ?? 0 }

    /// Lays the header out at the top of the scroll content, across the visible width.
    /// The text starts below it and moves with the header's own height changes.
    func attach(header next: RelayMarkEditorHeader?) {
        guard next !== header || (next != nil && headerContainer == nil) else { return }
        // Only a header still shown here is released: a text view replacing this one
        // may have taken it over already.
        if let header, let host = header.host, headerContainer != nil, host.view.superview === headerContainer {
            host.view.removeFromSuperview()
            if host.parent != nil { host.willMove(toParent: nil); host.removeFromParent() }
            header.onHeightChange = nil
        }
        headerContainer?.removeFromSuperview(); headerContainer = nil
        header = next
        defer { updateTopInset() }
        guard let next else { return }
        let host = next.hostingController()
        // A header shown by another text view moves here with its state.
        if host.parent != nil { host.willMove(toParent: nil); host.removeFromParent() }
        host.view.removeFromSuperview()
        // Frames, not constraints: typing and scrolling change the content size and
        // offset, and neither may lay the header out again.
        let container = HeaderContainer()
        host.view.translatesAutoresizingMaskIntoConstraints = true
        container.addSubview(host.view)
        // Using the header ends typing, as a tap outside the text does: the keyboard
        // changing under a menu or sheet would otherwise scroll back to the caret.
        let tap = UITapGestureRecognizer(target: self, action: #selector(endTypingFromHeader))
        tap.cancelsTouchesInView = false
        tap.delegate = container
        container.addGestureRecognizer(tap)
        addSubview(container)
        headerContainer = container
        next.onHeightChange = { [weak self] in self?.updateTopInset(); self?.setNeedsLayout() }
        layOutHeader()
        adoptHeaderHost()
    }

    private func layOutHeader() {
        guard let headerContainer, let view = header?.host?.view else { return }
        let frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        guard headerContainer.frame != frame || view.frame != headerContainer.bounds else { return }
        headerContainer.frame = frame
        view.frame = headerContainer.bounds
    }

    /// The header presents its own sheets and menus from the nearest view controller.
    private func adoptHeaderHost() {
        guard headerContainer != nil, let host = header?.host, host.parent == nil, window != nil,
              let parent = sequence(first: next, next: { $0?.next }).lazy.compactMap({ $0 as? UIViewController }).first else { return }
        parent.addChild(host)
        host.didMove(toParent: parent)
    }

    private func updateTopInset() {
        let top = baseTopInset + headerHeight
        if textContainerInset.top != top { textContainerInset.top = top }
    }

    /// The header takes its own taps and presses; the text's selection gestures
    /// begin only over the text. Scrolling starts anywhere.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        if let container = headerContainer, recognizer !== panGestureRecognizer,
           container.frame.contains(recognizer.location(in: self)) { return false }
        return super.gestureRecognizerShouldBegin(recognizer)
    }

    @objc private func endTypingFromHeader() { if isFirstResponder { _ = resignFirstResponder() } }

    /// Holds the header; its tap shares the header's touches.
    final class HeaderContainer: UIView, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
    @objc func handleTaskTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, !retired, markedTextRange == nil,
              let onPaperButton, let range = characterRange(at: gesture.location(in: self)) else { return }
        _ = onPaperButton(offset(from: beginningOfDocument, to: range.start))
    }
    private func receiveImageProviders(_ providers: [NSItemProvider], range: NSRange) -> Bool {
        guard providers.contains(where: { $0.registeredTypeIdentifiers.contains(where: { RelayNativeImageRepresentation.isImage($0) }) }) else { return false }
        if providers.count > 1 {
            guard providers.count <= 4096 else { onImageInputFailure?(String(localized: "Too many images in this input. No item was inserted.", bundle: .module, comment: "Shown when a paste or drop holds more images than the paper accepts.")); return true }
            var files: [RelayMarkImageFile] = [], identifiers: [String] = []
            for provider in providers {
                guard let identifier = provider.registeredTypeIdentifiers.first(where: { imagePolicy.mime($0) != nil }),
                      let mime = imagePolicy.mime(identifier) else {
                    onImageInputFailure?(String(localized: "Every item must be a supported image. No subset was inserted.", bundle: .module, comment: "Shown when some pasted or dropped items are not supported images.")); return true
                }
                files.append(.init(filename: RelayNativeImageRepresentation.filename(provider.suggestedName, identifier: identifier), contentType: mime))
                identifiers.append(identifier)
            }
            guard let intakes = onBeginImageBatchInputs?(range, files), intakes.count == providers.count else { return true }
            for (index, provider) in providers.enumerated() {
                provider.loadDataRepresentation(forTypeIdentifier: identifiers[index]) { bytes, _ in
                    Task { @MainActor in intakes[index].receive(bytes) }
                }
            }
            return true
        }
        guard let provider = providers.first else { return true }
        guard let identifier = provider.registeredTypeIdentifiers.first(where: { imagePolicy.mime($0) != nil }) else {
            onImageInputFailure?(String(localized: "This image type is not supported. No image was inserted.", bundle: .module, comment: "Shown when a pasted or dropped image type is not supported.")); return true
        }
        guard let mime = imagePolicy.mime(identifier),
              let intake = onBeginImageInput?(range, RelayNativeImageRepresentation.filename(provider.suggestedName, identifier: identifier), mime)
        else { return true }
        provider.loadDataRepresentation(forTypeIdentifier: identifier) { bytes, _ in
            Task { @MainActor in intake.receive(bytes) }
        }
        return true
    }
    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, proposalForDrop drop: UITextDropRequest) -> UITextDropProposal {
        let providers = drop.dropSession.items.map(\.itemProvider)
        guard providers.contains(where: { $0.registeredTypeIdentifiers.contains(where: { RelayNativeImageRepresentation.isImage($0) }) })
        else { return drop.suggestedProposal }
        let allowed = !retired && isEditable && markedTextRange == nil && compositionCompletion == nil && !providers.isEmpty && providers.count <= 4096 &&
            providers.allSatisfy({ $0.registeredTypeIdentifiers.contains(where: { imagePolicy.mime($0) != nil }) })
        let proposal = UITextDropProposal(operation: allowed ? .copy : .cancel)
        proposal.dropPerformer = .delegate
        proposal.useFastSameViewOperations = false
        return proposal
    }
    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, willPerformDrop drop: UITextDropRequest) {
        guard !retired, isEditable, markedTextRange == nil, compositionCompletion == nil else { return }
        let providers = drop.dropSession.items.map(\.itemProvider)
        guard providers.contains(where: { $0.registeredTypeIdentifiers.contains(where: { RelayNativeImageRepresentation.isImage($0) }) }) else { return }
        let range = NSRange(location: offset(from: beginningOfDocument, to: drop.dropPosition), length: 0)
        guard NSMaxRange(range) <= viewLength, !paper.tables.touchesTableLine(range) else { return }
        selectedRange = range
        _ = receiveImageProviders(providers, range: range)
    }
    override func paste(_ sender: Any?) {
        guard !retired, isEditable, markedTextRange == nil, compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange) <= viewLength else { return }
        // Plain clipboard text becomes one windowed command.
        let pasteboard = UIPasteboard.general
        if let session = editingSession, let value = pasteboard.string,
           !pasteboard.contains(pasteboardTypes: [UTType.html.identifier, UTType.rtf.identifier, UTType.flatRTFD.identifier]),
           !pasteboard.hasImages, session.pastePlainTextNatively(range: paperSelection, text: value) {
            onSessionEdit?()
            return
        }
        guard let baseline = paperValue() else { return }
        pasteCommand = RelayNativePasteCommand(baseline: baseline, range: paperSelection)
        if UIPasteboard.general.contains(pasteboardTypes: [UTType.html.identifier]) {
            receiveHTMLProviders(UIPasteboard.general.itemProviders, plainText: pasteboard.string)
        } else {
            structuredPasteIntake = nil
            if receiveImageProviders(UIPasteboard.general.itemProviders, range: selectedRange) { pasteCommand = nil; return }
            super.paste(sender)
        }
    }
    override func paste(itemProviders: [NSItemProvider]) {
        guard !retired, isEditable, markedTextRange == nil, compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange) <= viewLength, let baseline = paperValue() else { return }
        pasteCommand = RelayNativePasteCommand(baseline: baseline, range: paperSelection)
        if itemProviders.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.html.identifier) }) {
            receiveHTMLProviders(itemProviders)
            return
        }
        structuredPasteIntake = nil
        if receiveImageProviders(itemProviders, range: selectedRange) { pasteCommand = nil; return }
        super.paste(itemProviders: itemProviders)
    }
    private func receiveHTMLProviders(_ providers: [NSItemProvider], plainText: String? = nil) {
        // HTML never falls through UIKit's default converter. A mixed item list
        // remains on the clipboard intact; all-HTML delivery is ordered by slot.
        guard !providers.isEmpty, providers.allSatisfy({ $0.hasItemConformingToTypeIdentifier(UTType.html.identifier) }) else {
            onImageInputFailure?(String(localized: "Mixed clipboard representations cannot be inserted as a subset. No item was inserted.", bundle: .module, comment: "Shown when a paste mixes formatted and other items.")); return
        }
        guard let intake = onBeginStructuredPaste?(selectedRange, providers.count, plainText) else { return }
        for (index, provider) in providers.enumerated() {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.html.identifier) { bytes, _ in
                Task { @MainActor in intake.receive(bytes, at: index) }
            }
        }
    }
    override func toggleBoldface(_ sender: Any?) {
        guard !retired, isEditable, markedTextRange == nil, compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange) <= viewLength else { return }
        if toggleMark(.bold) { onSessionEdit?() }
    }
    override func toggleItalics(_ sender: Any?) {
        guard !retired, isEditable, markedTextRange == nil, compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange) <= viewLength else { return }
        if toggleMark(.italic) { onSessionEdit?() }
    }
    fileprivate let collaborationUndo = CollaborationUndoManager()
    weak var editingSession: (any RelayPaperTextEditing)?
    fileprivate var finalizerRegistration: UUID?
    private(set) var retired = false
    private var compositionGeneration = UUID()
    private var compositionCompletion: Task<Void, Never>?
    func cancelCompositionCompletion() {
        compositionGeneration = UUID()
        compositionCompletion?.cancel(); compositionCompletion = nil
    }
    func retireInput() {
        retired = true
        pasteCommand = nil
        onTaskCheckbox = nil
        onSessionEdit = nil
        cancelCompositionCompletion()
        onCompositionStart = nil; onCompositionEnd = nil; onDeclaredMarkedInput = nil
        collaborationUndo.undoAction = nil; collaborationUndo.redoAction = nil
    }
    func applyEmptyTypingStyle() {
        let selection = paperSelection
        if selection.length == 0, let block = paper.emptyBlocks.first(where: { $0.offset == selection.location }) {
            var attributes = NativeProseCodec.emptyAttributes(block.intent, inlineIntent: block.inlineIntent, link: block.link,
                typingStyle: block.typingStyle, listContext: paper.nativeLists)
            if let task = paper.taskItems.first(where: { $0.firstParagraphRange.location == block.offset }) {
                attributes[.paragraphStyle] = NativeProseCodec.emptyParagraphStyle(block.intent, checked: task.checked,
                    listContext: paper.nativeLists)
            }
            typingAttributes = attributes
        }
    }
    var onDeclaredMarkedInput: ((String?, NSRange, NSRange, NSRange?, Bool) -> Bool)?
    var onCompositionStart: (() -> Void)?
    var onCompositionEnd: (() -> Void)?
    override var undoManager: UndoManager? { collaborationUndo }
    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        guard !retired, isEditable else { return }
        pasteCommand = nil
        if markedTextRange == nil { cancelCompositionCompletion(); onCompositionStart?() }
        if let onDeclaredMarkedInput {
            guard let target = markedTextRange ?? selectedTextRange else { return }
            let start = offset(from: beginningOfDocument, to: target.start)
            let end = offset(from: beginningOfDocument, to: target.end)
            guard start >= 0, end >= start,
                  onDeclaredMarkedInput(markedText, NSRange(location: start, length: end - start),
                    selectedRange, nil, false) else { return }
        }
        super.setMarkedText(markedText, selectedRange: selectedRange)
    }
    override func unmarkText() {
        let wasMarked = markedTextRange != nil
        super.unmarkText()
        if wasMarked, !retired {
            let generation = compositionGeneration
            compositionCompletion = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, !self.retired, generation == self.compositionGeneration, self.markedTextRange == nil else { return }
                self.compositionCompletion = nil
                self.onCompositionEnd?()
            }
        }
    }
    func viewRange(_ range: UITextRange) -> NSRange {
        let start = offset(from: beginningOfDocument, to: range.start)
        return NSRange(location: start, length: offset(from: range.start, to: range.end))
    }
    /// Find in paper searches the paper's text, table cells included.
    private let search = RelayPaperTextSearch()
    private var paperFind: UIFindInteraction?
    func installFind() {
        search.view = self
        let interaction = UIFindInteraction(sessionDelegate: search)
        addInteraction(interaction)
        paperFind = interaction
    }
    override var findInteraction: UIFindInteraction? { paperFind ?? super.findInteraction }
    override func find(_ sender: Any?) { paperFind?.presentFindNavigator(showingReplace: false) }
    override func findNext(_ sender: Any?) { paperFind?.findNext() }
    override func findPrevious(_ sender: Any?) { paperFind?.findPrevious() }
    override func insertText(_ text: String) {
        guard !retired, isEditable else { return }
        if (markedTextRange != nil || compositionCompletion != nil), let onDeclaredMarkedInput {
            guard let target = markedTextRange ?? selectedTextRange else { return }
            let start = offset(from: beginningOfDocument, to: target.start)
            let end = offset(from: beginningOfDocument, to: target.end)
            guard start >= 0, end >= start,
                  onDeclaredMarkedInput(text, NSRange(location: start, length: end - start), selectedRange, nil, true) else { return }
        }
        super.insertText(text)
    }
    override func textViewportLayoutControllerDidLayout(_ controller: NSTextViewportLayoutController) {
        super.textViewportLayoutControllerDidLayout(controller)
        viewportDidLayout(controller)
        onContentLayoutChange?()
    }

    nonisolated func textContentManager(_ textContentManager: NSTextContentManager, shouldEnumerate textElement: NSTextElement,
                                        options: NSTextContentManager.EnumerationOptions) -> Bool {
        nonisolated(unsafe) let element = textElement
        return MainActor.assumeIsolated { paperShows(element) }
    }

}
#endif

/// Coalesces TextKit/layout notifications without invalidating SwiftUI again when
/// only the viewport moved. Measurement never replaces text or finalizes marked input.
@MainActor private final class RelayEditorContentLayout {
    private var pending: Task<Void, Never>?
    private var height: CGFloat?
    private var viewportRevision: Int?
    private var pendingReveal: Task<Void, Never>?

    func viewportDidChange(layout: RelayMarkEditorLayout, revision: Int, reveal: @escaping () -> Void) {
        guard layout == .content else {
            viewportRevision = nil
            pendingReveal?.cancel(); pendingReveal = nil
            return
        }
        guard viewportRevision != revision else { return }
        viewportRevision = revision
        pendingReveal?.cancel()
        pendingReveal = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            pendingReveal = nil
            reveal()
        }
    }

    func schedule(measure: @escaping () -> CGFloat?, changed: @escaping () -> Void) {
        guard pending == nil else { return }
        pending = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            defer { pending = nil }
            guard let next = measure(), next != height else { return }
            height = next
            changed()
        }
    }
}

/// Converts canonical UTF-16 ranges to TextKit ranges. Rectangles, when needed
/// by system integrations, come directly from enumerateTextSegments. No layout is
/// requested here, and no line, glyph, marker or caret geometry is synthesized.
@MainActor
struct RelayTextKitRanges {
    let manager: NSTextLayoutManager
    let content: NSTextContentManager
    let storage: NSTextStorage

    init?(_ manager: NSTextLayoutManager?) {
        guard let manager, let content = manager.textContentManager,
              let storage = (content as? NSTextContentStorage)?.textStorage else { return nil }
        self.manager = manager; self.content = content; self.storage = storage
    }

    var length: Int { storage.length }

    func location(_ offset: Int) -> (any NSTextLocation)? {
        guard offset >= 0, offset <= length else { return nil }
        return content.location(content.documentRange.location, offsetBy: offset)
    }

    func offset(_ location: any NSTextLocation) -> Int {
        content.offset(from: content.documentRange.location, to: location)
    }

    func textRange(_ range: NSRange) -> NSTextRange? {
        guard let start = location(range.location), let end = location(NSMaxRange(range)) else { return nil }
        return NSTextRange(location: start, end: end)
    }

    func range(_ textRange: NSTextRange) -> NSRange {
        let start = offset(textRange.location)
        return NSRange(location: start, length: max(0, offset(textRange.endLocation) - start))
    }

    func segmentFrames(_ range: NSRange) -> [CGRect] {
        guard let textRange = textRange(range) else { return [] }
        var frames: [CGRect] = []
        manager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            frames.append(frame); return true
        }
        return frames
    }

    func characterFrame(at offset: Int) -> CGRect? {
        guard offset >= 0, offset < length else { return nil }
        return segmentFrames(NSRange(location: offset, length: 1)).first
    }

}

extension RelayPaperTextView {
    /// Whether TextKit lays out a paragraph: not when it starts inside a folded section.
    func paperShows(_ element: NSTextElement) -> Bool {
        guard !paper.hidden.isEmpty, let range = element.elementRange, let content = textLayoutManager?.textContentManager else { return true }
        return !paper.isHidden(content.offset(from: content.documentRange.location, to: range.location))
    }

    /// The heading paragraph holding a view offset, as the view range of its text.
    /// Read from the view's own attributes, so it costs the same at any paper length.
    func headingParagraph(at location: Int) -> NSRange? {
        let storage = paperStorage, text = storage.string as NSString
        guard location >= 0, location <= text.length else { return nil }
        let paragraph = text.paragraphRange(for: NSRange(location: min(location, text.length), length: 0))
        let content = NSRange(location: paragraph.location,
                              length: paragraph.length - (NSMaxRange(paragraph) > paragraph.location &&
                                  text.character(at: NSMaxRange(paragraph) - 1) == 10 ? 1 : 0))
        let intent: PresentationIntent?
        if content.length > 0 {
            intent = (storage.attribute(.relayBlockIntent, at: content.location, effectiveRange: nil) as? RelayBlockIntent)?.intent
        } else {
            intent = paper.viewEmptyBlocks.first { $0.offset == content.location }?.intent
        }
        let heading = intent?.components.contains { if case .header = $0.kind { true } else { false } } == true
        return heading ? content : nil
    }

    /// The heading paragraphs that start in a view range.
    func headingParagraphs(in range: NSRange) -> [NSRange] {
        let text = paperStorage.string as NSString
        var result: [NSRange] = [], location = range.location
        while location <= min(NSMaxRange(range), text.length) {
            if let heading = headingParagraph(at: location) { result.append(heading) }
            guard location < text.length else { break }
            location = NSMaxRange(text.paragraphRange(for: NSRange(location: location, length: 0)))
        }
        return result
    }

    /// The destination name of the section whose heading starts at a view offset.
    func sectionID(atHeading location: Int) -> String? {
        let paper = paper.tables.paper(location)
        return editingSession?.sections.first { $0.heading.location == paper }?.id
    }

    /// The heading menu's entries for the section at the caret: fold or unfold it,
    /// and copy its link when the host gives sections links.
    func sectionMenuEntries(link: ((String) -> URL?)?) -> [(title: String, run: () -> Void)] {
        guard let section = sectionAtCaret, let session = editingSession else { return [] }
        let folded = session.foldedSections.contains(section.id)
        var entries: [(title: String, run: () -> Void)] = [(folded
            ? String(localized: "Expand section", bundle: .module, comment: "Heading menu command that shows a folded section.")
            : String(localized: "Collapse section", bundle: .module, comment: "Heading menu command that hides a section's content."),
            { [weak self] in _ = self?.toggleSection(section.id) })]
        if let url = link?(section.id) {
            entries.append((String(localized: "Copy link to this section", bundle: .module, comment: "Heading menu command that copies a link to the section."), {
                #if os(macOS)
                NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([url as NSURL])
                #else
                UIPasteboard.general.url = url
                #endif
            }))
        }
        return entries
    }

}

final class RelayTaskItemRun: NSObject {
    let entityID: String?
    let checked: Bool
    init(entityID: String?, checked: Bool) { self.entityID = entityID; self.checked = checked }
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RelayTaskItemRun else { return false }
        return entityID == other.entityID && checked == other.checked
    }
    override var hash: Int { (entityID?.hashValue ?? 0) ^ checked.hashValue }
}
