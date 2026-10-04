import Foundation
import RelayMarkProseProjection

/// Native selection replacement through ProseMirror's own algorithm. The v3
/// XML is read as a ProseMirror document in the browser's exact schema,
/// edited with the ported prosemirror-transform deleteRange / insertText /
/// replaceRange, and written back with y-prosemirror's diff, so selections
/// across paragraphs, lists, quotes, callouts, tables and atoms behave as
/// they do for a browser peer. Host authorization remains outside Mark.
@MainActor
public enum RelayMarkNativeRichEditing {
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
        let projection = try document.richProseProjection()
        guard projection.isEditable, range.location >= 0, range.length >= 0 else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let bridge = try PMYXmlBridge.canonical(), schema = bridge.schema
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
                    try paragraph.create(["relaymarkId": RelayMarkNativeRichXML.freshID()],
                                         PMFragment.fromArray(try inline(segment)))
                }
                try transform.replaceRange(from, to, PMSlice(PMFragment.fromArray(paragraphs), openStart: 1, openEnd: 1))
            }
        } catch is PMReplaceError {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        guard !transform.steps.isEmpty else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let (update, updated) = try commit(transform, source: doc, bridge: bridge, document: document)
        // deleteSelection places the caret with selectionToInsertionEnd;
        // insertText and replaceRange map the TextSelection head.
        let head: Int?
        if length == 0, let (start, _, newSize) = transform.steps.last?.ranges.first {
            head = (try? updated.resolve(start + newSize)).flatMap { PMCommands.near($0) }.flatMap {
                if case .text(let pos) = $0 { return pos } else { return nil }
            }
        } else {
            let mapped = transform.map(to, assoc: 1)
            head = (try? updated.resolve(mapped))?.parent.inlineContent == true
                ? mapped : (try? updated.resolve(mapped)).flatMap { PMCommands.near($0) }.flatMap {
                    if case .text(let pos) = $0 { return pos } else { return nil }
                }
        }
        return Change(update: update, caret: head.flatMap { caret($0, in: updated) })
    }

    /// Inline content for insertion: marked text or an inline node such as
    /// relayTag, relayReference or hardBreak, with its authored attributes.
    public enum Inline {
        case text(String, attributes: [String: Any] = [:])
        case node(String, attributes: [String: Any] = [:])
    }

    /// TipTap insertContent for inline content: replaces the projected range
    /// with the given nodes in one transaction and places the caret after
    /// them. Unknown node types, attributes or marks are refused.
    public static func insert(document: RelayMarkNativeDocument, range: NSRange, content: [Inline],
                              expectedSnapshot: Data) throws -> Change {
        guard document.integrationStatus().isComplete, try document.snapshot() == expectedSnapshot,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any], !content.isEmpty else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let projection = try document.richProseProjection()
        guard projection.isEditable, range.location >= 0, range.length >= 0 else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let bridge = try PMYXmlBridge.canonical(), schema = bridge.schema
        let doc = try bridge.document(fromSnapshot: tree)
        let from = try position(range.location, projection: projection, doc: doc)
        let to = try position(NSMaxRange(range), projection: projection, doc: doc)
        let nodes = try content.map { item -> PMNode in
            switch item {
            case let .text(text, attributes):
                guard !text.isEmpty, !text.contains("\n"), JSONSerialization.isValidJSONObject(attributes) else {
                    throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
                }
                return schema.text(Array(text.utf16), marks: try PMMark.setFrom(attributes.map { key, value in
                    guard let type = schema.marks[key] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                    return type.create(value as? [String: Any] ?? [:])
                }))
            case let .node(name, attributes):
                guard let type = schema.nodes[name], type.isInline, !type.isText,
                      Set(attributes.keys).isSubset(of: type.attrs.map(\.name)),
                      JSONSerialization.isValidJSONObject(attributes) else {
                    throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
                }
                return try type.create(attributes)
            }
        }
        var transform = PMTransform(doc)
        do {
            try transform.replaceRange(from, to, PMSlice(PMFragment.fromArray(nodes), openStart: 0, openEnd: 0))
        } catch is PMReplaceError {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        guard !transform.steps.isEmpty else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let (update, updated) = try commit(transform, source: doc, bridge: bridge, document: document)
        let head = transform.map(to, assoc: 1)
        return Change(update: update, caret: caret(head, in: updated))
    }

    /// How a block is placed, matching the browser command that inserts it.
    public enum BlockPlacement: Sendable {
        /// ProseMirror replaceSelectionWith, as TipTap insertTable does.
        case replaceSelection
        /// TipTap insertContentAt: an empty textblock at the caret is replaced.
        case insertContent
    }

    /// Inserts one block node, given as ProseMirror JSON (`type`, `attrs`,
    /// `content`, text `marks`), at the projected range. Created nodes get
    /// fresh relaymarkIds; the caret moves into the first text position of
    /// the inserted block, or after it when the block has none.
    public static func insertBlock(document: RelayMarkNativeDocument, range: NSRange, block json: [String: Any],
                                   placement: BlockPlacement, expectedSnapshot: Data) throws -> Change {
        guard document.integrationStatus().isComplete, try document.snapshot() == expectedSnapshot,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let projection = try document.richProseProjection()
        guard projection.isEditable, range.location >= 0, range.length >= 0 else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let bridge = try PMYXmlBridge.canonical(), schema = bridge.schema
        let doc = try bridge.document(fromSnapshot: tree)
        var from = try position(range.location, projection: projection, doc: doc)
        var to = try position(NSMaxRange(range), projection: projection, doc: doc)
        func node(_ json: [String: Any]) throws -> PMNode {
            guard let name = json["type"] as? String, let type = schema.nodes[name] else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            let marks = try (json["marks"] as? [[String: Any]] ?? []).map { mark -> PMMark in
                guard let name = mark["type"] as? String, let type = schema.marks[name] else {
                    throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
                }
                return type.create(mark["attrs"] as? [String: Any] ?? [:])
            }
            if type.isText {
                guard let text = json["text"] as? String, !text.isEmpty else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                return schema.text(Array(text.utf16), marks: marks)
            }
            let attrs = json["attrs"] as? [String: Any] ?? [:]
            guard Set(attrs.keys).isSubset(of: type.attrs.map(\.name)), JSONSerialization.isValidJSONObject(attrs) else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            let content = PMFragment.fromArray(try (json["content"] as? [[String: Any]] ?? []).map(node))
            guard let created = type.createAndFill(attrs, content, marks: marks), created.content.eq(content) || content.size == 0 else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            return created
        }
        let inserted = try node(json)
        guard inserted.isBlock else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        var transform = PMTransform(doc)
        do {
            if placement == .insertContent {
                let from$ = try doc.resolve(from)
                if from == to, from$.parent.isTextblock, !from$.parent.type.flag("code"), from$.parent.childCount == 0 {
                    from -= 1
                    to += 1
                }
                try transform.replaceWith(from, to, PMFragment.from(inserted))
            } else {
                try transform.replaceRangeWith(from, to, inserted)
            }
        } catch is PMReplaceError {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        guard !transform.steps.isEmpty else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let (update, updated) = try commit(transform, source: doc, bridge: bridge, document: document)
        // selectionToInsertionEnd: the end of the last step's replaced range,
        // biased backward for insertContent and forward for replaceSelectionWith.
        var head: Int?
        if let (start, _, size) = transform.steps.last?.ranges.first, let end$ = try? updated.resolve(start + size),
           case .text(let pos)? = PMCommands.near(end$, bias: placement == .insertContent ? -1 : 1) {
            head = pos
        }
        // TipTap insertTable selects near the original selection start + 1,
        // unmapped, which lands in the first cell of the inserted table.
        if inserted.type.name == "table", let next$ = try? updated.resolve(min(from + 1, updated.content.size)),
           case .text(let inside)? = PMCommands.near(next$) {
            head = inside
        }
        return Change(update: update, caret: head.flatMap { caret($0, in: updated) })
    }

    public enum Key: Sendable {
        case backspace, delete
    }

    /// Backspace or Delete at a collapsed projected caret through the
    /// browser's keymap chain (TipTap Keymap, branching-list and blockquote
    /// handlers, prosemirror-commands joinBackward/joinForward). Returns nil
    /// when the browser would leave the document unchanged, including when
    /// its handlers only select a node or throw.
    public static func key(_ key: Key, document: RelayMarkNativeDocument, at offset: Int,
                           expectedSnapshot: Data) throws -> Change? {
        guard document.integrationStatus().isComplete, try document.snapshot() == expectedSnapshot,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let projection = try document.richProseProjection()
        guard projection.isEditable else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let bridge = try PMYXmlBridge.canonical()
        let doc = try bridge.document(fromSnapshot: tree)
        let head = try position(offset, projection: projection, doc: doc)
        let result: PMState
        do {
            let state = PMState(transform: PMTransform(doc), selection: .text(head))
            result = key == .backspace ? try PMCommands.backspace(state) : try PMCommands.delete(state)
        } catch is PMReplaceError {
            return nil
        }
        guard !result.transform.steps.isEmpty else { return nil }
        let (update, updated) = try commit(result.transform, source: doc, bridge: bridge, document: document)
        guard case .text(let pos) = result.selection else { return Change(update: update, caret: nil) }
        return Change(update: update, caret: caret(pos, in: updated))
    }

    /// Applies identity rules, validates the prospective document on a
    /// scratch replica, then writes it through y-prosemirror's diff.
    private static func commit(_ transform: PMTransform, source: PMNode, bridge: PMYXmlBridge,
                               document: RelayMarkNativeDocument) throws -> (Data, PMNode) {
        var seen = Set<String>(), anchors = Set<String>()
        transform.doc.content.nodesBetween(0, transform.doc.content.size, { node, _, _, _ in
            if node.type.name == "relayAnchor", let name = node.attrs["name"] as? String { anchors.insert(name) }
            return true
        })
        let updated = identified(transform.doc, seen: &seen, anchors: &anchors)
        let prospective = bridge.snapshot(updated)
        let expected = try RelayMarkNativeDocumentProjection.project(
            snapshot: JSONSerialization.data(withJSONObject: prospective, options: [.sortedKeys]))
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        _ = try scratch.applyProseMirror(updated, source: source, bridge: bridge)
        guard try RelayMarkNativeDocumentProjection.project(document: scratch) == expected,
              try scratch.richProseProjection().isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return (try document.applyProseMirror(updated, source: source, bridge: bridge), updated)
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
                let id = RelayMarkNativeRichXML.freshID()
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
