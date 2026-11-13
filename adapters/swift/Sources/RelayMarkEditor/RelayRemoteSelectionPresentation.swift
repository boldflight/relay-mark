import Foundation
import SwiftUI
import RelayMarkEditorCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Nonempty remote selections use TextKit's rendering-only attributes. The
/// validator restores them when TextKit invalidates a fragment during layout.
/// No storage attributes, selection positions or geometry are changed.
/// https://developer.apple.com/documentation/appkit/nstextlayoutmanager/renderingattributesvalidator
@MainActor
final class RelayRemoteSelectionPresentation {
    private struct Highlight: Equatable {
        let range: NSRange
        let color: Color
    }
    private weak var manager: NSTextLayoutManager?
    private var highlights: [Highlight] = []

    func update(_ selections: [RelayMarkRemoteSelection], in manager: NSTextLayoutManager?,
                color: (String) -> Color) {
        guard let manager, let content = manager.textContentManager else { return }
        let length = content.offset(from: content.documentRange.location, to: content.documentRange.endLocation)
        let next = selections.compactMap { selection -> Highlight? in
            let range = selection.range
            guard range.location >= 0, range.location <= length, range.length > 0,
                  range.length <= length - range.location else { return nil }
            return Highlight(range: range, color: color(selection.color))
        }
        let replacedManager = self.manager !== manager
        if replacedManager {
            self.manager?.renderingAttributesValidator = nil
            self.manager = manager
            manager.renderingAttributesValidator = { [weak self] manager, fragment in
                // Native text views and their layout managers are owned by the main actor.
                MainActor.assumeIsolated { self?.validate(manager, fragment: fragment) }
            }
        }
        guard replacedManager || next != highlights else { return }
        let changed = highlights + next
        highlights = next
        for highlight in changed {
            let range = highlight.range
            guard range.location <= length else { continue }
            let count = min(range.length, length - range.location)
            guard count > 0,
                  let start = content.location(content.documentRange.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: count),
                  let textRange = NSTextRange(location: start, end: end) else { continue }
            manager.invalidateRenderingAttributes(for: textRange)
        }
    }

    private func validate(_ manager: NSTextLayoutManager, fragment: NSTextLayoutFragment) {
        guard let content = manager.textContentManager else { return }
        let range = fragment.rangeInElement
        let start = content.offset(from: content.documentRange.location, to: range.location)
        let end = content.offset(from: content.documentRange.location, to: range.endLocation)
        let paragraph = NSRange(location: start, length: max(0, end - start))
        // Remove only our rendering override. The document's own backgrounds and
        // unrelated rendering keys remain owned by their original systems.
        manager.removeRenderingAttribute(.backgroundColor, for: range)
        for highlight in highlights {
            let intersection = NSIntersectionRange(paragraph, highlight.range)
            guard intersection.length > 0,
                  let lower = content.location(content.documentRange.location, offsetBy: intersection.location),
                  let upper = content.location(lower, offsetBy: intersection.length),
                  let selected = NSTextRange(location: lower, end: upper) else { continue }
            #if os(macOS)
            let tint = NSColor(highlight.color).withAlphaComponent(0.2)
            #else
            let tint = UIColor(highlight.color).withAlphaComponent(0.2)
            #endif
            manager.addRenderingAttribute(.backgroundColor, value: tint, for: selected)
        }
    }
}
