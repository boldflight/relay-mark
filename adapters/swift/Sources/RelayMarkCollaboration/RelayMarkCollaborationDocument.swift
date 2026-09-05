import Foundation
import JavaScriptCore

/// An isolated Yjs v13 XML replica. The host owns authorization, networking and durable storage.
/// All text positions use UTF-16 offsets, matching Yjs and native attributed text APIs.
@MainActor
public final class RelayMarkCollaborationDocument {
    public enum Failure: Error, Equatable { case runtime(String) }
    private let context: JSContext

    public init() throws {
        guard let context = JSContext(),
              let url = Bundle.module.url(forResource: "yjs-runtime", withExtension: "js") else {
            throw Failure.runtime("Collaboration runtime is unavailable")
        }
        self.context = context
        // lib0 needs cryptographic random bytes and UTF-8 codecs in non-browser JavaScriptCore.
        let random: @convention(block) (Int) -> [UInt8] = { count in
            (0..<max(0, min(count, 65536))).map { _ in UInt8.random(in: .min ... .max) }
        }
        let encode: @convention(block) (String) -> [UInt8] = { Array($0.utf8) }
        let decode: @convention(block) ([UInt8]) -> String = { String(decoding: $0, as: UTF8.self) }
        context.setObject(random, forKeyedSubscript: "relayRandom" as NSString)
        context.setObject(encode, forKeyedSubscript: "relayUTF8Encode" as NSString)
        context.setObject(decode, forKeyedSubscript: "relayUTF8Decode" as NSString)
        context.evaluateScript("""
        globalThis.crypto = { getRandomValues(a) { a.set(relayRandom(a.length)); return a; } };
        globalThis.TextEncoder = class { encode(s) { return Uint8Array.from(relayUTF8Encode(s)); } };
        globalThis.TextDecoder = class { decode(a) { return relayUTF8Decode(Array.from(a || [])); } };
        globalThis.setTimeout = () => 0;
        globalThis.clearTimeout = () => {};
        globalThis.relayIntervals = new Map();
        globalThis.setInterval = fn => { const id = relayIntervals.size + 1; relayIntervals.set(id, fn); return id; };
        globalThis.clearInterval = id => relayIntervals.delete(id);
        globalThis.relayRunIntervals = () => { for (const fn of relayIntervals.values()) fn(); };
        """)
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        try checkException()
    }

    /// Applies a remote or restored update without recording it in the local undo stack.
    public func applyUpdate(_ update: Data) throws {
        _ = try call("apply", input: Array(update))
    }

    public func stateVector() throws -> Data { try bytes("vector") }

    /// Full checkpoint when vector is nil; otherwise a missing-update diff, including deletions.
    public func encodeUpdate(since vector: Data? = nil) throws -> Data {
        try bytes("state", input: vector.map { Array($0) } ?? NSNull())
    }

    /// Combines one logical local edit into a single durable update without losing deletions.
    public func mergeUpdates(_ updates: [Data]) throws -> Data {
        try bytes("mergeUpdates", input: updates.map { Array($0) })
    }

    /// Lossless XML tree JSON; unknown nodes and marks remain represented for read-only fallback.
    public func snapshot() throws -> Data { try call("snapshot") }

    /// One validated incremental XML edit. Returned updates must be durably stored by the host
    /// before claiming local save or sending them. The schema is documented in the adapter README.
    public func edit(_ operation: Data) throws -> [Data] {
        let object = try JSONSerialization.jsonObject(with: operation)
        return try updates("edit", input: object)
    }

    public func insertText(_ text: String, at index: Int, path: [Int]) throws -> [Data] {
        try updates("edit", input: ["kind": "insertText", "path": path, "index": index, "text": text])
    }

    public func deleteText(at index: Int, length: Int, path: [Int]) throws -> [Data] {
        try updates("edit", input: ["kind": "deleteText", "path": path, "index": index, "length": length])
    }

