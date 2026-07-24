import Foundation

public enum RelayMarkValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([RelayMarkValue])
    case object([String: RelayMarkValue])

    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    public var arrayValue: [RelayMarkValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    public var objectValue: [String: RelayMarkValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([RelayMarkValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: RelayMarkValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

public struct RelayMarkDocument: Codable, Equatable, Sendable {
    public let type: String
    public let version: Int
    public let frontmatter: [String: RelayMarkValue]
    public let blocks: [RelayMarkBlock]
    public let annotations: [RelayMarkAnnotation]
    public let resources: [RelayMarkResource]

    public static func decodeJSON(_ data: Data) throws -> RelayMarkDocument {
        try RelayMarkDecoder.decode(RelayMarkDocument.self, from: data)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        version = try container.decode(Int.self, forKey: .version)
        frontmatter = try container.decodeIfPresent([String: RelayMarkValue].self, forKey: .frontmatter) ?? [:]
        blocks = try container.decode([RelayMarkBlock].self, forKey: .blocks)
        annotations = try container.decodeIfPresent([RelayMarkAnnotation].self, forKey: .annotations) ?? []
        resources = try container.decodeIfPresent([RelayMarkResource].self, forKey: .resources) ?? []
    }
}

public struct RelayMarkBlock: Codable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let props: [String: RelayMarkValue]
    public let content: [RelayMarkContent]
    public let evidenceRefs: [String]

    public var childBlocks: [RelayMarkBlock] {
        content.compactMap { item in
            if case let .block(block) = item { return block }
            return nil
        }
    }

    public var plainText: String {
        content.map(\.plainText).joined()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case props
        case content
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        props = try container.decodeIfPresent([String: RelayMarkValue].self, forKey: .props) ?? [:]
        content = try container.decodeIfPresent([RelayMarkContent].self, forKey: .content) ?? []
        evidenceRefs = try container.decodeIfPresent([String].self, forKey: .evidenceRefs) ?? []
    }
}

public enum RelayMarkContent: Codable, Equatable, Sendable {
    case block(RelayMarkBlock)
    case inline(RelayMarkInline)

    public var plainText: String {
        switch self {
        case .block(let block):
            return block.plainText
        case .inline(let inline):
            return inline.plainText
        }
    }

    public init(from decoder: Decoder) throws {
        let probe = try decoder.container(keyedBy: ProbeKeys.self)
        let type = try probe.decode(String.self, forKey: .type)

        if Self.isInlineType(type) {
            self = .inline(try RelayMarkInline(from: decoder))
        } else {
            self = .block(try RelayMarkBlock(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .block(let block):
            try block.encode(to: encoder)
        case .inline(let inline):
            try inline.encode(to: encoder)
        }
    }

    enum ProbeKeys: String, CodingKey {
        case type
    }

    private static func isInlineType(_ type: String) -> Bool {
        switch type {
        case "text", "hard_break", "soft_break", "link", "emphasis", "strong", "code_span":
            return true
        case "relay.evidence_ref", "relay.file_ref", "relay.note_ref", "relay.url_ref":
            return false
        default:
            return type.hasPrefix("relay.") && type.hasSuffix("_ref")
        }
    }
}

public struct RelayMarkInline: Codable, Equatable, Sendable {
    public let type: String
    public let text: String?
    public let id: String?
    public let label: String?
    public let href: String?
    public let props: [String: RelayMarkValue]
    public let content: [RelayMarkInline]

    public var plainText: String {
        if let text { return text }
        if type.hasPrefix("relay."), let label { return label }
        return content.map(\.plainText).joined()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        href = try container.decodeIfPresent(String.self, forKey: .href)
        props = try container.decodeIfPresent([String: RelayMarkValue].self, forKey: .props) ?? [:]
        content = try container.decodeIfPresent([RelayMarkInline].self, forKey: .content) ?? []
    }
}

public struct RelayMarkAnnotation: Codable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let anchor: RelayMarkAnchor
    public let props: [String: RelayMarkValue]
    public let content: [RelayMarkInline]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        anchor = try container.decode(RelayMarkAnchor.self, forKey: .anchor)
        props = try container.decodeIfPresent([String: RelayMarkValue].self, forKey: .props) ?? [:]
        content = try container.decodeIfPresent([RelayMarkInline].self, forKey: .content) ?? []
    }
}

public struct RelayMarkAnchor: Codable, Equatable, Sendable {
    public let blockID: String
    public let start: Int?
    public let end: Int?
    public let quote: String?

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case start
        case end
        case quote
    }
}

public struct RelayMarkResource: Codable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let uri: String?
    public let label: String?
    public let scope: String?
    public let props: [String: RelayMarkValue]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        uri = try container.decodeIfPresent(String.self, forKey: .uri)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        props = try container.decodeIfPresent([String: RelayMarkValue].self, forKey: .props) ?? [:]
    }

    public func decodeScriptureRelease() throws -> RelayMarkScriptureRelease {
        guard type == "scripture" else {
            throw RelayMarkScriptureAdapterError.notScriptureResource
        }

        return try RelayMarkDecoder.decode(
            RelayMarkScriptureRelease.self,
            from: JSONEncoder().encode(RelayMarkValue.object(props))
        )
    }
}

