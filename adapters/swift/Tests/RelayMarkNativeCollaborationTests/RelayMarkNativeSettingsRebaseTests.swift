import Foundation
import Testing
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

/// Two native editors change one form question's aggregate `settings` at once. Settings stay ONE
/// attribute (never per-key storage), so the editor model rebases the loser's unacknowledged edit
/// through relaymark-core's `settings_rebase` and keeps both people's keys. Written against the aggregate
/// shape: the native writer must emit the single `settings` attribute (branch aggregate-writer) for these to pass.
struct RelayMarkNativeSettingsRebaseTests {
    /// A one-question form paper whose question node holds `settings` as one aggregate object.
    @MainActor private func seededPair(_ settings: [String: Any]) throws -> (RelayMarkNativeDocument, RelayMarkNativeDocument, id: String) {
        let source = "<!-- relay:question id=\"q-one\" type=\"file_upload\" -->\n**Evidence?**\n<!-- /relay:question -->"
        let seed = RelayMarkNativeDocument()
        try seed.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "settings-rebase"))
        var tree = try #require(JSONSerialization.jsonObject(with: seed.snapshot()) as? [String: Any])
        var id = ""
        func aggregate(_ node: Any) -> Any {
            guard var element = node as? [String: Any], element["kind"] as? String == "element" else { return node }
            if var attributes = element["attributes"] as? [String: Any], element["name"] as? String == "questionBlock" {
                for key in attributes.keys where key.hasPrefix("settings:") { attributes.removeValue(forKey: key) }
                attributes["settings"] = settings
                id = attributes["relaymarkId"] as? String ?? ""
                element["attributes"] = attributes
            }
            if let children = element["children"] as? [Any] { element["children"] = children.map(aggregate) }
            return element
        }
        let nodes = (tree["children"] as? [Any] ?? []).map(aggregate)
        tree["children"] = nodes
        let base = RelayMarkNativeDocument()
        _ = try base.edit(JSONSerialization.data(withJSONObject: ["kind": "insertNodes", "path": [Int](), "index": 0, "nodes": nodes]))
        let update = try base.encodeUpdate()
        let a = RelayMarkNativeDocument(guid: "settings-rebase", clientID: 1), b = RelayMarkNativeDocument(guid: "settings-rebase", clientID: 2)
        try a.applyUpdate(update); try b.applyUpdate(update)
        return (a, b, id)
    }

    @MainActor private func set(_ document: RelayMarkNativeDocument, id: String, from: [String: Any], to: [String: Any]) throws -> Data {
        try RelayMarkNativeWidgetMutation.updateAttributes(document: document, path: [0], expectedID: id,
            expected: JSONSerialization.data(withJSONObject: ["settings": from]),
            changes: JSONSerialization.data(withJSONObject: ["settings": to])).update
    }

    @MainActor private func settings(_ document: RelayMarkNativeDocument) throws -> NSDictionary {
        let tree = try #require(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
        let question = try #require((tree["children"] as? [[String: Any]])?.first)
        let decoded = try RelayMarkContentEditCodec.decodeDocumentAttributes(nodeName: "questionBlock",
            attributes: try #require(question["attributes"] as? [String: Any]))
        return NSDictionary(dictionary: try #require(decoded["settings"] as? [String: Any]))
    }

    /// Both peers exchange their edits, then whatever follow-up each wrote, until quiet.
    @MainActor private func exchange(_ a: RelayMarkNativeDocument, _ aUpdate: Data, _ b: RelayMarkNativeDocument, _ bUpdate: Data) throws
        -> (aFollowUp: Data?, bFollowUp: Data?) {
        let aFollowUp = try a.applyUpdate(bUpdate), bFollowUp = try b.applyUpdate(aUpdate)
        if let aFollowUp { try b.applyUpdate(aFollowUp) }
        if let bFollowUp { try a.applyUpdate(bFollowUp) }
        return (aFollowUp, bFollowUp)
    }

    @Test @MainActor func concurrentEditsOfDifferentKeysKeepBothKeys() throws {
        let (a, b, id) = try seededPair(["max_files": 1, "accept": "image"])
        let aUpdate = try set(a, id: id, from: ["max_files": 1, "accept": "image"], to: ["max_files": 3, "accept": "image"])
        let bUpdate = try set(b, id: id, from: ["max_files": 1, "accept": "image"], to: ["max_files": 1, "accept": "pdf"])
        _ = try exchange(a, aUpdate, b, bUpdate)
        let both: NSDictionary = ["max_files": 3, "accept": "pdf"]
        #expect(try settings(a) == both)
        #expect(try settings(b) == both)
    }

    @Test @MainActor func concurrentEditsOfTheSameKeyConvergeOnOneValue() throws {
        let (a, b, id) = try seededPair(["max_files": 1])
        let aUpdate = try set(a, id: id, from: ["max_files": 1], to: ["max_files": 3])
        let bUpdate = try set(b, id: id, from: ["max_files": 1], to: ["max_files": 5])
        _ = try exchange(a, aUpdate, b, bUpdate)
        #expect(try settings(a) == settings(b))
        #expect([3, 5].contains(try settings(a)["max_files"] as? Int ?? 0))
    }

    @Test @MainActor func anAcknowledgedEditIsNotAppliedAgainOverALaterRemoteChange() throws {
        let (a, b, id) = try seededPair(["max_files": 1])
        let aUpdate = try set(a, id: id, from: ["max_files": 1], to: ["max_files": 3])
        try b.applyUpdate(aUpdate)
        a.acknowledgeLocalEdits()
        // B, having seen A's edit, puts the key back to what it was before A's edit.
        let revert = try set(b, id: id, from: ["max_files": 3], to: ["max_files": 1])
        #expect(try a.applyUpdate(revert) == nil)
        #expect(try settings(a) == ["max_files": 1])
    }

    @Test @MainActor func undoAfterARebaseAddsNoUndoStepOfItsOwn() throws {
        let (a, b, id) = try seededPair(["max_files": 1, "accept": "image"])
        let aUpdate = try set(a, id: id, from: ["max_files": 1, "accept": "image"], to: ["max_files": 3, "accept": "image"])
        let bUpdate = try set(b, id: id, from: ["max_files": 1, "accept": "image"], to: ["max_files": 1, "accept": "pdf"])
        let followUps = try exchange(a, aUpdate, b, bUpdate)
        // Fixed client ids make the winner of the concurrent write known: B (id 2) wins, so A rebases.
        #expect(followUps.aFollowUp != nil && followUps.bFollowUp == nil)
        let both: NSDictionary = ["max_files": 3, "accept": "pdf"]
        #expect(try settings(a) == both)
        // The follow-up is written under an origin the undo manager does not track, so it is not an undo
        // step. As in stock Yjs, A's own write was superseded by the merge, leaving nothing to undo.
        #expect(try a.undo() == nil)
        #expect(try settings(a) == both)
    }
}
