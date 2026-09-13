import Foundation
import Testing
@testable import RelayMarkCollaboration

@MainActor
struct RelayMarkAttributedHistoryTests {
    private func identifier(_ value: Any?) throws -> UUID {
        let text = try #require(value as? String)
        return try #require(UUID(uuidString: text))
    }
    private func encoded(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
    private func canonical(_ data: Data) throws -> Data {
        try encoded(JSONSerialization.jsonObject(with: data))
    }
    private func setup() throws -> (RelayMarkCollaborationDocument, RelayMarkCollaborationDocument.AttributionReplay, [String: Any]) {
        let url = try #require(Bundle.module.url(forResource: "attributed-history-v1", withExtension: "json"))
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let expected = try #require(fixture["expected"] as? [String: Any])
        let binding = try #require(expected["binding"] as? [String: String])
        let scope = try #require(expected["scope_token"] as? String)
        let replay = try RelayMarkCollaborationDocument.AttributionReplay(
            bytes: Data(try #require(fixture["replay_json"] as? String).utf8), scopeToken: scope,
            binding: .init(documentID: try identifier(binding["document_id"]),
                           incarnation: try #require(binding["incarnation"])),
            digest: try #require(expected["replay_sha256"] as? String), cut: try #require(expected["cut"] as? String))
        let document = try RelayMarkCollaborationDocument()
        let ids = try #require(fixture["transaction_ids"] as? [String]).map { try #require(UUID(uuidString: $0)) }
        try document.restoreHistorySnapshot(encoded(#require(fixture["owner_snapshot"])), scopeToken: scope, transactionIDs: ids)
        return (document, replay, fixture)
    }

    @Test("Native attributed undo and redo follow restored copies across another owner restart")
    func restoredPeerFormattingUndoRedo() throws {
        let (document, replay, fixture) = try setup()
        let reference = try identifier(fixture["reference_id"])
        let undoID = try identifier(fixture["undo_id"])
        let result = try document.undoWithAttributedEvidence(operationID: undoID, referenceID: reference, replay: replay)
        #expect(result.evidence.kind.rawValue == "formatting")
        #expect(result.evidence.formattingMark == .bold)
        #expect(!result.evidence.updates.isEmpty)
        #expect(try canonical(document.snapshot()) == encoded(#require(fixture["plain_snapshot"])))
        #expect(result.replay.bytes != replay.bytes)
        #expect(result.replay.digest != replay.digest)
        let saved = try document.exportHistoryState(scopeToken: replay.scopeToken)
        let restored = try RelayMarkCollaborationDocument()
        try restored.restoreHistorySnapshot(saved.bytes, scopeToken: replay.scopeToken, transactionIDs: saved.transactionIDs)
        let redone = try restored.redoWithAttributedEvidence(operationID: identifier(fixture["redo_id"]),
                                                             referenceID: undoID, replay: result.replay)
        #expect(redone.evidence.formattingMark == .bold)
        #expect(try canonical(restored.snapshot()) == encoded(#require(fixture["bold_snapshot"])))
        // The durable expectation and exact JSON remain separate on the bridge.
        #expect(redone.replay.scopeToken == replay.scopeToken)
        #expect(redone.replay.binding.documentID == replay.binding.documentID)
    }

    @Test("Tampered or misbound native replay leaves both document and history unchanged")
    func invalidReplayRefusesBeforeMutation() throws {
        let (document, replay, fixture) = try setup()
        let before = try document.exportHistorySnapshot(scopeToken: replay.scopeToken)
        let reference = try identifier(fixture["reference_id"])
        let bad = try [
            RelayMarkCollaborationDocument.AttributionReplay(bytes: replay.bytes + Data(" ".utf8), scopeToken: replay.scopeToken,
                binding: replay.binding, digest: replay.digest, cut: replay.cut),
            RelayMarkCollaborationDocument.AttributionReplay(bytes: replay.bytes, scopeToken: "another-owner",
                binding: replay.binding, digest: replay.digest, cut: replay.cut),
            RelayMarkCollaborationDocument.AttributionReplay(bytes: replay.bytes, scopeToken: replay.scopeToken,
                binding: replay.binding, digest: replay.digest, cut: String(repeating: "0", count: 64))
        ]
        for value in bad {
            #expect(throws: (any Error).self) {
                try document.undoWithAttributedEvidence(operationID: UUID(), referenceID: reference, replay: value)
            }
            #expect(try document.exportHistorySnapshot(scopeToken: replay.scopeToken) == before)
        }
        #expect(throws: (any Error).self) {
            try RelayMarkCollaborationDocument.AttributionReplay(bytes: Data([0xff]), scopeToken: replay.scopeToken,
                binding: replay.binding, digest: replay.digest, cut: replay.cut)
        }
        _ = try document.undoWithAttributedEvidence(operationID: UUID(), referenceID: reference, replay: replay)
        #expect(try canonical(document.snapshot()) == encoded(#require(fixture["plain_snapshot"])))
    }

    private func freshOwners() throws -> (RelayMarkCollaborationDocument, RelayMarkCollaborationDocument) {
        let seed = try RelayMarkCollaborationDocument()
        _ = try seed.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"Hello"}]}]}]}"#.utf8))
        let a = try RelayMarkCollaborationDocument(), b = try RelayMarkCollaborationDocument()
        try a.applyUpdate(seed.encodeUpdate()); try b.applyUpdate(seed.encodeUpdate())
        return (a, b)
    }

    private func delta(_ document: RelayMarkCollaborationDocument) throws -> Data {
        let root = try #require(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
        let blocks = try #require(root["children"] as? [[String: Any]])
        let children = try #require(blocks[0]["children"] as? [[String: Any]])
        return try encoded(#require(children[0]["delta"]))
    }

    @Test("Native clients generate forward witnesses and preserve peer formatting on undo")
    func nativeForwardWitnesses() throws {
        let (a, b) = try freshOwners()
        let replay = try a.createAttributionReplay(scopeToken: "native-journal", binding: .init(documentID: UUID(), incarnation: "one"))
        let firstID = UUID()
        let first = try a.editNativeFormattingWithAttribution(Data(#"{"kind":"formatText","path":[0,0],"index":0,"length":5,"attributes":{"bold":{}}}"#.utf8), operationID: firstID, replay: replay)
        for update in first.updates { try b.applyUpdate(update) }
        let record = try #require(JSONSerialization.jsonObject(with: first.record) as? [String: Any])
        let event = try #require(record["event"] as? [String: Any])
        #expect(event["operation_id"] as? String == firstID.uuidString.lowercased())
        let recordedUpdate = try #require(record["update"] as? [UInt8])
        #expect(try Data(recordedUpdate) == a.mergeUpdates(first.updates))
        let remove = try b.editNativeFormattingWithAttribution(Data(#"{"kind":"formatText","path":[0,0],"index":2,"length":1,"attributes":{"bold":null}}"#.utf8), operationID: UUID(), replay: first.replay)
        for update in remove.updates { try a.applyUpdate(update) }
        let add = try b.editNativeFormattingWithAttribution(Data(#"{"kind":"formatText","path":[0,0],"index":2,"length":1,"attributes":{"bold":{}}}"#.utf8), operationID: UUID(), replay: remove.replay)
        for update in add.updates { try a.applyUpdate(update) }
        let undoID = UUID()
        let undone = try a.undoWithAttributedEvidence(operationID: undoID, referenceID: firstID, replay: add.replay)
        for update in undone.evidence.updates { try b.applyUpdate(update) }
        let expected = Data(#"[{"insert":"He"},{"attributes":{"bold":{}},"insert":"l"},{"insert":"lo"}]"#.utf8)
        #expect(try delta(a) == canonical(expected))
        #expect(try canonical(a.snapshot()) == canonical(b.snapshot()))
        let saved = try a.exportHistoryState(scopeToken: replay.scopeToken), restored = try RelayMarkCollaborationDocument()
        try restored.restoreHistorySnapshot(saved.bytes, scopeToken: replay.scopeToken, transactionIDs: saved.transactionIDs)
        let redone = try restored.redoWithAttributedEvidence(operationID: UUID(), referenceID: undoID, replay: undone.replay)
        #expect(!redone.record.isEmpty)
        #expect(try delta(restored) == canonical(Data(#"[{"insert":"Hello","attributes":{"bold":{}}}]"#.utf8)))
    }

    @Test("A native baseline cannot discard existing history and invalid forward intent does not mutate it")
    func forwardBaselineAndPreflightRefusals() throws {
        let (document, _) = try freshOwners()
        let binding = RelayMarkCollaborationDocument.PlacementBinding(documentID: UUID(), incarnation: "one")
        let replay = try document.createAttributionReplay(scopeToken: "native-journal", binding: binding)
        let operation = Data(#"{"kind":"formatText","path":[0,0],"index":0,"length":5,"attributes":{"bold":{}}}"#.utf8)
        let result = try document.editNativeFormattingWithAttribution(operation, operationID: UUID(), replay: replay)
        let before = try document.exportHistorySnapshot(scopeToken: replay.scopeToken)
        #expect(throws: (any Error).self) { try document.createAttributionReplay(scopeToken: replay.scopeToken, binding: binding) }
        #expect(throws: (any Error).self) { try document.editNativeFormattingWithAttribution(operation, operationID: UUID(), replay: result.replay) }
        #expect(try document.exportHistorySnapshot(scopeToken: replay.scopeToken) == before)
    }

}
