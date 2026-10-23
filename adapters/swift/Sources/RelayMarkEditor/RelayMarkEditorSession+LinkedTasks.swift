import Foundation

/// A checklist item linked to a Task draws as that Task's chip: its title runs
/// carry the chip as a text attribute, and the text view draws the status circle
/// and surface from it. The host supplies statuses and reports when they change.
extension RelayMarkEditorSession {
    /// The status the chip of `entityID`'s item shows, asking the host once per change.
    func linkedTaskStatus(entityID: String, checked: Bool) -> RelayMarkTaskGlyph? {
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
