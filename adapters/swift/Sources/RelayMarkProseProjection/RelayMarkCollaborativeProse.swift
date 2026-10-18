import Foundation
import CoreFoundation
import RelayMarkSwift

/// Deliberately bounded editable projection; unsupported structure is preserved by the replica.
public struct RelayMarkCollaborativeProse {
    public enum Dialect: Sendable {
        case legacy
        case rich
    }

    public private(set) var text: AttributedString
    public var isEditable: Bool { rootSupported && unsupportedChunks == 0 && rangeCount > 0 }
    public var blockRanges: [NSRange] { gather(\.ranges) { range, start, _ in NSRange(location: range.location + start, length: range.length) } }

    /// Native presentation metadata for table paragraphs. XML remains the
    /// source of truth; these ranges share the same UTF-16 text map as edits.
    public struct TableCell: Equatable, Sendable {
        public let tableIdentity: Int
        public internal(set) var range: NSRange
        public let columns: Int
        public let row: Int
        public let column: Int
        public let rowSpan: Int
        public let columnSpan: Int
        public let header: Bool
        /// TipTap's per-spanned-column widths, when explicitly authored.
        public let columnWidths: [Int]?
        /// Explicit cell alignment; nil retains the native paragraph default.
        public let alignment: String?
    }
    public var tableCells: [TableCell] { gather(\.cells) { _ = $2; var item = $0; item.range.location += $1; return item } }

    /// Stable callout identity and presentation ranges. The Yrs XML remains
    /// authoritative; these ranges only style editable native text leaves.
    public struct Callout: Equatable, Sendable {
        public let id: String
        public internal(set) var range: NSRange
        public internal(set) var titleRange: NSRange?
        public let tone: String
        public let emphasis: String
    }
    public var callouts: [Callout] { gather(\.callouts) { _ = $2; var item = $0; item.range.location += $1; item.titleRange?.location += $1; return item } }

    /// Identified inline XML nodes occupy one non-text UTF-16 unit in `text`.
    /// Authored identity and source remain on the XML node; the range is only a
    /// native selection/presentation coordinate.
    public struct InlineAtom: Equatable, Sendable {
        public enum Kind: String, Sendable {
            case relayReference
            case relayTag
        }
        public let kind: Kind
        public let id: String
        public let label: String
        public let source: String
        public internal(set) var range: NSRange
        public internal(set) var path: [Int]
    }
    public var inlineAtoms: [InlineAtom] { gather(\.inlineAtoms) { var item = $0; item.range.location += $1; item.path = Self.global(item.path, $2); return item } }

    /// Inert canonical Paper controls projected as one UTF-16 block unit.
    public struct BlockAtom: Equatable, Sendable {
        public typealias Control = RelayMarkPaperControlContract.Control
        public let id: String
        public let control: Control
        public let source: String
        public let displayLabel: String
        public internal(set) var range: NSRange
        public internal(set) var path: [Int]
    }
    public var blockAtoms: [BlockAtom] { gather(\.blockAtoms) { var item = $0; item.range.location += $1; item.path = Self.global(item.path, $2); return item } }

    /// A block reference occupies one selection unit. The host resolves its
    /// authorized target; authored identity and fallback remain in XML.
    public struct EntityReferenceAtom: Equatable, Sendable {
        public let id: String
        public let entityID: String
        public let label: String
        public let source: String
        public internal(set) var range: NSRange
        public internal(set) var path: [Int]
    }
    public var entityReferenceAtoms: [EntityReferenceAtom] { gather(\.entityReferenceAtoms) { var item = $0; item.range.location += $1; item.path = Self.global(item.path, $2); return item } }

    /// A task's authored checkbox and optional linked entity are metadata on
    /// its XML item, not characters inserted into the editable text map.
    public struct TaskItem: Equatable, Sendable {
        public let id: String
        public let checked: Bool
        public let entityID: String?
        public var firstParagraphRange: NSRange
        /// Exact first-paragraph XML text; inline atom presentation and hard
        /// breaks contribute no characters, matching domain task commands.
        public internal(set) var firstParagraphText: String
        public internal(set) var path: [Int]
    }
    public var taskItems: [TaskItem] { gather(\.taskItems) { var item = $0; item.firstParagraphRange.location += $1; item.path = Self.global(item.path, $2); return item } }

    /// Media occupies one block selection unit. The host resolves and renders
    /// the source; this projection never fetches media or changes the XML.
    public struct MediaAtom: Equatable, Sendable {
        public enum Kind: String, Sendable {
            case image
            case videoEmbed
        }
        public let kind: Kind
        public let id: String
        public let source: String
        public let alt: String?
        public let title: String?
        public let width: Int?
        public let height: Int?
        public internal(set) var range: NSRange
        public internal(set) var path: [Int]
    }
    public var mediaAtoms: [MediaAtom] { gather(\.mediaAtoms) { var item = $0; item.range.location += $1; item.path = Self.global(item.path, $2); return item } }

    /// Authored canonical suggestion as one inert block unit; review actions remain host-owned.
    public struct SuggestionAtom: Equatable, Sendable {
        public let id: String
        public let review: String
        public let kind: String
        public let confidence: Double?
        public let evidence: [String]
        public let content: String
        public internal(set) var range: NSRange
        public internal(set) var path: [Int]
    }
    public var suggestionAtoms: [SuggestionAtom] { gather(\.suggestionAtoms) { var item = $0; item.range.location += $1; item.path = Self.global(item.path, $2); return item } }

    /// Shared authored widgets retain XML identity and editable child ranges.
    /// The host supplies domain actions/rendering; this metadata contains no answers or permissions.
    public struct AuthoredWidget: Equatable, Sendable {
        public enum Kind: String, Sendable { case question,option,dataView,directive }
        public let kind: Kind
        public let id: String
        public let nodeName: String
        public let attributes: Data
        public internal(set) var range: NSRange
        public internal(set) var path: [Int]
    }
    public var authoredWidgets: [AuthoredWidget] { gather(\.authoredWidgets) { var item = $0; item.range.location += $1; item.path = Self.global(item.path, $2); return item } }

    /// Block metadata remains available when an empty paragraph has no text run.
    public var blockIntents: [PresentationIntent] { gather(\.intents) { intent, _, _ in intent } }
    public var blockPaths: [[Int]] { gather(\.paths) { path, _, index in Self.global(path, index) } }
    public struct TextRange: Equatable, Sendable {
        public let path: [Int]
        public let index: Int
        public let length: Int
    }
    private struct Span {
        var range: NSRange
        let path: [Int]
        let text: Bool
        let afterPath: [Int]
        var afterIndex: Int
        let atom: Bool
    }

    /// One top-level XML node's projection. Offsets count from the node's
    /// first character and paths are those the node would have alone in a
    /// paper (`[0, ...]`, the paper itself `[]`), so re-projecting a node
    /// never touches the others.
    private struct Chunk {
        var name = ""
        var length = 0
        var supported = true
        var ranges: [NSRange] = []
        var paths: [[Int]] = []
        var intents: [PresentationIntent] = []
        var cells: [TableCell] = []
        var callouts: [Callout] = []
        var inlineAtoms: [InlineAtom] = []
        var blockAtoms: [BlockAtom] = []
        var entityReferenceAtoms: [EntityReferenceAtom] = []
        var taskItems: [TaskItem] = []
        var mediaAtoms: [MediaAtom] = []
        var suggestionAtoms: [SuggestionAtom] = []
        var authoredWidgets: [AuthoredWidget] = []
        var spans: [Span] = []
        var boundaries: [[Int]: [Int]] = [:]
    }
    private var chunks: [Chunk]
    /// Where each chunk's text begins in `text`. Chunks with text are joined by one separator.
    private var starts: NodeStarts
    /// A restricted projection's starts, fixed in the paper's offsets.
    private var restrictedStarts: [Int]?
    private var rootSupported: Bool
    private var unsupportedChunks: Int
    private var rangeCount: Int
    /// Presentation identities below this are in use; a re-projected node starts here.
    public private(set) var identityLimit: Int

