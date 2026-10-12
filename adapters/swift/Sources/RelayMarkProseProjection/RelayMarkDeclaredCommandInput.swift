import Foundation
import RelayMarkSwift

// The actual maintained command choices, shared by execution and original custody.
public enum RelayMarkFormattingMark: String, Codable, Sendable { case bold, italic, strike, code }
public enum RelayMarkListDepthChange: String, Codable, Sendable { case indent, outdent }
public enum RelayMarkTableOperation: String, Codable, Sendable, CaseIterable {
    case addRowBefore, addRowAfter, addColumnBefore, addColumnAfter
    case deleteRow, deleteColumn, deleteTable
    case toggleHeaderCell, toggleHeaderRow, toggleHeaderColumn
    case mergeCells, splitCell
}

/// Only explicitly supplied arguments, frozen before current document fields
/// are merged. No before/expected state, target anchors, receipts or copied labels.
/// Validation here is custody shape, not document/domain authoring authority.
public enum RelayMarkDeclaredCommandInput: Codable, Equatable, Sendable {
    case formatting(mark: RelayMarkFormattingMark, enabled: Bool)
    case mediaSettings(fields: [String: RelayMarkValue])
    case widgetSettings(nodeName: String, fields: [String: RelayMarkValue], settingFields: [String: RelayMarkValue])
    case paperControl(nodeName: String, fields: [String: String])
    case link(destination: String?)
    case image(source: String?, alt: String)
    case orderedListStart(start: Int)
    case listDepth(change: RelayMarkListDepthChange)
    case heading(level: Int)
    case table(operation: RelayMarkTableOperation)

    public enum Failure: Error { case invalidOriginal }

    /// Decode into the existing portable JSON value, never retain opaque bytes.
    public static func fields(from data: Data) throws -> [String: RelayMarkValue] {
        let value = try JSONDecoder().decode(RelayMarkValue.self, from: data)
        guard case .object(let fields) = value else { throw Failure.invalidOriginal }
        return fields
    }

    public func validate() throws {
        func validateFields(_ fields: [String: RelayMarkValue], sourceBundleProperties: Bool = false) throws {
            guard fields.keys.allSatisfy({ !$0.isEmpty && ($0 != "id" || sourceBundleProperties) && $0 != "relaymarkId" }) else { throw Failure.invalidOriginal }
            // The maintained portable codec rejects nonfinite/non-JSON values.
            _ = try JSONEncoder().encode(RelayMarkValue.object(fields))
        }
        switch self {
        case .mediaSettings(let fields):
            guard !fields.isEmpty, Set(fields.keys).isSubset(of: ["width", "height", "alt", "title"]) else { throw Failure.invalidOriginal }
            try validateFields(fields)
        case .widgetSettings(let nodeName, let fields, let settingFields):
            guard nodeName == "questionBlock" || nodeName == "questionOption" || nodeName.hasPrefix("relay"),
                !fields.isEmpty || !settingFields.isEmpty,
                nodeName == "questionBlock" || settingFields.isEmpty,
                nodeName != "questionBlock" || fields["settings"] == nil else { throw Failure.invalidOriginal }
            // SourceBundle props.id is its authored evidence-reference key,
            // distinct from the immutable AST identity (relaymarkId).
            try validateFields(fields, sourceBundleProperties: nodeName == "relaySourceBundle")
            try validateFields(settingFields)
        case .paperControl(let nodeName, let fields):
            guard !fields.isEmpty, Set(fields.keys).isSubset(of: Set(try RelayMarkPaperControlContract.authoredFieldNames(nodeName: nodeName))) else { throw Failure.invalidOriginal }
        case .image(let source, let alt):
            guard source != nil || !alt.isEmpty else { throw Failure.invalidOriginal }
        case .formatting, .link, .orderedListStart, .listDepth, .heading, .table:
            // Their actual canonical mutation owns validity/current target; this
            // preserves supplied choice without minting an authoring capability.
            break
        }
    }

    public func canonicalData() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public init(validatingCanonical data: Data) throws {
        let original = try JSONDecoder().decode(Self.self, from: data)
        guard try original.canonicalData() == data else { throw Failure.invalidOriginal }
        self = original
    }
}
