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

        if probe.contains(.id) {
            self = .block(try RelayMarkBlock(from: decoder))
        } else {
            self = .inline(try RelayMarkInline(from: decoder))
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
        case id
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
}

public struct RelayMarkManifest: Codable, Equatable, Sendable {
    public let type: String
    public let version: Int
    public let actions: [RelayMarkAction]
    public let mentions: [RelayMarkMention]
    public let forms: [RelayMarkFormQuestion]
    public let sources: [RelayMarkSource]
    public let diagnostics: [RelayMarkDiagnostic]

    public static func decodeJSON(_ data: Data) throws -> RelayMarkManifest {
        try RelayMarkDecoder.decode(RelayMarkManifest.self, from: data)
    }
}

public struct RelayMarkAction: Codable, Equatable, Sendable {
    public let blockID: String
    public let action: String
    public let args: [String: RelayMarkValue]
    public let target: String?
    public let destination: String?
    public let visibility: String?
    public let review: String
    public let evidenceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case action
        case args
        case target
        case destination
        case visibility
        case review
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockID = try container.decode(String.self, forKey: .blockID)
        action = try container.decode(String.self, forKey: .action)
        args = try container.decodeIfPresent([String: RelayMarkValue].self, forKey: .args) ?? [:]
        target = try container.decodeIfPresent(String.self, forKey: .target)
        destination = try container.decodeIfPresent(String.self, forKey: .destination)
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility)
        review = try container.decode(String.self, forKey: .review)
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
    public let sourceID: String?
    public let start: String?
    public let end: String?
    public let uri: String?
    public let label: String?

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case kind
        case sourceID = "source_id"
        case start
        case end
        case uri
        case label
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
