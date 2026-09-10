import Foundation
import Testing
@testable import RelayMarkCollaboration

@MainActor
struct RelayMarkIntegrationStatusTests {
    private func source() throws -> RelayMarkCollaborationDocument {
        let doc = try RelayMarkCollaborationDocument()
        _ = try doc.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"human"}]}]}]}"#.utf8))
        return doc
    }

    @Test func missingStructsSurviveCheckpointAndSettleWithBaseline() throws {
        let doc = try source(), baseline = try doc.encodeUpdate()
        let updates = try doc.insertText("!", at: 5, path: [0, 0])
        let partial = try RelayMarkCollaborationDocument()
        for update in updates { try partial.applyUpdate(update) }
        let status = try partial.integrationStatus()
        #expect(status.hasPendingStructs && !status.isComplete)
        let restored = try RelayMarkCollaborationDocument()
        try restored.applyUpdate(partial.encodeUpdate())
        #expect(try restored.integrationStatus() == status)
        for replica in [partial, restored] {
            try replica.applyUpdate(baseline)
            #expect(try replica.integrationStatus().isComplete)
            #expect(try replica.snapshot() == doc.snapshot())
        }
    }

    @Test func pendingDeletesAreNotProvedCompleteByStateVector() throws {
        let doc = try source(), baseline = try doc.encodeUpdate()
        let updates = try doc.deleteText(at: 0, length: 5, path: [0, 0])
        let partial = try RelayMarkCollaborationDocument(), vector = try partial.stateVector()
        for update in updates { try partial.applyUpdate(update); try partial.applyUpdate(update) }
        #expect(try partial.stateVector() == vector)
        let status = try partial.integrationStatus()
        #expect(!status.hasPendingStructs && status.hasPendingDeletes && !status.isComplete)
        let restored = try RelayMarkCollaborationDocument()
        try restored.applyUpdate(partial.encodeUpdate())
        #expect(try restored.integrationStatus() == status)
        for replica in [partial, restored] {
            try replica.applyUpdate(baseline)
            #expect(try replica.integrationStatus().isComplete)
            #expect(try replica.snapshot() == doc.snapshot())
        }
    }
}
