import Foundation
import CoreText
import RelayMarkCollaboration
import RelayMarkEditorCore
import RelayMarkProseProjection
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NSAttributedString.Key {
    static let relayIntent = NSAttributedString.Key("RelayInlineIntent")
    static let relayBlockIntent = NSAttributedString.Key("RelayBlockIntent")
    static let relayBlockBackground = NSAttributedString.Key("RelayBlockBackground")
    static let relayBold = NSAttributedString.Key("RelayRenderedBold")
    static let relayItalic = NSAttributedString.Key("RelayRenderedItalic")
    static let relayOfferedMarks = NSAttributedString.Key("RelayOfferedMarks")
    static let relayAIAuthored = NSAttributedString.Key("RelayAIAuthored")
    static let relayTaskItem = NSAttributedString.Key("RelayTaskItem")
}

@MainActor
enum NativeProseCodec {
    private static func traits(_ font: PlatformFont) -> (bold: Bool, italic: Bool) {
        #if os(macOS)
        let traits = NSFontManager.shared.traits(of: font)
        return (traits.contains(.boldFontMask), traits.contains(.italicFontMask))
        #else
        let traits = font.fontDescriptor.symbolicTraits
        return (traits.contains(.traitBold), traits.contains(.traitItalic))
        #endif
    }

    /// List identities belong to the canonical tree. TextKit owns marker rendering,
    /// indentation and hit testing; markers never enter the editable string.
    fileprivate struct ListDescriptor {
        let identity: Int
        let format: NSTextList.MarkerFormat
        let start: Int
    }

    private static func listDescriptors(_ intent: PresentationIntent?) -> [ListDescriptor] {
        var ordinal = 1
        return (intent?.components ?? []).compactMap { component in
            switch component.kind {
            case .listItem(let value): ordinal = value; return nil
            case .orderedList:
                return ListDescriptor(identity: component.identity, format: .init(rawValue: "{decimal}."), start: ordinal)
            case .unorderedList:
                return ListDescriptor(identity: component.identity, format: .disc, start: ordinal)
            default: return nil
            }
        }
    }

    /// One editor's semantic list attributes. The native text storage retains
    /// assigned lists; weak references allow retired list identities to leave the
    /// registry without scanning unrelated document text. Descriptors also retain
    /// the canonical start for empty lists with no native backing character yet.
    @MainActor final class ListContext {
        fileprivate final class Attributes {
            let descriptor: ListDescriptor
            private weak var ordinary: NSTextList?
            private weak var checked: NSTextList?
            private weak var unchecked: NSTextList?

            init(_ descriptor: ListDescriptor) { self.descriptor = descriptor }
            var isInUse: Bool { ordinary != nil || checked != nil || unchecked != nil }

            func native(checked state: Bool?) -> NSTextList {
                let existing = state.map { $0 ? checked : unchecked } ?? ordinary
                if let existing { return existing }
                let marker = state.map { NSTextList.MarkerFormat(rawValue: $0 ? "☑" : "☐") } ?? descriptor.format
                let list = NSTextList(markerFormat: marker, options: 0)
                list.startingItemNumber = descriptor.start
                if let state {
                    if state { checked = list } else { unchecked = list }
                } else { ordinary = list }
                return list
            }
        }
        fileprivate var attributes: [Int: Attributes] = [:]

        func reset() { attributes.removeAll() }

        fileprivate func register(_ intent: PresentationIntent) {
            for descriptor in NativeProseCodec.listDescriptors(intent) where attributes[descriptor.identity] == nil {
                attributes[descriptor.identity] = Attributes(descriptor)
            }
        }

        /// Resolve only newly encountered identities against the complete
        /// canonical source. Stop at their first text occurrences, then consider
        /// empty items, whose smaller canonical ordinals can precede that text.
        /// Known identities never scan the rest of the document.
        @discardableResult
        func prepare(for piece: AttributedString, emptyBlocks: [RelayEmptyProseBlock],
                     canonical: AttributedString, canonicalEmptyBlocks: [RelayEmptyProseBlock]) -> Bool {
            let appearing = Set((piece.runs.flatMap { NativeProseCodec.listDescriptors($0.presentationIntent) } +
                emptyBlocks.flatMap { NativeProseCodec.listDescriptors($0.intent) }).map(\.identity))
            let requested = appearing.subtracting(attributes.keys)
            guard !requested.isEmpty else { return true }
            let emptyLists = canonicalEmptyBlocks.flatMap { NativeProseCodec.listDescriptors($0.intent) }
            let emptyIDs = Set(emptyLists.map(\.identity))
            attributes = attributes.filter {
                $0.value.isInUse || emptyIDs.contains($0.key) || appearing.contains($0.key)
            }
            var missing = requested
            var resolved: [Int: ListDescriptor] = [:]
            for run in canonical.runs {
                for descriptor in NativeProseCodec.listDescriptors(run.presentationIntent)
                    where missing.remove(descriptor.identity) != nil {
                    resolved[descriptor.identity] = descriptor
                }
                if missing.isEmpty { break }
            }
            for descriptor in emptyLists where requested.contains(descriptor.identity) {
                if resolved[descriptor.identity].map({ descriptor.start < $0.start }) ?? true {
                    resolved[descriptor.identity] = descriptor
                }
            }
            guard resolved.count == requested.count else { return false }
            for (identity, descriptor) in resolved { attributes[identity] = Attributes(descriptor) }
            return true
        }
    }

