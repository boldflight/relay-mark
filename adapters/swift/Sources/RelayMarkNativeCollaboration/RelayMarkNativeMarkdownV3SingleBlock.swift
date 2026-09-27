import Foundation
import Markdown

/// Bounded Markdown-to-v3 XML input shared by native authored commands.
/// The parser owns Markdown syntax; this adapter only maps an admitted single
/// block to the existing TipTap/Yjs XML shape. Unsupported nodes fail closed.
@MainActor
public enum RelayMarkNativeMarkdownV3SingleBlock {
    public static func canConvert(_ source: String) -> Bool { (try? parse(source)) != nil }

    enum Kind {
        case paragraph
        case heading(level: Int)
        case quote
        case code(language: String?)
        case rule
        case bulletList
        case orderedList(start: Int)

        var tag: String {
            switch self {
            case .paragraph: "paragraph"
            case .heading: "heading"
            case .quote: "blockquote"
            case .code: "codeBlock"
            case .rule: "horizontalRule"
            case .bulletList: "bulletList"
            case .orderedList: "orderedList"
            }
        }
    }

    struct Run {
        let text: String
        let attributes: [String: Any]
    }

    struct Block {
        let kind: Kind
        let runs: [Run]
        let listItems: [[Run]]

        init(kind: Kind, runs: [Run], listItems: [[Run]] = []) {
            self.kind = kind
            self.runs = runs
            self.listItems = listItems
        }

        func attributes(id: String, headingID: String?) -> [String: Any] {
            switch kind {
            case .paragraph, .quote, .rule, .bulletList: ["relaymarkId": id]
            case .heading(let level):
                ["relaymarkId": id, "level": level, "headingId": headingID ?? NSNull()]
            case .code(let language): ["relaymarkId": id, "language": language ?? NSNull()]
            // y-tiptap omits ProseMirror's null `type` from the Yjs XML attrs.
            case .orderedList(let start): ["relaymarkId": id, "start": start]
            }
        }

        func snapshot(id: String, headingID: String?, quoteParagraphID: String?,
                      listIDs: [(item: String, paragraph: String)]) throws -> [String: Any] {
            let text: [[String: Any]] = runs.isEmpty ? [] : [["kind": "text", "delta": runs.map {
                ["insert": $0.text, "attributes": $0.attributes] as [String: Any]
            }]]
            let children: [[String: Any]]
            switch kind {
            case .quote:
                guard let quoteParagraphID else { throw Failure.unsupported }
                children = [["kind": "element", "name": "paragraph",
                             "attributes": ["relaymarkId": quoteParagraphID], "children": text]]
            case .rule: children = []
            case .bulletList, .orderedList:
                guard listIDs.count == listItems.count else { throw Failure.unsupported }
                children = zip(listItems, listIDs).map { runs, ids in
                    let text: [[String: Any]] = [["kind": "text", "delta": runs.map {
                        ["insert": $0.text, "attributes": $0.attributes] as [String: Any]
                    }]]
                    return ["kind": "element", "name": "listItem",
                            "attributes": ["relaymarkId": ids.item],
                            "children": [["kind": "element", "name": "paragraph",
                                          "attributes": ["relaymarkId": ids.paragraph],
                                          "children": text]]]
                }
            default: children = text
            }
            return ["kind": "element", "name": kind.tag,
                    "attributes": attributes(id: id, headingID: headingID), "children": children]
        }
    }

