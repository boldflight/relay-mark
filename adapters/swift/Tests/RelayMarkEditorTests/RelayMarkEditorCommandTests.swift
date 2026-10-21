import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkProseProjection
import RelayMarkSwift
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The paper's editing commands are defined once, in `RelayMarkEditorCommand`,
/// and each Apple platform's surfaces list them. The suite runs through the
/// AppKit adapter on macOS and the UIKit adapter on iOS and visionOS.
@MainActor @Suite(.serialized)
struct RelayMarkEditorCommandTests {
    private func mount(_ markdown: String) throws -> (RelayMarkEditorSession, RelayMarkEditorView.TextCoordinator, CollaborationTextView) {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "commands"))
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        return (editor, coordinator, coordinator.makeTextView(accessibilityLabel: "Paper"))
    }

    // Bug caught: a mark the paper's schema has (underline) offered on one
    // platform and refused on another, or in no menu at all.
    @Test("Every mark in the paper's schema has a command")
    func everySchemaMarkHasACommand() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let schema = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appending(path: "spec/relaymark/editor-schema.json"))) as? [String: Any])
        let marks = try #require(schema["marks"] as? [[String: Any]]).compactMap { $0["name"] as? String }
        // A link is edited in its own sheet; AI authorship is provenance, never a command.
        let expected = Set(marks.filter { !["link", "ai_authored"].contains($0) }.map { "editor.mark.\($0)" })
        #expect(Set(RelayMarkEditorCommand.commands(in: .mark).map(\.id)) == expected)
    }

    // Bug caught: a command reachable from the Mac's menus but not from the
    // iPhone's edit menu, or the reverse.
    @Test("The text view's Format menu lists every command")
    func formatMenuListsEveryCommand() throws {
        let (_, coordinator, view) = try mount("Hello")
        #if os(macOS)
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try #require(coordinator.textView(view, menu: NSMenu(), for: event, at: 0))
        let format = try #require(menu.items.first { $0.title == RelayMarkEditorCommandMenu.title }?.submenu)
        let ids = format.items.compactMap { $0.identifier?.rawValue }
        #else
        let menu = try #require(coordinator.textView(view, editMenuForTextInRanges: [NSValue(range: NSRange(location: 0, length: 0))], suggestedActions: []))
        let format = try #require(menu.children.compactMap { $0 as? UIMenu }.first { $0.title == RelayMarkEditorCommandMenu.title })
        let ids = format.children.compactMap { $0 as? UIMenu }.flatMap(\.children).compactMap { ($0 as? UIAction)?.identifier.rawValue }
        #endif
        #expect(ids == RelayMarkEditorCommand.all.map(\.id))
    }

    enum UnderlineRoute: CaseIterable { case menu, systemAction, formattingPanel }

    // Bug caught: underline shown by TextKit but never saved, so the next render
    // drops it; or refused on one platform while another offers it.
    @Test("Underline from the menu, the system action and the panel is saved and survives a re-render",
          arguments: UnderlineRoute.allCases)
    func underlineIsSavedAndRendered(route: UnderlineRoute) throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("Hello world", namespace: "commands"))
        var saved: [RelayMarkLocalTransaction] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        defer { coordinator.retire(view) }
        let selection = NSRange(location: 0, length: 5)
        editor.setNativeSelection(selection)
        #if os(macOS)
        view.setSelectedRange(selection)
        #else
        view.selectedRange = selection
        #endif
        switch route {
        case .menu: editor.perform(try #require(RelayMarkEditorCommand.command(id: "editor.mark.underline")))
        #if os(macOS)
        case .systemAction: view.underline(nil)
        case .formattingPanel: return // The Mac has no formatting panel; its Font panel has no underline control.
        #else
        case .systemAction: view.toggleUnderline(nil)
        case .formattingPanel:
            let panel = UITextFormattingViewController(configuration: CollaborationTextView.formattingPanel)
            coordinator.textView(view, willBeginFormattingWith: panel)
            panel.delegate?.textFormattingViewController(panel, didChangeValue: .underline(true))
        #endif
        }
        #expect(editor.failure == nil && !saved.isEmpty)
        let projected = try document.richProseProjection().text
        let end = projected.characters.index(projected.startIndex, offsetBy: 5)
        #expect(projected[projected.startIndex..<end][RelayMarkOfferedMarksAttribute.self]?.contains(.underline) == true)
        coordinator.update(view)
        #if os(macOS)
        let storage = try #require(view.textStorage)
        #else
        let storage = view.textStorage
        #endif
        #expect(storage.attribute(.underlineStyle, at: 2, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
    }

    // Bug caught: underline applied to the view where the paper cannot hold it
    // (inside code), then dropped by the next render.
    @Test("The system's underline action is refused where the paper cannot hold it")
    func underlineInCodeIsRefused() throws {
        let (editor, _, view) = try mount("```\ncode here\n```")
        var refusals = 0
        let feedback = RelayPaperRefusal.feedback
        RelayPaperRefusal.feedback = { refusals += 1 }
        defer { RelayPaperRefusal.feedback = feedback }
        let selection = NSRange(location: 0, length: 4)
        editor.setNativeSelection(selection)
        #if os(macOS)
        view.setSelectedRange(selection)
        view.underline(nil)
        let storage = try #require(view.textStorage)
        #else
        view.selectedRange = selection
        view.toggleUnderline(nil)
        let storage = view.textStorage
        #endif
        #expect(refusals == 1)
        #expect(storage.attribute(.underlineStyle, at: 1, effectiveRange: nil) == nil)
    }
}
