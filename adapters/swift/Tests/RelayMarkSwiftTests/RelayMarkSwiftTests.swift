import XCTest
@testable import RelayMarkSwift

final class RelayMarkSwiftTests: XCTestCase {
    func testDecodesInlineEntityReferenceWithIDAsInlineContent() throws {
        let data = Data(
            #"{"type":"relaymark.document","version":1,"blocks":[{"id":"b1","type":"paragraph","content":[{"type":"relay.entity_ref","id":"product-1","label":"Mac mini"}]}]}"#.utf8
        )

        let document = try RelayMarkDocument.decodeJSON(data)

        guard case let .inline(reference) = document.blocks[0].content[0] else {
            return XCTFail("Expected an inline entity reference")
        }

        XCTAssertEqual(reference.type, "relay.entity_ref")
        XCTAssertEqual(reference.id, "product-1")
        XCTAssertEqual(reference.label, "Mac mini")
    }

    func testDecodesRelayMarkDocumentFixture() throws {
        let document = try RelayMarkDocument.decodeJSON(fixtureData("mentor-meeting.ast.json"))

        XCTAssertEqual(document.type, "relaymark.document")
        XCTAssertEqual(document.version, 1)
        XCTAssertEqual(document.frontmatter["title"]?.stringValue, "Marcus interview prep")
        XCTAssertEqual(document.blocks.count, 5)

        let sourceBundle = document.blocks[2]
        XCTAssertEqual(sourceBundle.id, "src-1")
        XCTAssertEqual(sourceBundle.type, "relay.source_bundle")
        XCTAssertEqual(sourceBundle.props["scope"]?.stringValue, "private")
        XCTAssertEqual(sourceBundle.childBlocks.first?.type, "relay.transcript_segment")

        let action = document.blocks[4]
        XCTAssertEqual(action.type, "relay.action_row")
        XCTAssertEqual(action.props["action"]?.stringValue, "relay.task.create")
        XCTAssertEqual(action.evidenceRefs, ["src-1"])
        XCTAssertEqual(action.plainText, "Send interview prep resources before Thursday.")
    }

    func testDecodesRelayMarkManifestFixture() throws {
        let manifest = try RelayMarkManifest.decodeJSON(fixtureData("mentor-meeting.manifest.json"))

        XCTAssertEqual(manifest.type, "relaymark.manifest")
        XCTAssertEqual(manifest.actions.count, 1)
        XCTAssertEqual(manifest.actions[0].blockID, "b5")
        XCTAssertEqual(manifest.actions[0].action, "relay.task.create")
        XCTAssertEqual(manifest.actions[0].args["title"]?.stringValue, "Send interview prep resources before Thursday.")
        XCTAssertEqual(manifest.sources.map(\.kind), ["source_bundle", "transcript_range"])
        XCTAssertTrue(manifest.diagnostics.isEmpty)
    }

    func testDecodesProductResearchDocumentFixture() throws {
        let document = try RelayMarkDocument.decodeJSON(fixtureData("product-research.ast.json"))

        XCTAssertEqual(document.blocks.count, 9)

        guard case let .inline(productReference) = document.blocks[1].content[1] else {
            return XCTFail("Expected a product reference to remain inline")
        }

        XCTAssertEqual(productReference.type, "relay.product_ref")
        XCTAssertEqual(productReference.id, "product-mac-mini-m4-pro")
        XCTAssertEqual(productReference.label, "Mac mini with M4 Pro")

        let sourceBundle = document.blocks[2]
        XCTAssertEqual(sourceBundle.childBlocks.map(\.type), ["relay.url_ref", "relay.url_ref"])

        let comparison = document.blocks[4]
        XCTAssertEqual(comparison.type, "relay.comparison")
        XCTAssertEqual(comparison.evidenceRefs, ["src-apple", "src-mbench"])
        XCTAssertEqual(comparison.plainText, "Mac mini with M4 Pro is the lower-cost fit; Mac Studio with M4 Max leads on memory bandwidth and the imported CPU score.")
    }

    func testDecodesProductResearchManifestFixture() throws {
        let manifest = try RelayMarkManifest.decodeJSON(fixtureData("product-research.manifest.json"))

        XCTAssertEqual(manifest.actions.map(\.review), ["accepted", "rejected"])
        XCTAssertEqual(manifest.references.map(\.type), [
            "relay.product_ref",
            "relay.product_ref",
            "relay.entity_ref",
            "relay.product_ref",
            "relay.product_ref"
        ])
        XCTAssertEqual(manifest.claims.map(\.status), ["disputed", "disputed"])
        XCTAssertEqual(manifest.claims.map(\.evidenceRefs), [["src-apple"], ["src-mbench"]])
        XCTAssertEqual(manifest.comparisons.count, 1)
        XCTAssertEqual(manifest.comparisons[0].layout, "table")
        XCTAssertEqual(manifest.comparisons[0].preferred, "entity:product-mac-mini-m4-pro")
        XCTAssertEqual(
            manifest.comparisons[0].values["price_usd"]?.objectValue?["entity:product-mac-mini-m4-pro"]?.numberValue,
            1399
        )
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
