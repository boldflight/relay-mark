import Foundation
import XCTest
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeRichTableCommandTests: XCTestCase {
    private typealias Command = RelayMarkNativeRichTableCommand

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

            let beforeState = try native.encodeUpdate()
            let beforeIdentity = try native.captureIdentitySnapshot()
            let beforeClocks = try JSONSerialization.jsonObject(with: native.captureUpdateFootprint(Data([0,0]))) as! [String: Any]
            let observation = try native.captureContentEditObservation()
            let operationID = UUID()
            var update: RelayMarkNativeRichEditing.Change!
            do {
                _ = try native.performOwnedCommand(operationID: operationID, separateHistoryItem: true) {
                    update = try Command.apply(operation, document: native, cellAnchor: anchor, expectedCellID: anchorID,
                                               headAnchor: head, expectedHeadCellID: headID, expectedSnapshot: before)
                    return update.update
                }
            } catch {
                XCTFail("\(command) \(entry["table"] ?? "spanned"): \(error)")
                continue
            }
            let witness = try JSONSerialization.jsonObject(with: native.buildContentEditWitness(observation, steps: update.steps, update: update.update)) as! [String: Any]
            XCTAssertEqual(((witness["text_items"] as! [String: Any])["runs"] as! [Any]).count, 0, command)
            let expectedCopies: [String: Int] = ["deleteRow:b00000000000a40008000000000000000": 1,
                "mergeCells:b00000000000a40008000000000000000": 3,
                "mergeCells:b00000000000840008000000000000000": 1,
                "mergeCells:b00000000000340008000000000000000": 1]
            if let count = expectedCopies[command + ":" + anchorID] {
                let copies = witness["proven_copies"] as! [[String: Any]]
                let units = copies.reduce(0) { total, copy in total + ((copy["destination"] as! [String: Any])["runs"] as! [[String: Any]]).reduce(0) { $0 + ($1["count"] as! Int) } }
                XCTAssertEqual(units, count, "\(command) copied original cell content")
                if ProcessInfo.processInfo.environment["RELAYMARK_EXPORT_TABLE_COPY_FIXTURE"] != nil {
                    let identity = try JSONSerialization.jsonObject(with: beforeIdentity)
                    let afterIdentity = try JSONSerialization.jsonObject(with: native.captureIdentitySnapshot())
                    let footprint = try JSONSerialization.jsonObject(with: native.captureUpdateFootprint(update.update)) as! [String: Any]
                    let group = try native.ownedCommandGroup(operationID: operationID)
                    let operation: [String: Any] = ["kind":"content_edit", "steps": try JSONSerialization.jsonObject(with: update.steps), "copies": copies,
                        "group": ["owner_id":group.ownerID.uuidString.lowercased(), "reference":group.reference.uuidString.lowercased(), "operation_ids":group.operationIDs.map { $0.uuidString.lowercased() }]]
                    let evidence: [String: Any] = ["sender_before_snapshot": identity, "sender_after_snapshot": afterIdentity, "before_snapshot": identity, "after_snapshot": afterIdentity, "before_state_vector": beforeClocks["state_vector"]!, "operation":operation, "footprint":footprint]
                    let frame: [String: Any] = ["description":"Actual maintained native \(command) copies existing cell content, not human input", "transaction_id":operationID.uuidString.lowercased(), "text_items":witness["text_items"]!, "sender_state_base64":beforeState.base64EncodedString(), "current_state_base64":beforeState.base64EncodedString(), "before_snapshot_base64":update.beforeSnapshot.base64EncodedString(), "update_base64":update.update.base64EncodedString(), "writer_client": (footprint["state_vector"] as! [[String: Any]]).first { entry in !(beforeClocks["state_vector"] as! [[String: Any]]).contains { $0["client"] as! UInt64 == entry["client"] as! UInt64 } }!["client"]!, "operation":operation, "footprint":footprint, "evidence":evidence, "expected_copied_units":count]
                    try JSONSerialization.data(withJSONObject:frame,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:"spec/relaymark/collaboration/fixtures/content-edit-native-table-\(command)-\(anchorID).json"))
                }
            }
            XCTAssertFalse((try JSONSerialization.jsonObject(with: update.steps) as! [Any]).isEmpty, command)
            try peer.applyUpdate(update.update)
            let after = try tree(native)
            let expected = try XCTUnwrap(entry["after_xml"] as? [String: Any])
            XCTAssertEqual(try canonical(after), try canonical(expected), command)
            XCTAssertEqual(try native.snapshot(), try peer.snapshot(), command)
            let original = Set(ids(beforeTree)), nativeIDs = ids(after)
            XCTAssertEqual(Set(nativeIDs).count, nativeIDs.count, command)
            XCTAssertEqual(Set(ids(expected)).count, ids(expected).count, command)
            XCTAssertEqual(Set(nativeIDs).intersection(original), Set(ids(expected)).intersection(original), command)
            XCTAssertTrue(try native.richProseProjection().isEditable, command)

            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            XCTAssertEqual(try native.snapshot(), before, command)
            XCTAssertEqual(try peer.snapshot(), before, command)
        }
    }

    /// Retained cells stay the same Yjs elements: a peer edit in another cell
    /// survives merging existing source content and the actual owned undo.
    func testRetainedCellsKeepIdentityForConcurrentText() throws {
        let entry = try XCTUnwrap(try cases().first { $0["command"] as? String == "mergeCells" })
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(entry["seed"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let peerTree = try tree(peer)
        let dCell = try XCTUnwrap(ids(peerTree).first { id in
            guard let found = path(of: id, in: peerTree),
                  let node = try? RelayMarkNativeRichXML.node(at: found, in: peerTree) else { return false }
            return node["name"] as? String == "paragraph" &&
                (try? canonical(node))?.contains("\"insert\":\"D\"") == true
        })
        let peerUpdate = try RelayMarkNativeRichTextMutation.replace(document: peer, blockID: dCell,
            childIndex: 0, start: 1, end: 1, text: " concurrent")
        let anchorID = try XCTUnwrap(entry["anchor_id"] as? String)
        let anchorPath = try XCTUnwrap(path(of: anchorID, in: try tree(native)))
        let headID = try XCTUnwrap(entry["head_id"] as? String)
        let headPath = try XCTUnwrap(path(of: headID, in: try tree(native)))
        let observation = try native.captureContentEditObservation()
        let operationID = UUID()
        var update: RelayMarkNativeRichEditing.Change!
        _ = try native.performOwnedCommand(operationID: operationID, separateHistoryItem: true) {
            update = try Command.apply(.mergeCells, document: native,
                cellAnchor: native.anchor(path: anchorPath, index: 0), expectedCellID: anchorID,
                headAnchor: native.anchor(path: headPath, index: 0), expectedHeadCellID: headID,
                expectedSnapshot: native.snapshot())
            return update.update
        }
        let witness = try JSONSerialization.jsonObject(with: native.buildContentEditWitness(observation, steps: update.steps, update: update.update)) as! [String: Any]
        XCTAssertEqual(((witness["text_items"] as! [String: Any])["runs"] as! [Any]).count, 0)
        XCTAssertFalse((witness["proven_copies"] as! [Any]).isEmpty)
        try native.applyUpdate(peerUpdate)
        try peer.applyUpdate(update.update)
        XCTAssertEqual(try native.snapshot(), try peer.snapshot())
        XCTAssertTrue(String(try native.richProseProjection().text.characters).contains("D concurrent"))
        let inverseObservation = try native.captureContentEditObservation()
        let inverse = try XCTUnwrap(native.undoWithReference())
        XCTAssertEqual(inverse.reference, operationID)
        let inverseWitness = try JSONSerialization.jsonObject(with: native.buildOwnedHistoryWitness(inverseObservation, effect: inverse)) as! [String: Any]
        XCTAssertEqual(((inverseWitness["text_items"] as! [String: Any])["runs"] as! [Any]).count, 0)
        try peer.applyUpdate(inverse.update)
        XCTAssertEqual(try native.snapshot(), try peer.snapshot())
        let expected = RelayMarkNativeDocument()
        try expected.applyUpdate(seed); try expected.applyUpdate(peerUpdate)
        XCTAssertEqual(try native.snapshot(), try expected.snapshot())
    }
}
