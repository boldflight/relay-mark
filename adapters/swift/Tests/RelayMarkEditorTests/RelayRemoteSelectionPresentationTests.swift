import Foundation
import SwiftUI
import Testing
@testable import RelayMarkEditor
@testable import RelayMarkEditorCore
#if os(macOS)
import AppKit

@MainActor @Suite(.serialized)
struct RelayRemoteSelectionPresentationTests {
    @Test func nativeRenderingHighlightsWithoutChangingDocumentAttributes() throws {
        _ = NSApplication.shared
        let view = NSTextView(usingTextLayoutManager: true)
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 100)
        view.textContainer?.widthTracksTextView = true
        let original = NSAttributedString(string: "Remote selection stays presentation only", attributes: [
            .font: NSFont.systemFont(ofSize: 18), .backgroundColor: NSColor.yellow
        ])
        view.textStorage?.setAttributedString(original)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(CGPoint(x: -10000, y: -10000))
        window.contentView = view
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        let manager = try #require(view.textLayoutManager)
        let presentation = RelayRemoteSelectionPresentation()
        let peer = RelayMarkRemoteSelection(id: 1, name: "Peer", color: "green", range: NSRange(location: 0, length: 6), caretLocation: 6)
        presentation.update([peer], in: manager, color: { _ in .green })

        func render() throws {
            manager.ensureLayout(for: manager.documentRange)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        try render()
        var backgrounds = 0
        manager.enumerateRenderingAttributes(from: manager.documentRange.location, reverse: false) { _, attributes, _ in
            if attributes[.backgroundColor] != nil { backgrounds += 1 }
            return true
        }
        #expect(backgrounds > 0)
        #expect(view.attributedString() == original)

        presentation.update([], in: manager, color: { _ in .green })
        try render()
        backgrounds = 0
        manager.enumerateRenderingAttributes(from: manager.documentRange.location, reverse: false) { _, attributes, _ in
            if attributes[.backgroundColor] != nil { backgrounds += 1 }
            return true
        }
        #expect(backgrounds == 0)
        #expect(view.attributedString() == original)
    }
}
#endif
