import Foundation
import Testing
@testable import RelayMarkCollaboration

@MainActor
struct RelayMarkProseLineageTests {
    @Test("Placement candidates preserve exact local formatting references through atomic export and restart")
    func placementBridgeRoundTrip() throws {
        let baseline = try seed(), document = try RelayMarkCollaborationDocument(), operationID = UUID(), inverseID = UUID()
        try document.applyUpdate(baseline.encodeUpdate())
        let binding = RelayMarkCollaborationDocument.PlacementBinding(documentID: UUID(), incarnation: "one")
        let updates = try document.editNativeFormatting(Data(#"{"kind":"formatText","path":[0,0],"index":0,"length":6,"attributes":{"italic":{}}}"#.utf8), operationID: operationID)
        let update = try document.mergeUpdates(updates)
        let candidate = try document.prepareLocalPlacementReceipt(update: update, binding: binding)
        #expect(candidate.receiptIDs == [operationID])
        let unchanged = try document.exportHistoryState(scopeToken: "old")
        #expect(unchanged.placementReceiptIDs.isEmpty)
        let saved = try document.exportHistoryState(scopeToken: "cut1", placementCandidate: candidate)
        #expect(saved.placementReceiptIDs == [operationID])
        try document.commitPlacementReceipt(candidate)
        let inverse = try document.undoWithEvidence(operationID: inverseID)
        let inverseCandidate = try document.prepareLocalPlacementReceipt(update: document.mergeUpdates(inverse.updates), binding: binding)
        let last = try #require(JSONSerialization.jsonObject(with: inverseCandidate.receipt) as? [String: Any])
        let operation = try #require(last["operation"] as? [String: String])
        #expect(operation["kind"] == "undo" && operation["reference"] == operationID.uuidString.lowercased())
        let second = try document.exportHistoryState(scopeToken: "cut2", placementCandidate: inverseCandidate)
        let restored = try RelayMarkCollaborationDocument(), pristine = try restored.encodeUpdate()
        #expect(throws: (any Error).self) {
            try restored.restoreHistorySnapshot(second.bytes, scopeToken: "cut2", transactionIDs: second.transactionIDs)
        }
        #expect(try restored.encodeUpdate() == pristine)
        try restored.restoreHistorySnapshot(second.bytes, scopeToken: "cut2", transactionIDs: second.transactionIDs,
            placementBinding: binding, placementReceiptIDs: second.placementReceiptIDs)
        let reopened = try restored.exportHistoryState(scopeToken: "cut2")
        #expect(reopened.placementReceiptIDs == [operationID, inverseID])
        _ = try restored.redoWithEvidence(operationID: UUID())
    }

    @Test("Peer split undo retains formatting counterparts for native owner snapshot restore")
    func peerDeletedFormattingCounterpartsSurviveRestart() throws {
        let baseline = try RelayMarkCollaborationDocument()
        _ = try baseline.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"Hello"}]}]}]}"#.utf8))
        let a = try RelayMarkCollaborationDocument(), b = try RelayMarkCollaborationDocument()
        try a.applyUpdate(baseline.encodeUpdate())
        try b.applyUpdate(baseline.encodeUpdate())
        let split = try a.replaceProseWithLineage(start: 2, end: 2, text: "\n", operationID: UUID())
        for update in split.updates { try b.applyUpdate(update) }
        let formatting = try b.editNativeFormatting(Data(#"{"kind":"formatText","ranges":[{"path":[0,0],"index":0,"length":2},{"path":[1,0],"index":0,"length":3}],"attributes":{"bold":{}}}"#.utf8), operationID: UUID())
        for update in formatting { try a.applyUpdate(update) }
        let inverse = try a.undoWithEvidence(operationID: UUID())
        for update in inverse.updates { try b.applyUpdate(update) }
        #expect(try canonical(a.snapshot()) == canonical(b.snapshot()))
        for owner in [a, b] {
            let saved = try owner.exportHistoryState(scopeToken: "peer-history-restart")
            let restored = try RelayMarkCollaborationDocument()
            try restored.restoreHistorySnapshot(saved.bytes, scopeToken: "peer-history-restart", transactionIDs: saved.transactionIDs)
            #expect(try canonical(restored.snapshot()) == canonical(owner.snapshot()))
            #expect(try restored.stateVector() == owner.stateVector())
            let reopened = try restored.exportHistoryState(scopeToken: "peer-history-restart")
            #expect(reopened.transactionIDs == saved.transactionIDs)
        }
    }

    @Test("Host eligibility is read-only and conservative")
    func hostEligibility() throws {
        let document = try RelayMarkCollaborationDocument()
        #expect(try !document.supportsProseLineage())
        _ = try document.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"paragraph","children":[]}]}"#.utf8))
        let before = try document.encodeUpdate()
        #expect(try document.supportsProseLineage())
        #expect(try document.encodeUpdate() == before)
        let marked = try seed()
        #expect(try marked.supportsProseLineage())
    }

    @Test("Durable tracked history restores only into a pristine matching owner")
    func durableSnapshotRoundTrip() throws {
        let baseline = try seed(), document = try RelayMarkCollaborationDocument()
        try document.applyUpdate(baseline.encodeUpdate())
        let original = try canonical(document.snapshot()), forwardID = UUID(), undoID = UUID()
        _ = try document.replaceProseWithLineage(start: 7, end: 7, text: "\nH", operationID: forwardID)
        let changed = try canonical(document.snapshot())
        let bytes = try document.exportHistorySnapshot(scopeToken: "qualified-cut-1")
        let restored = try RelayMarkCollaborationDocument(), pristine = try restored.encodeUpdate()
        #expect(throws: (any Error).self) {
            try restored.restoreHistorySnapshot(bytes, scopeToken: "wrong-cut", transactionIDs: [forwardID])
        }
        #expect(try restored.encodeUpdate() == pristine)
        #expect(throws: (any Error).self) {
            try restored.restoreHistorySnapshot(bytes, scopeToken: "qualified-cut-1", transactionIDs: [])
        }
        #expect(try restored.encodeUpdate() == pristine)
        try restored.restoreHistorySnapshot(bytes, scopeToken: "qualified-cut-1", transactionIDs: [forwardID])
        #expect(try canonical(restored.snapshot()) == changed)
        #expect(throws: (any Error).self) {
            try restored.restoreHistorySnapshot(bytes, scopeToken: "qualified-cut-1", transactionIDs: [forwardID])
        }
        let undo = try restored.undoWithLineage(operationID: undoID)
        #expect(try canonical(restored.snapshot()) == original)
        #expect((try json(undo.lineage)["operation"] as? [String: String])?["transaction_id"] == forwardID.uuidString.lowercased())
        let second = try RelayMarkCollaborationDocument()
        try second.restoreHistorySnapshot(restored.exportHistorySnapshot(scopeToken: "qualified-cut-2"),
            scopeToken: "qualified-cut-2", transactionIDs: [forwardID, undoID])
        _ = try second.redoWithLineage(operationID: UUID())
        #expect(try canonical(second.snapshot()) == changed)
    }

    private func seed() throws -> RelayMarkCollaborationDocument {
        let document = try RelayMarkCollaborationDocument()
        _ = try document.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"PREFIX 🌍 generated ","attributes":{"bold":{}}}]}]}]}"#.utf8))
        let human = try RelayMarkCollaborationDocument()
        try human.applyUpdate(document.encodeUpdate())
        _ = try human.edit(Data(#"{"kind":"insertText","path":[0,0],"index":20,"text":"人🌍人","attributes":{"italic":{}}}"#.utf8))
        try document.applyUpdate(human.encodeUpdate())
        return document
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func encoded(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    private func canonical(_ data: Data) throws -> Data { try encoded(JSONSerialization.jsonObject(with: data)) }
    private func copy(_ result: RelayMarkCollaborationDocument.ProseLineageResult) throws -> [String: Any] {
        let copies = try #require(json(result.lineage)["copies"] as? [[String: Any]])
        #expect(copies.count == 1)
        return try #require(copies.first)
    }
    private func selected(_ document: RelayMarkCollaborationDocument, _ selection: Data) throws -> String {
        let resolved = try document.resolveTextItems(selection)
        #expect(resolved.unavailableRuns.isEmpty && resolved.collapsedUnits == 0)
        return resolved.segments.map(\.text).joined()
    }

    @Test func middleSplitCarriesCopiedIdentityAndOnlyNewTypedAdmission() throws {
        let document = try seed()
        let checkpoint = try document.encodeUpdate()
        let prefix = try document.captureTextItems(path: [0, 0], index: 0, length: 7)
        let tail = try document.captureTextItems(path: [0, 0], index: 7, length: 17)
        let result = try document.replaceProseWithLineage(start: 7, end: 7, text: "typed\nnext ")
        #expect(result.updates.count == 1)
        #expect(try selected(document, prefix) == "PREFIX ")
        #expect(try selected(document, result.insertedTextItems) == "typednext ")
        let mapping = try copy(result)
        let source = try encoded(#require(mapping["source"]))
        let destination = try encoded(#require(mapping["destination"]))
        #expect(try source == canonical(tail))
        #expect(source != destination)
        #expect(try selected(document, destination) == "🌍 generated 人🌍人")
        let snapshot = try json(document.snapshot())
        let paragraphs = try #require(snapshot["children"] as? [[String: Any]])
        let leaves = try #require(paragraphs[1]["children"] as? [[String: Any]])
        let delta = try #require(leaves.last?["delta"])
        #expect(try encoded(delta) == canonical(Data(#"[{"insert":"next "},{"insert":"🌍 generated ","attributes":{"bold":{}}},{"insert":"人🌍人","attributes":{"italic":{}}}]"#.utf8)))
        let reopened = try RelayMarkCollaborationDocument()
        try reopened.applyUpdate(checkpoint)
        for update in result.updates + result.updates { try reopened.applyUpdate(update) }
        #expect(try reopened.snapshot() == document.snapshot())
        #expect(try reopened.resolveTextItems(destination) == document.resolveTextItems(destination))
    }

    @Test func joinCopiesExactTailAndAdmitsNoText() throws {
        let document = try seed()
        _ = try document.replaceProseWithLineage(start: 7, end: 7, text: "\n")
        let tail = try document.captureTextItems(path: [1, 0], index: 0, length: 17)
        let checkpoint = try document.encodeUpdate()
        let result = try document.replaceProseWithLineage(start: 7, end: 8, text: "")
        #expect(result.updates.count == 1)
        #expect(try canonical(result.insertedTextItems) == canonical(Data(#"{"runs":[]}"#.utf8)))
        let mapping = try copy(result)
        #expect(try encoded(#require(mapping["source"])) == canonical(tail))
        let destination = try encoded(#require(mapping["destination"]))
        #expect(try selected(document, destination) == "🌍 generated 人🌍人")
        let reopened = try RelayMarkCollaborationDocument()
        try reopened.applyUpdate(checkpoint)
        for update in result.updates + result.updates { try reopened.applyUpdate(update) }
        #expect(try reopened.snapshot() == document.snapshot())
        #expect(try selected(reopened, destination) == "🌍 generated 人🌍人")
    }

    @Test func emittedLineageTransactionPersistsExactlyAndLegacyRecordsRemainReadable() throws {
        let document = try seed()
        let result = try document.replaceProseWithLineage(start: 7, end: 7, text: "typed\nnext ")
        let id = UUID()
        let update = try document.mergeUpdates(result.updates)
        let transaction = RelayMarkLocalTransaction(id: id, update: update, changes: [],
            inputIntent: .nativeReplacement(startUTF16: 7, removed: "", inserted: "typed\nnext "),
            insertedTextItems: result.insertedTextItems, nativeFormatting: nil,
            nativeParagraph: nil, nativeParagraphPaste: nil, proseLineage: result.lineage)
        let bytes = try JSONEncoder().encode(transaction)
        let restored = try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: bytes)
        #expect(restored == transaction)
        #expect(restored.id == id && restored.update == update)
        #expect(restored.insertedTextItems == result.insertedTextItems)
        #expect(restored.proseLineage == result.lineage)
        #expect(try selected(document, #require(restored.insertedTextItems)) == "typednext ")

        // Compile the established initializer and decode a record with the new key absent.
        let legacy = RelayMarkLocalTransaction(id: id, update: update, changes: [],
            inputIntent: transaction.inputIntent, insertedTextItems: result.insertedTextItems,
            nativeFormatting: nil, nativeParagraph: nil, nativeParagraphPaste: nil)
        #expect(legacy.proseLineage == nil)
        var oldJSON = try json(bytes)
        oldJSON.removeValue(forKey: "proseLineage")
        let oldRecord = try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: encoded(oldJSON))
        #expect(oldRecord == legacy)
        #expect(oldRecord.proseLineage == nil)
        #expect(oldRecord.update == update && oldRecord.insertedTextItems == result.insertedTextItems)
    }

    @Test func trackedUndoRedoCarriesActualReferenceAndNeverAdmitsRestoredText() throws {
        let document = try seed()
        let checkpoint = try document.encodeUpdate()
        var previousID = UUID()
        let forward = try document.replaceProseWithLineage(start: 7, end: 20, text: "NEW🌍", operationID: previousID)
        var updates = forward.updates
        for cycle in 0..<4 {
            let nextID = UUID()
            let redo = cycle % 2 == 1
            let result = try redo ? document.redoWithLineage(operationID: nextID) : document.undoWithLineage(operationID: nextID)
            let operation = try #require(json(result.lineage)["operation"] as? [String: Any])
            #expect(operation["kind"] as? String == (redo ? "redo" : "undo"))
            #expect(operation["transaction_id"] as? String == previousID.uuidString.lowercased())
            #expect(try canonical(result.insertedTextItems) == canonical(Data(#"{"runs":[]}"#.utf8)))
            let copies = try #require(json(result.lineage)["copies"] as? [[String: Any]])
            let restoredText = try copies.map { try selected(document, encoded(#require($0["destination"]))) }.joined()
            #expect(restoredText == (redo ? "NEW🌍" : "🌍 generated "))
            updates += result.updates
            let reopened = try RelayMarkCollaborationDocument()
            try reopened.applyUpdate(checkpoint)
            for update in updates + updates { try reopened.applyUpdate(update) }
            #expect(try reopened.snapshot() == document.snapshot())
            #expect(try String(RelayMarkCollaborativeProse(snapshot: document.snapshot()).text.characters) ==
                (redo ? "PREFIX NEW🌍人🌍人" : "PREFIX 🌍 generated 人🌍人"))
            previousID = nextID
        }
    }

    @Test func refusedHistoryLeavesBytesAndTrackedStackUsable() throws {
        let untracked = try seed()
        let old = try untracked.encodeUpdate()
        #expect(throws: (any Error).self) { try untracked.undoWithLineage(operationID: UUID()) }
        #expect(try untracked.encodeUpdate() == old)
        let id = UUID()
        _ = try untracked.replaceProseWithLineage(start: 7, end: 7, text: "tracked", operationID: id)
        let beforeRefusal = try untracked.encodeUpdate()
        #expect(throws: (any Error).self) { try untracked.undoWithLineage(operationID: id) }
        #expect(try untracked.encodeUpdate() == beforeRefusal)
        let undone = try untracked.undoWithLineage(operationID: UUID())
        #expect(!undone.updates.isEmpty)
        #expect(try String(RelayMarkCollaborativeProse(snapshot: untracked.snapshot()).text.characters) == "PREFIX 🌍 generated 人🌍人")
        let empty = try RelayMarkCollaborationDocument()
        #expect(throws: (any Error).self) { try empty.redoWithLineage(operationID: UUID()) }
    }

    @Test func unsupportedShapeAndStructuralInputFailBeforeMutation() throws {
        let document = try seed()
        let state = try document.encodeUpdate()
        #expect(throws: (any Error).self) { try document.replaceProseWithLineage(start: 7, end: 7, text: "\r") }
        #expect(try document.encodeUpdate() == state)
        let heading = try RelayMarkCollaborationDocument()
        _ = try heading.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"heading","attributes":{"level":2},"children":[{"kind":"text","delta":[{"insert":"Heading"}]}]}]}"#.utf8))
        let headingState = try heading.encodeUpdate()
        #expect(throws: (any Error).self) { try heading.replaceProseWithLineage(start: 2, end: 2, text: "\n") }
        #expect(try heading.encodeUpdate() == headingState)
    }
}
