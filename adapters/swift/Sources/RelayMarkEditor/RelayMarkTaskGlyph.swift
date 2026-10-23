import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The one checklist and task status glyph on Apple. A checklist checkbox is a
/// task's status circle, so paper checklists, task chips, rows, cards, headers
/// and status menus all draw this, at any size, from one routine. Its tokens
/// match the web's glyph (docs/engineering/entity-card-contracts.md in
/// relay-elixir): a ring a tenth of the diameter thick around a faint tint of
/// its own colour; done is a filled circle with a check, cancelled one with a
/// cross. The host chooses the colour (a task's priority, green when done).
public struct RelayMarkTaskGlyph: Equatable, Sendable {
    public enum Shape: Sendable, Equatable {
        /// To do, or an unticked checklist item.
        case open
        /// Backlog.
        case dashed
        /// In progress: the ring with its trailing half filled.
        case half
        /// Done, or a ticked checklist item.
        case done
        case cancelled
    }

    public var shape: Shape
    public var tint: Color

    public init(_ shape: Shape, tint: Color) {
        self.shape = shape
        self.tint = tint
    }

    /// The diameter beside body text (15 pt), and its ratio to the text's point size.
    public static let size: CGFloat = 20
    public static let sizePerPoint: CGFloat = size / 15
    /// The ring's thickness as a share of the diameter: 2 pt at 20 pt.
    public static let strokeRatio: CGFloat = 0.1
    /// The inner tint's opacity of the ring's colour.
    public static let tintOpacity: CGFloat = 0.12
    /// A checklist item without a Task: a neutral ring, green once ticked.
    public static let neutral = Color.secondary
    public static let done = Color.green

    public static func checklist(checked: Bool) -> Self {
        checked ? .init(.done, tint: done) : .init(.open, tint: neutral)
    }

    /// Draws the glyph filling the square `rect` with the resolved tint.
    public func draw(in context: CGContext, rect: CGRect, tint color: CGColor) {
        let diameter = min(rect.width, rect.height)
        let box = CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)
        let stroke = diameter * Self.strokeRatio
        context.saveGState()
        defer { context.restoreGState() }
        switch shape {
        case .done, .cancelled:
            context.setFillColor(color)
            context.fillEllipse(in: box)
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.setLineWidth(diameter * 0.11)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            let unit = diameter / 20
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: box.minX + x * unit, y: box.minY + y * unit) }
            if shape == .done {
                context.move(to: point(6, 10.4)); context.addLine(to: point(8.7, 13)); context.addLine(to: point(14, 7.4))
            } else {
                context.move(to: point(7, 7)); context.addLine(to: point(13, 13))
                context.move(to: point(13, 7)); context.addLine(to: point(7, 13))
            }
            context.strokePath()
        case .open, .dashed, .half:
            let ring = box.insetBy(dx: stroke / 2, dy: stroke / 2)
            context.setFillColor(color.copy(alpha: color.alpha * Self.tintOpacity) ?? color)
            context.fillEllipse(in: ring)
            context.setStrokeColor(color)
            context.setLineWidth(stroke)
            if shape == .dashed {
                // Twelve dashes around the ring, as the web's dashed circle.
                let dash = .pi * ring.width / 24
                context.setLineDash(phase: 0, lengths: [dash, dash])
            }
            context.strokeEllipse(in: ring)
            if shape == .half {
                let inner = box.insetBy(dx: stroke * 2, dy: stroke * 2)
                context.setFillColor(color)
                context.move(to: CGPoint(x: inner.midX, y: inner.minY))
                context.addArc(center: CGPoint(x: inner.midX, y: inner.midY), radius: inner.width / 2,
                               startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
                context.closePath()
                context.fillPath()
            }
        }
    }

    #if os(macOS)
    /// The glyph as an image for menus and other image-only places; it redraws
    /// in the appearance it is shown in.
    @MainActor public func image(diameter: CGFloat = size) -> NSImage {
        let tint = NSColor(self.tint)
        return NSImage(size: CGSize(width: diameter, height: diameter), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, rect: rect, tint: tint.cgColor)
            return true
        }
    }
    #else
    /// The glyph as an image for menus and other image-only places, with light
    /// and dark variants.
    @MainActor public func image(diameter: CGFloat = size) -> UIImage {
        let asset = UIImageAsset(), tint = UIColor(self.tint)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter),
                                                   format: UIGraphicsImageRendererFormat(for: traits))
            let image = renderer.image { context in
                draw(in: context.cgContext, rect: CGRect(x: 0, y: 0, width: diameter, height: diameter),
                     tint: tint.resolvedColor(with: traits).cgColor)
            }
            asset.register(image.withRenderingMode(.alwaysOriginal), with: traits)
        }
        return asset.image(with: .current).withRenderingMode(.alwaysOriginal)
    }
    #endif
}

/// The task glyph as a view, filling its frame's shorter side.
public struct RelayMarkTaskGlyphView: View {
    public var glyph: RelayMarkTaskGlyph
    @Environment(\.self) private var environment

    public init(_ glyph: RelayMarkTaskGlyph) {
        self.glyph = glyph
    }

    public var body: some View {
        Canvas { context, size in
            let tint = glyph.tint.resolve(in: environment).cgColor
            context.withCGContext { glyph.draw(in: $0, rect: CGRect(origin: .zero, size: size), tint: tint) }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
