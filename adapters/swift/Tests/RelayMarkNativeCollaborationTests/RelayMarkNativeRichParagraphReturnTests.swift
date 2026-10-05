import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeRichParagraphReturnTests: XCTestCase {
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
            let before = try RelayMarkNativeDocumentProjection.project(document: native)
            let anchor = try native.anchor(path: [0], index: 0)
            let snapshot = try native.snapshot()
            XCTAssertThrowsError(try native.returnInRichParagraph(at: anchor,
                utf16Offset: 99, expectedSnapshot: snapshot))
            XCTAssertThrowsError(try native.returnInRichParagraph(at: anchor,
                utf16Offset: offset, expectedSnapshot: Data()))
            let change = try native.returnInRichParagraph(at: anchor,
                utf16Offset: offset, expectedSnapshot: snapshot)
            try peer.applyUpdate(change.update)
            let after = try RelayMarkNativeDocumentProjection.project(document: native)
            XCTAssertEqual(after, try RelayMarkNativeDocumentProjection.project(document: peer))
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
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)
        }
    }

    func testTaskListInsertionKeepsTheSourceParagraphAndReplaysToPeer() throws {
        let source = try seed()
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(source)
        try peer.applyUpdate(source)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let anchor = try native.anchor(path: [0], index: 0)
        let snapshot = try native.snapshot()
        XCTAssertThrowsError(try native.insertEmptyRichTaskList(after: anchor,
            expectedSnapshot: Data()))

        let change = try native.insertEmptyRichTaskList(after: anchor,
            expectedSnapshot: snapshot)
        try peer.applyUpdate(change.change.update)
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(after, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(after.blocks[0], before.blocks[0])
        XCTAssertEqual(after.blocks[1].id, change.listID)
        XCTAssertEqual(after.blocks[1].type, "task_list")
        let tasks = try native.richProseProjection().taskItems
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].id, change.itemID)
        XCTAssertFalse(tasks[0].checked)
        XCTAssertNil(tasks[0].entityID)
        if let path = ProcessInfo.processInfo.environment["RELAY_TASK__FIXTURE_OUTPUT"] {
            let fixture = ["schema": "relaymark-prosemirror", "root": "default",
                           "seed": source.base64EncodedString(),
                           "native_update": change.change.update.base64EncodedString(),
                           "list_id": change.listID, "item_id": change.itemID,
                           "paragraph_id": change.paragraphID]
            let encoded = try JSONSerialization.data(withJSONObject: fixture,
                options: [.prettyPrinted, .sortedKeys])
            try encoded.write(to: URL(fileURLWithPath: path))
        }

        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)
    }

    func testBrowserContinuesNativeInsertedTaskThroughYjs() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "native-task-insertion-v3", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String])
        let document = RelayMarkNativeDocument()
        for key in ["seed", "native_update", "browser_update"] {
            try document.applyUpdate(XCTUnwrap(Data(base64Encoded: XCTUnwrap(fixture[key]))))
        }
        XCTAssertTrue(document.integrationStatus().isComplete)
        let projected = try RelayMarkNativeDocumentProjection.project(document: document)
        XCTAssertEqual(projected.blocks.map(\.type), ["paragraph", "task_list", "image", "paragraph"])
        XCTAssertEqual(projected.blocks[0].plainText, "Before image")
        XCTAssertEqual(projected.blocks[1].id, fixture["list_id"])
        XCTAssertEqual(projected.blocks[1].childBlocks[0].id, fixture["item_id"])
        XCTAssertEqual(projected.blocks[1].childBlocks[0].plainText, "From browser")
        let item = try XCTUnwrap(document.richProseProjection().taskItems.first)
        XCTAssertEqual(item.id, fixture["item_id"])
        XCTAssertFalse(item.checked)
        XCTAssertNil(item.entityID)
    }
}