    private static func textLists(_ intent: PresentationIntent?, task: Bool? = nil,
                                  context: ListContext) -> [NSTextList] {
        var result: [NSTextList] = []
        for descriptor in listDescriptors(intent) {
            if context.attributes[descriptor.identity] == nil {
                context.attributes[descriptor.identity] = ListContext.Attributes(descriptor)
            }
            let checked = result.isEmpty ? task : nil
            result.append(context.attributes[descriptor.identity]!.native(checked: checked))
        }
        return Array(result.reversed())
    }

    static func attributed(_ value: AttributedString, emptyBlocks: [RelayEmptyProseBlock] = [],
                           tableCells: [RelayMarkCollaborativeProse.TableCell] = [],
                           callouts: [RelayMarkCollaborativeProse.Callout] = [],
                           questions: [RelayMarkCollaborativeProse.Question] = [],
                           taskItems: [RelayMarkCollaborativeProse.TaskItem] = [],
                           inlineAtoms: [RelayMarkCollaborativeProse.InlineAtom] = [],
                           blockAtoms: [RelayMarkCollaborativeProse.BlockAtom] = [],
                           authoredWidgets: [RelayMarkCollaborativeProse.AuthoredWidget] = [],
                           entityReferenceAtoms: [RelayMarkCollaborativeProse.EntityReferenceAtom] = [],
                           mediaAtoms: [RelayMarkCollaborativeProse.MediaAtom] = [],
                           suggestionAtoms: [RelayMarkCollaborativeProse.SuggestionAtom] = [],
                           mediaImages: RelayMarkImageStore? = nil,
                           startingAt base: Int = 0, inParagraphAt paragraphStart: Int? = nil,
                           listContext: ListContext? = nil) -> NSAttributedString {
        // Metadata is in paper offsets; `value` starts at `base`.
        func local(_ range: NSRange) -> NSRange { NSRange(location: range.location - base, length: range.length) }
        let result = NSMutableAttributedString(string: "")
        let taskStates = Dictionary(uniqueKeysWithValues: taskItems.map {
            ($0.firstParagraphRange.location, $0.checked)
        })
        // Task identity remains semantic metadata; native lists render its state.
        let taskRuns = Dictionary(uniqueKeysWithValues: taskItems.map { item in
            (item.firstParagraphRange.location, RelayTaskItemRun(entityID: item.entityID, checked: item.checked))
        })
        let lists = listContext ?? ListContext()
        // Seed list starts in document order, including empty first items.
        var listIntents: [(Int, PresentationIntent)] = []
        var offset = base
        for run in value.runs {
            if let intent = run.presentationIntent { listIntents.append((offset, intent)) }
            offset += String(value[run.range].characters).utf16.count
        }
        listIntents += emptyBlocks.map { ($0.offset, $0.intent) }
        func itemIdentity(_ intent: PresentationIntent) -> Int? {
            intent.components.first { if case .listItem = $0.kind { true } else { false } }?.identity
        }
        var firstParagraphByItem: [Int: Int] = [:]
        for (_, intent) in listIntents.sorted(by: { $0.0 < $1.0 }) {
            lists.register(intent)
            if let item = itemIdentity(intent), let paragraph = intent.components.first?.identity,
               firstParagraphByItem[item] == nil { firstParagraphByItem[item] = paragraph }
        }
        func paragraphLists(_ intent: PresentationIntent?, task: Bool?) -> [NSTextList] {
            guard let intent else { return [] }
            // TextKit lists are paragraph-based. A canonical item's later prose
            // remains ordinary paragraphs instead of acquiring false list numbers.
            if let item = itemIdentity(intent), firstParagraphByItem[item] != intent.components.first?.identity { return [] }
            return textLists(intent, task: task, context: lists)
        }
        // Every run of a task's first paragraph carries its metadata.
        var paragraphStart = paragraphStart ?? base
        for run in value.runs {
            if result.length > 0, (result.string as NSString).character(at: result.length - 1) == 10 {
                paragraphStart = base + result.length
            }
            let intent = run.inlinePresentationIntent ?? []
            let offered = run[RelayMarkOfferedMarksAttribute.self] ?? []
            var size: CGFloat = 15
            var heading = false
            var code = intent.contains(.code)
            for component in run.presentationIntent?.components ?? [] {
                if case .header(let level) = component.kind { size = level == 1 ? 28 : level == 2 ? 23 : 19; heading = true }
                if case .codeBlock = component.kind { code = true }
            }
            let bold = heading || intent.contains(.stronglyEmphasized), italic = intent.contains(.emphasized)
            #if os(macOS)
            var font = code ? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular) : NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            #else
            var font = code ? UIFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular) : UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            if italic, let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) { font = UIFont(descriptor: descriptor, size: size) }
            font = UIFontMetrics(forTextStyle: .body).scaledFont(for: font)
            #endif
            var attrs: [NSAttributedString.Key: Any] = [.font: font,
                .relayBold: bold, .relayItalic: italic, .foregroundColor: PlatformColor.labelColorCompat]
            // Block separators carry no inline intent. Preserve absence rather
            // than turning an unchanged native roundtrip into a different baseline.
            if let originalIntent = run.inlinePresentationIntent { attrs[.relayIntent] = originalIntent }
            if let block = run.presentationIntent { attrs[.relayBlockIntent] = RelayBlockIntent(block) }
            if intent.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if !offered.isEmpty { attrs[.relayOfferedMarks] = offered }
            if offered.contains(.underline) { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if offered.contains(.highlight) { attrs[.backgroundColor] = PlatformColor.systemYellow.withAlphaComponent(0.25) }
            // Agent-written words read subdued, as on web, until a person edits them.
            if let run = run[RelayMarkAIAuthoredAttribute.self] {
                attrs[.relayAIAuthored] = run; attrs[.foregroundColor] = PlatformColor.secondaryLabelColorCompat
            }
            // A block separator belongs to no title; whichever paragraph a render reaches it from,
            // it stays unmarked.
            if let task = taskRuns[paragraphStart], run.inlinePresentationIntent != nil {
                attrs[.relayTaskItem] = task
                // Checked presentation does not introduce a canonical strike mark.
                if task.checked { attrs[.foregroundColor] = PlatformColor.secondaryLabelColorCompat }
            }
            if offered.contains(.subscript) || offered.contains(.superscript) {
                attrs[.font] = scriptFont(font, inferior: offered.contains(.subscript))
            }
            if let link = run.link { attrs[.link] = link }
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 5
            paragraph.textLists = paragraphLists(run.presentationIntent, task: taskStates[paragraphStart])
            if run.presentationIntent?.components.contains(where: { if case .blockQuote = $0.kind { true } else { false } }) == true {
                paragraph.headIndent = 18
                paragraph.firstLineHeadIndent = 18
            }
            attrs[.paragraphStyle] = paragraph
            let characters = String(value[run.range].characters)
            let thematicBreak = run.presentationIntent?.components.contains {
                if case .thematicBreak = $0.kind { true } else { false }
            } == true
            // Preserve the one-unit CRDT atom; never substitute visual dashes or a label.
            if thematicBreak && characters == "\u{FFFC}" {
                attrs[.attachment] = ThematicBreakAttachment.shared
            }
            result.append(NSAttributedString(string: characters, attributes: attrs))
        }
        // A paragraph has one native style, even when canonical inline runs and
        // their separator have different semantic attributes.
        let plain = result.string as NSString
        var paragraphOffset = 0
        while paragraphOffset < result.length {
            let range = plain.paragraphRange(for: NSRange(location: paragraphOffset, length: 0))
            if let style = result.attribute(.paragraphStyle, at: paragraphOffset, effectiveRange: nil) {
                result.addAttribute(.paragraphStyle, value: style, range: range)
            }
            paragraphOffset = NSMaxRange(range)
        }
        for block in emptyBlocks where block.offset - base >= 0 && block.offset - base < result.length {
            // Style the existing newline glyph only. Its semantic attributes stay
            // absent, preserving the exact canonical attributed-text roundtrip.
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 5
            paragraph.textLists = paragraphLists(block.intent, task: taskStates[block.offset])
            result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: block.offset - base, length: 1))
        }
        for cell in tableCells {
            let cellRange = local(cell.range)
            guard cell.columns > 0, cell.row >= 0, cell.column >= 0,
                  cell.rowSpan > 0, cell.columnSpan > 0,
                  cellRange.location >= 0, cellRange.length >= 0,
                  NSMaxRange(cellRange) <= result.length else { continue }
            let styledRange = cellRange.length > 0 ? cellRange :
                NSRange(location: cellRange.location, length: cellRange.location < result.length ? 1 : 0)
            guard styledRange.length > 0, let alignment = cell.alignment else { continue }
            let existing = result.attribute(.paragraphStyle, at: styledRange.location,
                effectiveRange: nil) as? NSParagraphStyle
            let paragraph = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            switch alignment {
            case "left": paragraph.alignment = .left
            case "center": paragraph.alignment = .center
            case "right": paragraph.alignment = .right
            default: break
            }
            result.addAttribute(.paragraphStyle, value: paragraph, range: styledRange)
        }
        for callout in callouts {
            let calloutRange = local(callout.range)
            guard calloutRange.location >= 0, calloutRange.length > 0,
                  NSMaxRange(calloutRange) <= result.length else { continue }
            result.addAttribute(.relayBlockBackground, value: PlatformColor.systemYellow.withAlphaComponent(
                callout.emphasis == "strong" ? 0.22 : 0.10), range: calloutRange)
        }
        // Native text backgrounds retain grouping without a parallel block renderer.
        for question in questions {
            let range = local(question.range)
            guard range.location >= 0, range.length > 0, NSMaxRange(range) <= result.length else { continue }
            result.addAttribute(.relayBlockBackground, value: PlatformColor.secondaryLabelColorCompat.withAlphaComponent(0.08), range: range)
        }
        for atom in inlineAtoms where atom.range.length == 1 && local(atom.range).location >= 0 &&
            NSMaxRange(local(atom.range)) <= result.length &&
            (result.string as NSString).substring(with: local(atom.range)) == "\u{FFFC}" {
            // The one-unit text map remains canonical. Identity, source and XML
            // path stay on the projection, outside TextKit's attributed storage.
            let font = result.attribute(.font, at: local(atom.range).location, effectiveRange: nil) as? PlatformFont
                ?? PlatformFont.systemFont(ofSize: 13)
            result.addAttribute(.attachment, value: InlineAtomAttachment.attachment(
                label: atom.label, kind: atom.kind, font: font), range: local(atom.range))
        }
        for atom in blockAtoms where atom.range.length == 1 && local(atom.range).location >= 0 &&
            NSMaxRange(local(atom.range)) <= result.length &&
            (result.string as NSString).substring(with: local(atom.range)) == "\u{FFFC}" {
            let font = result.attribute(.font, at: local(atom.range).location, effectiveRange: nil) as? PlatformFont
                ?? PlatformFont.systemFont(ofSize: 13)
            result.addAttribute(.attachment, value: PaperControlAttachment.attachment(
                atom: atom, font: font), range: local(atom.range))
        }
        for widget in authoredWidgets where (widget.kind == .dataView || widget.kind == .directive) &&
            widget.range.length == 1 && local(widget.range).location >= 0 && NSMaxRange(local(widget.range)) <= result.length &&
            (result.string as NSString).substring(with: local(widget.range)) == "\u{FFFC}" {
            let attributes = (try? JSONSerialization.jsonObject(with: widget.attributes)) as? [String: Any] ?? [:]
            let title = attributes["title"] as? String ?? attributes["label"] as? String ?? attributes["source"] as? String
                ?? String(widget.nodeName.dropFirst("relay".count))
            let font = result.attribute(.font, at: local(widget.range).location, effectiveRange: nil) as? PlatformFont
                ?? PlatformFont.systemFont(ofSize: 13)
            result.addAttribute(.attachment, value: InlineAtomAttachment.attachment(title: title,
                description: widget.kind == .dataView ? String(localized: "Data view", bundle: .module, comment: "VoiceOver description of an embedded data view.") : String(localized: "Authored widget", bundle: .module, comment: "VoiceOver description of an embedded authored widget."), font: font), range: local(widget.range))
        }
        for atom in entityReferenceAtoms where atom.range.length == 1 && local(atom.range).location >= 0 &&
            NSMaxRange(local(atom.range)) <= result.length &&
            (result.string as NSString).substring(with: local(atom.range)) == "\u{FFFC}" {
            let font = result.attribute(.font, at: local(atom.range).location, effectiveRange: nil) as? PlatformFont
                ?? PlatformFont.systemFont(ofSize: 13)
            let title = String(localized: "Reference: \(atom.label)", bundle: .module, comment: "Text and VoiceOver label of a block reference chip; the placeholder is the referenced item's title.")
            result.addAttribute(.attachment, value: InlineAtomAttachment.attachment(
                title: title, description: title, font: font), range: local(atom.range))
        }
        for atom in mediaAtoms where atom.range.length == 1 && local(atom.range).location >= 0 &&
            NSMaxRange(local(atom.range)) <= result.length &&
            (result.string as NSString).substring(with: local(atom.range)) == "\u{FFFC}" {
            let font = result.attribute(.font, at: local(atom.range).location, effectiveRange: nil) as? PlatformFont
                ?? PlatformFont.systemFont(ofSize: 13)
            let image = atom.kind == .image ? mediaImages?.image(for: atom.source) : nil
            result.addAttribute(.attachment, value: MediaAtomAttachment.attachment(
                atom: atom, font: font, image: image), range: local(atom.range))
        }
        for atom in suggestionAtoms where atom.range.length == 1 && local(atom.range).location >= 0 &&
            NSMaxRange(local(atom.range)) <= result.length &&
            (result.string as NSString).substring(with: local(atom.range)) == "\u{FFFC}" {
            let font = result.attribute(.font, at: local(atom.range).location, effectiveRange: nil) as? PlatformFont
                ?? PlatformFont.systemFont(ofSize: 13)
            result.addAttribute(.attachment, value: AgentSuggestionAttachment.attachment(
                atom: atom, font: font), range: local(atom.range))
        }
        resolveBackgrounds(in: result)
        return result
    }

    /// The paper as the editor shows it: each table is one attachment character
    /// whose cells hold their own text. `tables` supplies the attachment of a table
    /// identity, so an unchanged table keeps its attachment and grid.
    static func viewText(_ value: AttributedString, emptyBlocks: [RelayEmptyProseBlock] = [],
                         tableCells: [RelayMarkCollaborativeProse.TableCell] = [],
                         callouts: [RelayMarkCollaborativeProse.Callout] = [],
                         questions: [RelayMarkCollaborativeProse.Question] = [],
                         taskItems: [RelayMarkCollaborativeProse.TaskItem] = [],
                         inlineAtoms: [RelayMarkCollaborativeProse.InlineAtom] = [],
                         blockAtoms: [RelayMarkCollaborativeProse.BlockAtom] = [],
                         authoredWidgets: [RelayMarkCollaborativeProse.AuthoredWidget] = [],
                         entityReferenceAtoms: [RelayMarkCollaborativeProse.EntityReferenceAtom] = [],
                         mediaAtoms: [RelayMarkCollaborativeProse.MediaAtom] = [],
                         suggestionAtoms: [RelayMarkCollaborativeProse.SuggestionAtom] = [],
                         mediaImages: RelayMarkImageStore? = nil, startingAt base: Int = 0,
                         listContext: ListContext? = nil,
                         tables: (Int, Int, [RelayTableCellModel]) -> RelayTableAttachment) -> (text: NSAttributedString, spans: [RelayTableSpan]) {
        let full = attributed(value, emptyBlocks: emptyBlocks, tableCells: tableCells, callouts: callouts,
            questions: questions, taskItems: taskItems,
            inlineAtoms: inlineAtoms, blockAtoms: blockAtoms, authoredWidgets: authoredWidgets,
            entityReferenceAtoms: entityReferenceAtoms, mediaAtoms: mediaAtoms, suggestionAtoms: suggestionAtoms,
            mediaImages: mediaImages, startingAt: base, listContext: listContext)
        guard !tableCells.isEmpty else { return (full, []) }
        let groups = tableModels(tableCells, in: full, base: base)
        guard !groups.isEmpty else { return (full, []) }
        let result = NSMutableAttributedString()
        var spans: [RelayTableSpan] = [], copied = 0
        for group in groups {
            let local = NSRange(location: group.range.location - base, length: group.range.length)
            result.append(full.attributedSubstring(from: NSRange(location: copied, length: local.location - copied)))
            let table = tables(group.identity, group.range.location, group.cells)
            // Spans are relative to this rendered piece; its caller applies the view offset once.
            spans.append(RelayTableSpan(view: result.length, table: table))
            result.append(NSAttributedString(string: "\u{FFFC}", attributes: tableAttributes(table)))
            copied = NSMaxRange(local)
        }
        result.append(full.attributedSubstring(from: NSRange(location: copied, length: full.length - copied)))
        return (result, spans)
    }

    /// Each table's cells, with each cell's paragraphs together, in paper order.
    /// Cell ranges are relative to the table's first offset.
    static func tableModels(_ cells: [RelayMarkCollaborativeProse.TableCell], in rendered: NSAttributedString,
                            base: Int) -> [(identity: Int, range: NSRange, cells: [RelayTableCellModel])] {
        var groups: [(identity: Int, range: NSRange, cells: [RelayTableCellModel])] = []
        var paper: [[NSRange]] = []
        for cell in cells.sorted(by: { $0.range.location < $1.range.location }) {
            let local = NSRange(location: cell.range.location - base, length: cell.range.length)
            guard local.location >= 0, NSMaxRange(local) <= rendered.length else { continue }
            if groups.last?.identity != cell.tableIdentity {
                groups.append((cell.tableIdentity, cell.range, [])); paper.append([])
            }
            let index = groups.count - 1
            groups[index].range = NSUnionRange(groups[index].range, cell.range)
            if let last = groups[index].cells.indices.last, groups[index].cells[last].row == cell.row,
               groups[index].cells[last].column == cell.column {
                paper[index][last] = NSUnionRange(paper[index][last], cell.range)
            } else {
                groups[index].cells.append(RelayTableCellModel(row: cell.row, column: cell.column, rowSpan: max(1, cell.rowSpan),
                    columnSpan: max(1, cell.columnSpan), header: cell.header, columnWidths: cell.columnWidths,
                    range: cell.range, text: NSAttributedString()))
                paper[index].append(cell.range)
            }
        }
        for index in groups.indices {
            let start = groups[index].range.location
            for (cellIndex, range) in paper[index].enumerated() {
                groups[index].cells[cellIndex].range = NSRange(location: range.location - start, length: range.length)
                groups[index].cells[cellIndex].text = rendered.attributedSubstring(from: NSRange(location: range.location - base, length: range.length))
            }
        }
        return groups
    }

    /// Apple's Vertical Position feature selects the font's own script glyphs.
    /// Unsupported glyphs keep their ordinary native form; no offset or size is synthesized.
    /// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM09/AppendixF.html
    private static func scriptFont(_ font: PlatformFont, inferior: Bool) -> PlatformFont {
        let selector = inferior ? kInferiorsSelector : kSuperiorsSelector
        #if os(macOS)
        let feature: [NSFontDescriptor.FeatureKey: Int] = [
            .typeIdentifier: kVerticalPositionType, .selectorIdentifier: selector
        ]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: [feature]])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        #else
        let feature: [UIFontDescriptor.FeatureKey: Int] = [
            .type: kVerticalPositionType, .selector: selector
        ]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: [feature]])
        return UIFont(descriptor: descriptor, size: font.pointSize)
        #endif
    }

    static func tableAttributes(_ table: RelayTableAttachment) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 5
        return [.attachment: table, .font: PlatformFont.systemFont(ofSize: 15), .paragraphStyle: paragraph]
    }

    /// Renders `range` of the session text into `old` of a view showing the
    /// text before a leaf-only change. A leaf lies inside one block, so its
    /// rendered block style, including table and callout presentation, carries over.
    static func splice(_ storage: NSTextStorage, replacing old: NSRange, with value: AttributedString, range: NSRange,
                       taskItems: [RelayMarkCollaborativeProse.TaskItem], listContext: ListContext? = nil) -> Bool {
        guard old.location >= 0, old.length > 0, NSMaxRange(old) <= storage.length,
              let bounds = Range(range, in: value),
              let paragraph = storage.attribute(.paragraphStyle, at: old.location, effectiveRange: nil) else { return false }
        let piece = NSMutableAttributedString(attributedString: attributed(AttributedString(value[bounds]),
            taskItems: taskItems, startingAt: range.location, inParagraphAt: taskParagraph(containing: range, taskItems), listContext: listContext))
        piece.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: piece.length))
        for key in blockKeys where key != .paragraphStyle {
            if let value = storage.attribute(key, at: old.location, effectiveRange: nil) {
                piece.addAttribute(key, value: value, range: NSRange(location: 0, length: piece.length))
            }
        }
        resolveBackgrounds(in: piece)
        storage.replaceCharacters(in: old, with: piece)
        return true
    }

    /// Presentation that belongs to a whole block, carried over by leaf edits.
    static let blockKeys: [NSAttributedString.Key] = [.paragraphStyle, .relayBlockBackground]

    /// Inline highlights take precedence over block tint. Keeping the two inputs
    /// separate lets leaf edits remove a highlight without erasing its callout.
    private static func backgroundColor(for attributes: [NSAttributedString.Key: Any]) -> PlatformColor? {
        if (attributes[.relayOfferedMarks] as? Set<RelayMarkOfferedMark>)?.contains(.highlight) == true {
            return PlatformColor.systemYellow.withAlphaComponent(0.25)
        }
        return attributes[.relayBlockBackground] as? PlatformColor
    }

    private static func resolveBackgrounds(in text: NSMutableAttributedString) {
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            if let color = backgroundColor(for: attributes) {
                text.addAttribute(.backgroundColor, value: color, range: range)
            } else {
                text.removeAttribute(.backgroundColor, range: range)
            }
        }
    }

    private static func taskParagraph(containing range: NSRange, _ taskItems: [RelayMarkCollaborativeProse.TaskItem]) -> Int? {
        taskItems.first { $0.firstParagraphRange.location <= range.location &&
            NSMaxRange($0.firstParagraphRange) >= NSMaxRange(range) }?.firstParagraphRange.location
    }

    /// Gives characters TextKit just typed their canonical rendering from the
    /// session text. TextKit's typing attributes can differ, for example past a
    /// link's end; the paragraph style stays TextKit's, which keeps it uniform.
    /// `paper` is where the characters are in `value`, when `range` in the view differs.
    static func restyle(_ storage: NSTextStorage, range: NSRange, paper: Int? = nil, from value: AttributedString,
                        taskItems: [RelayMarkCollaborativeProse.TaskItem], listContext: ListContext? = nil) {
        let source = NSRange(location: paper ?? range.location, length: range.length)
        guard range.length > 0, NSMaxRange(range) <= storage.length, let bounds = Range(source, in: value) else { return }
        let piece = attributed(AttributedString(value[bounds]), taskItems: taskItems, startingAt: source.location,
                               inParagraphAt: taskParagraph(containing: source, taskItems), listContext: listContext)
        guard piece.length == range.length else { return }
        let text = storage.string as NSString
        /// Block presentation comes from the paragraph's own untouched text,
        /// not from typing attributes TextKit took from a neighbouring block.
        func blockSource(_ location: Int) -> Int {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            let separator = NSMaxRange(paragraph) - 1
            let content = separator >= paragraph.location && text.character(at: separator) == 10 ? separator : NSMaxRange(paragraph)
            for candidate in [paragraph.location, content - 1] where candidate >= paragraph.location && candidate < content &&
                !NSLocationInRange(candidate, range) { return candidate }
            return location
        }
        storage.beginEditing()
        defer { storage.endEditing() }
        piece.enumerateAttributes(in: NSRange(location: 0, length: piece.length)) { attributes, run, _ in
            let target = NSRange(location: range.location + run.location, length: run.length)
            var attributes = attributes
            let anchor = blockSource(target.location)
            for key in blockKeys { attributes[key] = storage.attribute(key, at: anchor, effectiveRange: nil) }
            attributes[.backgroundColor] = backgroundColor(for: attributes)
            storage.setAttributes(attributes, range: target)
        }
    }

    /// Empty paragraphs use the same native paragraph/list representation as text.
    static func emptyParagraphStyle(_ intent: PresentationIntent, checked: Bool?, listContext: ListContext? = nil) -> NSParagraphStyle? {
        let context = listContext ?? ListContext()
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 5
        style.textLists = textLists(intent, task: checked, context: context)
        return style
    }

    static func emptyAttributes(_ intent: PresentationIntent, inlineIntent: InlinePresentationIntent = [], link: URL? = nil, typingStyle: AttributedString? = nil, listContext: ListContext? = nil) -> [NSAttributedString.Key: Any] {
        var sample = typingStyle ?? AttributedString("x")
        sample.presentationIntent = intent
        if typingStyle == nil { sample.inlinePresentationIntent = inlineIntent; sample.link = link }
        return attributed(sample, listContext: listContext).attributes(at: 0, effectiveRange: nil)
    }

    /// TextKit may substitute AppleColorEmoji without bold/italic font traits.
    /// Ordinary typing/IME keeps stored semantic intent; only an explicit native
    /// font command should interpret a rendered font change as a mark change.
    static func value(_ source: NSAttributedString, inferFontChanges: Bool = true) -> AttributedString {
        var result = AttributedString()
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, range, _ in
            var part = AttributedString((source.string as NSString).substring(with: range))
            var intent = attributes[.relayIntent] as? InlinePresentationIntent ?? []
            if inferFontChanges, let font = attributes[.font] as? PlatformFont {
                let actual = traits(font)
                if actual.bold != (attributes[.relayBold] as? Bool ?? false) {
                    if actual.bold { intent.insert(.stronglyEmphasized) } else { intent.remove(.stronglyEmphasized) }
                }
                if actual.italic != (attributes[.relayItalic] as? Bool ?? false) {
                    if actual.italic { intent.insert(.emphasized) } else { intent.remove(.emphasized) }
                }
            }
            if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { intent.insert(.strikethrough) } else { intent.remove(.strikethrough) }
            if attributes[.relayIntent] != nil || !intent.isEmpty { part.inlinePresentationIntent = intent }
            var offered = attributes[.relayOfferedMarks] as? Set<RelayMarkOfferedMark> ?? []
            if inferFontChanges, attributes[.relayOfferedMarks] == nil,
               (attributes[.underlineStyle] as? Int ?? 0) != 0 { offered.insert(.underline) }
            if !offered.isEmpty { part[RelayMarkOfferedMarksAttribute.self] = offered }
            if let run = attributes[.relayAIAuthored] as? String { part[RelayMarkAIAuthoredAttribute.self] = run }
            if let link = attributes[.link] as? URL { part.link = link }
            if let link = attributes[.link] as? String { part.link = URL(string: link) }
            part.presentationIntent = (attributes[.relayBlockIntent] as? RelayBlockIntent)?.intent
            result.append(part)
        }
        return result
    }
}

