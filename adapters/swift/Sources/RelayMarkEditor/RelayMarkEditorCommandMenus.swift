import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The platform menus of `RelayMarkEditorCommand`: each lists every command,
/// one inline section per `RelayMarkEditorCommand.Section`, and runs it on
/// the session. Nothing here decides which commands exist.
@MainActor
enum RelayMarkEditorCommandMenus {
    nonisolated static var title: String { String(localized: "Format", bundle: .module, comment: "Menu of the paper's editing commands.") }

    #if os(macOS)
    static func format(session: RelayMarkEditorSession, after perform: @escaping @MainActor () -> Void) -> NSMenuItem {
        let menu = NSMenu(title: title)
        for (index, section) in RelayMarkEditorCommand.Section.allCases.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for command in RelayMarkEditorCommand.commands(in: section) {
                let item = RelayMenuAction.item(command.title) { [weak session] in
                    guard let session else { return }
                    session.perform(command)
                    perform()
                }
                item.identifier = NSUserInterfaceItemIdentifier(command.id)
                item.image = NSImage(systemSymbolName: command.systemImage, accessibilityDescription: nil)
                item.isEnabled = session.canPerform(command)
                menu.addItem(item)
            }
        }
        menu.autoenablesItems = false
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
    #else
    static func format(session: RelayMarkEditorSession, after perform: @escaping @MainActor () -> Void) -> UIMenu {
        UIMenu(title: title, image: UIImage(systemName: "textformat"), children: RelayMarkEditorCommand.Section.allCases.map { section in
            UIMenu(options: .displayInline, children: RelayMarkEditorCommand.commands(in: section).map { command in
                UIAction(title: command.title, image: UIImage(systemName: command.systemImage),
                         identifier: UIAction.Identifier(command.id),
                         attributes: session.canPerform(command) ? [] : .disabled) { [weak session] _ in
                    guard let session else { return }
                    session.perform(command)
                    perform()
                }
            })
        })
    }
    #endif
}
