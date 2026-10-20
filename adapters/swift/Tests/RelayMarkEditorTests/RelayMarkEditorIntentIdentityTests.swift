import Foundation
import Testing
@testable import RelayMarkEditor

/// Foundation uniques attribute dictionaries process-wide, and NSPresentationIntent
/// equality ignores parents. Two lists whose items share identities must still
/// round-trip with their own list, whatever else the process has rendered.
@MainActor
struct RelayMarkEditorIntentIdentityTests {
    private func item(inList list: Int) -> AttributedString {
        let root = PresentationIntent(.orderedList, identity: list)
        let item = PresentationIntent(.listItem(ordinal: 8), identity: 7, parent: root)
        var text = AttributedString("Sibling")
        text.presentationIntent = PresentationIntent(.paragraph, identity: 8, parent: item)
        text.inlinePresentationIntent = []
        return text
    }

    @Test func blockIntentKeepsItsOwnParentsThroughTheCodec() {
        let decoy = NativeProseCodec.attributed(item(inList: 4))
        let text = item(inList: 1)
        #expect(NativeProseCodec.value(NativeProseCodec.attributed(text)) == text)
        _ = decoy
    }
}