    static func parse(_ source: String) throws -> Block {
        guard !source.isEmpty, source.utf16.count <= 32_768,
              source == source.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.contains("\r"), !source.contains("\0") else { throw Failure.unsupported }
        let document = Document(parsing: source)
        guard document.childCount == 1, let root = document.child(at: 0) else {
            throw Failure.unsupported
        }
        let kind: Kind
        if root is Paragraph { kind = .paragraph }
        else if let heading = root as? Heading, (1...6).contains(heading.level) {
            // PaperHeading's {#anchor} suffix is a Relay extension. Until it
            // has a shared converter, avoid turning its syntax into prose.
            guard source.range(of: #"\s+\{#[A-Za-z0-9][A-Za-z0-9_-]{0,127}\}$"#,
                               options: .regularExpression) == nil else { throw Failure.unsupported }
            kind = .heading(level: heading.level)
        } else if let quote = root as? BlockQuote, quote.childCount == 1,
                  quote.child(at: 0) is Paragraph {
            kind = .quote
        } else if let code = root as? CodeBlock {
            if let language = code.language,
               language.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) == nil {
                throw Failure.unsupported
            }
            kind = .code(language: code.language)
        } else if root is ThematicBreak { kind = .rule }
        else if root is UnorderedList { kind = .bulletList }
        else if let ordered = root as? OrderedList,
                ordered.startIndex >= 1, ordered.startIndex <= UInt(Int.max) {
            kind = .orderedList(start: Int(ordered.startIndex))
        }
        else { throw Failure.unsupported }
        switch kind {
        case .bulletList, .orderedList:
            guard (1...4_096).contains(root.childCount) else { throw Failure.unsupported }
            var items = [[Run]]()
            for child in root.children {
                guard let item = child as? ListItem, item.checkbox == nil,
                      item.childCount == 1, let paragraph = item.child(at: 0) as? Paragraph else {
                    throw Failure.unsupported
                }
                items.append(try inlineRuns(in: paragraph))
            }
            return Block(kind: kind, runs: [], listItems: items)
        default: break
        }
        if case .rule = kind { return Block(kind: kind, runs: []) }
        if case .code = kind {
            guard let code = root as? CodeBlock else { throw Failure.unsupported }
            // cmark includes the fence's terminating newline; TipTap's code
            // leaf stores only the authored body.
            let body = code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code
            guard !body.isEmpty else { throw Failure.unsupported }
            return Block(kind: kind, runs: [Run(text: body, attributes: [:])])
        }
        let inlineRoot: Markup
        if case .quote = kind {
            guard let paragraph = root.child(at: 0) else { throw Failure.unsupported }
            inlineRoot = paragraph
        } else { inlineRoot = root }
        return Block(kind: kind, runs: try inlineRuns(in: inlineRoot))
    }

    private static func inlineRuns(in root: Markup) throws -> [Run] {
        guard root.childCount > 0 else { throw Failure.unsupported }
        var runs: [Run] = []
        func append(_ markup: Markup, marks: [String: Any]) throws {
            if let value = markup as? Text {
                if !value.string.isEmpty { runs.append(Run(text: value.string, attributes: marks)) }
            } else if let value = markup as? InlineCode {
                guard marks.isEmpty else { throw Failure.unsupported }
                if !value.code.isEmpty { runs.append(Run(text: value.code, attributes: ["code": [String: Any]()])) }
            } else if let value = markup as? Strong {
                var nested = marks
                nested["bold"] = [String: Any]()
                for child in value.children { try append(child, marks: nested) }
            } else if let value = markup as? Emphasis {
                var nested = marks
                nested["italic"] = [String: Any]()
                for child in value.children { try append(child, marks: nested) }
            } else if let value = markup as? Link {
                guard marks["link"] == nil, value.title == nil,
                      let href = value.destination, !href.isEmpty,
                      let url = URL(string: href), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      url.host != nil else { throw Failure.unsupported }
                var nested = marks
                nested["link"] = ["href": href, "target": "_blank",
                                  "rel": "noopener noreferrer nofollow", "class": NSNull(),
                                  "title": NSNull()] as [String: Any]
                for child in value.children { try append(child, marks: nested) }
            } else { throw Failure.unsupported }
        }
        for child in root.children { try append(child, marks: [:]) }
        guard !runs.isEmpty, runs.count <= 4_096 else { throw Failure.unsupported }
        return runs
    }

    enum Failure: Error { case unsupported }
}
