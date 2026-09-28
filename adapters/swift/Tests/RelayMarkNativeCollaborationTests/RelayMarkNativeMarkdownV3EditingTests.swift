import Foundation
import XCTest
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeMarkdownV3EditingTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "native-replace-v3", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
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
            if var attributes = object["attributes"] as? [String: Any], object["kind"] as? String == "element" {
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

    func testEmbeddedSchemaIsTheBrowserSchema() throws {
        let exported = try XCTUnwrap(fixture()["schema"])
        let embedded = try JSONSerialization.jsonObject(with: Data(RelayMarkNativeProseMirrorSchemaV3.json.utf8))
        XCTAssertEqual(try canonical(embedded), try canonical(exported))
        XCTAssertNoThrow(try PMYXmlBridge.v3())
    }

    /// Every case is replayed against actual ProseMirror output through the
    /// browser schema: same XML, same retained IDs, same caret, peer replay
    /// and exact undo.
    func testCrossContainerReplacementMatchesProseMirror() throws {
        let fixture = try fixture()
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String)))
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 89)
        var failures: [String] = []
        for (number, entry) in cases.enumerated() {
            let action = try XCTUnwrap(entry["action"] as? String)
            let from = try XCTUnwrap(entry["from"] as? [String: Any]), to = try XCTUnwrap(entry["to"] as? [String: Any])
            let label = "#\(number) \(action) \(from["id"]!)@\(from["offset"]!)→\(to["id"]!)@\(to["offset"]!)"
            let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try native.applyUpdate(seed)
            try peer.applyUpdate(seed)
            let before = try native.snapshot(), beforeTree = try tree(native)
            let prose = try native.markdownV3ProseProjection()
            func location(_ endpoint: [String: Any]) throws -> Int {
                let blockPath = try XCTUnwrap(path(of: try XCTUnwrap(endpoint["id"] as? String), in: beforeTree))
                let block = try XCTUnwrap(prose.blockPaths.firstIndex(of: blockPath))
                return prose.blockRanges[block].location + (try XCTUnwrap(endpoint["offset"] as? Int))
            }
            let start = try location(from), end = try location(to)
            let runs: [(text: String, attributes: [String: Any])] = action == "delete" ? []
                : action == "insertText" ? [("X", [:])] : [("P1\nP2", [:])]
            let unchanged = (entry["update"] as? String).map { $0.count < 8 } ?? true
            let change: RelayMarkNativeMarkdownV3Editing.Change
            do {
                if action == "Backspace" || action == "Delete" {
                    let keyed = try RelayMarkNativeMarkdownV3Editing.key(action == "Backspace" ? .backspace : .delete,
                        document: native, at: start, expectedSnapshot: before)
                    if unchanged {
                        if keyed != nil { failures.append("\(label): changed where the browser did not") }
                        if try native.snapshot() != before { failures.append("\(label): document changed") }
                        continue
                    }
                    guard let keyed else { failures.append("\(label): no change"); continue }
                    change = keyed
                } else {
                    change = try RelayMarkNativeMarkdownV3Editing.replace(document: native,
                        range: NSRange(location: start, length: end - start), runs: runs,
                        inheritMarks: action == "insertText", expectedSnapshot: before)
                }
            } catch {
                failures.append("\(label): threw \(error)")
                continue
            }
            let after = try tree(native), expected = try XCTUnwrap(entry["after_xml"] as? [String: Any])
            guard try canonical(after) == canonical(expected) else {
                failures.append("\(label): XML differs\n native \(try canonical(after))\n browser \(try canonical(expected))")
                continue
            }
            let original = Set(ids(beforeTree)), nativeIDs = ids(after)
            if Set(nativeIDs).count != nativeIDs.count { failures.append("\(label): duplicate IDs") }
            if Set(nativeIDs).intersection(original) != Set(ids(expected)).intersection(original) {
                failures.append("\(label): retained IDs differ")
            }
            let selection = try XCTUnwrap(entry["selection_after"] as? [String: Any])
            if let id = selection["id"] as? String, let expectedPath = path(of: id, in: expected) {
                if change.caret != .init(blockPath: expectedPath, offset: try XCTUnwrap(selection["offset"] as? Int)) {
                    failures.append("\(label): caret \(String(describing: change.caret)) expected \(expectedPath)@\(selection["offset"]!)")
                }
            }
            try peer.applyUpdate(change.update)
            if try native.snapshot() != peer.snapshot() { failures.append("\(label): peer differs") }
            try peer.applyUpdate(try XCTUnwrap(native.undo()))
            if try native.snapshot() != before || peer.snapshot() != before { failures.append("\(label): undo differs") }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of \(cases.count) cases failed:\n" + failures.joined(separator: "\n"))
    }
}
