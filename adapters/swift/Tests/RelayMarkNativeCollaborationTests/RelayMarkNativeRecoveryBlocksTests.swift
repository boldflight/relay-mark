import Foundation
import XCTest
import RelayMarkCollaboration
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeRecoveryBlocksTests: XCTestCase {
    private func fixture(_ name: String) throws -> RelayMarkNativeDocument {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        let receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(receipt["update"] as? String)))
        let doc = RelayMarkNativeDocument()
        try doc.applyUpdate(update)
        // Exact old fixture bytes remain unchanged. Commands start only after
        // the finite shared importer records/removes obsolete derived attrs.
        let prepared = try RelayMarkNativeSnapshotImport.prepare(document: doc,
            namespace: "retained-recovery-" + name, expectedSnapshot: doc.snapshot())
        _ = try RelayMarkNativeSnapshotImport.install(document: doc, prepared: prepared)
        return doc
    }
    private func blocks(_ snapshot: Data) throws -> [[String: Any]] {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
        return try XCTUnwrap(root["children"] as? [[String: Any]])
    }
    private func withoutCopiedIdentities(_ node: [String: Any]) -> [String: Any] {
        var result = node
        if var attrs = node["attributes"] as? [String: Any] {
            attrs.removeValue(forKey: "relaymarkId")
            if node["name"] as? String == "heading" { attrs.removeValue(forKey: "headingId") }
            result["attributes"] = attrs
        }
        if let children = node["children"] as? [[String: Any]] { result["children"] = children.map(withoutCopiedIdentities) }
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
            let update = try target.appendRecoveredRichBlocks(from: source.snapshot(),
                indices: selected, expectedSnapshot: initial)
            receipts.append(["name": name, "seed": baseline.base64EncodedString(), "update": update.update.base64EncodedString()])
            let restored = try blocks(target.snapshot())
            XCTAssertEqual(try json(Array(restored.prefix(original.count))), try json(original), name)
            XCTAssertEqual(try json(Array(restored.dropFirst(original.count)).map(withoutCopiedIdentities)),
                try json(original.map(withoutCopiedIdentities)), name)
            // The canonical projection rejects any duplicate block IDs or invalid shapes.
            _ = try RelayMarkNativeDocumentProjection.project(document: target)
            let peer = try RelayMarkCollaborationDocument()
            try peer.applyUpdate(baseline); try peer.applyUpdate(update.update)
            XCTAssertEqual(try json(blocks(peer.snapshot())), try json(blocks(target.snapshot())), name)
            let cold = RelayMarkNativeDocument()
            try cold.applyUpdate(baseline); try cold.applyUpdate(update.update)
            XCTAssertEqual(try cold.snapshot(), try target.snapshot(), name)
            _ = try target.undo()
            XCTAssertEqual(try target.snapshot(), initial, name)
        }
        if let output = ProcessInfo.processInfo.environment["RELAY_NATIVE_RECOVERY__FIXTURE_OUTPUT"] {
            try JSONSerialization.data(withJSONObject: ["source": "Community YSwift/Yrs retained-block append over existing TipTap fixtures",
                "receipts": receipts], options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: output))
        }
    }

    func testReviewedRecoveryAppendHasActualStepAndPreservesExistingIdentityAndMetadata() throws {
        let target = RelayMarkNativeDocument(), source = RelayMarkNativeDocument()
        var ast = try JSONSerialization.jsonObject(with: RelayMarkSourceCodec.parseDocument("Current", namespace: "current-recovery")) as! [String: Any]
        ast["meta"] = ["provider": "retained"]
        _ = try target.initializeDocument(authoredAST: JSONSerialization.data(withJSONObject: ast))
        _ = try source.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("@Callout(tone: \"warning\") {\nRecovered **rich** 🌍\n}", namespace: "reviewed-recovery"))
        let initial = try target.snapshot(), beforeIdentity = try target.captureIdentitySnapshot()
        let change = try target.appendRecoveredRichBlocks(from: source.snapshot(), indices: [0], expectedSnapshot: initial)
        let steps = try XCTUnwrap(JSONSerialization.jsonObject(with: change.steps) as? [[String: Any]])
        XCTAssertEqual(steps.first?["stepType"] as? String, "replace")
        XCTAssertEqual(steps.first?["from"] as? Int, 9)
        XCTAssertEqual(steps.first?["to"] as? Int, 9)
        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(target.encodeUpdate())
        XCTAssertEqual(try peer.authoredDocument(), try target.authoredDocument())
        let old = try XCTUnwrap(JSONSerialization.jsonObject(with: beforeIdentity) as? [String: Any])
        let current = try XCTUnwrap(JSONSerialization.jsonObject(with: target.captureIdentitySnapshot()) as? [String: Any])
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: (old["children"] as! [Any])[0], options: .sortedKeys),
                       try JSONSerialization.data(withJSONObject: (current["children"] as! [Any])[0], options: .sortedKeys))
        let afterAST = try XCTUnwrap(JSONSerialization.jsonObject(with: target.authoredDocument()) as? [String: Any])
        XCTAssertEqual(afterAST["meta"] as? [String: String], ["provider": "retained"])
        _ = try target.undo()
        XCTAssertEqual(try target.snapshot(), initial)
    }

    func testOnlyChosenBlocksAreAddedAndStaleOrInvalidSelectionCannotMutate() throws {
        let source = try fixture("markdown-blocks-v3-draft"), target = try fixture("markdown-blocks-v3-draft")
        let initial = try target.snapshot(), old = try blocks(initial)
        _ = try target.appendRecoveredRichBlocks(from: source.snapshot(), indices: [1], expectedSnapshot: initial)
        let changed = try target.snapshot(), result = try blocks(changed)
        XCTAssertEqual(result.count, old.count + 1)
        XCTAssertEqual(try json([withoutCopiedIdentities(try XCTUnwrap(result.last))]), try json([withoutCopiedIdentities(old[1])]))
        XCTAssertThrowsError(try target.appendRecoveredRichBlocks(from: source.snapshot(), indices: [1], expectedSnapshot: initial))
        for selection in [[], [-1], [99999], [0, 0], [1, 0]] {
            XCTAssertThrowsError(try target.appendRecoveredRichBlocks(from: source.snapshot(), indices: selection, expectedSnapshot: changed))
            XCTAssertEqual(try target.snapshot(), changed)
        }
        XCTAssertThrowsError(try target.appendRecoveredRichBlocks(from: Data("{}".utf8), indices: [0], expectedSnapshot: changed))
        XCTAssertEqual(try target.snapshot(), changed)
    }
}
