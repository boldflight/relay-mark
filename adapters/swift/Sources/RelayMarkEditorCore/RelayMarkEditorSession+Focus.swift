import Foundation

/// Where the caret goes when the host moves keyboard focus into the paper.
public enum RelayPaperFocus: Sendable {
    case start, end
    /// The paper's current selection.
    case selection
}

extension RelayMarkEditorSession {
    /// Moves keyboard focus into the paper with the caret at `placement`, as
    /// Return in the host's title does on the web. The paper's view takes focus
    /// now, or as soon as it is in a window.
    public func requestFocus(at placement: RelayPaperFocus = .start) {
        guard !isInvalidated else { return }
        switch placement {
        case .start: setNativeSelection(NSRange(location: 0, length: 0))
        case .end: setNativeSelection(NSRange(location: text.utf16.count, length: 0))
        case .selection: break
        }
        focusRequest = placement
        onFocusRequest?()
    }
}
