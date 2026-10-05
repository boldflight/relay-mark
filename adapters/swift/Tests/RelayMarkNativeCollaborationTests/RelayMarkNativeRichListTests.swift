import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeRichListTests: XCTestCase {
    private func fixture() throws -> (Data, RelayMarkDocument) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich-list-v3", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return (try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String))),
            try RelayMarkDocument.decodeJSON(JSONSerialization.data(withJSONObject: XCTUnwrap(fixture["expected_ast"]))))
    }

    func testCommunityRichListProjectsExactlyAndReturnsAtThirdDepthWithPeerUndo() throws {
        let (seed, expected) = try fixture()
        let path = [0, 0, 4, 0, 1, 0, 0]
        for offset in [0, 5, "Third depth".utf16.count] {
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try native.applyUpdate(seed)
            try peer.applyUpdate(seed)
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), expected)
            XCTAssertTrue(try native.richProseProjection().isEditable)
            let snapshot = try native.snapshot()
            let change = try RelayMarkNativeRichReturn.apply(document: native,
                blockPath: path, utf16Offset: offset, expectedSnapshot: snapshot)
            let update = change.change.update
            try peer.applyUpdate(update)
            let after = try RelayMarkNativeDocumentProjection.project(document: native)
            XCTAssertEqual(after, try RelayMarkNativeDocumentProjection.project(document: peer))
            XCTAssertEqual(Array(after.blocks[0].childBlocks[0].childBlocks[1...3]),
                           Array(expected.blocks[0].childBlocks[0].childBlocks[1...3]))
            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), expected)
            XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: peer), expected)
        }
    }
}
