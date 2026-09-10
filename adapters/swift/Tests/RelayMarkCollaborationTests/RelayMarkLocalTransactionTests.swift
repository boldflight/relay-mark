import Foundation
import Testing
@testable import RelayMarkCollaboration

struct RelayMarkLocalTransactionTests {
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
}
