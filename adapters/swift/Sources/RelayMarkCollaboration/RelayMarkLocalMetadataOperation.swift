import Foundation

/// A local history transition with no Yjs update. Hosts persist its exact attribution
/// record and successor replay atomically with the owner's history snapshot.
/// Decoding this candidate does not establish authorization or semantic validity.
public struct RelayMarkLocalMetadataOperation: Codable, Equatable, Sendable, Identifiable {
    public enum Intent: String, Codable, Sendable { case undo, redo }
    public let id: UUID
    public let intent: Intent
    public let attribution: RelayMarkLocalTransaction.AttributionCandidate

    public init(id: UUID, intent: Intent, attribution: RelayMarkLocalTransaction.AttributionCandidate) {
        self.id = id
        self.intent = intent
        self.attribution = attribution
    }
}
