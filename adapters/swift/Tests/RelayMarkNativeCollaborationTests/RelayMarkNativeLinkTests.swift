import Foundation
import XCTest
import RelayMarkCollaboration
import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeLinkTests: XCTestCase {
    func testActualBrowserLinksMatchNativeMarksWithoutMovingText() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "links-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for item in try XCTUnwrap(fixture["cases"] as? [[String: Any]]) {
            let doc = RelayMarkNativeDocument(), browser = RelayMarkNativeDocument()
            let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(item["seed"] as? String)))
            try doc.applyUpdate(seed); try browser.applyUpdate(seed)
            let before = try doc.snapshot(), projection = try doc.proseProjection()
            let range = try XCTUnwrap(projection.blockRanges.first)
            let path = try XCTUnwrap(projection.textRanges(in: range).first).path
            let anchor = try doc.anchor(path: path, index: 10)
            var expected = try XCTUnwrap(item["snapshot"] as? [String: Any])
            for index in path { expected = try XCTUnwrap((expected["children"] as? [[String: Any]])?[index]) }
            let run = try XCTUnwrap((expected["delta"] as? [[String: Any]])?.first)
            let marks = try XCTUnwrap(run["attributes"] as? [String: Any])
            let link = try XCTUnwrap(marks["link"] as? [String: Any])
            XCTAssertNil(link["title"])
            try browser.applyUpdate(doc.formatProse(start: 0, end: range.length, attributes: ["link": link]))
            XCTAssertEqual(try JSONSerialization.jsonObject(with: doc.snapshot()) as? NSDictionary, item["snapshot"] as? NSDictionary)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary, item["snapshot"] as? NSDictionary)
            XCTAssertEqual(try doc.resolve(anchor: anchor)?.path, path)
            XCTAssertEqual(try doc.resolve(anchor: anchor)?.index, 10)
            _ = try doc.formatProse(start: 0, end: range.length, attributes: ["link": NSNull()])
            XCTAssertEqual(try doc.snapshot(), before)
            _ = try doc.undo()
            XCTAssertEqual(try JSONSerialization.jsonObject(with: doc.snapshot()) as? NSDictionary, item["snapshot"] as? NSDictionary)
            let unchanged = try doc.encodeUpdate()
            var unsupported = link; unsupported["title"] = "Preserve unknown metadata"
            XCTAssertThrowsError(try doc.formatProse(start: 0, end: range.length, attributes: ["link": unsupported]))
            XCTAssertEqual(try doc.encodeUpdate(), unchanged)
        }
    }
}