/// A block intent compared by its whole chain. Foundation uniques attribute
/// dictionaries process-wide and NSPresentationIntent equality ignores parents,
/// so a bare intent can come back with another list's parents.
final class RelayBlockIntent: NSObject {
    let intent: PresentationIntent
    init(_ intent: PresentationIntent) { self.intent = intent }
    override func isEqual(_ object: Any?) -> Bool { (object as? RelayBlockIntent)?.intent == intent }
    override var hash: Int { intent.hashValue }
    override var description: String { String(describing: intent) }
}

/// Display only: the projector retains identity and the editor rejects atom replacement.
@MainActor
private enum InlineAtomAttachment {
    private static let cache: NSCache<NSString, NSTextAttachment> = {
        let cache = NSCache<NSString, NSTextAttachment>()
        cache.countLimit = 256
        return cache
    }()

    static func attachment(label: String, kind: RelayMarkCollaborativeProse.InlineAtom.Kind,
                           font: PlatformFont) -> NSTextAttachment {
        let title = kind == .relayTag ? label : "@\(label)"
        return attachment(title: title,
            description: kind == .relayTag ? String(localized: "Tag \(label)", bundle: .module, comment: "VoiceOver label of a tag chip; the placeholder is the tag.") : String(localized: "Reference \(label)", bundle: .module, comment: "VoiceOver label of an inline reference chip; the placeholder is the referenced item's title."), font: font)
    }

