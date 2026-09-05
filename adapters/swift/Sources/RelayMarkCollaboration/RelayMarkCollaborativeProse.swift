import Foundation
import CoreFoundation

/// Deliberately bounded editable projection; unsupported structure is preserved by the replica.
public struct RelayMarkCollaborativeProse {
    public let text: AttributedString
    public let isEditable: Bool
    public let blockRanges: [NSRange]

    public let blockPaths: [[Int]]
    private let anchorPaths: [[Int]]

    public init(snapshot: Data) throws {
        let root = try JSONSerialization.jsonObject(with: snapshot) as? [String: Any]
        var value = AttributedString()
        var ranges: [NSRange] = []
        var paths: [[Int]] = []
        var anchors: [[Int]] = []
        var supported = true
        var identity = 0

        func validInteger(_ value: Any?, minimum: Int, maximum: Int = Int.max) -> Bool {
            guard let value, !(value is NSNull) else { return true }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let integer = value as? Int else { return false }
            return integer >= minimum && integer <= maximum
        }

        func appendText(_ node: [String: Any]) {
            if let delta = node["delta"] as? [[String: Any]] {
                for run in delta {
                    guard let insert = run["insert"] as? String else { supported = false; continue }
                    let attributes = run["attributes"] as? [String: Any] ?? [:]
                    if !Set(attributes.keys).isSubset(of: ["bold", "italic", "strike", "code", "link"]) { supported = false }
                    if attributes["code"] != nil && (attributes.count > 1 || insert.contains("\r") || insert.contains("\n")) { supported = false }
                    if let link = attributes["link"] as? [String: Any],
                       !Set(link.keys).isSubset(of: ["href", "target", "rel", "class"]) { supported = false }
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
                for child in node["children"] as? [[String: Any]] ?? [] { appendText(child) }
            }
        }

        func walk(_ nodes: [[String: Any]], path: [Int], parent: PresentationIntent? = nil, ordinal: Int = 1) {
            for (index, block) in nodes.enumerated() {
                let blockPath = path + [index]
                let name = block["name"] as? String ?? ""
                let attributes = block["attributes"] as? [String: Any] ?? [:]
                let children = block["children"] as? [[String: Any]] ?? []
                identity += 1
                let kind: PresentationIntent.Kind
                switch name {
                case "paragraph": kind = .paragraph
                case "heading":
                    if !validInteger(attributes["level"], minimum: 1, maximum: 6) { supported = false }
                    kind = .header(level: min(6, max(1, attributes["level"] as? Int ?? 1)))
                case "codeBlock": kind = .codeBlock(languageHint: attributes["language"] as? String)
                case "blockquote": kind = .blockQuote
                case "bulletList": kind = .unorderedList
                case "orderedList":
                    if !validInteger(attributes["start"], minimum: 1) { supported = false }
                    kind = .orderedList
                case "listItem": kind = .listItem(ordinal: ordinal + index)
                default: supported = false; kind = .paragraph
                }
                let allowed: Set<String> = name == "heading" ? ["level"] : name == "codeBlock" ? ["language"] : name == "orderedList" ? ["start"] : []
                if !Set(attributes.keys).isSubset(of: allowed) { supported = false }
                let intent = PresentationIntent(kind, identity: identity, parent: parent)
                if ["blockquote", "bulletList", "orderedList", "listItem"].contains(name) {
                    walk(children, path: blockPath, parent: intent, ordinal: attributes["start"] as? Int ?? 1)
                } else {
                    if !ranges.isEmpty { value.append(AttributedString("\n")) }
                    let start = String(value.characters).utf16.count
                    let attributedStart = value.endIndex
                    if children.count > 1 { supported = false }
                    children.forEach(appendText)
                    value[attributedStart..<value.endIndex].presentationIntent = intent
                    ranges.append(NSRange(location: start, length: String(value.characters).utf16.count - start))
                    paths.append(blockPath)
                    anchors.append(children.isEmpty ? blockPath : blockPath + [0])
                }
            }
        }
        walk(root?["children"] as? [[String: Any]] ?? [], path: [])
        text = value
        blockRanges = ranges
        blockPaths = paths
        anchorPaths = anchors
        isEditable = supported && !ranges.isEmpty
    }

    public func position(atUTF16 offset: Int) -> (path: [Int], index: Int)? {
        for (block, range) in blockRanges.enumerated() where offset >= range.location && offset <= NSMaxRange(range) {
            return (anchorPaths[block], offset - range.location)
        }
        return nil
    }

    public func offset(for position: RelayMarkCollaborationDocument.Position) -> Int? {
        let block = anchorPaths.firstIndex(of: position.path)
            ?? blockPaths.firstIndex(of: position.path)
            ?? blockPaths.firstIndex(of: Array(position.path.dropLast()))
        guard let block else { return nil }
        let range = blockRanges[block]
        if position.path == blockPaths[block] { return range.location + (position.index == 0 ? 0 : range.length) }
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
