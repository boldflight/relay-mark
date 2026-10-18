import Foundation
import XCTest
import RelayMarkCollaboration
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeTableProbeTests: XCTestCase {
    func testCommunityTablesPreserveXMLAndRejectLossyProseEditing() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "table-experimental", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        var results: [String: String] = [:]
        for item in cases {
            let name = try XCTUnwrap(item["name"] as? String)
            let update = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(item["update"] as? String)))
            let native = RelayMarkNativeDocument()
            try native.applyUpdate(update)
            try native.applyUpdate(update) // Duplicate delivery must preserve spans and widths.
            XCTAssertTrue(native.integrationStatus().isComplete, name)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                           item["snapshot"] as? NSDictionary, name)
            XCTAssertFalse(native.supportsOrdinaryProseEditing(), name)
            XCTAssertFalse(native.supportsBasicMarkdownEditing(), name)
            XCTAssertFalse(try native.proseProjection().isEditable, name)
            let before = try native.encodeUpdate()
            XCTAssertThrowsError(try native.replaceBasicMarkdownProse(start: 0, end: 0, text: "must not flatten"))
            XCTAssertEqual(try native.encodeUpdate(), before, name)
            let reference = RelayMarkNativeDocument()
            try reference.applyUpdate(before)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: reference.snapshot()) as? NSDictionary,
                           item["snapshot"] as? NSDictionary, name)
            results[name] = before.base64EncodedString()
            // Low-level Yrs text edits are interoperable even though no native
            // table authoring surface or Markdown admission is enabled.
            let path = [0, 0, 0, 0, 0]
            let anchor = try native.anchor(path: path, index: 1)
            let cellEdit = try native.insertText("✓", at: 0, path: path)
            try reference.applyUpdate(cellEdit)
            XCTAssertEqual(try native.resolve(anchor: anchor)?.index, 2, name)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: reference.snapshot()) as? NSDictionary,
                           try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary, name)
            let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])
            let tables = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
            let rows = try XCTUnwrap(tables[0]["children"] as? [[String: Any]])
            let cells = try XCTUnwrap(rows[0]["children"] as? [[String: Any]])
            let expectedTables = try XCTUnwrap((item["snapshot"] as? [String: Any])?["children"] as? [[String: Any]])
            let expectedRows = try XCTUnwrap(expectedTables[0]["children"] as? [[String: Any]])
            let expectedCells = try XCTUnwrap(expectedRows[0]["children"] as? [[String: Any]])
            XCTAssertEqual(cells[0]["attributes"] as? NSDictionary, expectedCells[0]["attributes"] as? NSDictionary, name)
        }
        if let path = ProcessInfo.processInfo.environment["RELAY_TABLE_NATIVE_OUTPUT"] {
            try JSONEncoder().encode(results).write(to: URL(filePath: path))
        }
    }
}
