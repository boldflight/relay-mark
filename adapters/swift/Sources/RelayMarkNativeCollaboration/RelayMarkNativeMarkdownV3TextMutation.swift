import Foundation

/// A bounded v3 text-leaf command over the existing YSwift/Yrs replica.
///
/// The host still gates v3 admission. This command keeps an edit inside one
/// existing XmlText leaf and validates the complete candidate document before
/// mutating the live replica. It does not reinterpret or rebuild block nodes.
@MainActor
public enum RelayMarkNativeMarkdownV3TextMutation {
    public static func replace(document: RelayMarkNativeDocument, path: [Int],
                               start: Int, end: Int, text: String) throws -> Data {
        guard end >= start, !text.unicodeScalars.contains(where: {
            $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}"
        }), text.utf16.count <= 131_072 else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }

        _ = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: document)
        guard try staysWithinOneTextRun(snapshot: document.snapshot(), path: path,
                                        start: start, end: end, text: text) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        _ = try scratch.replaceText(at: start, length: end - start, with: text, path: path)
        _ = try RelayMarkNativeMarkdownBlocksV3Projection.project(document: scratch)
        return try document.replaceText(at: start, length: end - start, with: text, path: path)
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
        var offset = 0
        for run in runs {
            guard let value = run["insert"] as? String else { return false }
            let next = offset + value.utf16.count
            if start >= offset && start < next && end <= next &&
                (end > start || start > offset) { return true }
            offset = next
        }
        return false
    }
}
