import Foundation
import RelayMarkProseProjection

/// One local editor transaction: the exact Yjs update the host appends to its
/// journal and sends. Undo is the editor's own Yrs UndoManager; nothing here
/// is provenance or authorization.
public struct RelayMarkLocalTransaction: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let update: Data
    /// Local input evidence only; it confers no authorship.
    public let inputIntent: InputIntent?

    public init(id: UUID = UUID(), update: Data, inputIntent: InputIntent? = nil) {
        self.id = id; self.update = update; self.inputIntent = inputIntent
    }

    public enum InputIntent: Codable, Equatable, Sendable {
        /// The start is in the pre-edit prose projection's UTF-16 coordinates.
        /// The removed string's UTF-16 length determines the replaced extent.
        case nativeReplacement(startUTF16: Int, removed: String, inserted: String)
        /// Actual explicitly supplied command arguments.
        case declaredCommand(RelayMarkDeclaredCommandInput)
        /// A candidate diff without a validated native replacement request.
        case derived
        /// Committed marked input.
        case composition
        case undo
        case redo
    }
}
