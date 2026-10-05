import Foundation
import CoreFoundation
import CryptoKit
import RelayMarkProseProjection
import YSwift
import RelayMarkSwift

/// RelayMark's portable XML projection over the community YSwift/Yrs document.
/// Authorization, persistence, transport, and UI remain with the host.
@MainActor
public final class RelayMarkNativeDocument {
    public struct Position: Codable, Equatable, Sendable {
        public let path: [Int]
        public let index: Int
        public let association: Int

        public init(path: [Int], index: Int, association: Int = 0) {
            self.path = path
            self.index = index
            self.association = association
        }
    }

    public enum Failure: Error {
        case unsupportedXMLNode(String)
        case invalidTextPath
        case invalidUTF16Range
        case invalidAnchor
        case unsupportedProseEdit
        case unboundOwnedHistory
        case conflictingOwnedCommand
    }

    private let document: YDocument
    private let root: YXmlNode
    private let metadata: YMap<RelayMarkValue>
    private let localOrigin: Origin
    private var undoManager: YUndoManager<NSObject>
    public let presence: RelayMarkNativePresence
    /// Stable identity of this actual manager, supplied by its persisted journal on restore.
    public let historyOwnerID: UUID
    private var historySubscriptions: [YSubscription] = []
    private var ownedOperationID: UUID?
    private final class HistoryCapture {
        var inverseMetadata: [NSMutableData] = []
        var operations: [UUID]?
    }
    private var historyCapture: HistoryCapture?

    public init(guid: String = UUID().uuidString, retainDeletedItems: Bool = true, historyOwnerID: UUID = UUID()) {
        let document = YDocument(guid:guid,retainDeletedItems:retainDeletedItems)
        let root = document.getOrCreateXmlFragment(named: "default")
        let metadata: YMap<RelayMarkValue> = document.getOrCreateMap(named:"relaymark")
        let origin = Origin(UUID().uuidString)
        let undoManager: YUndoManager<NSObject> = document.undoManager(trackedRefs: [root,metadata])
        undoManager.addOrigin(origin)
        undoManager.preserveChangedXML()
        self.historyOwnerID = historyOwnerID
        self.document = document
        self.root = root
        self.metadata = metadata
        localOrigin = origin
        self.undoManager = undoManager
        presence = RelayMarkNativePresence(awareness: document.makeAwareness())
        installHistoryObservers()
    }

    /// Maintained identities and full rich runs, including authored envelope
    /// metadata, without a host traversal or text-diff reconstruction.
    public func captureIdentitySnapshot() throws -> Data {
        _ = try authoredDocument()
        var tree=try JSONSerialization.jsonObject(with:document.inspectXMLSnapshot()) as! [String:Any]
        let envelope=metadata.toMap()
        if !envelope.isEmpty {tree["metadata"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(envelope))}
        return try JSONSerialization.data(withJSONObject:tree,options:[.sortedKeys])
    }
    /// The exact original update's allocated/deleted/hidden items and maintained
    /// clocks. Empty update bytes obtain a trusted vector without a wire decoder.
    public func captureUpdateFootprint(_ update: Data) throws -> Data {
        _ = try authoredDocument()
        return try document.inspectUpdateFootprint(update)
    }

    /// Exact upstream sender Snapshot bytes from this same settled retained owner.
    public func captureSenderSnapshot() throws -> Data {
        _ = try authoredDocument()
        return try document.stateSnapshot()
    }

    /// Actual visible UTF-16 item identities on this canonical rich document.
    /// Positions count text units, including both units of a surrogate pair.
    public func captureTextItems(path: [Int], start: Int, length: Int) throws -> Data {
        _ = try authoredDocument()
        guard let start = UInt32(exactly: start), let length = UInt32(exactly: length) else { throw Failure.invalidUTF16Range }
        let data = try document.transactSync { tx in
            var node = self.root
            for index in path {
                guard let index = UInt32(exactly:index), let child = node.child(at:index,in:tx) else { throw Failure.invalidTextPath }
                node = child
            }
            return try node.textItems(start:start,length:length,in:tx)
        }
        var envelope = try JSONSerialization.jsonObject(with:data) as! [String:Any]
        envelope["contract_version"] = RelayMarkContract.version; envelope["kind"] = "text_items"
        return try JSONSerialization.data(withJSONObject:envelope,options:[.sortedKeys])
    }

    /// Captures every visible rich XML string identity in one maintained bounded
    /// traversal. A supplied pre-state vector returns only newly allocated visible
    /// identities, including independent nested widget edits. Deleted ancestors and
    /// format markers are excluded; the host still proves authorship/copy witnesses.
    public func captureVisibleTextItems(since stateVector: Data? = nil) throws -> Data {
        _ = try authoredDocument()
        let data = try document.inspectVisibleTextItems(since:stateVector ?? Data([0]),rootName:"default")
        var envelope = try JSONSerialization.jsonObject(with:data) as! [String:Any]
        envelope["contract_version"] = RelayMarkContract.version
        envelope["kind"] = "text_items"
        return try JSONSerialization.data(withJSONObject:envelope,options:[.sortedKeys])
    }

    /// Exact causal evidence for one bold/italic update against this unchanged
    /// prestate. Immutable record authentication remains the host's responsibility.
    public func captureFormatEvent(update: Data, mark: String, textItems: Data, operationID: UUID) throws -> Data {
        _ = try authoredDocument()
        guard ["bold","italic"].contains(mark),
              let selection = try JSONSerialization.jsonObject(with:textItems) as? [String:Any],
              Set(selection.keys) == ["contract_version","kind","runs"],
              selection["contract_version"] as? Int == RelayMarkContract.version,
              selection["kind"] as? String == "text_items", let runs = selection["runs"] as? [[String:Any]] else { throw Failure.unsupportedProseEdit }
        let bare = try JSONSerialization.data(withJSONObject:["runs":runs],options:[.sortedKeys])
        let result = try document.inspectFormatEvent(update:update,attribute:mark,textItems:bare)
        var event = try JSONSerialization.jsonObject(with:result) as! [String:Any]
        // Observe the full rich tree to refuse a claimed selection that hides
        // actual enabled-state changes to unrelated text.
        let all = try JSONSerialization.jsonObject(with:captureVisibleTextItems()) as! [String:Any]
        let allBare = try JSONSerialization.data(withJSONObject:["runs":all["runs"]!],options:[.sortedKeys])
        let whole = try JSONSerialization.jsonObject(with:document.inspectFormatEvent(update:update,attribute:mark,textItems:allBare)) as! [String:Any]
        let changes = event["changes"] as! [[String:Any]]
        func identity(_ unit: Any) throws -> Data { try JSONSerialization.data(withJSONObject:unit,options:[.sortedKeys]) }
        let selected = try Set(changes.map { try identity($0["unit"]!) })
        func enabled(_ state: [String:Any]) throws -> Bool {
            if state["value"] is NSNull { return false }
            guard let value = state["value"] as? [String:Any], value.isEmpty else { throw Failure.unsupportedProseEdit }
            return true
        }
        for change in whole["changes"] as! [[String:Any]] where try !selected.contains(identity(change["unit"]!)) {
            guard try enabled(change["before"] as! [String:Any]) == enabled(change["after"] as! [String:Any]) else { throw Failure.unsupportedProseEdit }
        }
        event["changes"] = try changes.map { change -> [String:Any] in
            let before = change["before"] as! [String:Any], after = change["after"] as! [String:Any]
            return ["unit":change["unit"]!,"before":["marker":before["marker"]!,"enabled":try enabled(before)],"after":["marker":after["marker"]!,"enabled":try enabled(after)]]
        }
        event["contract_version"] = RelayMarkContract.version;event["kind"] = "format_event"
        event["operation_id"] = operationID.uuidString.lowercased();event["mark"] = mark
        event["update_sha256"] = SHA256.hash(data:update).map { String(format:"%02x",$0) }.joined()
        event["text_items"] = ["runs":runs]
        return try JSONSerialization.data(withJSONObject:event,options:[.sortedKeys])
    }

    /// Immediate maintained undo/redo ancestry. Capture before checkpointing and
    /// retain it in the host's immutable operation journal; wire bytes lack redone links.
    public func captureRestoredTextItems(since stateVector: Data) throws -> Data {
        _ = try authoredDocument()
        return try document.inspectRestoredTextItems(since:stateVector,rootName:"default")
    }

    /// Capture intent before mutation using the same rich text owner and upstream
    /// RelativePosition JSON as browser/headless operations. No flat-text indexing.
    public func captureReplaceProseOperation(start: Position, end: Position, text: String,
                                             attributes: [String:Any] = [:]) throws -> Data {
        _ = try authoredDocument()
        guard (start.path==end.path && start.index<=end.index) || start.path.lexicographicallyPrecedes(end.path),
              JSONSerialization.isValidJSONObject(attributes) else { throw Failure.unsupportedProseEdit }
        let typeIdentities = try document.transactSync { tx -> [[String:Any]] in
            var types:[[String:Any]]=[]
            for position in [start,end] {
                var node=self.root
                for index in position.path {
                    guard let index=UInt32(exactly:index),let child=node.child(at:index,in:tx) else {throw Failure.invalidTextPath}
                    node=child
                }
                guard node.kind(in:tx)=="text" else {throw Failure.invalidTextPath}
                let units=Array(try node.text(in:tx).utf16)
                guard position.index>=0,position.index<=units.count else {throw Failure.invalidUTF16Range}
                if position.index>0 && position.index<units.count && (0xd800...0xdbff).contains(units[position.index-1]) && (0xdc00...0xdfff).contains(units[position.index]) {throw Failure.invalidUTF16Range}
                // Binary item anchors omit parent type. The maintained end-of-type
                // anchor supplies that exact binding without scanning text per unit.
                let typeAnchor=try node.relativePosition(at:node.length(in:tx),association:0,in:tx)
                guard let identity=try YDocument.relativePositionJSON(from:typeAnchor)["type"] as? [String:Any] else {throw Failure.invalidAnchor}
                types.append(identity)
            }
            return types
        }
        // The shared grammar validates typing marks/links, including exclusivity,
        // without inventing another application mark allowlist or changing this owner.
        try RelayMarkSourceCodec.validateTextAttributes(attributes)
        let a=try anchor(path:start.path,index:start.index,association:start.association)
        let b=try anchor(path:end.path,index:end.index,association:end.association)
        var startJSON=try YDocument.relativePositionJSON(from:a),endJSON=try YDocument.relativePositionJSON(from:b)
        startJSON["type"]=typeIdentities[0];endJSON["type"]=typeIdentities[1]
        let operation:[String:Any]=["kind":"replace_prose","start_anchor":startJSON,"end_anchor":endJSON,"inserted_text":text,"inserted_attributes":attributes]
        return try JSONSerialization.data(withJSONObject:operation,options:[.sortedKeys])
    }

    public var documentGUID: String { document.guid }

    /// One scoped retained Yrs checkpoint. The host owns authorization and durable storage.
    public func exportHistoryState(scopeToken: String) throws -> Data {
        let archive = try undoManager.exportHistory(scopeToken:scopeToken) { object in
            guard let data=object as? NSData else { throw Failure.unsupportedProseEdit }
            return data as Data
        }
        return try JSONSerialization.data(withJSONObject:[
            "contract_version":RelayMarkContract.version,"kind":"prosemirror_history",
            "owner_id":historyOwnerID.uuidString.lowercased(),
            "history":JSONSerialization.jsonObject(with:archive.data)
        ],options:[.sortedKeys])
    }

    /// Load the checkpoint update before restoring stacks; integrate newer peer updates afterward.
    public static func historyDocumentState(_ state: Data) throws -> Data { try historyArchive(state).documentState }
    public static func historyDocumentGUID(_ state: Data) throws -> String { try historyArchive(state).documentGUID }
    public static func historyOwner(_ state: Data) throws -> UUID {
        _ = try historyArchive(state)
        let value = try JSONSerialization.jsonObject(with:state) as! [String:Any]
        return UUID(uuidString:value["owner_id"] as! String)!
    }

    public struct RetainedHistoryImport: Sendable {
        public let originalState: Data
        public let state: Data
        public let normalizations: Data
    }

