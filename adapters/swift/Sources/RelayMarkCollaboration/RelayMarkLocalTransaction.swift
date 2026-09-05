import Foundation

/// One locally authored input operation. Hosts persist this together with its exact update bytes.
/// Replica replay never creates a contribution; generation provenance belongs to the layer host.
public struct RelayMarkLocalTransaction: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let update: Data
    public let changes: [TextChange]

    public init(id: UUID = UUID(), update: Data, changes: [TextChange]) {
        self.id = id
        self.update = update
        self.changes = changes
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
