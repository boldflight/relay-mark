import Foundation
#if os(macOS)
import AppKit
private typealias LayoutColor = NSColor
#else
import UIKit
private typealias LayoutColor = UIColor
#endif

/// Callouts are a paragraph attribute drawn by a Relay layout fragment: NSTextBlock
/// forces TextKit 1 on iOS and TextKit 2 ignores it on macOS. Tables are attachments.
extension NSAttributedString.Key {
    static let relayCallout = NSAttributedString.Key("RelayCallout")
}

/// One callout's presentation, shared by each of its paragraphs.
final class RelayCalloutStyle: NSObject {
    let identity: Int
    let tone: String
    let strong: Bool

    init(identity: Int, tone: String, strong: Bool) {
        self.identity = identity; self.tone = tone; self.strong = strong
    }

    fileprivate var color: LayoutColor {
        switch tone {
        case "success": .systemGreen
        case "warning": .systemOrange
        case "error": .systemRed
        case "accent", "secondary": .systemPurple
        default: .systemBlue
        }
    }
    static let inset: CGFloat = 8
    var borderWidth: CGFloat { strong ? 2 : 1 }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RelayCalloutStyle else { return false }
        return identity == other.identity && tone == other.tone && strong == other.strong
    }
    override var hash: Int { identity ^ tone.hashValue ^ strong.hashValue }
    override var description: String { "RelayCallout(\(identity), \(tone), strong: \(strong))" }
}

/// The paper's margins, the same on every platform. The leading margin holds the
/// heading chevrons' gutter, 1.5rem wide as on the web.
enum RelayPaperMargins {
    static let gutter: CGFloat = 24
    static let trailing: CGFloat = 5
    static let leading: CGFloat = trailing + gutter
}

/// The paper's TextKit 2 layout: system paragraphs and callout fragments.
final class RelayTextLayoutManager: NSTextLayoutManager, NSTextLayoutManagerDelegate {
    override init() {
        super.init()
        delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var textStorage: NSTextStorage? { (textContentManager as? NSTextContentStorage)?.textStorage }

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        let range = textElement.elementRange ?? NSTextRange(location: location)
        if let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0,
           let callout = paragraph.attributedString.attribute(.relayCallout, at: 0, effectiveRange: nil) as? RelayCalloutStyle {
            return RelayCalloutFragment(textElement: textElement, range: range, callout: callout)
        }
        return NSTextLayoutFragment(textElement: textElement, range: range)
    }
}

/// A callout paragraph: inset text over its tinted, bordered block.
final class RelayCalloutFragment: NSTextLayoutFragment {
    let callout: RelayCalloutStyle

    init(textElement: NSTextElement, range: NSTextRange, callout: RelayCalloutStyle) {
        self.callout = callout
        super.init(textElement: textElement, range: range)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func sameCallout(at offset: Int) -> Bool {
        guard let storage = (textLayoutManager as? RelayTextLayoutManager)?.textStorage,
              offset >= 0, offset < storage.length else { return false }
        return (storage.attribute(.relayCallout, at: offset, effectiveRange: nil) as? RelayCalloutStyle)?.identity == callout.identity
    }
    private var bounds: NSRange? {
        guard let content = textLayoutManager?.textContentManager else { return nil }
        let start = content.offset(from: content.documentRange.location, to: rangeInElement.location)
        let end = content.offset(from: content.documentRange.location, to: rangeInElement.endLocation)
        return NSRange(location: start, length: end - start)
    }
    var isFirst: Bool { bounds.map { !sameCallout(at: $0.location - 1) } ?? true }
    var isLast: Bool { bounds.map { !sameCallout(at: NSMaxRange($0)) } ?? true }

    private var inset: CGFloat { RelayCalloutStyle.inset + callout.borderWidth }
    override var leadingPadding: CGFloat { inset }
    override var trailingPadding: CGFloat { inset }
    override var topMargin: CGFloat { isFirst ? inset : 0 }
    override var bottomMargin: CGFloat { isLast ? inset : 0 }

    /// The block in fragment coordinates: the container's width, the fragment's height.
    private var blockRect: CGRect {
        let frame = layoutFragmentFrame
        let padding = textLayoutManager?.textContainer?.lineFragmentPadding ?? 0
        let width = (textLayoutManager?.textContainer?.size.width ?? frame.maxX) - 2 * padding
        return CGRect(x: padding - frame.minX, y: 0, width: width, height: frame.height)
    }
    override var renderingSurfaceBounds: CGRect { super.renderingSurfaceBounds.union(blockRect) }

    override func draw(at point: CGPoint, in context: CGContext) {
        let rect = blockRect.offsetBy(dx: point.x, dy: point.y)
        let color = callout.color
        context.saveGState()
        context.setFillColor(color.withAlphaComponent(callout.strong ? 0.14 : 0.07).cgColor)
        context.fill(rect)
        context.setFillColor(color.cgColor)
        let border = callout.borderWidth
        context.fill(CGRect(x: rect.minX, y: rect.minY, width: border, height: rect.height))
        context.fill(CGRect(x: rect.maxX - border, y: rect.minY, width: border, height: rect.height))
        if isFirst { context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: border)) }
        if isLast { context.fill(CGRect(x: rect.minX, y: rect.maxY - border, width: rect.width, height: border)) }
        context.restoreGState()
        super.draw(at: point, in: context)
    }
}

#if os(macOS)
/// The Mac paper's container. NSTextView keeps a tracking container as wide as
/// the view less its symmetric inset; the paper lays out narrower by the gutter
/// its leading margin adds, and the view moves the container past the gutter.
final class RelayPaperTextContainer: NSTextContainer {
    override var size: NSSize {
        get { let size = super.size; return NSSize(width: max(1, size.width - RelayPaperMargins.gutter), height: size.height) }
        set { super.size = newValue }
    }
}
#endif

#if os(macOS) && DEBUG
/// TextKit 1 compatibility mode is a one-way switch away from the paper's
/// TextKit 2 layout. Debug builds and tests stop at the first paper or cell
/// view that takes it. UIKit posts no notification; its views assert in layout.
@MainActor enum RelayTextKit1Guard {
    private static var installed = false
    static func install() {
        guard !installed else { return }
        installed = true
        NotificationCenter.default.addObserver(forName: NSTextView.willSwitchToNSLayoutManagerNotification,
                                               object: nil, queue: nil) { note in
            guard note.object is CollaborationTextView || note.object is RelayTableCellTextView else { return }
            assertionFailure("A paper text view switched to TextKit 1 compatibility mode")
        }
    }
}
#endif
