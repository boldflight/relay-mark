import Foundation
import SwiftUI

/// How a linked checklist item's Task chip shows the Task's status: the host's
/// status symbol and tint, as its other task chips show them.
public struct RelayMarkLinkedTaskStatus: Equatable, Sendable {
    public var systemImage: String
    public var tint: Color

    public init(systemImage: String, tint: Color) {
        self.systemImage = systemImage
        self.tint = tint
    }
}

/// A checklist item linked to a Task draws as that Task's chip: its title runs
/// carry the chip as a text attribute, and the text view draws the status circle
/// and surface from it. The host supplies statuses and reports when they change.
extension RelayMarkEditorSession {
    /// The status the chip of `entityID`'s item shows, asking the host once per change.
    func linkedTaskStatus(entityID: String, checked: Bool) -> RelayMarkLinkedTaskStatus? {
        let key = LinkedTaskKey(entityID: entityID, checked: checked)
        if let known = linkedTaskStatuses[key] { return known }
        let status = linkedTaskStatus?(entityID, checked)
        linkedTaskStatuses[key] = status
        return status
    }

    /// The host's Tasks changed (its local replica published): chips ask again and redraw.
    /// It costs one redraw, never a re-render of the paper's text, and nothing
    /// while no chip has been drawn.
    public func linkedTasksChanged() {
        guard !linkedTaskStatuses.isEmpty else { return }
        linkedTaskStatuses.removeAll()
        linkedTaskRevision &+= 1
    }
}
