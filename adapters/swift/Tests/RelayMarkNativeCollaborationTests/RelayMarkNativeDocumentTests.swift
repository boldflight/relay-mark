import Foundation
import XCTest
import RelayMarkCollaboration
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeDocumentTests: XCTestCase {
    func testCommunityFlatTaskUpdateKeepsIDsAndConvergesAfterNativeEdits() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "task-list-flat-v3-draft", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"] as? String)))
        let native = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        try native.applyUpdate(seed)
        try peer.applyUpdate(seed)
        let initial = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertThrowsError(try native.taskItems())
        let items = try native.taskItems(rich: true)
        XCTAssertEqual(items.map(\.paragraphs), [["Done today"], ["Next"]])
        XCTAssertEqual(items[0].entityID, fixture["linked_entity_id"] as? String)
        let toggle = try native.setTaskItemChecked(anchor: items[1].anchor,
            expectedEntityID: nil, checked: true, rich: true)
        try peer.applyUpdate(toggle)
        let text = try native.replaceTaskItemText(anchor: items[0].anchor,
            expectedEntityID: items[0].entityID, start: 4, end: 4, text: " again",
            rich: true)
        try peer.applyUpdate(text)
        let changed = try RelayMarkNativeDocumentProjection.project(document: native)
        XCTAssertEqual(changed, try RelayMarkNativeDocumentProjection.project(document: peer))
        XCTAssertEqual(changed.blocks[0].id, initial.blocks[0].id)
        XCTAssertEqual(changed.blocks[0].childBlocks.map(\.id), initial.blocks[0].childBlocks.map(\.id))
        XCTAssertEqual(try native.taskItems(rich: true)[0].paragraphs, ["Done again today"])
        XCTAssertThrowsError(try native.setTaskItemChecked(anchor: items[0].anchor,
            expectedEntityID: nil, checked: false, rich: true))
    }

    func testRealBrowserTaskListFixtureNativeReadToggleAndTextConverge() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "task-list-experimental", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"])))
        let native = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        try native.applyUpdate(seed)
        try browser.applyUpdate(seed)
        XCTAssertFalse(native.supportsOrdinaryProseEditing())
        let items = try native.taskItems()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].entityID, fixture["linkedEntityId"])
        XCTAssertEqual(items[0].checked, true)
        XCTAssertEqual(items[0].paragraphs, [fixture["linkedText"]])
        XCTAssertEqual(items[1].entityID, nil)
        XCTAssertEqual(items[1].checked, false)
        XCTAssertEqual(items[1].paragraphs, [fixture["unlinkedText"]])
        XCTAssertEqual(items[1].anchor, try browser.anchor(path: [0, 1], index: 0))

        let toggle = try native.setTaskItemChecked(anchor: items[0].anchor,
                                                    expectedEntityID: items[0].entityID, checked: false)
        try browser.applyUpdate(toggle)
        let text = try native.replaceTaskItemText(anchor: items[0].anchor,
                                                   expectedEntityID: items[0].entityID,
                                                   start: 0, end: 4, text: "Done today")
        try browser.applyUpdate(text)
        XCTAssertEqual(try native.taskItems()[0].entityID, fixture["linkedEntityId"])
        XCTAssertEqual(try native.taskItems()[0].paragraphs, ["Done today"])
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary)
        let before = try native.encodeUpdate()
        XCTAssertThrowsError(try native.setTaskItemChecked(anchor: items[0].anchor,
                                                             expectedEntityID: nil, checked: true))
        XCTAssertEqual(try native.encodeUpdate(), before)
    }

    func testUnlinkedTaskAnchorSurvivesSiblingInsertionAndFailsAfterDeletion() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "task-list-experimental", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String])
        let seed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["update"])))
        let native = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        try native.applyUpdate(seed)
        try browser.applyUpdate(seed)
        let unlinked = try native.taskItems()[1]
        let insertion = try browser.edit(Data(#"{"kind":"insertNodes","path":[0],"index":1,"nodes":[{"kind":"element","name":"taskItem","attributes":{"checked":false},"children":[{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"Inserted"}]}]}]}]}"#.utf8))
        for update in insertion { try native.applyUpdate(update) }
        XCTAssertEqual(try native.taskItems().map { $0.paragraphs[0] }, ["Done", "Inserted", "Next"])
        let toggle = try native.setTaskItemChecked(anchor: unlinked.anchor, expectedEntityID: nil, checked: true)
        try browser.applyUpdate(toggle)
        XCTAssertEqual(try native.taskItems().map(\.checked), [true, false, true])
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary)

        let deletion = try browser.edit(Data(#"{"kind":"deleteNodes","path":[0],"index":2,"length":1}"#.utf8))
        for update in deletion { try native.applyUpdate(update) }
        let before = try native.encodeUpdate()
        XCTAssertThrowsError(try native.setTaskItemChecked(anchor: unlinked.anchor,
                                                             expectedEntityID: nil, checked: false))
        XCTAssertEqual(try native.encodeUpdate(), before)
    }

    func testTaskListRejectsUnsupportedMetadataWithoutMutatingReplica() throws {
        let browser = try RelayMarkCollaborationDocument()
        _ = try browser.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"taskList","children":[{"kind":"element","name":"taskItem","attributes":{"checked":true,"lastText":"shadow"},"children":[{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"No"}]}]}]}]}]}"#.utf8))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(browser.encodeUpdate())
        let before = try native.encodeUpdate()
        XCTAssertThrowsError(try native.taskItems())
        XCTAssertEqual(try native.encodeUpdate(), before)
    }

    func testBasicMarkdownHeadingEditPreservesTagAndHeadingID() throws {
        let browser = try RelayMarkCollaborationDocument()
        _ = try browser.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"heading","attributes":{"level":2,"headingId":"agenda"},"children":[{"kind":"text","delta":[{"insert":"Agenda"}]}]},{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"Notes"}]}]}]}"#.utf8))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(browser.encodeUpdate())
        XCTAssertTrue(native.supportsBasicMarkdownEditing())
        XCTAssertFalse(native.supportsOrdinaryProseEditing())
        let anchor = try native.anchor(path: [0, 0], index: 4)
        let edit = try native.replaceBasicMarkdownProse(start: 0, end: 6, text: "Plan")
        try browser.applyUpdate(edit)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary)
        XCTAssertEqual(String(try native.proseProjection().text.characters), "Plan\nNotes")
        XCTAssertEqual(try native.resolve(anchor: anchor)?.path, [0, 0])
        let blocks = try XCTUnwrap((JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])?["children"] as? [[String: Any]])
        XCTAssertEqual(blocks[0]["name"] as? String, "heading")
        XCTAssertEqual((blocks[0]["attributes"] as? [String: Any])?["headingId"] as? String, "agenda")
        XCTAssertEqual((blocks[0]["attributes"] as? [String: Any])?["level"] as? Int, 2)
        let before = try native.encodeUpdate()
        XCTAssertThrowsError(try native.replaceBasicMarkdownProse(start: 2, end: 7, text: "flatten"))
        XCTAssertEqual(try native.encodeUpdate(), before)
    }

    func testBasicMarkdownEmptyHeadingAcceptsFirstTextWithoutReplacingElement() throws {
        let browser = try RelayMarkCollaborationDocument()
        _ = try browser.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"heading","attributes":{"level":1,"headingId":"empty"},"children":[]}]}"#.utf8))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(browser.encodeUpdate())
        XCTAssertTrue(native.supportsBasicMarkdownEditing())
        try browser.applyUpdate(native.replaceBasicMarkdownProse(start: 0, end: 0, text: "Title"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary)
        XCTAssertEqual(String(try native.proseProjection().text.characters), "Title")
    }

    func testBasicMarkdownHardBreakEditPreservesSurroundingTextAndBrowserParity() throws {
        let browser = try RelayMarkCollaborationDocument()
        _ = try browser.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"heading","attributes":{"level":3,"headingId":"two-lines"},"children":[{"kind":"text","delta":[{"insert":"One"}]},{"kind":"element","name":"hardBreak","children":[]},{"kind":"text","delta":[{"insert":"Two"}]}]}]}"#.utf8))
        let native = RelayMarkNativeDocument()
        try native.applyUpdate(browser.encodeUpdate())
        XCTAssertTrue(native.supportsBasicMarkdownEditing())
        XCTAssertEqual(String(try native.proseProjection().text.characters), "One\u{2028}Two")
        let otherLeafAnchor = try native.anchor(path: [0, 2], index: 2)

        let edit = try native.replaceBasicMarkdownProse(start: 4, end: 7, text: "Three")
        try browser.applyUpdate(edit)
        XCTAssertEqual(try native.resolve(anchor: otherLeafAnchor)?.path, [0, 2])
        XCTAssertEqual(String(try native.proseProjection().text.characters), "One\u{2028}Three")
        let insertion = try native.replaceBasicMarkdownProse(start: 6, end: 6, text: "\u{2028}")
        try browser.applyUpdate(insertion)
        XCTAssertEqual(String(try native.proseProjection().text.characters), "One\u{2028}Th\u{2028}ree")
        let deletion = try native.replaceBasicMarkdownProse(start: 3, end: 4, text: "")
        try browser.applyUpdate(deletion)
        XCTAssertEqual(String(try native.proseProjection().text.characters), "OneTh\u{2028}ree")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary)
        let blocks = try XCTUnwrap((JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])?["children"] as? [[String: Any]])
        XCTAssertEqual((blocks[0]["attributes"] as? [String: Any])?["headingId"] as? String, "two-lines")
        let undo = try XCTUnwrap(native.undo())
        try browser.applyUpdate(undo)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary)
    }

    func testProseFormattingIsOnePortableMarkOnlyTransactionAcrossParagraphs() throws {
        let native = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        let seed = try native.replaceProse(start: 0, end: 0, text: "Hello\nWorld")
        try browser.applyUpdate(seed)
        let beforeText = String(try native.proseProjection().text.characters)
        let anchor = try native.anchor(path: [1, 0], index: 2)

        let mark = try native.formatProse(start: 3, end: 8, attributes: ["bold": [:]])
        try browser.applyUpdate(mark)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary)
        XCTAssertEqual(String(try native.proseProjection().text.characters), beforeText)
        XCTAssertEqual(try native.resolve(anchor: anchor)?.path, [1, 0])
        XCTAssertEqual(try native.resolve(anchor: anchor)?.index, 2)
        let blocks = try XCTUnwrap((JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])?["children"] as? [[String: Any]])
        for block in blocks {
            let children = try XCTUnwrap(block["children"] as? [[String: Any]])
            let runs = try XCTUnwrap(children[0]["delta"] as? [[String: Any]])
            XCTAssertTrue(runs.contains { ($0["attributes"] as? [String: Any])?["bold"] != nil })
        }

        let remote = try browser.edit(Data(#"{"kind":"insertText","path":[1,0],"index":5,"text":"!"}"#.utf8))
        for update in remote { try native.applyUpdate(update) }
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary)
        let undo = try XCTUnwrap(native.undo())
        try browser.applyUpdate(undo)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary)
        XCTAssertEqual(String(try native.proseProjection().text.characters), "Hello\nWorld!")
        let after = try XCTUnwrap((JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])?["children"] as? [[String: Any]])
        for block in after {
            let children = try XCTUnwrap(block["children"] as? [[String: Any]])
            let runs = try XCTUnwrap(children[0]["delta"] as? [[String: Any]])
            XCTAssertFalse(runs.contains { ($0["attributes"] as? [String: Any])?["bold"] != nil })
        }
    }

    func testProseFormattingRejectsInvalidRangeWithoutMutation() throws {
        let document = RelayMarkNativeDocument()
        _ = try document.replaceProse(start: 0, end: 0, text: "A😀\nB")
        let before = try document.encodeUpdate()
        XCTAssertThrowsError(try document.formatProse(start: 2, end: 3, attributes: ["italic": [:]]))
        XCTAssertThrowsError(try document.formatProse(start: 3, end: 4, attributes: ["italic": [:]]))
        XCTAssertThrowsError(try document.formatProse(start: 0, end: 1, attributes: ["unknown": [:]]))
        XCTAssertEqual(try document.encodeUpdate(), before)
    }

    func testProseFormattingCanClearOneMarkWithoutRemovingAnother() throws {
        let native = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        try browser.applyUpdate(native.replaceProse(start: 0, end: 0, text: "Marked"))
        try browser.applyUpdate(native.formatProse(start: 0, end: 6,
                                                    attributes: ["bold": [:], "italic": [:]]))
        try browser.applyUpdate(native.formatProse(start: 1, end: 5, attributes: ["bold": NSNull()]))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary)
        let blocks = try XCTUnwrap((JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])?["children"] as? [[String: Any]])
        let children = try XCTUnwrap(blocks[0]["children"] as? [[String: Any]])
        let runs = try XCTUnwrap(children[0]["delta"] as? [[String: Any]])
        XCTAssertEqual(runs.map { $0["insert"] as? String }, ["M", "arke", "d"])
        XCTAssertNil((runs[1]["attributes"] as? [String: Any])?["bold"])
        XCTAssertNotNil((runs[1]["attributes"] as? [String: Any])?["italic"])
    }

    func testProseFormattingSupportsPortableStrikeLinkAndExclusiveCode() throws {
        let native = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        try browser.applyUpdate(native.replaceProse(start: 0, end: 0, text: "Alpha"))
        try browser.applyUpdate(native.formatProse(start: 0, end: 5, attributes: ["strike": [:]]))
        try browser.applyUpdate(native.formatProse(start: 0, end: 5,
                                                    attributes: ["link": ["href": "relay:entity/123"]]))
        let before = try native.encodeUpdate()
        XCTAssertThrowsError(try native.formatProse(start: 0, end: 5, attributes: ["code": [:]]))
        XCTAssertThrowsError(try native.formatProse(start: 0, end: 5,
                                                    attributes: ["link": ["href": "bad\nurl"]]))
        XCTAssertEqual(try native.encodeUpdate(), before)
        try browser.applyUpdate(native.formatProse(start: 0, end: 5,
                                                    attributes: ["code": [:], "strike": NSNull(),
                                                                 "link": NSNull()]))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: native.snapshot()) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: browser.snapshot()) as? NSDictionary)
        let blocks = try XCTUnwrap((JSONSerialization.jsonObject(with: native.snapshot()) as? [String: Any])?["children"] as? [[String: Any]])
        let children = try XCTUnwrap(blocks[0]["children"] as? [[String: Any]])
        let runs = try XCTUnwrap(children[0]["delta"] as? [[String: Any]])
        let marks = try XCTUnwrap(runs[0]["attributes"] as? [String: Any])
        XCTAssertNotNil(marks["code"])
        XCTAssertNil(marks["strike"])
        XCTAssertNil(marks["link"])
        XCTAssertTrue(try native.proseProjection().isEditable)
    }

    func testAwarenessInteroperatesWithJavaScriptYjsAndStaysEphemeral() throws {
        let native = RelayMarkNativeDocument()
        let browser = try RelayMarkCollaborationDocument()
        let seed = try native.replaceProse(start: 0, end: 0, text: "Hello")
        try browser.applyUpdate(seed)
        let documentBefore = try native.encodeUpdate()
        let nativeAnchor = try native.anchor(path: [0, 0], index: 2)

        let nativePresence = try native.presence.setPresence(name: "Native", anchor: nativeAnchor, head: nativeAnchor,
                                                             userID: "native-user-123")
        try browser.applyPresence(nativePresence, origin: "native-channel")
        let browserView = try XCTUnwrap(browser.collaborators().first)
        XCTAssertEqual(browserView.name, "Native")
        XCTAssertEqual(browserView.userID, "native-user-123")
        XCTAssertEqual(browserView.anchor, nativeAnchor)
        let browserSnapshot = try browser.presenceSnapshot()
        let nativeMirror = RelayMarkNativeDocument()
        try nativeMirror.presence.apply(snapshot: .init(update: browserSnapshot.update, origins: browserSnapshot.origins))
        XCTAssertEqual(try nativeMirror.presence.collaborators().first?.name, "Native")
        XCTAssertEqual(try nativeMirror.presence.collaborators().first?.userID, "native-user-123")

        let browserAnchor = try browser.anchor(path: [0, 0], index: 3)
        for bytes in try browser.setPresence(name: "Browser", anchor: browserAnchor, head: browserAnchor,
                                             userID: "browser-user-456") {
            try native.presence.applyPresence(bytes, origin: "browser-channel")
        }
        let nativeView = try XCTUnwrap(native.presence.collaborators().first)
        XCTAssertEqual(nativeView.name, "Browser")
        XCTAssertEqual(nativeView.userID, "browser-user-456")
        XCTAssertEqual(nativeView.anchor, browserAnchor)

        let mounted = RelayMarkNativeDocument()
        try mounted.applyUpdate(documentBefore)
        try mounted.presence.apply(snapshot: native.presence.snapshot())
        XCTAssertEqual(try mounted.presence.collaborators().first?.name, "Browser")
        XCTAssertEqual(try mounted.presence.collaborators().first?.userID, "browser-user-456")
        let invalid = RelayMarkNativePresence.Snapshot(update: try native.presence.snapshot().update,
                                                       origins: ["browser-channel": [native.presence.clientID]])
        XCTAssertThrowsError(try mounted.presence.apply(snapshot: invalid))
        try native.presence.removePresence(origin: "browser-channel")
        XCTAssertTrue(try native.presence.collaborators().isEmpty)
        try browser.applyPresence(native.presence.setPresence(name: nil), origin: "native-channel")
        XCTAssertTrue(try browser.collaborators().isEmpty)
        XCTAssertEqual(try native.encodeUpdate(), documentBefore)
    }

    func testRemoteAwarenessExpiresWithoutChangingDocument() throws {
        let sender = RelayMarkNativeDocument()
        let receiver = RelayMarkNativeDocument()
        let before = try receiver.encodeUpdate()
        try receiver.presence.applyPresence(sender.presence.setPresence(name: "Gone"), origin: "socket")
        XCTAssertEqual(try receiver.presence.collaborators().count, 1)
        XCTAssertTrue(try receiver.presence.advancePresenceClock(nowMillis: .max).isEmpty)
        XCTAssertTrue(try receiver.presence.collaborators().isEmpty)
        XCTAssertEqual(try receiver.encodeUpdate(), before)
    }

    func testAtomicParagraphSplitJoinAndFormattedSuffixConverge() throws {
        let local = RelayMarkNativeDocument()
        let peer = RelayMarkNativeDocument()
        XCTAssertTrue(local.supportsOrdinaryProseEditing())
        let seed = try local.replaceProse(start: 0, end: 0, text: "Hello World")
        try peer.applyUpdate(seed)
        let mark = try local.formatText(at: 6, length: 5, attributes: ["bold": [:]], path: [0, 0])
        try peer.applyUpdate(mark)

        let split = try local.replaceProse(start: 6, end: 6, text: "\nNew ")
        try peer.applyUpdate(split)
        XCTAssertEqual(String(try local.proseProjection().text.characters), "Hello \nNew World")
        XCTAssertEqual(try local.snapshot(), try peer.snapshot())
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: local.snapshot()) as? [String: Any])
        let blocks = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
        let secondChildren = try XCTUnwrap(blocks[1]["children"] as? [[String: Any]])
        let runs = try XCTUnwrap(secondChildren[0]["delta"] as? [[String: Any]])
        XCTAssertEqual(runs.last?["insert"] as? String, "World")
        XCTAssertNotNil((runs.last?["attributes"] as? [String: Any])?["bold"])

        let join = try local.replaceProse(start: 6, end: 11, text: "")
        try peer.applyUpdate(join)
        XCTAssertEqual(String(try local.proseProjection().text.characters), "Hello World")
        XCTAssertEqual(try local.snapshot(), try peer.snapshot())
        let undo = try XCTUnwrap(local.undo())
        try peer.applyUpdate(undo)
        XCTAssertEqual(try local.snapshot(), try peer.snapshot())
    }

    func testCrossParagraphReplacementAndInvalidEditAreAtomic() throws {
        let local = RelayMarkNativeDocument()
        let peer = RelayMarkNativeDocument()
        let seed = try local.replaceProse(start: 0, end: 0, text: "A😀B\nSecond\nThird")
        try peer.applyUpdate(seed)
        let before = try local.snapshot()
        XCTAssertThrowsError(try local.replaceProse(start: 2, end: 3, text: "broken"))
        XCTAssertThrowsError(try local.replaceProse(start: 1, end: 1, text: "\r"))
        XCTAssertEqual(try local.snapshot(), before)

        let update = try local.replaceProse(start: 1, end: 13, text: "X\nY")
        try peer.applyUpdate(update)
        XCTAssertEqual(String(try local.proseProjection().text.characters), "AX\nYhird")
        XCTAssertEqual(try local.snapshot(), try peer.snapshot())
    }

    func testConcurrentParagraphSplitAndIndependentPeerEditConverge() throws {
        let local = RelayMarkNativeDocument()
        let peer = RelayMarkNativeDocument()
        let seed = try local.replaceProse(start: 0, end: 0, text: "Hello World")
        try peer.applyUpdate(seed)

        let split = try local.replaceProse(start: 6, end: 6, text: "\n")
        let peerEdit = try peer.replaceProse(start: 0, end: 0, text: "Peer ")
        try local.applyUpdate(peerEdit)
        try peer.applyUpdate(split)

        XCTAssertEqual(try local.snapshot(), try peer.snapshot())
        let content = String(try local.proseProjection().text.characters)
        XCTAssertTrue(content.contains("Peer "))
        XCTAssertTrue(content.contains("World"))
    }

    func testConcurrentEditAtSplitSuffixRetainsBothContributions() throws {
        let local = RelayMarkNativeDocument()
        let peer = RelayMarkNativeDocument()
        let seed = try local.replaceProse(start: 0, end: 0, text: "Hello World")
        try peer.applyUpdate(seed)

        let split = try local.replaceProse(start: 6, end: 6, text: "\n")
        let peerEdit = try peer.replaceProse(start: 8, end: 8, text: "X")
        try local.applyUpdate(peerEdit)
        try peer.applyUpdate(split)

        XCTAssertEqual(try local.snapshot(), try peer.snapshot())
        XCTAssertTrue(String(try local.proseProjection().text.characters).contains("X"))
    }

    func testPortableAnchorsMatchYjsRelativePositionFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "relative-ranges-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["seed"] as? String))))
        let ranges = try XCTUnwrap(fixture["ranges"] as? [[String: Any]])
        for range in ranges {
            let wire = try XCTUnwrap(range["range"] as? [String: Any])
            for endpoint in ["anchor", "head"] {
                let encoded = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(wire[endpoint] as? String)))
                guard let expected = range["expected"] as? [String: Any] else {
                    XCTAssertNil(try document.resolve(anchor: encoded))
                    continue
                }
                let position = try XCTUnwrap(expected[endpoint] as? [String: Any])
                let path = try XCTUnwrap(position["path"] as? [Int])
                let index = try XCTUnwrap(position["index"] as? Int)
                let association = try XCTUnwrap(position["association"] as? Int)
                let label = "\(range["name"] ?? "range") \(endpoint)"
                XCTAssertEqual(try document.anchor(path: path, index: index, association: association), encoded, label)
                XCTAssertEqual(try document.resolve(anchor: encoded),
                               .init(path: path, index: index, association: association), label)
            }
        }
    }

    func testSnapshotPreservesTypedXmlAttributesAndInlineMarks() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "inline-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seed = try XCTUnwrap(fixture["seed"] as? String)
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(try XCTUnwrap(Data(base64Encoded: seed)))
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
        let children = try XCTUnwrap(snapshot["children"] as? [[String: Any]])
        let heading = try XCTUnwrap(children.first)
        XCTAssertEqual(heading["name"] as? String, "heading")
        XCTAssertEqual((heading["attributes"] as? [String: Any])?["level"] as? Int, 2)
        XCTAssertFalse(children.isEmpty)
        let projection = try document.proseProjection()
        XCTAssertTrue(projection.isEditable)
        XCTAssertEqual(String(projection.text.characters), fixture["initial_text"] as? String)
    }

    func testTextLeafEditProducesPortableIncrementalUpdate() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "convergence-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        let testCase = try XCTUnwrap(cases.first { $0["id"] as? String == "unicode-delete-only" })
        let updates = try XCTUnwrap(testCase["updates"] as? [String])
        let seed = try XCTUnwrap(Data(base64Encoded: updates[0]))
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        let replica = RelayMarkNativeDocument()
        try replica.applyUpdate(seed)

        let insertion = try document.insertText("🙂", at: 1, path: [0, 0])
        try replica.applyUpdate(insertion)
        XCTAssertEqual(try document.snapshot(), try replica.snapshot())

        let deletion = try document.deleteText(at: 1, length: 2, path: [0, 0])
        try replica.applyUpdate(deletion)
        XCTAssertEqual(try document.snapshot(), try replica.snapshot())

        let formatting = try document.formatText(at: 0, length: 1, attributes: ["bold": [:]], path: [0, 0])
        try replica.applyUpdate(formatting)
        XCTAssertEqual(try document.snapshot(), try replica.snapshot())
        let merged = try document.mergeUpdates([insertion, deletion, formatting])
        let mergedReplica = RelayMarkNativeDocument()
        try mergedReplica.applyUpdate(seed)
        try mergedReplica.applyUpdate(merged)
        XCTAssertEqual(try document.snapshot(), try mergedReplica.snapshot())

        let replacement = try document.replaceText(at: 0, length: 1, with: "Q", path: [0, 0])
        try replica.applyUpdate(replacement)
        XCTAssertEqual(try document.snapshot(), try replica.snapshot())
        let undo = try XCTUnwrap(document.undo())
        try replica.applyUpdate(undo)
        XCTAssertEqual(try document.snapshot(), try replica.snapshot())
        XCTAssertThrowsError(try document.deleteText(at: 999, length: 1, path: [0, 0]))
    }

    func testUndoTracksOnlyLocalOriginAcrossRemoteEdit() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "convergence-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        let testCase = try XCTUnwrap(cases.first { $0["id"] as? String == "unicode-delete-only" })
        let updates = try XCTUnwrap(testCase["updates"] as? [String])
        let seed = try XCTUnwrap(Data(base64Encoded: updates[0]))
        let local = RelayMarkNativeDocument()
        let peer = RelayMarkNativeDocument()
        try local.applyUpdate(seed)
        try peer.applyUpdate(seed)

        let localEdit = try local.insertText("X", at: 1, path: [0, 0])
        try peer.applyUpdate(localEdit)
        let peerEdit = try peer.insertText("Y", at: 0, path: [0, 0])
        try local.applyUpdate(peerEdit)
        let before = String(try local.proseProjection().text.characters)
        XCTAssertTrue(before.contains("X") && before.contains("Y"))

        let undo = try XCTUnwrap(local.undo())
        try peer.applyUpdate(undo)
        XCTAssertEqual(try local.snapshot(), try peer.snapshot())
        let afterUndo = String(try local.proseProjection().text.characters)
        XCTAssertFalse(afterUndo.contains("X"))
        XCTAssertTrue(afterUndo.contains("Y"))

        let redo = try XCTUnwrap(local.redo())
        try peer.applyUpdate(redo)
        XCTAssertEqual(try local.snapshot(), try peer.snapshot())
        let afterRedo = String(try local.proseProjection().text.characters)
        XCTAssertTrue(afterRedo.contains("X") && afterRedo.contains("Y"))
    }

    func testCommunityYjsUpdatesProjectToRelayMarkXMLAndConverge() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "convergence-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])

        for testCase in cases {
            let id = try XCTUnwrap(testCase["id"] as? String)
            let updates = try XCTUnwrap(testCase["updates"] as? [String]).map {
                try XCTUnwrap(Data(base64Encoded: $0))
            }
            let orders = try XCTUnwrap(testCase["orders"] as? [[Int]])
            let expected = try XCTUnwrap(testCase["expected"])
            for order in orders {
                let document = RelayMarkNativeDocument()
                for index in order { try document.applyUpdate(updates[index]) }
                let snapshot = try JSONSerialization.jsonObject(with: document.snapshot())
                XCTAssertTrue((snapshot as AnyObject).isEqual(expected), "\(id), order \(order), actual: \(snapshot)")

                let replica = RelayMarkNativeDocument()
                try replica.applyUpdate(document.encodeUpdate())
                let remoteVector = replica.stateVector()
                let diff = try document.encodeUpdate(since: remoteVector)
                try replica.applyUpdate(diff)
                let roundTrip = try JSONSerialization.jsonObject(with: replica.snapshot())
                XCTAssertTrue((roundTrip as AnyObject).isEqual(expected), "\(id), round trip, actual: \(roundTrip)")
            }
        }
    }

    func testPendingOutOfOrderUpdatesMustNotPassNativeAdmission() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "convergence-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        let testCase = try XCTUnwrap(cases.first { $0["id"] as? String == "unicode-delete-only" })
        let updates = try XCTUnwrap(testCase["updates"] as? [String]).map {
            try XCTUnwrap(Data(base64Encoded: $0))
        }
        let document = RelayMarkNativeDocument()
        XCTAssertTrue(document.integrationStatus().isComplete)
        try document.applyUpdate(updates[2])
        XCTAssertFalse(document.integrationStatus().isComplete)
        try document.applyUpdate(updates[1])
        try document.applyUpdate(updates[0])
        XCTAssertTrue(document.integrationStatus().isComplete)
    }
}
