import Foundation
import RelayMarkProseProjection

/// A narrow canonical XML sibling command. The caller supplies the authored source;
/// the portable projection checks its exact identity and spelling.
@MainActor
public enum RelayMarkNativeInlineAtomMutation {
    public struct Atom: Sendable {
        public enum Kind: String, Sendable { case relayReference, relayTag }
        public let kind: Kind
        public let attributes: [String: String]

        public init(kind: Kind, attributes: [String: String]) {
            self.kind = kind
            self.attributes = attributes
        }
    }

    /// Insert at an XML child boundary in an existing paragraph or heading.
    /// The one-unit map must expose that boundary as a native UTF-16 offset.
    public static func insert(document: RelayMarkNativeDocument, blockID: String,
                              childIndex: Int, atom: Atom) throws -> Data {
        try mutate(document: document, blockID: blockID, childIndex: childIndex,
                   replacing: false, atom: atom)
    }

    /// Insert within an XmlText leaf. Expected text binds the UTF-16 caret to
    /// the source shown to the caller, so a stale position fails closed.
    public static func insert(document: RelayMarkNativeDocument, blockID: String,
                              childIndex: Int, utf16Offset: Int,
                              expectedLeafText: String, atom: Atom) throws -> Data {
        let prose = try document.richProseProjection()
        guard prose.isEditable, childIndex >= 0,
              let root = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any],
              let path = path(to: blockID, in: root, prefix: []),
              let block = node(at: path, in: root),
              ["paragraph", "heading"].contains(block["name"] as? String ?? ""),
              var children = block["children"] as? [[String: Any]],
              children.indices.contains(childIndex), childIndex < 4_096,
              children[childIndex]["kind"] as? String == "text",
              let delta = children[childIndex]["delta"] as? [[String: Any]],
              let actualText = text(of: delta), actualText == expectedLeafText,
              utf16Offset > 0, utf16Offset < actualText.utf16.count,
              isCharacterBoundary(utf16Offset, in: actualText),
              prose.offset(path: path + [childIndex], index: utf16Offset) != nil,
              let (prefix, suffix) = split(delta: delta, at: utf16Offset) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        children[childIndex]["delta"] = prefix
        children.insert(["kind": "element", "name": atom.kind.rawValue,
                         "attributes": atom.attributes, "children": []], at: childIndex + 1)
        children.insert(["kind": "text", "delta": suffix], at: childIndex + 2)
        var candidate = root
        guard setChildren(children, at: path, in: &candidate) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let candidateData = try JSONSerialization.data(withJSONObject: candidate)
        let candidateAST = try RelayMarkNativeDocumentProjection.project(snapshot: candidateData)
        guard try RelayMarkCollaborativeProse(snapshot: candidateData, dialect: .rich).isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        _ = try scratch.insertInlineAtom(in: path + [childIndex], at: utf16Offset,
                                         expectedText: expectedLeafText,
                                         tag: atom.kind.rawValue, attributes: atom.attributes)
        let scratchAST = try RelayMarkNativeDocumentProjection.project(document: scratch)
        guard scratchAST == candidateAST,
              try scratch.richProseProjection().isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return try document.insertInlineAtom(in: path + [childIndex], at: utf16Offset,
                                             expectedText: expectedLeafText,
                                             tag: atom.kind.rawValue, attributes: atom.attributes)
    }

    /// Replace exactly one projected atom; adjacent text and other atoms retain
    /// their XML identities. The range is the current native selection range.
    public static func replace(document: RelayMarkNativeDocument, range: NSRange,
                               expectedID: String, atom: Atom) throws -> Data {
        let prose = try document.richProseProjection()
        guard prose.isEditable,
              let current = prose.inlineAtoms.first(where: { $0.range == range && $0.id == expectedID }),
              let snapshot = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any],
              let block = node(at: Array(current.path.dropLast()), in: snapshot),
              let blockID = (block["attributes"] as? [String: Any])?["relaymarkId"] as? String,
              let childIndex = current.path.last else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return try mutate(document: document, blockID: blockID, childIndex: childIndex,
                          replacing: true, atom: atom)
    }

    private static func mutate(document: RelayMarkNativeDocument, blockID: String,
                               childIndex: Int, replacing: Bool, atom: Atom) throws -> Data {
        let prose = try document.richProseProjection()
        guard prose.isEditable, childIndex >= 0,
              let root = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any],
              let path = path(to: blockID, in: root, prefix: []),
              let block = node(at: path, in: root),
              ["paragraph", "heading"].contains(block["name"] as? String ?? ""),
              var children = block["children"] as? [[String: Any]],
              childIndex <= children.count, childIndex <= 4_096,
              prose.offset(path: path, index: childIndex) != nil else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        if replacing {
            guard childIndex < children.count,
                  prose.inlineAtoms.contains(where: { $0.path == path + [childIndex] }) else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
        }
        let newNode: [String: Any] = ["kind": "element", "name": atom.kind.rawValue,
                                      "attributes": atom.attributes, "children": []]
        if replacing { children[childIndex] = newNode }
        else { children.insert(newNode, at: childIndex) }
        var candidate = root
        guard setChildren(children, at: path, in: &candidate) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let candidateData = try JSONSerialization.data(withJSONObject: candidate)
        _ = try RelayMarkNativeDocumentProjection.project(snapshot: candidateData)
        guard try RelayMarkCollaborativeProse(snapshot: candidateData, dialect: .rich).isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }

        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        _ = try scratch.mutateInlineAtom(path: path + [childIndex], replacing: replacing,
                                         tag: atom.kind.rawValue, attributes: atom.attributes)
        _ = try scratch.richProseProjection()
        return try document.mutateInlineAtom(path: path + [childIndex], replacing: replacing,
                                             tag: atom.kind.rawValue, attributes: atom.attributes)
    }

    private static func path(to id: String, in node: [String: Any], prefix: [Int]) -> [Int]? {
        if (node["attributes"] as? [String: Any])?["relaymarkId"] as? String == id { return prefix }
        guard let children = node["children"] as? [[String: Any]] else { return nil }
        for (index, child) in children.enumerated() {
            if let found = path(to: id, in: child, prefix: prefix + [index]) { return found }
        }
        return nil
    }

    private static func node(at path: [Int], in root: [String: Any]) -> [String: Any]? {
        var current = root
        for index in path {
            guard let children = current["children"] as? [[String: Any]],
                  children.indices.contains(index) else { return nil }
            current = children[index]
        }
        return current
    }

    private static func setChildren(_ children: [[String: Any]], at path: [Int],
                                    in node: inout [String: Any]) -> Bool {
        guard let first = path.first else { node["children"] = children; return true }
        guard var siblings = node["children"] as? [[String: Any]], siblings.indices.contains(first) else { return false }
        var child = siblings[first]
        guard setChildren(children, at: Array(path.dropFirst()), in: &child) else { return false }
        siblings[first] = child
        node["children"] = siblings
        return true
    }

    private static func text(of delta: [[String: Any]]) -> String? {
        var text = ""
        for run in delta {
            guard let part = run["insert"] as? String else { return nil }
            text += part
        }
        return text
    }

    private static func isCharacterBoundary(_ offset: Int, in text: String) -> Bool {
        var position = 0
        for character in text {
            if position == offset { return true }
            position += String(character).utf16.count
        }
        return position == offset
    }

    private static func split(delta: [[String: Any]], at offset: Int)
        -> (prefix: [[String: Any]], suffix: [[String: Any]])? {
        var prefix: [[String: Any]] = [], suffix: [[String: Any]] = []
        var base = 0
        for run in delta {
            guard let value = run["insert"] as? String else { return nil }
            let length = value.utf16.count
            let cut = min(max(offset - base, 0), length)
            guard isCharacterBoundary(cut, in: value) else { return nil }
            let index = String.Index(utf16Offset: cut, in: value)
            let left = String(value[..<index]), right = String(value[index...])
            if !left.isEmpty { var item = run; item["insert"] = left; prefix.append(item) }
            if !right.isEmpty { var item = run; item["insert"] = right; suffix.append(item) }
            base += length
        }
        return (prefix, suffix)
    }
}
