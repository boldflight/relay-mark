import Foundation
import Testing
@testable import RelayMarkCollaboration

@MainActor
struct RelayMarkAttributionMetadataTests {
    private func owners() throws -> (RelayMarkCollaborationDocument, RelayMarkCollaborationDocument) {
        let seed = try RelayMarkCollaborationDocument()
        _ = try seed.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"Hello"}]}]}]}"#.utf8))
        let a = try RelayMarkCollaborationDocument(), b = try RelayMarkCollaborationDocument()
        try a.applyUpdate(seed.encodeUpdate()); try b.applyUpdate(seed.encodeUpdate())
        return (a, b)
    }

    @Test("Opt-in masked history persists metadata across owner restart and later redo becomes effective")
    func maskedPeerHistoryRestart() throws {
        let (a, b) = try owners()
        let binding = RelayMarkCollaborationDocument.PlacementBinding(documentID: UUID(), incarnation: "one")
        var ar = try a.createAttributionReplay(scopeToken: "owner-a", binding: binding)
        var br = try b.createAttributionReplay(scopeToken: "owner-b", binding: binding)
        let addID = UUID(), removeID = UUID()
        let add = try a.editNativeFormattingWithAttribution(Data(#"{"kind":"formatText","path":[0,0],"index":0,"length":5,"attributes":{"bold":{}}}"#.utf8), operationID: addID, replay: ar)
        ar = add.replay; br = try b.applyAttributionRecord(add.record, replay: br)
        let remove = try b.editNativeFormattingWithAttribution(Data(#"{"kind":"formatText","path":[0,0],"index":0,"length":5,"attributes":{"bold":null}}"#.utf8), operationID: removeID, replay: br)
        br = remove.replay; ar = try a.applyAttributionRecord(remove.record, replay: ar)
        let before = try a.exportHistorySnapshot(scopeToken: "snapshot-a")
        #expect(throws: (any Error).self) { try a.undoWithAttributedEvidence(operationID: UUID(), replay: ar) }
        #expect(throws: (any Error).self) { try a.undoWithAttributedEvidence(operationID: UUID(), replay: ar, allowNoEffect: false) }
        #expect(throws: (any Error).self) { try a.undoWithAttributedEvidence(operationID: UUID(), referenceID: removeID, replay: ar, allowNoEffect: true) }
        #expect(try a.exportHistorySnapshot(scopeToken: "snapshot-a") == before)
        let undoID = UUID(), plain = try a.snapshot()
        let updateBefore = try a.encodeUpdate(), vectorBefore = try a.stateVector()
        let undo = try a.undoWithAttributedEvidence(operationID: undoID, referenceID: addID, replay: ar, allowNoEffect: true)
        #expect(undo.evidence.kind.rawValue == "formatting")
        #expect(undo.evidence.updates.isEmpty)
        #expect(try a.snapshot() == plain)
        #expect(try a.encodeUpdate() == updateBefore)
        #expect(try a.stateVector() == vectorBefore)
        #expect(undo.replay.cut == ar.cut)
        #expect(undo.replay.digest != ar.digest)
        let record = try #require(JSONSerialization.jsonObject(with: undo.record) as? [String: Any])
        #expect(record["kind"] as? String == "format_noop")
        #expect(record["update"] == nil)
        let packed = try a.packAttributionMetadata(undo.record)
        #expect(packed.operationID == undoID)
        #expect(try a.unpackAttributionMetadata(packed.bytes, expectedDigest: packed.digest, operationID: undoID) == undo.record)
        #expect(throws: (any Error).self) { try a.unpackAttributionMetadata(packed.bytes, expectedDigest: packed.digest, operationID: UUID()) }
        #expect(throws: (any Error).self) { try a.unpackAttributionMetadata(packed.bytes + Data(" ".utf8), expectedDigest: packed.digest, operationID: undoID) }
        #expect(throws: (any Error).self) { try a.packAttributionMetadata(add.record) }
        br = try b.applyAttributionRecord(undo.record, replay: br)
        let saved = try a.exportHistoryState(scopeToken: "snapshot-a"), restored = try RelayMarkCollaborationDocument()
        try restored.restoreHistorySnapshot(saved.bytes, scopeToken: "snapshot-a", transactionIDs: saved.transactionIDs)
        try restored.validateAttributionReplay(undo.replay)
        let bUndo = try b.undoWithAttributedEvidence(operationID: UUID(), replay: br, allowNoEffect: true)
        #expect(bUndo.evidence.updates.isEmpty)
        let successor = try restored.applyAttributionRecord(bUndo.record, replay: undo.replay)
        let redo = try restored.redoWithAttributedEvidence(operationID: UUID(), referenceID: undoID, replay: successor, allowNoEffect: true)
        #expect(!redo.evidence.updates.isEmpty)
        _ = try b.applyAttributionRecord(redo.record, replay: bUndo.replay)
        #expect(try restored.snapshot() == b.snapshot())
        #expect(try restored.snapshot() != plain)
    }
}