public enum RelayMarkScriptureAdapterError: Error, Equatable, Sendable {
    case notScriptureResource
    case notScriptureEvidence
}

public struct RelayMarkScriptureSource: Codable, Equatable, Sendable {
    public let name: String
    public let uri: String
    public let digest: String

    public init(name: String, uri: String, digest: String) {
        self.name = name
        self.uri = uri
        self.digest = digest
    }
}

public struct RelayMarkScriptureLicense: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let url: String

    public init(id: String, name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
    }
}

public struct RelayMarkScriptureProvenance: Codable, Equatable, Sendable {
    public let coordinateInventoryDigest: String
    public let normalizedIndexInputDigest: String
    public let sourceArchiveDigest: String?
    public let authority: String?
    public let importedAt: String?

    enum CodingKeys: String, CodingKey {
        case coordinateInventoryDigest = "coordinate_inventory_digest"
        case normalizedIndexInputDigest = "normalized_index_input_digest"
        case sourceArchiveDigest = "source_archive_digest"
        case authority
        case importedAt = "imported_at"
    }

    public init(
        coordinateInventoryDigest: String,
        normalizedIndexInputDigest: String,
        sourceArchiveDigest: String? = nil,
        authority: String? = nil,
        importedAt: String? = nil
    ) {
        self.coordinateInventoryDigest = coordinateInventoryDigest
        self.normalizedIndexInputDigest = normalizedIndexInputDigest
        self.sourceArchiveDigest = sourceArchiveDigest
        self.authority = authority
        self.importedAt = importedAt
    }
}

public struct RelayMarkScriptureRelease: Codable, Equatable, Sendable {
    public let profile: String
    public let translationID: String
    public let editionID: String
    public let corpusReleaseID: String
    public let versificationID: String
    public let source: RelayMarkScriptureSource
    public let license: RelayMarkScriptureLicense
    public let attribution: String
    public let provenance: RelayMarkScriptureProvenance

    enum CodingKeys: String, CodingKey {
        case profile
        case translationID = "translation_id"
        case editionID = "edition_id"
        case corpusReleaseID = "corpus_release_id"
        case versificationID = "versification_id"
        case source
        case license
        case attribution
        case provenance
    }

    public init(
        profile: String = "relaymark.scripture_release.v1",
        translationID: String,
        editionID: String,
        corpusReleaseID: String,
        versificationID: String,
        source: RelayMarkScriptureSource,
        license: RelayMarkScriptureLicense,
        attribution: String,
        provenance: RelayMarkScriptureProvenance
    ) {
        self.profile = profile
        self.translationID = translationID
        self.editionID = editionID
        self.corpusReleaseID = corpusReleaseID
        self.versificationID = versificationID
        self.source = source
        self.license = license
        self.attribution = attribution
        self.provenance = provenance
    }
}

public enum RelayMarkScriptureCoordinate: Codable, Equatable, Sendable {
    case chapter(bookID: String, chapter: Int, verseLabel: String)
    case section(bookID: String, sectionID: String, verseLabel: String)

    enum CodingKeys: String, CodingKey {
        case bookID = "book_id"
        case coordinateKind = "coordinate_kind"
        case chapter
        case sectionID = "section_id"
        case verseLabel = "verse_label"
    }

    enum CoordinateKind: String, Codable {
        case chapter
        case section
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bookID = try container.decode(String.self, forKey: .bookID)
        let verseLabel = try container.decode(String.self, forKey: .verseLabel)

