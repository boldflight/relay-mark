import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkNativeCollaboration
import RelayMarkSwift
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Return in the host's title moves the caret into the paper, as on the web.
@MainActor
struct RelayMarkEditorFocusTests {
    @Test func theHostMovesFocusIntoThePaper() throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("First line\n\nSecond line", namespace: "focus"))
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        defer { coordinator.retire(view) }
        // Asked before the paper is on screen, it takes focus once it is.
        editor.requestFocus(at: .start)
        #if os(macOS)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let title = NSTextView()
        window.contentView?.addSubview(title)
        window.makeFirstResponder(title)
        window.contentView?.addSubview(view)
        #expect(window.firstResponder === view)
        #expect(view.selectedRange() == NSRange(location: 0, length: 0))
        window.makeFirstResponder(title)
        editor.requestFocus(at: .end)
        #expect(window.firstResponder === view)
        #expect(view.selectedRange() == NSRange(location: view.string.utf16.count, length: 0))
        #else
        let window = relayTestWindow(width: 390)
        window.makeKeyAndVisible()
        let title = UITextView()
        window.addSubview(title)
        #expect(title.becomeFirstResponder())
        window.addSubview(view)
        #expect(view.isFirstResponder)
        #expect(view.selectedRange == NSRange(location: 0, length: 0))
        #expect(title.becomeFirstResponder())
        editor.requestFocus(at: .end)
        #expect(view.isFirstResponder)
        #expect(view.selectedRange == NSRange(location: view.text.utf16.count, length: 0))
        #endif
    }
}