    static func attachment(title: String, description: String, font: PlatformFont) -> NSTextAttachment {
        let visible = title.count > 80 ? String(title.prefix(79)) + "…" : title
        #if os(macOS)
        let appearance = "dynamic"
        #else
        let appearance = String(UITraitCollection.current.userInterfaceStyle.rawValue)
        #endif
        let key = "\(description):\(title):\(font.fontName):\(font.pointSize):\(appearance)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let attachment = RelayPresentationAttachment(label: title, content: AnyView(
            Text(visible)
                .font(Font(font))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityLabel(description)
        ))
        cache.setObject(attachment, forKey: key)
        return attachment
    }
}

@MainActor
private enum PaperControlAttachment {
    static func attachment(atom: RelayMarkCollaborativeProse.BlockAtom,
                           font: PlatformFont) -> NSTextAttachment {
        let title: String
        switch atom.control {
        case .button: title = String(localized: "Button: \(atom.displayLabel)", bundle: .module, comment: "Paper control chip; the placeholder is the button's label.")
        case .anchor: title = String(localized: "Anchor: \(atom.displayLabel)", bundle: .module, comment: "Paper control chip; the placeholder is the anchor's name.")
        case .connection: title = String(localized: "Connection: \(atom.displayLabel)", bundle: .module, comment: "Paper control chip; the placeholder is the connection's label.")
        }
        // The control is an authored declaration. Clicking or executing it is a
        // separate host action, never a TextKit or CRDT side effect.
        return InlineAtomAttachment.attachment(title: title, description: title, font: font)
    }
}

