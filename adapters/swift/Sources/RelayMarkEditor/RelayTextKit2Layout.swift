import Foundation
#if os(macOS)
import AppKit
typealias LayoutColor = NSColor
typealias LayoutFont = NSFont
#else
import UIKit
typealias LayoutColor = UIColor
typealias LayoutFont = UIFont
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
    /// Whether a question option is the respondent's choice (NSNumber, a Bool); absent
    /// where no answers are shown.
    static let relayOptionState = NSAttributedString.Key("RelayOptionState")
}

/// What a question card shows under its last paragraph, drawn by the layout and never
/// part of the text: answer lines, chips, and room for content the host supplies.
struct RelayAnswerSlot: Equatable {
    enum Row: Equatable {
        case text(String)
        case chip(String)
        case subdued(String)
    }
    let questionID: String
    let rows: [Row]
    /// Height of the host's view (leased files, a video), which sits above the rows.
    let hostHeight: CGFloat

    static let rowSpacing: CGFloat = 4
    static let gap: CGFloat = 8

    static func font(_ row: Row) -> LayoutFont {
        switch row { case .chip: .systemFont(ofSize: 11, weight: .semibold); default: .systemFont(ofSize: 14) }
    }
    static func attributed(_ row: Row) -> NSAttributedString {
        let color: LayoutColor
        let text: String
        switch row {
        case .text(let value): text = value; color = .labelColorCompat
        case .chip(let value): text = value; color = .secondaryLabelColorCompat
        case .subdued(let value): text = value; color = .secondaryLabelColorCompat
        }
        return NSAttributedString(string: text, attributes: [.font: font(row), .foregroundColor: color])
    }
    /// Row heights at `width`, then the whole slot's height with its gap above.
    func rowHeights(width: CGFloat) -> [CGFloat] {
        rows.map { row in
            let box = Self.attributed(row).boundingRect(with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            return ceil(box.height) + (row.isChip ? 4 : 0)
        }
    }
    func height(width: CGFloat) -> CGFloat {
        let heights = rowHeights(width: width)
        let parts = (hostHeight > 0 ? 1 : 0) + heights.count
        guard parts > 0 else { return 0 }
        return Self.gap + hostHeight + heights.reduce(0, +) + CGFloat(parts - 1) * Self.rowSpacing
    }
}

private extension RelayAnswerSlot.Row {
    var isChip: Bool { if case .chip = self { true } else { false } }
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
    /// A question's answer, drawn under its last paragraph.
    let answer: RelayAnswerSlot?

    init(identity: Int, appearance: Appearance, answer: RelayAnswerSlot? = nil) {
        self.identity = identity; self.appearance = appearance; self.answer = answer
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
        return identity == other.identity && appearance == other.appearance && answer == other.answer
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
            let selected = (paragraph.attributedString.attribute(.relayOptionState, at: 0, effectiveRange: nil) as? NSNumber)?.boolValue
            return RelayBlockFragment(textElement: textElement, range: range, block: block, optionSelected: selected)
        }
        return NSTextLayoutFragment(textElement: textElement, range: range)
    }
}

/// A paragraph of a callout or question card: inset text over the block's fill and border,
/// one continuous shape across the block's paragraphs. A chosen option carries a "Selected"
/// chip, and the card's last paragraph leaves room under it for the answer.
final class RelayBlockFragment: NSTextLayoutFragment {
    let block: RelayBlockStyle
    /// Nil where no answers are shown; otherwise whether the respondent chose this option.
    let optionSelected: Bool?