    private static func global(_ path: [Int], _ chunk: Int) -> [Int] {
        path.isEmpty ? path : [chunk] + path.dropFirst()
    }

    private static func local(_ path: [Int]) -> (chunk: Int, path: [Int])? {
        guard let first = path.first else { return nil }
        return (first, [0] + path.dropFirst())
    }

    private func gather<T>(_ items: KeyPath<Chunk, [T]>, _ place: (T, Int, Int) -> T) -> [T] {
        var result: [T] = []
        for (index, chunk) in chunks.enumerated() {
            let start = restrictedStarts?[index] ?? starts[index]
            for item in chunk[keyPath: items] { result.append(place(item, start, index + firstNode)) }
        }
        return result
    }

    /// The paper's index of this projection's first top-level node; nonzero only when restricted.
    private var firstNode = 0

    /// The metadata of just the top-level nodes in `range`, in the paper's
    /// offsets and paths, at a cost that follows those nodes. Only the
    /// metadata collections and block lists are meaningful on the result.
    public func restricted(toTopLevel range: Range<Int>) -> RelayMarkCollaborativeProse {
        var copy = self
        copy.chunks = Array(chunks[range]); copy.restrictedStarts = range.map { starts[$0] }
        copy.firstNode = firstNode + range.lowerBound
        return copy
    }

    private static let markupNames: Set<String> = ["horizontalRule", "relayButton", "relayAnchor", "relayConnection",
                                                   "relayEntityReference", "agentSuggestion", "image", "videoEmbed"]

    nonisolated(unsafe) private static var cachedDirectiveDefinitions: [[String: Any]]?
    private static func directiveDefinitions() throws -> [[String: Any]] {
        if let cachedDirectiveDefinitions { return cachedDirectiveDefinitions }
        let value = try JSONSerialization.jsonObject(with: RelayMarkSourceCodec.directiveDefinitions()) as? [[String: Any]] ?? []
        cachedDirectiveDefinitions = value
        return value
    }

    /// The same portable mark presentation used by document text leaves.
    /// Hosts use actual maintained stored attributes for an empty typing caret.
    public static func attributedText(text: String, attributes: Data) throws -> AttributedString {
        guard let values=try JSONSerialization.jsonObject(with:attributes) as? [String:Any] else {throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument}
        try RelayMarkSourceCodec.validateTextAttributes(values)
        return try projectedText(text:text,attributes:values,dialect:.rich,codeBlock:false)
    }

    private static func projectedText(text insert:String,attributes:[String:Any],dialect:Dialect,codeBlock:Bool) throws -> AttributedString {
        let offered = Set(RelayMarkOfferedMark.allCases.map(\.rawValue))
        let allowed = Set(["bold", "italic", "strike", "code", "link"])
            .union(dialect == .rich ? offered : [])
        if !Set(attributes.keys).isSubset(of: allowed) { throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument }
        if codeBlock && !attributes.isEmpty { throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument }
        if attributes["code"] != nil && (attributes.count > 1 || insert.contains("\r") || insert.contains("\n")) { throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument }
        for key in ["bold", "italic", "strike", "code"] where attributes[key] != nil {
            if !(attributes[key] is [String: Any]) { throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument }
        }
        var offeredMarks = Set<RelayMarkOfferedMark>()
        if dialect == .rich {
            for mark in RelayMarkOfferedMark.allCases where attributes[mark.rawValue] != nil {
                if (attributes[mark.rawValue] as? [String: Any])?.isEmpty == true {
                    offeredMarks.insert(mark)
                } else { throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument }
            }
        }
        var part = AttributedString(insert)
        var intent: InlinePresentationIntent = []
        if attributes["bold"] != nil { intent.insert(.stronglyEmphasized) }
        if attributes["italic"] != nil { intent.insert(.emphasized) }
        if attributes["strike"] != nil { intent.insert(.strikethrough) }
        if attributes["code"] != nil { intent.insert(.code) }
        part.inlinePresentationIntent = intent
        if !offeredMarks.isEmpty { part[RelayMarkOfferedMarksAttribute.self] = offeredMarks }
        if let mark = attributes["link"] {
            if let link = mark as? [String: Any], let href = link["href"] as? String,
                Set(link.keys).isSubset(of: dialect == .rich
                    ? ["href", "target", "rel", "class", "title"] : ["href", "target", "rel", "class"]),
                !href.contains("\n"), !href.contains("<"), !href.contains(">"), let url = URL(string: href) {
                part.link = url
            } else { throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument }
        }
        return part
    }


    public init(snapshot: Data, dialect: Dialect = .legacy) throws {
        try self.init(snapshot: snapshot, dialect: dialect, codecValidated: false)
    }

    /// `codecValidated` means the caller already ran this exact snapshot through
    /// the codec, so the rich dialect does not convert it a second time.
    /// `identityBase` numbers presentation identities from there, for nodes
    /// that will replace others in an existing projection.
    public init(snapshot: Data, dialect: Dialect, codecValidated: Bool, identityBase: Int = 0) throws {
        let root = try JSONSerialization.jsonObject(with: snapshot) as? [String: Any]
        if dialect == .rich, !codecValidated { _ = try RelayMarkSourceCodec.snapshotToDocument(snapshot) }
        var value = AttributedString(), length = 0, identity = identityBase
        chunks = []; unsupportedChunks = 0; rangeCount = 0
        var widths: [Int] = [], separated: [Bool] = []
        for node in root?["children"] as? [[String: Any]] ?? [] {
            let (chunk, part, next) = try Self.project(node, dialect: dialect, identityStart: identity)
            identity = next
            let separator = !chunk.ranges.isEmpty && rangeCount > 0
            if separator { value.append(AttributedString("\n")); length += 1 }
            rangeCount += chunk.ranges.count
            widths.append(chunk.length + (separator ? 1 : 0)); separated.append(separator)
            value.append(part); length += chunk.length
            if !chunk.supported { unsupportedChunks += 1 }
            chunks.append(chunk)
        }
        text = value
        starts = NodeStarts(widths: widths, separated: separated)
        restrictedStarts = nil
        rootSupported = root?["kind"] as? String == "fragment"
        identityLimit = identity
    }

