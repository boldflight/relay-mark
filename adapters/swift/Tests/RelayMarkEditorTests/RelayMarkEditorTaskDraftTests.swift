import Foundation
@testable import RelayMarkEditor
@testable import RelayMarkNativeCollaboration
import RelayMarkModel
import Testing
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Checklist items a person starts become draft Tasks (M10), decided by
/// relaymark-core's task_draft jobs and typed through the platform's text view.
@MainActor @Suite(.serialized)
struct RelayMarkEditorTaskDraftTests {
    @MainActor private final class Paper {
        let editor: RelayMarkEditorSession
        let coordinator: RelayMarkEditorView.TextCoordinator
        let view: CollaborationTextView
        #if !os(macOS)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        #endif
        var finished: [RelayTaskDraft] = []

        init(_ blocks: [[String: Any]]) throws {
            let bridge = try PMYXmlBridge.canonical()
            var next = 0
            func identify(_ node: [String: Any]) -> [String: Any] {
                var node = node
                if let type = node["type"] as? String, type != "text" {
                    next += 1
                    var attrs = node["attrs"] as? [String: Any] ?? [:]
                    attrs["relaymarkId"] = String(format: "b%012x40008%015x", next, next)
                    node["attrs"] = attrs
                }
                if let content = node["content"] as? [[String: Any]] { node["content"] = content.map(identify) }
                return node
            }
            let slice = try PMSlice.fromJSON(["content": blocks.map(identify)], schema: bridge.schema)
            let doc = try bridge.schema.topNodeType.create(["relaymark": [String: Any]()], slice.content)
            editor = try RelayMarkEditorSession(document: try RelayMarkNativeDocument().scratch(tree: bridge.snapshot(doc)), persist: { _ in })
            coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
            view = coordinator.makeTextView(accessibilityLabel: "Paper")
            #if !os(macOS)
            window.addSubview(view); view.frame = window.bounds; window.isHidden = false
            #endif
            editor.createsTaskDrafts = true
            editor.onTaskDraftsFinished = { [unowned self] in finished += $0 }
        }

        func place(_ offset: Int, length: Int = 0) {
            editor.setNativeSelection(NSRange(location: offset, length: length))
            #if os(macOS)
            view.setSelectedRange(NSRange(location: offset, length: length))
            #else
            view.selectedRange = NSRange(location: offset, length: length)
            #endif
        }

        /// Types each character as the keyboard does, Return included.
        func type(_ text: String) {
            for character in text {
                let caret = editor.nativeSelection ?? NSRange(location: 0, length: 0)
                #if os(macOS)
                view.setSelectedRange(caret)
                view.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
                #else
                view.selectedRange = caret
                if coordinator.textView(view, shouldChangeTextInRanges: [NSValue(range: caret)], replacementText: String(character)) {
                    view.insertText(String(character))
                }
                #endif
            }
        }

        var titles: [String] { editor.nativeTaskItems.map(\.firstParagraphText) }
        var armedTitles: [String] { editor.nativeTaskItems.filter { editor.armedTaskDrafts.contains($0.id) }.map(\.firstParagraphText) }

        func retire() { coordinator.retire(view) }
    }

    // Bug caught: Apple checklists staying plain checkboxes, or Return creating
    // the item being typed instead of the one it finished.
    @Test("A typed checklist arms its item; Return finishes it and arms the next")
    func typedChecklistAndReturn() throws {
        let paper = try Paper([["type": "paragraph"]]); defer { paper.retire() }
        paper.place(0)
        paper.type("[ ] Call Ana")
        #expect(paper.editor.failure == nil)
        #expect(paper.armedTitles == ["Call Ana"] && paper.finished.isEmpty)
        paper.type("\nBuy")
        #expect(paper.finished.map(\.title) == ["Call Ana"])
        let call = try #require(paper.finished.first)
        #expect(call.operationID.count == 36 && call.blockID.dropFirst() == call.operationID.replacingOccurrences(of: "-", with: ""))
        #expect(paper.armedTitles == ["Buy"])
    }

