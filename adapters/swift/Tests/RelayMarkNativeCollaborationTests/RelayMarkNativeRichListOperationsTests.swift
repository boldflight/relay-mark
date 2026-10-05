import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeRichListOperationsTests: XCTestCase {
    private func fixture(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "list-operations-v3", withExtension: "json"))
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(all[name] as? [String: Any])
    }

    private func expected(_ fixture: [String: Any], itemID: String, paragraphID: String) throws -> RelayMarkDocument {
        let oldItem = "b00000000000040008000000000000065"
        let oldParagraph = "b00000000000040008000000000000066"
        func replacing(_ value: Any) -> Any {
            if var dictionary = value as? [String: Any] {
                if dictionary["id"] as? String == oldItem { dictionary["id"] = itemID }
                if dictionary["id"] as? String == oldParagraph { dictionary["id"] = paragraphID }
                return dictionary.mapValues(replacing)
            }
            if let array = value as? [Any] { return array.map(replacing) }
            return value
        }
        return try RelayMarkDocument.decodeJSON(JSONSerialization.data(
            withJSONObject: replacing(try XCTUnwrap(fixture["expected_ast"]))))
    }

    private func parentID(_ document: RelayMarkNativeDocument, caret: RelayMarkNativeRichEditing.Caret?) throws -> String {
        var node = try XCTUnwrap(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
        for index in try XCTUnwrap(caret).blockPath.dropLast() {
            node = try XCTUnwrap((node["children"] as? [[String: Any]])?[index])
        }
        return try XCTUnwrap((node["attributes"] as? [String: Any])?["relaymarkId"] as? String)
    }

    func testBrowserFlatAndNestedInteriorReturnPreservesMarksIDsAndPeerUndo() throws {
        for (name, path) in [
            ("interior_flat_ordered", [0, 1, 0]),
            ("interior_nested_ordered", [0, 0, 1, 0, 0])
        ] {
            let source = try fixture(name)
            let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(source["seed"] as? String)))
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try native.applyUpdate(seed)
            try peer.applyUpdate(seed)
            let before = try RelayMarkNativeDocumentProjection.project(document: native)
            let snapshot = try native.snapshot()
            let state = try native.encodeUpdate()
            XCTAssertThrowsError(try RelayMarkNativeRichReturn.apply(document: native,
                blockPath: path, utf16Offset: 8, expectedSnapshot: snapshot))
            XCTAssertThrowsError(try RelayMarkNativeRichReturn.apply(document: native,
                blockPath: path, utf16Offset: 3, expectedSnapshot: Data()))
            XCTAssertEqual(try native.encodeUpdate(), state)
            let change = try RelayMarkNativeRichReturn.apply(document: native,
                blockPath: path, utf16Offset: 3, expectedSnapshot: snapshot)
            try peer.applyUpdate(change.change.update)
            let after = try RelayMarkNativeDocumentProjection.project(document: native)
            XCTAssertEqual(after, try expected(source, itemID: try parentID(native, caret: change.change.caret),
                                               paragraphID: change.blockID))
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), after)
            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)
        }
    }

    func testBrowserFlatAndNestedEmptyExitReplaysStructureAndUndoes() throws {
        for (name, path) in [
            ("exit_flat_ordered", [0, 1, 0]), ("exit_flat_bullet", [0, 1, 0]),
            ("exit_nested_ordered", [0, 0, 1, 0, 0]),
            ("exit_nested_bullet", [0, 0, 1, 0, 0])
        ] {
            let source = try fixture(name)
            let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(source["seed"] as? String)))
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try native.applyUpdate(seed)
            try peer.applyUpdate(seed)
            let before = try RelayMarkNativeDocumentProjection.project(document: native)
            let snapshot = try native.snapshot()
            let state = try native.encodeUpdate()
            XCTAssertThrowsError(try RelayMarkNativeRichReturn.apply(document: native,
                blockPath: path, utf16Offset: 0, expectedSnapshot: Data()))
            XCTAssertEqual(try native.encodeUpdate(), state)
            let change = try RelayMarkNativeRichReturn.apply(document: native,
                blockPath: path, utf16Offset: 0, expectedSnapshot: snapshot)
            try peer.applyUpdate(change.change.update)
            let after = try RelayMarkNativeDocumentProjection.project(document: native)
            var expectedSource = source
            if path.count == 5 {
                // Maintained splitListItem creates a new default paragraph for
                // nested empty exit; bind only that freshly allocated ID.
                let oldID = before.blocks[0].childBlocks[0].childBlocks[1].childBlocks[0].childBlocks[0].id
                func replaceNewParagraph(_ value: Any) -> Any {
                    if var object = value as? [String: Any] {
                        if object["id"] as? String == oldID { object["id"] = change.blockID }
                        return object.mapValues(replaceNewParagraph)
                    }
                    if let array = value as? [Any] { return array.map(replaceNewParagraph) }
                    return value
                }
                expectedSource["expected_ast"] = replaceNewParagraph(try XCTUnwrap(source["expected_ast"]))
            }
            let expected = try expected(expectedSource, itemID: (path.count == 5 ? try parentID(native, caret: change.change.caret) : nil) ??
                "b00000000000040008000000000000065", paragraphID:
                "b00000000000040008000000000000066")
            XCTAssertEqual(after, expected)
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), after)
            XCTAssertThrowsError(try RelayMarkNativeRichReturn.apply(document: native,
                blockPath: path, utf16Offset: 0, expectedSnapshot: snapshot))
            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)
        }
    }

    func testCommunityTaskReturnSplitsUncheckedSiblingAndExitsLastEmptyItem() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "task-list-flat-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let split = try RelayMarkNativeRichReturn.apply(document: native, blockPath: [0, 0, 0],
            utf16Offset: 4, expectedSnapshot: native.snapshot())
        try peer.applyUpdate(split.change.update)
        let afterSplit = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(afterSplit, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(afterSplit.blocks[0].childBlocks.map(\.plainText), ["Done", " today", "Next"])
        XCTAssertEqual(afterSplit.blocks[0].childBlocks.map { $0.props["checked"] },
                       [.bool(true), .bool(false), .bool(false)])
        XCTAssertEqual(afterSplit.blocks[0].childBlocks[1].props["entityId"], .null)
        XCTAssertEqual(afterSplit.blocks[0].childBlocks[1].id, try parentID(native, caret: split.change.caret))
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), before)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), before)

        let append = try RelayMarkNativeRichReturn.apply(document: native, blockPath: [0, 1, 0], utf16Offset: 4,
            expectedSnapshot: native.snapshot())
        try peer.applyUpdate(append.change.update)
        let afterAppend = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(afterAppend.blocks[0].childBlocks.last?.id, try parentID(native, caret: append.change.caret))
        XCTAssertEqual(afterAppend.blocks[0].childBlocks.last?.props["checked"], .bool(false))
        XCTAssertEqual(afterAppend.blocks[0].childBlocks.last?.props["entityId"], .null)
        XCTAssertEqual(afterAppend, try RelayMarkNativeDocumentProjection.project(document: peer))
        let exit = try RelayMarkNativeRichReturn.apply(document: native, blockPath: [0, 2, 0], utf16Offset: 0,
            expectedSnapshot: native.snapshot())
        try peer.applyUpdate(exit.change.update)
        let afterExit = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(afterExit.blocks.map(\.type), ["task_list", "paragraph"])
        XCTAssertEqual(afterExit.blocks[0], before.blocks[0])
        XCTAssertEqual(afterExit.blocks[1].id, append.blockID)
        XCTAssertEqual(afterExit, try RelayMarkNativeDocumentProjection.project(document: peer))
    }

    func testSingleEmptyCommunityTaskExitsToParagraphAndUndoes() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "task-list-single-empty-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(before.blocks.map(\.type), ["task_list"])
        let paragraphID = try XCTUnwrap(before.blocks[0].childBlocks[0].childBlocks.first?.id)
        let exit = try RelayMarkNativeRichReturn.apply(document: native, blockPath: [0, 0, 0], utf16Offset: 0,
            expectedSnapshot: native.snapshot())
        try peer.applyUpdate(exit.change.update)
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(after.blocks.map(\.type), ["paragraph"])
        XCTAssertEqual(after.blocks[0].id, paragraphID)
        XCTAssertEqual(after, try RelayMarkNativeDocumentProjection.project(document: peer))
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(before, try RelayMarkNativeDocumentProjection.project(document: native))
        XCTAssertEqual(before, try RelayMarkNativeDocumentProjection.project(document: peer))
    }

    func testNestedCommunityTaskReturnKeepsOuterMixedStructure() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "task-list-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let before = try RelayMarkNativeDocumentProjection.project(document: native)
        let change = try RelayMarkNativeRichReturn.apply(document: native,
            blockPath: [1, 0, 2, 0, 0], utf16Offset: before.blocks[1].childBlocks[0].childBlocks[2].childBlocks[0].plainText.utf16.count,
            expectedSnapshot: native.snapshot())
        try peer.applyUpdate(change.change.update)
        let after = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(after, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(after.blocks[0], before.blocks[0])
        XCTAssertEqual(after.blocks[2], before.blocks[2])
        XCTAssertEqual(after.blocks[1].childBlocks[0].childBlocks[0],
                       before.blocks[1].childBlocks[0].childBlocks[0])
        XCTAssertEqual(after.blocks[1].childBlocks[0].childBlocks[3],
                       before.blocks[1].childBlocks[0].childBlocks[3])
        let nested = after.blocks[1].childBlocks[0].childBlocks[2]
        XCTAssertEqual(nested.childBlocks.count, 2)
        XCTAssertEqual(nested.childBlocks[1].id, try parentID(native, caret: change.change.caret))
        XCTAssertEqual(nested.childBlocks[1].props["checked"], .bool(false))
        XCTAssertEqual(nested.childBlocks[1].props["entityId"], .null)
        try peer.applyUpdate(try XCTUnwrap(native.undo()))
        XCTAssertEqual(before, try RelayMarkNativeDocumentProjection.project(document: native))
        XCTAssertEqual(before, try RelayMarkNativeDocumentProjection.project(document: peer))
    }
}