@MainActor
private enum AgentSuggestionAttachment {
    static func attachment(atom: RelayMarkCollaborativeProse.SuggestionAtom,
                           font: PlatformFont) -> NSTextAttachment {
        let preview = atom.content.replacingOccurrences(of: "\n", with: " ")
        let title = String(localized: "Suggestion (\(atom.kind)): \(preview)", bundle: .module, comment: "Agent suggestion chip; the placeholders are the suggestion kind and its text.")
        let description = String(localized: "Agent suggestion, \(atom.review), \(atom.kind). \(atom.content)", bundle: .module, comment: "VoiceOver description of an agent suggestion: review state, kind, then its text.")
        // The authored Markdown stays on the Yrs atom. This preview never
        // converts an Accept or Dismiss tap into a CRDT or domain action.
        return InlineAtomAttachment.attachment(title: title, description: description, font: font)
    }
}

/// Accessible fallback until the app resolves authorized media for the same editor.
@MainActor
enum MediaAtomAttachment {
    private static let images: NSCache<NSString, NSTextAttachment> = {
        let cache = NSCache<NSString, NSTextAttachment>()
        cache.countLimit = 64
        return cache
    }()

    static func attachment(atom: RelayMarkCollaborativeProse.MediaAtom, font: PlatformFont,
                           image: PlatformImage?) -> NSTextAttachment {
        guard let image, image.size.width > 0, image.size.height > 0 else { return attachment(atom: atom, font: font) }
        // Reuse one attachment per displayed image so unchanged text stays equal.
        let key = [atom.id, atom.source, String(ObjectIdentifier(image).hashValue),
            String(describing: atom.width), String(describing: atom.height),
            String(describing: atom.alt), String(describing: atom.title)].description as NSString
        if let cached = images.object(forKey: key) { return cached }
        var size = image.size
        if let width = atom.width { size.width = CGFloat(width) }
        if let height = atom.height { size.height = CGFloat(height) }
        if atom.width != nil && atom.height == nil { size.height = size.width * image.size.height / image.size.width }
        if atom.height != nil && atom.width == nil { size.width = size.height * image.size.width / image.size.height }
        // Bound presentation only; the authored dimensions remain unchanged.
        let scale = min(1, 520 / size.width, 400 / size.height)
        let attachment = NSTextAttachment(data: nil, ofType: nil)
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
        #if os(macOS)
        if let described = image.copy() as? NSImage {
            described.accessibilityDescription = atom.alt.map { String(localized: "Image: \($0)", bundle: .module, comment: "VoiceOver label of an image; the placeholder is its alt text.") } ?? String(localized: "Image", bundle: .module, comment: "VoiceOver label of an image without alt text.")
            attachment.image = described
        }
        #else
        attachment.accessibilityLabel = atom.alt.map { String(localized: "Image: \($0)", bundle: .module, comment: "VoiceOver label of an image; the placeholder is its alt text.") } ?? String(localized: "Image", bundle: .module, comment: "VoiceOver label of an image without alt text.")
        #endif
        images.setObject(attachment, forKey: key)
        return attachment
    }

