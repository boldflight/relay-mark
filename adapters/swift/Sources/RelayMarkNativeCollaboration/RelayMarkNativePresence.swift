import Foundation
import YSwift

/// RelayMark's ephemeral presentation of standard Yrs/y-protocols awareness.
/// Transport origin ownership is local host state, never part of a Yjs document.
@MainActor
public final class RelayMarkNativePresence {
    public enum Failure: Error {
        case invalidOrigin
        case invalidSnapshot
    }

    public struct Snapshot: Codable, Equatable, Sendable {
        public let version: Int
        public let update: Data
        public let origins: [String: [UInt64]]

        public init(version: Int = 1, update: Data, origins: [String: [UInt64]]) {
            self.version = version
            self.update = update
            self.origins = origins
        }
    }

    public struct Collaborator: Identifiable, Equatable, Sendable {
        public let id: UInt64
        public let userID: String?
        public let name: String
        public let color: String
        public let anchor: Data?
        public let head: Data?
    }

    private let awareness: YAwareness
    private var origins: [String: Set<UInt64>] = [:]

    init(awareness: YAwareness) {
        self.awareness = awareness
    }

    public var clientID: UInt64 { awareness.clientID }

    /// Returns the exact y-protocols update to broadcast, including a null
    /// state when leaving. Cursor positions use Yjs's standard JSON shape.
    public func setPresence(name: String?, color: String = "#666666", anchor: Data? = nil, head: Data? = nil,
                            userID: String? = nil) throws -> Data {
        guard let name else {
            awareness.clearLocalState()
            return try awareness.encodeUpdate(for: [clientID])
        }
        var user: [String: Any] = ["name": String(name.prefix(100)), "color": color]
        if let userID { user["id"] = userID }
        var state: [String: Any] = ["user": user]
        if let anchor, let head {
            state["cursor"] = [
                "anchor": try YDocument.relativePositionJSON(from: anchor),
                "head": try YDocument.relativePositionJSON(from: head)
            ]
        } else {
            state["cursor"] = NSNull()
        }
        try awareness.setLocalState(state)
        return try awareness.encodeUpdate(for: [clientID])
    }

    public func applyPresence(_ update: Data, origin: String) throws {
        guard Self.valid(origin: origin) else { throw Failure.invalidOrigin }
        guard let changes = try awareness.applyUpdate(update) else { return }
        for id in changes.added + changes.updated + changes.removed {
            for key in Array(origins.keys) {
                origins[key]?.remove(id)
                if origins[key]?.isEmpty == true { origins.removeValue(forKey: key) }
            }
            if id != clientID, try awareness.state(for: id)?.state != nil {
                origins[origin, default: []].insert(id)
            }
        }
    }

    /// A newly mounted consumer receives the same active remote awareness and
    /// its origin ownership, so a later channel leave can remove those cursors.
    public func snapshot() throws -> Snapshot {
        let active = try awareness.states().filter { $0.clientID != clientID && $0.state != nil }
        let ids = Set(active.map(\.clientID))
        let covered = origins.values.reduce(into: Set<UInt64>()) { $0.formUnion($1) }
        guard ids == covered else { throw Failure.invalidSnapshot }
        return Snapshot(update: try awareness.encodeUpdate(for: ids.sorted()),
                        origins: origins.mapValues { $0.sorted() })
    }

