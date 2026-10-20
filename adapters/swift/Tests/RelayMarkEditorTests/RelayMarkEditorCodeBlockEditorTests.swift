import Foundation
@testable import RelayMarkEditor
import Testing
#if os(macOS)
import AppKit
#endif
import RelayMarkNativeCollaboration
import RelayMarkSwift

@MainActor
struct RelayMarkEditorCodeBlockEditorTests {
    private func document() throws -> RelayMarkNativeDocument {
        let doc = RelayMarkNativeDocument()
        _ = try doc.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            "````swift\nlet 🌍 = \"```\"\nprint(🌍)\n// tail\n````", namespace: "canonical-code-editor"))
        return doc
    }
    private func assertCodeShape(_ doc: RelayMarkNativeDocument, text: String) throws {
        let tree = try #require(JSONSerialization.jsonObject(with: doc.snapshot()) as? [String: Any])
        let blocks = try #require(tree["children"] as? [[String: Any]])
        #expect(blocks.count == 1 && blocks[0]["name"] as? String == "codeBlock", "Kinds: \(blocks.compactMap { $0["name"] as? String })")
        #expect((blocks[0]["attributes"] as? [String: Any])?["language"] as? String == "swift")
        let leaves = try #require(blocks[0]["children"] as? [[String: Any]])
        #expect(leaves.count == 1 && leaves[0]["kind"] as? String == "text")
        #expect(String(try doc.richProseProjection().text.characters) == text)
    }



    #if os(macOS)
    @Test func nativeEmptyingAndRetypingKeepsCodeIdentity() throws {
        _ = NSApplication.shared
        let doc = try document(), block = try doc.anchor(path: [0], index: 0)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: doc, persist: { saved.append($0.update) })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Code")
        editor.setNativeSelection(NSRange(location: 0, length: String(editor.text.characters).utf16.count))
        coordinator.update(view); view.deleteBackward(nil)
        #expect(editor.failure == nil && saved.count == 1)
        #expect(try doc.richProseProjection().isEditable)
        try assertCodeShape(doc, text: "")
        coordinator.update(view)
        view.insertText("日本🌍", replacementRange: NSRange(location: 0, length: 0))
        #expect(editor.failure == nil && saved.count == 2)
        try assertCodeShape(doc, text: "日本🌍")
        #expect(try doc.resolve(anchor: block)?.path == [0])
    }

    @Test(arguments: [false, true]) func nativeReturnInsertsLFInsideOriginalCodeLeaf(overSelection: Bool) throws {
        _ = NSApplication.shared
        let doc = try document()
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: doc, persist: { saved.append($0.update) })
        let before = String(editor.text.characters), anchor = try doc.anchor(path: [0, 0], index: 12)
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Code")
        let range = overSelection ? NSRange(location: 0, length: 3) : NSRange(location: before.utf16.count, length: 0)
        editor.setNativeSelection(range); coordinator.update(view)
        view.insertNewline(nil)
        #expect(editor.failure == nil && saved.count == 1)
        try assertCodeShape(doc, text: (before as NSString).replacingCharacters(in: range, with: "\n"))
        #expect(try doc.resolve(anchor: anchor)?.index == (overSelection ? 10 : 12))
    }
    #endif
}
