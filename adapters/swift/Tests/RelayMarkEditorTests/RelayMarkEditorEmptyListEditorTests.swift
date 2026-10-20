import Foundation
@testable import RelayMarkEditor
import Testing
#if os(macOS)
import AppKit
#endif
import RelayMarkNativeCollaboration
import RelayMarkSwift

@MainActor
struct RelayMarkEditorEmptyListEditorTests {
    private func document(trailing: Bool, empty: Bool = true) throws -> RelayMarkNativeDocument {
        let doc = RelayMarkNativeDocument()
        _ = try doc.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(
            "- Outer\n\n  3. Nested 🌍 text\n\n- Sibling", namespace: "canonical-empty-list"))
        if empty {
            let projection = try doc.richProseProjection(), path = trailing ? [0, 1, 0] : [0, 0, 1, 0, 0]
            let row = try #require(projection.blockPaths.firstIndex(of: path))
            _ = try RelayMarkNativeRichReturn.apply(document: doc, blockPath: path,
                utf16Offset: projection.blockRanges[row].length, expectedSnapshot: doc.snapshot())
        }
        let baseline = RelayMarkNativeDocument()
        try baseline.applyUpdate(doc.encodeUpdate())
        return baseline
    }

    @Test func emptyRowsKeepIntentAndCanonicalSelectionWithoutPlaceholders() throws {
        for trailing in [false, true] {
            let doc = try document(trailing: trailing)
            let editor = try RelayMarkEditorSession(document: doc, persist: { _ in })
            let block = try #require(editor.nativeEmptyBlocks.first)
            let marker = try #require(NativeProseCodec.listMarker(block.intent))
            #expect(marker.label == (trailing ? "•" : "4."))
            #expect(marker.depth == (trailing ? 1 : 2))
            let native = NativeProseCodec.attributed(editor.text, emptyBlocks: editor.nativeEmptyBlocks)
            #expect(NativeProseCodec.value(native) == editor.text)
            #expect(!native.string.contains("\u{FFFC}"))
            editor.setNativeSelection(NSRange(location: block.offset, length: 0))
            #expect(editor.nativeSelection == NSRange(location: block.offset, length: 0))
        }
    }

    @Test func canonicalReturnSupportsInteriorWhileIMEAndInspectionDoNotMutate() throws {
        let doc = try document(trailing: false, empty: false)
        let editor = try RelayMarkEditorSession(document: doc, persist: { _ in })
        let before = try doc.encodeUpdate(), plain = String(editor.text.characters)
        let end = NSMaxRange(try doc.richProseProjection().blockRanges[1])
        #expect(editor.acceptsNativeReplacement(baseline: plain, range: NSRange(location: end, length: 0), replacement: "\n"))
        for offset in [3, 5, end - 1] {
            #expect(editor.acceptsNativeReplacement(baseline: plain, range: NSRange(location: offset, length: 0), replacement: "\n"))
        }
        let composition = try editor.beginComposition()
        #expect(!editor.acceptsNativeReplacement(baseline: plain, range: NSRange(location: end, length: 0), replacement: "\n"))
        editor.cancelComposition(composition)
        #expect(try doc.encodeUpdate() == before)
    }

    #if os(macOS)
    @Test func realReturnPersistsExactUpdateRetainsAnchorsAndUndo() throws {
        _ = NSApplication.shared
        let doc = try document(trailing: false, empty: false)
        let seed = try doc.encodeUpdate()
        let anchor = try doc.anchor(path: [0, 0, 1, 0, 0, 0], index: 10)
        var attempts: [Data] = [], fail = true
        let editor = try RelayMarkEditorSession(document: doc, persist: {
            attempts.append($0.update)
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
        })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "List Return")
        let baseline = String(editor.text.characters)
        let end = NSMaxRange(try doc.richProseProjection().blockRanges[1])
        editor.setNativeSelection(NSRange(location: end, length: 0)); coordinator.update(view)
        view.insertNewline(nil)
        #expect(attempts.count == 1)
        #expect(editor.hasUnpersistedTransaction && !editor.isEditable)
        #expect(editor.nativeEmptyBlocks.count == 1)
        #expect(editor.nativeSelection == NSRange(location: end + 1, length: 0))
        #expect(try doc.resolve(anchor: anchor)?.index == 10)
        fail = false; editor.retryPersistence()
        #expect(attempts.count == 2 && attempts[0] == attempts[1])
        #expect(!editor.hasUnpersistedTransaction && editor.isEditable)
        let reopened = RelayMarkNativeDocument()
        try reopened.applyUpdate(seed); try reopened.applyUpdate(attempts[0])
        #expect(try reopened.snapshot() == doc.snapshot())
        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(seed)
        let peerProjection = try peer.richProseProjection()
        let sibling = try #require(peerProjection.blockPaths.firstIndex(of: [0, 1, 0]))
        let remote = try RelayMarkNativeRichEditing.replace(document: peer,
            range: NSRange(location: peerProjection.blockRanges[sibling].location, length: 0),
            runs: [("Peer ", [:])], expectedSnapshot: peer.snapshot()).update
        try editor.applyRemoteUpdate(remote)
        editor.undo()
        #expect(String(editor.text.characters) == baseline.replacingOccurrences(of: "Sibling", with: "Peer Sibling"))
        editor.redo()
        #expect(editor.nativeEmptyBlocks.count == 1)
        #expect(try doc.resolve(anchor: anchor)?.index == 10)
    }

    @Test func actualTextViewRendersEmptyMarkerAndTypesIntoSameParagraph() throws {
        _ = NSApplication.shared
        for trailing in [false, true] {
            let doc = try document(trailing: trailing)
            var saved: [Data] = []
            let editor = try RelayMarkEditorSession(document: doc, persist: { saved.append($0.update) })
            let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
            let view = coordinator.makeTextView(accessibilityLabel: "Empty list")
            view.frame = NSRect(x: 0, y: 0, width: 320, height: 220)
            view.drawsBackground = false
            let block = try #require(editor.nativeEmptyBlocks.first)
            editor.setNativeSelection(NSRange(location: block.offset, length: 0))
            coordinator.update(view)
            let manager = try #require(view.textLayoutManager)
            manager.ensureLayout(for: manager.documentRange)
            func raster() throws -> NSBitmapImageRep {
                let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: image)
                return image
            }
            let marked = try raster()
            view.paper.emptyBlocks = []
            let plain = try raster()
            var pixels = 0
            for y in 0..<marked.pixelsHigh {
                for x in 0..<marked.pixelsWide where marked.colorAt(x: x, y: y) != plain.colorAt(x: x, y: y) { pixels += 1 }
            }
            #expect(pixels > 5)
            coordinator.update(view)
            let baseline = view.string
            view.insertText("New 🌍", replacementRange: NSRange(location: block.offset, length: 0))
            #expect(editor.failure == nil)
            #expect(saved.count == 1)
            #expect(String(editor.text.characters) == (baseline as NSString).replacingCharacters(in: NSRange(location: block.offset, length: 0), with: "New 🌍"))
            #expect(editor.nativeEmptyBlocks.isEmpty)
            editor.undo()
            #expect(String(editor.text.characters) == baseline)
        }
    }
    #endif
}
