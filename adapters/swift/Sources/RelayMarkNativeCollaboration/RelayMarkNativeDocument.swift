import Foundation
import RelayMarkProseProjection
import YSwift

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
    }

    private let document: YDocument
    private let root: YXmlNode
    private let localOrigin: Origin
    private let undoManager: YUndoManager<NSObject>

    public init() {
        let document = YDocument()
        let root = document.getOrCreateXmlFragment(named: "default")
        let origin = Origin(UUID().uuidString)
        let undoManager: YUndoManager<NSObject> = document.undoManager(trackedRefs: [root])
        undoManager.addOrigin(origin)
        self.document = document
        self.root = root
        localOrigin = origin
        self.undoManager = undoManager
    }

    public func applyUpdate(_ update: Data) throws {
        try document.transactSync { transaction in
            try transaction.transactionApplyUpdate(update: Array(update))
        }
    }

    public func stateVector() -> Data {
        Data(document.transactSync { $0.transactionStateVector() })
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
        let object = try snapshot(root)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public func proseProjection() throws -> RelayMarkCollaborativeProse {
        try RelayMarkCollaborativeProse(snapshot: snapshot())
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
            undoManager.wrap()
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
        undoManager.wrap()
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

    /// Standard in-memory Yrs undo, scoped to this document's local edit origin.
    /// The host persists the returned update; the undo stack itself is not durable.
    public func undo() throws -> Data? {
        let before = stateVector()
        undoManager.wrap()
        guard try undoManager.undo() else { return nil }
        undoManager.wrap()
        return try encodeUpdate(since: before)
    }

    public func redo() throws -> Data? {
        let before = stateVector()
        undoManager.wrap()
        guard try undoManager.redo() else { return nil }
        undoManager.wrap()
        return try encodeUpdate(since: before)
    }

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

    /// Deletion and insertion share one transaction and one undo item.
    public func replaceText(at index: Int, length: Int, with text: String, path: [Int]) throws -> Data {
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
            if length > 0 { try node.removeText(start: UInt32(index), length: UInt32(length), in: transaction) }
            if !text.isEmpty { try node.insert(text, at: UInt32(index), in: transaction) }
            return Data(transaction.transactionEncodeUpdate())
        }
        undoManager.wrap()
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
        undoManager.wrap()
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
