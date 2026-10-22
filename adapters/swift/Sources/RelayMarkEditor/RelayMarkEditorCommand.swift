import Foundation
import RelayMarkNativeCollaboration
import RelayMarkProseProjection
import SwiftUI

/// One paper editing command, defined once for every Apple platform. The menu
/// bar, the edit menu, the paper toolbar, the formatting panel and the / menu
/// all list `RelayMarkEditorCommand.all`; UIKit and AppKit only map their
/// events onto it. Block and insert IDs are Relay's editor catalog IDs, so the
/// / menu runs a catalog command by looking it up here.
public struct RelayMarkEditorCommand: Identifiable, Hashable, Sendable {
    public enum Section: CaseIterable, Sendable { case block, listDepth, mark, insert }

    enum Operation: Equatable, Sendable {
        case block(RelayMarkNativeBlockStyle)
        case listDepth(RelayMarkNativeListDepthChange)
        case mark(RelayMarkFormattingMark)
        case offeredMark(RelayMarkOfferedMark)
        case insert(Insertion)
    }

    enum Insertion: Hashable, Sendable { case table, divider, callout, codeBlock }

    public let id: String
    public let title: String
    public let systemImage: String
    public let section: Section
    public let shortcut: KeyboardShortcut?
    let operation: Operation

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The level a heading command sets, which hosts may show as its glyph.
    public var headingLevel: Int? {
        if case .block(.heading(let level)) = operation { level } else { nil }
    }

    /// Every command's ID.
    public static var ids: Set<String> { Set(all.map(\.id)) }

    /// The command with this ID, or nil when the paper has none.
    public static func command(id: String) -> RelayMarkEditorCommand? { all.first { $0.id == id } }

    /// The commands of one section, in menu order.
    public static func commands(in section: Section) -> [RelayMarkEditorCommand] { all.filter { $0.section == section } }

