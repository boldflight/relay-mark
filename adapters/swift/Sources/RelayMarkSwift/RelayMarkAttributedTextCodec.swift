import Foundation

/// A native attributed-text bridge for RelayMark's Markdown-compatible prose source.
///
/// The canonical interchange remains ``RelayMarkDocument``. This codec is the
/// lossless authoring bridge for headings, lists, emphasis, code, ordinary
/// links, and canonical `relay:` inline references. Hosts remain responsible
/// for resolving references and presenting product-specific entity UI.
public enum RelayMarkAttributedTextCodec {
    /// Parses RelayMark-compatible prose source into native attributed text.
    public static func attributedString(from source: String) -> AttributedString {
        guard !source.isEmpty else { return AttributedString() }
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
    }

    /// Encodes native attributed text back into RelayMark-compatible prose source.
    public static func source(from text: AttributedString) -> String {
        guard !text.characters.isEmpty else { return "" }

        var blocks: [Block] = []
        var current: Block?
        for run in text.runs {
            let content = inlineSource(
                String(text[run.range].characters),
                intent: run.inlinePresentationIntent,
                link: run.link
            )
            let descriptor = blockDescriptor(run.presentationIntent)
            if var existing = current, existing.identity == descriptor.identity {
                existing.content += content
                current = existing
            } else {
                if let current { blocks.append(current) }
                current = Block(
                    identity: descriptor.identity,
                    prefix: descriptor.prefix,
                    listIdentity: descriptor.listIdentity,
                    content: content
                )
            }
        }
        if let current { blocks.append(current) }

        var result = ""
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                let prior = blocks[index - 1]
                result += prior.listIdentity != nil && prior.listIdentity == block.listIdentity
                    ? "\n" : "\n\n"
            }
            result += block.prefix + block.content
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns each unique canonical entity reference in source order.
    public static func entityReferences(in source: String) -> [RelayMarkSourceEntityReference] {
        let text = attributedString(from: source)
        var seen = Set<String>()
        var references: [RelayMarkSourceEntityReference] = []
        var currentID: String?
        var currentLabel = ""

        func finishReference() {
            if let currentID, seen.insert(currentID).inserted {
                references.append(RelayMarkSourceEntityReference(id: currentID, label: currentLabel))
            }
            currentID = nil
            currentLabel = ""
        }

        for run in text.runs {
            let id: String?
            if let url = run.link?.absoluteString, url.hasPrefix("relay:entity/") {
                let candidate = String(url.dropFirst("relay:entity/".count))
                id = candidate.isEmpty ? nil : candidate
            } else {
                id = nil
            }
            if id != currentID { finishReference() }
            currentID = id
            if id != nil { currentLabel += String(text[run.range].characters) }
        }
        finishReference()
        return references
    }

    /// Creates the canonical Markdown source form for an entity reference.
    public static func entityLink(label: String, id: String) -> String {
        "[\(escapedLabel(label))](relay:entity/\(id))"
    }

    private static func inlineSource(
        _ value: String,
        intent: InlinePresentationIntent?,
        link: URL?
    ) -> String {
        var result = value
        if let intent {
            if intent.contains(.code) { result = "`\(result)`" }
            if intent.contains(.stronglyEmphasized) { result = "**\(result)**" }
            if intent.contains(.emphasized) { result = "*\(result)*" }
            if intent.contains(.strikethrough) { result = "~~\(result)~~" }
        }
        if let link {
            result = "[\(escapedLabel(result))](\(link.absoluteString))"
        }
        return result
    }

    private static func blockDescriptor(
        _ intent: PresentationIntent?
    ) -> (identity: Int, prefix: String, listIdentity: Int?) {
        guard let components = intent?.components, !components.isEmpty else {
            return (0, "", nil)
        }

        var identity = components[0].identity
        var prefix = ""
        var listIdentity: Int?
        for component in components {
            switch component.kind {
            case .header(let level):
                identity = component.identity
                prefix = String(repeating: "#", count: max(1, min(level, 6))) + " "
            case .paragraph:
                identity = component.identity
            case .listItem(let ordinal):
                identity = component.identity
                if prefix.isEmpty { prefix = "\(ordinal). " }
            case .unorderedList:
                listIdentity = component.identity
                prefix = "- "
            case .orderedList:
                listIdentity = component.identity
            default:
                break
            }
        }
        return (identity, prefix, listIdentity)
    }

    private static func escapedLabel(_ value: String) -> String {
        value.replacingOccurrences(of: "]", with: #"\]"#)
    }

    private struct Block {
        let identity: Int
        let prefix: String
        let listIdentity: Int?
        var content: String
    }
}

/// A canonical entity link extracted from RelayMark-compatible prose source.
public struct RelayMarkSourceEntityReference: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}
