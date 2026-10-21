import Foundation
@testable import RelayMarkEditor
import Testing
@testable import RelayMarkNativeCollaboration
import RelayMarkSwift
#if os(macOS)
import AppKit
#endif

/// Typing cost must not depend on how long the paper is.
@MainActor @Suite("Native edit cost", .serialized)
struct RelayMarkEditorEditCostTests {
    /// Each size's paper is parsed once; later replicas apply its seed update.
    private static var seeds: [String: Data] = [:]

    /// The cost gate shared with web: at 1 MB an edit costs at most four times
    /// its 1 KB cost plus 20 ms, measured through the real text view.
    static func withinGate(_ large: Duration, of small: Duration) -> Bool {
        large <= small * 4 + .milliseconds(20)
    }

    /// `prefix` is Markdown placed before the paragraphs.
    private func paper(bytes: Int, prefix: String = "") throws -> RelayMarkNativeDocument {
        let document = RelayMarkNativeDocument(), key = "\(bytes)|\(prefix)"
        if let seed = Self.seeds[key] { try document.applyUpdate(seed); return document }
        let paragraph = String(repeating: "Lorem ipsum dolor sit amet. ", count: 4)
        let count = max(1, bytes / (paragraph.utf8.count + 2))
        let markdown = prefix + Array(repeating: paragraph, count: count).joined(separator: "\n\n")
        Self.seeds[key] = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "cost"))
        return document
    }

    private func median(_ samples: [Duration]) -> Duration { samples.sorted()[samples.count / 2] }

    /// One paper set up for a gate: a round of its measured edits, and the checks
    /// once every round has run.
    private struct Probe {
        var round: @MainActor (Int) async throws -> [(name: String, cost: Duration)]
        var finish: @MainActor () throws -> Void
    }

    /// Both papers are edited in alternating rounds, so a load spike on the
    /// machine falls on both, and each operation is compared by its median over
    /// the rounds rather than against one fast small-paper run.
    private func gate(_ label: String, rounds: Int, small: Int = 1_024, large: Int = 1_048_576,
                      _ probe: (Int) async throws -> Probe) async throws {
        let a = try await probe(small)
        await Task.yield()
        let b = try await probe(large)
        var costs: (small: [String: [Duration]], large: [String: [Duration]]) = ([:], [:])
        for index in 0..<rounds {
            for sample in try await a.round(index) { costs.small[sample.name, default: []].append(sample.cost) }
            for sample in try await b.round(index) { costs.large[sample.name, default: []].append(sample.cost) }
        }
        try a.finish(); try b.finish()
        for name in costs.small.keys.sorted() {
            let x = median(try #require(costs.small[name])), y = median(try #require(costs.large[name]))
            print("\(label) \(name) median: \(small / 1_024) KB \(x), 1 MB \(y)")
            #expect(Self.withinGate(y, of: x), "\(label) \(name)")
        }
    }

    /// One typed character through the session: the leaf edit, the projection and the journal hand-off.
    private func sessionKeystroke(bytes: Int) async throws -> Duration {
        var saved = 0
        let editor = try RelayMarkEditorSession(document: try paper(bytes: bytes), persist: { _ in saved += 1 })
        await Task.yield()
        let clock = ContinuousClock()
        let samples = (0..<40).map { index in
            clock.measure { #expect(editor.typeNatively(range: NSRange(location: 5 + index, length: 0), replacement: "a")) }
        }
        #expect(saved == 40 && String(editor.text.characters).hasPrefix("Lorema"))
        #expect(editor.fallbackEdits == 0, "a whole-paper path ran")
        return median(samples)
    }

    @Test("A typed character costs the same in a 1 KB and a 1 MB paper")
    func sessionKeystrokeIsIndependentOfPaperSize() async throws {
        let small = try await sessionKeystroke(bytes: 1_024)
        // Other main-actor tests run between the two papers.
        await Task.yield()
        let large = try await sessionKeystroke(bytes: 1_048_576)
        print("Session keystroke median: 1 KB \(small), 1 MB \(large)")
        // Whole-paper work at 1 MB costs tens of milliseconds; a leaf edit stays within noise of the small paper.
        #expect(large < small * 3 + .microseconds(200))
    }

    /// A peer's typed character: its update, the leaf re-projection and the view splice.
    private func remoteKeystroke(bytes: Int) async throws -> Duration {
        let document = try paper(bytes: bytes)
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(document.encodeUpdate())
        await Task.yield()
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        await Task.yield()
        let path = try #require(try peer.richProseProjection().textPosition(replacing: NSRange(location: 0, length: 0))).path
        let updates = try (0..<20).map { try peer.typeText("p", replacing: 0, at: 5 + $0, path: path).update }
        #if os(macOS)
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Cost")
        defer { coordinator.retire(view) }
        await Task.yield()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        #endif
        let clock = ContinuousClock()
        let samples = try updates.map { update in
            try clock.measure {
                try editor.applyRemoteUpdate(update)
                #if os(macOS)
                coordinator.update(view)
                #endif
            }
        }
        #expect(String(editor.text.characters).hasPrefix("Lorem" + String(repeating: "p", count: 20)))
        #if os(macOS)
        #expect(view.string == String(editor.text.characters))
        #endif
        #expect(editor.fallbackEdits == 0, "a whole-paper path ran")
        return median(samples)
    }

    @Test("A peer's typed character costs the same in a 1 KB and a 1 MB paper")
    func remoteKeystrokeIsIndependentOfPaperSize() async throws {
        let small = try await remoteKeystroke(bytes: 1_024)
        // Other main-actor tests run between the two papers.
        await Task.yield()
        let large = try await remoteKeystroke(bytes: 1_048_576)
        print("Remote keystroke median: 1 KB \(small), 1 MB \(large)")
        // Re-projecting a 1 MB paper costs over a second; a leaf splice stays within a few milliseconds.
        #expect(large < .milliseconds(8))
    }

    /// A peer's Return: its update, the re-projection of the touched node and the view splice.
    private func remoteReturn(bytes: Int) async throws -> Probe {
        let document = try paper(bytes: bytes)
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(document.encodeUpdate())
        await Task.yield()
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        await Task.yield()
        // The peer's own Return command costs whole-paper work until it is windowed; its
        // update is the same shape as this one, a new paragraph beside a top-level node.
        let updates = try (0..<10).map { index in
            try peer.replaceSnapshotNodes(parentPath: [], start: 1 + index, count: 0, nodes: [[
                "kind": "element", "name": "paragraph", "attributes": ["relaymarkId": RelayMarkNativeRichXML.freshID()],
                "children": [["kind": "text", "delta": [["insert": "New line"]]]]]])
        }
        #if os(macOS)
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Cost")
        await Task.yield()
        coordinator.update(view)
        #endif
        let clock = ContinuousClock()
        return Probe(round: { index in
            [("peer return", try clock.measure {
                try editor.applyRemoteUpdate(updates[index])
                #if os(macOS)
                coordinator.update(view)
                #endif
            })]
        }, finish: {
            let expected = String(try peer.richProseProjection().text.characters)
            #expect(editor.textSplice?.nodes != nil && String(editor.text.characters) == expected)
            #if os(macOS)
            #expect(view.string == String(editor.text.characters))
            coordinator.retire(view)
            #endif
            #expect(editor.fallbackEdits == 0, "a whole-paper path ran")
        })
    }

    @Test("A peer's Return costs the same in a 1 KB and a 1 MB paper")
    func remoteReturnIsIndependentOfPaperSize() async throws {
        try await gate("Remote", rounds: 10, remoteReturn)
    }

    #if os(macOS)
    @Test("A peer's structural edit renders exactly as a full render")
    func remoteStructuralSpliceMatchesFullRender() throws {
        let document = try richPaper()
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(document.encodeUpdate())
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Structure")
        defer { coordinator.retire(view) }
        coordinator.update(view)
        var spliced = 0
        for offset in stride(from: 1, to: 80, by: 3) {
            guard offset < String(try peer.richProseProjection().text.characters).utf16.count - 2 else { break }
            let update: Data
            do {
                update = offset % 2 == 0
                    ? try RelayMarkNativeRichEditing.replace(document: peer, range: NSRange(location: offset, length: 0),
                        runs: [("one\ntwo", [:])], expectedSnapshot: peer.snapshot()).update
                    : try RelayMarkNativeRichEditing.replace(document: peer, range: NSRange(location: offset, length: 2),
                        runs: [], expectedSnapshot: peer.snapshot()).update
            } catch { continue }
            let before = editor.textRevision
            try editor.applyRemoteUpdate(update)
            coordinator.update(view)
            if editor.textSplice?.from == before, editor.textSplice?.nodes != nil { spliced += 1 }
            let expected = String(try peer.richProseProjection().text.characters)
            #expect(String(editor.text.characters) == expected)
            expectRendersLikeFullRender(view, editor)
        }
        #expect(spliced > 10)
    }

    @Test("Peer updates delivered out of order re-render only the nodes they touched once complete")
    func outOfOrderPeerUpdatesSplice() throws {
        let document = try richPaper()
        let peerDocument = RelayMarkNativeDocument(); try peerDocument.applyUpdate(document.encodeUpdate())
        var outbox: [Data] = []
        let peer = try RelayMarkEditorSession(document: peerDocument, persist: { outbox.append($0.update) })
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Out of order")
        defer { coordinator.retire(view) }
        coordinator.update(view)
        let last = (String(peer.text.characters) as NSString).range(of: "Last")
        #expect(peer.typeNatively(range: NSRange(location: last.location, length: 0), replacement: "Very "))
        #expect(peer.editStructureNatively(range: NSRange(location: last.location + 2, length: 0), replacement: "\n"))
        #expect(outbox.count == 2)
        let before = editor.textRevision
        try editor.applyRemoteUpdate(outbox[1])
        #expect(!editor.isSupported && editor.textRevision == before, "waits for the missing update")
        try editor.applyRemoteUpdate(outbox[0])
        #expect(editor.isSupported && String(editor.text.characters) == String(peer.text.characters))
        #expect(editor.textSplice?.from == before && editor.textSplice?.to == editor.textRevision,
                "the completed updates re-rendered the whole paper")
        coordinator.update(view)
        expectRendersLikeFullRender(view, editor)
    }

    @Test("Block commands re-render only the nodes they change, exactly as a full render")
    func blockCommandsSpliceLikeFullRender() throws {
        let editor = try RelayMarkEditorSession(document: try richPaper(), persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Commands")
        defer { coordinator.retire(view) }
        coordinator.update(view)
        func select(_ needle: String) {
            let found = (String(editor.text.characters) as NSString).range(of: needle)
            editor.setNativeSelection(NSRange(location: found.location + 1, length: 0))
        }
        let commands: [(String, () throws -> Void)] = [
            ("heading level", { select("Heading"); editor.setSelectedHeadingLevel(2) }),
            ("block style", { select("Last"); editor.setSelectedBlockStyle(.quote) }),
            ("table row", { select("left"); editor.performSelectedTableCommand(.addRowAfter) }),
            ("link", { let found = (String(editor.text.characters) as NSString).range(of: "Plain")
                       editor.setNativeSelection(found)
                       try editor.applyLink("https://relay.example/y", review: editor.prepareLinkEdit()) }),
            ("divider", { select("First"); editor.insertDivider() }),
            ("list at the paper's start", { select("Heading"); editor.setSelectedBlockStyle(.bulletList) }),
            ("Backspace at the paper's start", { editor.setNativeSelection(NSRange(location: 0, length: 0))
                                                  #expect(editor.handleNativeEdgeDeletion(backward: true)) }),
        ]
        for (name, command) in commands {
            let before = editor.textRevision
            try command()
            #expect(editor.failure == nil && editor.textRevision != before, "\(name) applied")
            #expect(editor.textSplice?.from == before && editor.textSplice?.to == editor.textRevision,
                    "\(name) re-rendered the whole paper")
            coordinator.update(view)
            expectRendersLikeFullRender(view, editor)
        }
        // Backspace where it changes nothing, at the start of a paragraph opening
        // the paper, leaves the shown text alone.
        let before = editor.textRevision
        #expect(String(editor.text.characters).hasPrefix("Heading"))
        #expect(editor.handleNativeEdgeDeletion(backward: true))
        #expect(editor.textRevision == before && editor.failure == nil)
    }

    private func richPaper() throws -> RelayMarkNativeDocument {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("""
            # Heading **bold**

            Plain **bold** and [a link](https://relay.example/x) end.

            - First item
            - [ ] Open task

            | Name | Value |
            | --- | --- |
            | left | right |

            Last paragraph.
            """, namespace: "splice"))
        return document
    }

    @Test("Characters typed into the text view render exactly as a full render")
    func typedCharactersMatchFullRender() throws {
        let editor = try RelayMarkEditorSession(document: try richPaper(), persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Typing")
        defer { coordinator.retire(view) }
        coordinator.update(view)
        // After marks and at paragraph starts, where TextKit's typing attributes come
        // from a neighbour. Table cells are their own text views.
        let places = ["Heading bold", "Plain bold", "a link", "First item", "Open task", "Last"].map { ($0, true) } +
            ["Plain", "First", "Open", "Last"].map { ($0, false) }
        for (needle, after) in places {
            let found = (view.string as NSString).range(of: needle)
            #expect(found.location != NSNotFound)
            view.setSelectedRange(NSRange(location: after ? NSMaxRange(found) : found.location, length: 0))
            let before = editor.textRevision
            view.insertText("z", replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(editor.textRevision != before && editor.failure == nil, "typing after \(needle)")
            expectRendersLikeFullRender(view, editor)
        }
        // A character typed in a cell's own text view is styled as a full render styles it.
        for needle in ["left", "right"] {
            let table = try #require(view.paper.tables.spans.first?.table)
            let cell = table.grid.cellView(try #require(table.cells.firstIndex { $0.text.string.hasPrefix(needle) }))
            cell.setSelectedRange(NSRange(location: needle.utf16.count, length: 0))
            cell.insertText("z", replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(editor.failure == nil && String(editor.text.characters).contains(needle + "z"), "typing in cell \(needle)")
            expectRendersLikeFullRender(view, editor)
        }
        // Return inside bold text stores the mark for the new paragraph's first character.
        let bold = (view.string as NSString).range(of: "Plain bold")
        view.setSelectedRange(NSRange(location: bold.location + 8, length: 0))
        view.insertNewline(nil)
        view.insertText("z", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string.contains("bo\nzld"))
        expectRendersLikeFullRender(view, editor)
        // Bold on a word and off again re-render just its block.
        let word = (view.string as NSString).range(of: "Last")
        embolden(view, range: word)
        #expect(editor.text.runs.contains { String(editor.text[$0.range].characters) == "Last" && $0.inlinePresentationIntent == .stronglyEmphasized })
        expectRendersLikeFullRender(view, editor)
        embolden(view, range: word, remove: true)
        #expect(!editor.text.runs.contains { String(editor.text[$0.range].characters).contains("Last") && $0.inlinePresentationIntent == .stronglyEmphasized })
        expectRendersLikeFullRender(view, editor)
        // Typing over a selection from one paragraph into the list joins them.
        let across = (view.string as NSString).range(of: "end.")
        view.setSelectedRange(NSRange(location: across.location, length: across.length + 4))
        view.insertText("Q", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.failure == nil && !view.string.contains("end."))
        expectRendersLikeFullRender(view, editor)
        // Backspace before "zld" joins the paragraphs back.
        view.setSelectedRange(NSRange(location: bold.location + 9, length: 0))
        view.deleteBackward(nil)
        #expect(view.string.contains("bozld") && editor.failure == nil)
        expectRendersLikeFullRender(view, editor)
        // Pasting lines splits the heading; the new lines are paragraphs without marks.
        let target = (view.string as NSString).range(of: "Heading")
        #expect(editor.pastePlainTextNatively(range: NSRange(location: NSMaxRange(target), length: 0), text: "A\nB"))
        coordinator.update(view)
        #expect(editor.failure == nil && view.string.hasPrefix("HeadingA\nB"))
        expectRendersLikeFullRender(view, editor)
    }

    /// The oracle is a second view rendering the same session in full.
    private func expectRendersLikeFullRender(_ view: CollaborationTextView, _ editor: RelayMarkEditorSession) {
        let reference = RelayMarkEditorView.TextCoordinator(session: editor)
        let referenceView = reference.makeTextView(accessibilityLabel: "Reference")
        defer { reference.retire(referenceView) }
        reference.update(referenceView)
        guard let shown = view.textStorage, let full = referenceView.textStorage else { Issue.record("No text storage"); return }
        guard shown.string == full.string else { Issue.record("Text differs from a full render"); return }
        for index in 0..<full.length {
            var expected = full.attributes(at: index, effectiveRange: nil)
            var actual = shown.attributes(at: index, effectiveRange: nil)
            let expectedFont = expected.removeValue(forKey: .font) as? NSFont, actualFont = actual.removeValue(forKey: .font) as? NSFont
            let expectedStyle = expected.removeValue(forKey: .paragraphStyle) as? NSParagraphStyle
            let actualStyle = actual.removeValue(forKey: .paragraphStyle) as? NSParagraphStyle
            #expect(expectedFont?.fontName == actualFont?.fontName && expectedFont?.pointSize == actualFont?.pointSize, "font at \(index)")
            #expect(expectedStyle?.headIndent == actualStyle?.headIndent, "paragraph style at \(index)")
            #expect(Set(expected.keys) == Set(actual.keys), "attributes at \(index)")
            for (key, value) in expected {
                if let intent = value as? PresentationIntent {
                    #expect(intent == actual[key] as? PresentationIntent, "\(key.rawValue) at \(index)")
                } else if let table = value as? RelayTableAttachment {
                    // Each view has its own table attachment; they must show the same cells.
                    let other = actual[key] as? RelayTableAttachment
                    #expect(other?.identity == table.identity && other?.start == table.start, "table at \(index)")
                    #expect(other.map { zip($0.cells, table.cells).allSatisfy { $0.sameCell(as: $1) } && $0.cells.count == table.cells.count } == true,
                            "table cells at \(index)")
                } else {
                    #expect("\(value)" == actual[key].map { "\($0)" }, "\(key.rawValue) at \(index)")
                }
            }
        }
    }

    @Test("A spliced peer edit renders exactly as a full render of the same text")
    func remoteSpliceMatchesFullRender() throws {
        let document = try richPaper()
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(document.encodeUpdate())
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Splice")
        defer { coordinator.retire(view) }
        coordinator.update(view)
        let length = String(editor.text.characters).utf16.count
        var spliced = 0
        for offset in stride(from: 1, to: length, by: 4) {
            let projection = try peer.richProseProjection()
            guard let position = projection.textPosition(replacing: NSRange(location: offset, length: 0)),
                  position.index > 0 else { continue }
            let update = offset % 2 == 0 ? try peer.typeText("q", replacing: 0, at: position.index, path: position.path).update
                : try peer.formatText(at: 0, length: position.index, attributes: ["italic": [:]], path: position.path)
            let before = editor.textRevision
            try editor.applyRemoteUpdate(update)
            #expect(editor.textSplice?.from == before, "offset \(offset) was not spliced")
            coordinator.update(view)
            expectRendersLikeFullRender(view, editor)
            spliced += 1
        }
        #expect(spliced > 8)
    }

    /// One typed character through the real AppKit text view, including TextKit's own layout work.
    private func viewKeystroke(bytes: Int) async throws -> Duration {
        var saved = 0
        let editor = try RelayMarkEditorSession(document: try paper(bytes: bytes), persist: { _ in saved += 1 })
        await Task.yield()
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Cost")
        defer { coordinator.retire(view) }
        await Task.yield()
        // As in the app, the text view scrolls inside a window-sized viewport.
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        view.setSelectedRange(NSRange(location: 5, length: 0))
        let clock = ContinuousClock()
        let samples = (0..<20).map { index in
            clock.measure { view.insertText(index.isMultiple(of: 2) ? "a" : "b", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        }
        #expect(saved == 20 && editor.failure == nil)
        #expect(editor.fallbackEdits == 0, "a whole-paper path ran")
        return median(samples)
    }

    /// The paper's AppKit view as in the app: scrolling inside a window-sized viewport.
    private func mountView(_ editor: RelayMarkEditorSession) async -> (RelayMarkEditorView.TextCoordinator, CollaborationTextView) {
        await Task.yield()
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Cost")
        await Task.yield()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        return (coordinator, view)
    }

    /// Return inside a paragraph, then Backspace joining it back, through the real AppKit text view.
    private func structuralKeystrokes(bytes: Int) async throws -> Probe {
        var saved = 0
        let editor = try RelayMarkEditorSession(document: try paper(bytes: bytes), persist: { _ in saved += 1 })
        let (coordinator, view) = await mountView(editor)
        let original = view.string, clock = ContinuousClock()
        return Probe(round: { index in
            view.setSelectedRange(NSRange(location: 20 + index * 113, length: 0))
            return [("split", clock.measure { view.insertNewline(nil) }), ("join", clock.measure { view.deleteBackward(nil) })]
        }, finish: {
            #expect(saved == 12 && editor.failure == nil && view.string == original && String(editor.text.characters) == original)
            #expect(editor.fallbackEdits == 0, "a whole-paper path ran")
            coordinator.retire(view)
        })
    }

    @Test("Return and joining blocks cost the same in a 1 KB and a 1 MB paper")
    func structuralKeystrokesAreIndependentOfPaperSize() async throws {
        // TextKit's layout grows mildly with length, as for a typed character; Relay's own work does not.
        try await gate("Return and join", rounds: 6, structuralKeystrokes)
    }

    /// Typing over a selection that spans two paragraphs, through the real AppKit text view.
    private func spanningReplacement(bytes: Int) async throws -> Probe {
        var saved = 0
        let editor = try RelayMarkEditorSession(document: try paper(bytes: bytes), persist: { _ in saved += 1 })
        let (coordinator, view) = await mountView(editor)
        let clock = ContinuousClock()
        return Probe(round: { index in
            // Paragraph pairs ahead of earlier replacements keep their offsets.
            view.setSelectedRange(NSRange(location: 1_000 - index * 226 + 100, length: 30))
            return [("spanning replacement", clock.measure { view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0)) })]
        }, finish: {
            #expect(saved == 4 && editor.failure == nil && view.string == String(editor.text.characters))
            #expect(editor.fallbackEdits == 0, "a whole-paper path ran")
            coordinator.retire(view)
        })
    }

    @Test("Typing over a selection across paragraphs costs the same in a 1 KB and a 1 MB paper")
    func spanningReplacementIsIndependentOfPaperSize() async throws {
        try await gate("Spanning", rounds: 4, small: 2_048, spanningReplacement)
    }

    /// Japanese input: marked candidates, then the committed word, through the real AppKit text view.
    private func compositionCommit(bytes: Int) async throws -> Probe {
        var saved = 0
        let editor = try RelayMarkEditorSession(document: try paper(bytes: bytes), persist: { _ in saved += 1 })
        let (coordinator, view) = await mountView(editor)
        let clock = ContinuousClock()
        return Probe(round: { index in
            view.setSelectedRange(NSRange(location: 5 + index * 3, length: 0))
            view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            view.setMarkedText("にほ", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            return [("commit", clock.measure { view.insertText("日本", replacementRange: NSRange(location: NSNotFound, length: 0)) })]
        }, finish: {
            #expect(saved == 6 && editor.failure == nil && String(editor.text.characters).hasPrefix("Lorem日本"))
            #expect(view.string == String(editor.text.characters))
            #expect(editor.fallbackEdits == 0, "a whole-paper path ran")
            coordinator.retire(view)
        })
    }

    @Test("A committed Japanese word costs the same in a 1 KB and a 1 MB paper")
    func compositionCommitIsIndependentOfPaperSize() async throws {
        try await gate("Composition", rounds: 6, compositionCommit)
    }

    /// The Bold menu command as the font manager converts the selection's font.
    private func embolden(_ view: CollaborationTextView, range: NSRange, remove: Bool = false) {
        view.setSelectedRange(range)
        #expect(view.formatNatively { font in
            remove ? NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                : NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        })
    }

    private func formatting(bytes: Int) async throws -> Probe {
        var saved = 0
        let editor = try RelayMarkEditorSession(document: try paper(bytes: bytes), persist: { _ in saved += 1 })
        let (coordinator, view) = await mountView(editor)
        let clock = ContinuousClock()
        return Probe(round: { index in
            [("bold", clock.measure { embolden(view, range: NSRange(location: 6 + index * 113, length: 5)) })]
        }, finish: {
            #expect(saved == 6 && editor.failure == nil)
            #expect(editor.text.runs.contains { String(editor.text[$0.range].characters) == "ipsum" && $0.inlinePresentationIntent == .stronglyEmphasized })
            #expect(editor.fallbackEdits == 0, "a whole-paper path ran")
            coordinator.retire(view)
        })
    }

    @Test("Bolding a word costs the same in a 1 KB and a 1 MB paper")
    func formattingIsIndependentOfPaperSize() async throws {
        try await gate("Formatting", rounds: 6, formatting)
    }

    /// Tab and Shift-Tab on a list item, through the real AppKit text view.
    private func listDepth(bytes: Int) async throws -> Probe {
        var saved = 0
        let editor = try RelayMarkEditorSession(document: try paper(bytes: bytes, prefix: "- one\n- two\n- three\n\n"),
                                                persist: { _ in saved += 1 })
        let (coordinator, view) = await mountView(editor)
        let original = view.string, clock = ContinuousClock()
        return Probe(round: { _ in
            view.setSelectedRange(NSRange(location: 5, length: 0))
            return [("indent", clock.measure { view.insertTab(nil); coordinator.update(view) }),
                    ("outdent", clock.measure { view.insertBacktab(nil); coordinator.update(view) })]
        }, finish: {
            #expect(saved == 8 && editor.failure == nil && view.string == original)
            #expect(editor.fallbackEdits == 0, "a whole-paper path ran")
            coordinator.retire(view)
        })
    }

    @Test("Indenting a list item costs the same in a 1 KB and a 1 MB paper")
    func listDepthIsIndependentOfPaperSize() async throws {
        try await gate("List depth", rounds: 4, listDepth)
    }

    /// Pasting three lines of plain text over a word, through the session and the real AppKit view.
    /// The system clipboard is left alone; the view's paste hands the session the same text.
    private func plainPaste(bytes: Int) async throws -> Probe {
        var saved = 0
        let editor = try RelayMarkEditorSession(document: try paper(bytes: bytes), persist: { _ in saved += 1 })
        let (coordinator, view) = await mountView(editor)
        let clock = ContinuousClock()
        return Probe(round: { index in
            [("plain paste", clock.measure {
                #expect(editor.pastePlainTextNatively(range: NSRange(location: 6 + index * 113, length: 5), text: "one\ntwo\nthree"))
                coordinator.update(view)
            })]
        }, finish: {
            #expect(saved == 4 && editor.failure == nil && view.string == String(editor.text.characters))
            #expect(editor.fallbackEdits == 0, "a whole-paper path ran")
            coordinator.retire(view)
        })
    }

    @Test("Pasting lines costs the same in a 1 KB and a 1 MB paper")
    func plainPasteIsIndependentOfPaperSize() async throws {
        try await gate("Paste", rounds: 4, plainPaste)
    }

    /// Pasting formatted HTML (a heading, a bold paragraph and a list) through the session and the real AppKit view.
    private func richPaste(bytes: Int) async throws -> Probe {
        var saved = 0
        let editor = try RelayMarkEditorSession(document: try paper(bytes: bytes), persist: { _ in saved += 1 })
        let (coordinator, view) = await mountView(editor)
        let html = "<h2>Pasted</h2><p>Some <strong>bold</strong> text</p><ul><li>one</li><li>two</li></ul>"
        let clock = ContinuousClock()
        return Probe(round: { index in
            editor.setNativeSelection(NSRange(location: 6 + index * 113, length: 0))
            let start = clock.now
            let paste = try editor.prepareStructuredClipboard(html: html, capture: editor.captureStructuredPaste())
            try await editor.insertStructuredPaste(paste, authorize: { _ in })
            coordinator.update(view)
            return [("rich paste", clock.now - start)]
        }, finish: {
            #expect(saved == 4 && editor.failure == nil && view.string == String(editor.text.characters))
            #expect(editor.fallbackEdits == 0, "a whole-paper path ran")
            coordinator.retire(view)
        })
    }

    @Test("Pasting formatted HTML costs the same in a 1 KB and a 1 MB paper")
    func richPasteIsIndependentOfPaperSize() async throws {
        try await gate("Paste", rounds: 4, richPaste)
    }

    /// Cmd-Z and Shift-Cmd-Z of a Return, through the session and the real AppKit view.
    private func history(bytes: Int) async throws -> Probe {
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: try paper(bytes: bytes), persist: { saved.append($0.update) })
        let (coordinator, view) = await mountView(editor)
        let original = view.string, clock = ContinuousClock()
        return Probe(round: { index in
            view.setSelectedRange(NSRange(location: 20 + index * 113, length: 0))
            view.insertNewline(nil)
            let undo = clock.measure { editor.undo(); coordinator.update(view) }
            let redo = clock.measure { editor.redo(); coordinator.update(view) }
            editor.undo(); coordinator.update(view)
            return [("undo", undo), ("redo", redo)]
        }, finish: {
            #expect(editor.failure == nil && view.string == original && String(editor.text.characters) == original)
            // Each saved undo is its own small transaction, not the paper's whole delete set.
            #expect(saved.count == 16 && saved.allSatisfy { $0.count < 512 })
            #expect(editor.fallbackEdits == 0, "a whole-paper path ran")
            coordinator.retire(view)
        })
    }

    @Test("Undo and redo cost the same in a 1 KB and a 1 MB paper")
    func historyIsIndependentOfPaperSize() async throws {
        try await gate("History", rounds: 4, history)
    }

    /// A paper that is one long list. Task lists stop at RelayMark's 4096-item
    /// limit, so a large task list has longer items; bullet lists have no limit.
    private func listPaper(bytes: Int, marker: String) throws -> RelayMarkNativeDocument {
        let document = RelayMarkNativeDocument(), key = "list|\(marker)|\(bytes)"
        if let seed = Self.seeds[key] { try document.applyUpdate(seed); return document }
        let line = "\(marker) Item with a few more words to fill"
        var count = max(2, bytes / (line.utf8.count + 8))
        if marker.contains("[") { count = min(count, 4_000) }
        let padding = String(repeating: "w", count: max(0, bytes / count - line.utf8.count - 8))
        let markdown = (0..<count).map { "\(line) \(padding) \($0)." }.joined(separator: "\n")
        Self.seeds[key] = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "list"))
        return document
    }

    /// Typing, Return, Tab, Cmd-B and Cmd-Z in a list item, and a peer's typing
    /// and new item, through the session and the real AppKit view.
    private func listEdits(bytes: Int, marker: String) async throws -> Probe {
        let document = try listPaper(bytes: bytes, marker: marker)
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(document.encodeUpdate())
        var saved = 0
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in saved += 1 })
        let (coordinator, view) = await mountView(editor)
        let clock = ContinuousClock()
        return Probe(round: { index in
            var samples: [(name: String, cost: Duration)] = []
            func measure(_ name: String, _ work: () throws -> Void) rethrows {
                let start = clock.now; try work(); samples.append((name, clock.now - start))
            }
            let text = view.string as NSString, found = text.range(of: " \(1 + index * 2).")
            #expect(found.location != NSNotFound)
            let item = text.lineRange(for: found)
            view.setSelectedRange(NSRange(location: item.location + 3, length: 0))
            measure("type") { view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0)) }
            measure("return") { view.insertNewline(nil) }
            measure("tab") { view.insertTab(nil); coordinator.update(view) }
            measure("undo") { editor.undo(); coordinator.update(view) }
            view.setSelectedRange(NSRange(location: item.location, length: 4))
            measure("bold") { #expect(view.formatNatively { NSFontManager.shared.convert($0, toHaveTrait: .boldFontMask) }) }
            let path = try #require(peer.richProseProjection().textPosition(replacing: NSRange(location: item.location + 5, length: 0))).path
            let typed = try peer.typeText("p", replacing: 0, at: 1, path: path).update
            try measure("peer type") { try editor.applyRemoteUpdate(typed); coordinator.update(view) }
            // A peer's new item, shaped as an existing one with fresh identities.
            let list = try #require((try JSONSerialization.jsonObject(with: peer.snapshot()) as? [String: Any])?["children"] as? [[String: Any]])[0]
            var template = try #require((list["children"] as? [[String: Any]])?.first)
            @MainActor func fresh(_ node: [String: Any]) -> [String: Any] {
                var node = node
                if var attributes = node["attributes"] as? [String: Any], attributes["relaymarkId"] != nil {
                    attributes["relaymarkId"] = RelayMarkNativeRichXML.freshID(); node["attributes"] = attributes
                }
                if let children = node["children"] as? [[String: Any]] { node["children"] = children.map(fresh) }
                return node
            }
            template = fresh(template)
            let added = try peer.replaceSnapshotNodes(parentPath: [0], start: 1 + index * 2, count: 0, nodes: [template])
            try measure("peer item") { try editor.applyRemoteUpdate(added); coordinator.update(view) }
            try peer.applyUpdate(document.encodeUpdate(since: peer.stateVector()))
            return samples
        }, finish: {
            #expect(editor.failure == nil && view.string == String(editor.text.characters))
            let projected = String(try peer.richProseProjection().text.characters)
            #expect(String(editor.text.characters) == projected)
            #expect(editor.fallbackEdits == 0, "a whole-paper path ran")
            coordinator.retire(view)
        })
    }

    @Test("Editing a long list costs the same at 1 KB and 1 MB", arguments: ["-", "- [ ]"])
    func listEditsAreIndependentOfListLength(marker: String) async throws {
        try await gate("List \(marker)", rounds: 4) { try await listEdits(bytes: $0, marker: marker) }
    }

    /// A paper holding one table of eight-column rows, as many as fit up to
    /// RelayMark's 256-row limit, then paragraphs up to `bytes`.
    private func tablePaper(bytes: Int) throws -> RelayMarkNativeDocument {
        let document = RelayMarkNativeDocument(), key = "table|\(bytes)"
        if let seed = Self.seeds[key] { try document.applyUpdate(seed); return document }
        let columns = 8, filler = String(repeating: "w", count: 40)
        let row = { (r: Int) in "| " + (0..<columns).map { "\(filler) r\(r)c\($0)." }.joined(separator: " | ") + " |" }
        let rows = max(2, min(255, bytes / row(0).utf8.count))
        let table = ["| " + (0..<columns).map { "h\($0)" }.joined(separator: " | ") + " |",
                     "| " + Array(repeating: "---", count: columns).joined(separator: " | ") + " |"] + (0..<rows).map(row)
        var markdown = table.joined(separator: "\n")
        let paragraph = String(repeating: "Lorem ipsum dolor sit amet. ", count: 4)
        markdown += String(repeating: "\n\n" + paragraph, count: max(0, (bytes - markdown.utf8.count) / (paragraph.utf8.count + 2)))
        Self.seeds[key] = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "table"))
        return document
    }

    /// Typing, Return, Bold and Undo in a table cell's text view, a peer's
    /// typing in a cell, and Return and its join in the paragraph beside the
    /// table, through the session and the real AppKit views.
    private func tableEdits(bytes: Int) async throws -> Probe {
        let document = try tablePaper(bytes: bytes)
        let peer = RelayMarkNativeDocument(); try peer.applyUpdate(document.encodeUpdate())
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let (coordinator, view) = await mountView(editor)
        view.textLayoutManager?.textViewportLayoutController.layoutViewport()
        let table = try #require(view.paper.tables.spans.first?.table)
        let clock = ContinuousClock()
        return Probe(round: { index in
            var samples: [(name: String, cost: Duration)] = []
            func measure(_ name: String, _ work: () throws -> Void) rethrows {
                let start = clock.now; try work(); samples.append((name, clock.now - start))
            }
            // The paragraph after the table: the table is the edit's neighbour.
            let beside = (view.string as NSString).range(of: "Lorem").location + 6 + index
            view.setSelectedRange(NSRange(location: beside, length: 0))
            measure("return beside") { view.insertNewline(nil) }
            measure("join beside") { view.deleteBackward(nil) }
            let marker = " r1c\(1 + index * 2)."
            let cellIndex = try #require(table.cells.firstIndex { $0.text.string.contains(marker) })
            let cell = table.grid.cellView(cellIndex)
            let at = (cell.string as NSString).range(of: marker).location
            cell.setSelectedRange(NSRange(location: at, length: 0))
            measure("type") { cell.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0)) }
            measure("return") { cell.insertNewline(nil) }
            measure("undo") { editor.undo(); coordinator.update(view) }
            let paper = (String(editor.text.characters) as NSString).range(of: marker)
            measure("bold") { #expect(editor.toggleMarkNatively(.bold, range: NSRange(location: paper.location - 4, length: 4))); coordinator.update(view) }
            let path = try #require(peer.richProseProjection().textPosition(replacing: NSRange(location: paper.location, length: 0))).path
            let typed = try peer.typeText("p", replacing: 0, at: 1, path: path).update
            try measure("peer type") { try editor.applyRemoteUpdate(typed); coordinator.update(view) }
            try peer.applyUpdate(document.encodeUpdate(since: peer.stateVector()))
            return samples
        }, finish: {
            #expect(editor.failure == nil && view.paperString == String(editor.text.characters))
            let projected = String(try peer.richProseProjection().text.characters)
            #expect(String(editor.text.characters) == projected)
            #expect(editor.fallbackEdits == 0, "a whole-paper path ran")
            coordinator.retire(view)
        })
    }

    @Test("Editing a table costs the same in a 1 KB and a 1 MB paper")
    func tableEditsAreIndependentOfPaperSize() async throws {
        try await gate("Table", rounds: 4, tableEdits)
    }

    @Test("A keystroke in the real text view stays far below whole-paper cost on a 1 MB paper")
    func viewKeystrokeStaysSmall() async throws {
        let small = try await viewKeystroke(bytes: 1_024)
        // Other main-actor tests run between the two papers.
        await Task.yield()
        let large = try await viewKeystroke(bytes: 1_048_576)
        print("Text view keystroke median: 1 KB \(small), 1 MB \(large)")
        // TextKit's layout bookkeeping grows mildly with length; Relay's own work does not (see above).
        #expect(large < .milliseconds(8))
    }
    #endif
}
