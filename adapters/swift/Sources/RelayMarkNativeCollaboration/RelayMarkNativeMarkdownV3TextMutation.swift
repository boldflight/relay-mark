import Foundation

/// A bounded v3 text-leaf command over the existing YSwift/Yrs replica.
///
/// The host still gates v3 admission. This command keeps an edit inside one
/// existing XmlText leaf and validates the complete candidate document before
/// mutating the live replica. Deletion may span formatting runs within that
/// leaf; surviving formatting remains owned by the community Yrs text type.
/// It does not reinterpret or rebuild block nodes.
@MainActor
public enum RelayMarkNativeMarkdownV3TextMutation {
    /// Address a paragraph by its durable RelayMark ID rather than a possibly
    /// shifted table/list path. The child index selects one existing XmlText
    /// leaf inside that paragraph; callers bind it to their current selection.
    public static func replace(document: RelayMarkNativeDocument, blockID: String,
                               childIndex: Int, start: Int, end: Int, text: String) throws -> Data {
        _ = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: document)
        guard childIndex >= 0,
              let root = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any],
              let path = path(to: blockID, in: root, prefix: []),
              let children = node(at: path, in: root)?["children"] as? [[String: Any]],
              children.indices.contains(childIndex), children[childIndex]["kind"] as? String == "text" else {
            throw RelayMarkNativeDocument.Failure.invalidTextPath
        }
        return try replace(document: document, path: path + [childIndex],
                           start: start, end: end, text: text)
    }

    public static func replace(document: RelayMarkNativeDocument, path: [Int],
                               start: Int, end: Int, text: String) throws -> Data {
        try replace(document: document, path: path, start: start, end: end, text: text,
                    insertionRuns: nil)
    }

    /// Explicit typing marks permit replacement across existing formatting runs.
    /// The full v3 projection rejects unsupported marks before live mutation.
    public static func replace(document: RelayMarkNativeDocument, path: [Int],
                               start: Int, end: Int, text: String,
                               attributes: [String: Any]) throws -> Data {
        try replace(document: document, path: path, start: start, end: end,
                    runs: text.isEmpty ? [] : [(text, attributes)])
    }

    /// Preserve every authored run in an inline rich-text paste. The operation
    /// remains one Yrs transaction; surrounding blocks and surviving marks stay intact.
    public static func replace(document: RelayMarkNativeDocument, path: [Int],
                               start: Int, end: Int,
                               runs: [(text: String, attributes: [String: Any])]) throws -> Data {
        var length = 0
        for run in runs {
            guard !run.text.isEmpty, run.text.utf16.count <= 131_072 - length,
                  JSONSerialization.isValidJSONObject(run.attributes) else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            length += run.text.utf16.count
        }
        return try replace(document: document, path: path, start: start, end: end,
                           text: runs.map(\.text).joined(), insertionRuns: runs)
    }

    private static func replace(document: RelayMarkNativeDocument, path: [Int],
                                start: Int, end: Int, text: String,
                                insertionRuns: [(text: String, attributes: [String: Any])]?) throws -> Data {
        let snapshot = try document.snapshot()
        let tree = try JSONSerialization.jsonObject(with: snapshot) as? [String: Any]
        let current = tree.flatMap { node(at: path, in: $0) }
        let parent = tree.flatMap { node(at: Array(path.dropLast()), in: $0) }
        let code = current?["name"] as? String == "codeBlock" || parent?["name"] as? String == "codeBlock"
        guard end >= start, !text.unicodeScalars.contains(where: {
            $0 == "\u{FFFC}" || (!code && ($0 == "\n" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}"))
        }), text.utf16.count <= 131_072 else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }

        _ = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: document)
        let emptyParagraph = try isEmptyTextBlock(snapshot: snapshot, path: path) &&
            start == 0 && end == 0 && !text.isEmpty
        let validTextRun: Bool
        if emptyParagraph { validTextRun = true }
        else {
            validTextRun = try staysWithinOneTextRun(snapshot: snapshot, path: path,
                                                    start: start, end: end, text: text, explicitMarks: insertionRuns != nil)
        }
        guard validTextRun else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        func apply(to target: RelayMarkNativeDocument) throws -> Data {
            if emptyParagraph {
                return try target.insertTextIntoEmptyParagraph(path: path,
                    runs: insertionRuns ?? [(text, [:])])
            }
            if let insertionRuns {
                return try target.replaceText(at: start, length: end - start,
                                              runs: insertionRuns, path: path)
            }
            return try target.replaceText(at: start, length: end - start, with: text, path: path)
        }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        _ = try apply(to: scratch)
        _ = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: scratch)
        return try apply(to: document)
    }

    private static func isEmptyTextBlock(snapshot: Data, path: [Int]) throws -> Bool {
        guard let root = try JSONSerialization.jsonObject(with: snapshot) as? [String: Any],
              let block = node(at: path, in: root),
              block["kind"] as? String == "element",
              (block["children"] as? [Any])?.isEmpty == true else { return false }
        if ["paragraph", "heading", "codeBlock"].contains(block["name"] as? String ?? "") { return true }
        guard block["name"] as? String == "calloutTitle", path.count == 2, path[1] == 0,
              let callout = node(at: [path[0]], in: root),
              callout["name"] as? String == "callout" else { return false }
        return true
    }

    private static func staysWithinOneTextRun(snapshot: Data, path: [Int],
                                              start: Int, end: Int, text: String, explicitMarks: Bool) throws -> Bool {
        guard start >= 0, path.count >= 2,
              let root = try JSONSerialization.jsonObject(with: snapshot) as? [String: Any] else {
            return false
        }
        var node = root
        for index in path {
            guard index >= 0, let children = node["children"] as? [[String: Any]],
                  children.indices.contains(index) else { return false }
            node = children[index]
        }
        guard node["kind"] as? String == "text", let runs = node["delta"] as? [[String: Any]] else {
            return false
        }
        if runs.isEmpty { return start == 0 && end == 0 && !text.isEmpty }
        if explicitMarks || (text.isEmpty && end > start) {
            // Explicit typing marks resolve boundary styling; deletion needs none.
            // Yrs keeps all surviving characters and their existing attributes.
            let fragments = runs.compactMap { $0["insert"] as? String }
            guard fragments.count == runs.count else { return false }
            let value = fragments.joined()
            return end <= value.utf16.count && isCharacterBoundary(start, in: value) &&
                isCharacterBoundary(end, in: value)
        }
        // YSwift inserts explicit empty attributes at an exact run boundary.
        // At the beginning of a plain first run this is the same semantic
        // style; a styled first run remains fenced rather than losing marks.
        if start == 0 && end == 0 && !text.isEmpty,
           let first = runs.first,
           (first["attributes"] as? [String: Any] ?? [:]).isEmpty { return true }
        var offset = 0
        for run in runs {
            guard let value = run["insert"] as? String else { return false }
            let next = offset + value.utf16.count
            if start >= offset && start < next && end <= next &&
                (end > start || start > offset) &&
                isCharacterBoundary(start - offset, in: value) &&
                isCharacterBoundary(end - offset, in: value) { return true }
            offset = next
        }
        guard let last = runs.last?["insert"] as? String, !last.isEmpty else { return false }
        return start == offset && end == offset && !text.isEmpty
    }

    private static func isCharacterBoundary(_ utf16Offset: Int, in value: String) -> Bool {
        guard utf16Offset >= 0 else { return false }
        var position = 0
        for character in value {
            if position == utf16Offset { return true }
            position += String(character).utf16.count
        }
        return position == utf16Offset
    }

    private static func path(to blockID: String, in node: [String: Any], prefix: [Int]) -> [Int]? {
        if (node["attributes"] as? [String: Any])?["relaymarkId"] as? String == blockID {
            return prefix
        }
        guard let children = node["children"] as? [[String: Any]] else { return nil }
        for (index, child) in children.enumerated() {
            if let found = path(to: blockID, in: child, prefix: prefix + [index]) { return found }
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
}
