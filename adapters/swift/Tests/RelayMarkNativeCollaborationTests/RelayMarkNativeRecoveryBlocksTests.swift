import Foundation
import XCTest
import RelayMarkCollaboration
@testable import RelayMarkSwift
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
    func testReviewedImportedRegionsConsumeSameObservationWithoutDeclaringHumanInput() throws {
        let source = RelayMarkNativeDocument(), target = RelayMarkNativeDocument()
        _ = try source.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("Same **🌍**\n\nSame **🌍**", namespace: "reviewed-regions-donor"))
        _ = try target.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("Current peer prefix", namespace: "reviewed-regions-target"))
        let before = try target.snapshot(), beforeState = try target.encodeUpdate(), observation = try target.captureContentEditObservation()
        let beforeIdentity = try JSONSerialization.jsonObject(with: target.captureIdentitySnapshot())
        let beforeFootprint = try XCTUnwrap(JSONSerialization.jsonObject(with: target.captureUpdateFootprint(Data([0, 0]))) as? [String: Any])
        let archive = try source.captureIdentitySnapshot(), reviewed = try source.authoredDocument()
        let change = try target.appendRecoveredRichBlocks(from: source.snapshot(), indices: [0, 1], expectedSnapshot: before)
        let review = try JSONSerialization.data(withJSONObject: [
            "archive_sha256": String(repeating: "a", count: 64),
            "reviewed_document_sha256": String(repeating: "b", count: 64),
            "block_indices": [0, 1], "target_guard": ["body_revision": "sha256:" + String(repeating: "c", count: 64)],
            "donor_cut": NSNull()
        ], options: [.sortedKeys])
        let bytes = try target.buildReviewedRecoveryWitness(observation, steps: change.steps, update: change.update,
            reviewedRecovery: review, archiveIdentitySnapshot: archive, reviewedDocument: reviewed)
        let proof = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual((proof["text_items"] as? [String: [[String: Any]]])?["runs"]?.count, 0)
        let regions = try XCTUnwrap(proof["recovery_regions"] as? [[String: Any]])
        XCTAssertEqual(regions.compactMap { $0["count"] as? Int }.reduce(0, +), 14)
        XCTAssertEqual(Set(regions.compactMap { ($0["archive_path"] as? [Int])?.first }), [0, 1])
        XCTAssertEqual(proof["requires_recovery_authorization"] as? Bool, true)
        XCTAssertNil(proof["complete_mutation_correspondence"])
        let regional: [String: Any] = ["archive_identity_snapshot": try JSONSerialization.jsonObject(with: archive), "recovery_regions": regions]
        let sourceBytes = try RelayMarkContentEditCodec.reviewedRecoverySourceSelection(JSONSerialization.data(withJSONObject: regional))
        let selected = try XCTUnwrap(JSONSerialization.jsonObject(with: sourceBytes) as? [String: Any])
        let mappedBytes = try RelayMarkContentEditCodec.mapReviewedRecoverySelection(JSONSerialization.data(withJSONObject: regional.merging(["source_selector": selected]) { _, new in new }))
        let mapped = try XCTUnwrap(JSONSerialization.jsonObject(with: mappedBytes) as? [String: Any])
        let destinations = try XCTUnwrap(mapped["destination"] as? [String: Any])
        XCTAssertEqual((destinations["runs"] as? [[String: Any]])?.compactMap { $0["count"] as? Int }.reduce(0, +), 14)
        let empty = try RelayMarkContentEditCodec.mapReviewedRecoverySelection(JSONSerialization.data(withJSONObject: regional.merging(["source_selector": ["runs": []]]) { _, new in new }))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: empty) as? [String: [String: [Any]]])?["destination"]?["runs"]?.count, 0)
        // The same actual append is independently replayed by the shipped
        // maintained binding before the stateless classifier sees any source fact.
        let operation = try XCTUnwrap(proof["operation"] as? [String: Any])
        let afterIdentity = try JSONSerialization.jsonObject(with: target.captureIdentitySnapshot())
        var retainedInput: [String: Any] = [
            "sender_before_snapshot": beforeIdentity, "sender_after_snapshot": afterIdentity,
            "before_snapshot": beforeIdentity, "after_snapshot": afterIdentity,
            "before_state_vector": try XCTUnwrap(beforeFootprint["state_vector"]),
            "operation": operation, "footprint": try JSONSerialization.jsonObject(with: target.captureUpdateFootprint(change.update)),
            "regional_context": ["recovery_regions": regions, "human_destinations": ["runs": []]]
        ]
        let retained = try XCTUnwrap(JSONSerialization.jsonObject(with: RelayMarkContentEditCodec.prepareRetainedReviewedRecoveryWitness(JSONSerialization.data(withJSONObject: retainedInput))) as? [String: Any])
        XCTAssertEqual((retained["text_items"] as? [String: [Any]])?["runs"]?.count, 0)
        XCTAssertEqual(retained["requires_mutation_correspondence"] as? Bool, true)
        XCTAssertEqual(retained["complete_recovery_correspondence"] as? Bool, true)
        XCTAssertNil(retained["complete_mutation_correspondence"])
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: retained["recovery_regions"]!, options: [.sortedKeys]), try JSONSerialization.data(withJSONObject: regions, options: [.sortedKeys]))
        retainedInput["regional_context"] = ["recovery_regions": [], "human_destinations": ["runs": []]]
        XCTAssertThrowsError(try RelayMarkContentEditCodec.prepareRetainedReviewedRecoveryWitness(JSONSerialization.data(withJSONObject: retainedInput)))
        let fresh = try XCTUnwrap(proof["fresh_items"] as? [String: [[String: Any]]])
        let writer = try XCTUnwrap((fresh["runs"]?.first?["item"] as? [String: Any])?["client"])
        let replayInput: [String: Any] = ["sender_state_base64": beforeState.base64EncodedString(), "current_state_base64": beforeState.base64EncodedString(), "writer_client": writer, "operation": operation, "footprint": try JSONSerialization.jsonObject(with: target.captureUpdateFootprint(change.update))]
        let replayBytes = try RelayMarkPortableRuntime.call(resource: "content-edit-runtime", global: "RelayMarkContentEditRuntime", operation: "replayContentEditMutation", arguments: [replayInput])
        let replay = try XCTUnwrap(JSONSerialization.jsonObject(with: replayBytes) as? [String: Any])
        XCTAssertEqual(replay["complete_mutation_correspondence"] as? Bool, true)
        let completeProof = proof.merging(replay) { _, new in new }
        let binding: [String: Any] = ["document_id": "target", "incarnation": "incarnation"]
        let transactionID = "22222222-2222-4222-8222-222222222222"
        let transaction: [String: Any] = ["transaction_id": transactionID, "text_items": proof["text_items"]!, "content_edit": operation]
        var destinationRuns = try XCTUnwrap(destinations["runs"] as? [[String: Any]])
        // An independently authenticated donor subset: exactly the first2units.
        destinationRuns = [destinationRuns[0]]; destinationRuns[0]["count"] = 2
        let human: [String: Any] = ["runs": destinationRuns]
        let context: [String: Any] = ["recovery_regions": regions, "human_destinations": human]
        func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
        let reference = try RelayMarkSourceCodec.classifyContentEditReference(binding: data(binding), transaction: data(transaction), proof: data(completeProof), humanAncestry: data(["runs": []]), regionalContext: data(context))
        let referenceObject = try XCTUnwrap(JSONSerialization.jsonObject(with: reference) as? [String: Any])
        XCTAssertEqual(referenceObject["human_destinations"] as? NSDictionary, human as NSDictionary)
        let folded = try RelayMarkSourceCodec.foldSourceReferences(binding: data(binding), candidateSelector: data(destinations), references: data([referenceObject]), regionalContexts: data([transactionID: context]))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: folded) as? NSDictionary, human as NSDictionary)
        XCTAssertThrowsError(try RelayMarkSourceCodec.classifyContentEditReference(binding: data(binding), transaction: data(transaction), proof: data(completeProof), humanAncestry: data(["runs": []])))
        let partitionBytes = try RelayMarkSourceCodec.partitionReviewedRecoveryDestinations(data(context.merging(["generated_destinations": ["runs": []]]) { _, new in new }))
        let partition = try XCTUnwrap(JSONSerialization.jsonObject(with: partitionBytes) as? [String: Any])
        let unknown = try XCTUnwrap(partition["unknown_destinations"] as? [String: [[String: Any]]])
        XCTAssertEqual(unknown["runs"]?.compactMap { $0["count"] as? Int }.reduce(0, +), 12)

        var forgedRuns = try XCTUnwrap(selected["runs"] as? [[String: Any]])
        forgedRuns[0]["type"] = ["client": 999999, "clock": 0]
        XCTAssertThrowsError(try RelayMarkContentEditCodec.mapReviewedRecoverySelection(JSONSerialization.data(withJSONObject: regional.merging(["source_selector": ["runs": forgedRuns]]) { _, new in new })))
        let frozenState = try target.encodeUpdate()
        XCTAssertThrowsError(try target.buildReviewedRecoveryWitness(observation, steps: change.steps, update: change.update,
            reviewedRecovery: review, archiveIdentitySnapshot: archive, reviewedDocument: reviewed))
        XCTAssertEqual(try target.encodeUpdate(), frozenState)
    }

}
