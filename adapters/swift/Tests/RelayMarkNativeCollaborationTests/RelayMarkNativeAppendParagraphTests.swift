import Foundation
import XCTest
import RelayMarkSwift
import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeAppendParagraphTests: XCTestCase {
    func testAppendAfterTableOrNestedListPreservesRichContentPeerAndUndo() throws {
        let table = "| Person | Detail |\n| --- | --- |\n| Maya | **Keep bold** |"
        let nestedList = "- Outer\n  - **Inner**"
        let id = "b00000000000040008000000000000001"
        let text = "- [ ] Call Maya\n\n# literal title, not a command"

        for source in [table + "\n\n" + nestedList, nestedList + "\n\n" + table] {
            let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            _ = try document.initializeDocument(authoredAST:
                RelayMarkSourceCodec.parseDocument(source, namespace: "append-rich-human"))
            let seed = try document.encodeUpdate(), before = try document.snapshot()
            try peer.applyUpdate(seed)
            let original = try RelayMarkNativeDocumentProjection.project(document: document)
            XCTAssertEqual(Set(original.blocks.map(\.type)), ["table", "list"])
            let list = try XCTUnwrap(original.blocks.first { $0.type == "list" })
            XCTAssertEqual(list.childBlocks.first?.childBlocks.last?.type, "list")

            let change = try RelayMarkNativeRichEditing.appendParagraph(document: document,
                id: id, text: text, expectedSnapshot: before)
            let after = try RelayMarkNativeDocumentProjection.project(document: document)
            XCTAssertEqual(Array(after.blocks.dropLast()), original.blocks)
            let paragraph = try XCTUnwrap(after.blocks.last)
            XCTAssertEqual(paragraph.id, id)
            XCTAssertEqual(paragraph.type, "paragraph")
            let inlines = try paragraph.content.map { content -> RelayMarkInline in
                guard case let .inline(inline) = content else {
                    throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
                }
                return inline
            }
            XCTAssertEqual(inlines.map(\.type), ["text", "hard_break", "hard_break", "text"])
            XCTAssertEqual(inlines.first?.text, "- [ ] Call Maya")
            XCTAssertEqual(inlines.last?.text, "# literal title, not a command")
            XCTAssertTrue(paragraph.evidenceRefs.isEmpty)
            try peer.applyUpdate(change.update)
            XCTAssertEqual(try peer.snapshot(), try document.snapshot())
            try peer.applyUpdate(try XCTUnwrap(document.undo()))
            XCTAssertEqual(try document.snapshot(), before)
            XCTAssertEqual(try peer.snapshot(), before)
        }
    }

    func testStaleSnapshotAndInvalidOrNestedDuplicateIDCannotAppend() throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST:
            RelayMarkSourceCodec.parseDocument("- Outer\n  - Inner", namespace: "append-stale-human"))
        let before = try document.snapshot()
        let original = try RelayMarkNativeDocumentProjection.project(document: document)
        let nestedID = try XCTUnwrap(original.blocks.first?.childBlocks.first?.childBlocks.first?.id)
        for id in ["invalid-id", nestedID] {
            XCTAssertThrowsError(try RelayMarkNativeRichEditing.appendParagraph(document: document,
                id: id, text: "Keep this human sentence.", expectedSnapshot: before))
            XCTAssertEqual(try document.snapshot(), before)
        }
        _ = try RelayMarkNativeRichEditing.appendParagraph(document: document,
            id: "b00000000000040008000000000000002", text: "First turn", expectedSnapshot: before)
        let current = try document.snapshot()
        XCTAssertThrowsError(try RelayMarkNativeRichEditing.appendParagraph(document: document,
            id: "b00000000000040008000000000000003", text: "Stale callback", expectedSnapshot: before))
        XCTAssertEqual(try document.snapshot(), current)
    }
}
