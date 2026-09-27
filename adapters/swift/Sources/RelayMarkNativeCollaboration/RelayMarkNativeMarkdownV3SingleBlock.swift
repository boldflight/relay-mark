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

        var tag: String {
            switch self {
            case .paragraph: "paragraph"
            case .heading: "heading"
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

        func attributes(id: String, headingID: String?) -> [String: Any] {
            switch kind {
            case .paragraph: ["relaymarkId": id]
            case .heading(let level):
                ["relaymarkId": id, "level": level, "headingId": headingID ?? NSNull()]
            }
        }

        func snapshot(id: String, headingID: String?) -> [String: Any] {
            ["kind": "element", "name": kind.tag, "attributes": attributes(id: id, headingID: headingID),
             "children": [["kind": "text", "delta": runs.map {
                 ["insert": $0.text, "attributes": $0.attributes] as [String: Any]
             }]]]
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
        } else { throw Failure.unsupported }
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
        return Block(kind: kind, runs: runs)
    }

    enum Failure: Error { case unsupported }
}
