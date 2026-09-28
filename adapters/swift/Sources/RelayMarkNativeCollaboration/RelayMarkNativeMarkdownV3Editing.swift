import Foundation
import RelayMarkProseProjection

/// Native selection replacement through ProseMirror's own algorithm. The v3
/// XML is read as a ProseMirror document in the browser's exact schema,
/// edited with the ported prosemirror-transform deleteRange / insertText /
/// replaceRange, and written back with y-prosemirror's diff, so selections
/// across paragraphs, lists, quotes, callouts, tables and atoms behave as
/// they do for a browser peer. Host authorization remains outside Mark.
@MainActor
public enum RelayMarkNativeMarkdownV3Editing {
    /// A caret in a projected textblock: its XML path and UTF-16 offset.
    public struct Caret: Equatable, Sendable {
        public let blockPath: [Int]
        public let offset: Int
    }

    public struct Change {
        public let update: Data
        /// ProseMirror's mapped selection head; nil when it leaves textblocks.
        public let caret: Caret?
    }

    /// Replaces a projected UTF-16 range as ProseMirror does for the same
    /// input: no text deletes the selection (deleteSelection), one line
    /// inserts inline text (insertText), and several lines paste paragraphs
    /// as an open slice (replaceRange). With `inheritMarks`, a single
    /// unattributed run takes ProseMirror's marks at the range, like typing.
    public static func replace(document: RelayMarkNativeDocument, range: NSRange,
                               runs: [(text: String, attributes: [String: Any])], inheritMarks: Bool = false,
                               expectedSnapshot: Data) throws -> Change {
        guard document.integrationStatus().isComplete, try document.snapshot() == expectedSnapshot,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let projection = try document.markdownV3ProseProjection()
        guard projection.isEditable, range.location >= 0, range.length >= 0 else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let bridge = try PMYXmlBridge.v3(), schema = bridge.schema
        let doc = try bridge.document(fromSnapshot: tree)
        let from = try position(range.location, projection: projection, doc: doc)
        let to = try position(NSMaxRange(range), projection: projection, doc: doc)

        var segments: [[(String, [String: Any])]] = [[]], length = 0
        for run in runs {
            guard run.text.utf16.count <= 131_072 - length, JSONSerialization.isValidJSONObject(run.attributes),
                  !run.text.unicodeScalars.contains(where: {
                      $0 == "\u{FFFC}" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}"
                  }) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            length += run.text.utf16.count
            for (index, part) in run.text.components(separatedBy: "\n").enumerated() {
                if index > 0 { segments.append([]) }
                if !part.isEmpty { segments[segments.count - 1].append((part, run.attributes)) }
            }
            guard segments.count <= 4_096 else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        }
        func inline(_ segment: [(String, [String: Any])]) throws -> [PMNode] {
            try segment.map { text, attributes in
                schema.text(Array(text.utf16), marks: try PMMark.setFrom(attributes.map { key, value in
                    guard let type = schema.marks[key] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                    return type.create(value as? [String: Any] ?? [:])
                }))
            }
        }

        var transform = PMTransform(doc)
        do {
            if length == 0 {
                guard from < to else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                try transform.deleteRange(from, to)
            } else if segments.count == 1 {
                if inheritMarks, runs.count == 1, runs[0].attributes.isEmpty {
                    try transform.insertText(Array(runs[0].text.utf16), from, to, schema: schema)
                } else {
                    try transform.replaceRange(from, to, PMSlice(PMFragment.fromArray(try inline(segments[0])),
                                                                  openStart: 0, openEnd: 0))
                }
            } else {
                guard let paragraph = schema.nodes["paragraph"] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                let paragraphs = try segments.map { segment in
                    try paragraph.create(["relaymarkId": RelayMarkNativeMarkdownV3XML.freshID()],
                                         PMFragment.fromArray(try inline(segment)))
                }
                try transform.replaceRange(from, to, PMSlice(PMFragment.fromArray(paragraphs), openStart: 1, openEnd: 1))
            }
        } catch is PMReplaceError {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        guard !transform.steps.isEmpty else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        var seen = Set<String>(), anchors = Set<String>()
        transform.doc.content.nodesBetween(0, transform.doc.content.size, { node, _, _, _ in
            if node.type.name == "relayAnchor", let name = node.attrs["name"] as? String { anchors.insert(name) }
            return true
        })
        let updated = identified(transform.doc, seen: &seen, anchors: &anchors)

        let prospective = bridge.snapshot(updated)
        let expected = try RelayMarkNativeMarkdownBlocksV3Projection.project(
            snapshot: JSONSerialization.data(withJSONObject: prospective, options: [.sortedKeys]))
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        _ = try scratch.applyProseMirror(updated, source: doc, bridge: bridge)
        guard try RelayMarkNativeMarkdownBlocksV3Projection.project(document: scratch) == expected,
              try scratch.markdownV3ProseProjection().isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let update = try document.applyProseMirror(updated, source: doc, bridge: bridge)
        // deleteSelection places the caret with selectionToInsertionEnd;
        // insertText and replaceRange map the TextSelection head.
        let head: Int?
        if length == 0, let (start, _, newSize) = transform.steps.last?.ranges.first {
            head = selectionNear(updated, start + newSize, bias: 1)
        } else {
            let mapped = transform.map(to, assoc: 1)
            head = (try? updated.resolve(mapped))?.parent.inlineContent == true
                ? mapped : selectionNear(updated, mapped, bias: 1)
        }
        return Change(update: update, caret: head.flatMap { caret($0, in: updated) })
    }