    init(textElement: NSTextElement, range: NSTextRange, block: RelayBlockStyle, optionSelected: Bool?) {
        self.block = block; self.optionSelected = optionSelected
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
    /// The width the card's content has, between its paddings.
    private var contentWidth: CGFloat { max(1, blockRect.width - 2 * padding) }
    private var chipSize: CGSize? {
        guard optionSelected == true else { return nil }
        let box = RelayAnswerSlot.attributed(.chip(RelayBlockFragment.selectedLabel)).size()
        return CGSize(width: ceil(box.width) + 12, height: ceil(box.height) + 4)
    }
    static var selectedLabel: String {
        String(localized: "Selected", bundle: .module, comment: "Marker on the option a respondent chose, in a form response.")
    }
    private var slotHeight: CGFloat { isLast ? block.answer?.height(width: contentWidth) ?? 0 : 0 }

    override var leadingPadding: CGFloat { padding }
    override var trailingPadding: CGFloat { padding + (chipSize.map { $0.width + 8 } ?? 0) }
    override var topMargin: CGFloat { isFirst ? padding + block.outerGap : 0 }
    override var bottomMargin: CGFloat { isLast ? padding + block.outerGap + slotHeight : 0 }

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

    /// Where the answer's content goes, in fragment coordinates; nil unless this is a card's last
    /// paragraph with an answer.
    var slotFrame: CGRect? {
        guard isLast, block.answer != nil, slotHeight > 0 else { return nil }
        let box = blockRect
        return CGRect(x: box.minX + padding, y: box.maxY - padding - slotHeight + RelayAnswerSlot.gap,
                      width: contentWidth, height: slotHeight - RelayAnswerSlot.gap)
    }
    /// The top of the slot, where a host's view for files and video goes.
    var hostFrame: CGRect? {
        guard let slot = slotFrame, let height = block.answer?.hostHeight, height > 0 else { return nil }
        return CGRect(x: slot.minX, y: slot.minY, width: slot.width, height: height)
    }

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
        if let chip = chipSize { drawChip(chip, at: point, in: context, box: box) }
        if isLast, let answer = block.answer, let slot = slotFrame { drawRows(answer, slot: slot.offsetBy(dx: point.x, dy: point.y), in: context) }
    }

    private func drawChip(_ size: CGSize, at point: CGPoint, in context: CGContext, box: CGRect) {
        let line = textLineFragments.first?.typographicBounds ?? .zero
        let rect = CGRect(x: box.maxX - padding - size.width, y: point.y + line.minY + (line.height - size.height) / 2,
                          width: size.width, height: size.height)
        let label = RelayAnswerSlot.attributed(.chip(Self.selectedLabel)).mutableCopy() as? NSMutableAttributedString ?? NSMutableAttributedString()
        label.addAttribute(.foregroundColor, value: LayoutColor.systemBlue, range: NSRange(location: 0, length: label.length))
        context.saveGState()
        context.setFillColor(LayoutColor.systemBlue.withAlphaComponent(0.14).cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
        context.fillPath()
        context.restoreGState()
        Self.withGraphics(context) { label.draw(at: CGPoint(x: rect.minX + 6, y: rect.minY + 2)) }
    }

    /// The answer's rows, under the host's content.
    private func drawRows(_ answer: RelayAnswerSlot, slot: CGRect, in context: CGContext) {
        var y = slot.minY + (answer.hostHeight > 0 ? answer.hostHeight + RelayAnswerSlot.rowSpacing : 0)
        let heights = answer.rowHeights(width: slot.width)
        Self.withGraphics(context) {
            for (row, height) in zip(answer.rows, heights) {
                let text = RelayAnswerSlot.attributed(row)
                if case .chip = row {
                    let width = ceil(text.size().width) + 12
                    let rect = CGRect(x: slot.minX, y: y, width: width, height: height)
                    context.setFillColor(LayoutColor.secondaryLabelColorCompat.withAlphaComponent(0.14).cgColor)
                    context.addPath(CGPath(roundedRect: rect, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil))
                    context.fillPath()
                    text.draw(at: CGPoint(x: rect.minX + 6, y: rect.minY + 2))
                } else {
                    text.draw(with: CGRect(x: slot.minX, y: y, width: slot.width, height: height),
                              options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                }
                y += height + RelayAnswerSlot.rowSpacing
            }
        }
    }

    /// Lets AppKit and UIKit drawing calls target the layout's context.
    private static func withGraphics(_ context: CGContext, _ body: () -> Void) {
        #if os(macOS)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
        #else
        UIGraphicsPushContext(context)
        body()
        UIGraphicsPopContext()
        #endif
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
