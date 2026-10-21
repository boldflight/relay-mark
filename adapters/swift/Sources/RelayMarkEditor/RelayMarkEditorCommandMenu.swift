import SwiftUI

/// Every `RelayMarkEditorCommand` as SwiftUI menu content, one section per
/// command section. The app's Format menu (menu bar on Mac, iPad and Vision
/// Pro) and the paper toolbar's Format menu (every platform, the only route on
/// iPhone) both show this. Keyboard shortcuts belong to one of them only, so
/// a chord is never registered twice.
public struct RelayMarkEditorCommandMenu: View {
    let session: RelayMarkEditorSession?
    let shortcuts: Bool

    public init(session: RelayMarkEditorSession?, shortcuts: Bool) {
        self.session = session
        self.shortcuts = shortcuts
    }

    public var body: some View {
        ForEach(RelayMarkEditorCommand.Section.allCases, id: \.self) { section in
            Section {
                ForEach(RelayMarkEditorCommand.commands(in: section)) { command in
                    Button(command.title, systemImage: command.systemImage) { session?.perform(command) }
                        .keyboardShortcut(shortcuts ? command.shortcut : nil)
                        .disabled(session?.canPerform(command) != true)
                }
            }
        }
    }

    /// The menu's title.
    public static var title: String { RelayMarkEditorCommandMenus.title }
}