    /// Selection.near restricted to text: nil when ProseMirror would select a node.
    private static func selectionNear(_ doc: PMNode, _ pos: Int, bias: Int) -> Int? {
        guard let resolved = try? doc.resolve(pos) else { return nil }
        enum Found { case text(Int), node }
        func within(_ node: PMNode, _ pos: Int, _ index: Int, _ dir: Int) -> Found? {
            if node.inlineContent { return .text(pos) }
            var i = index - (dir > 0 ? 0 : 1), pos = pos
            while dir > 0 ? i < node.childCount : i >= 0 {
                let child = node.child(i)
                if !child.isAtom {
                    if let inner = within(child, pos + dir, dir < 0 ? child.childCount : 0, dir) { return inner }
                } else {
                    return .node
                }
                pos += child.nodeSize * dir
                i += dir
            }
            return nil
        }
        func from(_ dir: Int) -> Found? {
            if let inner = resolved.parent.inlineContent ? .text(resolved.pos)
                : within(resolved.parent, resolved.pos, resolved.index(), dir) { return inner }
            var depth = resolved.depth - 1
            while depth >= 0 {
                let found = dir < 0
                    ? within(resolved.node(depth), resolved.before(depth + 1), resolved.index(depth), dir)
                    : within(resolved.node(depth), resolved.after(depth + 1), resolved.index(depth) + 1, dir)
                if let found { return found }
                depth -= 1
            }
            return nil
        }
        if case .text(let position)? = from(bias) ?? from(-bias) { return position }
        return nil
    }

    /// The ProseMirror position of a projected offset inside a textblock.
    private static func position(_ offset: Int, projection: RelayMarkCollaborativeProse, doc: PMNode) throws -> Int {
        guard let block = projection.blockRanges.firstIndex(where: {
            offset >= $0.location && offset <= NSMaxRange($0)
        }) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        var node = doc, pos = 0
        for index in projection.blockPaths[block] {
            guard index < node.childCount else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
            for sibling in 0..<index { pos += node.child(sibling).nodeSize }
            node = node.child(index)
            pos += 1
        }
        let local = offset - projection.blockRanges[block].location
        guard node.isTextblock, local <= node.content.size else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return pos + local
    }

    private static func caret(_ pos: Int, in doc: PMNode) -> Caret? {
        guard let resolved = try? doc.resolve(pos), resolved.parent.isTextblock else { return nil }
        return Caret(blockPath: (0..<resolved.depth).map { resolved.index($0) }, offset: resolved.parentOffset)
    }

    /// PaperHeading's anchor-name rule for headingId.
    private static func anchorName(_ value: Any?) -> Bool {
        guard let value = value as? String, (1...128).contains(value.utf16.count),
              let first = value.unicodeScalars.first, first.isASCII,
              CharacterSet.alphanumerics.contains(first) else { return false }
        return value.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-") }
    }

    /// UniqueID and PaperHeading after a local edit: nodes created by the
    /// transform (null IDs) and later duplicates receive fresh relaymarkIds,
    /// headings keep a unique anchor headingId; retained nodes keep theirs.
    private static func identified(_ node: PMNode, seen: inout Set<String>, anchors: inout Set<String>) -> PMNode {
        var attrs = node.attrs, changed = false
        if node.type.name == "heading" {
            let current = attrs["headingId"]
            if !anchorName(current) || anchors.contains(current as? String ?? "") {
                var id = "h-" + UUID().uuidString.lowercased()
                while anchors.contains(id) { id = "h-" + UUID().uuidString.lowercased() }
                attrs["headingId"] = id
                changed = true
            }
            anchors.insert(attrs["headingId"] as? String ?? "")
        }
        if node.type.attrs.contains(where: { $0.name == "relaymarkId" }) {
            if let id = attrs["relaymarkId"] as? String, seen.insert(id).inserted {
                // retained
            } else {
                let id = RelayMarkNativeMarkdownV3XML.freshID()
                seen.insert(id)
                attrs["relaymarkId"] = id
                changed = true
            }
        }
        var children = node.content.children, childChanged = false
        for (index, child) in children.enumerated() where !child.isText {
            let next = identified(child, seen: &seen, anchors: &anchors)
            if next !== child { children[index] = next; childChanged = true }
        }
        guard changed || childChanged else { return node }
        return PMNode(type: node.type, attrs: attrs, content: childChanged ? PMFragment(children) : node.content,
                      marks: node.marks)
    }
}
