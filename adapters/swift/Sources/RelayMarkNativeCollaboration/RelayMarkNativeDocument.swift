import Foundation
import RelayMarkModel
import CoreFoundation
import RelayMarkProseProjection
import YSwift
import Yniffi
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
        /// A command on a list's items changed the list itself; it runs again on the whole list.
        case containerChanged
    }

    private let document: YDocument
    private let root: YXmlNode
    private let metadata: YMap<RelayMarkValue>
    private let localOrigin: Origin
    /// Tracks only this document's local origin, so undo never reverts a peer's edit.
    private let undoManager: YUndoManager<NSObject>
    public let presence: RelayMarkNativePresence

    public init(guid: String = UUID().uuidString) {
        let document = YDocument(guid: guid, retainDeletedItems: false)
        let root = document.getOrCreateXmlFragment(named: "default")
        let metadata: YMap<RelayMarkValue> = document.getOrCreateMap(named:"relaymark")
        let origin = Origin(UUID().uuidString)
        let undoManager: YUndoManager<NSObject> = document.undoManager(trackedRefs: [root,metadata])
        undoManager.addOrigin(origin)
        undoManager.preserveChangedXML()
        self.document = document
        self.root = root
        self.metadata = metadata
        localOrigin = origin
        self.undoManager = undoManager
        presence = RelayMarkNativePresence(awareness: document.makeAwareness())
    }

    public var documentGUID: String { document.guid }

    private var undoGroupDepth = 0
    private var editorCommandDepth = 0

    /// Closes the current undo item unless an enclosing group or editor command is open.
    private func wrapUndo() {
        if undoGroupDepth == 0 && editorCommandDepth == 0 { undoManager.wrap() }
    }

    /// Runs one editor command. Consecutive ordinary edits join the current undo
    /// item, as the Yjs UndoManager capture timeout groups a typing burst; a
    /// semantic command (a paste, a block insertion) is its own item.
    public func editorCommand<T>(separateUndoItem: Bool = false, _ body: () throws -> T) rethrows -> T {
        if separateUndoItem, undoGroupDepth == 0 { undoManager.wrap() }
        editorCommandDepth += 1
        defer {
            editorCommandDepth -= 1
            if separateUndoItem, undoGroupDepth == 0 { undoManager.wrap() }
        }
        return try body()
    }

    /// Ends the current undo item so the next edit starts a new one.
    public func closeUndoItem() { if undoGroupDepth == 0 { undoManager.wrap() } }

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

    /// Advances on every local or applied change. Hosts key derived views to it.
    public private(set) var revision = 0

    public func applyUpdate(_ update: Data) throws {
        revision &+= 1
        let rootCount = Int(root.length())
        try document.transactSync { transaction in
            try transaction.transactionApplyUpdate(update: Array(update))
        }
        lastUpdate = (revision, rootCount, RelayMarkUpdateFootprint(update))
    }

    /// The last applied update's items, with the paper's top-level count before it.
    private var lastUpdate: (revision: Int, rootCount: Int, footprint: RelayMarkUpdateFootprint?)?

    /// The text leaves the last applied update changed, when it only inserted,
    /// deleted or formatted text inside existing leaves; nil when it changed
    /// structure. A host re-projects just these leaves instead of the paper.
    public func textLeavesTouchedByLastUpdate() -> [[Int]]? {
        guard let lastUpdate, lastUpdate.revision == revision,
              let footprint = lastUpdate.footprint, footprint.textOnly else { return nil }
        return document.transactSync { transaction -> [[Int]]? in
            var identities: Set<Data> = [], paths: [[Int]] = []
            for (index, id) in footprint.touched.enumerated() {
                // Each item resolves to the text node holding it, named by its own sticky index.
                guard let resolved = try? self.document.resolveXmlRelativePosition(
                          RelayMarkUpdateFootprint.stickyIndex(id), in: transaction) else {
                    // A deleted item inside an already removed node changes nothing visible.
                    if index >= footprint.insertedCount { continue } else { return nil }
                }
                guard resolved.node.kind(in: transaction) == "text",
                      let identity = try? resolved.node.relativePosition(at: 0, association: -1, in: transaction) else { return nil }
                guard identities.insert(identity).inserted else { continue }
                guard let path = self.livePath(of: resolved.node, in: transaction) else { return nil }
                paths.append(path)
            }
            return paths
        }
    }

    /// The top-level nodes the last applied update may have changed: the range
    /// they held before it and the range they hold now. Nodes outside both are
    /// untouched, so a host re-projects only these. Nil when unknown.
    public func topLevelNodesTouchedByLastUpdate() -> (before: Range<Int>, after: Range<Int>)? {
        guard let lastUpdate, lastUpdate.revision == revision, let footprint = lastUpdate.footprint else { return nil }
        return topLevelNodesTouched(by: footprint, rootCountBefore: lastUpdate.rootCount)
    }

    /// The same for a local change this replica just made, given the paper's
    /// top-level count before it: only the nodes the update itself touched.
    public func topLevelNodesTouched(by update: Data, rootCountBefore: Int) -> (before: Range<Int>, after: Range<Int>)? {
        RelayMarkUpdateFootprint(update).flatMap { topLevelNodesTouched(by: $0, rootCountBefore: rootCountBefore) }
    }

    private func topLevelNodesTouched(by footprint: RelayMarkUpdateFootprint,
                                      rootCountBefore: Int) -> (before: Range<Int>, after: Range<Int>)? {
        document.transactSync { transaction -> (before: Range<Int>, after: Range<Int>)? in
            let count = Int(self.root.length(in: transaction))
            var lower = count, upper = 0
            for (index, id) in footprint.touched.enumerated() {
                // Items inside a node removed by this update cannot resolve; the node's own item does.
                guard let resolved = try? self.document.resolveXmlRelativePosition(
                          RelayMarkUpdateFootprint.stickyIndex(id), in: transaction) else {
                    if index >= footprint.insertedCount { continue } else { return nil }
                }
                guard let path = self.climb(from: resolved.node, in: transaction) else { return nil }
                // A removed node resolves to where it was; re-projecting its neighbour too is harmless.
                let top = path.first ?? Int(resolved.index)
                lower = min(lower, top); upper = max(upper, min(top + 1, count))
            }
            guard lower <= upper else { return (0..<0, 0..<0) }
            let before = rootCountBefore - (count - upper)
            guard before >= lower else { return nil }
            return (lower..<before, lower..<upper)
        }
    }

    /// When the last applied update changed only items of one top-level list,
    /// that list, the item range it now holds and its item count now; nil
    /// otherwise. The host checks the list's own attributes are unchanged.
    public func itemsTouchedByLastUpdate() -> (node: Int, after: Range<Int>, count: Int)? {
        guard let lastUpdate, lastUpdate.revision == revision, let footprint = lastUpdate.footprint else { return nil }
        return itemsTouched(by: footprint)
    }

    /// The same for a local change this replica just made.
    public func itemsTouched(by update: Data) -> (node: Int, after: Range<Int>, count: Int)? {
        RelayMarkUpdateFootprint(update).flatMap(itemsTouched(by:))
    }

    private func itemsTouched(by footprint: RelayMarkUpdateFootprint) -> (node: Int, after: Range<Int>, count: Int)? {
        document.transactSync { transaction -> (node: Int, after: Range<Int>, count: Int)? in
            var node: Int?, lower = Int.max, upper = Int.min, count = 0
            for (index, id) in footprint.touched.enumerated() {
                guard let resolved = try? self.document.resolveXmlRelativePosition(
                          RelayMarkUpdateFootprint.stickyIndex(id), in: transaction) else {
                    if index >= footprint.insertedCount { continue } else { return nil }
                }
                guard let path = self.climb(from: resolved.node, in: transaction), let first = path.first else { return nil }
                if node == nil {
                    node = first
                    guard let list = self.root.child(at: UInt32(first), in: transaction) else { return nil }
                    count = Int(list.length(in: transaction))
                }
                guard node == first else { return nil }
                let item: Int
                if path.count == 1 {
                    // An item added or removed directly in the list; a new value there is the list's own attribute.
                    if index < footprint.insertedCount, !footprint.insertedNodes[index] { return nil }
                    item = Int(resolved.index)
                } else { item = path[1] }
                lower = min(lower, item); upper = max(upper, min(item + 1, count))
            }
            guard let node else { return nil }
            return (node, lower <= upper ? lower..<upper : 0..<0, count)
        }
    }

    /// The authored attributes of top-level node `node`, as sorted JSON.
    public func listAttributes(ofTopLevel node: Int) -> Data? {
        guard let list = root.child(at: UInt32(node)), let attributes = try? list.attributes() else { return nil }
        return try? JSONSerialization.data(withJSONObject: attributes, options: [.sortedKeys])
    }

    /// Projects just items `items` of the top-level list `node` as `paper`
    /// projects that list, for `RelayMarkCollaborativeProse.replaceItems`.
    public func richProseProjection(items: Range<Int>, ofTopLevel node: Int, paper: RelayMarkCollaborativeProse,
                                    identityBase: Int) throws -> RelayMarkCollaborativeProse? {
        guard integrationStatus().isComplete else { return nil }
        let fragment = try JSONSerialization.data(withJSONObject: snapshot(items: items, ofTopLevel: node), options: [.sortedKeys])
        _ = try RelayMarkNativeDocumentProjection.project(snapshot: fragment)
        return try paper.projectItems(snapshot: fragment, ofTopLevel: node, from: items.lowerBound, identityBase: identityBase)
    }

    /// A fragment holding the top-level list `node` with only items `items`, and the paper's metadata.
    func snapshot(items: Range<Int>, ofTopLevel node: Int) throws -> [String: Any] {
        guard let list = root.child(at: UInt32(node)), list.kind() == "element", let tag = list.tag(),
              items.lowerBound >= 0, items.upperBound <= Int(list.length()) else { throw Failure.invalidAnchor }
        let children = try items.map { index -> [String: Any] in
            guard let child = list.child(at: UInt32(index)) else { throw Failure.invalidAnchor }
            return try snapshot(child)
        }
        var object: [String: Any] = ["kind": "fragment", "children": [["kind": "element", "name": tag,
            "attributes": try list.attributes(), "children": children]]]
        try addMetadata(to: &object)
        return object
    }

    /// The path from the paper to `node`, climbing one level at a time: a
    /// node's sticky index before its start names its own item, without
    /// walking its children, and resolves to its parent and index. A removed
    /// node yields where it was.
    private func climb(from node: YXmlNode, in transaction: YrsTransaction) -> [Int]? {
        var path: [Int] = [], current = node
        while !current.isSameNode(as: root) {
            guard path.count < 256,
                  let identity = try? current.relativePosition(at: 0, association: -1, in: transaction),
                  let id = RelayMarkUpdateFootprint.nestedID(identity),
                  let parent = try? document.resolveXmlRelativePosition(RelayMarkUpdateFootprint.stickyIndex(id), in: transaction)
            else { return nil }
            path.insert(Int(parent.index), at: 0)
            current = parent.node
        }
        return path
    }

    /// A live node's path; nil for a removed node.
    private func livePath(of node: YXmlNode, in transaction: YrsTransaction) -> [Int]? {
        guard let path = climb(from: node, in: transaction) else { return nil }
        var found = root
        for index in path {
            guard let child = found.child(at: UInt32(index), in: transaction) else { return nil }
            found = child
        }
        return found.isSameNode(as: node) ? path : nil
    }

    /// Projects just the top-level nodes in `range`, numbered from
    /// `identityBase`, for `RelayMarkCollaborativeProse.replaceTopLevelNodes`.
    /// The nodes pass the same codec validation as a whole paper.
    public func richProseProjection(topLevel range: Range<Int>, identityBase: Int) throws -> RelayMarkCollaborativeProse {
        guard integrationStatus().isComplete, range.lowerBound >= 0, range.upperBound <= Int(root.length()) else {
            throw RelayMarkNativeDocumentProjection.Failure.unsupported("incomplete update")
        }
        let nodes = try range.map { index -> [String: Any] in
            guard let child = root.child(at: UInt32(index)) else { throw Failure.invalidAnchor }
            return try snapshot(child)
        }
        let fragment = try JSONSerialization.data(withJSONObject: ["kind": "fragment", "children": nodes], options: [.sortedKeys])
        _ = try RelayMarkNativeDocumentProjection.project(snapshot: fragment)
        return try RelayMarkCollaborativeProse(snapshot: fragment, dialect: .rich, codecValidated: true, identityBase: identityBase)
    }

    /// The authored runs of one text leaf, as a projection splices them.
    public func textRuns(path: [Int]) throws -> [(text: String, attributes: [String: Any])] {
        try document.transactSync { transaction in
            var node = self.root
            for component in path {
                guard component >= 0, component <= Int(UInt32.max),
                      let child = node.child(at: UInt32(component), in: transaction) else { throw Failure.invalidTextPath }
                node = child
            }
            guard node.kind(in: transaction) == "text" else { throw Failure.invalidTextPath }
            return try node.delta(in: transaction).map { ($0.text, $0.attributes) }
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

    /// The same lossless XML JSON shape used by the existing collaboration adapter.
    public func snapshot() throws -> Data {
        var object = try snapshot(root)
        try addMetadata(to: &object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// The same shape for just the top-level nodes in `range`, with the paper's
    /// metadata, for a command that reads and writes only those nodes.
    func snapshot(topLevel range: Range<Int>) throws -> [String: Any] {
        guard range.lowerBound >= 0, range.upperBound <= Int(root.length()) else { throw Failure.invalidAnchor }
        var object: [String: Any] = ["kind": "fragment", "children": try range.map { index -> [String: Any] in
            guard let child = root.child(at: UInt32(index)) else { throw Failure.invalidAnchor }
            return try snapshot(child)
        }]
        try addMetadata(to: &object)
        return object
    }

    private func addMetadata(to object: inout [String: Any]) throws {
        let envelope = metadata.toMap()
        guard Set(envelope.keys).isSubset(of:["frontmatter","annotations","resources","meta"]) else { throw Failure.unsupportedProseEdit }
        if !envelope.isEmpty { object["metadata"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(envelope)) }
    }

    /// The number of top-level nodes.
    public var topLevelCount: Int { Int(root.length()) }

    /// A replica holding only some top-level nodes and the paper's metadata,
    /// where a command's write is rehearsed at the cost of those nodes.
    func scratch(topLevel range: Range<Int>) throws -> RelayMarkNativeDocument {
        try scratch(tree: snapshot(topLevel: range))
    }

    /// A replica holding a fragment snapshot's nodes and metadata.
    func scratch(tree: [String: Any]) throws -> RelayMarkNativeDocument {
        let scratch = RelayMarkNativeDocument()
        let envelope = try JSONDecoder().decode([String: RelayMarkValue].self,
            from: JSONSerialization.data(withJSONObject: tree["metadata"] ?? [String: Any]()))
        _ = try scratch.replaceSnapshotNodes([SnapshotNodeReplacement(parentPath: [], start: 0, count: 0,
            nodes: tree["children"] as? [[String: Any]] ?? [])], metadataUpdates: envelope)
        return scratch
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
    /// One snapshot and one codec conversion serve both the document validation and the prose projection.
    public func richProseProjection() throws -> RelayMarkCollaborativeProse {
        guard integrationStatus().isComplete else { throw RelayMarkNativeDocumentProjection.Failure.unsupported("incomplete update") }
        let snapshot = try snapshot()
        _ = try RelayMarkNativeDocumentProjection.project(snapshot: snapshot)
        return try RelayMarkCollaborativeProse(snapshot: snapshot, dialect: .rich, codecValidated: true)
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
        revision &+= 1
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
                revision &+= 1
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
            revision &+= 1
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
        guard blocks.count - removedBlockCount + lines.count - 1 <= Self.maximumBlocks else {
            throw Failure.unsupportedProseEdit
        }
        // All bounds, Unicode boundaries, node kinds and JSON attributes were
        // validated above. The mutation itself is one local Yrs transaction.
        revision &+= 1
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
            revision &+= 1
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
            revision &+= 1
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
        revision &+= 1
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

    /// The update returned is the undo or redo transaction's own, so saving and
    /// sending it costs the change; it is located like an applied update.
    private func performHistory(redo: Bool) throws -> Data? {
        guard undoGroupDepth == 0, editorCommandDepth == 0 else { throw Failure.unsupportedProseEdit }
        let rootCount = Int(root.length())
        undoManager.wrap()
        revision &+= 1
        guard let update = try redo ? undoManager.redoUpdate() : undoManager.undoUpdate() else { return nil }
        undoManager.wrap()
        lastUpdate = (revision, rootCount, RelayMarkUpdateFootprint(update))
        return update
    }

    /// Plain Yrs undo of this document's own local edits; returns the update to persist and send.
    public func undo() throws -> Data? { try performHistory(redo: false) }
    public func redo() throws -> Data? { try performHistory(redo: true) }

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
        document.transactSync { transaction in self.livePath(of: target, in: transaction) }
    }

    /// Mutate one existing XmlText leaf and return the exact Yjs-v1 transaction update.
    /// The host must persist this update before it acknowledges the local edit.
    public func insertText(_ text: String, at index: Int, path: [Int]) throws -> Data {
        try replaceText(at: index, length: 0, with: text, path: path)
    }

    public func deleteText(at index: Int, length: Int, path: [Int]) throws -> Data {
        try replaceText(at: index, length: length, with: "", path: path)
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
        revision &+= 1
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

    /// Types `text` over `length` UTF-16 units at `index` in one XML text leaf.
    /// Marks follow ProseMirror's stored marks: the preceding character's marks
    /// continue, except a link, which does not extend past its end. Explicit
    /// `attributes` (a stored typing style) win. Cost depends on the leaf only.
    /// What a person types is theirs: it never carries ai_authored.
    public func typeText(_ text: String, replacing length: Int, at index: Int, path: [Int],
                         attributes explicit: [String: Any]? = nil) throws -> (update: Data, attributes: [String: Any]) {
        if var explicit {
            explicit.removeValue(forKey: "ai_authored")
            guard JSONSerialization.isValidJSONObject(explicit) else { throw Failure.unsupportedProseEdit }
            return (try replaceText(at: index, length: length, with: text, path: path, insertionRuns: [(text, explicit)]), explicit)
        }
        var chosen: [String: Any] = [:]
        revision &+= 1
        let update = try document.transactSync(origin: localOrigin) { transaction in
            var node = self.root
            for component in path {
                guard component >= 0, component <= Int(UInt32.max),
                      let child = node.child(at: UInt32(component), in: transaction) else { throw Failure.invalidTextPath }
                node = child
            }
            guard node.kind(in: transaction) == "text" else { throw Failure.invalidTextPath }
            let total = Int(node.length(in: transaction))
            guard index >= 0, length >= 0, index <= total, length <= total - index else { throw Failure.invalidUTF16Range }
            let runs = try node.delta(in: transaction)
            var before: [String: Any]?, after: [String: Any]?, offset = 0
            for run in runs {
                let end = offset + run.text.utf16.count
                if index > offset && index <= end { before = run.attributes }
                if after == nil, index + length >= offset, index + length < end { after = run.attributes }
                offset = end
            }
            var marks = before ?? runs.first?.attributes ?? [:]
            marks.removeValue(forKey: "ai_authored")
            if let link = marks["link"] as? NSDictionary, before == nil || (after?["link"] as? NSDictionary) != link {
                marks.removeValue(forKey: "link")
            }
            if length > 0 { try node.removeText(start: UInt32(index), length: UInt32(length), in: transaction) }
            if !text.isEmpty { try node.insert(text, attributes: marks, at: UInt32(index), in: transaction) }
            chosen = marks
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return (update, chosen)
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
        revision &+= 1
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
        revision &+= 1
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
        revision &+= 1
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

    /// Insert one identified title into the existing canonical callout. The
    /// exact checkpoint and whole candidate grammar are validated before writing.
    public func addCalloutTitle(anchor: Data, expectedID: String,
                                expectedSnapshot: Data) throws -> (change: RelayMarkNativeRichEditing.Change, titleID: String) {
        guard integrationStatus().isComplete,
              try snapshot() == expectedSnapshot,
              try richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let (callout, path) = try anchoredElement(anchor)
        guard callout.tag() == "callout",
              try callout.attributes()["relaymarkId"] as? String == expectedID,
              !callout.children().contains(where: { $0.tag() == "calloutTitle" }) else {
            throw Failure.invalidAnchor
        }
        let titleID = RelayMarkNativeRichXML.freshID()
        let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as! [String: Any]
        let title: [String: Any] = ["kind": "element", "name": "calloutTitle",
            "attributes": ["relaymarkId": titleID], "children": [["kind": "text", "delta": [["insert": "Title"]]]]]
        var candidate = tree
        try RelayMarkNativeRichXML.mutate(path: path[...], in: &candidate) { parent in
            var children = try RelayMarkNativeRichXML.children(parent)
            children.insert(title, at: 0); parent["children"] = children
        }
        let change = try RelayMarkNativeRichEditing.insertWidget(document: self, tree: tree,
            candidate: candidate, parentID: expectedID, index: 0)
        return (change, titleID)
    }

    /// Change only the appearance of one existing, editable canonical callout.
    /// The host binds this relative anchor to its authorized document and
    /// captures the ID and appearance from the same displayed revision. A
    /// changed/deleted callout is rejected rather than retargeting its path.
    public func setCalloutAppearance(anchor: Data, expectedID: String,
                                     expectedTone: String, expectedEmphasis: String,
                                     tone: String, emphasis: String) throws -> RelayMarkNativeRichEditing.Change {
        let tones: Set<String> = ["neutral", "primary", "secondary", "accent", "info", "success", "warning", "error"]
        let emphases: Set<String> = ["soft", "strong"]
        guard tones.contains(tone), emphases.contains(emphasis),
              tone != expectedTone || emphasis != expectedEmphasis,
              integrationStatus().isComplete,
              try richProseProjection().isEditable else {
            throw Failure.unsupportedProseEdit
        }
        let (callout, _) = try anchoredElement(anchor)
        guard callout.tag() == "callout" else { throw Failure.invalidAnchor }
        let attributes = try callout.attributes()
        guard attributes["relaymarkId"] as? String == expectedID,
              attributes["tone"] as? String == expectedTone,
              attributes["emphasis"] as? String == expectedEmphasis else {
            throw Failure.invalidAnchor
        }
        var changes: [String: Any] = [:]
        if tone != expectedTone { changes["tone"] = tone }
        if emphasis != expectedEmphasis { changes["emphasis"] = emphasis }
        return try authoredAttributeChange(callout, attributes: changes)
    }

    private func authoredAttributeChange(_ node: YXmlNode, attributes: [String: Any]) throws -> RelayMarkNativeRichEditing.Change {
        guard let id = try node.attributes()["relaymarkId"] as? String else { throw Failure.invalidAnchor }
        let tree = try JSONSerialization.jsonObject(with: snapshot()) as! [String: Any]
        return try RelayMarkNativeRichEditing.updateWidget(document: self, tree: tree, id: id, attributes: attributes)
    }

    ///  attribute commands retain the existing XML containers and text.
    /// Relative anchors fence the selected identity even when a peer shifts paths.
    public func setRichHeadingLevel(anchor: Data, expectedHeadingID: String?, level: Int) throws -> RelayMarkNativeRichEditing.Change {
        guard (1...6).contains(level), integrationStatus().isComplete,
              try richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let (heading, _) = try anchoredElement(anchor)
        guard heading.tag() == "heading",
              try heading.attributes()["headingId"] as? String == expectedHeadingID else { throw Failure.invalidAnchor }
        return try authoredAttributeChange(heading, attributes: ["level": level])
    }

    public func setRichOrderedListStart(anchor: Data, expectedStart: Int, start: Int) throws -> RelayMarkNativeRichEditing.Change {
        guard (1...1_000_000).contains(start), integrationStatus().isComplete,
              try richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let (list, _) = try anchoredElement(anchor)
        guard list.tag() == "orderedList",
              (try list.attributes()["start"] as? Int ?? 1) == expectedStart else { throw Failure.invalidAnchor }
        return try authoredAttributeChange(list, attributes: ["start": start])
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
        revision &+= 1
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
        revision &+= 1
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
            revision &+= 1
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
        revision &+= 1
        let update = try document.transactSync(origin: localOrigin) { transaction in
            let next = try list.insertElement(named: "listItem", at: UInt32(itemIndex + 1), in: transaction)
            _ = try next.insertElement(named: "paragraph", at: 0, in: transaction)
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
        -> (change: RelayMarkNativeRichEditing.Change, listID: String, itemID: String, paragraphID: String) {
        guard integrationStatus().isComplete, try snapshot() == expectedSnapshot,
              try richProseProjection().isEditable else { throw Failure.unsupportedProseEdit }
        let (_, path, _) = try richTopLevelParagraphTarget(paragraphAnchor)
        guard Int(root.length()) < Self.maximumBlocks else { throw Failure.unsupportedProseEdit }
        let listID = RelayMarkNativeRichXML.freshID(), itemID = RelayMarkNativeRichXML.freshID(),
            paragraphID = RelayMarkNativeRichXML.freshID()
        let paragraph: [String: Any] = ["kind": "element", "name": "paragraph",
            "attributes": ["relaymarkId": paragraphID], "children": []]
        let item: [String: Any] = ["kind": "element", "name": "taskItem",
            "attributes": ["relaymarkId": itemID, "checked": false], "children": [paragraph]]
        let list: [String: Any] = ["kind": "element", "name": "taskList",
            "attributes": ["relaymarkId": listID], "children": [item]]
        let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as! [String: Any]
        let change = try RelayMarkNativeRichEditing.replaceRootChildren(document: self, tree: tree,
            index: path[0] + 1, count: 0, replacements: [list])
        return (change, listID, itemID, paragraphID)
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
        revision &+= 1
        let update = try document.transactSync(origin: localOrigin) { transaction in
            try record.node.setAttribute("checked", value: checked, in: transaction)
            return Data(transaction.transactionEncodeUpdate())
        }
        wrapUndo()
        return update
    }

    public struct TaskItemCheckTarget: Sendable {
        public let path: [Int]
        public let expectedID: String
        public let expectedEntityID: String?
        public let expectedChecked: Bool

        public init(path: [Int], expectedID: String, expectedEntityID: String?, expectedChecked: Bool) {
            self.path = path; self.expectedID = expectedID
            self.expectedEntityID = expectedEntityID; self.expectedChecked = expectedChecked
        }
    }

    /// All occurrences of a linked Task change together. Every supplied
    /// identity/status and complete linked occurrence set is guarded before
    /// the single maintained transform writes any attribute.
    public func setRichTaskItemsChecked(items: [TaskItemCheckTarget], checked: Bool,
                                        expectedSnapshot: Data) throws -> RelayMarkNativeRichEditing.Change {
        guard integrationStatus().isComplete, !items.isEmpty, items.count <= 512,
              try snapshot() == expectedSnapshot,
              Set(items.map(\.expectedID)).count == items.count else {
            throw Failure.unsupportedProseEdit
        }
        let current = try richProseProjection().taskItems
        for item in items {
            guard let actual = current.first(where: { $0.id == item.expectedID }),
                  actual.path == item.path, actual.entityID == item.expectedEntityID,
                  actual.checked == item.expectedChecked else { throw Failure.invalidAnchor }
        }
        let supplied = Set(items.map(\.expectedID))
        let entities = Set(items.compactMap(\.expectedEntityID))
        guard current.filter({ $0.entityID.map(entities.contains) ?? false }).allSatisfy({ supplied.contains($0.id) }) else {
            throw Failure.invalidAnchor
        }
        let changes = items.filter { $0.expectedChecked != checked }.map { (id: $0.expectedID, attributes: ["checked": checked] as [String: Any]) }
        guard !changes.isEmpty,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else {
            throw Failure.unsupportedProseEdit
        }
        return try RelayMarkNativeRichEditing.updateWidgets(document: self, tree: tree, changes: changes)
    }

    /// The single-item entry point uses the same complete linked occurrence
    /// guard and maintained batch owner; unlinked tasks remain independent.
    public func setRichTaskItemChecked(path: [Int], expectedID: String,
                                      expectedEntityID: String?, expectedChecked: Bool,
                                      checked: Bool) throws -> RelayMarkNativeRichEditing.Change {
        let snapshot = try self.snapshot()
        let current = try richProseProjection().taskItems
        guard let target = current.first(where: { $0.id == expectedID }), target.path == path,
              target.entityID == expectedEntityID, target.checked == expectedChecked else { throw Failure.invalidAnchor }
        let matching = current.filter { expectedEntityID == nil ? $0.id == expectedID : $0.entityID == expectedEntityID }
        guard matching.allSatisfy({ $0.checked == expectedChecked }) else { throw Failure.invalidAnchor }
        return try setRichTaskItemsChecked(items: matching.map {
            TaskItemCheckTarget(path: $0.path, expectedID: $0.id, expectedEntityID: $0.entityID, expectedChecked: $0.checked)
        }, checked: checked, expectedSnapshot: snapshot)
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
        revision &+= 1
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

    /// Writes a transformed ProseMirror document through y-prosemirror's
    /// updateYFragment diff as one local transaction and one undo item.
    /// `window` writes only those top-level nodes; `updated` and `source` then hold just them.
    /// `items` writes only those items of a top-level list; both then hold that one list.
    func applyProseMirror(_ updated: PMNode, source: PMNode, bridge: PMYXmlBridge, window: Range<Int>? = nil,
                          items: (node: Int, window: Range<Int>)? = nil) throws -> Data {
        let metadataReplacement=try JSONDecoder().decode([String:RelayMarkValue].self,from:JSONSerialization.data(withJSONObject:updated.attrs["relaymark"] ?? [:]))
        wrapUndo()
        revision &+= 1
        let update = try document.transactSync(origin: localOrigin) { transaction in
            if let items {
                guard updated.childCount == 1, source.childCount == 1,
                      let list = self.root.child(at: UInt32(items.node), in: transaction) else { throw Failure.containerChanged }
                try bridge.update(list, updated.child(0), source: source.child(0), in: transaction, window: items.window)
            } else {
                try bridge.update(self.root, updated, source: source, in: transaction, window: window)
            }
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
        revision &+= 1
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
                    for (key, value) in try PMYXmlBridge.orderedPhysicalAttributes(nodeName: name, values: raw["attributes"] as? [String: Any] ?? [:]) {
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
