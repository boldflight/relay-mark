import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeAttributeCommandTests: XCTestCase {
    func testAuthoredHeadingListCalloutAndTaskSettingsRetainText() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let source = "# Heading\n\n7. Entry\n\n@Callout(tone: \"info\", emphasis: \"soft\") {\nNested **rich** text\n}\n\n- [ ] Task"
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "attribute-command"))
        try peer.applyUpdate(seed)
        let beforeText = String(try document.richProseProjection().text.characters)
        let root = try JSONSerialization.jsonObject(with: document.snapshot()) as! [String: Any]
        let nodes = root["children"] as! [[String: Any]]
        let heading = nodes[0]["attributes"] as! [String: Any], callout = nodes[2]["attributes"] as! [String: Any]
        let task = ((nodes[3]["children"] as! [[String: Any]])[0]["attributes"] as! [String: Any])
        for kind in ["heading", "ordered", "callout", "task"] {
            let change: RelayMarkNativeRichEditing.Change
            switch kind {
            case "heading": change = try document.setRichHeadingLevel(anchor: document.anchor(path: [0], index: 0), expectedHeadingID: heading["headingId"] as? String, level: 3)
            case "ordered": change = try document.setRichOrderedListStart(anchor: document.anchor(path: [1], index: 0), expectedStart: 7, start: 10)
            case "callout": change = try document.setCalloutAppearance(anchor: document.anchor(path: [2], index: 0), expectedID: callout["relaymarkId"] as! String, expectedTone: "info", expectedEmphasis: "soft", tone: "warning", emphasis: "strong")
            default: change = try document.setRichTaskItemChecked(path: [3, 0], expectedID: task["relaymarkId"] as! String, expectedEntityID: nil, expectedChecked: false, checked: true)
            }
            try peer.applyUpdate(change.update)
            XCTAssertEqual(try peer.authoredDocument(), try document.authoredDocument())
            XCTAssertEqual(String(try document.richProseProjection().text.characters), beforeText)
        }
        let final = try JSONSerialization.jsonObject(with: document.snapshot()) as! [String: Any]
        let finalNodes = final["children"] as! [[String: Any]]
        XCTAssertEqual((finalNodes[0]["attributes"] as! [String: Any])["level"] as? Int, 3)
        XCTAssertEqual((finalNodes[1]["attributes"] as! [String: Any])["start"] as? Int, 10)
        XCTAssertEqual((finalNodes[2]["attributes"] as! [String: Any])["tone"] as? String, "warning")
        XCTAssertEqual(((finalNodes[3]["children"] as! [[String: Any]])[0]["attributes"] as! [String: Any])["checked"] as? Bool, true)
    }
    func testBlockStyleKeepsTextAndUndoesLocally() throws {
        for style in [RelayMarkNativeBlockStyle.heading(2), .quote, .bulletList, .orderedList, .taskList] {
            let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("**Kept🌍**", namespace: "block-style"))
            try peer.applyUpdate(seed)
            let before = try document.authoredDocument()
            let change: RelayMarkNativeRichEditing.Change = try document.setRichBlockStyle(at: 0, style: style, expectedSnapshot: document.snapshot())
            XCTAssertEqual(String(try document.richProseProjection().text.characters), "Kept🌍")
            try peer.applyUpdate(change.update)
            XCTAssertEqual(try document.authoredDocument(), try peer.authoredDocument())
            _ = try XCTUnwrap(document.undo())
            XCTAssertEqual(try document.authoredDocument(), before)
        }
    }

    func testCalloutTitleAndTaskInsertionLeaveNeighborsUnchanged() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("Before\n\n@Callout(tone: \"info\", emphasis: \"soft\") {\n- Nested **body**\n}", namespace: "title-insertion"))
        try peer.applyUpdate(seed)
        let before = try JSONSerialization.jsonObject(with: document.authoredDocument()) as! [String: Any]
        let nodes = (try JSONSerialization.jsonObject(with: document.snapshot()) as! [String: Any])["children"] as! [[String: Any]]
        let calloutID = (nodes[1]["attributes"] as! [String: Any])["relaymarkId"] as! String
        let title = try document.addCalloutTitle(anchor: document.anchor(path: [1], index: 0), expectedID: calloutID, expectedSnapshot: document.snapshot())
        try peer.applyUpdate(title.change.update)
        let task = try document.insertEmptyRichTaskList(after: document.anchor(path: [0], index: 0), expectedSnapshot: document.snapshot())
        try peer.applyUpdate(task.change.update)
        XCTAssertEqual(try peer.authoredDocument(), try document.authoredDocument())
        let after = try JSONSerialization.jsonObject(with: document.authoredDocument()) as! [String: Any]
        XCTAssertEqual(NSDictionary(dictionary: (after["blocks"] as! [[String: Any]])[0]), NSDictionary(dictionary: (before["blocks"] as! [[String: Any]])[0]))
    }

    func testLinkedTaskOccurrencesToggleTogetherAndUndoKeepsPeerText() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        var ast = try JSONSerialization.jsonObject(with: RelayMarkSourceCodec.parseDocument("- [ ] First **🌍**\n- [ ] Unlinked\n\n> - [ ] Second Ω", namespace: "linked-batch")) as! [String: Any]
        let entityID = "11111111-1111-4111-8111-111111111111"
        var blocks = ast["blocks"] as! [[String: Any]]
        var topItems = blocks[0]["content"] as! [[String: Any]]
        topItems[0]["props"] = ["checked": false, "entityId": entityID]
        blocks[0]["content"] = topItems
        var quote = blocks[1]["content"] as! [[String: Any]]
        var nestedItems = quote[0]["content"] as! [[String: Any]]
        nestedItems[0]["props"] = ["checked": false, "entityId": entityID]
        quote[0]["content"] = nestedItems; blocks[1]["content"] = quote; ast["blocks"] = blocks
        let seed = try document.initializeDocument(authoredAST: JSONSerialization.data(withJSONObject: ast))
        try peer.applyUpdate(seed)
        let items = try document.richProseProjection().taskItems.filter { $0.entityID == entityID }
        let original = try document.encodeUpdate()
        let targets = items.map { RelayMarkNativeDocument.TaskItemCheckTarget(path: $0.path, expectedID: $0.id, expectedEntityID: $0.entityID, expectedChecked: $0.checked) }
        XCTAssertThrowsError(try document.setRichTaskItemsChecked(items: [targets[0]], checked: true, expectedSnapshot: document.snapshot()))
        XCTAssertThrowsError(try document.setRichTaskItemsChecked(items: [targets[0], targets[0]], checked: true, expectedSnapshot: document.snapshot()))
        let stale = RelayMarkNativeDocument.TaskItemCheckTarget(path: targets[1].path, expectedID: targets[1].expectedID, expectedEntityID: entityID, expectedChecked: true)
        XCTAssertThrowsError(try document.setRichTaskItemsChecked(items: [targets[0], stale], checked: true, expectedSnapshot: document.snapshot()))
        XCTAssertEqual(try document.encodeUpdate(), original)
        let actual = try document.editorCommand(separateUndoItem: true) {
            try document.setRichTaskItemsChecked(items: targets, checked: true, expectedSnapshot: document.snapshot())
        }
        XCTAssertEqual(try document.richProseProjection().taskItems.filter { $0.entityID == entityID }.map(\.checked), [true, true])
        try peer.applyUpdate(actual.update)
        XCTAssertEqual(try document.authoredDocument(), try peer.authoredDocument())
        let peerText = try RelayMarkNativeRichEditing.replace(document: peer, range: NSRange(location: 0, length: 0), runs: [("Peer ", [:])], expectedSnapshot: peer.snapshot())
        try document.applyUpdate(peerText.update)
        _ = try XCTUnwrap(document.undo())
        XCTAssertEqual(try document.richProseProjection().taskItems.filter { $0.entityID == entityID }.map(\.checked), [false, false])
        XCTAssertTrue(String(try document.richProseProjection().text.characters).contains("Peer First 🌍"))
        _ = try XCTUnwrap(document.redo())
        XCTAssertEqual(try document.richProseProjection().taskItems.filter { $0.entityID == entityID }.map(\.checked), [true, true])
        XCTAssertFalse(try document.richProseProjection().taskItems.first(where: { $0.entityID == nil })!.checked)
        XCTAssertTrue(String(try document.richProseProjection().text.characters).contains("Peer First 🌍"))
    }

}
