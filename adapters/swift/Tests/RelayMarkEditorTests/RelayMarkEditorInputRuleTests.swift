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

/// RelayMark's shared typed-shortcut cases (spec/relaymark/editor/input-rules-v1.json),
/// typed into the real text view: AppKit's when the suite runs on macOS, UIKit's
/// on iOS and visionOS. The web editor runs the same cases through TipTap.
@MainActor @Suite(.serialized)
struct RelayMarkEditorInputRuleTests {
    nonisolated static func cases() -> [[String: Any]] {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = (try? Data(contentsOf: root.appending(path: "spec/relaymark/editor/input-rules-v1.json"))) ?? Data()
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["cases"] as? [[String: Any]] ?? []
    }

    // Bug caught: a typed shortcut the web applies (- [ ] makes a checklist)
    // staying literal text on one Apple platform.
    @Test("Every shared typed shortcut applies through the platform's text view", arguments: 0..<cases().count)
    func sharedCase(index: Int) throws {
        let example = Self.cases()[index]
        let name = example["name"] as? String ?? "\(index)"
        let bridge = try PMYXmlBridge.canonical()
        let before = try Self.document(try #require(example["before"] as? [String: Any]), bridge: bridge, identified: true)
        let document = try RelayMarkNativeDocument().scratch(tree: bridge.snapshot(before))
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        defer { coordinator.retire(view) }
        let text = try #require(example["text"] as? String)
        let caret = try Self.offset(try #require(example["caret"] as? Int), in: before, editor: editor)
        let typedBefore = String(editor.text.characters)
        editor.setNativeSelection(NSRange(location: caret, length: 0))
        #if os(macOS)
        view.setSelectedRange(NSRange(location: caret, length: 0))
        view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        #else
        let window = relayTestWindow(width: 390)
        window.addSubview(view)
        view.frame = window.bounds
        window.isHidden = false
        view.selectedRange = NSRange(location: caret, length: 0)
        // The keyboard asks the delegate first; programmatic insertText does not.
        if coordinator.textView(view, shouldChangeTextInRanges: [NSValue(range: view.selectedRange)], replacementText: text) {
            view.insertText(text)
        }
        #endif
        #expect(editor.failure == nil, "\(name): \(editor.failure ?? "")")
        guard let expectedJSON = example["after"] as? [String: Any] else {
            let typed = (typedBefore as NSString).replacingCharacters(in: NSRange(location: caret, length: 0), with: text)
            #expect(String(editor.text.characters) == typed, "\(name): a shortcut applied where none should")
            return
        }
        let snapshot = try #require(try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
        let actual = try bridge.document(fromSnapshot: snapshot)
        let expected = try Self.document(expectedJSON, bridge: bridge, identified: false)
        #expect(Self.content(actual) == Self.content(expected), "\(name): \(Self.content(actual))")
        let selection = try Self.offset(try #require(example["selection"] as? Int), in: actual, editor: editor)
        #expect(editor.nativeSelection == NSRange(location: selection, length: 0), "\(name): caret")
    }

    /// A fixture document with schema defaults filled; `identified` gives each block an identity, as an authored paper has.
    private static func document(_ json: [String: Any], bridge: PMYXmlBridge, identified: Bool) throws -> PMNode {
        var next = 0
        func identify(_ node: [String: Any]) -> [String: Any] {
            var node = node
            if identified, let type = node["type"] as? String, type != "text", type != "doc" {
                next += 1
                var attrs = node["attrs"] as? [String: Any] ?? [:]
                attrs["relaymarkId"] = String(format: "b%012x40008%015x", next, next)
                node["attrs"] = attrs
            }
            if let content = node["content"] as? [[String: Any]] { node["content"] = content.map(identify) }
            return node
        }
        let slice = try PMSlice.fromJSON(["content": (identify(json)["content"] as? [[String: Any]]) ?? []], schema: bridge.schema)
        return try bridge.schema.topNodeType.create(["relaymark": [String: Any]()], slice.content)
    }

    /// The top-level content without block identity, which each editor allocates.
    private static func content(_ node: PMNode) -> NSArray {
        func strip(_ value: Any) -> Any {
            if let map = value as? [String: Any] {
                return map.filter { $0.key != "relaymarkId" && $0.key != "headingId" }.mapValues(strip)
            }
            if let list = value as? [Any] { return list.map(strip) }
            return value
        }
        return (strip(node.json()["content"] ?? []) as? [Any] ?? []) as NSArray
    }

    /// A ProseMirror position as the paper's text offset.
    private static func offset(_ position: Int, in doc: PMNode, editor: RelayMarkEditorSession) throws -> Int {
        let resolved = try doc.resolve(position)
        let path = (0..<resolved.depth).map { resolved.index($0) }
        let block = try #require(try editor.currentProjection().blockRange(path: path))
        return block.location + resolved.parentOffset
    }
}
