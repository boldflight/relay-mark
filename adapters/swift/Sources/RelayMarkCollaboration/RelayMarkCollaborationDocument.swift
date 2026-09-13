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

    /// Local integration completeness, not proof of authorship, authorization, or
    /// receipt coverage. A state vector alone cannot detect unresolved deletions.
    public struct IntegrationStatus: Codable, Equatable, Sendable {
        public let hasPendingStructs: Bool
        public let hasPendingDeletes: Bool
        public var isComplete: Bool { !hasPendingStructs && !hasPendingDeletes }
    }

    /// Check scratch reconstruction after applying its checkpoint and exact suffix.
    /// Incomplete updates remain retained and can integrate when dependencies arrive.
    public func integrationStatus() throws -> IntegrationStatus {
        try JSONDecoder().decode(IntegrationStatus.self, from: call("integrationStatus"))
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

    public struct ProseLineageResult: Sendable {
        public let updates: [Data]
        public let insertedTextItems: Data
        /// Portable operation/copy evidence JSON; the host must authorize and verify it.
        public let lineage: Data
    }

    /// Plain replacement across top-level, attribute-free paragraphs containing only
    /// XmlText leaves. LF creates paragraphs; existing text marks are preserved.
    /// Unsupported shape, Unicode and bounds fail during preflight before mutation.
    /// Returned copies describe new identities for moved text, not new human authorship.
    /// Persist updates and evidence together; this adapter does not authorize lineage.
    public func replaceProseWithLineage(start: Int, end: Int, text: String) throws -> ProseLineageResult {
        try proseLineage("replaceProseWithLineage", input: ["start": start, "end": end, "text": text])
    }

    /// Binds the actual forward undo item to the host's durable transaction identity.
    /// A no-op does not create a history binding. The host must persist before exposing history.
    public func replaceProseWithLineage(start: Int, end: Int, text: String, operationID: UUID) throws -> ProseLineageResult {
        try proseLineage("replaceProseWithLineage", input: ["start": start, "end": end, "text": text,
            "operation_id": operationID.uuidString.lowercased()])
    }

    /// Uniform bold/italic insertion marks; mixed runs and other rich text stay unsupported.
    public func replaceProseWithLineage(start: Int, end: Int, text: String,
                                       insertedMarks: [RelayMarkLocalTransaction.NativeFormatting.Mark],
                                       operationID: UUID) throws -> ProseLineageResult {
        var attributes: [String: [String: String]] = [:]
        for mark in insertedMarks { attributes[mark.rawValue] = [:] }
        return try proseLineage("replaceProseWithLineage", input: ["start": start, "end": end, "text": text,
            "attributes": attributes, "operation_id": operationID.uuidString.lowercased()])
    }

    /// Restores through the actual tracked history item with copied-identity evidence.
    /// Empty, untracked or mixed history refuses before mutation. Restored text is not new human input.
    public func undoWithLineage(operationID: UUID) throws -> ProseLineageResult {
        try proseLineage("undoWithLineage", input: ["operation_id": operationID.uuidString.lowercased()])
    }

    public func redoWithLineage(operationID: UUID) throws -> ProseLineageResult {
        try proseLineage("redoWithLineage", input: ["operation_id": operationID.uuidString.lowercased()])
    }

    /// Exports the settled standard document and its actual local history stack. The host
    /// binds the token to a qualified durable cut and persists it atomically with updates.
    public func exportHistorySnapshot(scopeToken: String) throws -> Data {
        try call("exportHistorySnapshot", input: ["scope_token": scopeToken])
    }

    /// Restores only into a pristine document, before journal suffix or remote updates.
    /// Mark validates the complete snapshot and requires every stack operation to occur
    /// in the host's exact retained transaction whitelist. Failure leaves the owner pristine.
    public struct SnapshotExport: Sendable {
        public let bytes: Data
        public let transactionIDs: [UUID]
    }

    /// Library-owned receipt closure; callers need not decode private stack metadata.
    public func exportHistoryState(scopeToken: String) throws -> SnapshotExport {
        let bytes = try exportHistorySnapshot(scopeToken: scopeToken)
        struct Stack: Decodable { let operation_id: String }
        struct Wire: Decodable { let undo: [Stack]; let redo: [Stack] }
        let wire = try JSONDecoder().decode(Wire.self, from: bytes)
        let values = wire.undo + wire.redo
        guard values.count <= 16384 else { throw Failure.runtime("History reference limit") }
        var seen = Set<UUID>()
        let ids = try values.map { value -> UUID in
            guard let id = UUID(uuidString: value.operation_id),
                  id.uuidString.lowercased() == value.operation_id, seen.insert(id).inserted else {
                throw Failure.runtime("Invalid history reference")
            }
            return id
        }
        return SnapshotExport(bytes: bytes, transactionIDs: ids)
    }

    public func restoreHistorySnapshot(_ snapshot: Data, scopeToken: String, transactionIDs: [UUID]) throws {
        guard snapshot.count <= 64 * 1024 * 1024, transactionIDs.count <= 16384 else {
            throw Failure.runtime("History snapshot limit")
        }
        _ = try call("restoreHistorySnapshot", input: [
            "snapshot": JSONSerialization.jsonObject(with: snapshot), "scope_token": scopeToken,
            "transaction_ids": transactionIDs.map { $0.uuidString.lowercased() }])
    }

    private func proseLineage(_ command: String, input: [String: Any]) throws -> ProseLineageResult {
        struct Wire: Decodable {
            let updates: [[UInt8]]
            let insertedTextItems: [UInt8]
        }
        let data = try call(command, input: input)
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lineage = object["lineage"] as? [String: Any] else {
            throw Failure.runtime("Missing prose lineage evidence")
        }
        return ProseLineageResult(updates: wire.updates.map { Data($0) },
            insertedTextItems: Data(wire.insertedTextItems),
            lineage: try JSONSerialization.data(withJSONObject: lineage, options: [.sortedKeys]))
    }

    public struct ParagraphInsertionResult: Sendable {
        public let updates: [Data]
        public let evidence: RelayMarkLocalTransaction.NativeParagraph
    }

    /// Explicit Return at the current end of a top-level paragraph containing
    /// one XmlText. Creates one empty paragraph and XmlText without moving old
    /// items. Call outside an undo group; the host must validate native intent,
    /// persist the update/evidence together and apply its source admission policy.
    public func insertParagraphAfter(index: Int, expectedEndUTF16: Int) throws -> ParagraphInsertionResult {
        struct Wire: Decodable {
            let updates: [[UInt8]]
            let evidence: RelayMarkLocalTransaction.NativeParagraph
        }
        let wire = try JSONDecoder().decode(Wire.self, from: call("nativeParagraphAfter",
            input: ["index": index, "endUTF16": expectedEndUTF16]))
        return ParagraphInsertionResult(updates: wire.updates.map { Data($0) }, evidence: wire.evidence)
    }

    public struct ParagraphPasteResult: Sendable {
        public let updates: [Data]
        public let evidence: RelayMarkLocalTransaction.NativeParagraphPaste
        public let insertedTextItems: Data
    }

    /// Plain LF-delimited paste at a top-level paragraph end, outside an undo
    /// group. First line appends to the existing leaf; later lines create real
    /// paragraphs/XmlText, including empty lines. The selection excludes LF.
    /// Rejects CR, hard breaks, embeds, invalid Unicode, more than 131072 UTF-16
    /// input units or 4096 new paragraphs/nonempty lines; never truncates.
    public func insertParagraphTextAfter(index: Int, expectedEndUTF16: Int, text: String) throws -> ParagraphPasteResult {
        struct Wire: Decodable {
            let updates: [[UInt8]]
            let evidence: RelayMarkLocalTransaction.NativeParagraphPaste
            let insertedTextItems: [UInt8]
        }
        let wire = try JSONDecoder().decode(Wire.self, from: call("nativeParagraphPaste",
            input: ["index": index, "endUTF16": expectedEndUTF16, "text": text]))
        return ParagraphPasteResult(updates: wire.updates.map { Data($0) }, evidence: wire.evidence,
                                    insertedTextItems: Data(wire.insertedTextItems))
    }

    /// Groups one native input transaction, including its formatting, into one selective undo step.
    public func withUndoGroup<T>(_ body: () throws -> T) throws -> T {
        _ = try call("beginUndoGroup")
        defer { _ = try? call("endUndoGroup") }
        return try body()
    }

    public func undo() throws -> [Data] { try updates("undo") }
    public func redo() throws -> [Data] { try updates("redo") }

    /// Call only for an explicit native bold/italic command. The isolated history
    /// marker is local operation evidence; it never establishes text authorship.
    public func editNativeFormatting(_ operation: Data) throws -> [Data] {
        try updates("nativeFormatting", input: JSONSerialization.jsonObject(with: operation))
    }

    public func editNativeFormatting(_ operation: Data, operationID: UUID) throws -> [Data] {
        guard var value = try JSONSerialization.jsonObject(with: operation) as? [String: Any],
              value["operation_id"] == nil else { throw Failure.runtime("Invalid formatting operation") }
        value["operation_id"] = operationID.uuidString.lowercased()
        return try updates("nativeFormatting", input: value)
    }

    public struct HistoryEvidenceResult: Sendable {
        public enum Kind: String, Decodable, Sendable { case prose, formatting }
        public let kind: Kind
        public let updates: [Data]
        public let insertedTextItems: Data
        public let proseLineage: Data?
        public let formattingMark: RelayMarkLocalTransaction.NativeFormatting.Mark?
    }

    /// Resolves evidence from the actually performed tracked item. Unsupported,
    /// mixed or ineffective history refuses during preflight without mutation.
    public func undoWithEvidence(operationID: UUID) throws -> HistoryEvidenceResult {
        try historyEvidence(redo: false, operationID: operationID)
    }
    public func redoWithEvidence(operationID: UUID) throws -> HistoryEvidenceResult {
        try historyEvidence(redo: true, operationID: operationID)
    }
    private func historyEvidence(redo: Bool, operationID: UUID) throws -> HistoryEvidenceResult {
        struct Wire: Decodable {
            let kind: HistoryEvidenceResult.Kind
            let updates: [[UInt8]]
            let insertedTextItems: [UInt8]
            let formattingMark: RelayMarkLocalTransaction.NativeFormatting.Mark?
        }
        let data = try call(redo ? "redoWithEvidence" : "undoWithEvidence",
            input: ["operation_id": operationID.uuidString.lowercased()])
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let lineage = object?["lineage"] as? [String: Any]
        guard (wire.kind == .prose && lineage != nil && wire.formattingMark == nil) ||
              (wire.kind == .formatting && lineage == nil && wire.formattingMark != nil) else {
            throw Failure.runtime("Inconsistent history evidence")
        }
        return HistoryEvidenceResult(kind: wire.kind, updates: wire.updates.map { Data($0) },
            insertedTextItems: Data(wire.insertedTextItems),
            proseLineage: try lineage.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) },
            formattingMark: wire.formattingMark)
    }

    public struct FormattingHistoryResult: Sendable {
        public let updates: [Data]
        /// Identifies the actually performed stack item, including skipped no-ops.
        /// Callers must still prove unchanged text identities and bounded mark changes.
        public let formattingMark: RelayMarkLocalTransaction.NativeFormatting.Mark?
    }

    public func undoWithFormattingEvidence() throws -> FormattingHistoryResult { try formattingHistory(redo: false) }
    public func redoWithFormattingEvidence() throws -> FormattingHistoryResult { try formattingHistory(redo: true) }

    private func formattingHistory(redo: Bool) throws -> FormattingHistoryResult {
        struct Wire: Decodable {
            let updates: [[UInt8]]
            let formattingMark: RelayMarkLocalTransaction.NativeFormatting.Mark?
        }
        let wire = try JSONDecoder().decode(Wire.self, from: call(redo ? "redoWithFormattingEvidence" : "undoWithFormattingEvidence"))
        return FormattingHistoryResult(updates: wire.updates.map { Data($0) }, formattingMark: wire.formattingMark)
    }

    public func anchor(path: [Int], index: Int, association: Int = 0) throws -> Data {
        try bytes("anchor", input: ["path": path, "index": index, "association": association])
    }

    public struct Position: Codable, Equatable, Sendable {
        public let path: [Int]
        public let index: Int
        public let association: Int
        public init(path: [Int], index: Int, association: Int = 0) {
            self.path = path; self.index = index; self.association = association
        }
    }

    public func resolve(anchor: Data) throws -> Position? {
        try JSONDecoder().decode(Position?.self, from: call("resolve", input: Array(anchor)))
    }

    /// Portable Yjs endpoints. The host must bind this value to its document, incarnation and schema.
    public struct RelativeRange: Codable, Equatable, Sendable {
        public let version: Int
        public let anchor: Data
        public let head: Data
        public init(anchor: Data, head: Data) throws {
            guard (1...256).contains(anchor.count), (1...256).contains(head.count) else {
                throw Failure.runtime("Invalid relative range byte length")
            }
            self.version = 1; self.anchor = anchor; self.head = head
        }
        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            guard try fields.decode(Int.self, forKey: .version) == 1 else {
                throw DecodingError.dataCorruptedError(forKey: .version, in: fields, debugDescription: "Unsupported relative range version")
            }
            try self.init(anchor: fields.decode(Data.self, forKey: .anchor), head: fields.decode(Data.self, forKey: .head))
        }
    }
    public struct ResolvedRange: Codable, Equatable, Sendable {
        public let anchor: Position
        public let head: Position
    }
    public func relativeRange(anchor: Position, head: Position) throws -> RelativeRange {
        try RelativeRange(anchor: self.anchor(path: anchor.path, index: anchor.index, association: anchor.association),
                          head: self.anchor(path: head.path, index: head.index, association: head.association))
    }
    /// Throws for malformed/noncanonical bytes; returns nil for unknown/deleted shared types.
    /// Portable resolution does not follow local-only undo mappings, keeping replicas consistent.
    public func resolve(range: RelativeRange) throws -> ResolvedRange? {
        try JSONDecoder().decode(ResolvedRange?.self, from: call("resolveRange", input: [
            "version": range.version, "anchor": Array(range.anchor), "head": Array(range.head)]))
    }

    public struct TextItemSegment: Codable, Equatable, Sendable {
        public let path: [Int]
        public let index: Int
        public let length: Int
        public let text: String
    }

    public struct TextItemResolution: Codable, Equatable, Sendable {
        /// Surviving UTF-16 segments in current document order, excluding unrelated insertions.
        public let segments: [TextItemSegment]
        /// Selected identities currently resolving to zero width. This does not authenticate
        /// whether a forged identity originally represented text or a formatting structure.
        public let collapsedUnits: Int
        /// Original run indices whose items or shared types are unavailable/deleted.
        /// Callers must not interpret an incomplete resolution as complete source text.
        public let unavailableRuns: [Int]
    }

    /// Opaque versioned JSON containing exact Yjs text identities, not authorship.
    /// Hosts bind it to the document/incarnation and supply trusted edit intent.
    /// Rejects atoms, more than 131072 UTF-16 units or 4096 fragmented runs.
    public func captureTextItems(path: [Int], index: Int, length: Int) throws -> Data {
        try call("captureTextItems", input: ["path": path, "index": index, "length": length])
    }

    /// Strictly validates exact identity run JSON before resolving. Does not follow local undo mappings.
    /// Unknown or deleted shared types remain explicit, including deleted ancestors.
    public func resolveTextItems(_ selection: Data) throws -> TextItemResolution {
        guard selection.count <= 5_000_000 else { throw Failure.runtime("Text item selection is too large") }
        return try JSONDecoder().decode(TextItemResolution.self, from: call("resolveTextItems",
            input: JSONSerialization.jsonObject(with: selection)))
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

    /// Ephemeral remote awareness with its transport-origin ownership, never durable document data.
    public struct PresenceSnapshot: Codable, Equatable, Sendable {
        public let version: Int
        public let update: Data
        public let origins: [String: [UInt64]]
        public init(version: Int = 1, update: Data, origins: [String: [UInt64]]) {
            self.version = version; self.update = update; self.origins = origins
        }
    }

    public func presenceSnapshot() throws -> PresenceSnapshot {
        struct Wire: Decodable { let version: Int; let update: [UInt8]; let origins: [String: [UInt64]] }
        let value = try JSONDecoder().decode(Wire.self, from: call("presenceSnapshot"))
        return PresenceSnapshot(version: value.version, update: Data(value.update), origins: value.origins)
    }

    public func applyPresenceSnapshot(_ snapshot: PresenceSnapshot) throws {
        _ = try call("presenceApplySnapshot", input: ["version": snapshot.version,
            "update": Array(snapshot.update), "origins": snapshot.origins])
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
