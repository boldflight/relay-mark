import Foundation
import Testing
@testable import RelayMarkCollaboration

struct RelayMarkLocalTransactionTests {
    @Test func legacyInitializerFunctionReferenceAndJSONRemainCompatible() throws {
        let initializer: (UUID, Data, [RelayMarkLocalTransaction.TextChange]) -> RelayMarkLocalTransaction = RelayMarkLocalTransaction.init
        let transaction = initializer(UUID(), Data([1, 2]), [])
        #expect(transaction.inputIntent == nil)
        let encoded = try JSONEncoder().encode(transaction)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["inputIntent"] == nil)
        #expect(try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: encoded) == transaction)
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
}