    public func replaceProse(start: Int, end: Int, text: String) throws -> [Data] {
        try updates("replaceProse", input: ["start": start, "end": end, "text": text])
    }

    /// Groups one native input transaction, including its formatting, into one selective undo step.
    public func withUndoGroup<T>(_ body: () throws -> T) throws -> T {
        _ = try call("beginUndoGroup")
        defer { _ = try? call("endUndoGroup") }
        return try body()
    }

    public func undo() throws -> [Data] { try updates("undo") }
    public func redo() throws -> [Data] { try updates("redo") }

    public func anchor(path: [Int], index: Int, association: Int = 0) throws -> Data {
        try bytes("anchor", input: ["path": path, "index": index, "association": association])
    }

    public struct Position: Codable, Equatable, Sendable {
        public let path: [Int]
        public let index: Int
        public let association: Int
    }

    public func resolve(anchor: Data) throws -> Position? {
        try JSONDecoder().decode(Position?.self, from: call("resolve", input: Array(anchor)))
    }

    /// Standard y-protocols awareness; ephemeral data must never enter the durable update journal.
    public func setPresence(name: String?, color: String = "#666666", anchor: Data? = nil, head: Data? = nil) throws -> [Data] {
        guard let name else { return try updates("presenceSet") }
        var input: [String: Any] = ["name": String(name.prefix(100)), "color": color]
        if let anchor, let head { input["anchor"] = Array(anchor); input["head"] = Array(head) }
        return try updates("presenceSet", input: input)
    }

    public func applyPresence(_ update: Data, origin: String = "remote") throws {
        _ = try call("presenceApply", input: ["data": Array(update), "origin": origin])
    }

    public func removePresence(origin: String) throws { _ = try call("presenceRemoveOrigin", input: origin) }

    /// The connected host calls every three seconds; y-protocols owns renewal and expiry policy.
    public func advancePresenceClock() throws -> [Data] { try updates("presenceTick") }

    public func clearRemotePresence() throws { _ = try call("presenceClearRemote") }

    public struct Collaborator: Identifiable, Equatable, Sendable {
        public let id: UInt64
        public let name: String
        public let color: String
        public let anchor: Data?
        public let head: Data?
    }

    public func collaborators() throws -> [Collaborator] {
        struct State: Decodable {
            let id: UInt64
            let name: String
            let color: String
            let anchor: [UInt8]?
            let head: [UInt8]?
        }
        return try JSONDecoder().decode([State].self, from: call("presenceStates")).map {
            Collaborator(id: $0.id, name: $0.name, color: $0.color,
                         anchor: $0.anchor.map { Data($0) }, head: $0.head.map { Data($0) })
        }
    }

    private func bytes(_ command: String, input: Any = NSNull()) throws -> Data {
        Data(try JSONDecoder().decode([UInt8].self, from: call(command, input: input)))
    }

    private func updates(_ command: String, input: Any = NSNull()) throws -> [Data] {
        try JSONDecoder().decode([[UInt8]].self, from: call(command, input: input)).map { Data($0) }
    }

    private func call(_ command: String, input: Any = NSNull()) throws -> Data {
        context.exception = nil
        let data = try JSONSerialization.data(withJSONObject: input, options: [.fragmentsAllowed, .sortedKeys])
        guard let function = context.objectForKeyedSubscript("relayCollaborationCall"),
              let result = function.call(withArguments: [command, String(decoding: data, as: UTF8.self)]) else {
            try checkException()
            throw Failure.runtime("No collaboration response")
        }
        try checkException()
        guard let json = result.toString() else { throw Failure.runtime("Invalid collaboration response") }
        return Data(json.utf8)
    }

    private func checkException() throws {
        if let exception = context.exception {
            let message = exception.toString() ?? "JavaScript execution failed"
            context.exception = nil
            throw Failure.runtime(message)
        }
    }
}
