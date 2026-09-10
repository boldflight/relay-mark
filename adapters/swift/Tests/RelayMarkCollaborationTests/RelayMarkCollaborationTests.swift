import Foundation
import Testing
@testable import RelayMarkCollaboration

@MainActor
struct RelayMarkCollaborationTests {
    private func seed(_ doc: RelayMarkCollaborationDocument) throws {
        _ = try doc.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"paragraph","attributes":{},"children":[{"kind":"text","delta":[{"insert":"Hello 🌍","attributes":{"bold":{},"link":{"href":"relay:entity/123"}}}]}]}]}"#.utf8))
    }

    @Test func explicitFormattingHistoryUsesActualItemAndLegacyUndoStillReturnsUpdates() throws {
        let doc = try RelayMarkCollaborationDocument()
        try seed(doc)
        let ids = try doc.captureTextItems(path: [0, 0], index: 0, length: 8)
        let operation = Data(#"{"kind":"formatText","path":[0,0],"index":0,"length":5,"attributes":{"italic":{}}}"#.utf8)
        _ = try doc.editNativeFormatting(operation)
        let undone = try doc.undoWithFormattingEvidence()
        #expect(undone.formattingMark == .italic)
        #expect(!undone.updates.isEmpty)
        #expect(try doc.redoWithFormattingEvidence().formattingMark == .italic)
        let legacyUndo: () throws -> [Data] = doc.undo
        #expect(try !legacyUndo().isEmpty)
        #expect(try doc.redoWithFormattingEvidence().formattingMark == .italic)
        #expect(try doc.captureTextItems(path: [0, 0], index: 0, length: 8) == ids)
        let reopened = try RelayMarkCollaborationDocument()
        try reopened.applyUpdate(doc.encodeUpdate())
        let history = try reopened.undoWithFormattingEvidence()
        #expect(history.updates.isEmpty)
        #expect(history.formattingMark == nil)
    }

    @Test func mergedLogicalTransactionPreservesDeletionAndFormatting() throws {
        let local = try RelayMarkCollaborationDocument(), remote = try RelayMarkCollaborationDocument()
        try seed(local)
        try remote.applyUpdate(local.encodeUpdate())
        var updates = try local.deleteText(at: 0, length: 5, path: [0, 0])
        updates += try local.insertText("Goodbye", at: 0, path: [0, 0])
        updates += try local.edit(Data(#"{"kind":"formatText","path":[0,0],"index":0,"length":7,"attributes":{"italic":{}}}"#.utf8))
        let merged = try local.mergeUpdates(updates)
        try remote.applyUpdate(merged)
        try remote.applyUpdate(merged)
        #expect(try remote.snapshot() == local.snapshot())
        let changes = RelayMarkLocalTransaction.TextChange.between("Remote Hello 🌍", "Remote Goodbye 🌍")
        #expect(changes.count == 1)
        #expect(changes[0].kind == .replace)
        #expect(changes[0].before == "Hello")
        #expect(changes[0].after == "Goodbye")
        #expect(changes[0].contextBefore == "Remote ")
        #expect(RelayMarkLocalTransaction.TextChange.between("unchanged", "unchanged").isEmpty)
        let deletion = RelayMarkLocalTransaction.TextChange.between("A 🌍 B", "A  B")
        #expect(deletion[0].kind == .delete)
        #expect(deletion[0].before == "🌍")
    }

    @Test func portableUnicodeDeletionReorderingAndConcurrentReferenceFixtures() throws {
        let url = try #require(Bundle.module.url(forResource: "convergence-v1", withExtension: "json"))
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try #require(fixture["cases"] as? [[String: Any]])
        var exported: [[String: String]] = []
        for item in cases {
            let id = try #require(item["id"] as? String)
            let updates = try #require(item["updates"] as? [String]).map { try #require(Data(base64Encoded: $0)) }
            let orders = try #require(item["orders"] as? [[Int]])
            let expected = try JSONSerialization.data(withJSONObject: #require(item["expected"]), options: [.sortedKeys])
            for order in orders {
                let doc = try RelayMarkCollaborationDocument()
                for index in order { try doc.applyUpdate(updates[index]) }
                let actual = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: doc.snapshot()), options: [.sortedKeys])
                #expect(actual == expected, "Fixture \(id), delivery \(order)")
                let restarted = try RelayMarkCollaborationDocument()
                try restarted.applyUpdate(doc.encodeUpdate())
                #expect(try restarted.snapshot() == doc.snapshot())
                #expect(try doc.undo().isEmpty)
            }
            if item["deletion_update_index"] != nil {
                #expect(item["state_vector_before_delete"] as? String == item["state_vector_after_delete"] as? String)
            }
            let native = try RelayMarkCollaborationDocument()
            for update in updates { try native.applyUpdate(update) }
            let vector = try native.stateVector()
            _ = try native.insertText("Swift✅ ", at: 0, path: [0, 0])
            exported.append(["id": id, "update": try native.encodeUpdate(since: vector).base64EncodedString()])
        }
        if let path = ProcessInfo.processInfo.environment["RELAY_COLLABORATION_CONFORMANCE_OUTPUT"] {
            try JSONSerialization.data(withJSONObject: ["cases": exported], options: [.sortedKeys]).write(to: URL(fileURLWithPath: path))
        }
    }

    @Test func nativeProjectionRejectsServerInvalidAttributesWithoutLosingReplicaContent() throws {
        for (name, key, values) in [("heading", "level", [0, 7, 1.5, true, "2"] as [Any]),
                                     ("orderedList", "start", [0, -1, 1.5, true, "2"] as [Any])] {
            for value in values {
                let paragraph: [String: Any] = ["kind": "element", "name": "paragraph", "attributes": [:], "children": []]
                let children: [[String: Any]] = name == "orderedList" ? [["kind": "element", "name": "listItem", "attributes": [:], "children": [paragraph]]] : []
                let snapshot: [String: Any] = ["kind": "fragment", "children": [["kind": "element", "name": name, "attributes": [key: value], "children": children]]]
                let projection = try RelayMarkCollaborativeProse(snapshot: JSONSerialization.data(withJSONObject: snapshot))
                #expect(!projection.isEditable)
            }
        }
        let doc = try RelayMarkCollaborationDocument()
        try seed(doc)
        _ = try doc.edit(Data(#"{"kind":"formatText","path":[0,0],"index":0,"length":5,"attributes":{"link":{"href":"relay:entity/123","title":"Unsupported but retained"}}}"#.utf8))
        let before = try doc.snapshot()
        #expect(try !RelayMarkCollaborativeProse(snapshot: before).isEditable)
        #expect(try doc.snapshot() == before)
    }

    @Test func concurrentOfflineRestartAndSelectiveUndo() throws {
        let alice = try RelayMarkCollaborationDocument()
        try seed(alice)
        let bob = try RelayMarkCollaborationDocument()
        try bob.applyUpdate(alice.encodeUpdate())
        let anchor = try bob.anchor(path: [0, 0], index: 6)
        let a = try alice.insertText("Alice ", at: 0, path: [0, 0])
        let b = try bob.insertText(" Bob", at: 8, path: [0, 0])
        let restarted = try RelayMarkCollaborationDocument()
        try restarted.applyUpdate(bob.encodeUpdate())
        for update in a { try restarted.applyUpdate(update) }
        for update in b { try alice.applyUpdate(update) }
        #expect(try alice.snapshot() == restarted.snapshot())
        #expect(try restarted.resolve(anchor: anchor)?.index == 12)
        let undo = try alice.undo()
        for update in undo { try restarted.applyUpdate(update) }
        #expect(try alice.snapshot() == restarted.snapshot())
        let json = String(decoding: try alice.snapshot(), as: UTF8.self)
        #expect(json.contains(" Bob"))
        #expect(!json.contains("Alice "))
        #expect(json.contains("relay:entity/123"))
    }

    @Test func deletionDiffAndInvalidEdit() throws {
        let alice = try RelayMarkCollaborationDocument()
        try seed(alice)
        let bob = try RelayMarkCollaborationDocument()
        try bob.applyUpdate(alice.encodeUpdate())
        let vector = try bob.stateVector()
        _ = try alice.deleteText(at: 0, length: 1, path: [0, 0])
        let update = try alice.encodeUpdate(since: vector)
        try bob.applyUpdate(update)
        try bob.applyUpdate(update)
        #expect(try bob.snapshot() == alice.snapshot())
        let before = try alice.snapshot()
        #expect(throws: RelayMarkCollaborationDocument.Failure.self) {
            try alice.deleteText(at: -1, length: 200, path: [0, 0])
        }
        #expect(try before == alice.snapshot())
    }
    @Test func nodeYjsBinaryInteroperability() throws {
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf:
            Bundle.module.url(forResource: "yjs-v13-xml", withExtension: "json")!)) as! [String: String]
        let doc = try RelayMarkCollaborationDocument()
        try doc.applyUpdate(Data(base64Encoded: fixture["seed"]!)!)
        _ = try doc.insertText("Swift ", at: 0, path: [0, 0])
        try doc.applyUpdate(Data(base64Encoded: fixture["browserUpdate"]!)!)
        let json = String(decoding: try doc.snapshot(), as: UTF8.self)
        #expect(json.contains("Swift "))
        #expect(json.contains("Hello 🌍 browser"))
        #expect(json.contains("relay:entity/123"))
        if let path = ProcessInfo.processInfo.environment["RELAY_COLLABORATION_INTEROP_OUTPUT"] {
            let anchor = try doc.anchor(path: [0, 0], index: 6)
            let awareness = try doc.setPresence(name: "Native", anchor: anchor, head: anchor)
            let output = ["update": try doc.encodeUpdate().base64EncodedString(), "awareness": awareness[0].base64EncodedString()]
            try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]).write(to: URL(fileURLWithPath: path))
        }
    }

    @Test func paragraphSplitMergePreservesSuffixAndUnknownNodes() throws {
        let doc = try RelayMarkCollaborationDocument()
        try seed(doc)
        _ = try doc.replaceProse(start: 5, end: 5, text: "\nnew")
        var prose = try RelayMarkCollaborativeProse(snapshot: doc.snapshot())
        #expect(String(prose.text.characters) == "Hello\nnew 🌍")
        #expect(prose.isEditable)
        #expect(prose.blockRanges.count == 2)
        _ = try doc.replaceProse(start: 5, end: 9, text: " again")
        prose = try RelayMarkCollaborativeProse(snapshot: doc.snapshot())
        #expect(String(prose.text.characters) == "Hello again 🌍")
        #expect(prose.blockRanges.count == 1)
        #expect(String(decoding: try doc.snapshot(), as: UTF8.self).contains("relay:entity/123"))
        _ = try doc.edit(Data(#"{"kind":"insertNodes","path":[],"index":1,"nodes":[{"kind":"element","name":"customWidget","attributes":{"secret":"opaque"},"children":[]}]}"#.utf8))
        #expect(try !RelayMarkCollaborativeProse(snapshot: doc.snapshot()).isEditable)
    }

    @Test func replacementUsesGraphemeBoundariesAndUTF16() {
        let diff = RelayMarkCollaborativeProse.replacement(from: "Hi 🌍!", to: "Hi 👨‍👩‍👧‍👦!")
        #expect(diff.start == 3)
        #expect(diff.end == 5)
        #expect(diff.text == "👨‍👩‍👧‍👦")
    }

    @Test func groupedTextAndFormattingUndoTogether() throws {
        let doc = try RelayMarkCollaborationDocument()
        try seed(doc)
        let before = try doc.snapshot()
        try doc.withUndoGroup {
            _ = try doc.insertText("new ", at: 0, path: [0, 0])
            _ = try doc.edit(Data(#"{"kind":"formatText","path":[0,0],"index":0,"length":4,"attributes":{"italic":{}}}"#.utf8))
        }
        _ = try doc.undo()
        #expect(try doc.snapshot() == before)
    }

    @Test func standardAwarenessRoundTripRemovalAndNoDurableMutation() throws {
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf:
            Bundle.module.url(forResource: "yjs-v13-xml", withExtension: "json")!)) as! [String: String]
        let doc = try RelayMarkCollaborationDocument()
        try doc.applyUpdate(Data(base64Encoded: fixture["browserUpdate"]!)!)
        let before = try doc.encodeUpdate()
        try doc.applyPresence(Data(base64Encoded: fixture["browserAwareness"]!)!, origin: "browser-socket")
        let collaborators = try doc.collaborators()
        #expect(collaborators.count == 1)
        #expect(collaborators.first?.name == "Browser")
        #expect(try doc.resolve(anchor: collaborators[0].anchor!)?.index == 6)
        #expect(try doc.encodeUpdate() == before)
        try doc.removePresence(origin: "browser-socket")
        #expect(try doc.collaborators().isEmpty)
        #expect(try doc.encodeUpdate() == before)
    }

    @Test func presenceSnapshotSeedsExistingCursorAndRetainsOriginWithoutChangingUndo() throws {
        let remote = try RelayMarkCollaborationDocument(), owner = try RelayMarkCollaborationDocument(), child = try RelayMarkCollaborationDocument()
        try seed(remote)
        try owner.applyUpdate(remote.encodeUpdate()); try child.applyUpdate(remote.encodeUpdate())
        let anchor = try remote.anchor(path: [0, 0], index: 3)
        let awareness = try remote.setPresence(name: "Existing collaborator", anchor: anchor, head: anchor)
        for bytes in awareness { try owner.applyPresence(bytes, origin: "external-socket") }
        let snapshot = try owner.presenceSnapshot()
        let roundTrip = try JSONDecoder().decode(RelayMarkCollaborationDocument.PresenceSnapshot.self,
            from: JSONEncoder().encode(snapshot))
        #expect(roundTrip == snapshot)
        for bytes in awareness { try child.applyPresence(bytes, origin: "prior-path") }
        _ = try child.insertText("local ", at: 0, path: [0, 0])
        let before = try child.encodeUpdate()
        try child.applyPresenceSnapshot(snapshot); try child.applyPresenceSnapshot(snapshot)
        let cursor = try #require(child.collaborators().first)
        #expect(cursor.name == "Existing collaborator")
        #expect(try child.resolve(anchor: #require(cursor.anchor))?.index == 9)
        #expect(try child.encodeUpdate() == before)
        try child.removePresence(origin: "external-socket")
        #expect(try child.collaborators().isEmpty)
        _ = try child.undo()
        #expect(try child.snapshot() == remote.snapshot())
    }

    @Test func invalidPresenceSnapshotCannotInstallUnownedCursor() throws {
        let remote = try RelayMarkCollaborationDocument(), owner = try RelayMarkCollaborationDocument(), child = try RelayMarkCollaborationDocument()
        for bytes in try remote.setPresence(name: "Remote") { try owner.applyPresence(bytes, origin: "socket") }
        let snapshot = try owner.presenceSnapshot()
        let invalid = RelayMarkCollaborationDocument.PresenceSnapshot(update: snapshot.update, origins: [:])
        #expect(throws: (any Error).self) { try child.applyPresenceSnapshot(invalid) }
        #expect(try child.collaborators().isEmpty)
        #expect(try child.presenceSnapshot().origins.isEmpty)
    }

    @Test func nestedProseEditingPreservesContainersAndCodeNewlines() throws {
        let doc = try RelayMarkCollaborationDocument()
        _ = try doc.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"heading","attributes":{"level":2},"children":[{"kind":"text","delta":[{"insert":"Title"}]}]},{"kind":"element","name":"blockquote","children":[{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"Quote"}]}]}]},{"kind":"element","name":"bulletList","children":[{"kind":"element","name":"listItem","children":[{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"One"}]}]}]},{"kind":"element","name":"listItem","children":[{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"Two"}]}]}]}]},{"kind":"element","name":"codeBlock","attributes":{"language":"swift"},"children":[{"kind":"text","delta":[{"insert":"let x=1"}]}]}]}"#.utf8))
        var prose = try RelayMarkCollaborativeProse(snapshot: doc.snapshot())
        #expect(prose.isEditable)
        #expect(String(prose.text.characters) == "Title\nQuote\nOne\nTwo\nlet x=1")
        #expect(prose.blockPaths[2] == [2, 0, 0])
        let titleAnchor = try doc.anchor(path: [0, 0], index: 3)
        _ = try doc.replaceProse(start: 15, end: 15, text: "\nNew")
        prose = try RelayMarkCollaborativeProse(snapshot: doc.snapshot())
        #expect(String(prose.text.characters).contains("One\nNew\nTwo"))
        #expect(prose.blockPaths[3] == [2, 1, 0])
        #expect(try doc.resolve(anchor: titleAnchor)?.index == 3)
        let codeEnd = String(prose.text.characters).utf16.count
        _ = try doc.replaceProse(start: codeEnd, end: codeEnd, text: "\nlet y=2")
        prose = try RelayMarkCollaborativeProse(snapshot: doc.snapshot())
        #expect(prose.blockPaths.count == 6)
        #expect(String(prose.text.characters).hasSuffix("let x=1\nlet y=2"))
        let tree = String(decoding: try doc.snapshot(), as: UTF8.self)
        #expect(tree.contains("heading"))
        #expect(tree.contains("blockquote"))
        #expect(tree.contains("bulletList"))
        #expect(tree.contains("swift"))
    }

}
