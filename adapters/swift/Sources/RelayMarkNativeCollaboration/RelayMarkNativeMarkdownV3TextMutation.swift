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
        guard end >= start, !text.unicodeScalars.contains(where: {
            $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}"
        }), text.utf16.count <= 131_072 else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }

        _ = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: document)
        let snapshot = try document.snapshot()
        let emptyParagraph = try isEmptyTextBlock(snapshot: snapshot, path: path) &&
            start == 0 && end == 0 && !text.isEmpty
        let validTextRun: Bool
        if emptyParagraph { validTextRun = true }
        else {
            validTextRun = try staysWithinOneTextRun(snapshot: snapshot, path: path,
                                                    start: start, end: end, text: text)
        }
        guard validTextRun else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        if emptyParagraph { _ = try scratch.insertTextIntoEmptyParagraph(text, path: path) }
        else { _ = try scratch.replaceText(at: start, length: end - start, with: text, path: path) }
        _ = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: scratch)
        if emptyParagraph { return try document.insertTextIntoEmptyParagraph(text, path: path) }
        return try document.replaceText(at: start, length: end - start, with: text, path: path)
    }

    private static func isEmptyTextBlock(snapshot: Data, path: [Int]) throws -> Bool {
        guard let root = try JSONSerialization.jsonObject(with: snapshot) as? [String: Any],
              let block = node(at: path, in: root),
              block["kind"] as? String == "element",
              (block["children"] as? [Any])?.isEmpty == true else { return false }
        if block["name"] as? String == "paragraph" { return true }
        guard block["name"] as? String == "calloutTitle", path.count == 2, path[1] == 0,
              let callout = node(at: [path[0]], in: root),
              callout["name"] as? String == "callout" else { return false }
        return true
    }

    private static func staysWithinOneTextRun(snapshot: Data, path: [Int],
                                              start: Int, end: Int, text: String) throws -> Bool {
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
        if text.isEmpty && end > start {
            // Deleting a selection has no typing-mark decision. Do not fence it
            // merely because bold/link/etc. runs differ: Yrs removes exactly
            // these characters and retains the attributes of all survivors.
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
