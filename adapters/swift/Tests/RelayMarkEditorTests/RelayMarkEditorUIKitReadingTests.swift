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
