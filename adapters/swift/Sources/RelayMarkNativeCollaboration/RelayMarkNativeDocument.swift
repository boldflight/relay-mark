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