    private static func project(_ node: [String: Any], dialect: Dialect,
                                identityStart: Int) throws -> (Chunk, AttributedString, Int) {
        let directiveDefinitions = try Self.directiveDefinitions()
        let genericNames = Set(directiveDefinitions.compactMap { $0["name"] as? String })
        var authoredWidgets: [AuthoredWidget] = []
        var value = AttributedString()
        var ranges: [NSRange] = [], paths: [[Int]] = []
        var intents: [PresentationIntent] = []
        var cells: [TableCell] = []
        var calloutRanges: [Callout] = []
        var atoms: [InlineAtom] = []
        var blockAtoms: [BlockAtom] = []
        var entityReferenceAtoms: [EntityReferenceAtom] = []
        var taskItems: [TaskItem] = []
        var mediaAtoms: [MediaAtom] = []
        var suggestionAtoms: [SuggestionAtom] = []
        var mapped: [Span] = []
        var boundaries: [[Int]: [Int]] = [:]
        var supported = true
        var identity = identityStart
        func widget(kind:AuthoredWidget.Kind,id:String,name:String,attributes:[String:Any],range:NSRange,path:[Int]) {
            guard let data=try? JSONSerialization.data(withJSONObject:attributes,options:[.sortedKeys]) else { supported=false;return }
            authoredWidgets.append(AuthoredWidget(kind:kind,id:id,nodeName:name,attributes:data,range:range,path:path))
        }
        func length() -> Int { value.utf16.count }
        func validInteger(_ value: Any?, minimum: Int, maximum: Int = Int.max) -> Bool {
            guard let value, !(value is NSNull) else { return true }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let integer = value as? Int else { return false }
            return integer >= minimum && integer <= maximum
        }
        func xmlText(_ node: [String: Any]) -> String {
            if node["kind"] as? String == "text" {
                guard let delta = node["delta"] as? [[String: Any]] else { supported = false; return "" }
                return delta.map { run in
                    guard let insert = run["insert"] as? String else { supported = false; return "" }
                    return insert
                }.joined()
            }
            return (node["children"] as? [[String: Any]] ?? []).map(xmlText).joined()
        }
        func appendText(_ leaf: [String: Any], path: [Int], codeBlock: Bool) {
            let start = length()
            guard let delta = leaf["delta"] as? [[String: Any]] else { supported = false; return }
            for run in delta {
                guard let insert = run["insert"] as? String else { supported = false; continue }
                let attributes = run["attributes"] as? [String: Any] ?? [:]
                do {value.append(try Self.projectedText(text:insert,attributes:attributes,dialect:dialect,codeBlock:codeBlock))}
                catch {supported=false;value.append(AttributedString(insert))}
            }
            mapped.append(Span(range: NSRange(location: start, length: length() - start), path: path,
                text: true, afterPath: path, afterIndex: length() - start, atom: false))
        }
        func inlineAtom(_ leaf: [String: Any], path: [Int]) -> InlineAtom? {
            guard dialect == .rich, leaf["kind"] as? String == "element",
                  let name = leaf["name"] as? String,
                  let kind = InlineAtom.Kind(rawValue: name),
                  let attributes = leaf["attributes"] as? [String: Any],
                  let children = leaf["children"] as? [Any], children.isEmpty else { return nil }
            let uuidPattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
            func validUUID(_ id: String) -> Bool { id.range(of: uuidPattern, options: .regularExpression) != nil }
            if kind == .relayReference {
                guard Set(attributes.keys).isSubset(of: ["entityType", "entityId", "label", "source", "status", "subtitle"]),
                      let type = attributes["entityType"] as? String,
                      type.range(of: "^[A-Z][A-Za-z0-9]*(?: [A-Z][A-Za-z0-9]*)*$", options: .regularExpression) != nil,
                      type != "Tag", let id = attributes["entityId"] as? String, validUUID(id),
                      let label = attributes["label"] as? String, !label.isEmpty,
                      let source = attributes["source"] as? String,
                      source == (try? RelayMarkSourceCodec.buildEntityReferenceSource(entityType:type,entityID:id,label:label)),
                      (attributes["status"] == nil || attributes["status"] is NSNull),
                      (attributes["subtitle"] == nil || attributes["subtitle"] is NSNull) else { return nil }
                return InlineAtom(kind: kind, id: id, label: label, source: source,
                                  range: NSRange(location: length(), length: 1), path: path)
            }
            guard Set(attributes.keys).isSubset(of: ["id", "name", "color", "source"]),
                  let id = attributes["id"] as? String, validUUID(id),
                  let name = attributes["name"] as? String,
                  name.range(of: "^[a-z0-9][a-z0-9_-]*$", options: .regularExpression) != nil,
                  let source = attributes["source"] as? String,
                  source == "[[Tag: \(id) | #\(name)]]",
                  (attributes["color"] == nil || attributes["color"] is NSNull) else { return nil }
            return InlineAtom(kind: kind, id: id, label: "#\(name)", source: source,
                              range: NSRange(location: length(), length: 1), path: path)
        }
        func tableLayout(_ rows: [[String: Any]]) -> (width: Int, starts: [[Int]]) {
            var occupied = Array(repeating: Set<Int>(), count: rows.count)
            var starts = [[Int]]()
            var expectedWidth: Int?
            for (rowIndex, row) in rows.enumerated() {
                guard row["name"] as? String == "tableRow",
                      let cells = row["children"] as? [[String: Any]], !cells.isEmpty else {
                    supported = false; return (0, [])
                }
                var columns = [Int](), column = 0
                for cell in cells {
                    while occupied[rowIndex].contains(column) { column += 1 }
                    let attrs = cell["attributes"] as? [String: Any] ?? [:]
                    let colspan = attrs["colspan"] as? Int ?? 1
                    let rowspan = attrs["rowspan"] as? Int ?? 1
                    guard colspan > 0, rowspan > 0, column <= 256 - colspan,
                          rowIndex <= rows.count - rowspan else {
                        supported = false; return (0, [])
                    }
                    columns.append(column)
                    for row in rowIndex..<(rowIndex + rowspan) {
                        for slot in column..<(column + colspan) {
                            if !occupied[row].insert(slot).inserted { supported = false }
                        }
                    }
                    column += colspan
                }
                let width = (occupied[rowIndex].max() ?? -1) + 1
                if expectedWidth != nil && expectedWidth != width { supported = false }
                if (0..<width).contains(where: { !occupied[rowIndex].contains($0) }) { supported = false }
                expectedWidth = width
                starts.append(columns)
            }
            return (expectedWidth ?? 0, starts)
        }
        struct CellContext {
            let tableIdentity: Int
            let columns: Int
            let row: Int
            let column: Int
            let rowSpan: Int
            let columnSpan: Int
            let header: Bool
            let columnWidths: [Int]?
            let alignment: String?
        }
        func walk(_ nodes: [[String: Any]], path: [Int], parent: PresentationIntent? = nil,
                  ordinal: Int = 1, tableRows: [[Int]]? = nil, tableColumns: [Int]? = nil,
                  tableIdentity: Int? = nil, tableWidth: Int? = nil, tableRow: Int? = nil,
                  cellContext: CellContext? = nil, allowCalloutTitle: Bool = false) throws {
            var offsets: [Int] = []
            for (index, block) in nodes.enumerated() {
                let blockPath = path + [index]
                let name = block["name"] as? String ?? ""
                let physicalAttributes = block["attributes"] as? [String: Any] ?? [:]
                let attributes: [String: Any]
                if dialect == .rich {
                    // Rich admission above already validates the complete physical
                    // snapshot. Presentation and offered widget reviews use the
                    // same logical attrs as PM, without changing retained XML.
                    attributes = try RelayMarkContentEditCodec.decodeDocumentAttributes(
                        nodeName: name, attributes: physicalAttributes)
                } else { attributes = physicalAttributes }
                let children = block["children"] as? [[String: Any]] ?? []
                if block["kind"] as? String != "element" { supported = false }
                identity += 1
                if dialect == .rich && (name=="questionBlock" || (genericNames.contains(name) && !children.isEmpty)) {
                    let firstRange=ranges.count
                    try walk(children,path:blockPath,parent:parent,cellContext:cellContext)
                    guard ranges.count>firstRange,let id=attributes["relaymarkId"] as? String else { supported=false;continue }
                    let first=ranges[firstRange],last=ranges[ranges.count-1]
                    widget(kind:name=="questionBlock" ? .question : .directive,id:id,name:name,attributes:attributes,
                        range:NSRange(location:first.location,length:NSMaxRange(last)-first.location),path:blockPath)
                    offsets.append(first.location);continue
                }
                if name == "taskItem" {
                    let checkedValue = attributes["checked"] as? NSNumber
                    let checked = checkedValue?.boolValue ?? false
                    let entityID = attributes["entityId"] as? String
                    let validChecked = attributes["checked"] == nil ||
                        checkedValue.map { CFGetTypeID($0) == CFBooleanGetTypeID() } == true
                    let validEntity = attributes["entityId"] == nil || (dialect == .rich && attributes["entityId"] is NSNull) ||
                        entityID.map { UUID(uuidString: $0)?.uuidString.lowercased() == $0 } == true
                    guard dialect == .rich,
                          let id = attributes["relaymarkId"] as? String,
                          Set(attributes.keys).isSubset(of: ["relaymarkId", "checked", "entityId"]),
                          validChecked, validEntity,
                          children.first?["name"] as? String == "paragraph" else {
                        supported = false; continue
                    }
                    let intent = PresentationIntent(.listItem(ordinal: index + 1), identity: identity, parent: parent)
                    let firstRange = ranges.count
                    try walk(children, path: blockPath, parent: intent, cellContext: cellContext)
                    guard ranges.count > firstRange else { supported = false; continue }
                    taskItems.append(TaskItem(id: id, checked: checked, entityID: entityID,
                        firstParagraphRange: ranges[firstRange], firstParagraphText: xmlText(children[0]),
                        path: blockPath))
                    offsets.append(ranges[firstRange].location)
                    continue
                }
                if name == "callout" {
                    let tone = attributes["tone"] as? String
                    let emphasis = attributes["emphasis"] as? String
                    let title = children.first?["name"] as? String == "calloutTitle"
                    let body = title ? children.dropFirst() : children[...]
                    guard dialect == .rich,
                          Set(attributes.keys) == Set(["relaymarkId", "tone", "emphasis"]),
                          let id = attributes["relaymarkId"] as? String,
                          let tone, ["neutral", "primary", "secondary", "accent", "info", "success", "warning", "error"].contains(tone),
                          let emphasis, ["soft", "strong"].contains(emphasis),
                          !body.isEmpty else {
                        supported = false; continue
                    }
                    let firstRange = ranges.count
                    try walk(children, path: blockPath, parent: parent, cellContext: cellContext, allowCalloutTitle: true)
                    guard ranges.count > firstRange else { supported = false; continue }
                    let first = ranges[firstRange]
                    let last = ranges[ranges.count - 1]
                    calloutRanges.append(Callout(id: id,
                        range: NSRange(location: first.location, length: NSMaxRange(last) - first.location),
                        titleRange: title ? first : nil, tone: tone, emphasis: emphasis))
                    offsets.append(first.location)
                    continue
                }
                let kind: PresentationIntent.Kind
                var table: (width: Int, starts: [[Int]])?
                var paperControl: RelayMarkPaperControlContract.Validated?
                var entityReference: EntityReferenceAtom?
                var suggestion: RelayMarkAgentSuggestionContract.Validated?
                var media: MediaAtom.Kind?
                switch name {
                case "paragraph", "questionLabel", "questionOption": kind = .paragraph
                case "relayDataView": kind = .thematicBreak
                case "heading":
                    if !validInteger(attributes["level"], minimum: 1, maximum: 6) { supported = false }
                    if let headingID = attributes["headingId"],
                       (dialect == .legacy || !(headingID is NSNull)),
                       (headingID as? String)?.isEmpty != false { supported = false }
                    kind = .header(level: min(6, max(1, attributes["level"] as? Int ?? 1)))
                case "codeBlock":
                    if let language = attributes["language"], !(language is NSNull), !(language is String) { supported = false }
                    if let language = attributes["language"] as? String, language.contains("\n") || language.contains("\r") { supported = false }
                    kind = .codeBlock(languageHint: attributes["language"] as? String)
                case "horizontalRule": kind = .thematicBreak
                case "relayButton", "relayAnchor", "relayConnection":
                    kind = .thematicBreak
                    if dialect == .rich,
                       let validated = try? RelayMarkPaperControlContract.validate(nodeName: name, attributes: attributes),
                       children.isEmpty {
                        paperControl = validated
                    } else { supported = false }
                case "relayEntityReference":
                    kind = .thematicBreak
                    if dialect == .rich, children.isEmpty,
                       Set(attributes.keys).isSubset(of: ["relaymarkId", "entityRef", "entityId",
                                                          "entityType", "label", "projection", "source"]),
                       let id = attributes["relaymarkId"] as? String,
                       let entityRef = attributes["entityRef"] as? String,
                       let entityID = attributes["entityId"] as? String,
                       UUID(uuidString: entityID)?.uuidString.lowercased() == entityID,
                       entityRef == "entity:\(entityID)",
                       attributes["entityType"] as? String == "Entity",
                       let label = attributes["label"] as? String,
                       !label.isEmpty,
                       ["link", "card"].contains(attributes["projection"] as? String ?? ""),
                       let source = attributes["source"] as? String {
                        entityReference = EntityReferenceAtom(id: id, entityID: entityID,
                            label: label, source: source,
                            range: NSRange(location: 0, length: 1), path: blockPath)
                    } else { supported = false }
                case "agentSuggestion":
                    kind = .thematicBreak
                    if dialect == .rich,
                       let validated = try? RelayMarkAgentSuggestionContract.validate(attributes: attributes),
                       children.isEmpty {
                        suggestion = validated
                    } else { supported = false }
                case "image", "videoEmbed":
                    kind = .thematicBreak
                    if dialect == .rich, children.isEmpty,
                       let validated = try? RelayMarkMediaContract.validate(
                           name: name, attributes: attributes, children: children) {
                        media = validated.kind
                    } else { supported = false }
                case "blockquote": kind = .blockQuote
                case "bulletList": kind = .unorderedList
                case "taskList":
                    if dialect != .rich || !Set(attributes.keys).isSubset(of: ["relaymarkId"]) ||
                        attributes["relaymarkId"] as? String == nil { supported = false }
                    kind = .unorderedList
                case "orderedList":
                    if !validInteger(attributes["start"], minimum: 1) { supported = false }
                    if let type = attributes["type"], !(type is NSNull) { supported = false }
                    kind = .orderedList
                case "listItem": kind = .listItem(ordinal: ordinal + index)
                case "table":
                    table = tableLayout(children)
                    kind = .table(columns: Array(repeating: .init(alignment: .left), count: table?.width ?? 0))
                case "tableRow":
                    kind = children.allSatisfy { $0["name"] as? String == "tableHeader" }
                        ? .tableHeaderRow : .tableRow(rowIndex: index)
                case "tableHeader", "tableCell":
                    kind = .tableCell(columnIndex: tableColumns?[index] ?? index)
                case "calloutTitle":
                    if dialect != .rich || !allowCalloutTitle { supported = false }
                    kind = .paragraph
                default: if genericNames.contains(name) && children.isEmpty { kind = .thematicBreak } else { supported=false;kind = .paragraph }
                }
                var allowed: Set<String> = name == "heading" ? ["level", "headingId"] : name == "codeBlock" ? ["language"] : name == "orderedList" ? ["start"] : []
                if dialect == .rich {
                    allowed.insert("relaymarkId")
                    if name == "orderedList" { allowed.insert("type") }
                    if name == "tableHeader" || name == "tableCell" {
                        allowed.formUnion(["colspan", "rowspan", "colwidth", "align"])
                    }
                }
                if name=="questionOption" { allowed.formUnion(["id","correct","points","settings"]) }
                if name=="relayDataView" { allowed.formUnion(["source","projection","columns","filter","sort","group","limit","title"]) }
                if let definition=directiveDefinitions.first(where:{$0["name"] as? String == name}),let fields=definition["attributes"] as? [String:Any] { allowed.formUnion(fields.keys) }
                if paperControl == nil && entityReference == nil && suggestion == nil && media == nil &&
                    !Set(attributes.keys).isSubset(of: allowed) { supported = false }
                let intent = PresentationIntent(kind, identity: identity, parent: parent)
                let previousCount = ranges.count
                if ["blockquote", "bulletList", "orderedList", "listItem", "taskList"].contains(name) {
                    if ["bulletList", "orderedList"].contains(name), children.contains(where: { $0["name"] as? String != "listItem" }) { supported = false }
                    if name == "taskList", children.contains(where: { $0["name"] as? String != "taskItem" }) { supported = false }
                    try walk(children, path: blockPath, parent: intent, ordinal: attributes["start"] as? Int ?? 1, cellContext: cellContext)
                } else if name == "table" {
                    guard dialect == .rich, let table, table.width > 0 else { supported = false; continue }
                    try walk(children, path: blockPath, parent: intent, tableRows: table.starts,
                         tableIdentity: identity, tableWidth: table.width)
                } else if name == "tableRow" {
                    guard dialect == .rich, let columns = tableRows?[index] else { supported = false; continue }
                    try walk(children, path: blockPath, parent: intent, tableColumns: columns,
                         tableIdentity: tableIdentity, tableWidth: tableWidth, tableRow: index)
                } else if name == "tableHeader" || name == "tableCell" {
                    guard dialect == .rich, let tableIdentity, let tableWidth, let tableRow,
                          let column = tableColumns?[index], !children.isEmpty else {
                        supported = false; continue
                    }
                    let span = attributes["colspan"] as? Int ?? 1
                    let widths: [Int]?
                    if let raw = attributes["colwidth"], !(raw is NSNull) {
                        guard let values = raw as? [Int], values.count == span,
                              values.allSatisfy({ $0 >= 0 }) else { supported = false; continue }
                        widths = values
                    } else { widths = nil }
                    let alignment: String?
                    if let raw = attributes["align"], !(raw is NSNull) {
                        guard let value = raw as? String,
                              ["left", "center", "right"].contains(value) else { supported = false; continue }
                        alignment = value
                    } else { alignment = nil }
                    try walk(children, path: blockPath, parent: intent,
                         cellContext: CellContext(tableIdentity: tableIdentity, columns: tableWidth,
                            row: tableRow, column: column,
                            rowSpan: attributes["rowspan"] as? Int ?? 1,
                            columnSpan: span, header: name == "tableHeader",
                            columnWidths: widths, alignment: alignment))
                } else {
                    if !ranges.isEmpty { value.append(AttributedString("\n")) }
                    let start = length(), attributedStart = value.endIndex
                    var inlineOffsets = [start]
                    if name == "horizontalRule" || paperControl != nil || entityReference != nil ||
                        suggestion != nil || media != nil || name=="relayDataView" || genericNames.contains(name) {
                        if !children.isEmpty { supported = false }
                        value.append(AttributedString("\u{FFFC}"))
                        if let paperControl {
                            blockAtoms.append(BlockAtom(id: paperControl.id, control: paperControl.control,
                                source: paperControl.source, displayLabel: paperControl.displayLabel,
                                range: NSRange(location: start, length: 1), path: blockPath))
                        }
                        if let entityReference {
                            entityReferenceAtoms.append(EntityReferenceAtom(id: entityReference.id,
                                entityID: entityReference.entityID, label: entityReference.label,
                                source: entityReference.source,
                                range: NSRange(location: start, length: 1), path: blockPath))
                        }
                        if let suggestion {
                            suggestionAtoms.append(SuggestionAtom(id: suggestion.id, review: suggestion.review,
                                kind: suggestion.kind, confidence: suggestion.confidence,
                                evidence: suggestion.evidence, content: suggestion.content,
                                range: NSRange(location: start, length: 1), path: blockPath))
                        }
                        if let media, let id = attributes["relaymarkId"] as? String,
                           let source = attributes[media == .image ? "src" : "videoId"] as? String {
                            mediaAtoms.append(MediaAtom(kind: media, id: id, source: source,
                                alt: attributes["alt"] as? String, title: attributes["title"] as? String,
                                width:attributes["width"] as? Int,height:attributes["height"] as? Int,
                                range: NSRange(location: start, length: 1), path: blockPath))
                        } else if media != nil { supported = false }
                        if name=="relayDataView" || genericNames.contains(name),let id=attributes["relaymarkId"] as? String {
                            widget(kind:name=="relayDataView" ? .dataView : .directive,id:id,name:name,attributes:attributes,range:NSRange(location:start,length:1),path:blockPath)
                        }
                        mapped.append(Span(range: NSRange(location: start, length: 1), path: blockPath,
                            text: false, afterPath: path, afterIndex: index + 1,
                            atom: paperControl != nil || entityReference != nil || suggestion != nil || media != nil))
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
                                    text: false, afterPath: blockPath, afterIndex: childIndex + 1, atom: false))
                            } else if child["name"] as? String == "relayReference" || child["name"] as? String == "relayTag" {
                                if let atom = inlineAtom(child, path: childPath), name != "codeBlock" {
                                    atoms.append(atom)
                                    value.append(AttributedString("\u{FFFC}"))
                                    mapped.append(Span(range: atom.range, path: childPath, text: false,
                                        afterPath: blockPath, afterIndex: childIndex + 1, atom: true))
                                } else { supported = false }
                            } else { supported = false }
                            inlineOffsets.append(length())
                        }
                    }
                    boundaries[blockPath] = inlineOffsets
                    value[attributedStart..<value.endIndex].presentationIntent = intent
                    ranges.append(NSRange(location: start, length: length() - start)); paths.append(blockPath); intents.append(intent)
                    if name=="questionOption",let id=attributes["relaymarkId"] as? String {
                        widget(kind:.option,id:id,name:name,attributes:attributes,range:ranges[ranges.count-1],path:blockPath)
                    }
                    if let cellContext {
                        cells.append(TableCell(tableIdentity: cellContext.tableIdentity,
                            range: ranges[ranges.count - 1], columns: cellContext.columns,
                            row: cellContext.row, column: cellContext.column,
                            rowSpan: cellContext.rowSpan, columnSpan: cellContext.columnSpan,
                            header: cellContext.header, columnWidths: cellContext.columnWidths,
                            alignment: cellContext.alignment))
                    }
                }
                offsets.append(ranges.count > previousCount ? ranges[previousCount].location : length())
                // An XML boundary immediately after a rule maps to the atom's end.
                // The next text leaf has its own unambiguous start position.
                if index > 0, ["horizontalRule", "relayButton", "relayAnchor", "relayConnection", "relayEntityReference", "agentSuggestion", "image", "videoEmbed"]
                    .contains(nodes[index - 1]["name"] as? String ?? ""), previousCount > 0 {
                    offsets[offsets.count - 1] = NSMaxRange(ranges[previousCount - 1])
                }
            }
            offsets.append(length()); boundaries[path] = offsets
        }
        try walk([node], path: [])
        boundaries[[]] = nil
        var chunk = Chunk()
        chunk.name = node["name"] as? String ?? ""
        chunk.length = length()
        chunk.supported = supported
        chunk.ranges = ranges; chunk.paths = paths; chunk.intents = intents
        chunk.cells = cells; chunk.callouts = calloutRanges; chunk.inlineAtoms = atoms
        chunk.blockAtoms = blockAtoms; chunk.entityReferenceAtoms = entityReferenceAtoms
        chunk.taskItems = taskItems.sorted { $0.firstParagraphRange.location < $1.firstParagraphRange.location }
        chunk.mediaAtoms = mediaAtoms; chunk.suggestionAtoms = suggestionAtoms
        chunk.authoredWidgets = authoredWidgets
        chunk.spans = mapped; chunk.boundaries = boundaries
        return (chunk, value, identity)
    }

    /// Actual text-leaf intersections; atom and separator ranges never receive text marks.
    public func textRanges(in range: NSRange) -> [TextRange] {
        var result: [TextRange] = []
        let first = chunks(touching: range.location).first ?? starts.lastIndex(beginningAtOrBefore: range.location)
        for index in first..<chunks.count {
            let chunk = chunks[index], start = starts[index]
            guard start <= NSMaxRange(range) else { break }
            guard start + chunk.length >= range.location else { continue }
            for span in chunk.spans where span.text {
                let intersection = NSIntersectionRange(range, NSRange(location: span.range.location + start, length: span.range.length))
                guard intersection.length > 0 else { continue }
                result.append(TextRange(path: Self.global(span.path, index),
                    index: intersection.location - start - span.range.location, length: intersection.length))
            }
        }
        return result
    }

    /// The number of top-level nodes.
    public var topLevelCount: Int { chunks.count }

    /// The top-level node whose text holds `offset`, at either edge.
    public func topLevelIndex(atUTF16 offset: Int) -> Int? { chunks(touching: offset).last.map { $0 + firstNode } }

    /// Where a top-level node's text begins.
    public func topLevelStart(_ index: Int) -> Int { restrictedStarts?[index - firstNode] ?? starts[index - firstNode] }

    /// The textblock holding `offset`, at either edge: its path and range.
    public func block(containingUTF16 offset: Int) -> (path: [Int], range: NSRange)? {
        for index in chunks(touching: offset) {
            let chunk = chunks[index], start = starts[index], local = offset - start
            var low = 0, high = chunk.ranges.count
            while low < high {
                let middle = (low + high) / 2
                if NSMaxRange(chunk.ranges[middle]) < local { low = middle + 1 } else { high = middle }
            }
            if low < chunk.ranges.count, chunk.ranges[low].location <= local {
                let range = chunk.ranges[low]
                return (Self.global(chunk.paths[low], index + firstNode), NSRange(location: range.location + start, length: range.length))
            }
        }
        return nil
    }

    /// The textblocks `range` intersects, in order, reading only the nodes it touches.
    public func blocks(intersecting range: NSRange) -> [(path: [Int], range: NSRange, intent: PresentationIntent)] {
        var result: [(path: [Int], range: NSRange, intent: PresentationIntent)] = []
        let first = chunks(touching: range.location).first ?? starts.lastIndex(beginningAtOrBefore: range.location)
        for index in first..<chunks.count {
            let chunk = chunks[index], start = starts[index]
            guard start <= NSMaxRange(range) else { break }
            for row in chunk.ranges.indices {
                let block = NSRange(location: chunk.ranges[row].location + start, length: chunk.ranges[row].length)
                if NSIntersectionRange(block, range).length > 0 {
                    result.append((Self.global(chunk.paths[row], index + firstNode), block, chunk.intents[row]))
                }
            }
        }
        return result
    }

    /// Where the first empty textblock at or after `offset` begins.
    public func emptyBlock(atOrAfterUTF16 offset: Int) -> Int? {
        var index = max(0, chunks(touching: offset).first ?? min(starts.lastIndex(beginningAtOrBefore: offset), chunks.count - 1))
        while index < chunks.count {
            let start = starts[index]
            if let range = chunks[index].ranges.first(where: { $0.length == 0 && $0.location + start >= offset }) {
                return range.location + start
            }
            index += 1
        }
        return nil
    }

    /// A textblock's range, by its path.
    public func blockRange(path: [Int]) -> NSRange? {
        guard let (index, local) = Self.local(path), index - firstNode >= 0, index - firstNode < chunks.count,
              let row = chunks[index - firstNode].paths.firstIndex(of: local) else { return nil }
        let range = chunks[index - firstNode].ranges[row]
        return NSRange(location: range.location + topLevelStart(index), length: range.length)
    }

    /// The chunks whose text contains `offset`, at either edge; usually one.
    private func chunks(touching offset: Int) -> [Int] {
        guard !chunks.isEmpty else { return [] }
        var index = min(starts.lastIndex(beginningAtOrBefore: offset), chunks.count - 1)
        if index >= 0, starts[index] > offset { index -= 1 }
        var found: [Int] = []
        while index >= 0, starts[index] + chunks[index].length >= offset {
            found.insert(index, at: 0); index -= 1
        }
        return found
    }

    public func position(atUTF16 offset: Int) -> (path: [Int], index: Int)? {
        for index in chunks(touching: offset) {
            if let found = position(in: index, at: offset - starts[index]) {
                return (Self.global(found.path, index), found.path.isEmpty ? found.index + index : found.index)
            }
        }
        return nil
    }

    private func position(in index: Int, at offset: Int) -> (path: [Int], index: Int)? {
        let chunk = chunks[index]
        // Only spans touching `offset` can answer; find them by binary search.
        var low = 0, high = chunk.spans.count
        while low < high {
            let middle = (low + high) / 2
            if NSMaxRange(chunk.spans[middle].range) < offset { low = middle + 1 } else { high = middle }
        }
        var spans: [Span] = []
        while low < chunk.spans.count, case let value = chunk.spans[low], value.range.location <= offset {
            spans.append(value); low += 1
        }
        // For identified atoms, both edges are XML sibling boundaries. Prefer
        // an adjacent text leaf when present so a caret edits that leaf.
        if let atom = spans.first(where: { $0.atom && ($0.range.location == offset || NSMaxRange($0.range) == offset) }) {
            if atom.range.location == offset,
               chunk.blockAtoms.contains(where: { $0.path == atom.path }) ||
               chunk.mediaAtoms.contains(where: { $0.path == atom.path }) ||
               chunk.suggestionAtoms.contains(where: { $0.path == atom.path }) {
                return (atom.path, 0)
            }
            if atom.range.location == offset,
               let previous = spans.first(where: { $0.text && NSMaxRange($0.range) == offset }) {
                return (previous.path, previous.range.length)
            }
            if NSMaxRange(atom.range) == offset,
               let next = spans.first(where: { $0.text && $0.range.location == offset }) {
                return (next.path, 0)
            }
            return (atom.afterPath, atom.afterIndex - (atom.range.location == offset ? 1 : 0))
        }
        for span in spans where offset >= span.range.location && offset <= NSMaxRange(span.range) {
            if span.text { return (span.path, offset - span.range.location) }
            if offset == span.range.location { return (span.path, 0) }
            return (span.afterPath, span.afterIndex)
        }
        // An empty block holds no span; block starts are ordered too.
        var first = 0, last = chunk.ranges.count
        while first < last {
            let middle = (first + last) / 2
            if chunk.ranges[middle].location < offset { first = middle + 1 } else { last = middle }
        }
        while first < chunk.ranges.count, case let range = chunk.ranges[first], range.location == offset {
            if range.length == 0 { return (chunk.paths[first], 0) }
            first += 1
        }
        return nil
    }

    /// Resolve a current XML position without coupling a native binding to one replica type.
    public func offset(path: [Int], index: Int) -> Int? {
        guard index >= 0 else { return nil }
        guard let (chunkIndex, local) = Self.local(path) else { return rootOffset(index) }
        guard chunkIndex >= 0, chunkIndex < chunks.count else { return nil }
        let chunk = chunks[chunkIndex], start = starts[chunkIndex]
        if let found = Self.textSpanIndex(path: local, in: chunk.spans) {
            let range = chunk.spans[found].range
            guard index <= range.length else { return nil }
            return start + range.location + index
        }
        guard let offsets = chunk.boundaries[local], index < offsets.count else { return nil }
        return start + offsets[index]
    }

    /// The paper's own child boundaries: each node's first character, or the
    /// end of a preceding atom block, and finally the end of the text.
    private func rootOffset(_ index: Int) -> Int? {
        guard index <= chunks.count else { return nil }
        if index == chunks.count { return text.utf16.count }
        if index > 0, Self.markupNames.contains(chunks[index - 1].name), !chunks[index - 1].ranges.isEmpty {
            return starts[index - 1] + chunks[index - 1].length
        }
        return starts[index]
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

// MARK: Incremental edits

extension RelayMarkCollaborativeProse {
    /// The XML text leaf and offset for an edit wholly inside one non-empty text leaf.
    public func textPosition(replacing range: NSRange) -> (path: [Int], index: Int)? {
        guard let (chunk, span) = textSpanIndex(containing: range) else { return nil }
        let value = chunks[chunk].spans[span]
        return (Self.global(value.path, chunk), range.location - starts[chunk] - value.range.location)
    }

    private func textSpanIndex(containing range: NSRange) -> (chunk: Int, span: Int)? {
        guard range.location >= 0, range.length >= 0 else { return nil }
        for chunk in chunks(touching: range.location) {
            let spans = chunks[chunk].spans, local = NSRange(location: range.location - starts[chunk], length: range.length)
            // Spans are in document order; binary search keeps lookup logarithmic.
            var low = 0, high = spans.count - 1
            while low <= high {
                let middle = (low + high) / 2, span = spans[middle]
                if NSMaxRange(span.range) < local.location { low = middle + 1 }
                else if span.range.location > NSMaxRange(local) { high = middle - 1 }
                else {
                    // Adjacent spans can share a boundary; prefer a text span that contains the range.
                    for candidate in max(0, middle - 2)...min(spans.count - 1, middle + 2) {
                        let value = spans[candidate]
                        if value.text && value.range.length > 0 &&
                            local.location >= value.range.location && NSMaxRange(local) <= NSMaxRange(value.range) {
                            return (chunk, candidate)
                        }
                    }
                    break
                }
            }
        }
        return nil
    }

    /// Spans follow document order, so their paths sort lexicographically.
    private static func textSpanIndex(path: [Int], in spans: [Span]) -> Int? {
        var low = 0, high = spans.count
        while low < high {
            let middle = (low + high) / 2
            if spans[middle].path.lexicographicallyPrecedes(path) { low = middle + 1 } else { high = middle }
        }
        while low < spans.count, spans[low].path == path {
            if spans[low].text { return low }
            low += 1
        }
        return nil
    }

    /// This projection after typing `inserted` over `range` inside one text
    /// leaf, without re-projecting the document. Returns nil when the edit is
    /// not local to one leaf; the caller then projects the whole document.
    public func replacingText(in range: NSRange, with inserted: String,
                              attributes: [String: Any]) -> RelayMarkCollaborativeProse? {
        var copy = self
        return copy.replaceText(in: range, with: inserted, attributes: attributes) ? copy : nil
    }

    /// Moves what follows a changed leaf: ranges holding the whole leaf grow,
    /// ranges at or after its end move. Only the leaf's own node is visited;
    /// later nodes move by their start alone.
    private mutating func shift(chunk index: Int, start: Int, end: Int, delta: Int) {
        func move(_ range: inout NSRange) {
            if range.location <= start && NSMaxRange(range) >= end { range.length += delta }
            else if range.location >= end { range.location += delta }
        }
        var chunk = chunks[index]
        chunks[index] = Chunk()
        for item in chunk.ranges.indices { move(&chunk.ranges[item]) }
        for item in chunk.cells.indices { move(&chunk.cells[item].range) }
        for item in chunk.callouts.indices {
            move(&chunk.callouts[item].range)
            if chunk.callouts[item].titleRange != nil { move(&chunk.callouts[item].titleRange!) }
        }
        for item in chunk.inlineAtoms.indices { move(&chunk.inlineAtoms[item].range) }
        for item in chunk.blockAtoms.indices { move(&chunk.blockAtoms[item].range) }
        for item in chunk.entityReferenceAtoms.indices { move(&chunk.entityReferenceAtoms[item].range) }
        for item in chunk.taskItems.indices { move(&chunk.taskItems[item].firstParagraphRange) }
        for item in chunk.mediaAtoms.indices { move(&chunk.mediaAtoms[item].range) }
        for item in chunk.suggestionAtoms.indices { move(&chunk.suggestionAtoms[item].range) }
        for item in chunk.authoredWidgets.indices { move(&chunk.authoredWidgets[item].range) }
        for item in chunk.spans.indices { move(&chunk.spans[item].range) }
        for key in chunk.boundaries.keys {
            chunk.boundaries[key] = chunk.boundaries[key]?.map { $0 >= end ? $0 + delta : $0 }
        }
        chunk.length += delta
        chunks[index] = chunk
        starts.add(delta, at: index)
    }

    /// Re-projects one text leaf from its current authored runs, for a peer's
    /// update that changed only that leaf's text or marks. Returns nil,
    /// unchanged, when the leaf is empty or cannot be spliced on its own.
    /// Returns the range the leaf held before, which a text view replaces too.
    public mutating func replaceLeaf(path: [Int], runs: [(text: String, attributes: [String: Any])]) -> NSRange? {
        guard isEditable, let (index, local) = Self.local(path), index < chunks.count,
              let spanIndex = Self.textSpanIndex(path: local, in: chunks[index].spans) else { return nil }
        let localLeaf = chunks[index].spans[spanIndex].range
        let leaf = NSRange(location: localLeaf.location + starts[index], length: localLeaf.length)
        let inserted = runs.map(\.text).joined()
        guard leaf.length > 0, !inserted.isEmpty else { return nil }
        let task = chunks[index].taskItems.indices.first {
            let paragraph = chunks[index].taskItems[$0].firstParagraphRange
            return paragraph.location <= localLeaf.location && NSMaxRange(paragraph) >= NSMaxRange(localLeaf)
        }
        if let task, chunks[index].taskItems[task].firstParagraphRange != localLeaf { return nil }
        let utf16 = text.utf16, scalars = text.unicodeScalars
        let lower = utf16.index(text.startIndex, offsetBy: leaf.location)
        let upper = utf16.index(lower, offsetBy: leaf.length)
        guard let block = text[lower..<scalars.index(after: lower)].runs.first?.attributes else { return nil }
        let codeBlock = block.presentationIntent?.components.contains(where: {
            if case .codeBlock = $0.kind { return true } else { return false }
        }) == true
        // Only code text holds line breaks inside one leaf; other breaks are separate nodes.
        let forbidden = codeBlock ? "\r\u{2028}\u{2029}\u{FFFC}" : "\n\r\u{2028}\u{2029}\u{FFFC}"
        guard !inserted.unicodeScalars.contains(where: { forbidden.unicodeScalars.contains($0) }) else { return nil }
        var part = AttributedString()
        for run in runs where !run.text.isEmpty {
            guard var piece = try? Self.projectedText(text: run.text, attributes: run.attributes, dialect: .rich, codeBlock: codeBlock) else { return nil }
            piece.presentationIntent = block.presentationIntent
            part.append(piece)
        }
        text.replaceSubrange(lower..<upper, with: part)
        if let task { chunks[index].taskItems[task].firstParagraphText = inserted }
        shift(chunk: index, start: localLeaf.location, end: NSMaxRange(localLeaf), delta: inserted.utf16.count - leaf.length)
        return leaf
    }

    /// Applies typing `inserted` over `range` inside one text leaf in place.
    /// `attributes` are the leaf's authored marks for the inserted text. The
    /// text changes in logarithmic time; only the leaf's own top-level node
    /// is visited. Returns false, unchanged, when the edit is not local to one leaf.
    public mutating func replaceText(in range: NSRange, with inserted: String, attributes: [String: Any]) -> Bool {
        guard isEditable, let (index, spanIndex) = textSpanIndex(containing: range),
              !inserted.unicodeScalars.contains(where: { "\n\r\u{2028}\u{2029}\u{FFFC}".unicodeScalars.contains($0) }),
              range.length < chunks[index].spans[spanIndex].range.length || !inserted.isEmpty else { return false }
        let leaf = chunks[index].spans[spanIndex].range, chunkStart = starts[index]
        let start = leaf.location, end = NSMaxRange(leaf)
        // The paragraph's XML text omits atoms and breaks; only a task paragraph of this one leaf maps directly.
        let task = chunks[index].taskItems.indices.first {
            let paragraph = chunks[index].taskItems[$0].firstParagraphRange
            return paragraph.location <= start && NSMaxRange(paragraph) >= end
        }
        if let task, chunks[index].taskItems[task].firstParagraphRange != leaf { return false }
        let delta = inserted.utf16.count - range.length
        let utf16 = text.utf16, scalars = text.unicodeScalars
        let lower = utf16.index(text.startIndex, offsetBy: range.location)
        let upper = utf16.index(lower, offsetBy: range.length)
        // Block presentation comes from the leaf's neighbouring character; marks come from `attributes`.
        let neighbour = range.location > chunkStart + start ? scalars.index(before: lower) : (range.length > 0 ? lower : upper)
        guard neighbour < text.endIndex,
              let block = text[neighbour..<scalars.index(after: neighbour)].runs.first?.attributes,
              var part = try? Self.projectedText(text: inserted, attributes: attributes, dialect: .rich,
                  codeBlock: block.presentationIntent?.components.contains(where: {
                      if case .codeBlock = $0.kind { return true } else { return false }
                  }) == true) else { return false }
        part.presentationIntent = block.presentationIntent
        text.replaceSubrange(lower..<upper, with: part)
        if let task {
            chunks[index].taskItems[task].firstParagraphText = (chunks[index].taskItems[task].firstParagraphText as NSString)
                .replacingCharacters(in: NSRange(location: range.location - chunkStart - start, length: range.length), with: inserted)
        }
        shift(chunk: index, start: start, end: end, delta: delta)
        return true
    }

    /// Replaces the top-level nodes in `range` with `replacement`, a projection
    /// of just the nodes now there, numbered from `identityLimit`. Only those
    /// nodes' text and metadata change; later nodes move by their start alone.
    /// Returns the text range replaced and the range now holding its
    /// replacement, separators included, and `content`, the replaced nodes'
    /// own offsets before the change: metadata before it stays, metadata
    /// inside it is replaced, and metadata after it moves. Nil, unchanged,
    /// unless every node involved holds text.
    public mutating func replaceTopLevelNodes(_ range: Range<Int>, with replacement: RelayMarkCollaborativeProse)
        -> (old: NSRange, new: NSRange, content: NSRange)? {
        guard range.lowerBound >= 0, range.upperBound <= chunks.count, replacement.rootSupported,
              replacement.identityLimit >= identityLimit,
              chunks[range].allSatisfy({ !$0.ranges.isEmpty }),
              replacement.chunks.allSatisfy({ !$0.ranges.isEmpty }),
              chunks.count - range.count + replacement.chunks.count > 0 else { return nil }
        let contentStart = range.isEmpty
            ? (range.lowerBound > 0 ? starts[range.lowerBound - 1] + chunks[range.lowerBound - 1].length + 1 : 0)
            : starts[range.lowerBound]
        let contentEnd = range.isEmpty ? contentStart : starts[range.upperBound - 1] + chunks[range.upperBound - 1].length + 1
        // Separators sit before every node but the first, so the replaced text
        // takes the separator before it, or after it at the paper's start.
        let oldStart: Int, oldEnd: Int
        var inserted = AttributedString()
        if range.lowerBound > 0 {
            oldStart = starts[range.lowerBound - 1] + chunks[range.lowerBound - 1].length
            oldEnd = range.isEmpty ? oldStart : starts[range.upperBound - 1] + chunks[range.upperBound - 1].length
            for chunk in replacement.chunks.indices {
                inserted.append(AttributedString("\n")); inserted.append(replacement.chunkText(chunk))
            }
        } else if range.upperBound < chunks.count {
            oldStart = 0; oldEnd = starts[range.upperBound]
            for chunk in replacement.chunks.indices {
                inserted.append(replacement.chunkText(chunk)); inserted.append(AttributedString("\n"))
            }
        } else {
            oldStart = 0; oldEnd = text.utf16.count
            inserted = replacement.text
        }
        let lower = text.utf16.index(text.startIndex, offsetBy: oldStart)
        text.replaceSubrange(lower..<text.utf16.index(lower, offsetBy: oldEnd - oldStart), with: inserted)
        unsupportedChunks += replacement.chunks.filter { !$0.supported }.count - chunks[range].filter { !$0.supported }.count
        rangeCount += replacement.chunks.reduce(0) { $0 + $1.ranges.count } - chunks[range].reduce(0) { $0 + $1.ranges.count }
        chunks.replaceSubrange(range, with: replacement.chunks)
        // Every node involved holds text, so a separator precedes each but the paper's first;
        // past the replacement only the next node's separator can change.
        let replaced = range.lowerBound..<min(chunks.count, range.lowerBound + replacement.chunks.count + 1)
        var widths: [Int] = [], separated: [Bool] = []
        var any = (0..<range.lowerBound).reversed().contains { !chunks[$0].ranges.isEmpty }
        for index in replaced {
            let separator = !chunks[index].ranges.isEmpty && any
            any = any || !chunks[index].ranges.isEmpty
            widths.append(chunks[index].length + (separator ? 1 : 0)); separated.append(separator)
        }
        starts.replace(range.lowerBound..<min(starts.count, range.upperBound + 1), widths: widths, separated: separated)
        identityLimit = replacement.identityLimit
        return (NSRange(location: oldStart, length: oldEnd - oldStart),
                NSRange(location: oldStart, length: inserted.utf16.count),
                NSRange(location: contentStart, length: contentEnd - contentStart))
    }

    /// One chunk's own text, without separators.
    private func chunkText(_ index: Int) -> AttributedSubstring {
        let lower = text.utf16.index(text.startIndex, offsetBy: starts[index])
        return text[lower..<text.utf16.index(lower, offsetBy: chunks[index].length)]
    }
}

/// Where each top-level node's text begins. Node widths (length plus the
/// separator before it) live in buckets with running sums, so a typed
/// character or an inserted node touches one bucket and a lookup walks the
/// bucket sums, never every node.
private struct NodeStarts {
    private struct Bucket {
        var widths: [Int]
        var separated: [Bool]
        var sum: Int
    }
    private static let bucketSize = 256
    private var buckets: [Bucket] = []
    private(set) var count = 0

    init(widths: [Int], separated: [Bool]) {
        buckets = Self.buckets(widths[...], separated[...])
        count = widths.count
    }

    private static func buckets(_ widths: ArraySlice<Int>, _ separated: ArraySlice<Bool>) -> [Bucket] {
        stride(from: widths.startIndex, to: widths.endIndex, by: bucketSize).map { start in
            let end = min(widths.endIndex, start + bucketSize)
            return Bucket(widths: Array(widths[start..<end]), separated: Array(separated[start..<end]),
                          sum: widths[start..<end].reduce(0, +))
        }
    }

    /// The bucket holding node `index`, the bucket's first node and the width before it.
    private func locate(_ index: Int) -> (bucket: Int, first: Int, before: Int) {
        var first = 0, before = 0
        for (position, bucket) in buckets.enumerated() {
            if index < first + bucket.widths.count { return (position, first, before) }
            first += bucket.widths.count; before += bucket.sum
        }
        return (buckets.count, first, before)
    }

    subscript(index: Int) -> Int {
        let (position, first, before) = locate(index)
        let bucket = buckets[position]
        return bucket.widths[..<(index - first)].reduce(before, +) + (bucket.separated[index - first] ? 1 : 0)
    }

    mutating func add(_ delta: Int, at index: Int) {
        let (position, first, _) = locate(index)
        buckets[position].widths[index - first] += delta
        buckets[position].sum += delta
    }

    /// Replaces the widths of the nodes in `range`, touching only the buckets around it.
    mutating func replace(_ range: Range<Int>, widths: [Int], separated: [Bool]) {
        guard !buckets.isEmpty else {
            buckets = Self.buckets(widths[...], separated[...]); count = widths.count; return
        }
        var (low, first, _) = locate(range.lowerBound)
        if low == buckets.count { low -= 1; first -= buckets[low].widths.count }
        var high = low, end = first + buckets[low].widths.count
        while end < range.upperBound, high + 1 < buckets.count { high += 1; end += buckets[high].widths.count }
        var flatWidths = buckets[low...high].flatMap(\.widths), flatSeparated = buckets[low...high].flatMap(\.separated)
        let local = (range.lowerBound - first)..<(range.upperBound - first)
        flatWidths.replaceSubrange(local, with: widths); flatSeparated.replaceSubrange(local, with: separated)
        buckets.replaceSubrange(low...high, with: Self.buckets(flatWidths[...], flatSeparated[...]))
        count += widths.count - range.count
    }

    /// The last node whose width, its separator included, begins at or before `offset`.
    func lastIndex(beginningAtOrBefore offset: Int) -> Int {
        var first = 0, before = 0
        for bucket in buckets {
            if before + bucket.sum <= offset { first += bucket.widths.count; before += bucket.sum; continue }
            for width in bucket.widths {
                guard before + width <= offset else { return first }
                before += width; first += 1
            }
            return first
        }
        return first
    }
}
