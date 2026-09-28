import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeRichReturnTests: XCTestCase {
    private func seed() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich-list-v3", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
    }

    func testRichListSplitPreservesAtomsFormattingFollowingBlocksAndPeerUndo() throws {
        for offset in [0, 3, 6, 13, 24] {
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument(), source = try seed()
            try native.applyUpdate(source)
            try peer.applyUpdate(source)
            let before = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
            let prose = try native.markdownV3ProseProjection()
            let range = try XCTUnwrap(prose.blockRanges.first)
            let priorText = String(prose.text.characters)
            let change = try RelayMarkNativeMarkdownV3Return.apply(document: native, blockPath: [0, 0, 0],
                utf16Offset: offset, expectedSnapshot: native.snapshot())
            try peer.applyUpdate(change.update)
            let after = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
            XCTAssertEqual(after, try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer))
            XCTAssertEqual(String(try native.markdownV3ProseProjection().text.characters),
                (priorText as NSString).replacingCharacters(in: NSRange(location: range.location + offset, length: 0), with: "\n"))
            XCTAssertEqual(Array(after.blocks[0].childBlocks[1].childBlocks.dropFirst()),
                           Array(before.blocks[0].childBlocks[0].childBlocks.dropFirst()))
            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), before)
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), before)
        }
    }

    func testHeadingBodyAndTableCellReturnUseTheSameCommandAndReplay() throws {
        for (path, offset) in [([0, 0, 1], 3), ([0, 0, 3, 1, 0, 0], 2)] {
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument(), source = try seed()
            try native.applyUpdate(source)
            try peer.applyUpdate(source)
            let before = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native)
            let prose = try native.markdownV3ProseProjection()
            let row = try XCTUnwrap(prose.blockPaths.firstIndex(of: path))
            let priorText = String(prose.text.characters)
            let change = try RelayMarkNativeMarkdownV3Return.apply(document: native, blockPath: path,
                utf16Offset: offset, expectedSnapshot: native.snapshot())
            try peer.applyUpdate(change.update)
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native),
                           try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer))
            XCTAssertEqual(String(try native.markdownV3ProseProjection().text.characters),
                (priorText as NSString).replacingCharacters(in: NSRange(location: prose.blockRanges[row].location + offset, length: 0), with: "\n"))
            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: native), before)
            XCTAssertEqual(try RelayMarkNativeMarkdownBlocksV3Projection.project(document: peer), before)
        }
    }
}
