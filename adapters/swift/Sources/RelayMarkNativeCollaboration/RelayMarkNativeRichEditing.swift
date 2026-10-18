import Foundation
import CoreFoundation
import RelayMarkProseProjection
import RelayMarkSwift

/// Native selection replacement through ProseMirror's own algorithm. Canonical
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
        public init(blockPath: [Int], offset: Int) { self.blockPath=blockPath; self.offset=offset }
    }

    public struct Change: Sendable {
        public let update: Data
        /// ProseMirror's mapped selection head; nil when it leaves textblocks.
        public let caret: Caret?
        /// The same transaction changed authored envelope metadata.
        public let authoredMetadataChanged: Bool
        /// Exact maintained command typing context. nil is the actual null
        /// storedMarks state; an empty array/map explicitly clears marks.
        public let storedMarks: Data?
        public let storedTextAttributes: Data?
        /// Call-local exact fitter correspondence/normalizations, never a journal field.
        public let clipboardFitting: Data?
        /// For a windowed command, the top-level nodes it rewrote: their range
        /// before and after. A host re-projects just these.
        public internal(set) var topLevel: (before: Range<Int>, after: Range<Int>)?
        init(update:Data,caret:Caret?,authoredMetadataChanged:Bool=false,storedMarks:Data?=nil,storedTextAttributes:Data?=nil,clipboardFitting:Data?=nil){
            self.update=update;self.caret=caret;self.authoredMetadataChanged=authoredMetadataChanged
            self.storedMarks=storedMarks;self.storedTextAttributes=storedTextAttributes;self.clipboardFitting=clipboardFitting
        }
    }

    /// Replaces a projected UTF-16 range as ProseMirror does for the same
    /// input: no text deletes the selection (deleteSelection), one line
    /// inserts inline text (insertText), and several lines paste paragraphs
    /// as an open slice (replaceRange). With `inheritMarks`, a single
    /// unattributed run takes ProseMirror's marks at the range, like typing.
    public static func replace(document: RelayMarkNativeDocument, range: NSRange,
                               runs: [(text: String, attributes: [String: Any])], inheritMarks: Bool = false,
                               expectedSnapshot: Data) throws -> Change {
        try replace(document: document, range: range, runs: runs, inheritMarks: inheritMarks,
                    scope: scope(document: document, expectedSnapshot: expectedSnapshot))
    }

    /// The same command reading and writing only the top-level nodes around
    /// `range`. `paper` is the caller's projection of the document as it is now.
    public static func replace(document: RelayMarkNativeDocument, range: NSRange,
                               runs: [(text: String, attributes: [String: Any])], inheritMarks: Bool = false,
                               paper: RelayMarkCollaborativeProse) throws -> Change {
        try replace(document: document, range: range, runs: runs, inheritMarks: inheritMarks,
                    scope: scope(document: document, paper: paper, range: range))
    }

    private static func replace(document: RelayMarkNativeDocument, range paperRange: NSRange,
                                runs: [(text: String, attributes: [String: Any])], inheritMarks: Bool,
                                scope: Scope) throws -> Change {
        let range = scope.local(paperRange), tree = scope.tree, projection = scope.projection
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
        let (update, updated) = try commit(transform, source: doc, bridge: bridge, document: document, window: scope.nodes, outside: scope.outside)
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
        return scope.paper(Change(update: update, caret: head.flatMap { caret($0, in: updated) }), updated: updated)
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

    /// Insert a validated canonical block slice through the maintained PM
    /// replacement owner. Caller-supplied depths describe the clipboard Slice;
    /// this does not guess browser clipboard openness or grant host authority.
    public static func insertDocumentSlice(document: RelayMarkNativeDocument, range: NSRange,
        authoredAST: Data, openStart: Int, openEnd: Int, expectedSnapshot: Data) throws -> Change {
        guard document.integrationStatus().isComplete, try document.snapshot() == expectedSnapshot,
              range.location >= 0, range.length >= 0, openStart >= 0, openEnd >= 0,
              let before = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any],
              let incomingSnapshot = try JSONSerialization.jsonObject(with: RelayMarkSourceCodec.documentToSnapshot(authoredAST)) as? [String: Any],
              (incomingSnapshot["metadata"] == nil || (incomingSnapshot["metadata"] as? [String: Any])?.isEmpty == true) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: before)
        let imported = try bridge.document(fromSnapshot: incomingSnapshot)
        guard imported.childCount > 0 else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return try applyDocumentSlice(document: document, range: range, source: source, imported: imported,
            openStart: openStart, openEnd: openEnd, bridge: bridge)
    }

    /// Original fragment preflight is the host's responsibility; final fitted
    /// document passes the existing canonical write/projector before mutation.
    public static func insertDocumentSlice(document: RelayMarkNativeDocument, range: NSRange,
        clipboardSlice: Data, expectedSnapshot: Data) throws -> Change {
        try insertDocumentSlices(document: document, range: range, clipboardSlices: [clipboardSlice],
                                 scope: { _ in try scope(document: document, expectedSnapshot: expectedSnapshot) })
    }

    /// The same paste reading and writing only the top-level nodes the range
    /// touches. `paper` is the caller's projection of the document as it is now.
    public static func insertDocumentSlice(document: RelayMarkNativeDocument, range: NSRange,
        clipboardSlice: Data, paper: RelayMarkCollaborativeProse) throws -> Change {
        try insertDocumentSlices(document: document, range: range, clipboardSlices: [clipboardSlice],
                                 scope: { try windowedPasteScope(document: document, paper: paper, range: range, names: $0) })
    }

    public static func insertDocumentSlice(document: RelayMarkNativeDocument, range: NSRange,
        clipboardSlices: [Data], paper: RelayMarkCollaborativeProse) throws -> Change {
        try insertDocumentSlices(document: document, range: range, clipboardSlices: clipboardSlices,
                                 scope: { try windowedPasteScope(document: document, paper: paper, range: range, names: $0) })
    }

    /// A window, unless a pasted Anchor name is already used elsewhere in the
    /// paper: the maintained allocator then plans against the whole paper.
    private static func windowedPasteScope(document: RelayMarkNativeDocument, paper: RelayMarkCollaborativeProse,
                                           range: NSRange, names: Set<String>) throws -> Scope {
        let window = try scope(document: document, paper: paper, range: range)
        guard let nodes = window.nodes, !names.contains(where: { paper.anchorUsed($0, outside: nodes) }) else {
            return try scope(document: document, expectedSnapshot: document.snapshot())
        }
        return window
    }

    private static func applyDocumentSlice(document: RelayMarkNativeDocument, range: NSRange,
        source: PMNode, imported: PMNode, openStart: Int, openEnd: Int, bridge: PMYXmlBridge) throws -> Change {
        try applyDocumentSlices(document: document, range: range, source: source,
            fragments: [(imported, openStart, openEnd)], bridge: bridge)
    }

    public static func insertDocumentSlice(document: RelayMarkNativeDocument, range: NSRange,
        clipboardSlices: [Data], expectedSnapshot: Data) throws -> Change {
        try insertDocumentSlices(document: document, range: range, clipboardSlices: clipboardSlices,
                                 scope: { _ in try scope(document: document, expectedSnapshot: expectedSnapshot) })
    }

    private static func insertDocumentSlices(document: RelayMarkNativeDocument, range: NSRange, clipboardSlices: [Data],
                                             scope makeScope: (Set<String>) throws -> Scope) throws -> Change {
        guard (1...4096).contains(clipboardSlices.count), document.integrationStatus().isComplete,
              range.location >= 0, range.length >= 0 else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let bridge = try PMYXmlBridge.canonical()
        var count = 0, fragments: [(PMNode, Int, Int)] = []
        for bytes in clipboardSlices {
            guard let result = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  Set(result.keys) == Set(["slice", "normalizations"]), result["normalizations"] is [[String: Any]],
                  let raw = result["slice"] as? [String: Any], Set(raw.keys) == Set(["content", "openStart", "openEnd"]),
                  let content = raw["content"] as? [[String: Any]], !content.isEmpty else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            count += content.count
            guard count <= 4096 else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            for key in ["openStart", "openEnd"] {
                guard let number = raw[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
                      (0...128).contains(number.intValue), number.doubleValue == Double(number.intValue) else {
                    throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
                }
            }
            let slice = try PMSlice.fromJSON(raw, schema: bridge.schema)
            fragments.append((try bridge.schema.nodes["doc"]!.create(nil, slice.content), slice.openStart, slice.openEnd))
        }
        var names = Set<String>()
        for fragment in fragments {
            fragment.0.content.nodesBetween(0, fragment.0.content.size, { node, _, _, _ in
                if node.type.name == "relayAnchor", let name = node.attrs["name"] as? String { names.insert(name) }
                return true
            })
        }
        let scope = try makeScope(names)
        let source = try bridge.document(fromSnapshot: scope.tree)
        return try applyDocumentSlices(document: document, range: range, source: source, fragments: fragments,
                                       bridge: bridge, scope: scope)
    }

    private static func applyDocumentSlices(document: RelayMarkNativeDocument, range paperRange: NSRange,
        source: PMNode, fragments: [(PMNode, Int, Int)], bridge: PMYXmlBridge,
        scope: Scope? = nil) throws -> Change {
        let range = scope?.local(paperRange) ?? paperRange
        // Allocate by copied-fragment path, not by supplied donor identity.
        // Normal external HTML has no IDs; repeated supplied IDs are not a
        // destination identity. Only unambiguous explicit evidence can be moved.
        var allocated: [String: [String: String]] = [:]
        var copiedBlocks: [String: [String]] = [:]
        var hostEvidenceIDs = Set<String>()
        func key(_ path: [Int]) -> String { path.map(String.init).joined(separator: ".") }
        func allocate(_ node: PMNode, path: [Int]) {
            var fields: [String: String] = [:]
            if node.type.attrs.contains(where: { $0.name == "relaymarkId" }) {
                let fresh = RelayMarkNativeRichXML.freshID()
                fields["relaymarkId"] = fresh
                if let old = node.attrs["relaymarkId"] as? String, !old.isEmpty {
                    copiedBlocks[old, default: []].append(fresh)
                }
            }
            if node.type.name == "questionBlock" || node.type.name == "questionOption" {
                fields["id"] = UUID().uuidString.lowercased()
            }
            if ["relayEvidence", "relaySourceBundle"].contains(node.type.name),
               let id = node.attrs["id"] as? String { hostEvidenceIDs.insert(id) }
            allocated[key(path)] = fields
            for (index, child) in node.content.children.enumerated() { allocate(child, path: path + [index]) }
        }
        for (index, fragment) in fragments.enumerated() { allocate(fragment.0, path: [index]) }
        func copied(_ node: PMNode, path: [Int]) throws -> PMNode {
            var attrs = node.attrs
            for (name, value) in allocated[key(path)] ?? [:] { attrs[name] = value }
            // Canonical evidence arrays can name copied blocks or stable source
            // entries. Do not touch host Evidence.id, entity/media IDs, selectors
            // or arbitrary settings. An ambiguous supplied block ref refuses.
            if ["agentSuggestion", "relayClaim", "relayComparison", "relayAction"].contains(node.type.name),
               let evidence = attrs["evidence"] as? [String] {
                attrs["evidence"] = try evidence.map { old in
                    guard let destinations = copiedBlocks[old] else { return old }
                    guard destinations.count == 1, !hostEvidenceIDs.contains(old) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                    return destinations[0]
                }
            }
            let children = try node.content.children.enumerated().map { index, child in
                try copied(child, path: path + [index])
            }
            return PMNode(type: node.type, attrs: attrs,
                content: PMFragment(children), marks: node.marks, text: node.text)
        }
        let projection = try scope?.projection ?? document.richProseProjection()
        guard projection.isEditable else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        var from = try position(range.location, projection: projection, doc: source)
        var to = try position(NSMaxRange(range), projection: projection, doc: source)
        var transform = PMTransform(source), items: [[String: Any]] = [], slices: [PMSlice] = []
        for (index, fragment) in fragments.enumerated() {
            let incoming = try copied(fragment.0, path: [index]), maximum = PMSlice.maxOpen(incoming.content)
            guard fragment.1 <= maximum.openStart, fragment.2 <= maximum.openEnd else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            let slice = PMSlice(incoming.content, openStart: fragment.1, openEnd: fragment.2)
            let trace = try PMClipboardFitTrace(slice), stepIndex = transform.steps.count
            try transform.replaceRange(from, to, slice, sourceTrace: trace)
            guard transform.steps.count > stepIndex, let step = transform.steps.last,
                  let end = step.ranges.last.map({ $0.0 + $0.2 }) else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            items.append(["clipboard_slice": slice.json(), "source_trace": try trace.json(), "step_index": stepIndex])
            slices.append(slice)
            // Each subsequent item follows the actual maintained fitter's insertion end,
            // never text search or an inferred block/UTF offset.
            from = end; to = end
        }
        var preferred: [String: Int] = [:], headings = Set<Int>()
        source.content.nodesBetween(0, source.content.size, { node, pos, _, _ in
            let mapped = transform.map(pos)
            if let id = node.attrs["relaymarkId"] as? String,
               transform.doc.nodeAt(mapped)?.attrs["relaymarkId"] as? String == id {
                preferred[id] = mapped
                if node.type.name == "heading" { headings.insert(mapped) }
            }
            return true
        })
        let fitting = try JSONSerialization.data(withJSONObject: items.count == 1 ? items[0]["source_trace"]! : items)
        let (update, updated) = try commit(transform, source: source, bridge: bridge,
            document: document, preferredIDs: preferred, preservedHeadingPositions: headings,
            clipboardSlice: slices.count == 1 ? slices[0] : nil,
            clipboardSourceTrace: items.count == 1 ? items[0]["source_trace"] as? [String: Any] : nil,
            clipboardItems: items.count > 1 ? items : nil, window: scope?.nodes, outside: scope?.outside)
        let end = transform.steps.last?.ranges.last.map { $0.0 + $0.2 }
        let selected = end.flatMap { try? updated.resolve($0) }.flatMap { PMCommands.near($0) }
        let head: Int?
        if case .text(let position)? = selected { head = position } else { head = nil }
        let change = Change(update: update,
            caret: head.flatMap { caret($0, in: updated) }, clipboardFitting: fitting)
        return scope.map { $0.paper(change, updated: updated) } ?? change
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
        try self.key(key, document: document, at: offset, scope: scope(document: document, expectedSnapshot: expectedSnapshot))
    }

    /// The same command reading and writing only the top-level nodes around `offset`.
    public static func key(_ key: Key, document: RelayMarkNativeDocument, at offset: Int,
                           paper: RelayMarkCollaborativeProse) throws -> Change? {
        try self.key(key, document: document, at: offset,
                     scope: scope(document: document, paper: paper, range: NSRange(location: offset, length: 0)))
    }

    private static func key(_ key: Key, document: RelayMarkNativeDocument, at paperOffset: Int, scope: Scope) throws -> Change? {
        let tree = scope.tree, projection = scope.projection
        guard projection.isEditable else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let bridge = try PMYXmlBridge.canonical()
        let doc = try bridge.document(fromSnapshot: tree)
        let head = try position(scope.local(paperOffset), projection: projection, doc: doc)
        let result: PMState
        do {
            let state = PMState(transform: PMTransform(doc), selection: .text(head))
            result = key == .backspace ? try PMCommands.backspace(state) : try PMCommands.delete(state)
        } catch is PMReplaceError {
            return nil
        }
        guard !result.transform.steps.isEmpty else { return nil }
        let (update, updated) = try commit(result.transform, source: doc, bridge: bridge, document: document, window: scope.nodes, outside: scope.outside)
        guard case .text(let pos) = result.selection else { return scope.paper(Change(update: update, caret: nil), updated: updated) }
        return scope.paper(Change(update: update, caret: caret(pos, in: updated)), updated: updated)
    }

    /// Actual maintained AddMark/RemoveMark commands in the same canonical schema.
    /// A no-op selection returns nil without an authored transaction.
    public static func format(document: RelayMarkNativeDocument, range: NSRange,
                              mark: String, attributes: [String: Any] = [:], enabled: Bool,
                              expectedSnapshot: Data) throws -> Change? {
        try format(document: document, range: range, mark: mark, attributes: attributes, enabled: enabled,
                   scope: scope(document: document, expectedSnapshot: expectedSnapshot))
    }

    /// The same command reading and writing only the top-level nodes the range touches.
    public static func format(document: RelayMarkNativeDocument, range: NSRange,
                              mark: String, attributes: [String: Any] = [:], enabled: Bool,
                              paper: RelayMarkCollaborativeProse) throws -> Change? {
        try format(document: document, range: range, mark: mark, attributes: attributes, enabled: enabled,
                   scope: scope(document: document, paper: paper, range: range))
    }

    private static func format(document: RelayMarkNativeDocument, range paperRange: NSRange,
                               mark: String, attributes: [String: Any], enabled: Bool, scope: Scope) throws -> Change? {
        let range = scope.local(paperRange), tree = scope.tree
        guard range.location >= 0, range.length > 0, JSONSerialization.isValidJSONObject(attributes) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let bridge = try PMYXmlBridge.canonical(), doc = try bridge.document(fromSnapshot: tree)
        guard let type = bridge.schema.marks[mark],
              Set(attributes.keys).isSubset(of: Set(type.attrs.map(\.name))) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let projection = scope.projection
        let from = try position(range.location, projection: projection, doc: doc)
        let to = try position(NSMaxRange(range), projection: projection, doc: doc)
        // Portable hard breaks carry no marks. Keep the maintained PM mark
        // commands unchanged, but exclude break positions from this native
        // command's selection, including selections spanning multiple blocks.
        var intervals: [(Int, Int)] = [], start = from
        doc.content.nodesBetween(from, to, { node, position, _, _ in
            guard node.type.name == "hardBreak" else { return true }
            if start < position { intervals.append((start, min(position, to))) }
            start = max(start, position + node.nodeSize)
            return false
        }, parent: doc)
        if start < to { intervals.append((start, to)) }
        var transform = PMTransform(doc)
        for (lower, upper) in intervals {
            if enabled { try transform.addMark(lower, upper, type.create(attributes)) }
            else if attributes.isEmpty { try transform.removeMark(lower, upper, type: type) }
            else { try transform.removeMark(lower, upper, mark: type.create(attributes)) }
        }
        guard !transform.steps.isEmpty else { return nil }
        let (update, updated) = try commit(transform, source: doc, bridge: bridge, document: document, window: scope.nodes, outside: scope.outside)
        return scope.paper(Change(update: update, caret: nil), updated: updated)
    }

    /// Execute the packaged maintained PM command and apply those exact Steps
    /// through this existing native PM/Yrs owner. No native XML planner or diff
    /// manufactures the command evidence.
    static func command(document: RelayMarkNativeDocument, tree: [String: Any],
                        name: String, selection: [String: Any], scope: Scope? = nil) throws -> (change: Change, kind: String, blockID: String?) {
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: tree)
        let response = try RelayMarkContentEditCodec.command(document: JSONSerialization.data(withJSONObject: source.json()),
            request: JSONSerialization.data(withJSONObject: ["command": name, "selection": selection]))
        guard let result = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              let steps = result["steps"] as? [[String: Any]], let expected = result["document"] as? [String: Any],
              let finalSelection = result["selection"] as? [String: Any], let kind = result["kind"] as? String else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        guard let markState=result["stored_marks"],let attributeState=result["stored_text_attributes"],
              (markState is NSNull && attributeState is NSNull) || (markState is [[String:Any]] && attributeState is [String:Any]) else {throw RelayMarkNativeDocument.Failure.unsupportedProseEdit}
        let storedMarks=markState is NSNull ? nil : try JSONSerialization.data(withJSONObject:markState,options:[.sortedKeys])
        let storedAttributes=attributeState is NSNull ? nil : try JSONSerialization.data(withJSONObject:attributeState,options:[.sortedKeys])
        var transform = PMTransform(source)
        for json in steps {
            let step = try PMStep.fromJSON(json, schema: bridge.schema)
            guard pmCompareDeep(step.json(), json) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            try transform.step(step)
        }
        guard pmCompareDeep(transform.doc.json(), expected) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let (update, updated) = try commit(transform, source: source, bridge: bridge, document: document,
            preferredIDs: result["retained_ids"] as? [String: Int] ?? [:], window: scope?.nodes, outside: scope?.outside)
        let caret = (finalSelection["head"] as? Int).flatMap { Self.caret($0, in: updated) }
        let id = caret.flatMap { value -> String? in
            var node = updated
            for index in value.blockPath { guard index < node.childCount else { return nil }; node = node.child(index) }
            return node.attrs["relaymarkId"] as? String
        }
        let change = Change(update: update, caret: caret,storedMarks:storedMarks,storedTextAttributes:storedAttributes)
        return (scope.map { $0.paper(change, updated: updated) } ?? change, kind, id)
    }

    static func positionForPath(_ path: [Int], in source: PMNode) throws -> Int {
        var node = source, position = 0
        for (depth, index) in path.enumerated() {
            guard index >= 0, index < node.childCount else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
            position += node.content.children.prefix(index).reduce(0) { $0 + $1.nodeSize }
            if depth > 0 { position += 1 }
            node = node.child(index)
        }
        return position
    }

    /// Widget host commands supply their actual identified target and insertion
    /// index. The command becomes a maintained Step, never a document diff.
    static func insertWidget(document: RelayMarkNativeDocument, tree: [String: Any],
                             candidate: [String: Any], parentID: String?, index: Int) throws -> Change {
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: tree)
        let candidateBridge = try PMYXmlBridge.canonical()
        let prospective = try candidateBridge.document(fromSnapshot: candidate)
        let parent = try identifiedNode(parentID, in: source)
        let candidateParent = try identifiedNode(parentID, in: prospective)
        guard index >= 0, index <= parent.node.childCount,
              index < candidateParent.node.childCount else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
        let position = parent.position + (parentID == nil ? 0 : 1) + parent.node.content.children.prefix(index).reduce(0) { $0 + $1.nodeSize }
        var transform = PMTransform(source)
        try transform.step(.replace(from: position, to: position, slice: PMSlice(PMFragment.from(candidateParent.node.child(index)), openStart: 0, openEnd: 0)))
        return try change(transform, source: source, bridge: bridge, document: document)
    }

    /// Actual retained children travel as the maintained ReplaceAroundStep gap.
    static func wrapWidgets(document: RelayMarkNativeDocument, tree: [String: Any],
                            candidate: [String: Any], parentID: String?, index: Int,
                            count: Int, wrapperID: String) throws -> Change {
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: tree)
        let prospective = try bridge.document(fromSnapshot: candidate)
        let parent = try identifiedNode(parentID, in: source)
        let destination = try identifiedNode(parentID, in: prospective)
        guard count > 0, index >= 0, index <= parent.node.childCount, count <= parent.node.childCount - index,
              destination.node.childCount == parent.node.childCount - count + 1,
              index < destination.node.childCount else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
        let wrapper = destination.node.child(index)
        let retained = PMFragment.fromArray(Array(parent.node.content.children[index..<(index + count)]))
        guard wrapper.type.name == "relaySourceBundle", wrapper.attrs["relaymarkId"] as? String == wrapperID,
              wrapper.content.eq(retained) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let from = parent.position + (parentID == nil ? 0 : 1)
            + parent.node.content.children.prefix(index).reduce(0) { $0 + $1.nodeSize }
        let to = from + retained.size
        let shell = try wrapper.type.create(wrapper.attrs)
        var transform = PMTransform(source)
        try transform.step(.replaceAround(from: from, to: to, gapFrom: from, gapTo: to,
            slice: PMSlice(PMFragment.from(shell), openStart: 0, openEnd: 0), insert: 1, structure: true))
        guard transform.doc.eq(prospective) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return try change(transform, source: source, bridge: bridge, document: document)
    }

    /// Delete the exact retained node, then decode its insertion through the
    /// canonical serialized Step owner used by maintained mutation replay.
    static func moveWidget(document: RelayMarkNativeDocument, tree: [String: Any],
                           parentID: String?, index: Int, direction: Int) throws -> Change {
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: tree)
        let parent = try identifiedNode(parentID, in: source)
        guard direction == -1 || direction == 1, index >= 0, index < parent.node.childCount,
              index + direction >= 0, index + direction < parent.node.childCount else {
            throw RelayMarkNativeDocument.Failure.invalidTextPath
        }
        let node = parent.node.child(index), neighbor = parent.node.child(index + direction)
        guard node.type.name == neighbor.type.name else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
        let position = parent.position + (parentID == nil ? 0 : 1) + parent.node.content.children.prefix(index).reduce(0) { $0 + $1.nodeSize }
        // Destination after deletion; no detached AST or direct YXml mutation.
        let destination = direction == -1 ? position - neighbor.nodeSize : position + neighbor.nodeSize
        var transform = PMTransform(source)
        try transform.step(.replace(from: position, to: position + node.nodeSize, slice: .empty))
        let insertion = PMStep.replace(from: destination, to: destination,
            slice: PMSlice(PMFragment.from(node), openStart: 0, openEnd: 0))
        try transform.step(PMStep.fromJSON(insertion.json(), schema: bridge.schema))
        return try change(transform, source: source, bridge: bridge, document: document)
    }

    static func removeWidget(document: RelayMarkNativeDocument, tree: [String: Any], id: String) throws -> Change {
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: tree)
        let target = try identifiedNode(id, in: source)
        var transform = PMTransform(source)
        try transform.step(.replace(from: target.position, to: target.position + target.node.nodeSize, slice: .empty))
        return try change(transform, source: source, bridge: bridge, document: document)
    }

    static func updateWidget(document: RelayMarkNativeDocument, tree: [String: Any], id: String,
                             attributes: [String: Any]) throws -> Change {
        return try updateWidgets(document: document, tree: tree, changes: [(id, attributes)])
    }

    /// One maintained transform/commit for guarded changes to multiple identified nodes.
    static func updateWidgets(document: RelayMarkNativeDocument, tree: [String: Any],
                              changes: [(id: String, attributes: [String: Any])]) throws -> Change {
        guard !changes.isEmpty, Set(changes.map(\.id)).count == changes.count,
              changes.reduce(0, { $0 + $1.attributes.count }) <= 512 else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: tree)
        var transform = PMTransform(source)
        for change in changes {
            let target = try identifiedNode(change.id, in: source)
            guard Set(change.attributes.keys).isSubset(of: Set(target.node.type.attrs.map(\.name))) else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            for name in change.attributes.keys.sorted() {
                try transform.step(.attr(pos: target.position, name: name, value: change.attributes[name]!))
            }
        }
        return try self.change(transform, source: source, bridge: bridge, document: document)
    }

    static func setBlockStyle(document: RelayMarkNativeDocument, tree: [String: Any], id: String,
                               style: RelayMarkNativeBlockStyle) throws -> Change {
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: tree)
        let target = try identifiedNode(id, in: source)
        var transform = PMTransform(source)
        var attributes: [String: Any] = ["relaymarkId": id]
        let type: String
        if case .heading(let level) = style {
            guard (1...6).contains(level) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            type = "heading"; attributes["level"] = level
            attributes["headingId"] = target.node.attrs["headingId"] as? String ?? "h-" + UUID().uuidString.lowercased()
        } else { type = "paragraph" }
        guard let nodeType = bridge.schema.nodes[type] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let marked = try nodeType.create(attributes, target.node.content, marks: target.node.marks)
        if !marked.eq(target.node) { try transform.setNodeMarkup(target.position, type: nodeType, attrs: attributes) }
        switch style {
        case .paragraph, .heading: break
        case .quote, .bulletList, .orderedList, .taskList:
            let wrapperType: String
            var wrapperAttrs: [String: Any] = ["relaymarkId": RelayMarkNativeRichXML.freshID()]
            let content: PMFragment, depth: Int
            if style == .quote { wrapperType = "blockquote"; content = .empty; depth = 1 }
            else {
                let task = style == .taskList
                wrapperType = task ? "taskList" : style == .orderedList ? "orderedList" : "bulletList"
                if style == .orderedList { wrapperAttrs["start"] = 1; wrapperAttrs["type"] = NSNull() }
                var itemAttrs: [String: Any] = ["relaymarkId": RelayMarkNativeRichXML.freshID()]
                if task { itemAttrs["checked"] = false }
                guard let itemType = bridge.schema.nodes[task ? "taskItem" : "listItem"] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                content = PMFragment.from(try itemType.create(itemAttrs)); depth = 2
            }
            guard let wrapper = bridge.schema.nodes[wrapperType] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            let node = try wrapper.create(wrapperAttrs, content)
            let from = target.position, to = from + target.node.nodeSize
            try transform.step(.replaceAround(from: from, to: to, gapFrom: from, gapTo: to,
                slice: PMSlice(PMFragment.from(node), openStart: 0, openEnd: 0), insert: depth, structure: true))
        }
        guard !transform.steps.isEmpty else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return try change(transform, source: source, bridge: bridge, document: document)
    }

    /// An explicit root-child replacement command, using the full shared rich
    /// fragment and one maintained ReplaceStep rather than a document diff.
    static func replaceRootChildren(document: RelayMarkNativeDocument, tree: [String: Any],
                                    index: Int, count: Int, replacements: [[String: Any]]) throws -> Change {
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: tree)
        guard var children = tree["children"] as? [[String: Any]], index >= 0, count >= 0,
              index + count <= children.count else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
        children.replaceSubrange(index ..< index + count, with: replacements)
        var candidate = tree; candidate["children"] = children
        _ = try RelayMarkNativeDocumentProjection.project(snapshot: JSONSerialization.data(withJSONObject: candidate))
        let prospective = try PMYXmlBridge.canonical().document(fromSnapshot: candidate)
        let from = source.content.children.prefix(index).reduce(0) { $0 + $1.nodeSize }
        let to = from + source.content.children[index ..< index + count].reduce(0) { $0 + $1.nodeSize }
        let replacement = Array(prospective.content.children[index ..< index + replacements.count])
        var transform = PMTransform(source)
        try transform.step(.replace(from: from, to: to,
            slice: PMSlice(PMFragment.fromArray(replacement), openStart: 0, openEnd: 0)))
        return try change(transform, source: source, bridge: bridge, document: document)
    }

    /// Full authored replacement uses the admitted candidate's schema defaults,
    /// so omitted optional attributes are cleared by actual AttrSteps.
    static func replaceWidgetAttributes(document: RelayMarkNativeDocument, tree: [String: Any],
                                        candidate: [String: Any], id: String) throws -> Change {
        let bridge = try PMYXmlBridge.canonical()
        let prospective = try bridge.document(fromSnapshot: candidate)
        let target = try identifiedNode(id, in: prospective)
        return try updateWidget(document: document, tree: tree, id: id, attributes: target.node.attrs)
    }

    private static func identifiedNode(_ id: String?, in doc: PMNode) throws -> (node: PMNode, position: Int) {
        guard let id else { return (doc, 0) }
        var result: (PMNode, Int)?
        doc.content.nodesBetween(0, doc.content.size, { node, position, _, _ in
            if node.attrs["relaymarkId"] as? String == id { result = (node, position) }
            return true
        })
        guard let result else { throw RelayMarkNativeDocument.Failure.invalidTextPath }
        return result
    }

    private static func change(_ transform: PMTransform, source: PMNode, bridge: PMYXmlBridge,
                               document: RelayMarkNativeDocument) throws -> Change {
        let (update, _) = try commit(transform, source: source, bridge: bridge, document: document)
        return Change(update: update, caret: nil)
    }

    /// Applies identity rules, validates the prospective document on a
    /// scratch replica, then writes it through y-prosemirror's diff.
    private static func commit(_ transform: PMTransform, source: PMNode, bridge: PMYXmlBridge,
                               document: RelayMarkNativeDocument, preferredIDs: [String: Int] = [:],
                               preservedHeadingPositions: Set<Int> = [], clipboardSlice: PMSlice? = nil, clipboardSourceTrace: [String: Any]? = nil, clipboardItems: [[String: Any]]? = nil,
                               window: Range<Int>? = nil, outside: Reserved? = nil) throws -> (Data, PMNode) {
        var witnessed = transform
        let retainedHeadingPositions = preservedHeadingPositions
        var retainedDestinationNames = Set<String>()
        func applyRepairs(_ candidate: PMNode) throws {
            var repairs: [PMStep] = []
            candidate.content.nodesBetween(0, candidate.content.size, { node, pos, _, _ in
                if let original = witnessed.doc.nodeAt(pos) {
                    for name in node.attrs.keys.sorted() where !pmCompareDeep(node.attrs[name]!, original.attrs[name] ?? NSNull()) {
                        repairs.append(.attr(pos: pos, name: name, value: node.attrs[name]!))
                    }
                }
                return true
            })
            for repair in repairs { try witnessed.step(repair) }
            guard witnessed.doc.eq(candidate) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        }
        if clipboardSlice != nil || clipboardItems != nil {
            var identities = Set<String>(), ignoredAnchors = Set<String>()
            try applyRepairs(identified(witnessed.doc, seen: &identities, anchors: &ignoredAnchors,
                preferredIDs: preferredIDs, normalizeHeadings: false,
                reserved: Reserved(identity: { outside?.identity($0) ?? false })))
            var input: [String: Any] = ["before_document": source.json(), "steps": witnessed.steps.map { $0.json() }]
            if let clipboardItems { input["clipboard_items"] = clipboardItems }
            else if let clipboardSlice { input["clipboard_slice"] = clipboardSlice.json(); input["source_trace"] = clipboardSourceTrace ?? NSNull() }
            let result = try RelayMarkContentEditCodec.planClipboardAnchorAllocation(JSONSerialization.data(withJSONObject: input))
            guard let planned = try JSONSerialization.jsonObject(with: result) as? [String: Any],
                  let steps = planned["steps"] as? [[String: Any]],
                  let names = planned["retained_destination_names"] as? [String] else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            retainedDestinationNames = Set(names)
            for step in steps { try witnessed.step(PMStep.fromJSON(step, schema: bridge.schema)) }
            guard pmCompareDeep(witnessed.doc.json(), planned["document"] ?? NSNull()) else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
        }
        var seen = Set<String>(), anchors = retainedDestinationNames
        witnessed.doc.content.nodesBetween(0, witnessed.doc.content.size, { node, _, _, _ in
            if node.type.name == "relayAnchor", let name = node.attrs["name"] as? String { anchors.insert(name) }
            return true
        })
        // As the browser's PaperHeading does, a heading the change left exactly
        // as it was keeps its anchor, even an absent one; only edited or new
        // headings are given one.
        var unchangedHeadings = retainedHeadingPositions, unchangedAnchors = Set<String>()
        source.content.nodesBetween(0, source.content.size, { node, pos, _, _ in
            guard node.type.name == "heading" else { return true }
            let mapped = witnessed.map(pos)
            if let candidate = witnessed.doc.nodeAt(mapped), candidate.eq(node) {
                unchangedHeadings.insert(mapped)
                if let name = node.attrs["headingId"] as? String { unchangedAnchors.insert(name) }
            }
            return false
        })
        // An edited or pasted heading never takes an unchanged heading's anchor,
        // here or elsewhere in the paper, nor an identity used outside the window.
        let reserved = Reserved(identity: { outside?.identity($0) ?? false },
                                anchor: { unchangedAnchors.contains($0) || outside?.anchor($0) == true })
        try applyRepairs(identified(witnessed.doc, seen: &seen, anchors: &anchors, preferredIDs: preferredIDs,
                                    retainedHeadingPositions: unchangedHeadings, reserved: reserved))
        if clipboardSlice != nil || clipboardItems != nil {
            var input: [String: Any] = ["before_document": source.json(), "steps": witnessed.steps.map { $0.json() }]
            if let clipboardItems { input["clipboard_items"] = clipboardItems }
            else if let clipboardSlice { input["clipboard_slice"] = clipboardSlice.json(); input["source_trace"] = clipboardSourceTrace ?? NSNull() }
            let result = try RelayMarkContentEditCodec.planClipboardHeadingNavigation(JSONSerialization.data(withJSONObject: input))
            guard let planned = try JSONSerialization.jsonObject(with: result) as? [String: Any],
                  let steps = planned["steps"] as? [[String: Any]] else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            for step in steps { try witnessed.step(PMStep.fromJSON(step, schema: bridge.schema)) }
            guard pmCompareDeep(witnessed.doc.json(), planned["document"] ?? NSNull()) else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
        }
        let updated=witnessed.doc
        let steps=try JSONSerialization.data(withJSONObject:witnessed.steps.map { $0.json() },options:[.sortedKeys])
        let prepared=try RelayMarkContentEditCodec.prepareWrite(before:JSONSerialization.data(withJSONObject:source.json()),steps:steps,after:JSONSerialization.data(withJSONObject:updated.json()))
        try bridge.prepareWrite(prepared)
        let prospective = try bridge.snapshot(updated)
        let expected = try RelayMarkNativeDocumentProjection.project(
            snapshot: JSONSerialization.data(withJSONObject: prospective, options: [.sortedKeys]))
        // The write is rehearsed on a replica of just the nodes it reads.
        let scratch: RelayMarkNativeDocument
        if let window { scratch = try document.scratch(topLevel: window) }
        else { scratch = RelayMarkNativeDocument(); try scratch.applyUpdate(document.encodeUpdate()) }
        _ = try scratch.applyProseMirror(updated, source: source, bridge: bridge)
        guard try RelayMarkNativeDocumentProjection.project(document: scratch) == expected,
              try scratch.richProseProjection().isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return (try document.applyProseMirror(updated, source: source, bridge: bridge, window: window), updated)
    }

    /// Identities and destination names a commit must not take.
    struct Reserved {
        var identity: (String) -> Bool = { _ in false }
        var anchor: (String) -> Bool = { _ in false }
    }

    /// What a command reads: the whole paper, or a window of top-level nodes
    /// around the edit with one neighbour each side, so joins and emptied
    /// ranges behave as they do in the paper.
    struct Scope {
        let tree: [String: Any]
        let projection: RelayMarkCollaborativeProse
        /// The window's top-level nodes, and the paper offset where its text begins.
        let nodes: Range<Int>?
        let offset: Int
        /// Identities and destination names held by nodes outside the window.
        var outside: Reserved? = nil

        func local(_ value: Int) -> Int { value - offset }
        func local(_ range: NSRange) -> NSRange { NSRange(location: range.location - offset, length: range.length) }
        func local(_ path: [Int]) -> [Int] {
            guard let nodes, let first = path.first else { return path }
            return [first - nodes.lowerBound] + path.dropFirst()
        }
        func paper(_ caret: Caret?) -> Caret? {
            guard let nodes, let caret, let first = caret.blockPath.first else { return caret }
            return Caret(blockPath: [first + nodes.lowerBound] + caret.blockPath.dropFirst(), offset: caret.offset)
        }
        func paper(_ change: Change, updated: PMNode) -> Change {
            guard let nodes else { return change }
            var result = Change(update: change.update, caret: paper(change.caret),
                                authoredMetadataChanged: change.authoredMetadataChanged, storedMarks: change.storedMarks,
                                storedTextAttributes: change.storedTextAttributes, clipboardFitting: change.clipboardFitting)
            result.topLevel = (nodes, nodes.lowerBound..<(nodes.lowerBound + updated.childCount))
            return result
        }
    }

    static func scope(document: RelayMarkNativeDocument, expectedSnapshot: Data) throws -> Scope {
        guard document.integrationStatus().isComplete, try document.snapshot() == expectedSnapshot,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return Scope(tree: tree, projection: try document.richProseProjection(), nodes: nil, offset: 0)
    }

    /// `paper` is the caller's projection of the document as it is now.
    static func scope(document: RelayMarkNativeDocument, paper: RelayMarkCollaborativeProse,
                      range: NSRange) throws -> Scope {
        guard let first = paper.topLevelIndex(atUTF16: range.location),
              let last = paper.topLevelIndex(atUTF16: NSMaxRange(range)) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return try scope(document: document, paper: paper, nodes: min(first, last)...max(first, last))
    }

    static func scope(document: RelayMarkNativeDocument, paper: RelayMarkCollaborativeProse,
                      nodes touched: ClosedRange<Int>) throws -> Scope {
        guard document.integrationStatus().isComplete, paper.isEditable,
              paper.topLevelCount == document.topLevelCount else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let nodes = max(0, touched.lowerBound - 1)..<min(paper.topLevelCount, touched.upperBound + 2)
        let tree = try document.snapshot(topLevel: nodes)
        let data = try JSONSerialization.data(withJSONObject: tree, options: [.sortedKeys])
        _ = try RelayMarkNativeDocumentProjection.project(snapshot: data)
        let projection = try RelayMarkCollaborativeProse(snapshot: data, dialect: .rich, codecValidated: true)
        return Scope(tree: tree, projection: projection, nodes: nodes, offset: paper.topLevelStart(nodes.lowerBound),
                     outside: Reserved(identity: { paper.identityUsed($0, outside: nodes) },
                                       anchor: { paper.anchorUsed($0, outside: nodes) }))
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
    private static func identified(_ node: PMNode, seen: inout Set<String>, anchors: inout Set<String>, preferredIDs: [String: Int] = [:], position: Int = -1, normalizeHeadings: Bool = true, retainedHeadingPositions: Set<Int> = [], reserved: Reserved = Reserved()) -> PMNode {
        var attrs = node.attrs, changed = false
        if normalizeHeadings && node.type.name == "heading" && !retainedHeadingPositions.contains(position) {
            let current = attrs["headingId"]
            if !anchorName(current) || anchors.contains(current as? String ?? "") || reserved.anchor(current as? String ?? "") {
                var id = "h-" + UUID().uuidString.lowercased()
                while anchors.contains(id) || reserved.anchor(id) { id = "h-" + UUID().uuidString.lowercased() }
                attrs["headingId"] = id
                changed = true
            }
            anchors.insert(attrs["headingId"] as? String ?? "")
        }
        if node.type.attrs.contains(where: { $0.name == "relaymarkId" }) {
            if let id = attrs["relaymarkId"] as? String, (preferredIDs[id] == nil || preferredIDs[id] == position), seen.insert(id).inserted,
               !reserved.identity(id) {
                // retained
            } else {
                let id = RelayMarkNativeRichXML.freshID()
                seen.insert(id)
                attrs["relaymarkId"] = id
                changed = true
            }
        }
        var children = node.content.children, childChanged = false
        var childPosition = position + 1
        for (index, child) in children.enumerated() {
            if !child.isText {
                let next = identified(child, seen: &seen, anchors: &anchors, preferredIDs: preferredIDs, position: childPosition, normalizeHeadings: normalizeHeadings, retainedHeadingPositions: retainedHeadingPositions, reserved: reserved)
                if next !== child { children[index] = next; childChanged = true }
            }
            childPosition += child.nodeSize
        }
        guard changed || childChanged else { return node }
        return PMNode(type: node.type, attrs: attrs, content: childChanged ? PMFragment(children) : node.content,
                      marks: node.marks)
    }
}
