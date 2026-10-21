import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkSwift
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Collapsible headings, as the web's paper headings fold: by the section's
/// destination name, local to the open paper, hiding without changing the text.
@MainActor @Suite(.serialized)
struct RelayMarkEditorSectionFoldingTests {
    private let markdown = "# One\n\nFirst para\n\nSecond para\n\n## Sub\n\nThird para\n\n# Two\n\nFourth para"

    private func document(_ markdown: String) throws -> RelayMarkNativeDocument {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "folding"))
        return document
    }

    private func mount(_ editor: RelayMarkEditorSession) -> (RelayMarkEditorView.TextCoordinator, CollaborationTextView) {
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        #if os(macOS)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 800)
        scroll.documentView = view
        #else
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        view.layoutIfNeeded()
        #endif
        return (coordinator, view)
    }

    /// The paper offsets where TextKit laid out a paragraph.
    private func laidOutStarts(_ view: CollaborationTextView) throws -> Set<Int> {
        let manager = try #require(view.textLayoutManager)
        let geometry = try #require(RelayTextGeometry(manager))
        var starts = Set<Int>()
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
            starts.insert(geometry.offset(fragment.rangeInElement.location)); return true
        }
        return starts
    }

    private func offset(of text: String, in view: CollaborationTextView) -> Int {
        #if os(macOS)
        (view.string as NSString).range(of: text).location
        #else
        (view.text as NSString).range(of: text).location
        #endif
    }

    private func select(_ location: Int, in view: CollaborationTextView, _ coordinator: RelayMarkEditorView.TextCoordinator) {
        #if os(macOS)
        view.setSelectedRange(NSRange(location: location, length: 0))
        #else
        view.selectedRanges = [NSRange(location: location, length: 0)]
        coordinator.textViewDidChangeSelection(view)
        #endif
    }

    /// The same names the web gives these headings (checked against
    /// paperDocumentDestinations): derived from the text and made unique.
    @Test func sectionsAreNamedAsOnTheWeb() throws {
        let editor = try RelayMarkEditorSession(document: try document(
            "# Hello World\n\n## Hello World\n\n# Ça va?\n\n# ℌey!\n\n# 日本語\n\n#   A -- b  "), persist: { _ in })
        #expect(editor.sections.map(\.id) == ["hello-world", "hello-world-2", "ca-va", "ey", "section", "a----b"])
    }

    /// A section runs to the next heading of the same or a higher level.
    @Test func foldingHidesTheSectionsParagraphsAndOnlyThose() throws {
        let editor = try RelayMarkEditorSession(document: try document(markdown), persist: { _ in })
        let (coordinator, view) = mount(editor)
        defer { coordinator.retire(view) }
        #expect(editor.sections.map(\.id) == ["one", "sub", "two"])
        let before = String(editor.text.characters)
        #expect(view.toggleSection("one"))
        let shown = try laidOutStarts(view)
        for hidden in ["First para", "Second para", "Sub", "Third para"] {
            #expect(!shown.contains(offset(of: hidden, in: view)), "\(hidden) is still laid out")
        }
        for visible in ["One", "Two", "Fourth para"] {
            #expect(shown.contains(offset(of: visible, in: view)), "\(visible) is hidden")
        }
        #expect(String(editor.text.characters) == before)
        #expect(view.textLayoutManager != nil)
        #expect(view.toggleSection("one"))
        #expect(try laidOutStarts(view).contains(offset(of: "Second para", in: view)))
    }

    @Test func movingTheCaretIntoAFoldedSectionUnfoldsIt() throws {
        let editor = try RelayMarkEditorSession(document: try document(markdown), persist: { _ in })
        let (coordinator, view) = mount(editor)
        defer { coordinator.retire(view) }
        #expect(view.toggleSection("sub"))
        #expect(!(try laidOutStarts(view)).contains(offset(of: "Third para", in: view)))
        select(offset(of: "Third para", in: view) + 2, in: view, coordinator)
        #expect(editor.foldedSections.isEmpty)
        #expect(try laidOutStarts(view).contains(offset(of: "Third para", in: view)))
    }

    /// A peer's edit inside a folded section changes the text but not the fold.
    @Test func aPeersEditInsideAFoldedSectionStaysHidden() throws {
        let document = try document(markdown)
        let remote = RelayMarkNativeDocument()
        try remote.applyUpdate(document.encodeUpdate())
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let (coordinator, view) = mount(editor)
        defer { coordinator.retire(view) }
        #expect(view.toggleSection("one"))
        let path = try #require(try remote.richProseProjection().textPosition(
            replacing: NSRange(location: offset(of: "Second para", in: view), length: 0))).path
        let update = try RelayMarkNativeRichTextMutation.replace(document: remote, path: path,
            start: 0, end: 0, text: "Peer ", attributes: [:])
        try editor.applyRemoteUpdate(update)
        coordinator.update(view)
        #expect(String(editor.text.characters).contains("Peer Second para"))
        #expect(editor.foldedSections == ["one"])
        let shown = try laidOutStarts(view)
        #expect(!shown.contains(offset(of: "Peer Second para", in: view)))
        #expect(shown.contains(offset(of: "Fourth para", in: view)))
        #expect(view.textLayoutManager != nil)
    }

    /// VoiceOver folds and unfolds the section whose heading holds the caret,
    /// and the action's name says which it will do.
    @Test func voiceOverFoldsTheSectionAtTheCaret() throws {
        let editor = try RelayMarkEditorSession(document: try document(markdown), persist: { _ in })
        let (coordinator, view) = mount(editor)
        defer { coordinator.retire(view) }
        select(1, in: view, coordinator)
        func actions() -> [(String, () -> Bool)] {
            #if os(macOS)
            (view.accessibilityCustomActions() ?? []).map { action in (action.name, { action.handler?() ?? false }) }
            #else
            (view.accessibilityCustomActions ?? []).map { action in (action.name, { action.actionHandler?(action) ?? false }) }
            #endif
        }
        let collapse = try #require(actions().first { $0.0 == "Collapse section" })
        #expect(collapse.1())
        #expect(editor.foldedSections == ["one"])
        let expand = try #require(actions().first { $0.0 == "Expand section" })
        #expect(expand.1())
        #expect(editor.foldedSections.isEmpty)
    }

    /// The disclosure beside a heading folds its section, on a read-only paper too.
    @Test func theHeadingsDisclosureFoldsItsSection() throws {
        let editor = try RelayMarkEditorSession(document: try document(markdown), persist: { _ in })
        let (coordinator, view) = mount(editor)
        defer { coordinator.retire(view) }
        view.isPaperEditable = false
        _ = try laidOutStarts(view)
        let geometry = try #require(RelayTextGeometry(view.textLayoutManager))
        let sub = offset(of: "Sub", in: view)
        let disclosure = try #require(view.sectionDisclosures(geometry: geometry).first { $0.heading.location == sub })
        let id = view.sectionDisclosureHit(at: CGPoint(x: disclosure.chevron.midX, y: disclosure.chevron.midY), geometry: geometry)
        #expect(id == "sub")
        #expect(view.toggleSection(try #require(id)))
        #expect(!(try laidOutStarts(view)).contains(offset(of: "Third para", in: view)))
    }

    private func containerOriginX(_ view: CollaborationTextView) -> CGFloat {
        #if os(macOS)
        view.textContainerOrigin.x
        #else
        view.textContainerInset.left
        #endif
    }

    private func disclosure(_ heading: String, in view: CollaborationTextView) throws -> (RelayHeadingDisclosure, RelayTextGeometry) {
        _ = try laidOutStarts(view)
        let geometry = try #require(RelayTextGeometry(view.textLayoutManager))
        let location = offset(of: heading, in: view)
        return (try #require(view.sectionDisclosures(geometry: geometry).first { $0.heading.location == location }), geometry)
    }

    /// As on the web, the chevron sits in a gutter before the heading's text,
    /// 1.5rem wide, and the paper's leading margin makes room for it.
    @Test func theChevronSitsInTheLeadingGutterBeforeItsHeading() throws {
        let editor = try RelayMarkEditorSession(document: try document(markdown), persist: { _ in })
        let (coordinator, view) = mount(editor)
        defer { coordinator.retire(view) }
        let (disclosure, geometry) = try disclosure("Sub", in: view)
        let text = try #require(geometry.characterFrame(at: disclosure.heading.location))
        #expect(disclosure.chevron.width == 24 && disclosure.chevron.height == 24)
        #expect(abs(disclosure.chevron.maxX - text.minX) < 0.5)
        #expect(disclosure.chevron.minX + containerOriginX(view) >= 0, "the gutter is outside the view")
        // The text keeps its trailing margin: the wider leading one narrows it.
        let width = try #require(view.textContainer).size.width
        #expect(abs(containerOriginX(view) + width + RelayPaperMargins.trailing - view.bounds.width) < 0.5)
    }

    /// A folded heading shows an expand control after its text, as the web's "…"
    /// does, and it unfolds the section.
    @Test func aFoldedHeadingHasAnExpandControlAfterItsText() throws {
        let editor = try RelayMarkEditorSession(document: try document(markdown), persist: { _ in })
        let (coordinator, view) = mount(editor)
        defer { coordinator.retire(view) }
        #expect(try disclosure("Sub", in: view).0.expand == nil)
        #expect(view.toggleSection("sub"))
        let (disclosure, geometry) = try disclosure("Sub", in: view)
        let expand = try #require(disclosure.expand)
        let last = try #require(geometry.characterFrame(at: NSMaxRange(disclosure.heading) - 1))
        #expect(expand.minX >= last.maxX + 7.5)
        #expect(view.sectionDisclosureHit(at: CGPoint(x: expand.midX, y: expand.midY), geometry: geometry) == "sub")
    }

    /// Where a pointer can hover, the chevron shows on the hovered heading or the
    /// heading holding the caret, as on the web; elsewhere it always shows.
    @Test func chevronsFollowThePointerWhereThereIsOne() throws {
        let editor = try RelayMarkEditorSession(document: try document(markdown), persist: { _ in })
        let (coordinator, view) = mount(editor)
        defer { coordinator.retire(view) }
        #if os(macOS)
        #expect(view.paper.disclosuresFollowPointer)
        #else
        #expect(!view.paper.disclosuresFollowPointer)
        #endif
        view.paper.disclosuresFollowPointer = true
        select(offset(of: "Fourth para", in: view), in: view, coordinator)
        #expect(try !disclosure("Sub", in: view).0.shown)
        view.paper.hoveredHeading = offset(of: "Sub", in: view)
        #expect(try disclosure("Sub", in: view).0.shown)
        view.paper.hoveredHeading = nil
        select(offset(of: "Sub", in: view) + 1, in: view, coordinator)
        #expect(try disclosure("Sub", in: view).0.shown)
        view.paper.disclosuresFollowPointer = false
        select(offset(of: "Fourth para", in: view), in: view, coordinator)
        #expect(try disclosure("Sub", in: view).0.shown)
    }

    /// Every edit redraws the headings' disclosures. They are found from the
    /// laid-out text, so a paper of two thousand headings costs what a short one does.
    @Test func drawingHeadingDisclosuresCostsTheSameAtAnyLength() throws {
        func paper(bytes: Int) throws -> (RelayMarkEditorSession, RelayMarkEditorView.TextCoordinator, CollaborationTextView) {
            let paragraph = String(repeating: "Lorem ipsum dolor sit amet. ", count: 4)
            var parts: [String] = [], size = 0
            while size < bytes { let part = parts.count % 5 == 0 ? "## Heading \(parts.count)" : paragraph; parts.append(part); size += part.utf8.count + 2 }
            let editor = try RelayMarkEditorSession(document: try document(parts.joined(separator: "\n\n")), persist: { _ in })
            let (coordinator, view) = mount(editor)
            view.textLayoutManager?.textViewportLayoutController.layoutViewport()
            return (editor, coordinator, view)
        }
        let small = try paper(bytes: 1_024), large = try paper(bytes: 1_048_576)
        defer { small.1.retire(small.2); large.1.retire(large.2) }
        let clock = ContinuousClock()
        var costs: ([Duration], [Duration]) = ([], [])
        for round in 0..<7 {
            for (index, paper) in [small, large].enumerated() {
                #expect(paper.0.typeNatively(range: NSRange(location: 30 + round, length: 0), replacement: "a"))
                paper.1.update(paper.2)
                let geometry = try #require(RelayTextGeometry(paper.2.textLayoutManager))
                let start = clock.now
                #expect(!paper.2.sectionDisclosures(geometry: geometry).isEmpty)
                if index == 0 { costs.0.append(clock.now - start) } else { costs.1.append(clock.now - start) }
            }
        }
        let a = costs.0.sorted()[3], b = costs.1.sorted()[3]
        print("Heading disclosures median: 1 KB \(a), 1 MB \(b)")
        #expect(RelayMarkEditorEditCostTests.withinGate(b, of: a))
    }
}
