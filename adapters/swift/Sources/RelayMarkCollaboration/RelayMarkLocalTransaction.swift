import Foundation

/// One local editor transaction. Hosts persist this together with its exact update bytes.
/// Replica replay never creates a contribution; generation provenance belongs to the layer host.
public struct RelayMarkLocalTransaction: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let update: Data
    public let changes: [TextChange]
    /// Local editor operation evidence only. It does not establish authenticated
    /// authorship, ownership of restored text, or contribution replacement rights.
    public let inputIntent: InputIntent?
    /// Exact item-selection JSON captured by the editor for newly inserted text.
    /// Nil means unproven; an empty selection means a proven operation inserted
    /// no text. This local evidence does not establish authenticated authorship.
    /// Freeze these bytes with the update before attempting durable persistence.
    public let insertedTextItems: Data?
    /// A native formatting command, or its actually performed undo/redo, whose
    /// editor verified unchanged text identities. InputIntent distinguishes history.
    /// This is local operation evidence, never an assertion of text authorship.
    public let nativeFormatting: NativeFormatting?
    /// Evidence from the explicit isolated paragraph-end operation. It does not
    /// authorize structural edits or establish ownership of existing prose.
    public let nativeParagraph: NativeParagraph?
    public let nativeParagraphPaste: NativeParagraphPaste?

    /// Exact bounded operation evidence; native paste intent and authorization
    /// remain the host's responsibility. Text comes from InputIntent, not here.
    public struct NativeParagraphPaste: Codable, Equatable, Sendable {
        public let paragraphIndex: Int
        public let endUTF16: Int
        public let paragraphCount: Int
        public init(paragraphIndex: Int, endUTF16: Int, paragraphCount: Int) {
            self.paragraphIndex = paragraphIndex; self.endUTF16 = endUTF16; self.paragraphCount = paragraphCount
        }
    }

    public struct NativeParagraph: Codable, Equatable, Sendable {
        public let paragraphIndex: Int
        public let endUTF16: Int
        public init(paragraphIndex: Int, endUTF16: Int) {
            self.paragraphIndex = paragraphIndex; self.endUTF16 = endUTF16
        }
    }

    public struct NativeFormatting: Codable, Equatable, Sendable {
        public enum Mark: String, Codable, Sendable { case bold, italic }
        public let startUTF16: Int
        public let lengthUTF16: Int
        public let mark: Mark
        public let enabled: Bool
        public init(startUTF16: Int, lengthUTF16: Int, mark: Mark, enabled: Bool) {
            self.startUTF16 = startUTF16; self.lengthUTF16 = lengthUTF16
            self.mark = mark; self.enabled = enabled
        }
    }

    public init(id: UUID = UUID(), update: Data, changes: [TextChange]) {
        self.init(id: id, update: update, changes: changes, inputIntent: nil)
    }

    public init(id: UUID = UUID(), update: Data, changes: [TextChange], inputIntent: InputIntent?) {
        self.init(id: id, update: update, changes: changes, inputIntent: inputIntent, insertedTextItems: nil)
    }

    public init(id: UUID = UUID(), update: Data, changes: [TextChange], inputIntent: InputIntent?, insertedTextItems: Data?) {
        self.init(id: id, update: update, changes: changes, inputIntent: inputIntent,
                  insertedTextItems: insertedTextItems, nativeFormatting: nil)
    }

    public init(id: UUID = UUID(), update: Data, changes: [TextChange], inputIntent: InputIntent?,
                insertedTextItems: Data?, nativeFormatting: NativeFormatting?) {
        self.init(id: id, update: update, changes: changes, inputIntent: inputIntent,
                  insertedTextItems: insertedTextItems, nativeFormatting: nativeFormatting, nativeParagraph: nil)
    }

    public init(id: UUID = UUID(), update: Data, changes: [TextChange], inputIntent: InputIntent?,
                insertedTextItems: Data?, nativeFormatting: NativeFormatting?, nativeParagraph: NativeParagraph?) {
        self.init(id: id, update: update, changes: changes, inputIntent: inputIntent,
                  insertedTextItems: insertedTextItems, nativeFormatting: nativeFormatting,
                  nativeParagraph: nativeParagraph, nativeParagraphPaste: nil)
    }

    public init(id: UUID = UUID(), update: Data, changes: [TextChange], inputIntent: InputIntent?,
                insertedTextItems: Data?, nativeFormatting: NativeFormatting?, nativeParagraph: NativeParagraph?,
                nativeParagraphPaste: NativeParagraphPaste?) {
        self.id = id
        self.update = update
        self.changes = changes
        self.inputIntent = inputIntent
        self.insertedTextItems = insertedTextItems
        self.nativeFormatting = nativeFormatting
        self.nativeParagraph = nativeParagraph
        self.nativeParagraphPaste = nativeParagraphPaste
    }

    public enum InputIntent: Codable, Equatable, Sendable {
        /// The start is in the pre-edit prose projection's UTF-16 coordinates.
        /// The removed string's UTF-16 length determines the replaced extent.
        case nativeReplacement(startUTF16: Int, removed: String, inserted: String)
        /// A candidate diff without a validated native replacement request.
        case derived
        /// Committed or explicitly reviewed marked input; ownership is unresolved.
        case composition
        /// History restoration is never implicitly new human source material.
        case undo
        case redo
    }

    public struct TextChange: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case insert, replace, delete }
        public let kind: Kind
        public let before: String
        public let after: String
        public let contextBefore: String
        public let contextAfter: String

        /// Describes only changed characters, never attributing the whole merged document to a user.
        public static func between(_ original: String, _ proposed: String) -> [Self] {
            guard original != proposed else { return [] }
            let edit = RelayMarkCollaborativeProse.replacement(from: original, to: proposed)
            let start = String.Index(utf16Offset: edit.start, in: original)
            let end = String.Index(utf16Offset: edit.end, in: original)
            let removed = String(original[start..<end])
            return [Self(kind: removed.isEmpty ? .insert : (edit.text.isEmpty ? .delete : .replace),
                before: removed, after: edit.text,
                contextBefore: String(original[..<start].suffix(80)),
                contextAfter: String(original[end...].prefix(80)))]
        }
    }
}
