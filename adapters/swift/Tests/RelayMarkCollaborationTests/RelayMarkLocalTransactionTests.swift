import Foundation
import Testing
@testable import RelayMarkCollaboration

struct RelayMarkLocalTransactionTests {
    @Test func actualNativeContentEditBytesFreezeWithTheSameOperationAndUpdate() throws {
        let operationID = UUID()
        let snapshot = Data([0, 1, 7, 14])
        let steps = Data("[ {\"stepType\":\"replace\",\"from\":1,\"to\":1} ]\n".utf8)
        let transaction = RelayMarkLocalTransaction(id: operationID, update: Data([1, 2, 3]), changes: [],
            nativeContentEdit: .init(beforeSnapshot: snapshot, steps: steps, ownedGroup: try .init(ownerID: operationID, reference: operationID, operationIDs: [operationID])))
        let restored = try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: JSONEncoder().encode(transaction))
        #expect(restored.id == operationID)
        #expect(restored.update == Data([1, 2, 3]))
        #expect(restored.nativeContentEdit?.beforeSnapshot == snapshot)
        #expect(restored.nativeContentEdit?.steps == steps)
        #expect(restored.nativeContentEdit?.ownedGroup?.ownerID == operationID)
        #expect(restored.nativeContentEdit?.ownedGroup?.reference == operationID)
        #expect(restored.nativeContentEdit?.ownedGroup?.operationIDs == [operationID])
        #expect(restored.proseLineage == nil)
        #expect(restored.nativeFormatting == nil)
        #expect(RelayMarkLocalTransaction(update: Data([1]), changes: []).nativeContentEdit == nil)
        let inverse=RelayMarkLocalTransaction(id:UUID(),update:Data([4]),changes:[],nativeContentEdit:.init(beforeSnapshot:snapshot,steps:steps,ownedHistory:try .init(kind:.undo,ownerID:operationID,reference:operationID,operationIDs:[operationID])))
        let savedInverse=try JSONDecoder().decode(RelayMarkLocalTransaction.self,from:JSONEncoder().encode(inverse))
        #expect(savedInverse==inverse);#expect(savedInverse.nativeContentEdit?.ownedGroup==nil)
        #expect(savedInverse.nativeContentEdit?.ownedHistory?.operationIDs==[operationID]);#expect(savedInverse.nativeContentEdit?.ownedHistory?.ownerID==operationID)
        var ambiguous=try JSONSerialization.jsonObject(with:JSONEncoder().encode(inverse.nativeContentEdit!)) as! [String:Any]
        ambiguous["ownedGroup"]=["ownerID":operationID.uuidString,"reference":operationID.uuidString,"operationIDs":[operationID.uuidString]]
        let ambiguousBytes=try JSONSerialization.data(withJSONObject:ambiguous)
        #expect(throws:(any Error).self){try JSONDecoder().decode(RelayMarkLocalTransaction.NativeContentEdit.self,from:ambiguousBytes)}
    }

    @Test func sharedWitnessBytesSurviveJournalDecodeWithoutNormalization() throws {
        let operationID = UUID()
        let candidate = RelayMarkLocalTransaction(id: operationID, update: Data([4, 8]), changes: [],
            nativeContentEdit: .init(beforeSnapshot: Data([0, 0]), steps: Data("[]".utf8),
                ownedGroup: try .init(ownerID: operationID, reference: operationID, operationIDs: [operationID])))
        // The journal must retain the exact packaged builder result. Decoding it
        // does not authenticate its source or turn a partial witness into admission.
        let witness = Data(" {\"requires_mutation_correspondence\":true,\"text_items\":{\"runs\":[]}}\n  ".utf8)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(candidate)) as? [String: Any])
        var evidence = try #require(object["nativeContentEdit"] as? [String: Any])
        evidence["witness"] = witness.base64EncodedString()
        object["nativeContentEdit"] = evidence
        let restored = try JSONDecoder().decode(RelayMarkLocalTransaction.self,
            from: JSONSerialization.data(withJSONObject: object))
        let written = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        let savedEvidence = try #require(written["nativeContentEdit"] as? [String: Any])
        #expect(savedEvidence["witness"] as? String == witness.base64EncodedString())
        #expect(restored.id == operationID)
        #expect(restored.update == candidate.update)
        #expect(restored.nativeContentEdit?.witness == witness)
        let inverse = RelayMarkLocalTransaction(id: UUID(), update: Data([9]), changes: [],
            nativeContentEdit: .init(beforeSnapshot: Data([0, 0]), steps: Data("[]".utf8),
                ownedHistory: try .init(kind: .redo, ownerID: operationID, reference: operationID, operationIDs: [operationID]), witness: witness))
        let savedInverse = try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: JSONEncoder().encode(inverse))
        #expect(savedInverse.nativeContentEdit?.witness == witness)
        #expect(savedInverse == inverse)
        #expect(candidate.nativeContentEdit?.witness == nil)
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

    @Test func reviewedArchiveBytesCannotDisappearDuringJournalRoundTrip() throws {
        let id = UUID()
        let original = RelayMarkLocalTransaction(id: id, update: Data([4, 9]), changes: [],
            nativeContentEdit: .init(beforeSnapshot: Data([0, 0]), steps: Data("[]".utf8),
                ownedGroup: try .init(ownerID: id, reference: id, operationIDs: [id]), witness: Data("{}".utf8)))
        let review = Data(" {\"originalArchive\":\"literal original 🌍\",\"originalAssociation\":null}\n".utf8)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var evidence = try #require(object["nativeContentEdit"] as? [String: Any])
        evidence["reviewedRecovery"] = review.base64EncodedString(); object["nativeContentEdit"] = evidence
        let restored = try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: JSONSerialization.data(withJSONObject: object))
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        let saved = try #require(encoded["nativeContentEdit"] as? [String: Any])
        #expect(saved["reviewedRecovery"] as? String == review.base64EncodedString())
        #expect(restored.id == id); #expect(restored.update == original.update)
        #expect(restored.nativeContentEdit?.witness == original.nativeContentEdit?.witness)
        evidence["reviewedRecovery"] = Data().base64EncodedString(); object["nativeContentEdit"] = evidence
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func reviewedEvidenceBudgetRefusesBeforeJournalConstruction() throws {
        typealias Evidence = RelayMarkLocalTransaction.NativeContentEdit
        let review = Data("{\"originalArchive\":\"exact bytes\"}\n".utf8)
        let captured = try Evidence(beforeSnapshot: Data([0, 0]), steps: Data("[]".utf8), reviewedRecovery: review)
        #expect(captured.reviewedRecovery == review)
        #expect(captured.witness == nil)
        #expect(try JSONDecoder().decode(Evidence.self, from: JSONEncoder().encode(captured)) == captured)
        #expect(throws: (any Error).self) {
            try Evidence(beforeSnapshot: Data([0, 0]), steps: Data("[]".utf8), reviewedRecovery: Data())
        }
        let oversized = Data(repeating: 0x20, count: 24_000_001)
        #expect(throws: (any Error).self) {
            try Evidence(beforeSnapshot: Data([0, 0]), steps: Data("[]".utf8), reviewedRecovery: oversized)
        }
        let nilEvidence = try Evidence(beforeSnapshot: Data([0, 0]), steps: Data("[]".utf8), reviewedRecovery: nil)
        #expect(nilEvidence.reviewedRecovery == nil)
    }

    @Test func inverseJournalCannotClaimTheOriginalReviewedAppendMaterial() throws {
        let id = UUID()
        let inverse = RelayMarkLocalTransaction.NativeContentEdit(beforeSnapshot: Data([0, 0]), steps: Data("[]".utf8),
            ownedHistory: try .init(kind: .undo, ownerID: id, reference: id, operationIDs: [id]))
        let material = Data("{\"originalArchive\":\"exact retained source\"}\n".utf8)
        var forged = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(inverse)) as? [String: Any])
        forged["reviewedRecovery"] = material.base64EncodedString()
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RelayMarkLocalTransaction.NativeContentEdit.self, from: JSONSerialization.data(withJSONObject: forged))
        }
        #expect(try JSONDecoder().decode(RelayMarkLocalTransaction.NativeContentEdit.self,
            from: JSONEncoder().encode(inverse)) == inverse)
        let original = try RelayMarkLocalTransaction.NativeContentEdit(beforeSnapshot: Data([0, 0]), steps: Data("[]".utf8),
            ownedGroup: .init(ownerID: id, reference: id, operationIDs: [id]), reviewedRecovery: material)
        #expect(try JSONDecoder().decode(RelayMarkLocalTransaction.NativeContentEdit.self,
            from: JSONEncoder().encode(original)).reviewedRecovery == material)
    }

}
