import Foundation
import OSLog
import RelayMarkSwift

/// A local edit to one question's or option's aggregate `settings` that the server has not
/// acknowledged. Settings stay ONE `settings` attribute (never per-key storage, Douglas 2026-11-02),
/// so a concurrent change to the same attribute keeps only the last writer's whole value; this entry
/// lets the document call relaymark-core's `settings_rebase` and keep both people's keys.
struct PendingSettingsEdit {
    let id: String
    /// The value the (first unacknowledged) edit started from, then the last incoming value rebased onto.
    var base: [String: Any]?
    /// The value this device last wrote.
    var local: [String: Any]?
    /// Undo-stack depth right after the edit when the edit is the top undo item and nothing else, else nil.
    var ownUndoItem: Int?
}

extension RelayMarkNativeDocument {
    /// Entries kept per document; the oldest is dropped beyond it.
    static let pendingSettingsLimit = 32
    private static let log = Logger(subsystem: "RelayMarkNativeCollaboration", category: "SettingsRebase")

    /// The host calls this once the server has acknowledged (merged) every local update it has sent,
    /// so an acknowledged edit is never re-applied over a later remote change.
    public func acknowledgeLocalEdits() { pendingSettings.removeAll() }

    /// Runs one settings write and remembers it as pending when it succeeds.
    func trackingSettingsEdits(_ edits: [(id: String, base: [String: Any]?, local: [String: Any]?)],
                               _ body: () throws -> RelayMarkNativeRichEditing.Change) throws -> RelayMarkNativeRichEditing.Change {
        let before = undoManager.undoMetadata().count
        let change = try body()
        guard !edits.isEmpty else { return change }
        let after = undoManager.undoMetadata().count
        let own = undoGroupDepth == 0 && editorCommandDepth == 0 && after == before + 1 && edits.count == 1 ? after : nil
        for edit in edits {
            if let index = pendingSettings.firstIndex(where: { $0.id == edit.id }) {
                // A later edit of the same node keeps the original base: its keys are all still unacknowledged.
                pendingSettings[index].local = edit.local
                pendingSettings[index].ownUndoItem = own
            } else {
                pendingSettings.append(PendingSettingsEdit(id: edit.id, base: edit.base, local: edit.local, ownUndoItem: own))
            }
        }
        if pendingSettings.count > Self.pendingSettingsLimit {
            pendingSettings.removeFirst(pendingSettings.count - Self.pendingSettingsLimit)
        }
        return change
    }

    /// Rebases every pending entry whose node's `settings` a remote update replaced. Never throws:
    /// a failed rebase leaves the incoming value (last writer wins) and drops the entry.
    func rebasePendingSettings() -> Data? {
        guard let data = try? snapshot(), let tree = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Self.log.error("settings rebase skipped: snapshot unavailable")
            return nil
        }
        var updates: [Data] = []
        var index = 0
        while index < pendingSettings.count {
            var entry = pendingSettings[index]
            guard let node = Self.node(withID: entry.id, in: tree) else {
                pendingSettings.remove(at: index); continue // the question is gone
            }
            let incoming = Self.settings(of: node)
            if Self.same(incoming, entry.local) { index += 1; continue } // nothing remote touched it
            do {
                guard let merged = try RelayMarkSettingsRebase.rebase(base: entry.base, local: entry.local, incoming: incoming) else {
                    pendingSettings.remove(at: index); continue // incoming already holds every surviving change
                }
                updates.append(try writeRebased(merged, entry: &entry, tree: tree))
                pendingSettings[index] = entry
                index += 1
            } catch {
                Self.log.error("settings rebase failed (\(String(describing: type(of: error)), privacy: .public)); keeping the incoming value")
                pendingSettings.remove(at: index)
            }
        }
        guard !updates.isEmpty else { return nil }
        return updates.count == 1 ? updates[0] : try? mergeUpdates(updates)
    }

    /// Writes the rebased value as one local transaction without adding an undo step: when the user's
    /// own edit is still the top undo item the rebase write replaces it, so one undo still reverts the
    /// whole settings change to the incoming value; otherwise the write is not undoable on its own.
    private func writeRebased(_ merged: [String: Any], entry: inout PendingSettingsEdit, tree: [String: Any]) throws -> Data {
        let incoming = Self.node(withID: entry.id, in: tree).flatMap { Self.settings(of: $0) }
        let before = undoManager.undoMetadata().count
        let change = try RelayMarkNativeRichEditing.updateWidget(document: self, tree: tree, id: entry.id, attributes: ["settings": merged])
        let after = undoManager.undoMetadata().count
        if after > before {
            let retire = entry.ownUndoItem == before ? before - 1 : before
            _ = try? undoManager.retireHistoryItems(undoIndices: [retire], redoIndices: [])
            entry.ownUndoItem = entry.ownUndoItem == before ? before : nil
        }
        entry.base = incoming
        entry.local = merged
        return change.update
    }

    /// The node's settings as the codec reads them: the one aggregate `settings` attribute.
    private static func settings(of node: [String: Any]) -> [String: Any]? {
        guard let name = node["name"] as? String, let attributes = node["attributes"] as? [String: Any],
              let decoded = try? RelayMarkContentEditCodec.decodeDocumentAttributes(nodeName: name, attributes: attributes) else { return nil }
        return decoded["settings"] as? [String: Any]
    }

    private static func same(_ a: [String: Any]?, _ b: [String: Any]?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return NSDictionary(dictionary: a).isEqual(to: b)
        default: return false
        }
    }

    private static func node(withID id: String, in node: [String: Any]) -> [String: Any]? {
        if (node["attributes"] as? [String: Any])?["relaymarkId"] as? String == id { return node }
        for child in node["children"] as? [[String: Any]] ?? [] {
            if let found = self.node(withID: id, in: child) { return found }
        }
        return nil
    }
}
