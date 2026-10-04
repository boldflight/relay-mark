import Foundation
import CoreFoundation
import RelayMarkSwift

/// Deliberately bounded editable projection; unsupported structure is preserved by the replica.
public struct RelayMarkCollaborativeProse {
    public enum Dialect: Sendable {
        case legacy
        case rich
    }

    public let text: AttributedString
    public let isEditable: Bool
    public let blockRanges: [NSRange]

    /// Native presentation metadata for table paragraphs. XML remains the
    /// source of truth; these ranges share the same UTF-16 text map as edits.
    public struct TableCell: Equatable, Sendable {
        public let tableIdentity: Int
        public let range: NSRange
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
    public let tableCells: [TableCell]

    /// Stable callout identity and presentation ranges. The Yrs XML remains
    /// authoritative; these ranges only style editable native text leaves.
    public struct Callout: Equatable, Sendable {
        public let id: String
        public let range: NSRange
        public let titleRange: NSRange?
        public let tone: String
        public let emphasis: String
    }
    public let callouts: [Callout]

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
        public let range: NSRange
        public let path: [Int]
    }
    public let inlineAtoms: [InlineAtom]

    /// Inert canonical Paper controls projected as one UTF-16 block unit.
    public struct BlockAtom: Equatable, Sendable {
        public typealias Control = RelayMarkPaperControlContract.Control
        public let id: String
        public let control: Control
        public let source: String
        public let displayLabel: String
        public let range: NSRange
        public let path: [Int]
    }
    public let blockAtoms: [BlockAtom]

    /// A block reference occupies one selection unit. The host resolves its
    /// authorized target; authored identity and fallback remain in XML.
    public struct EntityReferenceAtom: Equatable, Sendable {
        public let id: String
        public let entityID: String
        public let label: String
        public let source: String
        public let range: NSRange
        public let path: [Int]
    }
    public let entityReferenceAtoms: [EntityReferenceAtom]

