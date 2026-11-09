import CoreGraphics
import RelayMarkEditorCore
import Testing

/// The task glyph is a value the session carries without UI frameworks; its
/// tokens match the web's glyph.
@Suite("Task glyph value")
struct RelayMarkTaskGlyphTests {
    @Test("The ring rounds to whole points as the web's border does")
    func strokeRounding() {
        #expect([16, 18, 24, 30, 52].map { RelayMarkTaskGlyph.stroke(diameter: $0) } == [2, 2, 3, 3, 6])
        #expect(RelayMarkTaskGlyph.size == 18)
    }

    @Test("A checklist item without a Task is a neutral ring, green once ticked")
    func checklist() {
        #expect(RelayMarkTaskGlyph.checklist(checked: false) == .init(.open, tint: .neutral))
        #expect(RelayMarkTaskGlyph.checklist(checked: true) == .init(.done, tint: .green))
    }
}
