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
        let change = try body()
        guard !edits.isEmpty else { return change }
        for edit in edits {
            if let index = pendingSettings.firstIndex(where: { $0.id == edit.id }) {
                // A later edit of the same node keeps the original base: its keys are all still unacknowledged.
                pendingSettings[index].local = edit.local
            } else {
                pendingSettings.append(PendingSettingsEdit(id: edit.id, base: edit.base, local: edit.local))
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

    /// Writes the rebased value as one local transaction under an origin the undo manager does not
    /// track, so it adds no undo step; undo still reverts only the user's own edit.
    private func writeRebased(_ merged: [String: Any], entry: inout PendingSettingsEdit, tree: [String: Any]) throws -> Data {
        let incoming = Self.node(withID: entry.id, in: tree).flatMap { Self.settings(of: $0) }
        let change = try writingUntracked {
            try RelayMarkNativeRichEditing.updateWidget(document: self, tree: tree, id: entry.id, attributes: ["settings": merged])
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
