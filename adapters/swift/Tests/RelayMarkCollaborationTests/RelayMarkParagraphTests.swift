import Foundation
import Testing
@testable import RelayMarkCollaboration

@MainActor
struct RelayMarkParagraphTests {
    @Test func multilinePasteCarriesExactNewTextAndOptionalEvidence() throws {
        let doc = try seeded(), peer = try RelayMarkCollaborationDocument()
        try peer.applyUpdate(doc.encodeUpdate())
        let human = try doc.captureTextItems(path: [0, 0], index: 13, length: 5)
        let text = " First 😀\n\nSecond Ω\n"
        let result = try doc.insertParagraphTextAfter(index: 0, expectedEndUTF16: 18, text: text)
        #expect(result.updates.count == 1)
        #expect(result.evidence == .init(paragraphIndex: 0, endUTF16: 18, paragraphCount: 3))
        for update in result.updates { try peer.applyUpdate(update); try peer.applyUpdate(update) }
        #expect(try doc.snapshot() == peer.snapshot())
        #expect(try doc.resolveTextItems(result.insertedTextItems).segments.map(\.text).joined() == " First 😀Second Ω")
        #expect(try doc.resolveTextItems(human).segments.map(\.text).joined() == "human")
        #expect(try String(RelayMarkCollaborativeProse(snapshot: doc.snapshot()).text.characters) == "Generated 😀 human First 😀\n\nSecond Ω\n\nOther")
        let transaction = RelayMarkLocalTransaction(update: try doc.mergeUpdates(result.updates), changes: [],
            inputIntent: .nativeReplacement(startUTF16: 18, removed: "", inserted: text),
            insertedTextItems: result.insertedTextItems, nativeFormatting: nil, nativeParagraph: nil,
            nativeParagraphPaste: result.evidence)
        #expect(try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: JSONEncoder().encode(transaction)) == transaction)
        #expect(transaction.nativeParagraph == nil)
        let old = RelayMarkLocalTransaction(update: Data([1]), changes: [])
        #expect(try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: JSONEncoder().encode(old)).nativeParagraphPaste == nil)
    }

    @Test func invalidMultilinePasteDoesNotMutate() throws {
        let doc = try seeded(), before = try doc.encodeUpdate()
        for text in ["single", "\n\r", "\n\u{2028}", "\n\u{FFFC}"] {
            #expect(throws: (any Error).self) { try doc.insertParagraphTextAfter(index: 0, expectedEndUTF16: 18, text: text) }
            #expect(try doc.encodeUpdate() == before)
        }
    }
    private func seeded() throws -> RelayMarkCollaborationDocument {
        let doc = try RelayMarkCollaborationDocument()
        _ = try doc.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"Generated 😀 human","attributes":{"bold":{}}}]}]},{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"Other"}]}]}]}"#.utf8))
        return doc
    }

    @Test func explicitReturnPreservesItemsAndAllowsSubsequentNativeTyping() throws {
        let doc = try seeded(), peer = try RelayMarkCollaborationDocument()
        try peer.applyUpdate(doc.encodeUpdate())
        let human = try doc.captureTextItems(path: [0, 0], index: 13, length: 5)
        let result = try doc.insertParagraphAfter(index: 0, expectedEndUTF16: 18)
        #expect(result.updates.count == 1)
        #expect(result.evidence == .init(paragraphIndex: 0, endUTF16: 18))
        for update in result.updates { try peer.applyUpdate(update); try peer.applyUpdate(update) }
        #expect(try doc.snapshot() == peer.snapshot())
        #expect(try doc.resolveTextItems(human).segments.map(\.text).joined() == "human")
        let prose = try RelayMarkCollaborativeProse(snapshot: doc.snapshot())
        #expect(String(prose.text.characters) == "Generated 😀 human\n\nOther")
        let empty = try #require(prose.position(atUTF16: 19))
        #expect(empty.path == [1, 0] && empty.index == 0)
        let updates = try doc.replaceProse(start: 19, end: 19, text: "Next 😀")
        for update in updates { try peer.applyUpdate(update) }
        #expect(try doc.snapshot() == peer.snapshot())
        #expect(try String(RelayMarkCollaborativeProse(snapshot: doc.snapshot()).text.characters) == "Generated 😀 human\nNext 😀\nOther")
    }

    @Test func invalidEndAndGroupedInputLeaveReplicaUnchanged() throws {
        let doc = try seeded(), before = try doc.encodeUpdate()
        #expect(throws: (any Error).self) { try doc.insertParagraphAfter(index: 0, expectedEndUTF16: 17) }
        #expect(try doc.encodeUpdate() == before)
        _ = try doc.withUndoGroup {
            #expect(throws: (any Error).self) { try doc.insertParagraphAfter(index: 0, expectedEndUTF16: 18) }
        }
        #expect(try doc.encodeUpdate() == before)
    }

    @Test func paragraphEvidenceRoundTripsAndExistingInitializerReferenceRemainsValid() throws {
        let initializer: (UUID, Data, [RelayMarkLocalTransaction.TextChange], RelayMarkLocalTransaction.InputIntent?, Data?, RelayMarkLocalTransaction.NativeFormatting?) -> RelayMarkLocalTransaction = RelayMarkLocalTransaction.init
        let old = initializer(UUID(), Data([1]), [], .derived, nil, nil)
        #expect(old.nativeParagraph == nil)
        let doc = try seeded(), result = try doc.insertParagraphAfter(index: 0, expectedEndUTF16: 18)
        let value = RelayMarkLocalTransaction(update: try doc.mergeUpdates(result.updates), changes: [],
            inputIntent: .nativeReplacement(startUTF16: 18, removed: "", inserted: "\n"),
            insertedTextItems: Data(#"{"version":1,"runs":[]}"#.utf8), nativeFormatting: nil,
            nativeParagraph: result.evidence)
        #expect(try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: JSONEncoder().encode(value)) == value)
        let oldJSON = try JSONEncoder().encode(old)
        #expect(try JSONDecoder().decode(RelayMarkLocalTransaction.self, from: oldJSON).nativeParagraph == nil)
    }
}