    /// Every command, in menu order. Titles read the current localization.
    public static var all: [RelayMarkEditorCommand] {
        func command(_ id: String, _ title: String, _ image: String, _ section: Section, _ operation: Operation,
                     _ key: KeyEquivalent? = nil, _ modifiers: EventModifiers = .command) -> RelayMarkEditorCommand {
            .init(id: id, title: title, systemImage: image, section: section,
                  shortcut: key.map { KeyboardShortcut($0, modifiers: modifiers) }, operation: operation)
        }
        let headings = (1...6).map { level in
            command("editor.heading.\(level)",
                    String(localized: "Heading \(level)", bundle: .module, comment: "Editor command that makes the block a heading of this level."),
                    "textformat.size", .block, .block(.heading(level)),
                    KeyEquivalent(Character(String(level))), [.command, .option, .shift])
        }
        return [
            command("editor.body", String(localized: "Body", bundle: .module, comment: "Editor command that returns the block to body text."),
                    "text.alignleft", .block, .block(.paragraph), "0", [.command, .option]),
        ] + headings + [
            command("editor.quote", String(localized: "Quote", bundle: .module, comment: "Editor command that makes the block a quote."),
                    "text.quote", .block, .block(.quote), "b", [.command, .shift]),
            command("editor.list.bullet", String(localized: "Bullet List", bundle: .module, comment: "Editor command that makes the block a bulleted list."),
                    "list.bullet", .block, .block(.bulletList), "8", [.command, .shift]),
            command("editor.list.numbered", String(localized: "Numbered List", bundle: .module, comment: "Editor command that makes the block a numbered list."),
                    "list.number", .block, .block(.orderedList), "7", [.command, .shift]),
            command("editor.list.task", String(localized: "Checklist", bundle: .module, comment: "Editor command that makes the block a checklist of tasks."),
                    "checklist", .block, .block(.taskList), "9", [.command, .shift]),
            command("editor.list.indent", String(localized: "Indent", bundle: .module, comment: "Editor command that nests the list item one level deeper."),
                    "increase.indent", .listDepth, .listDepth(.indent)),
            command("editor.list.outdent", String(localized: "Outdent", bundle: .module, comment: "Editor command that moves the list item one level out."),
                    "decrease.indent", .listDepth, .listDepth(.outdent)),
            command("editor.mark.bold", String(localized: "Bold", bundle: .module, comment: "Editor command that toggles bold text."),
                    "bold", .mark, .mark(.bold), "b"),
            command("editor.mark.italic", String(localized: "Italic", bundle: .module, comment: "Editor command that toggles italic text."),
                    "italic", .mark, .mark(.italic), "i"),
            command("editor.mark.underline", String(localized: "Underline", bundle: .module, comment: "Editor command that toggles underlined text."),
                    "underline", .mark, .offeredMark(.underline), "u"),
            command("editor.mark.strike", String(localized: "Strikethrough", bundle: .module, comment: "Editor command that toggles struck-through text."),
                    "strikethrough", .mark, .mark(.strike), "s", [.command, .shift]),
            command("editor.mark.highlight", String(localized: "Highlight", bundle: .module, comment: "Editor command that toggles highlighted text."),
                    "highlighter", .mark, .offeredMark(.highlight), "h", [.command, .shift]),
            command("editor.mark.superscript", String(localized: "Superscript", bundle: .module, comment: "Editor command that toggles superscript text."),
                    "textformat.superscript", .mark, .offeredMark(.superscript)),
            command("editor.mark.subscript", String(localized: "Subscript", bundle: .module, comment: "Editor command that toggles subscript text."),
                    "textformat.subscript", .mark, .offeredMark(.subscript)),
            command("editor.mark.code", String(localized: "Inline Code", bundle: .module, comment: "Editor command that toggles inline code."),
                    "chevron.left.forwardslash.chevron.right", .mark, .mark(.code), "e"),
            command("editor.table", String(localized: "Table", bundle: .module, comment: "VoiceOver label of a table in the paper."),
                    "tablecells", .insert, .insert(.table)),
            command("editor.divider", String(localized: "Divider", bundle: .module, comment: "Editor command that inserts a divider."),
                    "minus", .insert, .insert(.divider)),
            command("editor.callout", String(localized: "Callout", bundle: .module, comment: "Editor command that inserts a callout."),
                    "text.bubble", .insert, .insert(.callout)),
            command("editor.code", String(localized: "Code Block", bundle: .module, comment: "Editor command that inserts a code block."),
                    "curlybraces", .insert, .insert(.codeBlock), "c", [.command, .option]),
        ]
    }
}

@MainActor
public extension RelayMarkEditorSession {
    /// Whether the command applies to the current selection.
    func canPerform(_ command: RelayMarkEditorCommand) -> Bool {
        guard isEditable else { return false }
        switch command.operation {
        case .block: return canSetSelectedBlockStyle
        case .listDepth(.indent): return canIndentSelectedListItem
        case .listDepth(.outdent): return canOutdentSelectedListItem
        case .mark(.code): return canFormatInlineCodeSelection
        case .mark, .offeredMark: return canFormatInlineSelection
        case .insert: return canInsertBlock
        }
    }

    /// Runs the command on the current selection.
    func perform(_ command: RelayMarkEditorCommand) {
        // A new checklist made by the command arms its empty items; converted lines stay local.
        let tasksBefore = command.id == "editor.list.task" && createsTaskDrafts ? nativeTaskItems : nil
        defer { if let tasksBefore { armTaskDrafts(event: ["kind": "command"], before: tasksBefore) } }
        switch command.operation {
        case .block(let style): setSelectedBlockStyle(style)
        case .listDepth(let change): changeSelectedListDepth(change)
        case .mark(let mark): toggleInlineMark(mark)
        case .offeredMark(let mark): toggleOfferedMark(mark)
        case .insert(.table): insertTable()
        case .insert(.divider): insertDivider()
        case .insert(.callout): insertCallout()
        case .insert(.codeBlock): insertCodeBlock()
        }
    }
}
