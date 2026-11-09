import CoreGraphics

/// The one checklist and task status glyph on Apple. A checklist checkbox is a
/// task's status circle, so paper checklists, task chips, rows, cards, headers
/// and status menus all draw this, at any size, from one routine. Its tokens
/// match the web's glyph (docs/engineering/entity-card-contracts.md in
/// relay-elixir): a ring a ninth of the diameter thick around a faint tint of
/// its own colour; done is a filled circle with a check, cancelled one with a
/// cross. The host chooses the colour (a task's priority, green when done).
///
/// The glyph is a value without UI frameworks, so editor sessions can carry it;
/// RelayMarkEditor draws it and maps its tint to the system colour.
public struct RelayMarkTaskGlyph: Equatable, Sendable {
    public enum Shape: Sendable, Equatable {
        /// To do, or an unticked checklist item.
        case open
        /// Backlog.
        case dashed
        /// In progress: the ring with its trailing half filled, one ring width inside the ring.
        case half
        /// Done, or a ticked checklist item.
        case done
        case cancelled
    }

    /// The glyph's colour, a system colour resolved in the appearance it is drawn in.
    public enum Tint: Sendable, Equatable, CaseIterable {
        /// The secondary label colour.
        case neutral
        case red
        case orange
        case blue
        case green
    }

    public var shape: Shape
    public var tint: Tint

    public init(_ shape: Shape, tint: Tint) {
        self.shape = shape
        self.tint = tint
    }

    /// The one diameter on every surface beside text, as the web's 18 px
    /// `--relay-task-glyph-size`: chips, rows, cards, menus, inline references and
    /// 15 pt paper prose. Paper prose scales it with its own point size.
    public static let size: CGFloat = 18
    public static let sizePerPoint: CGFloat = size / 15
    /// The ring's thickness as a share of the diameter: 2 pt at 18 pt, as the web's.
    public static let strokeRatio: CGFloat = 2 / 18

    /// The ring's thickness at `diameter`, in whole points as on the web (whose
    /// browsers snap a border to whole pixels): 2 at 16 and 18, 3 at 24 and 30,
    /// 6 at 52. The in-progress half sits one ring inside it.
    public static func stroke(diameter: CGFloat) -> CGFloat {
        max(1, (diameter * strokeRatio).rounded())
    }
    /// The inner tint's opacity of the ring's colour.
    public static let tintOpacity: CGFloat = 0.12

    /// A checklist item without a Task: a neutral ring, green once ticked.
    public static func checklist(checked: Bool) -> Self {
        checked ? .init(.done, tint: .green) : .init(.open, tint: .neutral)
    }
}
