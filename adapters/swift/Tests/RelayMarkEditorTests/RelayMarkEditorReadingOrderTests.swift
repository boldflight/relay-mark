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

/// The host's title and the paper are separate text views; VoiceOver reads from
/// one into the other as one text, line by line.
@MainActor
struct RelayMarkEditorReadingOrderTests {
    @Test func voiceOverReadsFromTheTitleIntoThePaper() throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("Body text", namespace: "order"))
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        #if os(macOS)
        let title = NSTextView()
        #else
        let title = UITextView()
        #endif
        var services = RelayMarkEditorServices()
        services.previousTextElement = { [weak title] in title }
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        coordinator.services = services
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        defer { coordinator.retire(view) }
        #if os(macOS)
        let shared = (view.accessibilitySharedTextUIElements() ?? []).map { $0 as AnyObject }
        #expect(shared.count == 2 && shared.first === title && shared.last === view)
        #expect((title.accessibilitySharedTextUIElements() ?? []).map { $0 as AnyObject }.last === view)
        #else
        #expect(view.accessibilityPreviousTextNavigationElement as AnyObject? === title)
        #expect(title.accessibilityNextTextNavigationElement as AnyObject? === view)
        #endif
    }
}