    public func apply(snapshot: Snapshot) throws {
        guard snapshot.version == 1 else { throw Failure.invalidSnapshot }
        let scratch = YDocument().makeAwareness()
        _ = try scratch.applyUpdate(snapshot.update)
        let active = try scratch.states().filter { $0.state != nil }
        let ids = Set(active.map(\.clientID))
        guard !ids.contains(clientID),
              !snapshot.origins.isEmpty || ids.isEmpty else { throw Failure.invalidSnapshot }
        var covered = Set<UInt64>()
        for (origin, members) in snapshot.origins {
            guard Self.valid(origin: origin), !members.isEmpty,
                  members.count == Set(members).count else { throw Failure.invalidSnapshot }
            for id in members {
                guard ids.contains(id), covered.insert(id).inserted else { throw Failure.invalidSnapshot }
            }
        }
        guard covered == ids else { throw Failure.invalidSnapshot }
        // Reject tombstones; snapshots are an active-state bootstrap, not a
        // second store of historical presence clocks.
        guard try scratch.states().allSatisfy({ $0.state != nil || $0.clientID == scratch.clientID }) else {
            throw Failure.invalidSnapshot
        }
        _ = try awareness.applyUpdate(snapshot.update)
        let current = Dictionary(uniqueKeysWithValues: try awareness.states().map { ($0.clientID, $0) })
        for (origin, members) in snapshot.origins {
            for id in members {
                guard let expected = active.first(where: { $0.clientID == id }),
                      let actual = current[id], actual.clock == expected.clock,
                      Self.equal(actual.state, expected.state) else { continue }
                for key in Array(origins.keys) { origins[key]?.remove(id) }
                origins[origin, default: []].insert(id)
            }
        }
        origins = origins.filter { !$0.value.isEmpty }
    }

    public func removePresence(origin: String) throws {
        guard Self.valid(origin: origin) else { throw Failure.invalidOrigin }
        for id in origins.removeValue(forKey: origin) ?? [] {
            _ = try awareness.removeRemoteState(for: id)
        }
    }

    /// Removes peers the server reports gone, whatever origin delivered them.
    public func removePresence(clientIDs: [UInt64]) throws {
        for id in clientIDs where id != clientID {
            _ = try awareness.removeRemoteState(for: id)
            for key in Array(origins.keys) { origins[key]?.remove(id) }
        }
        origins = origins.filter { !$0.value.isEmpty }
    }

    public func clearRemotePresence() throws {
        for state in try awareness.states() where state.clientID != clientID && state.state != nil {
            _ = try awareness.removeRemoteState(for: state.clientID)
        }
        origins.removeAll()
    }

    /// The connected host calls this periodically. Refresh and expiry use the
    /// standard 30-second awareness timeout; no presence enters durable updates.
    public func advancePresenceClock(nowMillis: UInt64 = UInt64(Date().timeIntervalSince1970 * 1_000)) throws -> [Data] {
        for state in try awareness.states() where state.clientID != clientID && state.state != nil {
            if nowMillis > state.lastUpdatedMillis && nowMillis - state.lastUpdatedMillis > 30_000 {
                _ = try awareness.removeRemoteState(for: state.clientID)
                for key in Array(origins.keys) { origins[key]?.remove(state.clientID) }
            }
        }
        origins = origins.filter { !$0.value.isEmpty }
        guard let local = try awareness.localState() else { return [] }
        try awareness.setLocalState(local)
        return [try awareness.encodeUpdate(for: [clientID])]
    }

    public func collaborators() throws -> [Collaborator] {
        try awareness.states().compactMap { record in
            guard record.clientID != clientID, let state = record.state else { return nil }
            let user = state["user"] as? [String: Any]
            let cursor = state["cursor"] as? [String: Any]
            let anchor = (cursor?["anchor"] as? [String: Any]).flatMap { try? YDocument.relativePositionBytes(fromJSON: $0) }
            let head = (cursor?["head"] as? [String: Any]).flatMap { try? YDocument.relativePositionBytes(fromJSON: $0) }
            return Collaborator(id: record.clientID, userID: user?["id"] as? String,
                                name: String((user?["name"] as? String ?? "Collaborator").prefix(100)),
                                color: user?["color"] as? String ?? "#666666", anchor: anchor, head: head)
        }.sorted { $0.id < $1.id }
    }

    private static func valid(origin: String) -> Bool {
        !origin.isEmpty && origin != "local" && origin != "timeout"
    }

    private static func equal(_ lhs: [String: Any]?, _ rhs: [String: Any]?) -> Bool {
        guard let lhs, let rhs,
              let a = try? JSONSerialization.data(withJSONObject: lhs, options: [.sortedKeys]),
              let b = try? JSONSerialization.data(withJSONObject: rhs, options: [.sortedKeys]) else { return false }
        return a == b
    }
}
