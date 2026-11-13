import Foundation
import Testing
@testable import RelayMarkEditor
@testable import RelayMarkEditorCore
import RelayMarkNativeCollaboration
import RelayMarkSwift
#if os(macOS)
import AppKit

@MainActor struct RelayMarkEditorListIdentityTests {
    @Test(arguments: [false, true])
    func partialFormattingKeepsOneNativeOrderedList(remote: Bool) throws {
        _ = NSApplication.shared
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            "7. First\n8. Second\n9. Third", namespace: "native-list-identity"))
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "List")
        defer { coordinator.retire(view) }
        func lists() throws -> [NSTextList] {
            try ["First", "Second", "Third"].map { title in
                let offset = (view.string as NSString).range(of: title).location
                let style = try #require(view.textStorage?.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
                return try #require(style.textLists.first)
            }
        }
        let before = try lists()
        #expect(before[0] === before[1] && before[1] === before[2])
        let beforeThird = try #require(view.textStorage?.itemNumber(in: before[2],
            at: (view.string as NSString).range(of: "Third").location))
        #expect(beforeThird == 3)
        let range = (view.string as NSString).range(of: "Second")
        if remote {
            let peer = RelayMarkNativeDocument()
            try peer.applyUpdate(document.encodeUpdate())
            var updates: [Data] = []
            let peerEditor = try RelayMarkEditorSession(document: peer, persist: { updates.append($0.update) })
            #expect(peerEditor.toggleMarkNatively(.bold, range: range))
            try editor.applyRemoteUpdate(try #require(updates.last))
        } else {
            #expect(editor.toggleMarkNatively(.bold, range: range))
        }
        coordinator.update(view)
        let after = try lists()
        #expect(after[0] === after[1] && after[1] === after[2])
        #expect(after[0].startingItemNumber == 7)
        let third = (view.string as NSString).range(of: "Third").location
        #expect(view.textStorage?.itemNumber(in: after[2], at: third) == beforeThird)
        editor.setNativeSelection(NSRange(location: 0, length: 0))
        try editor.applyListStart(12, review: editor.prepareListStartEdit())
        coordinator.update(view)
        let restarted = try lists()
        #expect(restarted[0] === restarted[1] && restarted[1] === restarted[2])
        #expect(restarted[0].startingItemNumber == 12 && after[0].startingItemNumber == 7)
        #expect(view.textStorage?.itemNumber(in: restarted[2], at: third) == beforeThird)
    }

    @Test func typingInAnInteriorEmptyCheckedTaskKeepsItsState() throws {
        _ = NSApplication.shared
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            "- [x] Done\n- [x] Checked\n- [ ] Next", namespace: "empty-checked-native-list"))
        // GFM does not import an empty checked marker as a task. Create the
        // valid canonical state by deleting only the checked item's text leaf.
        let projection = try document.richProseProjection()
        let title = (String(projection.text.characters) as NSString).range(of: "Checked")
        let position = try #require(projection.textPosition(replacing: title))
        _ = try document.deleteText(at: position.index, length: title.length, path: position.path)
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Tasks")
        defer { coordinator.retire(view) }
        let task = try #require(editor.nativeTaskItems.first { $0.checked && $0.firstParagraphRange.length == 0 })
        editor.setNativeSelection(task.firstParagraphRange)
        coordinator.update(view)
        let before = try #require(view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
        #expect(before.textLists.last?.markerFormat.rawValue == "☑")
        view.insertText("Title", replacementRange: view.selectedRange())
        #expect(editor.failure == nil)
        #expect(editor.nativeTaskItems.first { $0.firstParagraphRange.location == task.firstParagraphRange.location }?.checked == true)
        let after = try #require(view.textStorage?.attribute(.paragraphStyle, at: task.firstParagraphRange.location,
            effectiveRange: nil) as? NSParagraphStyle)
        #expect(after.textLists.last?.markerFormat.rawValue == "☑")
    }

    @Test func listContextsBelongToOneEditorAndResetForNewProjections() throws {
        func prose(_ start: Int) throws -> AttributedString {
            let document = RelayMarkNativeDocument()
            _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
                "\(start). First\n\(start + 1). Second", namespace: "list-context-lifetime"))
            return try document.richProseProjection().text
        }
        func firstList(_ value: AttributedString, _ context: NativeProseCodec.ListContext) throws -> NSTextList {
            let text = NativeProseCodec.attributed(value, listContext: context)
            return try #require((text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.textLists.first)
        }
        let value = try prose(7), a = NativeProseCodec.ListContext(), b = NativeProseCodec.ListContext()
        let first = try firstList(value, a), separate = try firstList(value, b)
        #expect(first !== separate)
        #expect(first === (try firstList(value, a)))
        a.reset()
        let replacement = try firstList(prose(3), a)
        #expect(replacement !== first && replacement.startingItemNumber == 3)
        #expect(first.startingItemNumber == 7, "assigned native attributes are immutable")
    }
}
#endif
