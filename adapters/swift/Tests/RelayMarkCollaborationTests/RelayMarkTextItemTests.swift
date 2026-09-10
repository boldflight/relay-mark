import Foundation
import Testing
@testable import RelayMarkCollaboration

@MainActor
struct RelayMarkTextItemTests {
    private func document() throws -> RelayMarkCollaborationDocument {
        let doc = try RelayMarkCollaborationDocument()
        _ = try doc.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"A😀B"}]}]}]}"#.utf8))
        return doc
    }
    @Test func exactItemsExcludeInterveningTextAcrossCheckpoint() throws {
        let doc = try document()
        let selection = try doc.captureTextItems(path: [0, 0], index: 0, length: 4)
        _ = try doc.insertText("remote", at: 3, path: [0, 0])
        let resolved = try doc.resolveTextItems(selection)
        #expect(resolved.segments.map(\.text).joined() == "A😀B")
        #expect(resolved.segments.count == 2)
        #expect(resolved.unavailableRuns.isEmpty)
        let restored = try RelayMarkCollaborationDocument()
        try restored.applyUpdate(doc.encodeUpdate())
        #expect(try restored.resolveTextItems(selection) == resolved)
        _ = try restored.edit(Data(#"{"kind":"deleteNodes","path":[],"index":0,"length":1}"#.utf8))
        #expect(try restored.resolveTextItems(selection).unavailableRuns == [0])
    }
    @Test func invalidSelectionPreservesReplica() throws {
        let doc = try document(), before = try doc.encodeUpdate()
        #expect(throws: (any Error).self) { try doc.resolveTextItems(Data(#"{"version":1,"runs":[],"extra":true}"#.utf8)) }
        #expect(throws: (any Error).self) { try doc.captureTextItems(path: [0, 0], index: 1, length: 1) }
        #expect(try doc.encodeUpdate() == before)
    }
}
