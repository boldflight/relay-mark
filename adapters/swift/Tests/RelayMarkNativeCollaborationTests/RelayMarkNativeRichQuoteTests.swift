import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeRichQuoteTests: XCTestCase {
    private func fixture() throws -> (Data, RelayMarkDocument) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich-quote-v3", withExtension: "json"))
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return (try XCTUnwrap(Data(base64Encoded: XCTUnwrap(value["update"] as? String))),
                try RelayMarkDocument.decodeJSON(JSONSerialization.data(withJSONObject: XCTUnwrap(value["expected_ast"]))))
    }

    func testCommunityRichQuotePreservesExactASTAndOneEditableNativePresentation() throws {
        let (seed, expected) = try fixture(), native = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        XCTAssertEqual(try RelayMarkNativeDocumentProjection.project(document: native), expected)
        let prose = try native.richProseProjection()
        XCTAssertTrue(prose.isEditable)
        XCTAssertEqual(prose.mediaAtoms.count, 1)
        XCTAssertEqual(prose.mediaAtoms[0].path, [0, 3])
        XCTAssertEqual(prose.callouts.count, 1)
        XCTAssertTrue(String(prose.text.characters).contains("Nested heading"))
        XCTAssertTrue(String(prose.text.characters).contains("let count = 1"))
    }

    func testRichAndNestedQuoteReturnReplaysAndUndoesWithoutFlattening() throws {
        for (path, offset) in [([0, 0], 6), ([0, 2, 0], 6), ([0, 4, 0], 7)] {
            let (seed, _) = try fixture(), native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try native.applyUpdate(seed); try peer.applyUpdate(seed)
            let snapshot = try native.snapshot(), before = try native.richProseProjection()
            let row = try XCTUnwrap(before.blockPaths.firstIndex(of: path))
            let change = try RelayMarkNativeRichReturn.apply(document: native, blockPath: path,
                utf16Offset: offset, expectedSnapshot: snapshot)
            try peer.applyUpdate(change.change.update)
            XCTAssertEqual(try native.snapshot(), try peer.snapshot())
            XCTAssertEqual(String(try native.richProseProjection().text.characters),
                (String(before.text.characters) as NSString).replacingCharacters(
                    in: NSRange(location: before.blockRanges[row].location + offset, length: 0), with: "\n"))
            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            XCTAssertEqual(try native.snapshot(), snapshot)
            XCTAssertEqual(try peer.snapshot(), snapshot)
        }
    }
}