    /// Explicit finite conversion of saved single-command receipt metadata.
    /// Preserve originalState durably before installing state. Unknown metadata
    /// remains unbound evidence; it never becomes an owned command receipt.
    public static func importRetainedHistoryState(_ state: Data, historyOwnerID: UUID) throws -> RetainedHistoryImport {
        guard var envelope = try JSONSerialization.jsonObject(with:state) as? [String:Any],
              Set(envelope.keys)==["contract_version","kind","history"] || Set(envelope.keys)==["contract_version","kind","history","owner_id"],
              envelope["kind"] as? String == "prosemirror_history",
              let version=envelope["contract_version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),version.doubleValue==Double(RelayMarkContract.version),
              var archive=envelope["history"] as? [String:Any],let metadata=archive["metadata"] as? [Any] else {throw Failure.unsupportedProseEdit}
        var changes:[[String:Any]]=[]
        _ = try YUndoHistoryArchive(data:JSONSerialization.data(withJSONObject:archive,options:[.sortedKeys]))
        let owner = historyOwnerID.uuidString.lowercased()
        if let old=envelope["owner_id"] {guard old as? String == owner else {throw Failure.conflictingOwnedCommand}}
        else {envelope["owner_id"]=owner;changes.append(["path":["owner_id"],"operation":"history_owner","value":owner])}
        archive["metadata"] = try metadata.enumerated().map { index,value -> Any in
            guard let object=value as? [String:Any] else {return value}
            if Set(object.keys)==["operation_id"] {
                guard let text=object["operation_id"] as? String,let id=UUID(uuidString:text) else {throw Failure.unboundOwnedHistory}
                changes.append(["path":["history","metadata",index],"operation":"owned_command_group"])
                return ["owner_id":owner,"operation_ids":[id.uuidString.lowercased()]]
            }
            if Set(object.keys)==["operation_ids"] {
                var current=object;current["owner_id"]=owner
                guard operationReferences(current,ownerID:historyOwnerID) != nil else {throw Failure.unboundOwnedHistory}
                changes.append(["path":["history","metadata",index,"owner_id"],"operation":"history_owner","value":owner])
                return current
            }
            return value
        }
        envelope["history"] = archive
        let imported = changes.isEmpty ? state : try JSONSerialization.data(withJSONObject:envelope,options:[.sortedKeys])
        _ = try historyArchive(imported)
        return RetainedHistoryImport(originalState:state,state:imported,normalizations:try JSONSerialization.data(withJSONObject:changes,options:[.sortedKeys]))
    }

    /// Rejection preserves the current document and manager. No reconstruction or second engine.
    public func restoreHistoryState(_ state: Data, scopeToken: String) throws {
        let archive = try Self.historyArchive(state)
        guard try Self.historyOwner(state) == historyOwnerID else {throw Failure.conflictingOwnedCommand}
        let manager: YUndoManager<NSObject> = try document.restoreUndoManager(
            trackedRefs:[root,metadata],history:archive,scopeToken:scopeToken,
            decodeMetadata:{ $0 as NSData })
        manager.addOrigin(localOrigin)
        manager.preserveChangedXML()
        historySubscriptions.forEach { $0.cancel() }
        undoManager=manager
        installHistoryObservers()
    }

    private static func historyArchive(_ state: Data) throws -> YUndoHistoryArchive {
        guard let value=try JSONSerialization.jsonObject(with:state) as? [String:Any],
              Set(value.keys)==["contract_version","kind","history","owner_id"],
              let owner=value["owner_id"] as? String,let ownerID=UUID(uuidString:owner),ownerID.uuidString.lowercased()==owner,
              let version=value["contract_version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),version.doubleValue==Double(RelayMarkContract.version),
              value["kind"] as? String=="prosemirror_history",let archive=value["history"] as? [String:Any] else { throw Failure.unsupportedProseEdit }
        if let values=archive["metadata"] as? [Any] {
            for item in values {
                if let object=item as? [String:Any],object["owner_id"] != nil || object["operation_ids"] != nil || object["operation_id"] != nil {
                    guard operationReferences(object,ownerID:ownerID) != nil else {throw Failure.conflictingOwnedCommand}
                }
            }
        }
        return try YUndoHistoryArchive(data:JSONSerialization.data(withJSONObject:archive,options:[.sortedKeys]))
    }

    private var undoGroupDepth = 0

    /// Closes the current undo item unless an enclosing group is open.
    private func wrapUndo() {
        if undoGroupDepth == 0 && ownedOperationID == nil { undoManager.wrap() }
    }

    /// Runs several local edits as one undo item, as one ProseMirror
    /// transaction would be (for example deleting a selection, then Return).
    public func groupingUndo<T>(_ body: () throws -> T) rethrows -> T {
        wrapUndo()
        undoGroupDepth += 1
        defer {
            undoGroupDepth -= 1
            wrapUndo()
        }
        return try body()
    }

    public func applyUpdate(_ update: Data) throws {
        try document.transactSync { transaction in
            try transaction.transactionApplyUpdate(update: Array(update))
        }
    }

    public func stateVector() -> Data {
        Data(document.transactSync { $0.transactionStateVector() })
    }

    /// Yrs can retain updates or deletes whose predecessors have not arrived.
    /// A usable-looking XML snapshot alone does not prove replay completeness.
    public struct IntegrationStatus: Equatable, Sendable {
        public let hasPendingStructs: Bool
        public let hasPendingDeletes: Bool
        public var isComplete: Bool { !hasPendingStructs && !hasPendingDeletes }
    }

    public func integrationStatus() -> IntegrationStatus {
        let status = document.integrationStatus()
        return IntegrationStatus(hasPendingStructs: status.hasPendingStructs,
                                 hasPendingDeletes: status.hasPendingDeletes)
    }

    /// A complete Yjs update when `vector` is nil, otherwise the missing diff.
    public func encodeUpdate(since vector: Data? = nil) throws -> Data {
        try Data(document.transactSync { transaction in
            if let vector {
                return try transaction.transactionEncodeStateAsUpdateFromSv(stateVector: Array(vector))
            }
            return transaction.transactionEncodeStateAsUpdate()
        })
    }

    public func mergeUpdates(_ updates: [Data]) throws -> Data {
        try YDocument.mergeUpdatesV1(updates)
    }

    /// Read community deletion metadata; callers must distinguish original
    /// updates from reconstructed state before interpreting sender observation.
    public static func hasAdditionalDeletionsV1(before: Data, after: Data, declaredBy: Data) throws -> Bool {
        try YDocument.hasAdditionalDeletionsV1(before: before, after: after, declaredBy: declaredBy)
    }

    /// The same lossless XML JSON shape used by the existing collaboration adapter.
    public func snapshot() throws -> Data {
        var object = try snapshot(root)
        let envelope = metadata.toMap()
        guard Set(envelope.keys).isSubset(of:["frontmatter","annotations","resources","meta"]) else { throw Failure.unsupportedProseEdit }
        if !envelope.isEmpty { object["metadata"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(envelope)) }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Initializes authored AST once, in the same Yrs transaction as its envelope.
    /// Existing rich replicas must retain their item identities and use incremental commands.
    @discardableResult public func initializeDocument(authoredAST: Data) throws -> Data {
        guard root.length()==0,metadata.isEmpty else { throw Failure.unsupportedProseEdit }
        let portable = try RelayMarkSourceCodec.documentToSnapshot(authoredAST)
        guard let object = try JSONSerialization.jsonObject(with:portable) as? [String:Any],
              let nodes = object["children"] as? [[String:Any]] else { throw Failure.unsupportedProseEdit }
        let envelopeData = try JSONSerialization.data(withJSONObject:object["metadata"] ?? [:])
        let envelope = try JSONDecoder().decode([String:RelayMarkValue].self,from:envelopeData)
        return try replaceSnapshotNodes([SnapshotNodeReplacement(parentPath:[],start:0,count:0,nodes:nodes)],metadataUpdates:envelope,origin:Origin("relaymark.initialization"))
    }
    public func authoredDocument() throws -> Data { try RelayMarkSourceCodec.snapshotToDocument(snapshot()) }

    public func proseProjection() throws -> RelayMarkCollaborativeProse {
        try RelayMarkCollaborativeProse(snapshot: snapshot())
    }

    /// Basic canonical Markdown read/selection map after strict whole-document AST
    /// validation. Tables and other unsupported presentation shapes stay gated.
    public func richProseProjection() throws -> RelayMarkCollaborativeProse {
        _ = try RelayMarkNativeDocumentProjection.project(document: self)
        return try RelayMarkCollaborativeProse(snapshot: snapshot(), dialect: .rich)
    }

    /// One quote with one or two flat paragraphs; no wrapping, splitting or joins.
    public func supportsQuoteEditing() -> Bool { (try? quoteParagraphs()) != nil }

    private func quoteParagraphs() throws -> [(node: YXmlNode, text: String)] {
        guard integrationStatus().isComplete else { throw Failure.unsupportedProseEdit }
        return try RelayMarkNativeQuote.paragraphs(root: root, projection: proseProjection())
    }

    /// Insert a second empty paragraph without relocating any existing content.
    /// The host must require a collapsed caret at the end of the first paragraph.
    public func appendEmptyQuoteParagraph(after paragraphAnchor: Data) throws -> Data {
        let paragraphs = try quoteParagraphs()
        let (_, path) = try anchoredElement(paragraphAnchor)
        guard paragraphs.count == 1, !paragraphs[0].text.isEmpty, path == [0, 0],
              let quote = root.child(at: 0) else { throw Failure.unsupportedProseEdit }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            _ = try quote.insertElement(named: "paragraph", at: 1, in: transaction)
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Replace within one paragraph only; the separator is never editable text.
    public func replaceQuoteText(start: Int, end: Int, text: String) throws -> Data {
        let paragraphs = try quoteParagraphs()
        guard start >= 0, end >= start, text.utf16.count <= 131_072,
              !text.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}" }) else {
            throw Failure.unsupportedProseEdit
        }
        var offset = 0
        for (index, paragraph) in paragraphs.enumerated() {
            let length = paragraph.text.utf16.count
            defer { offset += length + 1 }
            guard start >= offset, end <= offset + length else { continue }
            let localStart = start - offset, localEnd = end - offset
            guard Self.split(paragraph.text, at: localStart) != nil, Self.split(paragraph.text, at: localEnd) != nil,
                  paragraphs.reduce(0, { $0 + $1.text.utf16.count + 1 }) - (end - start) + text.utf16.count <= 131_072 else {
                throw Failure.unsupportedProseEdit
            }
            if start == end, localStart == length, !text.isEmpty {
                // End typing keeps the existing last-run marks. A newly appended
                // empty paragraph inherits the preceding paragraph's last run.
                let existing = paragraph.node.child(at: 0)
                let attributes = try existing?.delta().last?.attributes ??
                    (index == 1 ? paragraphs[0].node.child(at: 0)?.delta().last?.attributes : nil) ?? [:]
                let update = try document.transactSync(origin: localOrigin) { transaction in
                    let leaf = try existing ?? paragraph.node.insertText(at: 0, in: transaction)
                    try leaf.insert(text, attributes: attributes, at: UInt32(localStart), in: transaction)
                    return Data(transaction.transactionEncodeUpdate())
                }
                wrapUndo()
                return update
            }
            return try replaceText(at: localStart, length: localEnd - localStart, with: text, path: [0, index, 0])
        }
        throw Failure.unsupportedProseEdit
    }

    /// One existing v1 fenced-code block with one unmarked XmlText leaf.
    /// Admission is deliberately separate from paragraph/structural editing.
    public func supportsCodeBlockEditing() -> Bool { (try? codeBlockText()) != nil }

    private func codeBlockText() throws -> String {
        guard integrationStatus().isComplete, root.length() == 1,
              let block = root.child(at: 0), block.kind() == "element", block.tag() == "codeBlock",
              block.length() == 1, let leaf = block.child(at: 0), leaf.kind() == "text",
              try proseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let delta = try leaf.delta()
        guard delta.allSatisfy({ $0.attributes.isEmpty }) else { throw Failure.unsupportedProseEdit }
        let text = delta.map(\.text).joined()
        guard text.utf16.count <= 131_072,
              !text.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}" }) else {
            throw Failure.unsupportedProseEdit
        }
        return text
    }

