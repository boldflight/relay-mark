import Foundation
import XCTest
import RelayMarkCollaboration
import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeEmptyListTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "list-end-return-v1", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    func testNativeEndReturnMatchesBrowserAndPreservesEveryExistingAnchor() throws {
        let fixture = try fixture()
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String)))
        let native = RelayMarkNativeDocument(), browser = try RelayMarkCollaborationDocument()
        try native.applyUpdate(seed); try browser.applyUpdate(seed)
        let before = try native.snapshot()
        let replay = RelayMarkNativeDocument()
        try replay.applyUpdate(seed)
        try replay.applyUpdate(XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String))))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: replay.snapshot()) as? NSDictionary, fixture["after"] as? NSDictionary)
        let paragraph = try native.anchor(path: [0, 0, 1, 0, 0], index: 0)
        try browser.applyUpdate(native.appendEmptyListItem(after: paragraph))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary, fixture["after"] as? NSDictionary)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary)
        for item in try XCTUnwrap(fixture["anchors"] as? [[String: Any]]) {
            let anchor = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(item["anchor"] as? String)))
            let resolved = try XCTUnwrap(native.resolve(anchor: anchor))
            XCTAssertEqual(resolved.path, item["path"] as? [Int])
            XCTAssertEqual(resolved.index, item["index"] as? Int)
        }
        let projection = try native.proseProjection()
        XCTAssertEqual(String(projection.text.characters), "Outer\nNested 🌍 text\n\nSibling")
        XCTAssertEqual(projection.blockRanges[2].length, 0)
        XCTAssertEqual(projection.blockPaths[2], [0, 0, 1, 1, 0])
        XCTAssertTrue(projection.blockIntents[2].components.contains { if case .listItem(ordinal: 4) = $0.kind { true } else { false } })
        let empty = try native.anchor(path: [0, 0, 1, 1, 0], index: 0)
        try browser.applyUpdate(native.replaceListParagraphText(anchor: empty, start: 0, end: 0, text: "New 🌍"))
        XCTAssertTrue(String(try native.proseProjection().text.characters).contains("New 🌍"))
        try browser.applyUpdate(XCTUnwrap(native.undo()))
        XCTAssertEqual(try native.proseProjection().blockRanges[2].length, 0)
        try browser.applyUpdate(XCTUnwrap(native.undo()))
        XCTAssertEqual(try native.snapshot(), before)
        try browser.applyUpdate(XCTUnwrap(native.redo()))
        XCTAssertEqual(try native.proseProjection().blockRanges[2].length, 0)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary)
    }

    func testTrailingEmptyItemAndUnsupportedParentAreNonDestructive() throws {
        let fixture = try fixture(), native = RelayMarkNativeDocument()
        try native.applyUpdate(XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String))))
        let before = try native.encodeUpdate()
        XCTAssertThrowsError(try native.appendEmptyListItem(after: Data([255])))
        let foreign = RelayMarkNativeDocument()
        _ = try foreign.replaceProse(start: 0, end: 0, text: "Foreign")
        XCTAssertThrowsError(try native.appendEmptyListItem(after: foreign.anchor(path: [0], index: 0)))
        XCTAssertThrowsError(try native.appendEmptyListItem(after: native.anchor(path: [0, 0, 0], index: 0)))
        XCTAssertEqual(try native.encodeUpdate(), before)
        _ = try native.appendEmptyListItem(after: native.anchor(path: [0, 1, 0], index: 0))
        let projection = try native.proseProjection()
        XCTAssertEqual(projection.blockRanges.last?.length, 0)
        XCTAssertEqual(projection.blockPaths.last, [0, 2, 0])
        XCTAssertTrue(String(projection.text.characters).hasSuffix("\n"))
        let appended = try native.encodeUpdate()
        XCTAssertThrowsError(try native.appendEmptyListItem(after: native.anchor(path: [0, 2, 0], index: 0)))
        XCTAssertEqual(try native.encodeUpdate(), appended)
    }
}
