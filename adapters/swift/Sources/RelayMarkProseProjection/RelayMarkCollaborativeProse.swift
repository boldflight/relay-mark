import Foundation
import CoreFoundation

/// Deliberately bounded editable projection; unsupported structure is preserved by the replica.
public struct RelayMarkCollaborativeProse {
    public let text: AttributedString
    public let isEditable: Bool
    public let blockRanges: [NSRange]

    public let blockPaths: [[Int]]
    public struct TextRange: Equatable, Sendable {
        public let path: [Int]
        public let index: Int
        public let length: Int
    }
    private struct Span {
        let range: NSRange
        let path: [Int]
        let text: Bool
        let afterPath: [Int]
        let afterIndex: Int
    }
    private let spans: [Span]
    private let containerOffsets: [[Int]: [Int]]

    public init(snapshot: Data) throws {
        let root = try JSONSerialization.jsonObject(with: snapshot) as? [String: Any]
        var value = AttributedString()
        var ranges: [NSRange] = [], paths: [[Int]] = []
        var mapped: [Span] = []
        var boundaries: [[Int]: [Int]] = [:]
        var supported = root?["kind"] as? String == "fragment"
        var identity = 0
        func length() -> Int { String(value.characters).utf16.count }
        func validInteger(_ value: Any?, minimum: Int, maximum: Int = Int.max) -> Bool {
            guard let value, !(value is NSNull) else { return true }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let integer = value as? Int else { return false }
            return integer >= minimum && integer <= maximum
        }
        func appendText(_ leaf: [String: Any], path: [Int], codeBlock: Bool) {
            let start = length()
            guard let delta = leaf["delta"] as? [[String: Any]] else { supported = false; return }
            for run in delta {
                guard let insert = run["insert"] as? String else { supported = false; continue }
                let attributes = run["attributes"] as? [String: Any] ?? [:]
                if !Set(attributes.keys).isSubset(of: ["bold", "italic", "strike", "code", "link"]) { supported = false }
                if codeBlock && !attributes.isEmpty { supported = false }
                if attributes["code"] != nil && (attributes.count > 1 || insert.contains("\r") || insert.contains("\n")) { supported = false }
                for key in ["bold", "italic", "strike", "code"] where attributes[key] != nil {
                    if !(attributes[key] is [String: Any]) { supported = false }
                }
                var part = AttributedString(insert)
                var intent: InlinePresentationIntent = []
                if attributes["bold"] != nil { intent.insert(.stronglyEmphasized) }
                if attributes["italic"] != nil { intent.insert(.emphasized) }
                if attributes["strike"] != nil { intent.insert(.strikethrough) }
                if attributes["code"] != nil { intent.insert(.code) }
                part.inlinePresentationIntent = intent
                if let mark = attributes["link"] {
                    if let link = mark as? [String: Any], let href = link["href"] as? String,
                        Set(link.keys).isSubset(of: ["href", "target", "rel", "class"]),
                        !href.contains("\n"), !href.contains("<"), !href.contains(">"), let url = URL(string: href) {
                        part.link = url
                    } else { supported = false }
                }
                value.append(part)
            }
            mapped.append(Span(range: NSRange(location: start, length: length() - start), path: path,
                text: true, afterPath: path, afterIndex: length() - start))
        }
        func walk(_ nodes: [[String: Any]], path: [Int], parent: PresentationIntent? = nil, ordinal: Int = 1) {
            var offsets: [Int] = []
            for (index, block) in nodes.enumerated() {
                let blockPath = path + [index]
                let name = block["name"] as? String ?? ""
                let attributes = block["attributes"] as? [String: Any] ?? [:]
                let children = block["children"] as? [[String: Any]] ?? []
                if block["kind"] as? String != "element" { supported = false }
                identity += 1
                let kind: PresentationIntent.Kind
                switch name {
                case "paragraph": kind = .paragraph
                case "heading":
                    if !validInteger(attributes["level"], minimum: 1, maximum: 6) { supported = false }
                    kind = .header(level: min(6, max(1, attributes["level"] as? Int ?? 1)))
                case "codeBlock":
                    if let language = attributes["language"], !(language is NSNull), !(language is String) { supported = false }
                    if let language = attributes["language"] as? String, language.contains("\n") || language.contains("\r") { supported = false }
                    kind = .codeBlock(languageHint: attributes["language"] as? String)
                case "horizontalRule": kind = .thematicBreak
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
                let previousCount = ranges.count
                if ["blockquote", "bulletList", "orderedList", "listItem"].contains(name) {
                    if ["bulletList", "orderedList"].contains(name), children.contains(where: { $0["name"] as? String != "listItem" }) { supported = false }
                    walk(children, path: blockPath, parent: intent, ordinal: attributes["start"] as? Int ?? 1)
                } else {
                    if !ranges.isEmpty { value.append(AttributedString("\n")) }
                    let start = length(), attributedStart = value.endIndex
                    var inlineOffsets = [start]
                    if name == "horizontalRule" {
                        if !children.isEmpty { supported = false }
                        value.append(AttributedString("\u{FFFC}"))
                        mapped.append(Span(range: NSRange(location: start, length: 1), path: blockPath,
                            text: false, afterPath: path, afterIndex: index + 1))
                    } else {
                        for (childIndex, child) in children.enumerated() {
                            let childPath = blockPath + [childIndex]
                            if child["kind"] as? String == "text" { appendText(child, path: childPath, codeBlock: name == "codeBlock") }
                            else if child["kind"] as? String == "element", child["name"] as? String == "hardBreak",
                                (child["children"] as? [Any] ?? []).isEmpty,
                                (child["attributes"] as? [String: Any] ?? [:]).isEmpty, name != "codeBlock" {
                                let offset = length()
                                value.append(AttributedString("\u{2028}"))
                                boundaries[childPath] = [offset]
                                mapped.append(Span(range: NSRange(location: offset, length: 1), path: childPath,
                                    text: false, afterPath: blockPath, afterIndex: childIndex + 1))
                            } else { supported = false }
                            inlineOffsets.append(length())
                        }
                    }
                    boundaries[blockPath] = inlineOffsets
                    value[attributedStart..<value.endIndex].presentationIntent = intent
                    ranges.append(NSRange(location: start, length: length() - start)); paths.append(blockPath)
                }
                offsets.append(ranges.count > previousCount ? ranges[previousCount].location : length())
                // An XML boundary immediately after a rule maps to the atom's end.
                // The next text leaf has its own unambiguous start position.
                if index > 0, nodes[index - 1]["name"] as? String == "horizontalRule", previousCount > 0 {
                    offsets[offsets.count - 1] = NSMaxRange(ranges[previousCount - 1])
                }
            }
            offsets.append(length()); boundaries[path] = offsets
        }
        walk(root?["children"] as? [[String: Any]] ?? [], path: [])
        text = value; blockRanges = ranges; blockPaths = paths
        spans = mapped; containerOffsets = boundaries
        isEditable = supported && !ranges.isEmpty
    }

    /// Actual text-leaf intersections; atom and separator ranges never receive text marks.
    public func textRanges(in range: NSRange) -> [TextRange] {
        spans.filter(\.text).compactMap { span in
            let intersection = NSIntersectionRange(range, span.range)
            guard intersection.length > 0 else { return nil }
            return TextRange(path: span.path, index: intersection.location - span.range.location, length: intersection.length)
        }
    }

    public func position(atUTF16 offset: Int) -> (path: [Int], index: Int)? {
        for span in spans where offset >= span.range.location && offset <= NSMaxRange(span.range) {
            if span.text { return (span.path, offset - span.range.location) }
            if offset == span.range.location { return (span.path, 0) }
            return (span.afterPath, span.afterIndex)
        }
        for (block, range) in blockRanges.enumerated() where offset == range.location && range.length == 0 { return (blockPaths[block], 0) }
        return nil
    }

    /// Resolve a current XML position without coupling a native binding to one replica type.
    public func offset(path: [Int], index: Int) -> Int? {
        guard index >= 0 else { return nil }
        if let span = spans.first(where: { $0.text && $0.path == path }) {
            guard index <= span.range.length else { return nil }
            return span.range.location + index
        }
        guard let offsets = containerOffsets[path], index < offsets.count else { return nil }
        return offsets[index]
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
