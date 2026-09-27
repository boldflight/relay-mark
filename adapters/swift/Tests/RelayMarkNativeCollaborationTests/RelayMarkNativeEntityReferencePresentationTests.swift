import Foundation
import XCTest
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeEntityReferencePresentationTests: XCTestCase {
    func testBlockReferenceIsAnInertOneUnitNativeAtomBesideEditableProse() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "entity-reference-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        let before = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: document)
        let prose = try document.markdownV3ProseProjection()
        XCTAssertTrue(prose.isEditable)
        let atom = try XCTUnwrap(prose.entityReferenceAtoms.first)
        XCTAssertEqual(prose.entityReferenceAtoms.count, 1)
        XCTAssertEqual(atom.entityID, "9f815b37-67b3-4101-868c-5335351feb6a")
        XCTAssertEqual(atom.label, "Ada Lovelace")
        XCTAssertEqual(atom.path, [1])
        XCTAssertEqual((String(prose.text.characters) as NSString).substring(with: atom.range), "\u{FFFC}")
        let peer = RelayMarkNativeDocument()
        try peer.applyUpdate(seed)
        let update = try RelayMarkNativeMarkdownV3TextMutation.replace(
            document: document, path: [0, 0], start: 6, end: 6, text: "!")
        try peer.applyUpdate(update)
        let after = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: document)
        XCTAssertEqual(after, try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer))
        XCTAssertEqual(after.blocks[1], before.blocks[1])
    }
}
