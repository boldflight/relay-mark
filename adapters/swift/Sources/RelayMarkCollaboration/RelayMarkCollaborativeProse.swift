import RelayMarkProseProjection

/// Preserves the existing adapter API while the pure projection is shared with native YSwift.
public typealias RelayMarkCollaborativeProse = RelayMarkProseProjection.RelayMarkCollaborativeProse

public extension RelayMarkCollaborativeProse {
    func offset(for position: RelayMarkCollaborationDocument.Position) -> Int? {
        offset(path: position.path, index: position.index)
    }
}