    /// A task's authored checkbox and optional linked entity are metadata on
    /// its XML item, not characters inserted into the editable text map.
    public struct TaskItem: Equatable, Sendable {
        public let id: String
        public let checked: Bool
        public let entityID: String?
        public let firstParagraphRange: NSRange
        public let path: [Int]
    }
    public let taskItems: [TaskItem]

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
        public let range: NSRange
        public let path: [Int]
    }
    public let mediaAtoms: [MediaAtom]

    /// Authored canonical suggestion as one inert block unit; review actions remain host-owned.
    public struct SuggestionAtom: Equatable, Sendable {
        public let id: String
        public let review: String
        public let kind: String
        public let confidence: Double?
        public let evidence: [String]
        public let content: String
        public let range: NSRange
        public let path: [Int]
    }
    public let suggestionAtoms: [SuggestionAtom]

    /// Shared authored widgets retain XML identity and editable child ranges.
    /// The host supplies domain actions/rendering; this metadata contains no answers or permissions.
    public struct AuthoredWidget: Equatable, Sendable {
        public enum Kind: String, Sendable { case question,option,dataView,directive }
        public let kind: Kind
        public let id: String
        public let nodeName: String
        public let attributes: Data
        public let range: NSRange
        public let path: [Int]
    }
    public let authoredWidgets: [AuthoredWidget]

    /// Block metadata remains available when an empty paragraph has no text run.
    public let blockIntents: [PresentationIntent]
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
        let atom: Bool
    }
    private let spans: [Span]
    private let containerOffsets: [[Int]: [Int]]

    public init(snapshot: Data, dialect: Dialect = .legacy) throws {
        let root = try JSONSerialization.jsonObject(with: snapshot) as? [String: Any]
        if dialect == .rich { _ = try RelayMarkSourceCodec.snapshotToDocument(snapshot) }
        let directiveDefinitions = try JSONSerialization.jsonObject(with:RelayMarkSourceCodec.directiveDefinitions()) as? [[String:Any]] ?? []
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
        var supported = root?["kind"] as? String == "fragment"
        var identity = 0
        func widget(kind:AuthoredWidget.Kind,id:String,name:String,attributes:[String:Any],range:NSRange,path:[Int]) {
            guard let data=try? JSONSerialization.data(withJSONObject:attributes,options:[.sortedKeys]) else { supported=false;return }
            authoredWidgets.append(AuthoredWidget(kind:kind,id:id,nodeName:name,attributes:data,range:range,path:path))
        }
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
                let offered = Set(RelayMarkOfferedMark.allCases.map(\.rawValue))
                let allowed = Set(["bold", "italic", "strike", "code", "link"])
                    .union(dialect == .rich ? offered : [])
                if !Set(attributes.keys).isSubset(of: allowed) { supported = false }
                if codeBlock && !attributes.isEmpty { supported = false }
                if attributes["code"] != nil && (attributes.count > 1 || insert.contains("\r") || insert.contains("\n")) { supported = false }
                for key in ["bold", "italic", "strike", "code"] where attributes[key] != nil {
                    if !(attributes[key] is [String: Any]) { supported = false }
                }
                var offeredMarks = Set<RelayMarkOfferedMark>()
                if dialect == .rich {
                    for mark in RelayMarkOfferedMark.allCases where attributes[mark.rawValue] != nil {
                        if (attributes[mark.rawValue] as? [String: Any])?.isEmpty == true {
                            offeredMarks.insert(mark)
                        } else { supported = false }
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
                        (dialect != .rich || link["title"] == nil || link["title"] is NSNull),
                        !href.contains("\n"), !href.contains("<"), !href.contains(">"), let url = URL(string: href) {
                        part.link = url
                    } else { supported = false }
                }
                value.append(part)
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
                  cellContext: CellContext? = nil, allowCalloutTitle: Bool = false) {
            var offsets: [Int] = []
            for (index, block) in nodes.enumerated() {
                let blockPath = path + [index]
                let name = block["name"] as? String ?? ""
                let attributes = block["attributes"] as? [String: Any] ?? [:]
                let children = block["children"] as? [[String: Any]] ?? []
                if block["kind"] as? String != "element" { supported = false }
                identity += 1
                if dialect == .rich && (name=="questionBlock" || (genericNames.contains(name) && !children.isEmpty)) {
                    let firstRange=ranges.count
                    walk(children,path:blockPath,parent:parent,cellContext:cellContext)
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
                    let validEntity = attributes["entityId"] == nil ||
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
                    walk(children, path: blockPath, parent: intent, cellContext: cellContext)
                    guard ranges.count > firstRange else { supported = false; continue }
                    taskItems.append(TaskItem(id: id, checked: checked, entityID: entityID,
                        firstParagraphRange: ranges[firstRange], path: blockPath))
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
                    walk(children, path: blockPath, parent: parent, cellContext: cellContext, allowCalloutTitle: true)
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
                    walk(children, path: blockPath, parent: intent, ordinal: attributes["start"] as? Int ?? 1, cellContext: cellContext)
                } else if name == "table" {
                    guard dialect == .rich, let table, table.width > 0 else { supported = false; continue }
                    walk(children, path: blockPath, parent: intent, tableRows: table.starts,
                         tableIdentity: identity, tableWidth: table.width)
                } else if name == "tableRow" {
                    guard dialect == .rich, let columns = tableRows?[index] else { supported = false; continue }
                    walk(children, path: blockPath, parent: intent, tableColumns: columns,
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
                    walk(children, path: blockPath, parent: intent,
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
        walk(root?["children"] as? [[String: Any]] ?? [], path: [])
        text = value; blockRanges = ranges; blockPaths = paths; blockIntents = intents
        tableCells = cells; callouts = calloutRanges; inlineAtoms = atoms
        self.blockAtoms = blockAtoms; self.entityReferenceAtoms = entityReferenceAtoms
        self.taskItems = taskItems.sorted { $0.firstParagraphRange.location < $1.firstParagraphRange.location }
        self.mediaAtoms = mediaAtoms; self.suggestionAtoms = suggestionAtoms
        self.authoredWidgets = authoredWidgets
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
        // For identified atoms, both edges are XML sibling boundaries. Prefer
        // an adjacent text leaf when present so a caret edits that leaf.
        if let atom = spans.first(where: { $0.atom && ($0.range.location == offset || NSMaxRange($0.range) == offset) }) {
            if atom.range.location == offset,
               blockAtoms.contains(where: { $0.path == atom.path }) ||
               mediaAtoms.contains(where: { $0.path == atom.path }) ||
               suggestionAtoms.contains(where: { $0.path == atom.path }) {
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
