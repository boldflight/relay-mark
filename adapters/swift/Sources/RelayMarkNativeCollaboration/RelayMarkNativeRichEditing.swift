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
        /// Exact upstream Snapshot before this command, from the same retained owner.
        public let beforeSnapshot: Data
        /// Actual maintained Step JSON, including identity repair AttrSteps.
        public let steps: Data
        /// ProseMirror's mapped selection head; nil when it leaves textblocks.
        public let caret: Caret?
        /// The same transaction changed authored envelope metadata, witnessed by
        /// maintained DocAttrStep. Complete server correspondence remains required.
        public let authoredMetadataChanged: Bool
        /// Exact maintained command typing context. nil is the actual null
        /// storedMarks state; an empty array/map explicitly clears marks.
        public let storedMarks: Data?
        public let storedTextAttributes: Data?
        /// Call-local exact fitter correspondence/normalizations, never a grant or journal field.
        public let clipboardFitting: Data?
        init(update:Data,beforeSnapshot:Data,steps:Data,caret:Caret?,authoredMetadataChanged:Bool=false,storedMarks:Data?=nil,storedTextAttributes:Data?=nil,clipboardFitting:Data?=nil){
            self.update=update;self.beforeSnapshot=beforeSnapshot;self.steps=steps;self.caret=caret;self.authoredMetadataChanged=authoredMetadataChanged
            self.storedMarks=storedMarks;self.storedTextAttributes=storedTextAttributes;self.clipboardFitting=clipboardFitting
        }
    }

    /// Explicit reviewed whole-document import through this same live writer.
    public static func replaceDocument(document:RelayMarkNativeDocument,authoredAST:Data,expectedSnapshot:Data) throws -> Change {
        guard document.integrationStatus().isComplete,try document.snapshot()==expectedSnapshot,
              let before=try JSONSerialization.jsonObject(with:expectedSnapshot) as? [String:Any],
              let target=try JSONSerialization.jsonObject(with:RelayMarkSourceCodec.documentToSnapshot(authoredAST)) as? [String:Any] else {throw RelayMarkNativeDocument.Failure.unsupportedProseEdit}
        let bridge=try PMYXmlBridge.canonical(),source=try bridge.document(fromSnapshot:before),incoming=try bridge.document(fromSnapshot:target)
        let envelope=target["metadata"] as? [String:Any] ?? [:]
        var transform=PMTransform(source)
        try transform.replace(0,source.content.size,PMSlice(incoming.content,openStart:0,openEnd:0))
        if !pmCompareDeep(source.attrs["relaymark"] ?? [:],envelope){try transform.step(.docAttr(name:"relaymark",value:envelope))}
        let (update,_,beforeSnapshot,steps)=try commit(transform,source:source,bridge:bridge,document:document, reviewedArchive: incoming, reviewedIndices: Array(0..<incoming.childCount))
        let changed = !pmCompareDeep(before["metadata"] ?? [:],envelope)
        return Change(update:update,beforeSnapshot:beforeSnapshot,steps:steps,caret:nil,authoredMetadataChanged:changed)
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
        let (update, updated, beforeSnapshot, steps) = try commit(transform, source: doc, bridge: bridge, document: document)
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
        return Change(update: update, beforeSnapshot: beforeSnapshot, steps: steps, caret: head.flatMap { caret($0, in: updated) })
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
        let (update, updated, beforeSnapshot, steps) = try commit(transform, source: doc, bridge: bridge, document: document)
        let head = transform.map(to, assoc: 1)
        return Change(update: update, beforeSnapshot: beforeSnapshot, steps: steps, caret: caret(head, in: updated))
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
        let (update, updated, beforeSnapshot, steps) = try commit(transform, source: doc, bridge: bridge, document: document)
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
        return Change(update: update, beforeSnapshot: beforeSnapshot, steps: steps, caret: head.flatMap { caret($0, in: updated) })
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
        func depth(_ value: Any?) -> Int? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
                  number.doubleValue >= 0, number.doubleValue <= 128 else { return nil }
            return number.intValue
        }
        guard document.integrationStatus().isComplete, try document.snapshot() == expectedSnapshot,
              range.location >= 0, range.length >= 0,
              let before = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any],
              let result = try JSONSerialization.jsonObject(with: clipboardSlice) as? [String: Any],
              Set(result.keys) == Set(["slice", "normalizations"]), let raw = result["slice"] as? [String: Any],
              Set(raw.keys) == Set(["content", "openStart", "openEnd"]),
              result["normalizations"] is [[String: Any]],
              let start = depth(raw["openStart"]), let end = depth(raw["openEnd"]),
              let content = raw["content"] as? [[String: Any]], !content.isEmpty, content.count <= 4096 else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: before)
        let fragment = try PMSlice.fromJSON(raw, schema: bridge.schema)
        // A call-local root is only a path inventory wrapper, not a DocumentAST.
        let imported = try bridge.schema.nodes["doc"]!.create(nil, fragment.content)
        return try applyDocumentSlice(document: document, range: range, source: source, imported: imported,
            openStart: start, openEnd: end, bridge: bridge)
    }

    private static func applyDocumentSlice(document: RelayMarkNativeDocument, range: NSRange,
        source: PMNode, imported: PMNode, openStart: Int, openEnd: Int, bridge: PMYXmlBridge) throws -> Change {
        try applyDocumentSlices(document: document, range: range, source: source,
            fragments: [(imported, openStart, openEnd)], bridge: bridge)
    }

    public static func insertDocumentSlice(document: RelayMarkNativeDocument, range: NSRange,
        clipboardSlices: [Data], expectedSnapshot: Data) throws -> Change {
        guard (1...4096).contains(clipboardSlices.count), document.integrationStatus().isComplete,
              try document.snapshot() == expectedSnapshot, range.location >= 0, range.length >= 0,
              let before = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: before)
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
        return try applyDocumentSlices(document: document, range: range, source: source, fragments: fragments, bridge: bridge)
    }

    private static func applyDocumentSlices(document: RelayMarkNativeDocument, range: NSRange,
        source: PMNode, fragments: [(PMNode, Int, Int)], bridge: PMYXmlBridge) throws -> Change {
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
        let projection = try document.richProseProjection()
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
        let (update, updated, beforeSnapshot, steps) = try commit(transform, source: source, bridge: bridge,
            document: document, preferredIDs: preferred, preservedHeadingPositions: headings,
            clipboardSlice: slices.count == 1 ? slices[0] : nil,
            clipboardSourceTrace: items.count == 1 ? items[0]["source_trace"] as? [String: Any] : nil,
            clipboardItems: items.count > 1 ? items : nil)
        let end = transform.steps.last?.ranges.last.map { $0.0 + $0.2 }
        let selected = end.flatMap { try? updated.resolve($0) }.flatMap { PMCommands.near($0) }
        let head: Int?
        if case .text(let position)? = selected { head = position } else { head = nil }
        return Change(update: update, beforeSnapshot: beforeSnapshot, steps: steps,
            caret: head.flatMap { caret($0, in: updated) }, clipboardFitting: fitting)
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
        let (update, updated, beforeSnapshot, steps) = try commit(result.transform, source: doc, bridge: bridge, document: document)
        guard case .text(let pos) = result.selection else { return Change(update: update, beforeSnapshot: beforeSnapshot, steps: steps, caret: nil) }
        return Change(update: update, beforeSnapshot: beforeSnapshot, steps: steps, caret: caret(pos, in: updated))
    }

    /// Actual maintained AddMark/RemoveMark commands in the same canonical schema.
    /// A no-op selection returns nil without an authored transaction.
    public static func format(document: RelayMarkNativeDocument, range: NSRange,
                              mark: String, attributes: [String: Any] = [:], enabled: Bool,
                              expectedSnapshot: Data) throws -> Change? {
        guard document.integrationStatus().isComplete, try document.snapshot() == expectedSnapshot,
              range.location >= 0, range.length > 0,
              JSONSerialization.isValidJSONObject(attributes),
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let bridge = try PMYXmlBridge.canonical(), doc = try bridge.document(fromSnapshot: tree)
        guard let type = bridge.schema.marks[mark],
              Set(attributes.keys).isSubset(of: Set(type.attrs.map(\.name))) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let projection = try document.richProseProjection()
        let from = try position(range.location, projection: projection, doc: doc)
        let to = try position(NSMaxRange(range), projection: projection, doc: doc)
        var transform = PMTransform(doc)
        if enabled { try transform.addMark(from, to, type.create(attributes)) }
        else if attributes.isEmpty { try transform.removeMark(from, to, type: type) }
        else { try transform.removeMark(from, to, mark: type.create(attributes)) }
        guard !transform.steps.isEmpty else { return nil }
        return try change(transform, source: doc, bridge: bridge, document: document)
    }

    /// Execute the packaged maintained PM command and apply those exact Steps
    /// through this existing native PM/Yrs owner. No native XML planner or diff
    /// manufactures the command evidence.
    static func command(document: RelayMarkNativeDocument, tree: [String: Any],
                        name: String, selection: [String: Any]) throws -> (change: Change, kind: String, blockID: String?) {
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
        let (update, updated, beforeSnapshot, witnessedSteps) = try commit(transform, source: source, bridge: bridge, document: document, preferredIDs: result["retained_ids"] as? [String: Int] ?? [:])
        let caret = (finalSelection["head"] as? Int).flatMap { Self.caret($0, in: updated) }
        let id = caret.flatMap { value -> String? in
            var node = updated
            for index in value.blockPath { guard index < node.childCount else { return nil }; node = node.child(index) }
            return node.attrs["relaymarkId"] as? String
        }
        return (Change(update: update, beforeSnapshot: beforeSnapshot, steps: witnessedSteps, caret: caret,storedMarks:storedMarks,storedTextAttributes:storedAttributes), kind, id)
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
                                    index: Int, count: Int, replacements: [[String: Any]],
                                    reviewedArchive: PMNode? = nil, reviewedIndices: [Int]? = nil) throws -> Change {
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
        return try change(transform, source: source, bridge: bridge, document: document, reviewedArchive: reviewedArchive, reviewedIndices: reviewedIndices)
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
                               document: RelayMarkNativeDocument, reviewedArchive: PMNode? = nil, reviewedIndices: [Int]? = nil) throws -> Change {
        let (update, _, beforeSnapshot, steps) = try commit(transform, source: source, bridge: bridge, document: document, reviewedArchive: reviewedArchive, reviewedIndices: reviewedIndices)
        return Change(update: update, beforeSnapshot: beforeSnapshot, steps: steps, caret: nil)
    }

    /// Applies identity rules, validates the prospective document on a
    /// scratch replica, then writes it through y-prosemirror's diff.
    private static func commit(_ transform: PMTransform, source: PMNode, bridge: PMYXmlBridge,
                               document: RelayMarkNativeDocument, preferredIDs: [String: Int] = [:],
                               reviewedArchive: PMNode? = nil, reviewedIndices: [Int]? = nil,
                               preservedHeadingPositions: Set<Int> = [], clipboardSlice: PMSlice? = nil, clipboardSourceTrace: [String: Any]? = nil, clipboardItems: [[String: Any]]? = nil) throws -> (Data, PMNode, Data, Data) {
        var witnessed = transform
        var retainedHeadingPositions = preservedHeadingPositions, retainedDestinationNames = Set<String>()
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
        if let reviewedArchive, let reviewedIndices {
            // Allocate structural identity before deriving imported Anchor names.
            // This keeps an imported Anchor from renaming a retained heading.
            var identities = Set<String>(), ignoredAnchors = Set<String>()
            try applyRepairs(identified(witnessed.doc, seen: &identities, anchors: &ignoredAnchors,
                preferredIDs: preferredIDs, normalizeHeadings: false))
            let input: [String: Any] = ["archive_document": reviewedArchive.json(), "before_document": source.json(),
                "block_indices": reviewedIndices, "steps": witnessed.steps.map { $0.json() }]
            let result = try RelayMarkContentEditCodec.planReviewedAnchorAllocation(JSONSerialization.data(withJSONObject: input))
            guard let planned = try JSONSerialization.jsonObject(with: result) as? [String: Any],
                  let steps = planned["steps"] as? [[String: Any]],
                  let names = planned["retained_destination_names"] as? [String] else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            retainedDestinationNames = Set(names)
            if let first = witnessed.steps.first?.json(), first["from"] as? Int == source.content.size, first["to"] as? Int == source.content.size {
                source.content.nodesBetween(0, source.content.size, { node, pos, _, _ in
                    if node.type.name == "heading" { retainedHeadingPositions.insert(pos) }
                    return true
                })
            }
            for step in steps { try witnessed.step(PMStep.fromJSON(step, schema: bridge.schema)) }
            guard pmCompareDeep(witnessed.doc.json(), planned["document"] ?? NSNull()) else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
        }
        if clipboardSlice != nil || clipboardItems != nil {
            var identities = Set<String>(), ignoredAnchors = Set<String>()
            try applyRepairs(identified(witnessed.doc, seen: &identities, anchors: &ignoredAnchors,
                preferredIDs: preferredIDs, normalizeHeadings: false))
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
        try applyRepairs(identified(witnessed.doc, seen: &seen, anchors: &anchors, preferredIDs: preferredIDs, retainedHeadingPositions: retainedHeadingPositions))
        if let reviewedArchive, let reviewedIndices {
            let input: [String: Any] = ["archive_document": reviewedArchive.json(), "before_document": source.json(),
                "block_indices": reviewedIndices, "steps": witnessed.steps.map { $0.json() }]
            let result = try RelayMarkContentEditCodec.planReviewedHeadingNavigation(JSONSerialization.data(withJSONObject: input))
            guard let planned = try JSONSerialization.jsonObject(with: result) as? [String: Any],
                  let navigationSteps = planned["steps"] as? [[String: Any]] else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            for step in navigationSteps { try witnessed.step(PMStep.fromJSON(step, schema: bridge.schema)) }
            guard pmCompareDeep(witnessed.doc.json(), planned["document"] ?? NSNull()) else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
        }
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
        let beforeSnapshot=try document.captureSenderSnapshot()
        let steps=try JSONSerialization.data(withJSONObject:witnessed.steps.map { $0.json() },options:[.sortedKeys])
        let prepared=try RelayMarkContentEditCodec.prepareWrite(before:JSONSerialization.data(withJSONObject:source.json()),steps:steps,after:JSONSerialization.data(withJSONObject:updated.json()))
        try bridge.prepareWrite(prepared)
        let prospective = try bridge.snapshot(updated)
        let expected = try RelayMarkNativeDocumentProjection.project(
            snapshot: JSONSerialization.data(withJSONObject: prospective, options: [.sortedKeys]))
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        _ = try scratch.applyProseMirror(updated, source: source, bridge: bridge)
        guard try RelayMarkNativeDocumentProjection.project(document: scratch) == expected,
              try scratch.richProseProjection().isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return (try document.applyProseMirror(updated, source: source, bridge: bridge), updated, beforeSnapshot, steps)
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
    private static func identified(_ node: PMNode, seen: inout Set<String>, anchors: inout Set<String>, preferredIDs: [String: Int] = [:], position: Int = -1, normalizeHeadings: Bool = true, retainedHeadingPositions: Set<Int> = []) -> PMNode {
        var attrs = node.attrs, changed = false
        if normalizeHeadings && node.type.name == "heading" && !retainedHeadingPositions.contains(position) {
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
            if let id = attrs["relaymarkId"] as? String, (preferredIDs[id] == nil || preferredIDs[id] == position), seen.insert(id).inserted {
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
                let next = identified(child, seen: &seen, anchors: &anchors, preferredIDs: preferredIDs, position: childPosition, normalizeHeadings: normalizeHeadings, retainedHeadingPositions: retainedHeadingPositions)
                if next !== child { children[index] = next; childChanged = true }
            }
            childPosition += child.nodeSize
        }
        guard changed || childChanged else { return node }
        return PMNode(type: node.type, attrs: attrs, content: childChanged ? PMFragment(children) : node.content,
                      marks: node.marks)
    }
}
