import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkSwift
#if os(iOS)
import UIKit
import UniformTypeIdentifiers

/// The UIKit paper as VoiceOver, the keyboard and the text system meet it:
/// one TextKit 2 view, its accessible commands, and input it must refuse.
@MainActor @Suite(.serialized)
struct RelayMarkEditorUIKitReadingTests {
    @MainActor private struct Mounted {
        let editor: RelayMarkEditorSession
        let coordinator: RelayMarkEditorView.TextCoordinator
        let view: CollaborationTextView
        let window: UIWindow
        func retire() { coordinator.retire(view); window.isHidden = true }
    }

    private func mount(_ document: RelayMarkNativeDocument, services: RelayMarkEditorServices = .init(),
                       width: CGFloat = 390) throws -> Mounted {
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        coordinator.services = services
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 600))
        window.addSubview(view)
        view.frame = window.bounds
        window.isHidden = false
        view.layoutIfNeeded()
        return Mounted(editor: editor, coordinator: coordinator, view: view, window: window)
    }

    private func mount(markdown: String, services: RelayMarkEditorServices = .init()) throws -> Mounted {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "reading"))
        return try mount(document, services: services)
    }

    private func mount(fixture name: String) throws -> Mounted {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let document = RelayMarkNativeDocument()
        let encoded = try #require(object["update"] as? String)
        try document.applyUpdate(try #require(Data(base64Encoded: encoded)))
        return try mount(document)
    }

    // MARK: TextKit 2 only

    /// UITextView silently and permanently drops to TextKit 1 for content it
    /// cannot lay out on TextKit 2. Every kind of paper content must keep it.
    @Test(arguments: ["rich-image-v3-draft", "rich-callout-v3-draft", "rich-quote-v3",
                      "entity-reference-v3-draft", "inline-atoms-v3-draft", "paper-controls-v3-draft",
                      "table-mixed-v3-draft", "task-list-v3-draft", "markdown-blocks-v3-draft"])
    func everyKindOfPaperStaysOnTextKit2(fixture: String) throws {
        let paper = try mount(fixture: fixture)
        defer { paper.retire() }
        let manager = try #require(paper.view.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        paper.view.setContentOffset(CGPoint(x: 0, y: max(0, paper.view.contentSize.height - 600)), animated: false)
        paper.view.layoutIfNeeded()
        paper.view.layer.displayIfNeeded()
        #expect(paper.view.textLayoutManager != nil, "\(fixture) switched the paper to TextKit 1")
    }

    @Test func scriptsAndDirectionsStayOnTextKit2() throws {
        let paper = try mount(markdown: """
        # עברית ו-English באותה שורה

        مرحبا بالعالم، هذا نص عربي طويل يلتف على عدة أسطر في الورقة.

        - [ ] हिन्दी में कार्य
        - [x] ಕನ್ನಡ ಪಠ್ಯ 👩‍👩‍👧‍👦 🇯🇵

        日本語の文章です。
        """)
        defer { paper.retire() }
        let manager = try #require(paper.view.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        paper.view.layer.displayIfNeeded()
        #expect(paper.view.textLayoutManager != nil)
    }

    /// Rich HTML holding a table goes to the host as a structured paste; none of
    /// it reaches TextKit's storage, where an NSTextTable would force TextKit 1.
    @Test func pastingAnHTMLTableLeavesThePaperOnTextKit2() throws {
        let paper = try mount(markdown: "Before\n\nAfter")
        defer { paper.retire() }
        let html = "<table><tr><td>a</td><td>b</td></tr></table>"
        let provider = NSItemProvider(item: Data(html.utf8) as NSData, typeIdentifier: UTType.html.identifier)
        paper.view.selectedRanges = [NSRange(location: 6, length: 0)]
        paper.view.paste(itemProviders: [provider])
        paper.view.layoutIfNeeded()
        #expect(paper.view.textLayoutManager != nil)
        #expect(paper.view.text == "Before\nAfter")
    }

    // MARK: Input the paper cannot keep

    /// Underline is not a mark the paper can store. Offered, TextKit would show
    /// it until the next render, then drop it without saving.
    @Test func underlineIsNotOfferedAndIsRefused() throws {
        let paper = try mount(markdown: "Hello world")
        defer { paper.retire() }
        var refusals = 0
        let feedback = RelayPaperRefusal.feedback
        RelayPaperRefusal.feedback = { refusals += 1 }
        defer { RelayPaperRefusal.feedback = feedback }
        paper.window.makeKeyAndVisible()
        #expect(paper.view.becomeFirstResponder())
        paper.view.selectedRanges = [NSRange(location: 0, length: 5)]
        #expect(!paper.view.canPerformAction(#selector(UIResponderStandardEditActions.toggleUnderline(_:)), withSender: nil))
        #expect(paper.view.canPerformAction(#selector(UIResponderStandardEditActions.toggleBoldface(_:)), withSender: nil))
        paper.view.toggleUnderline(nil)
        #expect(refusals == 1)
        #expect(String(paper.editor.text.characters) == "Hello world")
    }

    /// The formatting panel offers only the paper's marks and applies them through
    /// the session; a font size the paper cannot store is refused, not shown and lost.
    @Test func theFormattingPanelAppliesOnlyThePapersMarks() throws {
        let paper = try mount(markdown: "Hello world")
        defer { paper.retire() }
        var refusals = 0
        let feedback = RelayPaperRefusal.feedback
        RelayPaperRefusal.feedback = { refusals += 1 }
        defer { RelayPaperRefusal.feedback = feedback }
        let configuration = try #require(paper.view.textFormattingConfiguration)
        #expect(configuration.groups.flatMap(\.components).map(\.componentKey) == [.fontAttributes])
        let panel = UITextFormattingViewController(configuration: configuration)
        paper.coordinator.textView(paper.view, willBeginFormattingWith: panel)
        paper.view.selectedRanges = [NSRange(location: 0, length: 5)]
        panel.delegate?.textFormattingViewController(panel, didChangeValue: .bold(true))
        let hello = try #require(paper.editor.text.runs.first)
        #expect(String(paper.editor.text[hello.range].characters) == "Hello")
        #expect(hello.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        panel.delegate?.textFormattingViewController(panel, didChangeValue: .fontSize(30))
        #expect(refusals == 1)
        let font = paper.view.textStorage.attribute(.font, at: 7, effectiveRange: nil) as? UIFont
        #expect(font.map { $0.pointSize < 30 } == true)
    }

    /// The keyboard keeps a language per context: the paper is one context,
    /// apart from search and title fields, so Japanese stays Japanese here.
    @Test func thePaperIsItsOwnKeyboardContext() throws {
        let paper = try mount(fixture: "table-mixed-v3-draft")
        defer { paper.retire() }
        #expect(paper.view.textInputContextIdentifier == "relay.paper")
        let table = try #require(paper.view.paper.tables.spans.first?.table)
        #expect(table.grid.cellView(0).textInputContextIdentifier == "relay.paper")
    }

    // MARK: Natural Selection

    /// A selection across mixed-direction text is several ranges. UIKit hands a
    /// delegate without the ranges method their union, which takes the text
    /// between them too.
    @Test func deletingABidiSelectionKeepsTheTextBetweenItsRanges() throws {
        let paper = try mount(markdown: "Hello world again")
        defer { paper.retire() }
        paper.view.selectedRanges = [NSRange(location: 0, length: 2), NSRange(location: 6, length: 5)]
        paper.view.deleteBackward()
        #expect(String(paper.editor.text.characters) == "llo  again")
        #expect(paper.view.text == "llo  again")
    }

    @Test func boldOverABidiSelectionLeavesTheTextBetweenPlain() throws {
        let paper = try mount(markdown: "Hello world again")
        defer { paper.retire() }
        paper.view.selectedRanges = [NSRange(location: 0, length: 5), NSRange(location: 12, length: 5)]
        paper.view.toggleBoldface(nil)
        func bold(_ offset: Int) -> Bool {
            paper.editor.text.runs.first { run in
                let start = paper.editor.text.characters.distance(from: paper.editor.text.startIndex, to: run.range.lowerBound)
                let end = paper.editor.text.characters.distance(from: paper.editor.text.startIndex, to: run.range.upperBound)
                return offset >= start && offset < end
            }.map { ($0.inlinePresentationIntent ?? []).contains(.stronglyEmphasized) } ?? false
        }
        #expect(bold(0) && bold(14))
        #expect(!bold(7), "the text between the ranges was formatted")
    }

    // MARK: VoiceOver

    /// A task's checkbox is drawn, not text, so VoiceOver gets its state and
    /// its toggle from an action on the paper at the caret.
    @Test func voiceOverChecksTheTaskAtTheCaret() throws {
        let paper = try mount(markdown: "- [ ] Open task\n- [x] Done task")
        defer { paper.retire() }
        paper.view.selectedRanges = [NSRange(location: 3, length: 0)]
        paper.coordinator.textViewDidChangeSelection(paper.view)
        let actions = paper.view.accessibilityCustomActions ?? []
        let check = try #require(actions.first { $0.name == "Mark as done" })
        #expect(!actions.contains { $0.name == "Mark as not done" })
        #expect(check.actionHandler?(check) == true)
        #expect(paper.editor.nativeTaskItems.first?.checked == true)
        let done = (paper.view.text as NSString).range(of: "Done")
        paper.view.selectedRanges = [NSRange(location: done.location, length: 0)]
        paper.coordinator.textViewDidChangeSelection(paper.view)
        #expect((paper.view.accessibilityCustomActions ?? []).contains { $0.name == "Mark as not done" })
    }

    /// The host's commands on selected text join VoiceOver's Edit rotor beside
    /// Cut, Copy and Paste, and act on the paper's selection.
    @Test func selectionCommandsAreInTheEditRotor() throws {
        var performed: [NSRange] = []
        var services = RelayMarkEditorServices()
        services.selectionActions = [RelayMarkSelectionAction(name: "Make Task") { performed.append($0); return true }]
        let paper = try mount(markdown: "Call Ada tomorrow", services: services)
        defer { paper.retire() }
        paper.view.selectedRanges = [NSRange(location: 5, length: 3)]
        paper.coordinator.textViewDidChangeSelection(paper.view)
        let actions = paper.view.accessibilityCustomActions ?? []
        let make = try #require(actions.first { $0.name == "Make Task" })
        #expect(make.category == UIAccessibilityCustomAction.editCategory)
        #expect(make.actionHandler?(make) == true)
        #expect(performed == [NSRange(location: 5, length: 3)])
    }

    /// Each cell is its own text view; the lines rotor and read-all move from
    /// one cell to the next in reading order instead of stopping at its edge.
    @Test func voiceOverReadsATableCellByCell() throws {
        let paper = try mount(fixture: "table-mixed-v3-draft")
        defer { paper.retire() }
        let table = try #require(paper.view.paper.tables.spans.first?.table)
        #expect(table.cells.count >= 3)
        let first = table.grid.cellView(0), second = table.grid.cellView(1)
        #expect(first.accessibilityNextTextNavigationElement as AnyObject? === second)
        #expect(second.accessibilityPreviousTextNavigationElement as AnyObject? === first)
        #expect(first.accessibilityPreviousTextNavigationElement == nil)
        let last = table.grid.cellView(table.cells.count - 1)
        #expect(last.accessibilityNextTextNavigationElement == nil)
    }

    // MARK: Task markers

    /// A right-to-left task's checkbox is on the right, where it is drawn, and a
    /// tap there toggles it; a left-to-right one's stays on the left.
    @Test(arguments: [("- [ ] مهمة عربية", true), ("- [ ] An English task", false)])
    func taskCheckboxesSitOnTheParagraphsLeadingSide(markdown: String, rightToLeft: Bool) throws {
        let paper = try mount(markdown: markdown)
        defer { paper.retire() }
        let geometry = try #require(RelayTextGeometry(paper.view.textLayoutManager))
        let item = try #require(paper.view.paper.viewTaskItems.first)
        let text = geometry.segmentFrames(item.firstParagraphRange).reduce(CGRect.null) { $0.union($1) }
        let inset = paper.view.textContainerInset
        let x = rightToLeft ? text.maxX + 12 : text.minX - 12
        let point = CGPoint(x: x + inset.left, y: text.midY + inset.top)
        #expect(paper.view.taskCheckboxOffset(at: point) == item.firstParagraphRange.location)
    }

    /// A tap is hit-tested against the tasks on its line, not by laying out
    /// every task in the paper. A tap on a task's text is the worst case: no
    /// checkbox is under it.
    @Test func aTaskTapCostsTheSameInAShortAndALongList() throws {
        func cost(tasks: Int) throws -> Duration {
            let paper = try mount(markdown: (1...tasks).map { "- [ ] Task number \($0)" }.joined(separator: "\n"))
            defer { paper.retire() }
            let geometry = try #require(RelayTextGeometry(paper.view.textLayoutManager))
            let item = try #require(paper.view.paper.viewTaskItems.first)
            let text = try #require(geometry.characterFrame(at: item.firstParagraphRange.location + 3))
            let inset = paper.view.textContainerInset
            let point = CGPoint(x: text.midX + inset.left, y: text.midY + inset.top)
            let clock = ContinuousClock()
            var samples: [Duration] = []
            for _ in 0..<5 {
                let start = clock.now
                #expect(paper.view.taskCheckboxOffset(at: point) == nil)
                samples.append(clock.now - start)
            }
            return samples.sorted()[2]
        }
        let short = try cost(tasks: 20), long = try cost(tasks: 2_000)
        print("Task tap median: 20 tasks \(short), 2000 tasks \(long)")
        #expect(long <= short * 4 + .milliseconds(5))
    }
}
#endif
