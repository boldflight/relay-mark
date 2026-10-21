import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The paper editor is one TextKit 2 editor. Touching a text view's TextKit 1
/// layout manager permanently switches that view to compatibility mode.
@MainActor
struct RelayMarkEditorTextKit2Tests {
    private static let forbidden = try! NSRegularExpression(
        pattern: #"\blayoutManager\b|(?<!willSwitchTo)NSLayoutManager|numberOfGlyphs|glyphIndex|glyphRange|CollaborationTextView\(frame"#)

    @Test func sourcesNeverReachForATextKit1LayoutManager() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if Self.forbidden.firstMatch(in: line, range: range) != nil {
                    offenders.append(file.lastPathComponent + ":" + String(index + 1))
                }
            }
        }
        #expect(offenders.isEmpty, "TextKit 1 API in Sources: \(offenders)")
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let encoded = try #require(object["update"] as? String)
        return try #require(Data(base64Encoded: encoded))
    }

    #if os(macOS)
    @Test func everyEditorPathKeepsTextKit2() throws {
        _ = NSApplication.shared
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(try fixture("task-list-flat-v3-draft"))
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        defer { coordinator.retire(view) }
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 480, height: 320),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        view.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        #expect(view.textLayoutManager != nil, "The editor must start on TextKit 2")
        #expect(!view.paper.taskItems.isEmpty, "Fixture must exercise task markers")

        view.paper.remoteSelections = [RelayMarkRemoteSelection(id: 7, name: "Alex", color: "#3366FF",
            range: NSRange(location: 0, length: 4), caretLocation: 4)]
        func raster() throws {
            let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: image)
        }
        try raster()
        let marker = try #require(view.paper.taskItems.last).firstParagraphRange.location
        _ = view.characterOffset(at: .zero)
        _ = view.taskCheckboxOffset(at: CGPoint(x: 2, y: 30))
        view.setSelectedRange(NSRange(location: marker, length: 0))
        view.insertText("x", replacementRange: view.selectedRange())
        try raster()
        #expect(view.textLayoutManager != nil, "An editor path switched the paper to TextKit 1")
    }
    #endif
}
