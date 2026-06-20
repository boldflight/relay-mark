import XCTest
@testable import RelayMarkSwift

final class RelayMarkSwiftTests: XCTestCase {
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
