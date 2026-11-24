import Foundation
import RelayMarkNativeCollaboration
import RelayMarkSwift
@testable import RelayMarkEditor
@testable import RelayMarkEditorCore
import Testing
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor @Suite(.serialized)
struct RelayMarkHostLinkTests {
    private let member = "/members/11111111-1111-4111-8111-111111111111"
    private final class Host: RelayMarkLinkService {
        var current = true
        var handled: [String] = []
        func handlesLink(_ href: String) -> Bool { current && (href.hasPrefix("#") || href.hasPrefix("/members/")) }
        func activateLink(_ href: String) { if handlesLink(href) { handled.append(href) } }
    }

    @Test(arguments: [false, true])
    func nativeLinksUseTheHostCatalogAndRetireWithTheirPaper(table: Bool) throws {
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        let source = table ? "| Name |\n| --- |\n| [Douglas](" + member + ") |" : "[Douglas](" + member + ")"
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "host-links"))
        let owner = try RelayMarkEditorSession(document: document, persist: { _ in })
        let host = Host(), coordinator = RelayMarkEditorView.TextCoordinator(session: owner)
        coordinator.services = RelayMarkEditorServices(links: host)
        let view = coordinator.makeTextView(accessibilityLabel: "Paper")
        defer { owner.invalidate(); coordinator.retire(view) }
        let catalog = [(member, true), ("#section", true), ("https://example.org", false)]
        if table {
            let attachment = try #require(view.paper.tables.spans.first?.table)
            let grid = attachment.grid
            for (href, accepted) in catalog {
                #expect(attachment.handlesLink?(href) == accepted)
                #if os(macOS)
                #expect(grid.textView(grid.textView, clickedOnLink: href, at: 0) == accepted)
                #else
                if accepted { attachment.activateLink?(href) }
                #endif
            }
            #expect(host.handled == [member, "#section"])
            owner.invalidate()
            #expect(attachment.handlesLink?(member) == false)
        } else {
            for (href, accepted) in catalog {
                #expect(coordinator.handlesLink?(href) == accepted)
                #if os(macOS)
                #expect(coordinator.textView(view, clickedOnLink: href, at: 0) == accepted)
                #else
                if accepted { coordinator.onActivateLink?(href) }
                #endif
            }
            #expect(host.handled == [member, "#section"])
            host.current = false
            #expect(coordinator.handlesLink?(member) == false)
            owner.invalidate()
            #if os(macOS)
            #expect(coordinator.textView(view, clickedOnLink: member, at: 0) == false)
            #endif
        }
        #expect(!owner.hasUnpersistedTransaction)
    }
}
