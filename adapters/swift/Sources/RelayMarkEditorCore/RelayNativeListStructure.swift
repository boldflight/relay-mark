import Foundation
import RelayMarkNativeCollaboration

/// The existing native operation admits one XmlText paragraph per item and one
/// nested list level. Presentation stays in the canonical prose offset space.
@MainActor
enum RelayNativeListStructure {
    static func supports(_ document: RelayMarkNativeDocument) -> Bool {
        guard document.integrationStatus().isComplete,
              let projection = try? document.proseProjection(), projection.isEditable,
              let snapshot = try? document.snapshot(),
              let tree = try? JSONSerialization.jsonObject(with: snapshot) as? [String: Any],
              let lists = tree["children"] as? [[String: Any]], !lists.isEmpty else { return false }
        func valid(_ list: [String: Any], depth: Int) -> Bool {
            guard depth <= 1, ["bulletList", "orderedList"].contains(list["name"] as? String ?? ""),
                  let items = list["children"] as? [[String: Any]], !items.isEmpty else { return false }
            return items.allSatisfy { item in
                guard item["name"] as? String == "listItem",
                      let children = item["children"] as? [[String: Any]], (1...2).contains(children.count),
                      children[0]["name"] as? String == "paragraph",
                      let leaves = children[0]["children"] as? [[String: Any]], leaves.count <= 1 else { return false }
                let delta: [[String: Any]]
                if let leaf = leaves.first {
                    guard leaf["kind"] as? String == "text", let value = leaf["delta"] as? [[String: Any]] else { return false }
                    delta = value
                } else { delta = [] }
                let text = delta.compactMap { $0["insert"] as? String }.joined()
                guard !text.unicodeScalars.contains(where: {
                    $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FFFC}"
                }) else { return false }
                return children.count == 1 || valid(children[1], depth: depth + 1)
            }
        }
        return lists.allSatisfy { valid($0, depth: 0) }
    }

    static func appendEmptyItem(_ document: RelayMarkNativeDocument, at offset: Int) throws -> Data {
        guard supports(document) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let projection = try document.proseProjection()
        guard let row = projection.blockRanges.firstIndex(where: { $0.length > 0 && NSMaxRange($0) == offset }) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return try document.appendEmptyListItem(after: document.anchor(path: projection.blockPaths[row], index: 0))
    }

    static func replace(_ document: RelayMarkNativeDocument, start: Int, end: Int, text: String) throws -> Data {
        guard supports(document), start >= 0, end >= start else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let projection = try document.proseProjection()
        guard let row = projection.blockRanges.firstIndex(where: {
            start >= $0.location && end <= NSMaxRange($0)
        }) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let range = projection.blockRanges[row]
        return try document.replaceListParagraphText(
            anchor: document.anchor(path: projection.blockPaths[row], index: 0),
            start: start - range.location, end: end - range.location, text: text)
    }
}
