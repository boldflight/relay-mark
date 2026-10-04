import Foundation
import Testing
@testable import RelayMarkCollaboration

struct RelayMarkLocalTransactionTests {
    @Test func actualNativeContentEditBytesFreezeWithTheSameOperationAndUpdate() throws {
        let operationID = UUID()
        let snapshot = Data([0, 1, 7, 14])
        let steps = Data("[ {\"stepType\":\"replace\",\"from\":1,\"to\":1} ]\n".utf8)
        let transaction = RelayMarkLocalTransaction(id: operationID, update: Data([1, 2, 3]), changes: [],
            nativeContentEdit: .init(beforeSnapshot: snapshot, steps: steps))
        let restored = try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: JSONEncoder().encode(transaction))
        #expect(restored.id == operationID)
        #expect(restored.update == Data([1, 2, 3]))
        #expect(restored.nativeContentEdit?.beforeSnapshot == snapshot)
        #expect(restored.nativeContentEdit?.steps == steps)
        #expect(restored.proseLineage == nil)
        #expect(restored.nativeFormatting == nil)
        #expect(RelayMarkLocalTransaction(update: Data([1]), changes: []).nativeContentEdit == nil)
    }

    @Test func legacyInitializerFunctionReferenceAndJSONRemainCompatible() throws {
        let initializer: (UUID, Data, [RelayMarkLocalTransaction.TextChange]) -> RelayMarkLocalTransaction = RelayMarkLocalTransaction.init
        let transaction = initializer(UUID(), Data([1, 2]), [])
        #expect(transaction.inputIntent == nil)
        #expect(transaction.insertedTextItems == nil)
        #expect(transaction.nativeFormatting == nil)
        let encoded = try JSONEncoder().encode(transaction)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["inputIntent"] == nil)
        #expect(object["insertedTextItems"] == nil)
        #expect(object["nativeFormatting"] == nil)
        #expect(try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: encoded) == transaction)
    }

    @Test func inputIntentInitializerReferenceRemainsCompatible() {
        let initializer: (UUID, Data, [RelayMarkLocalTransaction.TextChange], RelayMarkLocalTransaction.InputIntent?) -> RelayMarkLocalTransaction = RelayMarkLocalTransaction.init
        let transaction = initializer(UUID(), Data([1]), [], .derived)
        #expect(transaction.inputIntent == .derived)
        #expect(transaction.insertedTextItems == nil)
    }

    @Test func exactItemEvidenceBytesRoundTripWithoutNormalizingOrInventingEvidence() throws {
        let bytes = Data("{\"version\":1, \"runs\":[]}\n  ".utf8)
        let transaction = RelayMarkLocalTransaction(update: Data([1, 2]), changes: [],
            inputIntent: .nativeReplacement(startUTF16: 0, removed: "gone", inserted: ""),
            insertedTextItems: bytes)
        let decoded = try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: JSONEncoder().encode(transaction))
        #expect(decoded == transaction)
        #expect(decoded.insertedTextItems == bytes)
        #expect(decoded.id == transaction.id)
        #expect(decoded.update == transaction.update)
    }

    @Test func everyInputIntentRoundTripsWithoutRequiringTextDiff() throws {
        let intents: [RelayMarkLocalTransaction.InputIntent] = [
            .nativeReplacement(startUTF16: 8, removed: "😀", inserted: "😀"),
            .derived, .composition, .undo, .redo,
        ]
        for intent in intents {
            let transaction = RelayMarkLocalTransaction(update: Data([1]), changes: [], inputIntent: intent)
            let decoded = try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: JSONEncoder().encode(transaction))
            #expect(decoded == transaction)
            #expect(decoded.changes.isEmpty)
        }
    }

    @Test func formattingEvidencePreservesExistingInitializerAndExactFrozenReceipt() throws {
        let initializer: (UUID, Data, [RelayMarkLocalTransaction.TextChange], RelayMarkLocalTransaction.InputIntent?, Data?) -> RelayMarkLocalTransaction = RelayMarkLocalTransaction.init
        let legacy = initializer(UUID(), Data([1]), [], .derived, nil)
        #expect(legacy.nativeFormatting == nil)
        let transaction = RelayMarkLocalTransaction(update: Data([1, 2, 3]), changes: [], inputIntent: .derived,
            insertedTextItems: Data(#"{"version":1,"runs":[]}"#.utf8),
            nativeFormatting: .init(startUTF16: 2, lengthUTF16: 5, mark: .italic, enabled: true))
        let restored = try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: JSONEncoder().encode(transaction))
        #expect(restored == transaction)
        #expect(restored.id == transaction.id)
        #expect(restored.update == Data([1, 2, 3]))
        #expect(restored.nativeFormatting?.mark == .italic)
    }
    @MainActor @Test func attributionCandidatePreservesExactBytesAndLegacySignature() throws {
        let hash = String(repeating: "a", count: 64)
        let record = Data("{\"opaque\": \"日本\"}\n".utf8)
        let recipe = Data("{\"opaque\":true}  ".utf8)
        let replay = try RelayMarkCollaborationDocument.AttributionReplay(bytes: recipe,
            scopeToken: "scope", binding: .init(documentID: UUID(), incarnation: "one"), digest: hash, cut: hash)
        let candidate = try RelayMarkLocalTransaction.AttributionCandidate(record: record, replay: replay, inputReplayDigest: hash)
        let transaction = RelayMarkLocalTransaction(update: Data([1]), changes: [], inputIntent: .undo,
            insertedTextItems: nil, nativeFormatting: nil, nativeParagraph: nil,
            nativeParagraphPaste: nil, proseLineage: nil, attribution: candidate)
        let decoded = try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: JSONEncoder().encode(transaction))
        #expect(decoded == transaction)
        let retained = try #require(decoded.attribution)
        #expect(retained.record == record)
        #expect(try retained.replay().bytes == recipe)
        #expect(retained.inputReplayDigest == hash)
        // Shape-only carrier: opaque JSON here deliberately makes no witness claim.
        let oldInitializer: (UUID, Data, [RelayMarkLocalTransaction.TextChange], RelayMarkLocalTransaction.InputIntent?, Data?, RelayMarkLocalTransaction.NativeFormatting?, RelayMarkLocalTransaction.NativeParagraph?, RelayMarkLocalTransaction.NativeParagraphPaste?, Data?) -> RelayMarkLocalTransaction = RelayMarkLocalTransaction.init
        let old = oldInitializer(UUID(), Data([1]), [], nil, nil, nil, nil, nil, nil)
        #expect(old.attribution == nil)
        let oldBytes = try JSONEncoder().encode(old)
        let object = try #require(JSONSerialization.jsonObject(with: oldBytes) as? [String: Any])
        #expect(object["attribution"] == nil)
        #expect(try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: oldBytes).attribution == nil)
        #expect(throws: (any Error).self) {
            try RelayMarkLocalTransaction.AttributionCandidate(record: Data([0xff]), replay: replay, inputReplayDigest: hash)
        }
        #expect(throws: (any Error).self) {
            try RelayMarkLocalTransaction.AttributionCandidate(record: record, replay: replay, inputReplayDigest: "bad")
        }
    }

}
