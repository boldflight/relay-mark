import Foundation
@testable import RelayMarkEditor
@testable import RelayMarkEditorCore
import Testing
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkSwift
#if os(iOS)
import UIKit
import UniformTypeIdentifiers

/// The paper stays on TextKit 2; each table has an isolated native TextKit 1 view.
@MainActor @Suite(.serialized)
struct RelayMarkEditorTextKit2UIKitTests {
    private let markdown = """
    Before

    | Name | Note |
    | --- | --- |
    | left cell | right cell |
    | lower left | lower right |

    After
    """

    private func mount() throws -> (RelayMarkEditorSession,
        RelayMarkEditorView.TextCoordinator, CollaborationTextView, UIWindow) {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "uikit"))
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        let window = UIWindow(frame: view.frame)
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(view)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        view.layoutIfNeeded()
        let manager = try #require(view.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        manager.textViewportLayoutController.layoutViewport()
        view.layoutIfNeeded()
        return (editor, coordinator, view, window)
    }

    private func retire(_ coordinator: RelayMarkEditorView.TextCoordinator,
                        _ view: CollaborationTextView, _ window: UIWindow) {
        window.endEditing(true)
        coordinator.retire(view)
        window.isHidden = true
        window.rootViewController = nil
    }

    @Test func nativeTableEditorsDoNotDowngradeThePaper() throws {
        let (editor, coordinator, view, window) = try mount()
        defer { retire(coordinator, view, window) }
        #expect(view.textLayoutManager != nil)
        #expect(view.text == "Before\n\u{FFFC}\nAfter")
        let table = try #require(view.paper.tables.spans.first?.table)
        #expect(table.cells.map(\.text.string) == ["Name", "Note", "left cell", "right cell", "lower left", "lower right"])
        #expect(table.grid.layout(width: 390).height > 0)
        #expect(table.grid.textView.textLayoutManager == nil)
        #expect(view.textLayoutManager != nil)
        let search = try #require(view.findInteraction?.delegate as? RelayPaperTextSearch)
        let match = (String(editor.text.characters) as NSString).range(of: "lower right")
        search.decorate(foundTextRange: RelayPaperTextRange(match), document: nil, usingStyle: .highlighted)
        #expect(search.decorations[match] == .highlighted)
        #expect(table.readable.string == "Name\tNote\nleft cell\tright cell\nlower left\tlower right")
        let ignored = coordinator.textView(view, writingToolsIgnoredRangesInEnclosingRange:
            NSRange(location: 0, length: (view.text as NSString).length)).map(\.rangeValue)
        #expect(ignored == [NSRange(location: 7, length: 1)])
    }

    @Test func nativeTableTypingAndUndoUseTheSharedSession() throws {
        let (editor, coordinator, view, window) = try mount()
        defer { retire(coordinator, view, window) }
        let table = try #require(view.paper.tables.spans.first?.table)
        table.grid.layout(width: 390)
        let native = table.grid.textView
        try #require(native.window === window)
        try #require(native.isEditable)
        try #require(table.editing?.isEditable == true)
        try #require(table.grid.projection.supportsEditing)
        try #require(native.becomeFirstResponder())
        let before = String(editor.text.characters)
        let start = (before as NSString).range(of: "right cell").location + 5
        native.selectedRange = try #require(table.grid.projection.nativeRange(forPaper: NSRange(location: start, length: 0)))
        native.insertText(" edited")
        coordinator.update(view)
        #expect(editor.failure == nil)
        #expect(String(editor.text.characters).contains("right edited cell"))
        #expect(native.text.contains("right edited cell"))
        #expect(view.textLayoutManager != nil && native.textLayoutManager == nil)
        try #require(native.undoManager).undo()
        coordinator.update(view)
        #expect(String(editor.text.characters) == before)
        #expect(native.text.contains("right cell") && !native.text.contains("edited"))
    }

    @Test(arguments: ["replace", "delete", "return"])
    func nativeTableInputOperationsPreserveCellsAndSharedUndo(operation: String) throws {
        let (editor, coordinator, view, window) = try mount()
        defer { retire(coordinator, view, window) }
        let table = try #require(view.paper.tables.spans.first?.table)
        table.grid.layout(width: 390)
        let native = table.grid.textView
        try #require(native.window === window && native.isEditable)
        try #require(native.becomeFirstResponder())
        let before = String(editor.text.characters)
        let cell = (before as NSString).range(of: "right cell")
        let selected = operation == "replace"
            ? NSRange(location: cell.location, length: 5)
            : NSRange(location: cell.location + 5, length: 0)
        native.selectedRange = try #require(table.grid.projection.nativeRange(forPaper: selected))
        let expected: String
        switch operation {
        case "replace":
            native.insertText("new")
            expected = (before as NSString).replacingCharacters(in: selected, with: "new")
        case "delete":
            native.deleteBackward()
            expected = (before as NSString).replacingCharacters(in: NSRange(location: selected.location - 1, length: 1), with: "")
        default:
            native.insertText("\n")
            expected = (before as NSString).replacingCharacters(in: selected, with: "\n")
        }
        coordinator.update(view)
        #expect(editor.failure == nil)
        #expect(String(editor.text.characters) == expected)
        #expect(table.cells.count == 6)
        #expect(view.textLayoutManager != nil && native.textLayoutManager == nil)
        try #require(native.undoManager).undo()
        coordinator.update(view)
        #expect(String(editor.text.characters) == before)
        #expect(table.cells.count == 6)
        #expect(native.text.contains("right cell"))
    }

    /// The task-checkbox tap must not win over UITextView's own taps, or a tap
    /// in the paper never places the caret and the keyboard never appears.
    @Test func taskTapLeavesTheTextViewsOwnTapsWorking() throws {
        let (_, coordinator, view, window) = try mount()
        defer { retire(coordinator, view, window) }
        let recognizers = view.gestureRecognizers ?? []
        let task = try #require(recognizers.first { $0.name == RelayMarkEditorView.taskTapName })
        let others = recognizers.filter { $0 !== task }
        #expect(!others.isEmpty)
        for other in others {
            #expect(task.delegate?.gestureRecognizer?(task, shouldRecognizeSimultaneouslyWith: other) == true)
        }
    }

}
#endif
