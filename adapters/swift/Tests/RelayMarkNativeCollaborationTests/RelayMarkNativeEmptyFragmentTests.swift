import Foundation
import XCTest
import RelayMarkNativeCollaboration

/// An EMPTY root fragment projects as a document with one empty paragraph, in the view and the
/// projection only, as y-prosemirror and y-tiptap do. Nothing is written to Yjs until the first
/// local edit, which writes the paragraph and the edit in one transaction. Today's paper
/// (a daily paper whose body starts empty) must open in the native editor.
@MainActor
final class RelayMarkNativeEmptyFragmentTests: XCTestCase {
    private func children(_ document: RelayMarkNativeDocument) throws -> [[String: Any]] {
        let tree = try XCTUnwrap(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
        return try XCTUnwrap(tree["children"] as? [[String: Any]])
    }

    private func text(_ paragraph: [String: Any]) -> String {
        ((paragraph["children"] as? [[String: Any]]) ?? []).flatMap { ($0["delta"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["insert"] as? String }.joined()
    }

    private func firstRichEdit(_ document: RelayMarkNativeDocument, _ text: String) throws -> Data {
        try RelayMarkNativeRichEditing.replace(document: document, range: NSRange(location: 0, length: 0),
                                               runs: [(text, [:])], inheritMarks: true,
                                               expectedSnapshot: document.snapshot()).update
    }

    // Keep: materializing on open writes a paragraph two replicas would both create, and a
    // paper that is only opened would stop being empty (a Today paper would never read as new).
    func testOpeningProjectingAndRenderingAnEmptyFragmentWritesNothing() throws {
        let document = RelayMarkNativeDocument()
        let (vector, state) = (document.stateVector(), try document.encodeUpdate())
        let prose = try document.richProseProjection()
        _ = try document.proseProjection()
        _ = try RelayMarkNativeDocumentProjection.project(document: document)
        let authored = try XCTUnwrap(JSONSerialization.jsonObject(with: document.authoredDocument()) as? [String: Any])
        XCTAssertEqual(document.stateVector(), vector)
        XCTAssertEqual(try document.encodeUpdate(), state)
        XCTAssertEqual(document.topLevelCount, 0)
        XCTAssertTrue(try children(document).isEmpty, "the snapshot stays the lossless tree")
        // The projection is one empty paragraph with the cursor at offset 0 inside it.
        XCTAssertTrue(prose.isEditable)
        XCTAssertEqual(String(prose.text.characters), "")
        XCTAssertEqual(prose.blockPaths, [[0]])
        XCTAssertEqual(prose.blockRanges, [NSRange(location: 0, length: 0)])
        let blocks = try XCTUnwrap(authored["blocks"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?["type"] as? String, "paragraph")
        XCTAssertEqual(blocks.first?["id"] as? String, RelayMarkNativeDocument.virtualParagraphID)
    }

    // Keep: before this, a rich edit on an empty paper failed on the projection, so a Today paper
    // could not take its first keystroke in the native editor.
    func testTheFirstRichEditWritesTheParagraphAndTheTextInOneTransaction() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let update = try firstRichEdit(document, "Hello")
        try peer.applyUpdate(update)
        for replica in [document, peer] {
            let nodes = try children(replica)
            XCTAssertEqual(nodes.count, 1)
            XCTAssertEqual(text(nodes[0]), "Hello")
            let id = (nodes[0]["attributes"] as? [String: Any])?["relaymarkId"] as? String
            XCTAssertNotNil(id)
            XCTAssertNotEqual(id, RelayMarkNativeDocument.virtualParagraphID, "the projected id is never persisted")
            XCTAssertEqual(String(try replica.richProseProjection().text.characters), "Hello")
        }
    }

    func testTheFirstRichEditThroughAHostProjectionAndAnInsertionBothMaterializeOneParagraph() throws {
        let windowed = RelayMarkNativeDocument()
        let paper = try windowed.richProseProjection()
        _ = try RelayMarkNativeRichEditing.replace(document: windowed, range: NSRange(location: 0, length: 0),
                                                   runs: [("Hi", [:])], paper: paper)
        XCTAssertEqual(try children(windowed).map(text), ["Hi"])
        let inserted = RelayMarkNativeDocument()
        _ = try RelayMarkNativeRichEditing.insert(document: inserted, range: NSRange(location: 0, length: 0),
                                                  content: [.text("Yo")], expectedSnapshot: inserted.snapshot())
        XCTAssertEqual(try children(inserted).map(text), ["Yo"])
    }

    func testTheFirstPlainProseEditWritesOneParagraphWithTheText() throws {
        let document = RelayMarkNativeDocument()
        _ = try document.replaceProse(start: 0, end: 0, text: "Hello")
        XCTAssertEqual(try children(document).map(text), ["Hello"])
    }

    // y-prosemirror behaves this way: each replica creates the paragraph on its first edit, so
    // two replicas that both start from an empty paper and then merge hold two paragraphs.
    // This is documented behavior and is not "fixed" here.
    func testTwoConcurrentFirstEditsMergeIntoTwoParagraphs() throws {
        let a = RelayMarkNativeDocument(), b = RelayMarkNativeDocument()
        let fromA = try firstRichEdit(a, "A"), fromB = try firstRichEdit(b, "B")
        try a.applyUpdate(fromB); try b.applyUpdate(fromA)
        let left = try children(a), right = try children(b)
        XCTAssertEqual(left.count, 2)
        XCTAssertEqual(Set(left.map(text)), ["A", "B"])
        XCTAssertEqual(left.map(text), right.map(text), "both replicas order the paragraphs the same way")
        let ids = left.compactMap { ($0["attributes"] as? [String: Any])?["relaymarkId"] as? String }
        XCTAssertEqual(Set(ids).count, 2, "each first edit gets its own identity")
        XCTAssertNoThrow(try a.richProseProjection())
    }

    // A non-empty fragment is not virtualized.
    func testANonEmptyFragmentProjectsExactlyAsItIs() throws {
        let document = RelayMarkNativeDocument()
        _ = try firstRichEdit(document, "One")
        XCTAssertEqual(document.topLevelCount, 1)
        XCTAssertEqual(try document.richProseProjection().blockPaths, [[0]])
        XCTAssertEqual(String(try document.richProseProjection().text.characters), "One")
    }

    // Every first action on an empty paper, as a person can reach it: the paragraph and the
    // edit land in one update that reproduces the whole change on a peer, one undo item takes
    // it all back, and the projected placeholder id is never persisted. Keep: each of these
    // read the tree, an index or an id from the lossless snapshot, which has no paragraph.
    func testEveryFirstActionOnAnEmptyPaperMaterializesOneParagraphWithTheEdit() throws {
        let reference = RelayMarkNativeInlineAtomMutation.Atom(kind: .relayReference, attributes: [
            "entityType": "Person", "entityId": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "label": "Grace Hopper",
            "source": "[[Person: bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb | Grace Hopper]]"])
        let tag = RelayMarkNativeInlineAtomMutation.Atom(kind: .relayTag, attributes: [
            "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "name": "followup",
            "source": "[[Tag: aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa | #followup]]"])
        let slice = try JSONSerialization.data(withJSONObject: [
            "slice": ["content": [["type": "paragraph", "content": [["type": "text", "text": "Pasted"]]]], "openStart": 1, "openEnd": 1],
            "normalizations": [[String: Any]]()])
        let caret = NSRange(location: 0, length: 0)
        let cases: [(name: String, blocks: [String], edit: (RelayMarkNativeDocument) throws -> Data)] = [
            ("Enter", ["paragraph", "paragraph"], { document in
                try RelayMarkNativeRichReturn.apply(document: document, blockPath: [0], utf16Offset: 0,
                                                    expectedSnapshot: document.snapshot()).change.update }),
            ("heading", ["heading"], { document in
                try document.setRichBlockStyle(at: 0, style: .heading(1), expectedSnapshot: document.snapshot()).update }),
            // The host's /checklist: an empty paper has no anchor, so the call names the blank line with none.
            ("/checklist", ["taskList"], { document in
                let made = try document.insertEmptyRichTaskList(after: Data(), expectedSnapshot: document.snapshot())
                XCTAssertNotEqual(made.paragraphID, RelayMarkNativeDocument.virtualParagraphID)
                return made.change.update }),
            ("bullet list", ["bulletList"], { document in
                try document.setRichBlockStyle(at: 0, style: .bulletList, expectedSnapshot: document.snapshot()).update }),
            ("checklist", ["taskList"], { document in
                try document.setRichBlockStyle(at: 0, style: .taskList, expectedSnapshot: document.snapshot()).update }),
            ("reference chip", ["paragraph"], { document in
                try RelayMarkNativeRichEditing.insert(document: document, range: caret,
                    content: [.node(reference.kind.rawValue, attributes: reference.attributes.mapValues { $0 as Any })],
                    expectedSnapshot: document.snapshot()).update }),
            ("tag", ["paragraph"], { document in
                try RelayMarkNativeRichEditing.insert(document: document, range: caret,
                    content: [.node(tag.kind.rawValue, attributes: tag.attributes.mapValues { $0 as Any })],
                    expectedSnapshot: document.snapshot()).update }),
            ("reference chip by block id", ["paragraph"], { document in
                try RelayMarkNativeInlineAtomMutation.insert(document: document, blockID: RelayMarkNativeDocument.virtualParagraphID,
                                                             childIndex: 0, atom: reference).update }),
            ("rich paste", ["paragraph"], { document in
                try RelayMarkNativeRichEditing.insertDocumentSlice(document: document, range: caret, clipboardSlice: slice,
                                                                   expectedSnapshot: document.snapshot()).update }),
            // The host shows the placeholder as the first block, so its neighbours are the placeholder.
            ("image before the empty line", ["image", "paragraph"], { document in
                try RelayMarkNativeMediaMutation.insert(document: document, atRootIndex: 0, expectedPreviousID: nil,
                    expectedNextID: RelayMarkNativeDocument.virtualParagraphID,
                    block: .init(id: "b11111111111141118111111111111111", kind: .image, source: "https://example.com/a.png")).update }),
            ("image after the empty line", ["paragraph", "image"], { document in
                try RelayMarkNativeMediaMutation.insert(document: document, atRootIndex: 1,
                    expectedPreviousID: RelayMarkNativeDocument.virtualParagraphID, expectedNextID: nil,
                    block: .init(id: "b11111111111141118111111111111111", kind: .image, source: "https://example.com/a.png")).update }),
        ]
        for item in cases {
            let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            let update: Data
            do { update = try item.edit(document) } catch { XCTFail("\(item.name): \(error)"); continue }
            try peer.applyUpdate(update)
            for replica in [document, peer] {
                let raw = try replica.snapshot()
                XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains(RelayMarkNativeDocument.virtualParagraphID), item.name)
                XCTAssertEqual(try children(replica).compactMap { $0["name"] as? String }, item.blocks, item.name)
                XCTAssertNoThrow(try replica.richProseProjection(), item.name)
            }
            XCTAssertEqual(try document.snapshot(), try peer.snapshot(), "\(item.name): the one update carries the whole edit")
            // One undo item takes the paragraph and the edit back together.
            _ = try document.undo()
            XCTAssertEqual(document.topLevelCount, 0, "\(item.name): one undo item")
        }
    }

    func testUndoOfTheFirstEditEmptiesThePaperAgainAndAPeerFollows() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try peer.applyUpdate(firstRichEdit(document, "Hi"))
        let undone = try XCTUnwrap(document.undo())
        try peer.applyUpdate(undone)
        XCTAssertEqual(document.topLevelCount, 0)
        XCTAssertEqual(peer.topLevelCount, 0)
        XCTAssertEqual(String(try document.richProseProjection().text.characters), "", "it projects as the empty paragraph again")
    }

    // An edit addressed to a node by Yjs anchor or by text path needs that node to exist: it fails
    // plainly and writes nothing.
    func testEditsThatNeedARealNodeFailPlainlyAndWriteNothing() throws {
        let document = RelayMarkNativeDocument()
        let state = try document.encodeUpdate()
        XCTAssertThrowsError(try document.anchor(path: [0], index: 0))
        XCTAssertThrowsError(try document.replaceListParagraphText(anchor: Data([0, 0]), start: 0, end: 0, text: "x"))
        XCTAssertThrowsError(try document.typeText("x", replacing: 0, at: 0, path: [0, 0]))
        XCTAssertEqual(try document.encodeUpdate(), state)
        XCTAssertEqual(document.topLevelCount, 0)
    }
}
