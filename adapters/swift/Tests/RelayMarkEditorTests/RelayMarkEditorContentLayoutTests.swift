import Foundation
import RelayMarkNativeCollaboration
import RelayMarkSwift
@testable import RelayMarkEditor
import Testing
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
struct RelayMarkEditorContentLayoutTests {
    private func session(_ source: String, persist: @escaping () -> Void = {}) throws -> RelayMarkEditorSession {
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "content-layout"))
        return try RelayMarkEditorSession(document: document, persist: { _ in persist() })
    }

    @Test("Content mode uses TextKit height, rewraps at the host width, and grows after edits")
    func naturalContentSize() throws {
        let owner = try session(String(repeating: "A wrapping paragraph with readable words. ", count: 20))
        let coordinator = RelayMarkEditorView.TextCoordinator(session: owner)
        var services = RelayMarkEditorServices(); services.layout = .content
        coordinator.services = services
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        defer { owner.invalidate(); coordinator.retire(view) }
        let container = CollaborationTextContainer(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        container.install(view); container.configure(services)
        let narrow = try #require(container.contentSize(at: 180))
        let wide = try #require(container.contentSize(at: 480))
        #expect(narrow.height > wide.height)
        #expect(wide.height > 0)
        #expect(view.textLayoutManager != nil)
        #if os(macOS)
        #expect(container.scrollView == nil)
        #expect(view.enclosingScrollView == nil)
        #else
        #expect(!view.isScrollEnabled)
        #endif
        owner.edit(AttributedString(String(repeating: "Another line\n", count: 80)))
        coordinator.update(view)
        let grown = try #require(container.contentSize(at: 480))
        #expect(grown.height > narrow.height)
        #expect(owner.failure == nil)
    }

    @Test("Changing scroll ownership preserves the native input client and marked text")
    func sizingPreservesComposition() throws {
        var writes = 0
        let owner = try session("Alpha", persist: { writes += 1 })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: owner)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        defer { owner.invalidate(); coordinator.retire(view) }
        let container = CollaborationTextContainer(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        container.install(view)
        container.configure(.init())
        #if os(macOS)
        #expect(container.scrollView != nil)
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #else
        #expect(view.isScrollEnabled)
        view.selectedRange = NSRange(location: 5, length: 0)
        view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0))
        #endif
        var services = RelayMarkEditorServices(); services.layout = .content
        container.configure(services)
        _ = container.contentSize(at: 180)
        _ = container.contentSize(at: 480)
        #expect(container.textView === view)
        #expect(view.hasMarkedInput)
        #expect(String(owner.text.characters) == "Alpha")
        #expect(writes == 0)
        #expect(view.textLayoutManager != nil)
    }

    @Test("An empty editor and a final empty paragraph retain their input height")
    func emptyAndFinalLine() throws {
        let owner = try session("")
        let coordinator = RelayMarkEditorView.TextCoordinator(session: owner)
        var services = RelayMarkEditorServices(); services.layout = .content
        coordinator.services = services
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        defer { owner.invalidate(); coordinator.retire(view) }
        let empty = view.contentHeight(at: 320)
        #expect(empty > 0)
        owner.edit(AttributedString("Line")); coordinator.update(view)
        let one = view.contentHeight(at: 320)
        owner.edit(AttributedString("Line\n")); coordinator.update(view)
        #expect(view.contentHeight(at: 320) > one)
    }

    @Test("Content sizing follows laid-out fonts and attachment bounds")
    func fontsAndAttachments() throws {
        let owner = try session("Text")
        let coordinator = RelayMarkEditorView.TextCoordinator(session: owner)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        defer { owner.invalidate(); coordinator.retire(view) }
        let before = view.contentHeight(at: 320)
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: 60)
        #else
        let font = UIFont.systemFont(ofSize: 60)
        #endif
        view.paperStorage.addAttribute(.font, value: font, range: NSRange(location: 0, length: 4))
        #expect(view.contentHeight(at: 320) > before)
        let attachment = NSTextAttachment()
        attachment.bounds = CGRect(x: 0, y: 0, width: 160, height: 240)
        #if os(macOS)
        attachment.image = NSImage(size: attachment.bounds.size)
        #else
        attachment.image = UIGraphicsImageRenderer(size: attachment.bounds.size).image { _ in }
        #endif
        view.replaceAllText(NSAttributedString(attachment: attachment))
        #expect(view.contentHeight(at: 320) >= 240)
        #expect(view.textLayoutManager != nil)
    }

    #if os(macOS)
    @Test("The content editor reveals the caret through the enclosing host scroll")
    func caretReachesParentScroll() throws {
        let owner = try session((0..<100).map { "Paragraph \($0)" }.joined(separator: "\n\n"))
        let coordinator = RelayMarkEditorView.TextCoordinator(session: owner)
        var services = RelayMarkEditorServices(); services.layout = .content
        coordinator.services = services
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        defer { owner.invalidate(); coordinator.retire(view) }
        let container = CollaborationTextContainer(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        container.install(view); container.configure(services)
        container.frame.size.height = try #require(container.contentSize(at: 320)).height
        let parent = NSScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        parent.documentView = container
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 320, height: 120),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = parent
        defer { window.contentView = nil; window.close() }
        container.layoutSubtreeIfNeeded()
        window.makeFirstResponder(view)
        #expect(window.firstResponder === view)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        parent.contentView.scroll(to: .zero)
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view))
        #expect(container.scrollView == nil)
        #expect(view.enclosingScrollView === parent)
        #expect(parent.contentView.bounds.minY > 0)
    }
    #else
    @Test("The content editor reveals the caret through the enclosing host scroll")
    func caretReachesParentScroll() throws {
        let owner = try session((0..<100).map { "Paragraph \($0)" }.joined(separator: "\n\n"))
        let coordinator = RelayMarkEditorView.TextCoordinator(session: owner)
        var services = RelayMarkEditorServices(); services.layout = .content
        coordinator.services = services
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        defer { owner.invalidate(); coordinator.retire(view) }
        let container = CollaborationTextContainer(frame: CGRect(x: 0, y: 80, width: 320, height: 100))
        container.install(view); container.configure(services)
        container.frame.size.height = try #require(container.contentSize(at: 320)).height
        let parent = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        parent.addSubview(container)
        parent.contentSize = CGSize(width: 320, height: container.frame.maxY)
        let controller = UIViewController(); controller.view.addSubview(parent)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        container.layoutIfNeeded()
        view.becomeFirstResponder()
        #expect(view.isFirstResponder)
        view.selectedRange = NSRange(location: view.text.utf16.count, length: 0)
        parent.setContentOffset(.zero, animated: false)
        coordinator.textViewDidChangeSelection(view)
        #expect(!view.isScrollEnabled)
        #expect(parent.contentOffset.y > 0)
        #expect(view.contentOffset == .zero)
    }
    #endif
}
