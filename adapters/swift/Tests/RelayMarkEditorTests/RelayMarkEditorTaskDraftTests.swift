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
        let window = relayTestWindow(width: 390)
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

    // Bug caught: a checkbox tap while composing Japanese neither ticking the
    // item nor finishing the draft, so the Task is never created (Douglas, M10).
    @Test("A checkbox tap during IME composition commits the title and finishes the draft")
    func checkboxDuringComposition() throws {
        let paper = try Paper([["type": "paragraph"]]); defer { paper.retire() }
        paper.place(0)
        paper.type("[ ] ")
        let item = try #require(paper.editor.nativeTaskItems.first)
        #expect(paper.armedTitles == [""])
        #if os(macOS)
        paper.view.setMarkedText("電話する", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #else
        paper.view.setMarkedText("電話する", selectedRange: NSRange(location: 4, length: 0))
        #endif
        #expect(paper.view.hasMarkedInput)
        #expect(paper.view.onTaskCheckbox?(item.firstParagraphRange.location) == true)
        #expect(paper.finished.map { ($0.title, $0.done) } .elementsEqual([("電話する", true)], by: ==))
        // The composition ended in the session; AppKit's own marked range is not read headless.
        #expect(paper.editor.activeComposition == nil && paper.editor.failure == nil)
    }

    // Bug caught: VoiceOver reading a draft and a linked Task as the same plain
    // line, so a person never hears which items become Tasks.
    @Test("VoiceOver hears whether the item at the caret is a draft or a linked Task")
    func accessibilityContent() throws {
        let paper = try Paper([["type": "paragraph", "content": [["type": "text", "text": "Notes"]]], ["type": "taskList", "content": [
            ["type": "taskItem", "attrs": ["checked": false, "entityId": "5b0f3c1e-6a7d-4e8f-9a0b-1c2d3e4f5a6b"],
             "content": [["type": "paragraph", "content": [["type": "text", "text": "Call Ana"]]]]],
            ["type": "taskItem", "attrs": ["checked": false],
             "content": [["type": "paragraph", "content": [["type": "text", "text": "Buy milk"]]]]]]]])
        defer { paper.retire() }
        func content() -> [String] { paper.view.accessibilityCustomContent.map { "\($0.label): \($0.value)" } }
        let items = paper.editor.nativeTaskItems
        paper.place(items[0].firstParagraphRange.location + 2)
        #expect(content() == ["Checklist item: Task"])
        paper.place(NSMaxRange(items[1].firstParagraphRange))
        #expect(content().isEmpty)
        paper.editor.armTaskDrafts([items[1].id])
        #expect(content() == ["Checklist item: Draft task"])
        paper.place(0)
        #expect(content().isEmpty)
    }

    // Bug caught: a linked Task ticked by its host (the checkbox goes to the Task's own update,
    // and the paper changes afterwards) stayed drawn unticked until the paper was reopened.
    @Test("A checkbox the host ticks is drawn ticked at once")
    func hostTickedLinkedTaskIsDrawnTicked() throws {
        let paper = try Paper([["type": "taskList", "content": [
            ["type": "taskItem", "attrs": ["checked": false, "entityId": "5b0f3c1e-6a7d-4e8f-9a0b-1c2d3e4f5a6b"],
             "content": [["type": "paragraph", "content": [["type": "text", "text": "Call Ana"]]]]]]]])
        defer { paper.retire() }
        func drawnMarker() -> String? {
            paper.coordinator.update(paper.view)
            return paper.view.paperStorage.attribute(NSAttributedString.Key("RelayListMarker"), at: 0, effectiveRange: nil) as? String
        }
        #expect(drawnMarker() == "☐")
        let item = try #require(paper.editor.nativeTaskItems.first)
        // The host's command, after its domain action: the same call applyLinkedTaskToggle makes.
        _ = try paper.editor.toggleTaskItems(item)
        #expect(paper.editor.nativeTaskItems.map(\.checked) == [true])
        #expect(drawnMarker() == "☑")
        #expect(paper.view.paper.taskItems.map(\.checked) == [true])
    }

    // Bug caught: a checklist item made into a Task still drawn as a plain checkbox and text
    // (M11 C1), or its chip running into the next item or line.
    @Test("Each checklist item's whole title carries the item, a linked one its Task, and nothing around it does")
    func linkedItemTitleCarriesTaskChip() throws {
        let entity = "5b0f3c1e-6a7d-4e8f-9a0b-1c2d3e4f5a6b"
        let paper = try Paper([["type": "taskList", "content": [
            ["type": "taskItem", "attrs": ["checked": false, "entityId": entity],
             "content": [["type": "paragraph", "content": [["type": "text", "text": "Call "],
                                                           ["type": "text", "text": "Ana", "marks": [["type": "bold"]]]]]]],
            ["type": "taskItem", "attrs": ["checked": false],
             "content": [["type": "paragraph", "content": [["type": "text", "text": "Buy milk"]]]]]]],
            ["type": "paragraph", "content": [["type": "text", "text": "After"]]]])
        defer { paper.retire() }
        paper.coordinator.update(paper.view)
        let storage = paper.view.paperStorage, text = storage.string as NSString
        func items(_ word: String) -> [String] {
            let range = text.range(of: word)
            return (range.location..<NSMaxRange(range)).map {
                guard let item = storage.attribute(NSAttributedString.Key("RelayTaskItem"), at: $0, effectiveRange: nil) as? RelayTaskItemRun
                else { return "none" }
                return item.entityID ?? "plain"
            }
        }
        #expect(items("Call Ana") == Array(repeating: entity, count: 8))
        #expect(items("Buy milk") == Array(repeating: "plain", count: 8))
        #expect(items("After") == Array(repeating: "none", count: 5))
    }

    // Bug caught: a Task's status changed elsewhere never reaching its chip in an open paper,
    // or every local sync publish redrawing papers that show no chip.
    @Test("The host's Task status is read once per change, and a change costs nothing without chips")
    func linkedTaskStatusIsReadOncePerChange() throws {
        let paper = try Paper([["type": "taskList", "content": [
            ["type": "taskItem", "attrs": ["checked": false, "entityId": "5b0f3c1e-6a7d-4e8f-9a0b-1c2d3e4f5a6b"],
             "content": [["type": "paragraph", "content": [["type": "text", "text": "Call Ana"]]]]]]]])
        defer { paper.retire() }
        var reads = 0, shape = RelayMarkTaskGlyph.Shape.open
        paper.editor.linkedTaskStatus = { _, _ in reads += 1; return .init(shape, tint: .red) }
        let quiet = paper.editor.linkedTaskRevision
        paper.editor.linkedTasksChanged()
        #expect(paper.editor.linkedTaskRevision == quiet)
        let id = "5b0f3c1e-6a7d-4e8f-9a0b-1c2d3e4f5a6b"
        #expect(paper.editor.linkedTaskStatus(entityID: id, checked: false)?.shape == .open)
        #expect(paper.editor.linkedTaskStatus(entityID: id, checked: false)?.shape == .open)
        #expect(reads == 1)
        shape = .half
        paper.editor.linkedTasksChanged()
        #expect(paper.editor.linkedTaskRevision != quiet)
        #expect(paper.editor.linkedTaskStatus(entityID: id, checked: false)?.shape == .half)
        #expect(reads == 2)
    }

    // AppKit lays a headless view out without its paragraphs' indents, so only UIKit shows this.
#if !os(macOS)
    // Bug caught: on a Task paper's first open the paper's height settles after its first
    // draw, and UIKit scaled the stale drawing to the new size, so chips and glyphs rode up
    // over the lines above (M11 integration QA). A resize must redraw them for the new layout.
    @Test("Resizing the paper redraws its glyphs and chips instead of scaling the old drawing")
    func resizeRedrawsTaskDrawing() throws {
        let paper = try Paper([["type": "taskList", "content": [
            ["type": "taskItem", "attrs": ["checked": false, "entityId": "5b0f3c1e-6a7d-4e8f-9a0b-1c2d3e4f5a6b"],
             "content": [["type": "paragraph", "content": [["type": "text", "text": "Buy flowers"]]]]]]]])
        defer { paper.retire() }
        paper.coordinator.update(paper.view)
        paper.view.layoutIfNeeded()
        paper.view.layer.displayIfNeeded()
        #expect(!paper.view.layer.needsDisplay())
        paper.view.frame.size.height += 120
        #expect(paper.view.layer.needsDisplay(), "the old drawing would be stretched to the new size")
    }

    // Bug caught: the trailing empty draft's glyph drawn one indent too far right, over the
    // text of the item above it (M10 iPhone), or up into that item's chip (M11 Mac). It must
    // sit in the same column as the item's own, on the line below it.
    @Test("An empty trailing checklist item's glyph is drawn in its sibling's column, below it")
    func emptyDraftCheckboxAlignsWithItsSibling() throws {
        let paper = try Paper([["type": "taskList", "content": [
            ["type": "taskItem", "attrs": ["checked": true],
             "content": [["type": "paragraph", "content": [["type": "text", "text": "Buy candles"]]]]],
            ["type": "taskItem", "attrs": ["checked": false], "content": [["type": "paragraph"]]]]]])
        defer { paper.retire() }
        paper.coordinator.update(paper.view)
        paper.view.layoutIfNeeded()
        let geometry = try #require(RelayTextGeometry(paper.view.textLayoutManager))
        let item = try #require(paper.view.paper.taskItems.first)
        let block = try #require(paper.view.paper.emptyBlocks.first)
        let font = try #require(NativeProseCodec.emptyAttributes(block.intent)[.font] as? UIFont)
        let depth = try #require(NativeProseCodec.listMarker(block.intent)).depth
        let sibling = try #require(taskItemLayout(at: item.firstParagraphRange.location, geometry: geometry)?.glyph)
        let empty = try #require(taskGlyphFrame(at: block.offset, empty: true, headIndent: NativeProseCodec.taskIndent(font, depth: depth),
                                                font: font, gap: RelayTaskItemRun.textGap, geometry: geometry))
        #expect(abs(sibling.minX - empty.minX) < 1, "sibling \(sibling.minX), empty \(empty.minX)")
        #expect(empty.minY >= sibling.maxY, "the empty item's glyph clears the item above: \(empty.minY) < \(sibling.maxY)")
    }
#endif

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
