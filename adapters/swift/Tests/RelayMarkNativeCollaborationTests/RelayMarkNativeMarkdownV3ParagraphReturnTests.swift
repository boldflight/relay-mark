import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeMarkdownV3ParagraphReturnTests: XCTestCase {
    private func seed() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich-image-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
    }

    func testTopLevelParagraphReturnReplaysAndUndoesWithoutChangingExistingIDs() throws {
        let original = "Before image"
        for offset in [0, 6, original.utf16.count] {
            let source = try seed()
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try native.applyUpdate(source)
            try peer.applyUpdate(source)
            if offset == 6 {
                let mark = try native.formatText(at: 0, length: 8, attributes: ["bold": [:]], path: [0, 0])
                try peer.applyUpdate(mark)
            }
            let before = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
            let anchor = try native.anchor(path: [0], index: 0)
            let snapshot = try native.snapshot()
            XCTAssertThrowsError(try native.returnInMarkdownV3Paragraph(at: anchor,
                utf16Offset: 99, expectedSnapshot: snapshot))
            XCTAssertThrowsError(try native.returnInMarkdownV3Paragraph(at: anchor,
                utf16Offset: offset, expectedSnapshot: Data()))
            let change = try native.returnInMarkdownV3Paragraph(at: anchor,
                utf16Offset: offset, expectedSnapshot: snapshot)
            try peer.applyUpdate(change.update)
            let after = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
            XCTAssertEqual(after, try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer))
            XCTAssertEqual(after.blocks[0].id, before.blocks[0].id)
            XCTAssertEqual(after.blocks[1].id, change.paragraphID)
            XCTAssertEqual(after.blocks[0].plainText, String(original.prefix(offset)))
            XCTAssertEqual(after.blocks[1].plainText, String(original.dropFirst(offset)))
            if offset == 6 {
                guard case .inline(let marked)? = after.blocks[1].content.first else {
                    return XCTFail("Paragraph split lost the marked suffix")
                }
                XCTAssertEqual(marked.type, "strong")
            }
            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), before)
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), before)
        }
    }

    func testTaskListInsertionKeepsTheSourceParagraphAndReplaysToPeer() throws {
        let source = try seed()
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(source)
        try peer.applyUpdate(source)
        let before = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        let anchor = try native.anchor(path: [0], index: 0)
        let snapshot = try native.snapshot()
        XCTAssertThrowsError(try native.insertEmptyMarkdownV3TaskList(after: anchor,
            expectedSnapshot: Data()))

        let change = try native.insertEmptyMarkdownV3TaskList(after: anchor,
            expectedSnapshot: snapshot)
        try peer.applyUpdate(change.update)
        let after = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
        XCTAssertEqual(after, try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer))
        XCTAssertEqual(after.blocks[0], before.blocks[0])
        XCTAssertEqual(after.blocks[1].id, change.listID)
        XCTAssertEqual(after.blocks[1].type, "task_list")
        let tasks = try native.markdownV3ProseProjection().taskItems
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].id, change.itemID)
        XCTAssertFalse(tasks[0].checked)
        XCTAssertNil(tasks[0].entityID)

        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), before)
        XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), before)
    }
}
