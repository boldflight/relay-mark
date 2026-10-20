import XCTest
@testable import RelayMarkModel

/// Upstream prosemirror-transform tests for fixes carried by the Swift port.
final class PMTransformUpstreamTests: XCTestCase {
    // prosemirror-transform 1.12.1 test-trans.ts "won't try to open a leaf node".
    func testReplaceDoesNotOpenLeafNode() throws {
        let schema = try PMSchema(json: [
            "top": "doc",
            "nodes": [
                ["name": "doc", "content": "block"],
                ["name": "paragraph", "content": "inline*", "group": "block"],
                ["name": "text", "group": "inline"],
            ],
            "marks": [[String: Any]](),
        ])
        let paragraph = try XCTUnwrap(schema.nodes["paragraph"])
        let doc = try schema.topNodeType.create(nil, PMFragment.from(try paragraph.create()))
        var transform = PMTransform(doc)
        let slice = PMSlice(PMFragment.fromArray([try paragraph.create(), schema.text(Array("xy".utf16))]),
                            openStart: 0, openEnd: 0)
        try transform.replace(1, 1, slice)
        XCTAssertTrue(transform.doc.eq(doc))
    }
}
