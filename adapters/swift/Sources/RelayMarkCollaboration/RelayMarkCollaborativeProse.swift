import Foundation

/// Deliberately bounded editable projection; unsupported structure is preserved by the replica.
public struct RelayMarkCollaborativeProse {
    public let text: AttributedString
    public let isEditable: Bool
    public let blockRanges: [NSRange]

    public init(snapshot: Data) throws {
        let root = try JSONSerialization.jsonObject(with: snapshot) as? [String: Any]
        var value = AttributedString()
        var ranges: [NSRange] = []
        var supported = true
        let blocks = root?["children"] as? [[String: Any]] ?? []
        for (index, block) in blocks.enumerated() {
            if index > 0 { value.append(AttributedString("\n")) }
            let start = String(value.characters).utf16.count
            let children = block["children"] as? [[String: Any]] ?? []
            if block["name"] as? String != "paragraph" || !(block["attributes"] as? [String: Any] ?? [:]).isEmpty || children.count > 1 {
                supported = false
            }
            func append(_ node: [String: Any]) {
                if let delta = node["delta"] as? [[String: Any]] {
                    for run in delta {
                        guard let insert = run["insert"] as? String else { supported = false; continue }
                        let attributes = run["attributes"] as? [String: Any] ?? [:]
                        if !Set(attributes.keys).isSubset(of: ["bold", "italic", "strike", "code", "link"]) { supported = false }
                        var part = AttributedString(insert)
                        var intent: InlinePresentationIntent = []
                        if attributes["bold"] != nil { intent.insert(.stronglyEmphasized) }
                        if attributes["italic"] != nil { intent.insert(.emphasized) }
                        if attributes["strike"] != nil { intent.insert(.strikethrough) }
                        if attributes["code"] != nil { intent.insert(.code) }
                        part.inlinePresentationIntent = intent
                        if let link = attributes["link"] as? [String: Any], let href = link["href"] as? String {
                            part.link = URL(string: href)
                        }
                        value.append(part)
                    }
                } else {
                    supported = false
                    for child in node["children"] as? [[String: Any]] ?? [] { append(child) }
                }
            }
            children.forEach(append)
            ranges.append(NSRange(location: start, length: String(value.characters).utf16.count - start))
        }
        text = value
        blockRanges = ranges
        isEditable = supported && !blocks.isEmpty
    }

    public func position(atUTF16 offset: Int) -> (path: [Int], index: Int)? {
        for (block, range) in blockRanges.enumerated() where offset >= range.location && offset <= NSMaxRange(range) {
            return ([block, 0], offset - range.location)
        }
        return nil
    }

    public func offset(for position: RelayMarkCollaborationDocument.Position) -> Int? {
        guard position.path.count == 2, position.path[1] == 0,
              blockRanges.indices.contains(position.path[0]) else { return nil }
        let range = blockRanges[position.path[0]]
        guard position.index <= range.length else { return nil }
        return range.location + position.index
    }

    /// A single contiguous replacement at grapheme boundaries; unchanged runs retain CRDT identity.
    public static func replacement(from old: String, to new: String) -> (start: Int, end: Int, text: String) {
        let oldCharacters = Array(old), newCharacters = Array(new)
        var prefix = 0
        while prefix < min(oldCharacters.count, newCharacters.count), oldCharacters[prefix] == newCharacters[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(oldCharacters.count, newCharacters.count) - prefix,
              oldCharacters[oldCharacters.count - 1 - suffix] == newCharacters[newCharacters.count - 1 - suffix] { suffix += 1 }
        let start = String(oldCharacters[..<prefix]).utf16.count
        let end = String(oldCharacters[..<(oldCharacters.count - suffix)]).utf16.count
        return (start, end, String(newCharacters[prefix..<(newCharacters.count - suffix)]))
    }
}
