import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkProseProjection
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Plan M5c on Apple: agent-written words read grey; what the person types or
/// pastes inside them is theirs and reads like the rest of their text.
@MainActor
struct RelayMarkEditorAIAuthoredTests {
    private let run = "4f1c2b7a-5d6e-4f80-9a1b-2c3d4e5f6a7b"

    /// "Mine, then " followed by the agent's "generated notes".
    private func editor() throws -> (RelayMarkEditorSession, () -> Int) {
        let ast: [String: Any] = ["type": "relaymark.document", "blocks": [[
            "id": "b00000000000040008000000000000a01", "type": "paragraph", "content": [
                ["type": "text", "text": "Mine, then "],
                ["type": "ai_authored", "run_id": run, "content": [["type": "text", "text": "generated notes"]]]]]]]
        let document = RelayMarkNativeDocument()
        try document.initializeDocument(authoredAST: JSONSerialization.data(withJSONObject: ast))
        var saved = 0
        return (try RelayMarkEditorSession(document: document, persist: { _ in saved += 1 }), { saved })
    }

    private func grey(_ text: AttributedString) -> [String] {
        text.runs.compactMap { $0[RelayMarkAIAuthoredAttribute.self] == nil ? nil : String(text[$0.range].characters) }
    }

    @Test func agentTextRendersSubduedAndRoundTripsThroughTheTextView() throws {
        let (editor, _) = try editor()
        #expect(grey(editor.text) == ["generated notes"])
        let rendered = NativeProseCodec.attributed(editor.text)
        #if os(macOS)
        let label = NSColor.labelColor, subdued = NSColor.secondaryLabelColor
        #else
        let label = UIColor.label, subdued = UIColor.secondaryLabel
        #endif
        #expect(rendered.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSObject == label)
        #expect(rendered.attribute(.foregroundColor, at: 14, effectiveRange: nil) as? NSObject == subdued)
        #expect(NativeProseCodec.value(rendered) == editor.text)
    }

    @Test func typingAndPastingInsideAgentTextIsThePersons() throws {
        let (editor, saved) = try editor()
        let baseline = String(editor.text.characters)
        let range = NSRange(location: 15, length: 0)
        editor.setNativeSelection(NSRange(location: 16, length: 0))
        editor.edit(AttributedString((baseline as NSString).replacingCharacters(in: range, with: "X")),
                    nativeReplacement: RelayNativeTextReplacement(baseline: baseline, range: range, replacement: "X"),
                    nativePaste: nil)
        #expect(editor.failure == nil && saved() == 1)
        #expect(String(editor.text.characters) == "Mine, then geneXrated notes")
        #expect(grey(editor.text) == ["gene", "rated notes"])

        #expect(editor.pastePlainTextNatively(range: NSRange(location: 23, length: 0), text: "Y"))
        #expect(editor.failure == nil && saved() == 2)
        #expect(String(editor.text.characters) == "Mine, then geneXrated nYotes")
        #expect(grey(editor.text) == ["gene", "rated n", "otes"])
    }
}
