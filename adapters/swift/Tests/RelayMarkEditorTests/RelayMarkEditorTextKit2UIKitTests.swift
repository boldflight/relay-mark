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

/// The UIKit editor shares the TextKit 2 stack: UITextView switches itself to
/// TextKit 1 for NSTextTable and NSTextBlock, so these paths must never use them.
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
        RelayMarkEditorView.TextCoordinator, CollaborationTextView) {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "uikit"))
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        view.layoutIfNeeded()
        let manager = try #require(view.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        return (editor, coordinator, view)
    }

    @Test func tablesArePreservedReadOnlyAttachmentsOnTextKit2() throws {
        let (editor, coordinator, view) = try mount()
        defer { coordinator.retire(view) }
        #expect(view.textLayoutManager != nil)
        #expect(view.text == "Before\n\u{FFFC}\nAfter")
        let table = try #require(view.paper.tables.spans.first?.table)
        #expect(table.cells.map(\.text.string) == ["Name", "Note", "left cell", "right cell", "lower left", "lower right"])
        #expect(table.grid.layout(width: 390).height > 0)
        let search = try #require(view.findInteraction?.delegate as? RelayPaperTextSearch)
        let match = (String(editor.text.characters) as NSString).range(of: "lower right")
        search.decorate(foundTextRange: RelayPaperTextRange(match), document: nil, usingStyle: .highlighted)
        #expect(search.decorations[match] == .highlighted)
        #expect(table.readable.string == "Name\tNote\nleft cell\tright cell\nlower left\tlower right")
        let ignored = coordinator.textView(view, writingToolsIgnoredRangesInEnclosingRange:
            NSRange(location: 0, length: (view.text as NSString).length)).map(\.rangeValue)
        #expect(ignored == [NSRange(location: 7, length: 1)])
    }

    /// The task-checkbox tap must not win over UITextView's own taps, or a tap
    /// in the paper never places the caret and the keyboard never appears.
    @Test func taskTapLeavesTheTextViewsOwnTapsWorking() throws {
        let (_, coordinator, view) = try mount()
        defer { coordinator.retire(view) }
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
