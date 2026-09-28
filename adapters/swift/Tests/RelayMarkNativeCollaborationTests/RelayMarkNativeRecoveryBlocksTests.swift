import Foundation
import XCTest
import RelayMarkCollaboration
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeRecoveryBlocksTests: XCTestCase {
    private func fixture(_ name: String) throws -> RelayMarkNativeDocument {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        let receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(receipt["update"] as? String)))
        let doc = RelayMarkNativeDocument()
        try doc.applyUpdate(update)
        return doc
    }
    private func blocks(_ snapshot: Data) throws -> [[String: Any]] {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
        return try XCTUnwrap(root["children"] as? [[String: Any]])
    }
    private func withoutBlockIDs(_ node: [String: Any]) -> [String: Any] {
        var result = node
        if var attrs = node["attributes"] as? [String: Any] {
            attrs.removeValue(forKey: "relaymarkId"); result["attributes"] = attrs
        }
        if let children = node["children"] as? [[String: Any]] { result["children"] = children.map(withoutBlockIDs) }
        return result
    }
    private func json(_ nodes: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: nodes, options: [.sortedKeys])
    }

    func testOfferedRichBlocksAppendWithoutReplacingCurrentContentAndReplayAndUndo() throws {
        var receipts: [[String: Any]] = []
        for name in ["markdown-blocks-v3-draft", "table-mixed-v3-draft", "task-list-v3-draft",
                     "inline-atoms-v3-draft", "inline-offered-marks-v3-draft", "rich-image-v3-draft",
                     "rich-video-v3-draft", "rich-callout-v3-draft", "paper-controls-v3-draft",
                     "agent-suggestion-v3-draft"] {
            let source = try fixture(name), target = try fixture(name)
            let baseline = try target.encodeUpdate(), initial = try target.snapshot()
            let original = try blocks(initial), selected = Array(original.indices)
            let update = try target.appendRecoveredMarkdownV3Blocks(from: source.snapshot(),
                indices: selected, expectedSnapshot: initial)
            receipts.append(["name": name, "seed": baseline.base64EncodedString(), "update": update.base64EncodedString()])
            let restored = try blocks(target.snapshot())
            XCTAssertEqual(try json(Array(restored.prefix(original.count))), try json(original), name)
            XCTAssertEqual(try json(Array(restored.dropFirst(original.count)).map(withoutBlockIDs)),
                try json(original.map(withoutBlockIDs)), name)
            // The canonical projection rejects any duplicate block IDs or invalid shapes.
            _ = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: target)
            let peer = try RelayMarkCollaborationDocument()
            try peer.applyUpdate(baseline); try peer.applyUpdate(update)
            XCTAssertEqual(try json(blocks(peer.snapshot())), try json(blocks(target.snapshot())), name)
            let cold = RelayMarkNativeDocument()
            try cold.applyUpdate(baseline); try cold.applyUpdate(update)
            XCTAssertEqual(try cold.snapshot(), try target.snapshot(), name)
            _ = try target.undo()
            XCTAssertEqual(try target.snapshot(), initial, name)
        }
        if let output = ProcessInfo.processInfo.environment["RELAY_NATIVE_RECOVERY_V3_FIXTURE_OUTPUT"] {
            try JSONSerialization.data(withJSONObject: ["source": "Community YSwift/Yrs retained-block append over existing TipTap fixtures",
                "receipts": receipts], options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: output))
        }
    }

    func testOnlyChosenBlocksAreAddedAndStaleOrInvalidSelectionCannotMutate() throws {
        let source = try fixture("markdown-blocks-v3-draft"), target = try fixture("markdown-blocks-v3-draft")
        let initial = try target.snapshot(), old = try blocks(initial)
        _ = try target.appendRecoveredMarkdownV3Blocks(from: source.snapshot(), indices: [1], expectedSnapshot: initial)
        let changed = try target.snapshot(), result = try blocks(changed)
        XCTAssertEqual(result.count, old.count + 1)
        XCTAssertEqual(try json([withoutBlockIDs(try XCTUnwrap(result.last))]), try json([withoutBlockIDs(old[1])]))
        XCTAssertThrowsError(try target.appendRecoveredMarkdownV3Blocks(from: source.snapshot(), indices: [1], expectedSnapshot: initial))
        for selection in [[], [-1], [99999], [0, 0], [1, 0]] {
            XCTAssertThrowsError(try target.appendRecoveredMarkdownV3Blocks(from: source.snapshot(), indices: selection, expectedSnapshot: changed))
            XCTAssertEqual(try target.snapshot(), changed)
        }
        XCTAssertThrowsError(try target.appendRecoveredMarkdownV3Blocks(from: Data("{}".utf8), indices: [0], expectedSnapshot: changed))
        XCTAssertEqual(try target.snapshot(), changed)
    }
}