        switch try container.decode(CoordinateKind.self, forKey: .coordinateKind) {
        case .chapter:
            self = .chapter(
                bookID: bookID,
                chapter: try container.decode(Int.self, forKey: .chapter),
                verseLabel: verseLabel
            )
        case .section:
            self = .section(
                bookID: bookID,
                sectionID: try container.decode(String.self, forKey: .sectionID),
                verseLabel: verseLabel
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .chapter(bookID, chapter, verseLabel):
            try container.encode(bookID, forKey: .bookID)
            try container.encode(CoordinateKind.chapter, forKey: .coordinateKind)
            try container.encode(chapter, forKey: .chapter)
            try container.encode(verseLabel, forKey: .verseLabel)
        case let .section(bookID, sectionID, verseLabel):
            try container.encode(bookID, forKey: .bookID)
            try container.encode(CoordinateKind.section, forKey: .coordinateKind)
            try container.encode(sectionID, forKey: .sectionID)
            try container.encode(verseLabel, forKey: .verseLabel)
        }
    }
}

public struct RelayMarkScriptureSpan: Codable, Equatable, Sendable {
    public let profile: String
    public let start: RelayMarkScriptureCoordinate
    public let end: RelayMarkScriptureCoordinate
    public let contentDigest: String
    public let displayLabel: String?

    enum CodingKeys: String, CodingKey {
        case profile
        case start
        case end
        case contentDigest = "content_digest"
        case displayLabel = "display_label"
    }

    public init(
        profile: String = "relaymark.scripture_span.v1",
        start: RelayMarkScriptureCoordinate,
        end: RelayMarkScriptureCoordinate,
        contentDigest: String,
        displayLabel: String? = nil
    ) {
        self.profile = profile
        self.start = start
        self.end = end
        self.contentDigest = contentDigest
        self.displayLabel = displayLabel
    }
}

public struct RelayMarkScriptureEvidence: Equatable, Sendable {
    public let evidenceID: String
    public let sourceID: String
    public let sourceRevision: String
    public let span: RelayMarkScriptureSpan
    public let release: RelayMarkScriptureRelease
    public let scope: String
    public let excerpt: String
}

public struct RelayMarkManifest: Codable, Equatable, Sendable {
    public let type: String
    public let version: Int
    public let actions: [RelayMarkAction]
    public let mentions: [RelayMarkMention]
    public let references: [RelayMarkReference]
    public let forms: [RelayMarkFormQuestion]
    public let sources: [RelayMarkSource]
    public let claims: [RelayMarkClaim]
    public let comparisons: [RelayMarkComparison]
    public let diagnostics: [RelayMarkDiagnostic]

    public static func decodeJSON(_ data: Data) throws -> RelayMarkManifest {
        try RelayMarkDecoder.decode(RelayMarkManifest.self, from: data)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        version = try container.decode(Int.self, forKey: .version)
        actions = try container.decodeIfPresent([RelayMarkAction].self, forKey: .actions) ?? []
        mentions = try container.decodeIfPresent([RelayMarkMention].self, forKey: .mentions) ?? []
        references = try container.decodeIfPresent([RelayMarkReference].self, forKey: .references) ?? []
        forms = try container.decodeIfPresent([RelayMarkFormQuestion].self, forKey: .forms) ?? []
        sources = try container.decodeIfPresent([RelayMarkSource].self, forKey: .sources) ?? []
        claims = try container.decodeIfPresent([RelayMarkClaim].self, forKey: .claims) ?? []
        comparisons = try container.decodeIfPresent([RelayMarkComparison].self, forKey: .comparisons) ?? []
        diagnostics = try container.decodeIfPresent([RelayMarkDiagnostic].self, forKey: .diagnostics) ?? []
    }
}

public struct RelayMarkAction: Codable, Equatable, Sendable {
    public let blockID: String
    public let proposalID: String?
    public let proposalRecordID: String?
    public let proposalRevision: Int?
    public let action: String
    public let args: [String: RelayMarkValue]
    public let target: String?
    public let destination: String?
    public let visibility: String?
    public let review: String
    public let decisionID: String?
    public let executionID: String?
    public let undoID: String?
    public let evidenceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case proposalID = "proposal_id"
        case proposalRecordID = "proposal_record_id"
        case proposalRevision = "proposal_revision"
        case action
        case args
        case target
        case destination
        case visibility
        case review
        case decisionID = "decision_id"
        case executionID = "execution_id"
        case undoID = "undo_id"
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockID = try container.decode(String.self, forKey: .blockID)
        proposalID = try container.decodeIfPresent(String.self, forKey: .proposalID)
        proposalRecordID = try container.decodeIfPresent(String.self, forKey: .proposalRecordID)
        proposalRevision = try container.decodeIfPresent(Int.self, forKey: .proposalRevision)
        action = try container.decode(String.self, forKey: .action)
        args = try container.decodeIfPresent([String: RelayMarkValue].self, forKey: .args) ?? [:]
        target = try container.decodeIfPresent(String.self, forKey: .target)
        destination = try container.decodeIfPresent(String.self, forKey: .destination)
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility)
        review = try container.decode(String.self, forKey: .review)
        decisionID = try container.decodeIfPresent(String.self, forKey: .decisionID)
        executionID = try container.decodeIfPresent(String.self, forKey: .executionID)
        undoID = try container.decodeIfPresent(String.self, forKey: .undoID)
        evidenceRefs = try container.decodeIfPresent([String].self, forKey: .evidenceRefs) ?? []
    }
}

