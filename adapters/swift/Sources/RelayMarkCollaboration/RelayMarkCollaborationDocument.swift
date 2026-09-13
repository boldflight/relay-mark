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

    /// Conservative current-document eligibility for native tracked prose history.
    /// This is not authorization or a guarantee that every proposed operation is valid.
    /// Unsupported existing marks/shapes return false without modifying the document.
    public func supportsProseLineage() throws -> Bool {
        try JSONDecoder().decode(Bool.self, from: call("supportsProseLineage"))
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

    public struct AttributedProseResult: Sendable {
        public let evidence: ProseLineageResult
        public let record: Data
        public let replay: AttributionReplay
    }

    public func replaceProseWithAttribution(start: Int, end: Int, text: String,
        operationID: UUID, replay: AttributionReplay) throws -> AttributedProseResult {
        try replaceProseWithAttribution(start: start, end: end, text: text,
            insertedMarks: [], operationID: operationID, replay: replay)
    }

    /// Supported paragraph replacement only; full successor replay is checked before mutation.
    /// Persist the exact candidate with the update and owner snapshot; no authorization is implied.
    public func replaceProseWithAttribution(start: Int, end: Int, text: String,
        insertedMarks: [RelayMarkLocalTransaction.NativeFormatting.Mark], operationID: UUID,
        replay: AttributionReplay) throws -> AttributedProseResult {
        var attributes: [String: [String: String]] = [:]
        for mark in insertedMarks { attributes[mark.rawValue] = [:] }
        var input = try attributionInput(replay)
        input["operation"] = ["start": start, "end": end, "text": text,
            "attributes": attributes, "operation_id": operationID.uuidString.lowercased()]
        let data = try call("replaceProseWithAttribution", input: input)
        let wire = try JSONDecoder().decode(AttributionWire.self, from: data)
        return AttributedProseResult(evidence: try decodeProseLineage(data), record: try decodeAttributionRecord(wire),
            replay: try decodeAttributionReplay(wire, scopeToken: replay.scopeToken, binding: replay.binding))
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

    public struct PlacementBinding: Sendable {
        public let documentID: UUID
        public let incarnation: String
        public init(documentID: UUID, incarnation: String) {
            self.documentID = documentID; self.incarnation = incarnation
        }
        fileprivate var wire: [String: Any] {
            ["document_id": documentID.uuidString.lowercased(), "incarnation": incarnation]
        }
    }

    /// Immutable candidate; save its snapshot with the update before committing it.
    public struct PlacementCandidate: Sendable {
        /// Exact canonical receipt for the associated update row.
        public let receipt: Data
        public let bytes: Data
        public let receiptIDs: [UUID]
    }

    /// Derives the exact last emitted operation, including formatting inverse references.
    /// This proves local runtime identity, not server acceptance or human authorship.
    public func prepareLocalPlacementReceipt(update: Data, binding: PlacementBinding) throws -> PlacementCandidate {
        guard !update.isEmpty, update.count <= 8 * 1024 * 1024 else { throw Failure.runtime("Placement update limit") }
        return try placementCandidate(call("prepareLocalPlacementReceipt", input: [
            "expected_binding": binding.wire, "update": Array(update)]))
    }

    /// The caller must authenticate server receipt authority and its document binding.
    /// Mark validates exact update hash and graph consistency; it does not authenticate.
    public func prepareTrustedPlacementReceipt(_ receipt: Data, update: Data,
                                               binding: PlacementBinding) throws -> PlacementCandidate {
        guard receipt.count <= 64 * 1024 * 1024, !update.isEmpty, update.count <= 8 * 1024 * 1024 else {
            throw Failure.runtime("Placement receipt limit")
        }
        return try placementCandidate(call("preparePlacementReceipt", input: [
            "expected_binding": binding.wire, "trust": "server", "update": Array(update),
            "receipt": JSONSerialization.jsonObject(with: receipt)]))
    }

    public func commitPlacementReceipt(_ candidate: PlacementCandidate) throws {
        _ = try call("commitPlacementReceipt", input: JSONSerialization.jsonObject(with: candidate.bytes))
    }

    public func exportHistorySnapshot(scopeToken: String, placementCandidate: PlacementCandidate) throws -> Data {
        try call("exportHistorySnapshot", input: ["scope_token": scopeToken,
            "placement_candidate": JSONSerialization.jsonObject(with: placementCandidate.bytes)])
    }

    private static func placementIDs(_ value: Any?) throws -> [UUID] {
        guard let state = value as? [String: Any], let rows = state["receipts"] as? [[String: Any]], rows.count <= 16384 else {
            throw Failure.runtime("Invalid placement receipt closure")
        }
        var seen = Set<UUID>()
        return try rows.map { row in
            guard let receipt = row["receipt"] as? [String: Any], let raw = receipt["operation_id"] as? String,
                  let id = UUID(uuidString: raw), id.uuidString.lowercased() == raw, seen.insert(id).inserted else {
                throw Failure.runtime("Invalid placement receipt identity")
            }
            return id
        }
    }

    private func placementCandidate(_ bytes: Data) throws -> PlacementCandidate {
        guard bytes.count <= 64 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw Failure.runtime("Placement candidate limit")
        }
        guard let receipt = object["receipt"] as? [String: Any] else { throw Failure.runtime("Missing placement receipt") }
        return PlacementCandidate(receipt: try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]),
            bytes: bytes, receiptIDs: try Self.placementIDs(object["state"]))
    }

    /// Restores only into a pristine document, before journal suffix or remote updates.
    /// Mark validates the complete snapshot and requires every stack operation to occur
    /// in the host's exact retained transaction whitelist. Failure leaves the owner pristine.
    public struct SnapshotExport: Sendable {
        public let bytes: Data
        public let transactionIDs: [UUID]
        public let placementReceiptIDs: [UUID]
    }

    /// Library-owned receipt closure; callers need not decode private stack metadata.
    public func exportHistoryState(scopeToken: String) throws -> SnapshotExport {
        try snapshotExport(exportHistorySnapshot(scopeToken: scopeToken))
    }

    public func exportHistoryState(scopeToken: String, placementCandidate: PlacementCandidate) throws -> SnapshotExport {
        try snapshotExport(exportHistorySnapshot(scopeToken: scopeToken, placementCandidate: placementCandidate))
    }

    private func snapshotExport(_ bytes: Data) throws -> SnapshotExport {
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
        let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        let placements = try object?["placement"].map(Self.placementIDs) ?? []
        return SnapshotExport(bytes: bytes, transactionIDs: ids, placementReceiptIDs: placements)
    }

    public func restoreHistorySnapshot(_ snapshot: Data, scopeToken: String, transactionIDs: [UUID]) throws {
        guard snapshot.count <= 64 * 1024 * 1024, transactionIDs.count <= 16384 else {
            throw Failure.runtime("History snapshot limit")
        }
        _ = try call("restoreHistorySnapshot", input: [
            "snapshot": JSONSerialization.jsonObject(with: snapshot), "scope_token": scopeToken,
            "transaction_ids": transactionIDs.map { $0.uuidString.lowercased() }])
    }

    public func restoreHistorySnapshot(_ snapshot: Data, scopeToken: String, transactionIDs: [UUID],
                                       placementBinding: PlacementBinding, placementReceiptIDs: [UUID]) throws {
        guard snapshot.count <= 64 * 1024 * 1024, transactionIDs.count <= 16384, placementReceiptIDs.count <= 16384 else {
            throw Failure.runtime("History snapshot limit")
        }
        _ = try call("restoreHistorySnapshot", input: [
            "snapshot": JSONSerialization.jsonObject(with: snapshot), "scope_token": scopeToken,
            "transaction_ids": transactionIDs.map { $0.uuidString.lowercased() },
            "expected_placement_binding": placementBinding.wire,
            "placement_receipt_ids": placementReceiptIDs.map { $0.uuidString.lowercased() }])
    }

    private func proseLineage(_ command: String, input: [String: Any]) throws -> ProseLineageResult {
        return try decodeProseLineage(call(command, input: input))
    }

    private func decodeProseLineage(_ data: Data) throws -> ProseLineageResult {
        struct Wire: Decodable {
            let updates: [[UInt8]]
            let insertedTextItems: [UInt8]
        }
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

    /// Exact replay bytes with assertions independently authenticated by the host.
    /// These values do not establish app/account authorization. The host must persist
    /// a returned candidate atomically with its original update rows and owner snapshot.
    public struct AttributionReplay: Sendable {
        public let bytes: Data
        public let scopeToken: String
        public let binding: PlacementBinding
        public let digest: String
        public let cut: String

        public init(bytes: Data, scopeToken: String, binding: PlacementBinding,
                    digest: String, cut: String) throws {
            guard !bytes.isEmpty, bytes.count <= 64 * 1024 * 1024,
                  let json = String(data: bytes, encoding: .utf8), Data(json.utf8) == bytes,
                  !scopeToken.isEmpty, scopeToken.utf8.count <= 2048,
                  !binding.incarnation.isEmpty, binding.incarnation.utf8.count <= 256,
                  RelayMarkCollaborationDocument.isAttributionSHA256(digest),
                  RelayMarkCollaborationDocument.isAttributionSHA256(cut) else {
                throw Failure.runtime("Invalid attributed history replay assertions")
            }
            self.bytes = bytes; self.scopeToken = scopeToken; self.binding = binding
            self.digest = digest; self.cut = cut
        }
    }

    /// Compact exact-record integrity envelope. It is not authorship, authentication,
    /// or full formatting-witness validation; the host qualifies the associated row.
    public struct AttributionRecordSidecar: Sendable {
        public let bytes: Data
        public let digest: String
        public let recordDigest: String
        public let updateDigest: String
        public let operationID: UUID
    }

    /// Packs only compact JSON.stringify-produced runtime records. Whitespace
    /// variants refuse rather than changing the original record's exact bytes.
    public func packAttributionRecord(_ record: Data, update: Data) throws -> AttributionRecordSidecar {
        let json = try Self.attributionJSONString(record)
        try Self.validateAttributionUpdate(update)
        struct Wire: Decodable {
            let sidecar_json: String
            let sidecar_sha256: String
            let record_sha256: String
            let update_sha256: String
            let operation_id: String
        }
        let wire = try JSONDecoder().decode(Wire.self, from: call("packAttributionRecord", input: [
            "record_json": json, "update": Array(update)
        ]))
        guard Self.isAttributionSHA256(wire.sidecar_sha256), Self.isAttributionSHA256(wire.record_sha256),
              Self.isAttributionSHA256(wire.update_sha256), let operationID = UUID(uuidString: wire.operation_id),
              operationID.uuidString.lowercased() == wire.operation_id,
              !wire.sidecar_json.isEmpty, wire.sidecar_json.utf8.count <= 64 * 1024 * 1024 else {
            throw Failure.runtime("Invalid attribution record sidecar")
        }
        return AttributionRecordSidecar(bytes: Data(wire.sidecar_json.utf8), digest: wire.sidecar_sha256,
            recordDigest: wire.record_sha256, updateDigest: wire.update_sha256, operationID: operationID)
    }

    /// The digest must come independently from the host's qualified durable row.
    /// This checks exact reconstruction/integrity, not authority or witness semantics.
    public func unpackAttributionRecord(_ sidecar: Data, update: Data, expectedDigest: String,
                                         operationID: UUID) throws -> Data {
        let json = try Self.attributionJSONString(sidecar)
        try Self.validateAttributionUpdate(update)
        guard Self.isAttributionSHA256(expectedDigest) else {
            throw Failure.runtime("Invalid attribution sidecar digest")
        }
        struct Wire: Decodable { let record_json: String }
        let wire = try JSONDecoder().decode(Wire.self, from: call("unpackAttributionRecord", input: [
            "sidecar_json": json, "update": Array(update),
            "expected": ["sidecar_sha256": expectedDigest, "operation_id": operationID.uuidString.lowercased()]
        ]))
        guard !wire.record_json.isEmpty, wire.record_json.utf8.count <= 64 * 1024 * 1024 else {
            throw Failure.runtime("Missing or oversized attribution record")
        }
        return Data(wire.record_json.utf8)
    }

    private nonisolated static func isAttributionSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private nonisolated static func attributionJSONString(_ bytes: Data) throws -> String {
        guard !bytes.isEmpty, bytes.count <= 64 * 1024 * 1024,
              let json = String(data: bytes, encoding: .utf8), Data(json.utf8) == bytes else {
            throw Failure.runtime("Invalid attribution JSON UTF-8 or size")
        }
        return json
    }

    private nonisolated static func validateAttributionUpdate(_ update: Data) throws {
        guard !update.isEmpty, update.count <= 8 * 1024 * 1024 else {
            throw Failure.runtime("Invalid attribution update size")
        }
    }

    /// Candidate evidence and exact successor replay; not yet a durable host save.
    public struct AttributedHistoryResult: Sendable {
        public let evidence: HistoryEvidenceResult
        /// Exact single replay step for the corresponding durable update row.
        public let record: Data
        public let replay: AttributionReplay
    }

    /// Forward update and exact replay-step candidate; the host owns atomic persistence.
    public struct AttributedEditResult: Sendable {
        public let updates: [Data]
        public let record: Data
        public let replay: AttributionReplay
    }

    /// Creates a local attribution baseline before this owner has undo/redo history.
    /// The host supplies the scope/binding and authenticates subsequent stored assertions.
    public func createAttributionReplay(scopeToken: String, binding: PlacementBinding) throws -> AttributionReplay {
        let wire = try JSONDecoder().decode(AttributionWire.self, from: call("createAttributionReplay", input: [
            "scope_token": scopeToken, "binding": binding.wire
        ]))
        return try decodeAttributionReplay(wire, scopeToken: scopeToken, binding: binding)
    }

    /// Executes explicit native formatting with an independently authenticated replay.
    /// Save the exact record, updates, successor replay and owner snapshot atomically.
    public func editNativeFormattingWithAttribution(_ operation: Data, operationID: UUID,
                                                     replay: AttributionReplay) throws -> AttributedEditResult {
        guard var value = try JSONSerialization.jsonObject(with: operation) as? [String: Any],
              value["operation_id"] == nil else { throw Failure.runtime("Invalid formatting operation") }
        value["operation_id"] = operationID.uuidString.lowercased()
        var input = try attributionInput(replay)
        input["operation"] = value
        let data = try call("nativeFormattingWithAttribution", input: input)
        struct Updates: Decodable { let updates: [[UInt8]] }
        let updates = try JSONDecoder().decode(Updates.self, from: data)
        let wire = try JSONDecoder().decode(AttributionWire.self, from: data)
        return AttributedEditResult(updates: updates.updates.map { Data($0) }, record: try decodeAttributionRecord(wire),
            replay: try decodeAttributionReplay(wire, scopeToken: replay.scopeToken, binding: replay.binding))
    }

    /// The host supplies independently verified replay assertions for this owner.
    /// Persist the returned replay with the updates and snapshot before claiming save.
    public func undoWithAttributedEvidence(operationID: UUID, referenceID: UUID,
                                           replay: AttributionReplay) throws -> AttributedHistoryResult {
        try attributedHistoryEvidence(redo: false, operationID: operationID, referenceID: referenceID, replay: replay)
    }

    public func redoWithAttributedEvidence(operationID: UUID, referenceID: UUID,
                                           replay: AttributionReplay) throws -> AttributedHistoryResult {
        try attributedHistoryEvidence(redo: true, operationID: operationID, referenceID: referenceID, replay: replay)
    }

    /// Conservative current-formatting dispatch. Unknown, prose, skipped or ineffective
    /// tops refuse unchanged; this is not general actionable history selection.
    public func undoWithAttributedEvidence(operationID: UUID, replay: AttributionReplay) throws -> AttributedHistoryResult {
        try attributedHistoryEvidence(redo: false, operationID: operationID, referenceID: nil, replay: replay)
    }

    public func redoWithAttributedEvidence(operationID: UUID, replay: AttributionReplay) throws -> AttributedHistoryResult {
        try attributedHistoryEvidence(redo: true, operationID: operationID, referenceID: nil, replay: replay)
    }

    private func attributedHistoryEvidence(redo: Bool, operationID: UUID, referenceID: UUID?,
                                           replay: AttributionReplay) throws -> AttributedHistoryResult {
        var input = try attributionInput(replay)
        input["operation_id"] = operationID.uuidString.lowercased()
        if let referenceID { input["reference_id"] = referenceID.uuidString.lowercased() }
        let data = try call(redo ? "redoWithAttributedEvidence" : "undoWithAttributedEvidence", input: input)
        let wire = try JSONDecoder().decode(AttributionWire.self, from: data)
        return AttributedHistoryResult(evidence: try decodeHistoryEvidence(data), record: try decodeAttributionRecord(wire),
            replay: try decodeAttributionReplay(wire, scopeToken: replay.scopeToken, binding: replay.binding))
    }

    /// Read-only full replay validation against this document and independently saved assertions.
    public func validateAttributionReplay(_ replay: AttributionReplay) throws {
        _ = try call("validateAttributionReplay", input: attributionInput(replay))
    }

    /// Validates the entire successor recipe before applying one ordered peer update,
    /// using remote origin so it does not create a local undo item. The host must first
    /// authenticate the exact record through its qualified row/codec and persist the
    /// returned replay with the owner snapshot atomically. This does not authorize a peer.
    public func applyAttributionRecord(_ record: Data, replay: AttributionReplay) throws -> AttributionReplay {
        var input = try attributionInput(replay)
        input["record_json"] = try Self.attributionJSONString(record)
        let wire = try JSONDecoder().decode(AttributionWire.self, from: call("applyAttributionRecord", input: input))
        return try decodeAttributionReplay(wire, scopeToken: replay.scopeToken, binding: replay.binding)
    }

    private func attributionInput(_ replay: AttributionReplay) throws -> [String: Any] {
        guard let json = String(data: replay.bytes, encoding: .utf8) else {
            throw Failure.runtime("Invalid attributed history replay UTF-8")
        }
        return ["replay_json": json,
                "expected": ["scope_token": replay.scopeToken, "binding": replay.binding.wire,
                             "replay_sha256": replay.digest, "cut": replay.cut]]
    }

    private struct AttributionWire: Decodable {
        let replay_json: String
        let replay_sha256: String
        let cut: String
        let record_json: String?
    }

    private func decodeAttributionReplay(_ wire: AttributionWire, scopeToken: String,
                                         binding: PlacementBinding) throws -> AttributionReplay {
        guard wire.replay_json.utf8.count <= 64 * 1024 * 1024 else {
            throw Failure.runtime("Attributed history replay limit")
        }
        return try AttributionReplay(bytes: Data(wire.replay_json.utf8),
            scopeToken: scopeToken, binding: binding, digest: wire.replay_sha256, cut: wire.cut)
    }

    private func decodeAttributionRecord(_ wire: AttributionWire) throws -> Data {
        guard let record = wire.record_json, !record.isEmpty, record.utf8.count <= 64 * 1024 * 1024 else {
            throw Failure.runtime("Missing or oversized attributed history record")
        }
        // Preserve the runtime's exact UTF-8 JSON string, not a re-encoded object.
        return Data(record.utf8)
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
        try decodeHistoryEvidence(call(redo ? "redoWithEvidence" : "undoWithEvidence",
            input: ["operation_id": operationID.uuidString.lowercased()]))
    }

    private func decodeHistoryEvidence(_ data: Data) throws -> HistoryEvidenceResult {
        struct Wire: Decodable {
            let kind: HistoryEvidenceResult.Kind
            let updates: [[UInt8]]
            let insertedTextItems: [UInt8]
            let formattingMark: RelayMarkLocalTransaction.NativeFormatting.Mark?
        }
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
