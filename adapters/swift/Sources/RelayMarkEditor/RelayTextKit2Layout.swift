import Foundation
import RelayMarkEditorCore
#if os(macOS)
import AppKit
typealias LayoutColor = NSColor
#else
import UIKit
typealias LayoutColor = UIColor
#endif

extension LayoutColor {
    static var labelColorCompat: LayoutColor {
        #if os(macOS)
        .labelColor
        #else
        .label
        #endif
    }
    static var secondaryLabelColorCompat: LayoutColor {
        #if os(macOS)
        .secondaryLabelColor
        #else
        .secondaryLabel
        #endif
    }
    static var separatorColorCompat: LayoutColor {
        #if os(macOS)
        .separatorColor
        #else
        .separator
        #endif
    }
}

/// Callouts and form question cards are one paragraph attribute drawn by a Relay layout
/// fragment: NSTextBlock forces TextKit 1 on iOS and TextKit 2 ignores it on macOS.
/// Tables are attachments.
extension NSAttributedString.Key {
    static let relayBlock = NSAttributedString.Key("RelayBlock")
}

/// One block's presentation, shared by each of its paragraphs: a callout's tinted band or a
/// question's bordered card.
final class RelayBlockStyle: NSObject {
    enum Appearance: Equatable {
        case callout(tone: String, strong: Bool)
        case card
    }
    let identity: Int
    let appearance: Appearance

    init(identity: Int, appearance: Appearance) {
        self.identity = identity; self.appearance = appearance
    }

    fileprivate var color: LayoutColor {
        switch appearance {
        case .callout(let tone, _):
            switch tone {
            case "success": .systemGreen
            case "warning": .systemOrange
            case "error": .systemRed
            case "accent", "secondary": .systemPurple
            default: .systemBlue
            }
        case .card: .separatorColorCompat
        }
    }
    fileprivate var fill: LayoutColor? {
        if case .callout(_, let strong) = appearance { return color.withAlphaComponent(strong ? 0.14 : 0.07) }
        return nil
    }
    /// Space between the text and the border.
    var padding: CGFloat {
        switch appearance { case .callout: 8 + borderWidth; case .card: 12 + borderWidth }
    }
    /// Space left outside the border above the first and below the last paragraph.
    var outerGap: CGFloat { if case .card = appearance { 8 } else { 0 } }
    var cornerRadius: CGFloat { if case .card = appearance { 6 } else { 0 } }
    var borderWidth: CGFloat {
        switch appearance { case .callout(_, let strong): strong ? 2 : 1; case .card: 1 }
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RelayBlockStyle else { return false }
        return identity == other.identity && appearance == other.appearance
    }
    override var hash: Int { identity ^ "\(appearance)".hashValue }
    override var description: String { "RelayBlock(\(identity), \(appearance))" }
}

/// The paper's margins, the same on every platform. The leading margin holds the
/// heading chevrons' gutter, 1.5rem wide as on the web.
enum RelayPaperMargins {
    static let gutter: CGFloat = 24
    static let trailing: CGFloat = 5
    static let leading: CGFloat = trailing + gutter
    /// TextKit's default line fragment padding, which the paper keeps on both sides.
    static let linePadding: CGFloat = 5
}

public extension RelayMarkEditorView {
    /// How far the paper's text sits inside the view on each side: the margins plus
    /// line padding, the leading one holding the heading chevrons' gutter. A host
    /// aligns the text with its own column, as the web aligns paper text with the
    /// title, by letting the view extend past that column by these amounts.
    static var textInsets: (leading: CGFloat, trailing: CGFloat) {
        (RelayPaperMargins.leading + RelayPaperMargins.linePadding, RelayPaperMargins.trailing + RelayPaperMargins.linePadding)
    }
}

/// The paper's TextKit 2 layout: system paragraphs and block fragments.
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
           let block = paragraph.attributedString.attribute(.relayBlock, at: 0, effectiveRange: nil) as? RelayBlockStyle {
            return RelayBlockFragment(textElement: textElement, range: range, block: block)
        }
        return NSTextLayoutFragment(textElement: textElement, range: range)
    }
}

/// A paragraph of a callout or question card: inset text over the block's fill and border,
/// one continuous shape across the block's paragraphs.
final class RelayBlockFragment: NSTextLayoutFragment {
    let block: RelayBlockStyle

    init(textElement: NSTextElement, range: NSTextRange, block: RelayBlockStyle) {
        self.block = block
        super.init(textElement: textElement, range: range)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func sameBlock(at offset: Int) -> Bool {
        guard let storage = (textLayoutManager as? RelayTextLayoutManager)?.textStorage,
              offset >= 0, offset < storage.length else { return false }
        return (storage.attribute(.relayBlock, at: offset, effectiveRange: nil) as? RelayBlockStyle)?.identity == block.identity
    }
    private var bounds: NSRange? {
        guard let content = textLayoutManager?.textContentManager else { return nil }
        let start = content.offset(from: content.documentRange.location, to: rangeInElement.location)
        let end = content.offset(from: content.documentRange.location, to: rangeInElement.endLocation)
        return NSRange(location: start, length: end - start)
    }
    var isFirst: Bool { bounds.map { !sameBlock(at: $0.location - 1) } ?? true }
    var isLast: Bool { bounds.map { !sameBlock(at: NSMaxRange($0)) } ?? true }

    private var padding: CGFloat { block.padding }
    override var leadingPadding: CGFloat { padding }
    override var trailingPadding: CGFloat { padding }
    override var topMargin: CGFloat { isFirst ? padding + block.outerGap : 0 }
    override var bottomMargin: CGFloat { isLast ? padding + block.outerGap : 0 }

    /// The block's slice in fragment coordinates: the container's width, the fragment's height
    /// less the gap left outside the border at the block's ends.
    private var blockRect: CGRect {
        let frame = layoutFragmentFrame
        let inset = textLayoutManager?.textContainer?.lineFragmentPadding ?? 0
        let width = (textLayoutManager?.textContainer?.size.width ?? frame.maxX) - 2 * inset
        let top = isFirst ? block.outerGap : 0, bottom = isLast ? block.outerGap : 0
        return CGRect(x: inset - frame.minX, y: top, width: width, height: frame.height - top - bottom)
    }
    override var renderingSurfaceBounds: CGRect { super.renderingSurfaceBounds.union(blockRect) }

    override func draw(at point: CGPoint, in context: CGContext) {
        let box = blockRect.offsetBy(dx: point.x, dy: point.y)
        let border = block.borderWidth
        context.saveGState()
        // The whole block's shape, clipped to this slice, so its paragraphs join without seams.
        context.clip(to: box)
        let whole = CGRect(x: box.minX, y: isFirst ? box.minY : box.minY - 4096, width: box.width,
                           height: box.height + (isFirst ? 0 : 4096) + (isLast ? 0 : 4096))
        let path = CGPath(roundedRect: whole.insetBy(dx: border / 2, dy: border / 2),
                          cornerWidth: block.cornerRadius, cornerHeight: block.cornerRadius, transform: nil)
        if let fill = block.fill {
            context.addPath(path); context.setFillColor(fill.cgColor); context.fillPath()
        }
        context.addPath(path); context.setStrokeColor(block.color.cgColor); context.setLineWidth(border); context.strokePath()
        context.restoreGState()
        super.draw(at: point, in: context)
    }
}

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
