import Foundation
import XCTest
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeMarkdownV3TableCommandTests: XCTestCase {
    private typealias Command = RelayMarkNativeMarkdownV3TableCommand

    private static let operations: [String: Command.Operation] = [
        "addRowAfter": .addRowAfter, "addRowBefore": .addRowBefore,
        "addColumnAfter": .addColumnAfter, "addColumnBefore": .addColumnBefore,
        "deleteRow": .deleteRow, "deleteColumn": .deleteColumn, "deleteTable": .deleteTable,
        "toggleHeaderRow": .toggleHeaderRow, "toggleHeaderColumn": .toggleHeaderColumn,
        "toggleHeaderCell": .toggleHeaderCell, "mergeCells": .mergeCells, "splitCell": .splitCell,
    ]

    private func cases() throws -> [[String: Any]] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "table-commands-v3", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(fixture["cases"] as? [[String: Any]])
    }

    private func path(of id: String, in node: [String: Any], prefix: [Int] = []) -> [Int]? {
        if (node["attributes"] as? [String: Any])?["relaymarkId"] as? String == id { return prefix }
        for (index, child) in (node["children"] as? [[String: Any]] ?? []).enumerated() {
            if let found = path(of: id, in: child, prefix: prefix + [index]) { return found }
        }
        return nil
    }

    private func ids(_ node: [String: Any]) -> [String] {
        let own = ((node["attributes"] as? [String: Any])?["relaymarkId"] as? String).map { [$0] } ?? []
        return own + (node["children"] as? [[String: Any]] ?? []).flatMap(ids)
    }

    private func withoutIDs(_ value: Any) -> Any {
        if var object = value as? [String: Any] {
            if var attributes = object["attributes"] as? [String: Any] {
                attributes["relaymarkId"] = nil
                object["attributes"] = attributes
            }
            return object.mapValues(withoutIDs)
        }
        if let array = value as? [Any] { return array.map(withoutIDs) }
        return value
    }

    private func canonical(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: withoutIDs(value), options: [.sortedKeys]),
               as: UTF8.self)
    }

    private func tree(_ document: RelayMarkNativeDocument) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
    }

    /// Every span case is replayed against actual TipTap TableKit output:
    /// same XML, same retained identities, peer convergence and exact undo.
    func testSpannedCommandsMatchCommunityTableKitAndReplayUndo() throws {
        let cases = try cases()
        XCTAssertEqual(cases.count, 23)
        for entry in cases {
            let command = try XCTUnwrap(entry["command"] as? String)
            let operation = try XCTUnwrap(Self.operations[command])
            let seedText = try XCTUnwrap(entry["seed"] as? String)
            let seed = try XCTUnwrap(Data(base64Encoded: seedText))
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try native.applyUpdate(seed)
            try peer.applyUpdate(seed)
            let before = try native.snapshot(), beforeTree = try tree(native)
            let anchorID = try XCTUnwrap(entry["anchor_id"] as? String)
            let anchorPath = try XCTUnwrap(path(of: anchorID, in: beforeTree))
            let anchor = try native.anchor(path: anchorPath, index: 0)
            let headID = entry["head_id"] as? String
            let headPath = headID.flatMap { path(of: $0, in: beforeTree) }
            let head = try headPath.map { try native.anchor(path: $0, index: 0) }
            XCTAssertTrue(Command.canApply(operation, document: native, cellAnchor: anchor, expectedCellID: anchorID,
                                           headAnchor: head, expectedHeadCellID: headID), command)
            XCTAssertThrowsError(try Command.apply(operation, document: native, cellAnchor: anchor,
                expectedCellID: "b00000000000040008000000000000999", headAnchor: head,
                expectedHeadCellID: headID, expectedSnapshot: before), command)

            let update: Data
            do {
                update = try Command.apply(operation, document: native, cellAnchor: anchor, expectedCellID: anchorID,
                                           headAnchor: head, expectedHeadCellID: headID, expectedSnapshot: before)
            } catch {
                XCTFail("\(command) \(entry["table"] ?? "spanned"): \(error)")
                continue
            }
            try peer.applyUpdate(update)
            let after = try tree(native)
            let expected = try XCTUnwrap(entry["after_xml"] as? [String: Any])
            XCTAssertEqual(try canonical(after), try canonical(expected), command)
            XCTAssertEqual(try native.snapshot(), try peer.snapshot(), command)
            let original = Set(ids(beforeTree)), nativeIDs = ids(after)
            XCTAssertEqual(Set(nativeIDs).count, nativeIDs.count, command)
            XCTAssertEqual(Set(ids(expected)).count, ids(expected).count, command)
            XCTAssertEqual(Set(nativeIDs).intersection(original), Set(ids(expected)).intersection(original), command)
            XCTAssertTrue(try native.markdownV3ProseProjection().isEditable, command)

            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            XCTAssertEqual(try native.snapshot(), before, command)
            XCTAssertEqual(try peer.snapshot(), before, command)
        }
    }

    /// Retained cells stay the same Yjs elements, so a concurrent peer edit in
    /// a cell survives a structural column deletion elsewhere in the table.
    func testRetainedCellsKeepIdentityForConcurrentText() throws {
        let entry = try XCTUnwrap(try cases().first { $0["command"] as? String == "deleteColumn" })
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(entry["seed"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let peerTree = try tree(peer)
        let dCell = try XCTUnwrap(ids(peerTree).first { id in
            guard let found = path(of: id, in: peerTree),
                  let node = try? RelayMarkNativeMarkdownV3XML.node(at: found, in: peerTree) else { return false }
            return node["name"] as? String == "paragraph" &&
                (try? canonical(node))?.contains("\"insert\":\"D\"") == true
        })
        let peerUpdate = try RelayMarkNativeMarkdownV3TextMutation.replace(document: peer, blockID: dCell,
            childIndex: 0, start: 1, end: 1, text: " concurrent")
        let anchorID = try XCTUnwrap(entry["anchor_id"] as? String)
        let anchorPath = try XCTUnwrap(path(of: anchorID, in: try tree(native)))
        let update = try Command.apply(.deleteColumn, document: native,
            cellAnchor: native.anchor(path: anchorPath, index: 0), expectedCellID: anchorID,
            expectedSnapshot: native.snapshot())
        try native.applyUpdate(peerUpdate)
        try peer.applyUpdate(update)
        XCTAssertEqual(try native.snapshot(), try peer.snapshot())
        XCTAssertTrue(String(try native.markdownV3ProseProjection().text.characters).contains("D concurrent"))
    }
}