    /// Newlines stay inside the original XmlText; no block is split or rebuilt.
    public func replaceCodeBlockText(start: Int, end: Int, text: String) throws -> Data {
        let old = try codeBlockText()
        guard start >= 0, end >= start, end <= old.utf16.count,
              Self.split(old, at: start) != nil, Self.split(old, at: end) != nil,
              text.utf16.count <= 131_072, old.utf16.count - (end - start) + text.utf16.count <= 131_072,
              !text.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}" }) else {
            throw Failure.unsupportedProseEdit
        }
        return try replaceText(at: start, length: end - start, with: text, path: [0, 0])
    }

    /// Ordinary editor scope. More complex RelayMark shapes remain available for
    /// read-only projection or the legacy adapter until their native operations
    /// have explicit parity tests.
    public func supportsOrdinaryProseEditing() -> Bool {
        (try? paragraphs()) != nil
    }

    /// Replace a UTF-16 range in top-level prose using one Yrs transaction.
    /// Paragraph breaks are represented as XML siblings, never text newlines.
    /// Unchanged text stays in place; only a suffix moved by a split/join is
    /// copied with its existing inline attributes.
    public func replaceProse(start: Int, end: Int, text: String) throws -> Data {
        let blocks = try paragraphs()
        let old = blocks.map(\.text).joined(separator: "\n")
        guard start >= 0, end >= start, end <= old.utf16.count,
              Self.split(old, at: start) != nil, Self.split(old, at: end) != nil,
              !text.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}" }),
              text.utf16.count <= 131_072, old.utf16.count - (end - start) + text.utf16.count <= 131_072 else {
            throw Failure.unsupportedProseEdit
        }
        let lines = text.components(separatedBy: "\n")
        guard lines.count <= 4096 else { throw Failure.unsupportedProseEdit }
        if blocks.isEmpty {
            guard start == 0, end == 0 else { throw Failure.unsupportedProseEdit }
            let update = try document.transactSync(origin: localOrigin) { transaction in
                for (index, line) in lines.enumerated() {
                    let paragraph = try self.root.insertElement(named: "paragraph", at: UInt32(index), in: transaction)
                    let leaf = try paragraph.insertText(at: 0, in: transaction)
                    if !line.isEmpty { try leaf.insert(line, at: 0, in: transaction) }
                }
                return Data(transaction.transactionEncodeUpdate())
            }
            wrapUndo()
            return update
        }
        guard let first = Self.location(at: start, in: blocks),
              let last = Self.location(at: end, in: blocks),
              Self.split(blocks[first.block].text, at: first.index) != nil,
              Self.split(blocks[last.block].text, at: last.index) != nil else {
            throw Failure.unsupportedProseEdit
        }
        if first.block == last.block && lines.count == 1 {
            return try replaceText(at: first.index, length: end - start, with: text,
                                   path: [first.block, 0])
        }
        let suffix = try Self.suffixRuns(of: blocks[last.block].leaf, after: last.index)
        let firstLength = blocks[first.block].text.utf16.count
        let removedBlockCount = last.block - first.block
        guard blocks.count - removedBlockCount + lines.count - 1 <= 4096 else {
            throw Failure.unsupportedProseEdit
        }
        // All bounds, Unicode boundaries, node kinds and JSON attributes were
        // validated above. The mutation itself is one local Yrs transaction.
        let update = try document.transactSync(origin: localOrigin) { transaction in
            let leaf = blocks[first.block].leaf
            if firstLength > first.index {
                try leaf.removeText(start: UInt32(first.index), length: UInt32(firstLength - first.index), in: transaction)
            }
            if removedBlockCount > 0 {
                try self.root.removeChildren(start: UInt32(first.block + 1), length: UInt32(removedBlockCount), in: transaction)
            }
            if !lines[0].isEmpty { try leaf.insert(lines[0], at: UInt32(first.index), in: transaction) }
            var destination = leaf
            var offset = first.index + lines[0].utf16.count
            for (lineIndex, line) in lines.enumerated() where lineIndex > 0 {
                let paragraph = try self.root.insertElement(named: "paragraph", at: UInt32(first.block + lineIndex), in: transaction)
                destination = try paragraph.insertText(at: 0, in: transaction)
                offset = 0
                if !line.isEmpty {
                    try destination.insert(line, at: 0, in: transaction)
                    offset = line.utf16.count
                }
            }
            for run in suffix where !run.text.isEmpty {
                try destination.insert(run.text, attributes: run.attributes, at: UInt32(offset), in: transaction)
                offset += run.text.utf16.count
            }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    private struct Paragraph {
        let leaf: YXmlNode
        let text: String
    }

    private struct TextRun {
        let text: String
        let attributes: [String: Any]
    }

    private struct BasicPart {
        let node: YXmlNode
        let childIndex: Int
        let start: Int
        let end: Int
        let isText: Bool
    }

    private struct BasicBlock {
        let node: YXmlNode
        let start: Int
        let end: Int
        let parts: [BasicPart]
    }

    /// The next native editing scope: top-level paragraphs and headings with
    /// text leaves and hard breaks. More complex XML stays intact and read-only.
    public func supportsBasicMarkdownEditing() -> Bool {
        guard let blocks = try? basicBlocks() else { return false }
        return !blocks.isEmpty
    }

    /// Edit one basic Markdown block without changing its tag or attributes.
    /// This feeds the same host editor path after admission; it is not a second
    /// document model. LF/structural block changes remain on the paragraph path.
    public func replaceBasicMarkdownProse(start: Int, end: Int, text: String) throws -> Data {
        let blocks = try basicBlocks()
        let projected = try proseProjection()
        let old = String(projected.text.characters)
        guard projected.isEditable, start >= 0, end >= start, end <= old.utf16.count,
              Self.split(old, at: start) != nil, Self.split(old, at: end) != nil,
              !text.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\u{2029}" || $0 == "\u{FFFC}" }),
              text.utf16.count <= 131_072, old.utf16.count - (end - start) + text.utf16.count <= 131_072,
              let block = blocks.first(where: { start >= $0.start && end <= $0.end }) else {
            throw Failure.unsupportedProseEdit
        }
        // A hard break is one atom. A caller may delete it or insert exactly
        // one new break; arbitrary mixed structural replacement is rejected.
        let insertBreak = text == "\u{2028}" && start == end
        guard !text.contains("\u{2028}") || insertBreak else { throw Failure.unsupportedProseEdit }
        if block.parts.isEmpty {
            guard start == end, start == block.start, !text.isEmpty else { throw Failure.unsupportedProseEdit }
            let update = try document.transactSync(origin: localOrigin) { transaction in
                let leaf = try block.node.insertText(at: 0, in: transaction)
                if insertBreak {
                    _ = try block.node.insertElement(named: "hardBreak", at: 1, in: transaction)
                    _ = try block.node.insertText(at: 2, in: transaction)
                } else {
                    try leaf.insert(text, at: 0, in: transaction)
                }
                return Data(transaction.transactionEncodeUpdate())
            }
            wrapUndo()
            return update
        }
        guard let target = block.parts.first(where: { $0.isText && start >= $0.start && start <= $0.end }),
              let insertionIndex = UInt32(exactly: start - target.start) else {
            throw Failure.unsupportedProseEdit
        }
        let affected = block.parts.filter { $0.start < end && $0.end > start }
        guard insertBreak || !affected.isEmpty || !text.isEmpty else { throw Failure.unsupportedProseEdit }
        if insertBreak {
            let suffix = try Self.suffixRuns(of: target.node, after: Int(insertionIndex))
            let suffixLength = target.end - start
            let update = try document.transactSync(origin: localOrigin) { transaction in
                if suffixLength > 0 {
                    try target.node.removeText(start: insertionIndex, length: UInt32(suffixLength), in: transaction)
                }
                _ = try block.node.insertElement(named: "hardBreak", at: UInt32(target.childIndex + 1), in: transaction)
                let right = try block.node.insertText(at: UInt32(target.childIndex + 2), in: transaction)
                var offset = 0
                for run in suffix where !run.text.isEmpty {
                    try right.insert(run.text, attributes: run.attributes, at: UInt32(offset), in: transaction)
                    offset += run.text.utf16.count
                }
                return Data(transaction.transactionEncodeUpdate())
            }
            wrapUndo()
            return update
        }
        if end <= target.end, let path = path(to: target.node, from: root) {
            return try replaceText(at: Int(insertionIndex), length: end - start, with: text, path: path)
        }
        // Remove from right to left so original child indices stay valid. A
        // selected hardBreak is removed as an XML node; untouched siblings and
        // heading identity remain integrated in Yrs.
        let update = try document.transactSync(origin: localOrigin) { transaction in
            for part in affected.reversed() {
                if part.isText {
                    let lower = max(start, part.start), upper = min(end, part.end)
                    if upper > lower {
                        try part.node.removeText(start: UInt32(lower - part.start),
                                                 length: UInt32(upper - lower), in: transaction)
                    }
                } else {
                    try block.node.removeChildren(start: UInt32(part.childIndex), length: 1, in: transaction)
                }
            }
            if !text.isEmpty { try target.node.insert(text, at: insertionIndex, in: transaction) }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    private func basicBlocks() throws -> [BasicBlock] {
        var blocks: [BasicBlock] = []
        var offset = 0
        for node in root.children() {
            guard node.kind() == "element", let tag = node.tag(),
                  tag == "paragraph" || tag == "heading" else { throw Failure.unsupportedProseEdit }
            let attributes = try node.attributes()
            if tag == "paragraph" {
                guard attributes.isEmpty else { throw Failure.unsupportedProseEdit }
            } else {
                guard Set(attributes.keys).isSubset(of: ["level", "headingId"]),
                      (attributes["level"] == nil || (attributes["level"] as? Int).map({ (1...6).contains($0) }) == true),
                      (attributes["headingId"] == nil || (attributes["headingId"] as? String)?.isEmpty == false) else {
                    throw Failure.unsupportedProseEdit
                }
            }
            if !blocks.isEmpty { offset += 1 }
            let blockStart = offset
            var parts: [BasicPart] = []
            for (index, child) in node.children().enumerated() {
                let kind = child.kind()
                if kind == "text" {
                    let value = try child.delta().map(\.text).joined()
                    guard !value.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}" }) else {
                        throw Failure.unsupportedProseEdit
                    }
                    let end = offset + value.utf16.count
                    parts.append(BasicPart(node: child, childIndex: index, start: offset, end: end, isText: true))
                    offset = end
                } else if kind == "element", child.tag() == "hardBreak", try child.attributes().isEmpty, child.length() == 0 {
                    parts.append(BasicPart(node: child, childIndex: index, start: offset, end: offset + 1, isText: false))
                    offset += 1
                } else { throw Failure.unsupportedProseEdit }
            }
            guard parts.isEmpty || parts.contains(where: \.isText) else { throw Failure.unsupportedProseEdit }
            blocks.append(BasicBlock(node: node, start: blockStart, end: offset, parts: parts))
        }
        return blocks
    }

    private func paragraphs() throws -> [Paragraph] {
        var blocks: [Paragraph] = []
        for paragraph in root.children() {
            guard paragraph.kind() == "element", paragraph.tag() == "paragraph",
                  try paragraph.attributes().isEmpty, paragraph.length() == 1,
                  let leaf = paragraph.child(at: 0), leaf.kind() == "text" else {
                throw Failure.unsupportedProseEdit
            }
            let text = try leaf.delta().map(\.text).joined()
            guard !text.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}" }) else {
                throw Failure.unsupportedProseEdit
            }
            blocks.append(Paragraph(leaf: leaf, text: text))
        }
        return blocks
    }

    private static func location(at offset: Int, in blocks: [Paragraph]) -> (block: Int, index: Int)? {
        var base = 0
        for (index, block) in blocks.enumerated() {
            let end = base + block.text.utf16.count
            if offset <= end { return (index, offset - base) }
            base = end + 1
        }
        return nil
    }

    /// Split only at Swift Character boundaries, which are also valid UTF-16
    /// boundaries. Native text proposals cannot tear a grapheme in half.
    private static func split(_ value: String, at utf16Offset: Int) -> (String, String)? {
        guard utf16Offset >= 0 else { return nil }
        var offset = 0
        var index = value.startIndex
        while index < value.endIndex {
            if offset == utf16Offset { return (String(value[..<index]), String(value[index...])) }
            let next = value.index(after: index)
            offset += value[index..<next].utf16.count
            index = next
        }
        return offset == utf16Offset ? (value, "") : nil
    }

    private static func suffixRuns(of leaf: YXmlNode, after offset: Int) throws -> [TextRun] {
        var result: [TextRun] = []
        var base = 0
        for run in try leaf.delta() {
            let end = base + run.text.utf16.count
            if offset < end {
                guard let (_, suffix) = split(run.text, at: max(0, offset - base)) else {
                    throw Failure.unsupportedProseEdit
                }
                if !suffix.isEmpty { result.append(TextRun(text: suffix, attributes: run.attributes)) }
            }
            base = end
        }
        return result
    }

    /// Bind each immutable command UUID to the maintained typing group. Capturing
    /// a durable checkpoint does not close that live group. Hosts may explicitly
    /// request a boundary for a semantic command, never for every keystroke.
    public func performOwnedCommand(operationID: UUID, separateHistoryItem: Bool = false,
                                    _ command: () throws -> Data) throws -> Data {
        guard ownedOperationID == nil, historyCapture == nil, undoGroupDepth == 0 else { throw Failure.conflictingOwnedCommand }
        let history = undoManager.undoMetadata() + undoManager.redoMetadata()
        guard !history.contains(where: { self.operationReferences($0)?.contains(operationID) == true }) else { throw Failure.conflictingOwnedCommand }
        if separateHistoryItem || undoManager.undoMetadata().last.map({ self.operationReferences($0).map({$0.count>=4096}) ?? true }) == true {
            undoManager.wrap()
        }
        ownedOperationID = operationID
        defer { ownedOperationID = nil; if separateHistoryItem { undoManager.wrap() } }
        return try command()
    }

    public func closeOwnedHistoryGroup() throws {
        guard ownedOperationID == nil, historyCapture == nil, undoGroupDepth == 0 else { throw Failure.conflictingOwnedCommand }
        undoManager.wrap()
    }

    public struct OwnedCommandGroup: Sendable {
        public let ownerID: UUID
        public let reference: UUID
        public let operationIDs: [UUID]
    }
    public func ownedCommandGroup(operationID: UUID) throws -> OwnedCommandGroup {
        guard let metadata=undoManager.undoMetadata().last,
              let operations=self.operationReferences(metadata),operations.last==operationID,
              let first=operations.first else {throw Failure.unboundOwnedHistory}
        return OwnedCommandGroup(ownerID:historyOwnerID,reference:first,operationIDs:operations)
    }

    public struct OwnedHistoryEffect: Sendable {
        public let ownerID: UUID
        public enum Kind:String,Sendable { case undo,redo }
        public let kind:Kind
        /// Actual sender frontier captured before the same manager inverse.
        public let beforeSnapshot: Data
        /// Actual maintained synchronization ReplaceStep, independently applied
        /// to the pre-tree. It observes the effect; receipts still prove ownership.
        public let steps: Data
        public let update: Data
        public let reference: UUID
        public let operationIDs: [UUID]
    }

    /// The actual Popped event identifies the consumed group, including skipped
    /// obsolete items. Receipts remain the host's independent authority.
    public func undoWithReference() throws -> OwnedHistoryEffect? { try ownedHistory(redo:false) }
    public func redoWithReference() throws -> OwnedHistoryEffect? { try ownedHistory(redo:true) }
    private func ownedHistory(redo: Bool) throws -> OwnedHistoryEffect? {
        guard ownedOperationID == nil, historyCapture == nil, undoGroupDepth == 0 else { throw Failure.conflictingOwnedCommand }
        let metadata = redo ? undoManager.redoMetadata() : undoManager.undoMetadata()
        for object in metadata { guard self.operationReferences(object) != nil else { throw Failure.unboundOwnedHistory } }
        let bridge = try PMYXmlBridge.canonical()
        let beforeTree = try JSONSerialization.jsonObject(with:snapshot()) as! [String:Any]
        let beforePM = try bridge.document(fromSnapshot:beforeTree)
        let beforeSnapshot = try captureSenderSnapshot()
        guard let update = try performHistory(redo:redo) else { return nil }
        guard let operations = lastHistoryOperations,let reference = operations.first else { throw Failure.unboundOwnedHistory }
        _ = try authoredDocument()
        let afterTree = try JSONSerialization.jsonObject(with:snapshot()) as! [String:Any]
        let afterPM = try bridge.document(fromSnapshot:afterTree)
        // y-tiptap's _typeChanged/_forceRerender synchronizes the entire current
        // fragment with one transaction.replace(0, old.content.size, new Slice).
        // This is a read observer of the actual effect, never a fabricated CRDT
        // inverse, command rebase or provenance authority.
        let step = PMStep.replace(from:0,to:beforePM.content.size,
                                  slice:PMSlice(afterPM.content,openStart:0,openEnd:0))
        var observedSteps=[step.json()]
        if !pmCompareDeep(beforePM.attrs["relaymark"] ?? [:],afterPM.attrs["relaymark"] ?? [:]) {
            let metadataStep=PMStep.docAttr(name:"relaymark",value:afterPM.attrs["relaymark"] ?? [:])
            guard try metadataStep.apply(step.apply(beforePM)).eq(afterPM) else {throw Failure.unsupportedProseEdit}
            observedSteps.append(metadataStep.json())
        } else {guard try step.apply(beforePM).eq(afterPM) else {throw Failure.unsupportedProseEdit}}
        let steps = try JSONSerialization.data(withJSONObject:observedSteps,options:[.sortedKeys])
        return OwnedHistoryEffect(ownerID:historyOwnerID,kind:redo ? .redo : .undo,beforeSnapshot:beforeSnapshot,steps:steps,update:update,reference:reference,operationIDs:operations)
    }
    private var lastHistoryOperations: [UUID]?

    private func operationReferences(_ object: NSObject?) -> [UUID]? {
        guard let data=object as? NSData,let value=(try? JSONSerialization.jsonObject(with:data as Data)) as? [String:Any] else {return nil}
        return Self.operationReferences(value,ownerID:historyOwnerID)
    }
    private static func operationReferences(_ value: [String:Any], ownerID: UUID) -> [UUID]? {
        guard Set(value.keys)==["operation_ids","owner_id"],value["owner_id"] as? String==ownerID.uuidString.lowercased(),let ids=value["operation_ids"] as? [String],
              !ids.isEmpty,ids.count<=4096 else { return nil }
        let operations=ids.compactMap(UUID.init(uuidString:))
        guard operations.count==ids.count,Set(operations).count==operations.count,
              operations.map({$0.uuidString.lowercased()})==ids else {return nil}
        return operations
    }
    private func operationMetadata(_ operationIDs: [UUID]) -> Data {
        let ids=operationIDs.map{"\""+$0.uuidString.lowercased()+"\""}.joined(separator:",")
        return Data(("{\"owner_id\":\""+historyOwnerID.uuidString.lowercased()+"\",\"operation_ids\":["+ids+"]}").utf8)
    }
    private func bindStackMetadata(current: NSObject? = nil, extending: Bool = false) -> NSObject? {
        if let capture=self.historyCapture {
            let placeholder=NSMutableData(data:Data("null".utf8))
            capture.inverseMetadata.append(placeholder)
            return placeholder
        }
        guard let id=self.ownedOperationID else { return nil }
        if extending {
            guard var operations=self.operationReferences(current),operations.count<4096 else {return nil}
            if !operations.contains(id){operations.append(id)}
            return self.operationMetadata(operations) as NSData
        }
        return self.operationMetadata([id]) as NSData
    }
    private func installHistoryObservers() {
        historySubscriptions = [
            undoManager.observeAdded { [weak self] _, current in
                guard let self else { return current }; return self.bindStackMetadata()
            },
            undoManager.observeUpdated { [weak self] _, current in
                guard let self else { return current }; return self.bindStackMetadata(current:current,extending:true)
            },
            undoManager.observePopped { [weak self] _, current in
                guard let self,let capture=self.historyCapture else { return current }
                capture.operations=self.operationReferences(current)
                let bytes=capture.operations.map(self.operationMetadata) ?? Data("null".utf8)
                for inverse in capture.inverseMetadata { inverse.setData(bytes) }
                return current
            }
        ]
    }
    private func performHistory(redo: Bool) throws -> Data? {
        guard ownedOperationID == nil, historyCapture == nil, undoGroupDepth == 0 else { throw Failure.conflictingOwnedCommand }
        let before=stateVector()
        wrapUndo()
        let capture=HistoryCapture();historyCapture=capture;lastHistoryOperations=nil
        defer { historyCapture=nil }
        guard try redo ? undoManager.redo() : undoManager.undo() else { return nil }
        wrapUndo();lastHistoryOperations=capture.operations
        return try encodeUpdate(since:before)
    }

    /// Ordinary undo uses the same manager; it retains an operation reference when
    /// available without inventing one for unbound historical work.
    public func undo() throws -> Data? { try performHistory(redo:false) }
    public func redo() throws -> Data? { try performHistory(redo:true) }

    /// Portable Yjs relative position; byte format is owned by Yrs, not RelayMark.
    public func anchor(path: [Int], index: Int, association: Int = 0) throws -> Data {
        try document.transactSync { transaction in
            var node = self.root
            for component in path {
                guard component >= 0, component <= Int(UInt32.max),
                      let child = node.child(at: UInt32(component), in: transaction) else {
                    throw Failure.invalidAnchor
                }
                node = child
            }
            guard index >= 0, index <= Int(node.length(in: transaction)),
                  let association = Int32(exactly: association) else { throw Failure.invalidAnchor }
            return try node.relativePosition(at: UInt32(index), association: association, in: transaction)
        }
    }

    /// Resolve a portable Yjs anchor against the current document. Deleted or
    /// foreign XML nodes have no path in this tree and therefore return nil.
    public func resolve(anchor: Data) throws -> Position? {
        guard let resolved = try document.resolveXmlRelativePosition(anchor),
              let path = path(to: resolved.node, from: root) else { return nil }
        return Position(path: path, index: Int(resolved.index), association: Int(resolved.association))
    }

    private func path(to target: YXmlNode, from node: YXmlNode) -> [Int]? {
        if node.isSameNode(as: target) { return [] }
        for index in 0..<Int(node.length()) {
            guard let child = node.child(at: UInt32(index)) else { continue }
            if let suffix = path(to: target, from: child) {
                return [index] + suffix
            }
        }
        return nil
    }

    /// Mutate one existing XmlText leaf and return the exact Yjs-v1 transaction update.
    /// The host must persist this update before it acknowledges the local edit.
    public func insertText(_ text: String, at index: Int, path: [Int]) throws -> Data {
        try replaceText(at: index, length: 0, with: text, path: path)
    }

    public func deleteText(at index: Int, length: Int, path: [Int]) throws -> Data {
        try replaceText(at: index, length: length, with: "", path: path)
    }

    enum PaperControlChange {
        case insert(tag: String, attributes: [String: Any])
        case update(tag: String, expectedID: String, attributes: [String: String])
        case remove(tag: String, expectedID: String)
    }

    /// One root-sibling transaction after the canonical command has validated a
    /// scratch replica. Updates retain the existing Y.XmlElement identity.
    func mutatePaperControl(at index: Int, change: PaperControlChange) throws -> Data {
        guard let childIndex = UInt32(exactly: index) else { throw Failure.invalidTextPath }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            guard childIndex <= self.root.length(in: transaction) else { throw Failure.invalidTextPath }
            switch change {
            case let .insert(tag, attributes):
                let node = try self.root.insertElement(named: tag, at: childIndex, in: transaction)
                for (key, value) in attributes { try node.setAttribute(key, value: value, in: transaction) }
            case let .update(tag, expectedID, attributes):
                guard let node = self.root.child(at: childIndex, in: transaction),
                      node.kind(in: transaction) == "element", node.tag(in: transaction) == tag,
                      try node.attributes(in: transaction)["relaymarkId"] as? String == expectedID else {
                    throw Failure.invalidTextPath
                }
                for (key, value) in attributes where key != "relaymarkId" {
                    try node.setAttribute(key, value: value, in: transaction)
                }
            case let .remove(tag, expectedID):
                guard let node = self.root.child(at: childIndex, in: transaction),
                      node.kind(in: transaction) == "element", node.tag(in: transaction) == tag,
                      try node.attributes(in: transaction)["relaymarkId"] as? String == expectedID else {
                    throw Failure.invalidTextPath
                }
                try self.root.removeChildren(start: childIndex, length: 1, in: transaction)
            }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Replace one authored suggestion with one ordinary Markdown block in one
    /// local-origin Yrs transaction, so undo restores the complete atom.
    func acceptAgentSuggestion(at index: Int, expectedID: String,
                               block: RelayMarkNativeRichSingleBlock.Block,
                               newBlockID: String, headingID: String?,
                               quoteParagraphID: String?,
                               listIDs: [(item: String, paragraph: String)]) throws -> Data {
        guard let childIndex = UInt32(exactly: index),
              (!block.runs.isEmpty || !block.listItems.isEmpty || block.kind.tag == "horizontalRule"),
              listIDs.count == block.listItems.count else {
            throw Failure.invalidTextPath
        }
        if case .quote = block.kind, quoteParagraphID == nil { throw Failure.invalidTextPath }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            guard let node = self.root.child(at: childIndex, in: transaction),
                  node.kind(in: transaction) == "element",
                  node.tag(in: transaction) == "agentSuggestion",
                  try node.attributes(in: transaction)["relaymarkId"] as? String == expectedID else {
                throw Failure.invalidTextPath
            }
            try self.root.removeChildren(start: childIndex, length: 1, in: transaction)
            let replacement = try self.root.insertElement(named: block.kind.tag, at: childIndex,
                                                          in: transaction)
            for (key, value) in block.attributes(id: newBlockID, headingID: headingID) {
                try replacement.setAttribute(key, value: value, in: transaction)
            }
            if !block.listItems.isEmpty {
                for (offset, item) in block.listItems.enumerated() {
                    let listItem = try replacement.insertElement(named: "listItem",
                                                                  at: UInt32(offset), in: transaction)
                    try listItem.setAttribute("relaymarkId", value: listIDs[offset].item, in: transaction)
                    let paragraph = try listItem.insertElement(named: "paragraph", at: 0,
                                                               in: transaction)
                    try paragraph.setAttribute("relaymarkId", value: listIDs[offset].paragraph,
                                               in: transaction)
                    let leaf = try paragraph.insertText(at: 0, in: transaction)
                    var textOffset: UInt32 = 0
                    for run in item {
                        try leaf.insert(run.text, attributes: run.attributes, at: textOffset,
                                        in: transaction)
                        textOffset += UInt32(run.text.utf16.count)
                    }
                }
                return Data(transaction.transactionEncodeUpdate())
            }
            let textParent: YXmlNode
            if case .quote = block.kind {
                guard let quoteParagraphID else { throw Failure.invalidTextPath }
                let paragraph = try replacement.insertElement(named: "paragraph", at: 0,
                                                              in: transaction)
                try paragraph.setAttribute("relaymarkId", value: quoteParagraphID, in: transaction)
                textParent = paragraph
            } else { textParent = replacement }
            if !block.runs.isEmpty {
                let leaf = try textParent.insertText(at: 0, in: transaction)
                var offset: UInt32 = 0
                for run in block.runs {
                    try leaf.insert(run.text, attributes: run.attributes, at: offset, in: transaction)
                    offset += UInt32(run.text.utf16.count)
                }
            }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Deletion and insertion share one transaction and one undo item.
    public func replaceText(at index: Int, length: Int, with text: String, path: [Int]) throws -> Data {
        try replaceText(at: index, length: length, with: text, path: path, insertionRuns: nil)
    }

    /// Replace text using explicit authored typing marks supplied by the editor.
    /// Schema-specific callers validate their complete candidate before invoking this primitive.
    public func replaceText(at index: Int, length: Int, with text: String,
                            attributes: [String: Any], path: [Int]) throws -> Data {
        try replaceText(at: index, length: length, runs: [(text, attributes)], path: path)
    }

    /// Apply attributed paste as one community Yrs transaction and undo item.
    public func replaceText(at index: Int, length: Int,
                            runs: [(text: String, attributes: [String: Any])], path: [Int]) throws -> Data {
        guard runs.allSatisfy({ JSONSerialization.isValidJSONObject($0.attributes) }) else {
            throw Failure.unsupportedProseEdit
        }
        return try replaceText(at: index, length: length, with: runs.map(\.text).joined(),
                               path: path, insertionRuns: runs)
    }

    private func replaceText(at index: Int, length: Int, with text: String, path: [Int],
                             insertionRuns: [(text: String, attributes: [String: Any])]?) throws -> Data {
        let update = try document.transactSync(origin: localOrigin) { transaction in
            var node = self.root
            for component in path {
                guard component >= 0, component <= Int(UInt32.max),
                      let child = node.child(at: UInt32(component), in: transaction) else {
                    throw Failure.invalidTextPath
                }
                node = child
            }
            guard node.kind(in: transaction) == "text" else { throw Failure.invalidTextPath }
            let total = Int(node.length(in: transaction))
            guard index >= 0, length >= 0, index <= total, length <= total - index else {
                throw Failure.invalidUTF16Range
            }
            // YSwift's insert default is explicit empty attributes, not Yjs's
            // inherited typing marks. Preserve a replacement wholly within one
            // existing run (or an insertion strictly inside it). Appending to
            // the leaf has one unambiguous last run. Interior mark boundaries
            // and mixed-run styling remain the host's candidate-validation decision.
            var attributes: [String: Any] = [:]
            var offset = 0
            for run in try node.delta(in: transaction) {
                let end = offset + run.text.utf16.count
                if index >= offset && index < end && index + length <= end &&
                    (length > 0 || index > offset) {
                    attributes = run.attributes
                    break
                }
                if length == 0 && index == total && end == total && !run.text.isEmpty {
                    attributes = run.attributes
                }
                offset = end
            }
            if length > 0 { try node.removeText(start: UInt32(index), length: UInt32(length), in: transaction) }
            if let insertionRuns {
                var cursor = index
                for run in insertionRuns where !run.text.isEmpty {
                    try node.insert(run.text, attributes: run.attributes, at: UInt32(cursor), in: transaction)
                    cursor += run.text.utf16.count
                }
            } else if !text.isEmpty {
                try node.insert(text, attributes: attributes, at: UInt32(index), in: transaction)
            }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Seed one existing empty XML paragraph or first-child callout title without changing its stable block
    /// identity. The canonical adapter validates the surrounding document on a scratch
    /// replica before this operation reaches the live Yrs transaction.
    func insertTextIntoEmptyParagraph(_ text: String, path: [Int], attributes: [String: Any] = [:]) throws -> Data {
        try insertTextIntoEmptyParagraph(path: path, runs: [(text, attributes)])
    }

    func insertTextIntoEmptyParagraph(path: [Int],
                                      runs: [(text: String, attributes: [String: Any])]) throws -> Data {
        guard runs.contains(where: { !$0.text.isEmpty }) else { throw Failure.unsupportedProseEdit }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            var node = self.root
            for component in path {
                guard component >= 0, component <= Int(UInt32.max),
                      let child = node.child(at: UInt32(component), in: transaction) else {
                    throw Failure.invalidTextPath
                }
                node = child
            }
            let isTitle = path.count == 2 && path[1] == 0 && node.tag(in: transaction) == "calloutTitle" &&
                self.root.child(at: UInt32(path[0]), in: transaction)?.tag(in: transaction) == "callout"
            guard node.kind(in: transaction) == "element",
                  ["paragraph", "heading", "codeBlock", "questionLabel", "questionOption"].contains(node.tag(in: transaction) ?? "") || isTitle,
                  node.child(at: 0, in: transaction) == nil else {
                throw Failure.invalidTextPath
            }
            let leaf = try node.insertText(at: 0, in: transaction)
            var offset: UInt32 = 0
            for run in runs where !run.text.isEmpty {
                try leaf.insert(run.text, attributes: run.attributes, at: offset, in: transaction)
                offset += UInt32(run.text.utf16.count)
            }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Apply standard Y.XmlText formatting attributes; a null attribute clears a mark.
    public func formatText(at index: Int, length: Int, attributes: [String: Any], path: [Int]) throws -> Data {
        let update = try document.transactSync(origin: localOrigin) { transaction in
            var node = self.root
            for component in path {
                guard component >= 0, component <= Int(UInt32.max),
                      let child = node.child(at: UInt32(component), in: transaction) else {
                    throw Failure.invalidTextPath
                }
                node = child
            }
            guard node.kind(in: transaction) == "text" else { throw Failure.invalidTextPath }
            let total = Int(node.length(in: transaction))
            guard index >= 0, length > 0, index <= total, length <= total - index else {
                throw Failure.invalidUTF16Range
            }
            try node.format(at: UInt32(index), length: UInt32(length), attributes: attributes, in: transaction)
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// The same bounded basic blocks or list items as native text editing.
    /// This does not admit arbitrary containers just because they contain text.
    public func supportsInlineFormatting() -> Bool { (try? formattingProjection()) != nil }

    private func formattingProjection() throws -> RelayMarkCollaborativeProse {
        guard integrationStatus().isComplete else { throw Failure.unsupportedProseEdit }
        let projection = try proseProjection()
        guard projection.isEditable else { throw Failure.unsupportedProseEdit }
        if (try? basicBlocks()) == nil {
            guard !root.children().isEmpty else { throw Failure.unsupportedProseEdit }
            for list in root.children() { try validateEditableList(list, depth: 0) }
        }
        return projection
    }

    /// Format existing editable text leaves by their canonical UTF-16 offsets.
    /// Separators and atoms are skipped; one Yrs transaction preserves every
    /// XML element, its attributes and the text's CRDT item identities.
    public func formatProse(start: Int, end: Int, attributes: [String: Any]) throws -> Data {
        let projection = try formattingProjection()
        let prose = String(projection.text.characters)
        guard start >= 0, end > start, end <= prose.utf16.count,
              Self.split(prose, at: start) != nil, Self.split(prose, at: end) != nil,
              !attributes.isEmpty,
              Self.validFormatting(attributes) else { throw Failure.unsupportedProseEdit }
        var slices: [(leaf: YXmlNode, index: UInt32, length: UInt32)] = []
        for range in projection.textRanges(in: NSRange(location: start, length: end - start)) {
            var leaf = root
            for component in range.path {
                guard let next = leaf.child(at: UInt32(component)) else { throw Failure.invalidTextPath }
                leaf = next
            }
            guard leaf.kind() == "text", let index = UInt32(exactly: range.index),
                  let length = UInt32(exactly: range.length) else { throw Failure.unsupportedProseEdit }
            slices.append((leaf, index, length))
        }
        guard !slices.isEmpty else { throw Failure.unsupportedProseEdit }
        let enablingCode = attributes["code"] != nil && !(attributes["code"] is NSNull)
        let enablingOther = attributes.contains { key, value in key != "code" && !(value is NSNull) }
        for slice in slices {
            var offset = 0
            for run in try slice.leaf.delta() {
                let runEnd = offset + run.text.utf16.count
                let overlaps = offset < Int(slice.index + slice.length) && runEnd > Int(slice.index)
                if overlaps {
                    if enablingCode && run.attributes.keys.contains(where: { $0 != "code" && !(attributes[$0] is NSNull) }) {
                        throw Failure.unsupportedProseEdit
                    }
                    if enablingOther && run.attributes["code"] != nil && !(attributes["code"] is NSNull) {
                        throw Failure.unsupportedProseEdit
                    }
                }
                offset = runEnd
            }
        }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            for slice in slices {
                try slice.leaf.format(at: slice.index, length: slice.length,
                                      attributes: attributes, in: transaction)
            }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    private static func validFormatting(_ attributes: [String: Any]) -> Bool {
        let booleanMarks: Set<String> = ["bold", "italic", "strike", "code"]
        for (key, value) in attributes {
            if value is NSNull { continue }
            if booleanMarks.contains(key) {
                guard (value as? [String: Any])?.isEmpty == true else { return false }
            } else if key == "link", let link = value as? [String: Any],
                      let href = link["href"] as? String, !href.isEmpty,
                      !href.contains("\n"), !href.contains("<"), !href.contains(">"),
                      URL(string: href) != nil,
                      Set(link.keys).isSubset(of: ["href", "target", "rel", "class"]),
                      link.allSatisfy({ $0.key == "href" || $0.value is String }) {
                continue
            } else { return false }
        }
        return attributes.keys.allSatisfy { booleanMarks.contains($0) || $0 == "link" }
    }

    /// TipTap's `addRowAfter` for a rectangular canonical table without merged cells.
    /// Existing rows and text stay in place; the new empty cells copy the
    /// selected body row's column widths and alignment. The relative cell
    /// anchor and full displayed snapshot reject stale or retargeted actions.
    public func canAddRichTableRow(afterCell anchor: Data, expectedCellID: String) -> Bool {
        guard integrationStatus().isComplete,
              let projection = try? richProseProjection(), projection.isEditable else { return false }
        guard let target = try? richTableRowTarget(anchor, expectedCellID: expectedCellID) else { return false }
        return target.table.length() < 256
    }

    public func addRichTableRow(afterCell anchor: Data, expectedCellID: String,
                                      expectedSnapshot: Data) throws
        -> (update: Data, rowID: String, cellIDs: [String], paragraphIDs: [String]) {
        guard integrationStatus().isComplete, try snapshot() == expectedSnapshot,
              try richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let path = try richTableRowTarget(anchor, expectedCellID: expectedCellID)
        guard path.table.length() < 256 else { throw Failure.unsupportedProseEdit }
        let rowID = "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let cellIDs = (0..<path.width).map { _ in
            "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        }
        let paragraphIDs = (0..<path.width).map { _ in
            "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(encodeUpdate())
        guard try scratch.snapshot() == expectedSnapshot else { throw Failure.invalidAnchor }
        _ = try scratch.insertRichTableRow(afterCell: anchor, expectedCellID: expectedCellID,
            rowID: rowID, cellIDs: cellIDs, paragraphIDs: paragraphIDs)
        guard try scratch.richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let update = try insertRichTableRow(afterCell: anchor, expectedCellID: expectedCellID,
            rowID: rowID, cellIDs: cellIDs, paragraphIDs: paragraphIDs)
        return (update, rowID, cellIDs, paragraphIDs)
    }

    private func richTableRowTarget(_ anchor: Data, expectedCellID: String) throws
        -> (table: YXmlNode, row: YXmlNode, width: Int, rowIndex: Int) {
        let (cell, path) = try anchoredElement(anchor)
        guard path.count >= 3, ["tableCell", "tableHeader"].contains(cell.tag() ?? ""),
              try cell.attributes()["relaymarkId"] as? String == expectedCellID else { throw Failure.invalidAnchor }
        var table = root
        for index in path.dropLast(2) {
            guard let child = table.child(at: UInt32(index)) else { throw Failure.invalidAnchor }
            table = child
        }
        let rowIndex = path[path.count - 2]
        guard table.tag() == "table", let row = table.child(at: UInt32(rowIndex)), row.tag() == "tableRow",
              (1...256).contains(table.length()), (1...256).contains(row.length()) else { throw Failure.invalidAnchor }
        let width = Int(row.length())
        for candidate in table.children() {
            guard candidate.tag() == "tableRow", candidate.length() == width else {
                throw Failure.unsupportedProseEdit
            }
            for entry in candidate.children() {
                guard ["tableCell", "tableHeader"].contains(entry.tag() ?? "") else {
                    throw Failure.unsupportedProseEdit
                }
                let attrs = try entry.attributes()
                guard attrs["colspan"] as? Int == 1, attrs["rowspan"] as? Int == 1 else {
                    throw Failure.unsupportedProseEdit
                }
            }
        }
        return (table, row, width, rowIndex)
    }

    private func insertRichTableRow(afterCell anchor: Data, expectedCellID: String,
                                          rowID: String, cellIDs: [String], paragraphIDs: [String]) throws -> Data {
        let target = try richTableRowTarget(anchor, expectedCellID: expectedCellID)
        guard cellIDs.count == target.width, paragraphIDs.count == target.width else {
            throw Failure.unsupportedProseEdit
        }
        let sourceAttrs = try target.row.children().map { try $0.attributes() }
        let referenceRow = target.row.children().allSatisfy { $0.tag() == "tableHeader" }
            ? target.table.child(at: UInt32(target.rowIndex + 1)) : target.row
        let cellTags = (0..<target.width).map { referenceRow?.child(at: UInt32($0))?.tag() ?? "tableCell" }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            let row = try target.table.insertElement(named: "tableRow", at: UInt32(target.rowIndex + 1), in: transaction)
            try row.setAttribute("relaymarkId", value: rowID, in: transaction)
            for index in 0..<target.width {
                let cell = try row.insertElement(named: cellTags[index], at: UInt32(index), in: transaction)
                try cell.setAttribute("relaymarkId", value: cellIDs[index], in: transaction)
                for key in ["colspan", "rowspan", "colwidth", "align"] {
                    if let value = sourceAttrs[index][key], !(value is NSNull) {
                        try cell.setAttribute(key, value: value, in: transaction)
                    }
                }
                let paragraph = try cell.insertElement(named: "paragraph", at: 0, in: transaction)
                try paragraph.setAttribute("relaymarkId", value: paragraphIDs[index], in: transaction)
            }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// TipTap's `addColumnAfter` on an unmerged rectangular table. Each row
    /// receives a fresh empty cell/paragraph of that row's header or body
    /// type. Existing cells, marks, IDs, and widths remain untouched; the
    /// community command leaves the caret in the originally selected cell.
    public func canAddRichTableColumn(afterCell anchor: Data, expectedCellID: String) -> Bool {
        guard integrationStatus().isComplete,
              let projection = try? richProseProjection(), projection.isEditable else { return false }
        return (try? richTableColumnTarget(anchor, expectedCellID: expectedCellID)) != nil
    }

    public func addRichTableColumn(afterCell anchor: Data, expectedCellID: String,
                                         expectedSnapshot: Data) throws
        -> (update: Data, cellIDs: [String], paragraphIDs: [String]) {
        guard integrationStatus().isComplete, try snapshot() == expectedSnapshot,
              try richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let target = try richTableColumnTarget(anchor, expectedCellID: expectedCellID)
        let cellIDs = (0..<target.rows).map { _ in
            "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        }
        let paragraphIDs = (0..<target.rows).map { _ in
            "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(encodeUpdate())
        guard try scratch.snapshot() == expectedSnapshot else { throw Failure.invalidAnchor }
        _ = try scratch.insertRichTableColumn(afterCell: anchor, expectedCellID: expectedCellID,
            cellIDs: cellIDs, paragraphIDs: paragraphIDs)
        guard try scratch.richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let update = try insertRichTableColumn(afterCell: anchor, expectedCellID: expectedCellID,
            cellIDs: cellIDs, paragraphIDs: paragraphIDs)
        return (update, cellIDs, paragraphIDs)
    }

    private func richTableColumnTarget(_ anchor: Data, expectedCellID: String) throws
        -> (table: YXmlNode, columnIndex: Int, rows: Int) {
        let target = try richTableRowTarget(anchor, expectedCellID: expectedCellID)
        let (_, path) = try anchoredElement(anchor)
        guard target.width < 256 else { throw Failure.unsupportedProseEdit }
        return (target.table, path[path.count - 1], Int(target.table.length()))
    }

    private func insertRichTableColumn(afterCell anchor: Data, expectedCellID: String,
                                             cellIDs: [String], paragraphIDs: [String]) throws -> Data {
        let target = try richTableColumnTarget(anchor, expectedCellID: expectedCellID)
        guard cellIDs.count == target.rows, paragraphIDs.count == target.rows else {
            throw Failure.unsupportedProseEdit
        }
        let rows = target.table.children()
        let headerColumn = rows.allSatisfy { $0.child(at: UInt32(target.columnIndex))?.tag() == "tableHeader" }
        let referenceColumn = headerColumn ? target.columnIndex + 1 : target.columnIndex
        let rowTags = rows.map { $0.child(at: UInt32(referenceColumn))?.tag() ?? "tableCell" }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            for (index, row) in rows.enumerated() {
                let cell = try row.insertElement(named: rowTags[index], at: UInt32(target.columnIndex + 1), in: transaction)
                try cell.setAttribute("relaymarkId", value: cellIDs[index], in: transaction)
                try cell.setAttribute("colspan", value: 1, in: transaction)
                try cell.setAttribute("rowspan", value: 1, in: transaction)
                let paragraph = try cell.insertElement(named: "paragraph", at: 0, in: transaction)
                try paragraph.setAttribute("relaymarkId", value: paragraphIDs[index], in: transaction)
            }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Insert the browser's default `Title` child into one untitled, flat v3
    /// callout. The snapshot is the exact displayed checkpoint: it includes
    /// the callout, every child, and their text/marks. A changed document is
    /// rejected before any live transaction. The returned ID belongs to the
    /// newly inserted title and is stable across peer replay and undo/redo.
    public func addCalloutTitle(anchor: Data, expectedID: String,
                                expectedSnapshot: Data) throws -> (update: Data, titleID: String) {
        guard integrationStatus().isComplete,
              try snapshot() == expectedSnapshot,
              try richProseProjection().isEditable else {
            throw Failure.unsupportedProseEdit
        }
        let (callout, path) = try anchoredElement(anchor)
        guard path.count == 1, callout.tag() == "callout",
              try callout.attributes()["relaymarkId"] as? String == expectedID,
              callout.length() > 0,
              callout.children().allSatisfy({ $0.tag() == "paragraph" }) else {
            throw Failure.invalidAnchor
        }

        let titleID = "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(encodeUpdate())
        guard try scratch.snapshot() == expectedSnapshot else { throw Failure.invalidAnchor }
        _ = try scratch.insertCalloutTitle(anchor: anchor, expectedID: expectedID, titleID: titleID)
        guard try scratch.richProseProjection().isEditable else {
            throw Failure.unsupportedProseEdit
        }
        let update = try insertCalloutTitle(anchor: anchor, expectedID: expectedID, titleID: titleID)
        return (update, titleID)
    }

    private func insertCalloutTitle(anchor: Data, expectedID: String,
                                    titleID: String) throws -> Data {
        let (callout, path) = try anchoredElement(anchor)
        guard path.count == 1, callout.tag() == "callout",
              try callout.attributes()["relaymarkId"] as? String == expectedID,
              callout.length() > 0,
              callout.children().allSatisfy({ $0.tag() == "paragraph" }) else {
            throw Failure.invalidAnchor
        }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            let title = try callout.insertElement(named: "calloutTitle", at: 0, in: transaction)
            try title.setAttribute("relaymarkId", value: titleID, in: transaction)
            let leaf = try title.insertText(at: 0, in: transaction)
            try leaf.insert("Title", at: 0, in: transaction)
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Change only the appearance of one existing, editable canonical callout.
    /// The host binds this relative anchor to its authorized document and
    /// captures the ID and appearance from the same displayed revision. A
    /// changed/deleted callout is rejected rather than retargeting its path.
    public func setCalloutAppearance(anchor: Data, expectedID: String,
                                     expectedTone: String, expectedEmphasis: String,
                                     tone: String, emphasis: String) throws -> Data {
        let tones: Set<String> = ["neutral", "primary", "secondary", "accent", "info", "success", "warning", "error"]
        let emphases: Set<String> = ["soft", "strong"]
        guard tones.contains(tone), emphases.contains(emphasis),
              tone != expectedTone || emphasis != expectedEmphasis,
              integrationStatus().isComplete,
              try richProseProjection().isEditable else {
            throw Failure.unsupportedProseEdit
        }
        let (callout, path) = try anchoredElement(anchor)
        guard path.count == 1, callout.tag() == "callout" else { throw Failure.invalidAnchor }
        let attributes = try callout.attributes()
        guard attributes["relaymarkId"] as? String == expectedID,
              attributes["tone"] as? String == expectedTone,
              attributes["emphasis"] as? String == expectedEmphasis else {
            throw Failure.invalidAnchor
        }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            if tone != expectedTone { try callout.setAttribute("tone", value: tone, in: transaction) }
            if emphasis != expectedEmphasis { try callout.setAttribute("emphasis", value: emphasis, in: transaction) }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    ///  attribute commands retain the existing XML containers and text.
    /// Relative anchors fence the selected identity even when a peer shifts paths.
    public func setRichHeadingLevel(anchor: Data, expectedHeadingID: String?, level: Int) throws -> Data {
        guard (1...6).contains(level), integrationStatus().isComplete,
              try richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let (heading, _) = try anchoredElement(anchor)
        guard heading.tag() == "heading",
              try heading.attributes()["headingId"] as? String == expectedHeadingID else { throw Failure.invalidAnchor }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            try heading.setAttribute("level", value: level, in: transaction)
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    public func setRichOrderedListStart(anchor: Data, expectedStart: Int, start: Int) throws -> Data {
        guard (1...1_000_000).contains(start), integrationStatus().isComplete,
              try richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let (list, _) = try anchoredElement(anchor)
        guard list.tag() == "orderedList",
              (try list.attributes()["start"] as? Int ?? 1) == expectedStart else { throw Failure.invalidAnchor }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            try list.setAttribute("start", value: start, in: transaction)
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Change only an existing top-level heading's level. Its XML identity,
    /// headingId, inline marks and text are retained. The host binds the relative
    /// anchor to its authorized document/incarnation before calling this method.
    public func setHeadingLevel(anchor: Data, expectedHeadingID: String?, level: Int) throws -> Data {
        guard (1...6).contains(level), integrationStatus().isComplete,
              try proseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let (heading, path) = try anchoredElement(anchor)
        guard path.count == 1, heading.tag() == "heading" else { throw Failure.invalidAnchor }
        let attributes = try heading.attributes()
        guard attributes["headingId"] as? String == expectedHeadingID else { throw Failure.invalidAnchor }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            try heading.setAttribute("level", value: level, in: transaction)
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Change only an existing ordered-list start attribute. The command bound
    /// does not restrict otherwise valid stored lists. Child XML identities stay intact.
    public func setOrderedListStart(anchor: Data, expectedStart: Int, start: Int) throws -> Data {
        guard (1...1_000_000).contains(start), integrationStatus().isComplete,
              try proseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let (list, path) = try anchoredElement(anchor)
        guard (path.count == 1 || path.count == 3), list.tag() == "orderedList",
              let top = root.child(at: UInt32(path[0])) else { throw Failure.invalidAnchor }
        try validateEditableList(top, depth: 0)
        let current = try list.attributes()["start"] as? Int ?? 1
        guard current == expectedStart else { throw Failure.invalidAnchor }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            try list.setAttribute("start", value: start, in: transaction)
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Replace UTF-16 text in one existing list paragraph without rebuilding
    /// list/item nodes. Bounded scope: a list item starts with one paragraph
    /// containing one XmlText leaf and may have one nested bullet/ordered list.
    /// List conversion, indentation, splitting and cross-item edits are excluded.
    public func replaceListParagraphText(anchor: Data, start: Int, end: Int, text: String) throws -> Data {
        guard integrationStatus().isComplete, try proseProjection().isEditable else {
            throw Failure.unsupportedProseEdit
        }
        let (paragraph, path) = try anchoredElement(anchor)
        guard path.count == 3 || path.count == 5, paragraph.tag() == "paragraph",
              let top = root.child(at: UInt32(path[0])) else { throw Failure.invalidAnchor }
        try validateEditableList(top, depth: 0)
        // The target must be the first paragraph of a real list item, not an
        // arbitrary same-depth paragraph in another container.
        var ancestor = top
        for index in 1..<path.count {
            let expected = index % 2 == 1 ? "listItem" : (index == path.count - 1 ? "paragraph" : nil)
            guard let child = ancestor.child(at: UInt32(path[index])),
                  expected == nil || child.tag() == expected else { throw Failure.invalidAnchor }
            ancestor = child
        }
        let leaf = paragraph.child(at: 0)
        guard leaf == nil || leaf?.kind() == "text" else { throw Failure.unsupportedProseEdit }
        let old = try leaf?.delta().map(\.text).joined() ?? ""
        guard start >= 0, end >= start, end <= old.utf16.count,
              Self.split(old, at: start) != nil, Self.split(old, at: end) != nil,
              !text.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}" }),
              text.utf16.count <= 131_072, old.utf16.count - (end - start) + text.utf16.count <= 131_072 else {
            throw Failure.unsupportedProseEdit
        }
        if leaf == nil {
            guard start == 0, end == 0, !text.isEmpty else { throw Failure.unsupportedProseEdit }
            let update = try document.transactSync(origin: localOrigin) { transaction in
                let newText = try paragraph.insertText(at: 0, in: transaction)
                try newText.insert(text, at: 0, in: transaction)
                return Data(transaction.transactionEncodeUpdate())
            }
            wrapUndo()
            return update
        }
        return try replaceText(at: start, length: end - start, with: text, path: path + [0])
    }

    /// End-of-item Return only: insert an empty sibling without relocating any
    /// existing text or descendants. Interior splits and empty-item exit are not
    /// represented by this command.
    public func appendEmptyListItem(after paragraphAnchor: Data) throws -> Data {
        guard integrationStatus().isComplete, try proseProjection().isEditable else {
            throw Failure.unsupportedProseEdit
        }
        let (paragraph, path) = try anchoredElement(paragraphAnchor)
        guard path.count == 3 || path.count == 5, paragraph.tag() == "paragraph",
              let top = root.child(at: UInt32(path[0])) else { throw Failure.invalidAnchor }
        try validateEditableList(top, depth: 0)
        var list = root
        for index in path.dropLast(2) {
            guard let child = list.child(at: UInt32(index)) else { throw Failure.invalidAnchor }
            list = child
        }
        let itemIndex = path[path.count - 2]
        guard path.last == 0, let item = list.child(at: UInt32(itemIndex)),
              item.tag() == "listItem", item.length() == 1,
              let leaf = paragraph.child(at: 0), leaf.kind() == "text",
              try !leaf.delta().map(\.text).joined().isEmpty,
              list.length() < 4096,
              try String(proseProjection().text.characters).utf16.count < 131_072 else { throw Failure.unsupportedProseEdit }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            let next = try list.insertElement(named: "listItem", at: UInt32(itemIndex + 1), in: transaction)
            _ = try next.insertElement(named: "paragraph", at: 0, in: transaction)
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// TipTap's end-of-item Return for an admitted canonical list at any nesting level.
    /// The caller binds the paragraph anchor to an exact displayed snapshot;
    /// a sibling insert or changed text rejects before the live transaction.
    /// Existing list/item/paragraph XML nodes and ordered starts stay intact.
    public func appendEmptyRichListItem(after paragraphAnchor: Data,
                                               expectedSnapshot: Data) throws
        -> (update: Data, itemID: String, paragraphID: String) {
        try createEmptyRichListItem(relativeTo: paragraphAnchor, before: false, expectedSnapshot: expectedSnapshot)
    }

    public func prependEmptyRichListItem(before paragraphAnchor: Data, expectedSnapshot: Data) throws
        -> (update: Data, itemID: String, paragraphID: String) {
        try createEmptyRichListItem(relativeTo: paragraphAnchor, before: true, expectedSnapshot: expectedSnapshot)
    }

    private func createEmptyRichListItem(relativeTo paragraphAnchor: Data, before: Bool,
                                               expectedSnapshot: Data) throws
        -> (update: Data, itemID: String, paragraphID: String) {
        guard integrationStatus().isComplete, try snapshot() == expectedSnapshot,
              try richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let (_, path) = try richListEndTarget(paragraphAnchor)
        let itemID = "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let paragraphID = "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(encodeUpdate())
        guard try scratch.snapshot() == expectedSnapshot else { throw Failure.invalidAnchor }
        _ = try scratch.insertEmptyRichListItem(after: paragraphAnchor, path: path,
                                                      itemID: itemID, paragraphID: paragraphID, before: before)
        guard try scratch.richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let update = try insertEmptyRichListItem(after: paragraphAnchor, path: path,
                                                       itemID: itemID, paragraphID: paragraphID, before: before)
        return (update, itemID, paragraphID)
    }

    /// Split one existing nonempty canonical list paragraph at an interior grapheme
    /// boundary. The prefix keeps its XML text and stable IDs; suffix runs are
    /// copied with their original marks into a fresh sibling item/paragraph.
    public func splitRichListItem(at paragraphAnchor: Data, utf16Offset: Int,
                                         expectedSnapshot: Data) throws
        -> (update: Data, itemID: String, paragraphID: String) {
        guard integrationStatus().isComplete, try snapshot() == expectedSnapshot,
              try richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let (paragraph, path) = try richListEndTarget(paragraphAnchor)
        guard let leaf = paragraph.child(at: 0), leaf.kind() == "text" else { throw Failure.invalidAnchor }
        let old = try leaf.delta().map(\.text).joined()
        guard utf16Offset > 0, utf16Offset < old.utf16.count,
              Self.split(old, at: utf16Offset) != nil else { throw Failure.unsupportedProseEdit }
        let itemID = "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let paragraphID = "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(encodeUpdate())
        guard try scratch.snapshot() == expectedSnapshot else { throw Failure.invalidAnchor }
        _ = try scratch.insertSplitRichListItem(at: paragraphAnchor, path: path,
            offset: utf16Offset, itemID: itemID, paragraphID: paragraphID)
        guard try scratch.richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let update = try insertSplitRichListItem(at: paragraphAnchor, path: path,
            offset: utf16Offset, itemID: itemID, paragraphID: paragraphID)
        return (update, itemID, paragraphID)
    }

    private func insertSplitRichListItem(at anchor: Data, path: [Int], offset: Int,
                                                itemID: String, paragraphID: String) throws -> Data {
        let (paragraph, resolvedPath) = try richListEndTarget(anchor)
        guard resolvedPath == path, let leaf = paragraph.child(at: 0), leaf.kind() == "text" else {
            throw Failure.invalidAnchor
        }
        let old = try leaf.delta().map(\.text).joined()
        guard offset > 0, offset < old.utf16.count, Self.split(old, at: offset) != nil else {
            throw Failure.unsupportedProseEdit
        }
        let suffix = try Self.suffixRuns(of: leaf, after: offset)
        var list = root
        for index in path.dropLast(2) {
            guard let child = list.child(at: UInt32(index)) else { throw Failure.invalidAnchor }
            list = child
        }
        let position = UInt32(path[path.count - 2] + 1)
        let task = list.tag() == "taskList"
        let update = try document.transactSync(origin: localOrigin) { transaction in
            try leaf.removeText(start: UInt32(offset), length: UInt32(old.utf16.count - offset), in: transaction)
            let item = try list.insertElement(named: task ? "taskItem" : "listItem", at: position, in: transaction)
            try item.setAttribute("relaymarkId", value: itemID, in: transaction)
            if task { try item.setAttribute("checked", value: false, in: transaction) }
            let newParagraph = try item.insertElement(named: "paragraph", at: 0, in: transaction)
            try newParagraph.setAttribute("relaymarkId", value: paragraphID, in: transaction)
            let destination = try newParagraph.insertText(at: 0, in: transaction)
            var destinationOffset: UInt32 = 0
            for run in suffix where !run.text.isEmpty {
                try destination.insert(run.text, attributes: run.attributes,
                                       at: destinationOffset, in: transaction)
                destinationOffset += UInt32(run.text.utf16.count)
            }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// TipTap Enter on a final empty list item: leave a flat list for a
    /// top-level paragraph, or leave a one-item nested list for an outer item.
    /// The empty paragraph keeps its authored ID even though Yjs recreates its
    /// XML type; nested exit gives the new outer item a fresh ID.
    public func exitEmptyRichListItem(at paragraphAnchor: Data,
                                             expectedSnapshot: Data) throws
        -> (update: Data, newItemID: String?) {
        guard integrationStatus().isComplete, try snapshot() == expectedSnapshot,
              try richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let (path, paragraphID) = try richEmptyListExitTarget(paragraphAnchor)
        let newItemID = path.count == 5 ?
            "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "") : nil
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(encodeUpdate())
        guard try scratch.snapshot() == expectedSnapshot else { throw Failure.invalidAnchor }
        _ = try scratch.performRichListExit(anchor: paragraphAnchor, path: path,
                                                  paragraphID: paragraphID, newItemID: newItemID)
        guard try scratch.richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let update = try performRichListExit(anchor: paragraphAnchor, path: path,
                                                   paragraphID: paragraphID, newItemID: newItemID)
        return (update, newItemID)
    }

    private func richEmptyListExitTarget(_ anchor: Data) throws -> ([Int], String) {
        let (paragraph, path) = try anchoredElement(anchor)
        guard (path.count == 3 || path.count == 5), path.last == 0,
              paragraph.tag() == "paragraph", paragraph.length() == 0,
              let paragraphID = try paragraph.attributes()["relaymarkId"] as? String,
              let top = root.child(at: UInt32(path[0])),
              ["bulletList", "orderedList", "taskList"].contains(top.tag() ?? "") else { throw Failure.invalidAnchor }
        if path.count == 3 {
            guard path[1] == Int(top.length()) - 1,
                  let item = top.child(at: UInt32(path[1])),
                  item.tag() == (top.tag() == "taskList" ? "taskItem" : "listItem"),
                  item.length() == 1 else { throw Failure.unsupportedProseEdit }
        } else {
            guard let outer = top.child(at: UInt32(path[1])),
                  outer.tag() == (top.tag() == "taskList" ? "taskItem" : "listItem"),
                  outer.length() == 2,
                  let nested = outer.child(at: 1),
                  ["bulletList", "orderedList", "taskList"].contains(nested.tag() ?? ""),
                  nested.length() == 1, path[2] == 1, path[3] == 0,
                  let item = nested.child(at: 0),
                  item.tag() == (nested.tag() == "taskList" ? "taskItem" : "listItem"),
                  item.length() == 1 else { throw Failure.unsupportedProseEdit }
        }
        return (path, paragraphID)
    }

    private func performRichListExit(anchor: Data, path: [Int],
                                            paragraphID: String, newItemID: String?) throws -> Data {
        let (resolvedPath, resolvedID) = try richEmptyListExitTarget(anchor)
        guard resolvedPath == path, resolvedID == paragraphID,
              (path.count == 5) == (newItemID != nil),
              let top = root.child(at: UInt32(path[0])) else { throw Failure.invalidAnchor }
        let onlyItem = path.count == 3 && top.length() == 1
        let task = top.tag() == "taskList"
        let update = try document.transactSync(origin: localOrigin) { transaction in
            if path.count == 3 {
                if onlyItem {
                    try self.root.removeChildren(start: UInt32(path[0]), length: 1, in: transaction)
                } else {
                    try top.removeChildren(start: UInt32(path[1]), length: 1, in: transaction)
                }
                let paragraph = try self.root.insertElement(named: "paragraph",
                                                            at: UInt32(path[0] + (onlyItem ? 0 : 1)), in: transaction)
                try paragraph.setAttribute("relaymarkId", value: paragraphID, in: transaction)
            } else {
                guard let newItemID, let outer = top.child(at: UInt32(path[1]), in: transaction) else {
                    throw Failure.invalidAnchor
                }
                try outer.removeChildren(start: 1, length: 1, in: transaction)
                let item = try top.insertElement(named: task ? "taskItem" : "listItem",
                                                 at: UInt32(path[1] + 1), in: transaction)
                try item.setAttribute("relaymarkId", value: newItemID, in: transaction)
                if task { try item.setAttribute("checked", value: false, in: transaction) }
                let paragraph = try item.insertElement(named: "paragraph", at: 0, in: transaction)
                try paragraph.setAttribute("relaymarkId", value: paragraphID, in: transaction)
            }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    private func richListEndTarget(_ anchor: Data) throws -> (YXmlNode, [Int]) {
        let (paragraph, path) = try anchoredElement(anchor)
        guard path.count >= 3, path.last == 0,
              paragraph.tag() == "paragraph", paragraph.length() == 1,
              let leaf = paragraph.child(at: 0), leaf.kind() == "text",
              try !leaf.delta().map(\.text).joined().isEmpty else { throw Failure.invalidAnchor }
        var list = root
        for index in path.dropLast(2) {
            guard let child = list.child(at: UInt32(index)) else { throw Failure.invalidAnchor }
            list = child
        }
        guard ["bulletList", "orderedList", "taskList"].contains(list.tag() ?? ""),
              let item = list.child(at: UInt32(path[path.count - 2])),
              item.tag() == (list.tag() == "taskList" ? "taskItem" : "listItem"),
              item.length() == 1 else { throw Failure.unsupportedProseEdit }
        return (paragraph, path)
    }

    private func insertEmptyRichListItem(after anchor: Data, path: [Int],
                                                itemID: String, paragraphID: String, before: Bool = false) throws -> Data {
        let (_, resolvedPath) = try richListEndTarget(anchor)
        guard resolvedPath == path else { throw Failure.invalidAnchor }
        var list = root
        for index in path.dropLast(2) {
            guard let child = list.child(at: UInt32(index)) else { throw Failure.invalidAnchor }
            list = child
        }
        let position = UInt32(path[path.count - 2] + (before ? 0 : 1))
        let task = list.tag() == "taskList"
        let update = try document.transactSync(origin: localOrigin) { transaction in
            let item = try list.insertElement(named: task ? "taskItem" : "listItem", at: position, in: transaction)
            try item.setAttribute("relaymarkId", value: itemID, in: transaction)
            if task { try item.setAttribute("checked", value: false, in: transaction) }
            let paragraph = try item.insertElement(named: "paragraph", at: 0, in: transaction)
            try paragraph.setAttribute("relaymarkId", value: paragraphID, in: transaction)
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Insert a new task list after an existing top-level paragraph. The
    /// paragraph is never rebuilt or removed, so concurrent edits to its Yjs
    /// text are not discarded by creating the list.
    public func insertEmptyRichTaskList(after paragraphAnchor: Data,
                                               expectedSnapshot: Data) throws
        -> (update: Data, listID: String, itemID: String, paragraphID: String) {
        guard integrationStatus().isComplete, try snapshot() == expectedSnapshot,
              try richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let (_, path, _) = try richTopLevelParagraphTarget(paragraphAnchor)
        guard root.length() < 4_096 else { throw Failure.unsupportedProseEdit }
        func newID() -> String { "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "") }
        let listID = newID(), itemID = newID(), paragraphID = newID()
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(encodeUpdate())
        guard try scratch.snapshot() == expectedSnapshot else { throw Failure.invalidAnchor }
        _ = try scratch.performRichTaskListInsertion(after: paragraphAnchor, path: path,
            listID: listID, itemID: itemID, paragraphID: paragraphID)
        guard try scratch.richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let update = try performRichTaskListInsertion(after: paragraphAnchor, path: path,
            listID: listID, itemID: itemID, paragraphID: paragraphID)
        return (update, listID, itemID, paragraphID)
    }

    private func performRichTaskListInsertion(after anchor: Data, path: [Int],
                                                    listID: String, itemID: String,
                                                    paragraphID: String) throws -> Data {
        let (_, resolvedPath, _) = try richTopLevelParagraphTarget(anchor)
        guard resolvedPath == path else { throw Failure.invalidAnchor }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            let list = try self.root.insertElement(named: "taskList", at: UInt32(path[0] + 1), in: transaction)
            try list.setAttribute("relaymarkId", value: listID, in: transaction)
            let item = try list.insertElement(named: "taskItem", at: 0, in: transaction)
            try item.setAttribute("relaymarkId", value: itemID, in: transaction)
            try item.setAttribute("checked", value: false, in: transaction)
            let paragraph = try item.insertElement(named: "paragraph", at: 0, in: transaction)
            try paragraph.setAttribute("relaymarkId", value: paragraphID, in: transaction)
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Return in a top-level canonical paragraph creates one identified XML sibling.
    /// The original paragraph keeps its ID and any suffix carries its marks.
    /// A caller must bind the anchor and caret to an exact projected snapshot.
    public func returnInRichParagraph(at paragraphAnchor: Data, utf16Offset: Int,
                                            expectedSnapshot: Data) throws
        -> (update: Data, paragraphID: String) {
        guard integrationStatus().isComplete, try snapshot() == expectedSnapshot,
              try richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let (_, path, old) = try richTopLevelParagraphTarget(paragraphAnchor)
        guard utf16Offset >= 0, utf16Offset <= old.utf16.count,
              Self.split(old, at: utf16Offset) != nil,
              root.length() < 4_096 else { throw Failure.unsupportedProseEdit }
        let paragraphID = "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(encodeUpdate())
        guard try scratch.snapshot() == expectedSnapshot else { throw Failure.invalidAnchor }
        _ = try scratch.performRichParagraphReturn(anchor: paragraphAnchor, path: path,
            offset: utf16Offset, paragraphID: paragraphID)
        guard try scratch.richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let update = try performRichParagraphReturn(anchor: paragraphAnchor, path: path,
            offset: utf16Offset, paragraphID: paragraphID)
        return (update, paragraphID)
    }

    private func richTopLevelParagraphTarget(_ anchor: Data) throws
        -> (paragraph: YXmlNode, path: [Int], text: String) {
        let (paragraph, path) = try anchoredElement(anchor)
        let attrs = try paragraph.attributes()
        guard path.count == 1, ["paragraph", "heading"].contains(paragraph.tag() ?? ""),
              attrs["relaymarkId"] is String else { throw Failure.invalidAnchor }
        let projection = try richProseProjection()
        guard projection.isEditable,
              let row = projection.blockPaths.firstIndex(of: path),
              let range = Range(projection.blockRanges[row], in: String(projection.text.characters)) else {
            throw Failure.invalidAnchor
        }
        return (paragraph, path, String(String(projection.text.characters)[range]))
    }

    private func performRichParagraphReturn(anchor: Data, path: [Int], offset: Int,
                                                   paragraphID: String) throws -> Data {
        let (paragraph, resolvedPath, old) = try richTopLevelParagraphTarget(anchor)
        guard resolvedPath == path, offset >= 0, offset <= old.utf16.count,
              Self.split(old, at: offset) != nil else { throw Failure.invalidAnchor }
        // Split at the rendered inline boundary. Keep all prefix XML nodes
        // integrated; copy only the suffix that moves to the new sibling.
        // References, tags and hard breaks occupy one native selection unit.
        let children = paragraph.children()
        var consumed = 0
        var suffix: [[String: Any]] = []
        var removedChildrenStart = children.count
        var splitLeaf: (node: YXmlNode, offset: Int, length: Int)?
        for (index, child) in children.enumerated() {
            let width = child.kind() == "text" ? try child.delta().map(\.text).joined().utf16.count : 1
            if consumed + width <= offset {
                consumed += width
                continue
            }
            if consumed < offset {
                guard child.kind() == "text" else { throw Failure.invalidAnchor }
                let localOffset = offset - consumed
                let runs = try Self.suffixRuns(of: child, after: localOffset)
                suffix.append(["kind": "text", "delta": runs.map { run -> [String: Any] in
                    var value: [String: Any] = ["insert": run.text]
                    if !run.attributes.isEmpty { value["attributes"] = run.attributes }
                    return value
                }])
                splitLeaf = (child, localOffset, width - localOffset)
                removedChildrenStart = index + 1
            } else {
                suffix.append(try snapshot(child))
                removedChildrenStart = index
            }
            suffix.append(contentsOf: try children.dropFirst(index + 1).map(snapshot))
            break
        }
        let heading = paragraph.tag() == "heading"
        let headingLevel = try paragraph.attributes()["level"] as? Int ?? 1
        let update = try document.transactSync(origin: localOrigin) { transaction in
            // At the start, keep the original heading and its text identity intact.
            if heading && offset == 0 && !old.isEmpty {
                let preceding = try self.root.insertElement(named: "paragraph", at: UInt32(path[0]), in: transaction)
                try preceding.setAttribute("relaymarkId", value: paragraphID, in: transaction)
                return Data(transaction.transactionEncodeUpdate())
            }
            if let splitLeaf {
                try splitLeaf.node.removeText(start: UInt32(splitLeaf.offset),
                    length: UInt32(splitLeaf.length), in: transaction)
            }
            if removedChildrenStart < children.count {
                try paragraph.removeChildren(start: UInt32(removedChildrenStart),
                    length: UInt32(children.count - removedChildrenStart), in: transaction)
            }
            let nextIsHeading = heading && offset < old.utf16.count
            let next = try self.root.insertElement(named: nextIsHeading ? "heading" : "paragraph", at: UInt32(path[0] + 1), in: transaction)
            try next.setAttribute("relaymarkId", value: paragraphID, in: transaction)
            if nextIsHeading {
                try next.setAttribute("level", value: headingLevel, in: transaction)
                try next.setAttribute("headingId", value: "h-" + paragraphID, in: transaction)
            }
            for (index, raw) in suffix.enumerated() {
                if raw["kind"] as? String == "text" {
                    let leaf = try next.insertText(at: UInt32(index), in: transaction)
                    var destinationOffset: UInt32 = 0
                    for run in raw["delta"] as? [[String: Any]] ?? [] {
                        guard let text = run["insert"] as? String else { throw Failure.unsupportedProseEdit }
                        try leaf.insert(text, attributes: run["attributes"] as? [String: Any] ?? [:],
                            at: destinationOffset, in: transaction)
                        destinationOffset += UInt32(text.utf16.count)
                    }
                } else {
                    guard let name = raw["name"] as? String,
                          ["hardBreak", "relayReference", "relayTag"].contains(name),
                          (raw["children"] as? [Any] ?? []).isEmpty else { throw Failure.unsupportedProseEdit }
                    let atom = try next.insertElement(named: name, at: UInt32(index), in: transaction)
                    for (key, value) in try PMYXmlBridge.orderedAttributes(nodeName: name, values: raw["attributes"] as? [String: Any] ?? [:]) {
                        try atom.setAttribute(key, value: value, in: transaction)
                    }
                }
            }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Return inside a canonical quote uses the same identified paragraph shape as
    /// TipTap. The existing quote and paragraph retain their IDs; only the
    /// new paragraph receives an ID. The host binds the anchor to one exact
    /// snapshot and caret position before invoking this command.
    public func returnInRichQuote(at paragraphAnchor: Data, utf16Offset: Int,
                                        expectedSnapshot: Data) throws
        -> (update: Data, kind: RichQuoteReturnKind, paragraphID: String) {
        guard integrationStatus().isComplete, try snapshot() == expectedSnapshot,
              try richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let (paragraph, quote, path, old) = try richQuoteTarget(paragraphAnchor)
        guard utf16Offset >= 0, utf16Offset <= old.utf16.count,
              Self.split(old, at: utf16Offset) != nil else { throw Failure.unsupportedProseEdit }
        let kind: RichQuoteReturnKind
        if old.isEmpty {
            guard path[1] == Int(quote.length()) - 1 else { throw Failure.unsupportedProseEdit }
            kind = .exit
        } else if utf16Offset == old.utf16.count {
            guard quote.length() < 4_096 else { throw Failure.unsupportedProseEdit }
            kind = .append
        } else {
            guard utf16Offset > 0, quote.length() < 4_096,
                  paragraph.child(at: 0)?.kind() == "text" else { throw Failure.unsupportedProseEdit }
            kind = .split
        }
        let paragraphID = kind == .exit
            ? try quoteParagraphID(paragraph)
            : "b" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(encodeUpdate())
        guard try scratch.snapshot() == expectedSnapshot else { throw Failure.invalidAnchor }
        _ = try scratch.performRichQuoteReturn(anchor: paragraphAnchor, path: path,
            offset: utf16Offset, kind: kind, paragraphID: paragraphID)
        guard try scratch.richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let update = try performRichQuoteReturn(anchor: paragraphAnchor, path: path,
            offset: utf16Offset, kind: kind, paragraphID: paragraphID)
        return (update, kind, paragraphID)
    }

    public enum RichQuoteReturnKind: Equatable { case append, split, exit }

    private func quoteParagraphID(_ paragraph: YXmlNode) throws -> String {
        guard let id = try paragraph.attributes()["relaymarkId"] as? String else { throw Failure.invalidAnchor }
        return id
    }

    private func richQuoteTarget(_ anchor: Data) throws
        -> (paragraph: YXmlNode, quote: YXmlNode, path: [Int], text: String) {
        let (paragraph, path) = try anchoredElement(anchor)
        guard path.count == 2, paragraph.tag() == "paragraph",
              let quote = root.child(at: UInt32(path[0])), quote.tag() == "blockquote",
              path[1] < Int(quote.length()), paragraph.length() <= 1 else { throw Failure.invalidAnchor }
        _ = try quoteParagraphID(paragraph)
        let leaf = paragraph.child(at: 0)
        guard leaf == nil || leaf?.kind() == "text" else { throw Failure.invalidAnchor }
        return (paragraph, quote, path, try leaf?.delta().map(\.text).joined() ?? "")
    }

    private func performRichQuoteReturn(anchor: Data, path: [Int], offset: Int,
                                               kind: RichQuoteReturnKind,
                                               paragraphID: String) throws -> Data {
        let (paragraph, quote, resolvedPath, old) = try richQuoteTarget(anchor)
        guard resolvedPath == path, offset >= 0, offset <= old.utf16.count,
              Self.split(old, at: offset) != nil else { throw Failure.invalidAnchor }
        let suffix: [TextRun]
        if kind == .split {
            guard offset > 0, offset < old.utf16.count,
                  let leaf = paragraph.child(at: 0) else { throw Failure.invalidAnchor }
            suffix = try Self.suffixRuns(of: leaf, after: offset)
        } else { suffix = [] }
        let existingParagraphID = try quoteParagraphID(paragraph)
        guard kind != .exit || (old.isEmpty && path[1] == Int(quote.length()) - 1 &&
              existingParagraphID == paragraphID) else { throw Failure.invalidAnchor }
        guard kind != .append || (!old.isEmpty && offset == old.utf16.count) else {
            throw Failure.invalidAnchor
        }
        let exitRemovesQuote = kind == .exit && quote.length() == 1
        let splitLeaf = kind == .split ? paragraph.child(at: 0) : nil
        let update = try document.transactSync(origin: localOrigin) { transaction in
            if kind == .exit {
                try quote.removeChildren(start: UInt32(path[1]), length: 1, in: transaction)
                let insertAt: UInt32
                if exitRemovesQuote {
                    try self.root.removeChildren(start: UInt32(path[0]), length: 1, in: transaction)
                    insertAt = UInt32(path[0])
                } else { insertAt = UInt32(path[0] + 1) }
                let newParagraph = try self.root.insertElement(named: "paragraph", at: insertAt, in: transaction)
                try newParagraph.setAttribute("relaymarkId", value: paragraphID, in: transaction)
            } else {
                if kind == .split {
                    guard let leaf = splitLeaf else { throw Failure.invalidAnchor }
                    try leaf.removeText(start: UInt32(offset), length: UInt32(old.utf16.count - offset), in: transaction)
                }
                let newParagraph = try quote.insertElement(named: "paragraph", at: UInt32(path[1] + 1), in: transaction)
                try newParagraph.setAttribute("relaymarkId", value: paragraphID, in: transaction)
                if !suffix.isEmpty {
                    let leaf = try newParagraph.insertText(at: 0, in: transaction)
                    var destinationOffset: UInt32 = 0
                    for run in suffix where !run.text.isEmpty {
                        try leaf.insert(run.text, attributes: run.attributes,
                                        at: destinationOffset, in: transaction)
                        destinationOffset += UInt32(run.text.utf16.count)
                    }
                }
            }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    private func anchoredElement(_ anchor: Data) throws -> (YXmlNode, [Int]) {
        guard let resolved = try document.resolveXmlRelativePosition(anchor), resolved.index == 0,
              resolved.node.kind() == "element", let path = path(to: resolved.node, from: root), !path.isEmpty else {
            throw Failure.invalidAnchor
        }
        return (resolved.node, path)
    }

    private func validateEditableList(_ list: YXmlNode, depth: Int) throws {
        guard depth <= 1, list.kind() == "element", let tag = list.tag(), ["bulletList", "orderedList"].contains(tag),
              list.length() > 0 else { throw Failure.unsupportedProseEdit }
        // proseProjection already validates v1 list attributes and text marks.
        for item in list.children() {
            guard item.kind() == "element", item.tag() == "listItem", try item.attributes().isEmpty,
                  (1...2).contains(item.length()), let paragraph = item.child(at: 0),
                  paragraph.tag() == "paragraph", try paragraph.attributes().isEmpty, paragraph.length() <= 1 else { throw Failure.unsupportedProseEdit }
            let text = paragraph.child(at: 0)
            guard text == nil || text?.kind() == "text" else { throw Failure.unsupportedProseEdit }
            let value = try text?.delta().map(\.text).joined() ?? ""
            guard !value.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}" }) else {
                throw Failure.unsupportedProseEdit
            }
            if let nested = item.child(at: 1) { try validateEditableList(nested, depth: depth + 1) }
        }
    }

    /// A task item in the negotiated collaborative XML. `anchor` is a Yjs
    /// relative position tied to the XML item identity, including unlinked
    /// checklist items. The host still binds it to an authorized document.
    public struct TaskItem: Equatable, Sendable {
        public let anchor: Data
        public let entityID: String?
        public let checked: Bool
        public let paragraphs: [String]
    }

    private struct TaskRecord {
        let node: YXmlNode
        let item: TaskItem
    }

    /// Read task lists without making them eligible for the ordinary prose
    /// editor. Unknown task/item metadata and unsupported nested content fail
    /// closed; no XML is flattened or rewritten.
    public func taskItems(rich: Bool = false) throws -> [TaskItem] {
        try taskRecords(rich: rich).map(\.item)
    }

    /// Toggle a specific existing XML item. Resolve its relative position and
    /// revalidate its UUID immediately before mutation, so sibling insertion
    /// cannot retarget an unlinked item through a stale numeric path.
    public func setTaskItemChecked(anchor: Data, expectedEntityID: String?, checked: Bool,
                                   rich: Bool = false) throws -> Data {
        let record = try taskRecord(anchor: anchor, expectedEntityID: expectedEntityID,
                                    rich: rich)
        let update = try document.transactSync(origin: localOrigin) { transaction in
            try record.node.setAttribute("checked", value: checked, in: transaction)
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Toggle an identified canonical task at any supported nesting depth. The
    /// current whole-document contract and the item's stable ID guard a path
    /// that may have shifted after a remote insertion.
    public func setRichTaskItemChecked(path: [Int], expectedID: String,
                                             expectedEntityID: String?, expectedChecked: Bool,
                                             checked: Bool) throws -> Data {
        guard integrationStatus().isComplete, path.count >= 2, checked != expectedChecked,
              Self.validTaskID(["relaymarkId": expectedID]) else {
            throw Failure.unsupportedProseEdit
        }
        _ = try RelayMarkNativeDocumentProjection.project(document: self)
        var node = root
        var parent: YXmlNode?
        for index in path {
            guard index >= 0, let child = node.child(at: UInt32(index)) else { throw Failure.invalidAnchor }
            parent = node
            node = child
        }
        guard parent?.tag() == "taskList", node.kind() == "element", node.tag() == "taskItem" else {
            throw Failure.invalidAnchor
        }
        let attributes = try node.attributes()
        guard attributes["relaymarkId"] as? String == expectedID,
              (attributes["entityId"] as? String) == expectedEntityID else {
            throw Failure.invalidAnchor
        }
        let current: Bool
        if let value = attributes["checked"] {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else { throw Failure.unsupportedProseEdit }
            current = number.boolValue
        } else { current = false }
        guard current == expectedChecked else { throw Failure.invalidAnchor }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            try node.setAttribute("checked", value: checked, in: transaction)
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    /// Edit a one-paragraph, one-text-leaf item without replacing the task
    /// container or its UUID. More complex nested content remains read-only.
    public func replaceTaskItemText(anchor: Data, expectedEntityID: String?,
                                    start: Int, end: Int, text: String,
                                    rich: Bool = false) throws -> Data {
        let record = try taskRecord(anchor: anchor, expectedEntityID: expectedEntityID,
                                    rich: rich)
        guard record.node.length() == 1,
              let paragraph = record.node.child(at: 0), paragraph.tag() == "paragraph",
              (try rich ? Self.validTaskID(paragraph.attributes()) : paragraph.attributes().isEmpty),
              paragraph.length() == 1,
              let leaf = paragraph.child(at: 0), leaf.kind() == "text",
              let old = record.item.paragraphs.first,
              start >= 0, end >= start, end <= old.utf16.count,
              Self.split(old, at: start) != nil, Self.split(old, at: end) != nil,
              !text.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}" }),
              text.utf16.count <= 131_072, old.utf16.count - (end - start) + text.utf16.count <= 131_072 else {
            throw Failure.unsupportedProseEdit
        }
        let update = try document.transactSync(origin: localOrigin) { transaction in
            if end > start {
                try leaf.removeText(start: UInt32(start), length: UInt32(end - start), in: transaction)
            }
            if !text.isEmpty { try leaf.insert(text, at: UInt32(start), in: transaction) }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    private func taskRecord(anchor: Data, expectedEntityID: String?,
                            rich: Bool) throws -> TaskRecord {
        guard let resolved = try document.resolveXmlRelativePosition(anchor), resolved.index == 0,
              let record = try taskRecords(rich: rich).first(where: { $0.node.isSameNode(as: resolved.node) }),
              record.item.entityID == expectedEntityID else { throw Failure.invalidAnchor }
        return record
    }

    private func taskRecords(rich: Bool) throws -> [TaskRecord] {
        guard integrationStatus().isComplete else { throw Failure.unsupportedProseEdit }
        if rich { _ = try RelayMarkNativeDocumentProjection.project(document: self) }
        var result: [TaskRecord] = []
        for list in root.children() {
            guard list.tag() == "taskList" else {
                if containsTaskNode(list) { throw Failure.unsupportedProseEdit }
                continue
            }
            guard list.kind() == "element",
                  (try rich ? Self.validTaskID(list.attributes()) : list.attributes().isEmpty) else {
                throw Failure.unsupportedProseEdit
            }
            for item in list.children() {
                guard item.kind() == "element", item.tag() == "taskItem" else { throw Failure.unsupportedProseEdit }
                let attributes = try item.attributes()
                let allowed = rich ? Set(["relaymarkId", "checked", "entityId"]) : Set(["checked", "entityId"])
                guard Set(attributes.keys).isSubset(of: allowed),
                      (!rich || Self.validTaskID(attributes)), item.length() > 0 else {
                    throw Failure.unsupportedProseEdit
                }
                let checked: Bool
                if let value = attributes["checked"] {
                    guard let number = value as? NSNumber,
                          CFGetTypeID(number) == CFBooleanGetTypeID() else { throw Failure.unsupportedProseEdit }
                    checked = number.boolValue
                } else { checked = false }
                let entityID: String?
                if let value = attributes["entityId"], !(value is NSNull) {
                    guard let id = value as? String,
                          id.range(of: #"\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z"#,
                                   options: .regularExpression) != nil else { throw Failure.unsupportedProseEdit }
                    entityID = id
                } else { entityID = nil }
                var paragraphs: [String] = []
                for paragraph in item.children() {
                    guard paragraph.kind() == "element", paragraph.tag() == "paragraph",
                          (try rich ? Self.validTaskID(paragraph.attributes()) : paragraph.attributes().isEmpty) else {
                        throw Failure.unsupportedProseEdit
                    }
                    var content = ""
                    for inline in paragraph.children() {
                        if inline.kind() == "text" {
                            let runs = try inline.delta()
                            guard runs.allSatisfy({ run in
                                run.attributes.isEmpty && !run.text.unicodeScalars.contains(where: {
                                    $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}"
                                })
                            }) else { throw Failure.unsupportedProseEdit }
                            content += runs.map(\.text).joined()
                        } else if inline.kind() == "element", inline.tag() == "hardBreak",
                                  try inline.attributes().isEmpty, inline.length() == 0 {
                            content += "\u{2028}"
                        } else { throw Failure.unsupportedProseEdit }
                    }
                    paragraphs.append(content)
                }
                result.append(TaskRecord(node: item,
                    item: TaskItem(anchor: try item.relativePosition(at: 0), entityID: entityID,
                                   checked: checked, paragraphs: paragraphs)))
            }
        }
        return result
    }

    private static func validTaskID(_ attributes: [String: Any]) -> Bool {
        guard let id = attributes["relaymarkId"] as? String,
              id.range(of: #"\Ab[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}\z"#,
                       options: .regularExpression) != nil else { return false }
        return true
    }

    private func containsTaskNode(_ node: YXmlNode) -> Bool {
        if node.tag() == "taskList" || node.tag() == "taskItem" { return true }
        guard node.kind() == "element" || node.kind() == "fragment" else { return false }
        return node.children().contains(where: containsTaskNode)
    }

    /// Called only after the recovery adapter validates the complete prospective XML.
    func appendRecoveryNodes(_ nodes: [[String: Any]]) throws -> Data {
        try replaceSnapshotNodes(parentPath: [], start: Int(root.length()), count: 0, nodes: nodes)
    }

    /// Writes a transformed ProseMirror document through y-prosemirror's
    /// updateYFragment diff as one local transaction and one undo item.
    func applyProseMirror(_ updated: PMNode, source: PMNode, bridge: PMYXmlBridge) throws -> Data {
        let metadataReplacement=try JSONDecoder().decode([String:RelayMarkValue].self,from:JSONSerialization.data(withJSONObject:updated.attrs["relaymark"] ?? [:]))
        wrapUndo()
        let update = try document.transactSync(origin: localOrigin) { transaction in
            try bridge.update(self.root, updated, source: source, in: transaction)
            do {
                let existing=self.metadata.toMap(transaction:transaction)
                for key in existing.keys.sorted() where metadataReplacement[key]==nil {_ = self.metadata.removeValue(forKey:key,transaction:transaction)}
                for key in metadataReplacement.keys.sorted() where existing[key] != metadataReplacement[key] {self.metadata.updateValue(metadataReplacement[key]!,forKey:key,transaction:transaction)}
            }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    struct SnapshotNodeReplacement {
        let parentPath: [Int]
        let start: Int
        let count: Int
        let nodes: [[String: Any]]
    }

    /// Attribute-only change on an existing element, as y-prosemirror emits for
    /// setNodeMarkup without a type change. NSNull removes the attribute.
    struct SnapshotAttributeUpdate {
        let path: [Int]
        let attributes: [String: Any]
    }

    struct SnapshotTextRemoval {
        let path: [Int]
        let start: Int
        let count: Int
    }

    /// Shared XML insertion for validated editor/recovery operations, not a document codec.
    func replaceSnapshotNodes(parentPath: [Int], start: Int, count: Int, nodes: [[String: Any]]) throws -> Data {
        try replaceSnapshotNodes([SnapshotNodeReplacement(parentPath: parentPath, start: start, count: count, nodes: nodes)])
    }

    /// Resolve each existing parent before editing. A list lift/sink can then
    /// retain untouched ancestors and change both locations in one undo item.
    func replaceSnapshotNodes(_ replacements: [SnapshotNodeReplacement],
                              textRemovals: [SnapshotTextRemoval] = [],
                              attributeUpdates: [SnapshotAttributeUpdate] = [],
                              metadataUpdates: [String:RelayMarkValue] = [:],
                              origin: Origin? = nil) throws -> Data {
        let attributeTargets = try attributeUpdates.map { update -> (YXmlNode, [String: Any]) in
            var node = root
            for index in update.path {
                guard let index = UInt32(exactly: index), let child = node.child(at: index) else { throw Failure.invalidTextPath }
                node = child
            }
            guard node.kind() == "element" else { throw Failure.invalidTextPath }
            return (node, update.attributes)
        }
        let textTargets = try textRemovals.map { removal -> (YXmlNode, UInt32, UInt32) in
            var leaf = root
            for index in removal.path {
                guard let index = UInt32(exactly: index), let child = leaf.child(at: index) else { throw Failure.invalidTextPath }
                leaf = child
            }
            guard leaf.kind() == "text", let start = UInt32(exactly: removal.start),
                  let count = UInt32(exactly: removal.count), start <= leaf.length(),
                  count <= leaf.length() - start else { throw Failure.invalidTextPath }
            return (leaf, start, count)
        }
        let targets = try replacements.map { replacement -> (YXmlNode, UInt32, UInt32, [[String: Any]]) in
            var parent = root
            for index in replacement.parentPath {
                guard let index = UInt32(exactly: index), let child = parent.child(at: index) else { throw Failure.invalidTextPath }
                parent = child
            }
            guard let first = UInt32(exactly: replacement.start), let removed = UInt32(exactly: replacement.count),
                  first <= parent.length(), removed <= parent.length() - first else { throw Failure.invalidTextPath }
            return (parent, first, removed, replacement.nodes)
        }
        wrapUndo()
        let update = try document.transactSync(origin: origin ?? localOrigin) { transaction in
            func append(_ raw: [String: Any], to parent: YXmlNode, at index: UInt32) throws {
                if raw["kind"] as? String == "text" {
                    let leaf = try parent.insertText(at: index, in: transaction)
                    for run in raw["delta"] as? [[String: Any]] ?? [] {
                        guard let text = run["insert"] as? String else { throw Failure.unsupportedProseEdit }
                        try leaf.insert(text, attributes: run["attributes"] as? [String: Any] ?? [:],
                            at: leaf.length(in: transaction), in: transaction)
                    }
                } else {
                    guard let name = raw["name"] as? String else { throw Failure.unsupportedProseEdit }
                    let node = try parent.insertElement(named: name, at: index, in: transaction)
                    for (key, value) in try PMYXmlBridge.orderedAttributes(nodeName: name, values: raw["attributes"] as? [String: Any] ?? [:]) {
                        try node.setAttribute(key, value: value, in: transaction)
                    }
                    for child in raw["children"] as? [[String: Any]] ?? [] {
                        try append(child, to: node, at: node.length(in: transaction))
                    }
                }
            }
            for (key,value) in metadataUpdates { self.metadata.updateValue(value,forKey:key,transaction:transaction) }
            for (node, attributes) in attributeTargets {
                guard let name = node.tag(in: transaction) else { throw Failure.unsupportedProseEdit }
                // Finite snapshot normalization can explicitly remove obsolete
                // attributes absent from the live canonical schema. Never add them.
                for key in attributes.keys.sorted() where attributes[key] is NSNull {
                    try node.removeAttribute(key, in: transaction)
                }
                for (key, value) in try PMYXmlBridge.orderedAttributes(nodeName: name,
                    values: attributes.filter { !($0.value is NSNull) }) {
                    try node.setAttribute(key, value: value, in: transaction)
                }
            }
            for (leaf, start, count) in textTargets where count > 0 {
                try leaf.removeText(start: start, length: count, in: transaction)
            }
            for (parent, first, removed, nodes) in targets {
                if removed > 0 { try parent.removeChildren(start: first, length: removed, in: transaction) }
                for (offset, node) in nodes.enumerated() { try append(node, to: parent, at: first + UInt32(offset)) }
            }
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    private func snapshot(_ node: YXmlNode) throws -> [String: Any] {
        switch node.kind() {
        case "fragment":
            return ["kind": "fragment", "children": try node.children().map(snapshot)]
        case "element":
            guard let tag = node.tag() else { throw Failure.unsupportedXMLNode("missing element tag") }
            return ["kind": "element", "name": tag, "attributes": try node.attributes(),
                    "children": try node.children().map(snapshot)]
        case "text":
            let delta: [[String: Any]] = try node.delta().map { run in
                if run.attributes.isEmpty { return ["insert": run.text] }
                return ["insert": run.text, "attributes": run.attributes]
            }
            return ["kind": "text", "delta": delta]
        default:
            throw Failure.unsupportedXMLNode(node.kind())
        }
    }
}