    // Bug caught: converting a pasted list with the Checklist command creating a Task per line.
    @Test("The Checklist command arms a new empty item but never a converted line")
    func commandArmsOnlyEmptyItems() throws {
        let paper = try Paper([["type": "paragraph", "content": [["type": "text", "text": "Call Ana"]]],
                               ["type": "paragraph", "content": [["type": "text", "text": "Buy milk"]]],
                               ["type": "paragraph"]])
        defer { paper.retire() }
        let checklist = try #require(RelayMarkEditorCommand.command(id: "editor.list.task"))
        paper.place(3)
        paper.editor.perform(checklist)
        #expect(paper.titles == ["Call Ana"] && paper.editor.armedTaskDrafts.isEmpty)
        paper.place(String(paper.editor.text.characters).utf16.count)
        paper.editor.perform(checklist)
        #expect(paper.titles == ["Call Ana", ""] && paper.armedTitles == [""])
    }

    // Bug caught: leaving a draft by tapping elsewhere, or ticking it, never creating its Task.
    @Test("Leaving an armed draft or ticking it finishes it; a remote edit does not")
    func leavingAndTicking() throws {
        let paper = try Paper([["type": "paragraph", "content": [["type": "text", "text": "Notes"]]], ["type": "paragraph"]])
        defer { paper.retire() }
        paper.place(6)
        paper.type("[ ] Call Ana")
        let item = try #require(paper.editor.nativeTaskItems.first)
        // Placing the caret at the same item again, as a peer's update restores it, finishes nothing.
        paper.place(NSMaxRange(item.firstParagraphRange))
        #expect(paper.finished.isEmpty)
        paper.place(2)
        #expect(paper.finished.map(\.title) == ["Call Ana"] && paper.editor.armedTaskDrafts.isEmpty)
        paper.editor.armTaskDrafts([item.id])
        #expect(paper.editor.toggleTaskItem(atUTF16: item.firstParagraphRange.location))
        #expect(paper.finished.map(\.done) == [false, true])
    }

    /// The Yjs anchor task creation sends: y-prosemirror's positions, with the
    /// same association, for a plain title and one ending in a reference. With
    /// RELAYMARK_TASK_ANCHOR_FIXTURE set it writes the document and anchors for
    /// the server's own resolution test in relay-elixir.
    @Test("A task title anchor spans its first paragraph as the web's does")
    func titleAnchor() throws {
        let reference: [String: Any] = ["type": "relayReference", "attrs": ["entityType": "Person",
            "entityId": "5b0f3c1e-6a7d-4e8f-9a0b-1c2d3e4f5a6b", "label": "Ana",
            "source": "[[Person: 5b0f3c1e-6a7d-4e8f-9a0b-1c2d3e4f5a6b | Ana]]"]]
        let paper = try Paper([["type": "taskList", "content": [
            ["type": "taskItem", "content": [["type": "paragraph", "content": [["type": "text", "text": "Call Ana"]]]]],
            ["type": "taskItem", "content": [["type": "paragraph", "content": [["type": "text", "text": "Email "], reference]]]]]]])
        defer { paper.retire() }
        let items = paper.editor.nativeTaskItems
        #expect(items.count == 2)
        var anchors: [[String: Any]] = []
        for item in items {
            let anchor = try paper.editor.document.taskTitleAnchor(itemPath: item.path)
            // Yjs and Yrs both give the start of a text its type, not an item.
            #expect(anchor.from["assoc"] as? Int == -1 && anchor.from["type"] != nil)
            anchors.append(["block_id": item.id, "placement": "inside", "expected_text": item.firstParagraphText,
                            "range": ["from": anchor.from, "to": anchor.to]])
        }
        // A title ending in a reference ends at its paragraph's own end, as y-prosemirror's does.
        let trailing = try #require(anchors.last?["range"] as? [String: Any])
        #expect((trailing["to"] as? [String: Any])?["type"] != nil && (trailing["to"] as? [String: Any])?["assoc"] as? Int == 0)
        if let path = ProcessInfo.processInfo.environment["RELAYMARK_TASK_ANCHOR_FIXTURE"] {
            let fixture: [String: Any] = ["update_base64": try paper.editor.document.encodeUpdate().base64EncodedString(), "anchors": anchors]
            try JSONSerialization.data(withJSONObject: fixture, options: [.prettyPrinted, .sortedKeys]).write(to: URL(filePath: path))
        }
    }
}
