import Foundation
import Testing
@testable import RelayMarkSwift

struct RelayMarkSwiftTests {
    @Test
    func decodesInlineEntityReferenceWithIDAsInlineContent() throws {
        let data = Data(
            #"{"type":"relaymark.document","version":1,"blocks":[{"id":"b1","type":"paragraph","content":[{"type":"relay.entity_ref","id":"product-1","label":"Mac mini"}]}]}"#.utf8
        )

        let document = try RelayMarkDocument.decodeJSON(data)

        guard case let .inline(reference) = document.blocks[0].content[0] else {
            Issue.record("Expected an inline entity reference")
            return
        }

        #expect(reference.type == "relay.entity_ref")
        #expect(reference.id == "product-1")
        #expect(reference.label == "Mac mini")
    }

    @Test
    func decodesRelayMarkDocumentFixture() throws {
        let document = try RelayMarkDocument.decodeJSON(fixtureData("mentor-meeting.ast.json"))

        #expect(document.type == "relaymark.document")
        #expect(document.version == 1)
        #expect(document.frontmatter["title"]?.stringValue == "Marcus interview prep")
        #expect(document.blocks.count == 5)

        let sourceBundle = document.blocks[2]
        #expect(sourceBundle.id == "src-1")
        #expect(sourceBundle.type == "relay.source_bundle")
        #expect(sourceBundle.props["scope"]?.stringValue == "private")
        #expect(sourceBundle.childBlocks.first?.type == "relay.transcript_segment")

        let action = document.blocks[4]
        #expect(action.type == "relay.action_row")
        #expect(action.props["action"]?.stringValue == "relay.task.create")
        #expect(action.evidenceRefs == ["src-1"])
        #expect(action.plainText == "Send interview prep resources before Thursday.")
    }

    @Test
    func decodesRelayMarkManifestFixture() throws {
        let manifest = try RelayMarkManifest.decodeJSON(fixtureData("mentor-meeting.manifest.json"))

        #expect(manifest.type == "relaymark.manifest")
        #expect(manifest.actions.count == 1)
        #expect(manifest.actions[0].blockID == "b5")
        #expect(manifest.actions[0].action == "relay.task.create")
        #expect(manifest.actions[0].args["title"]?.stringValue == "Send interview prep resources before Thursday.")
        #expect(manifest.sources.map(\.kind) == ["source_bundle", "transcript_range"])
        #expect(manifest.diagnostics.isEmpty)
    }

    @Test
    func decodesProductResearchDocumentFixture() throws {
        let document = try RelayMarkDocument.decodeJSON(fixtureData("product-research.ast.json"))

        #expect(document.blocks.count == 9)

        guard case let .inline(productReference) = document.blocks[1].content[1] else {
            Issue.record("Expected a product reference to remain inline")
            return
        }

        #expect(productReference.type == "relay.product_ref")
        #expect(productReference.id == "product-mac-mini-m4-pro")
        #expect(productReference.label == "Mac mini with M4 Pro")

        let sourceBundle = document.blocks[2]
        #expect(sourceBundle.childBlocks.map(\.type) == ["relay.url_ref", "relay.url_ref"])

        let comparison = document.blocks[4]
        #expect(comparison.type == "relay.comparison")
        #expect(comparison.evidenceRefs == ["src-apple", "src-mbench"])
        #expect(comparison.plainText == "Mac mini with M4 Pro is the lower-cost fit; Mac Studio with M4 Max leads on memory bandwidth and the imported CPU score.")
    }

    @Test
    func decodesProductResearchManifestFixture() throws {
        let manifest = try RelayMarkManifest.decodeJSON(fixtureData("product-research.manifest.json"))

        #expect(manifest.actions.map(\.review) == ["accepted", "rejected"])
        #expect(manifest.references.map(\.type) == [
            "relay.product_ref",
            "relay.product_ref",
            "relay.entity_ref",
            "relay.product_ref",
            "relay.product_ref"
        ])
        #expect(manifest.claims.map(\.status) == ["disputed", "disputed"])
        #expect(manifest.claims.map(\.evidenceRefs) == [["src-apple"], ["src-mbench"]])
        #expect(manifest.comparisons.count == 1)
        #expect(manifest.comparisons[0].layout == "table")
        #expect(manifest.comparisons[0].preferred == "entity:product-mac-mini-m4-pro")
        #expect(manifest.comparisons[0].values["price_usd"]?.objectValue?["entity:product-mac-mini-m4-pro"]?.numberValue == 1399)
    }

    private func fixtureData(_ name: String) throws -> Data {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repoRoot
            .appendingPathComponent("spec")
            .appendingPathComponent("relaymark")
            .appendingPathComponent("examples")
            .appendingPathComponent(name)
        return try Data(contentsOf: fixtureURL)
    }
}