    static func attachment(atom: RelayMarkCollaborativeProse.MediaAtom,
                           font: PlatformFont) -> NSTextAttachment {
        let title: String
        let description: String
        switch atom.kind {
        case .image:
            title = atom.alt.map { String(localized: "Image: \($0)", bundle: .module, comment: "VoiceOver label of an image; the placeholder is its alt text.") } ?? String(localized: "Image", bundle: .module, comment: "VoiceOver label of an image without alt text.")
            description = title
        case .videoEmbed:
            title = String(localized: "Video", bundle: .module, comment: "Label of a video attachment in the paper.")
            description = String(localized: "Video attachment", bundle: .module, comment: "VoiceOver description of a video attachment.")
        }
        // Authenticated media retrieval and playback are host capabilities.
        // The authored source and ID remain in Yrs, not the TextKit attachment.
        return InlineAtomAttachment.attachment(title: title, description: description, font: font)
    }
}

/// Read-only projections use the label without changing canonical atom storage.
@MainActor
protocol RelayTextAttachmentLabel {
    var label: String { get }
}

/// TextKit places the attachment; SwiftUI measures and lays out its content.
@MainActor
private final class RelayPresentationAttachment: NSTextAttachment, RelayTextAttachmentLabel {
    let label: String
    let content: AnyView
    init(label: String, content: AnyView) {
        self.label = label
        self.content = content
        super.init(data: nil, ofType: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewProvider(for parentView: PlatformTableView?, location: any NSTextLocation,
                               textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let provider = RelayPresentationAttachmentProvider(textAttachment: self, parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager, location: location)
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

private final class RelayPresentationAttachmentProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let attachment = textAttachment as? RelayPresentationAttachment else { return }
        nonisolated(unsafe) let presentation = attachment
        view = MainActor.assumeIsolated { RelayHostingAttachmentView(rootView: presentation.content) }
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation,
                                   textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        if view == nil { loadView() }
        guard let host = view as? RelayHostingAttachmentView<AnyView> else { return .zero }
        // TextKit requests this UI view's fitting size on the main thread. The
        // framework override is nonisolated; capture only the actor-owned view.
        return MainActor.assumeIsolated {
            CGRect(origin: .zero, size: host.layout(width: proposedLineFragment.width))
        }
    }
}

@MainActor
private enum ThematicBreakAttachment {
    static let shared = RelayPresentationAttachment(label: String(localized: "Horizontal rule", bundle: .module,
        comment: "VoiceOver label for a horizontal rule in the paper."), content: AnyView(
        Divider()
            .padding(.vertical, 8)
            .accessibilityLabel(String(localized: "Horizontal rule", bundle: .module,
                comment: "VoiceOver label for a horizontal rule in the paper."))
    ))
}

private extension PlatformColor {
    /// A published collaborator color, as the host resolves it.
    static func collaborator(_ value: String, resolve: (String) -> Color) -> PlatformColor {
        PlatformColor(resolve(value))
    }
}

/// Native undo must target CRDT origins, never a second text-system history.