public struct RelayMarkMention: Codable, Equatable, Sendable {
    public let blockID: String
    public let kind: String
    public let id: String?
    public let label: String

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case kind
        case id
        case label
    }
}

public struct RelayMarkReference: Codable, Equatable, Sendable {
    public let blockID: String
    public let type: String
    public let id: String?
    public let label: String?
    public let href: String?

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case type
        case id
        case label
        case href
    }
}

public struct RelayMarkFormQuestion: Codable, Equatable, Sendable {
    public let blockID: String
    public let key: String
    public let label: String
    public let fieldType: String
    public let required: Bool
    public let options: [String]

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case key
        case label
        case fieldType = "field_type"
        case required
        case options
    }
}

public struct RelayMarkSource: Codable, Equatable, Sendable {
    public let blockID: String
    public let kind: String
    public let evidenceID: String?
    public let sourceID: String?
    public let sourceType: String?
    public let sourceRevision: String?
    public let selector: [String: RelayMarkValue]?
    public let scope: String?
    public let bundleRevision: Int?
    public let sourceHash: String?
    public let start: String?
    public let end: String?
    public let uri: String?
    public let label: String?
    public let excerpt: String?
    public let scriptureRelease: RelayMarkScriptureRelease?

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case kind
        case evidenceID = "evidence_id"
        case sourceID = "source_id"
        case sourceType = "source_type"
        case sourceRevision = "source_revision"
        case selector
        case scope
        case bundleRevision = "bundle_revision"
        case sourceHash = "source_hash"
        case start
        case end
        case uri
        case label
        case excerpt
        case scriptureRelease = "scripture_release"
    }

    public func decodeScriptureEvidence() throws -> RelayMarkScriptureEvidence {
        guard
            kind == "evidence_ref",
            sourceType == "scripture",
            let evidenceID,
            let sourceID,
            let sourceRevision,
            let selector,
            let scriptureRelease,
            let scope,
            let excerpt
        else {
            throw RelayMarkScriptureAdapterError.notScriptureEvidence
        }

        let span = try RelayMarkDecoder.decode(
            RelayMarkScriptureSpan.self,
            from: JSONEncoder().encode(RelayMarkValue.object(selector))
        )

        return RelayMarkScriptureEvidence(
            evidenceID: evidenceID,
            sourceID: sourceID,
            sourceRevision: sourceRevision,
            span: span,
            release: scriptureRelease,
            scope: scope,
            excerpt: excerpt
        )
    }
}

public struct RelayMarkClaim: Codable, Equatable, Sendable {
    public let blockID: String
    public let key: String
    public let subject: String?
    public let status: String
    public let confidence: Double?
    public let evidenceRefs: [String]
    public let text: String

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case key
        case subject
        case status
        case confidence
        case evidenceRefs = "evidence_refs"
        case text
    }
}

public struct RelayMarkComparison: Codable, Equatable, Sendable {
    public let blockID: String
    public let title: String?
    public let subjects: [String]
    public let criteria: [String]
    public let values: [String: RelayMarkValue]
    public let preferred: String?
    public let layout: String
    public let evidenceRefs: [String]
    public let summary: String

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case title
        case subjects
        case criteria
        case values
        case preferred
        case layout
        case evidenceRefs = "evidence_refs"
        case summary
    }
}

public struct RelayMarkDiagnostic: Codable, Equatable, Sendable {
    public let level: String
    public let code: String
    public let message: String
}

public enum RelayMarkDecoder {
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
