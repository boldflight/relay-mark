import Foundation
import XCTest
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeDocumentTests: XCTestCase {
    func testPortableAnchorsMatchYjsRelativePositionFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "relative-ranges-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String))))
        let ranges = try XCTUnwrap(fixture["ranges"] as? [[String: Any]])
        for range in ranges {
            let wire = try XCTUnwrap(range["range"] as? [String: Any])
            for endpoint in ["anchor", "head"] {
                let encoded = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(wire[endpoint] as? String)))
                guard let expected = range["expected"] as? [String: Any] else {
                    XCTAssertNil(try document.resolve(anchor: encoded))
                    continue
                }
                let position = try XCTUnwrap(expected[endpoint] as? [String: Any])
                let path = try XCTUnwrap(position["path"] as? [Int])
                let index = try XCTUnwrap(position["index"] as? Int)
                let association = try XCTUnwrap(position["association"] as? Int)
                let label = "\(range["name"] ?? "range") \(endpoint)"
                XCTAssertEqual(try document.anchor(path: path, index: index, association: association), encoded, label)
                XCTAssertEqual(try document.resolve(anchor: encoded),
                               .init(path: path, index: index, association: association), label)
            }
        }
    }

    func testSnapshotPreservesTypedXmlAttributesAndInlineMarks() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "inline-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(fixture["seed"] as? String)
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(try XCTUnwrap(Data(base64Encoded: seed)))
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
        let children = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
        let heading = try XCTUnwrap(children.first)
        XCTAssertEqual(heading["name"] as? String, "heading")
        XCTAssertEqual((heading["attributes"] as? [String: Any])?["level"] as? Int, 2)
        XCTAssertFalse(children.isEmpty)
        let projection = try document.proseProjection()
        XCTAssertTrue(projection.isEditable)
        XCTAssertEqual(String(projection.text.characters), fixture["initial_text"] as? String)
    }

    func testTextLeafEditProducesPortableIncrementalUpdate() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "convergence-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        let testCase = try XCTUnwrap(cases.first { $0["id"] as? String == "unicode-delete-only" })
        let updates = try XCTUnwrap(testCase["updates"] as? [String])
        let seed = try XCTUnwrap(Data(base64Encoded: updates[0]))
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        let replica = RelayMarkNativeDocument()
        try replica.applyUpdate(seed)

        let insertion = try document.insertText("🙂", at: 1, path: [0, 0])
        try replica.applyUpdate(insertion)
        XCTAssertEqual(try document.snapshot(), try replica.snapshot())

        let deletion = try document.deleteText(at: 1, length: 2, path: [0, 0])
        try replica.applyUpdate(deletion)
        XCTAssertEqual(try document.snapshot(), try replica.snapshot())

        let formatting = try document.formatText(at: 0, length: 1, attributes: ["bold": [:]], path: [0, 0])
        try replica.applyUpdate(formatting)
        XCTAssertEqual(try document.snapshot(), try replica.snapshot())
        let merged = try document.mergeUpdates([insertion, deletion, formatting])
        let mergedReplica = RelayMarkNativeDocument()
        try mergedReplica.applyUpdate(seed)
        try mergedReplica.applyUpdate(merged)
        XCTAssertEqual(try document.snapshot(), try mergedReplica.snapshot())

        let replacement = try document.replaceText(at: 0, length: 1, with: "Q", path: [0, 0])
        try replica.applyUpdate(replacement)
        XCTAssertEqual(try document.snapshot(), try replica.snapshot())
        let undo = try XCTUnwrap(document.undo())
        try replica.applyUpdate(undo)
        XCTAssertEqual(try document.snapshot(), try replica.snapshot())
        XCTAssertThrowsError(try document.deleteText(at: 999, length: 1, path: [0, 0]))
    }

    func testUndoTracksOnlyLocalOriginAcrossRemoteEdit() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "convergence-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        let testCase = try XCTUnwrap(cases.first { $0["id"] as? String == "unicode-delete-only" })
        let updates = try XCTUnwrap(testCase["updates"] as? [String])
        let seed = try XCTUnwrap(Data(base64Encoded: updates[0]))
        let local = RelayMarkNativeDocument()
        let peer = RelayMarkNativeDocument()
        try local.applyUpdate(seed)
        try peer.applyUpdate(seed)

        let localEdit = try local.insertText("X", at: 1, path: [0, 0])
        try peer.applyUpdate(localEdit)
        let peerEdit = try peer.insertText("Y", at: 0, path: [0, 0])
        try local.applyUpdate(peerEdit)
        let before = String(try local.proseProjection().text.characters)
        XCTAssertTrue(before.contains("X") && before.contains("Y"))

        let undo = try XCTUnwrap(local.undo())
        try peer.applyUpdate(undo)
        XCTAssertEqual(try local.snapshot(), try peer.snapshot())
        let afterUndo = String(try local.proseProjection().text.characters)
        XCTAssertFalse(afterUndo.contains("X"))
        XCTAssertTrue(afterUndo.contains("Y"))

        let redo = try XCTUnwrap(local.redo())
        try peer.applyUpdate(redo)
        XCTAssertEqual(try local.snapshot(), try peer.snapshot())
        let afterRedo = String(try local.proseProjection().text.characters)
        XCTAssertTrue(afterRedo.contains("X") && afterRedo.contains("Y"))
    }

    func testCommunityYjsUpdatesProjectToRelayMarkXMLAndConverge() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "convergence-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])

        for testCase in cases {
            let id = try XCTUnwrap(testCase["id"] as? String)
            let updates = try XCTUnwrap(testCase["updates"] as? [String]).map {
                try XCTUnwrap(Data(base64Encoded: $0))
            }
            let orders = try XCTUnwrap(testCase["orders"] as? [[Int]])
            let expected = try XCTUnwrap(testCase["expected"])
            for order in orders {
                let document = RelayMarkNativeDocument()
                for index in order { try document.applyUpdate(updates[index]) }
                let snapshot = try JSONSerialization.jsonObject(with: document.snapshot())
                XCTAssertTrue((snapshot as AnyObject).isEqual(expected), "\(id), order \(order), actual: \(snapshot)")

                let replica = RelayMarkNativeDocument()
                try replica.applyUpdate(document.encodeUpdate())
                let remoteVector = replica.stateVector()
                let diff = try document.encodeUpdate(since: remoteVector)
                try replica.applyUpdate(diff)
                let roundTrip = try JSONSerialization.jsonObject(with: replica.snapshot())
                XCTAssertTrue((roundTrip as AnyObject).isEqual(expected), "\(id), round trip, actual: \(roundTrip)")
            }
        }
    }
}
