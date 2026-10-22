import Foundation
import RelayMarkCollaboration
import UniformTypeIdentifiers
import RelayMarkProseProjection
import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
private typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformFont = UIFont
private typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
#endif

/// The images a host accepts from paste and drop, as pasteboard types.
struct RelayNativeImageRepresentation {
    var accepted: Set<String> = []
    var maximumBytes = 0
    var acceptedIdentifiers: [String] {
        accepted.sorted().flatMap {
            UTType.types(tag: $0, tagClass: .mimeType, conformingTo: .image).map(\.identifier)
        }
    }
    static func isImage(_ identifier: String) -> Bool { UTType(identifier)?.conforms(to: .image) == true }
    func mime(_ identifier: String) -> String? {
        guard let type = UTType(identifier), type.conforms(to: .image), let mime = type.preferredMIMEType,
              accepted.contains(mime)
        else { return nil }
        return mime
    }
    static func filename(_ suggested: String?, identifier: String) -> String {
        if let suggested, !suggested.isEmpty { return suggested }
        return "Clipboard image." + (UTType(identifier)?.preferredFilenameExtension ?? "image")
    }
}

private extension NSAttributedString.Key {
    static let relayIntent = NSAttributedString.Key("RelayInlineIntent")
    static let relayBlockIntent = NSAttributedString.Key("RelayBlockIntent")
    static let relayBold = NSAttributedString.Key("RelayRenderedBold")
    static let relayListMarker = NSAttributedString.Key("RelayListMarker")
    static let relayItalic = NSAttributedString.Key("RelayRenderedItalic")
    static let relayOfferedMarks = NSAttributedString.Key("RelayOfferedMarks")
    static let relayAIAuthored = NSAttributedString.Key("RelayAIAuthored")
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

    static func listMarker(_ intent: PresentationIntent?) -> (label: String, depth: Int)? {
        let components = intent?.components ?? []
        let depth = components.filter { component in
            if case .orderedList = component.kind { return true }
            if case .unorderedList = component.kind { return true }
            return false
        }.count
        guard depth > 0, let ordinal = components.compactMap({ component -> Int? in
            if case .listItem(let ordinal) = component.kind { return ordinal }; return nil
        }).first else { return nil }
        for component in components {
            if case .orderedList = component.kind { return ("\(ordinal).", depth) }
            if case .unorderedList = component.kind { return ("•", depth) }
        }
        return nil
    }

    static func attributed(_ value: AttributedString, emptyBlocks: [RelayEmptyProseBlock] = [],
                           tableCells: [RelayMarkCollaborativeProse.TableCell] = [],
                           callouts: [RelayMarkCollaborativeProse.Callout] = [],
                           taskItems: [RelayMarkCollaborativeProse.TaskItem] = [],
                           inlineAtoms: [RelayMarkCollaborativeProse.InlineAtom] = [],
                           blockAtoms: [RelayMarkCollaborativeProse.BlockAtom] = [],
                           authoredWidgets: [RelayMarkCollaborativeProse.AuthoredWidget] = [],
                           entityReferenceAtoms: [RelayMarkCollaborativeProse.EntityReferenceAtom] = [],
                           mediaAtoms: [RelayMarkCollaborativeProse.MediaAtom] = [],
                           suggestionAtoms: [RelayMarkCollaborativeProse.SuggestionAtom] = [],
                           mediaImages: RelayMarkImageStore? = nil,
                           startingAt base: Int = 0, inParagraphAt paragraphStart: Int? = nil) -> NSAttributedString {
        // Metadata is in paper offsets; `value` starts at `base`.
        func local(_ range: NSRange) -> NSRange { NSRange(location: range.location - base, length: range.length) }
        let result = NSMutableAttributedString(string: "")
        let taskMarkers = Dictionary(uniqueKeysWithValues: taskItems.map {
            ($0.firstParagraphRange.location, $0.checked ? "☑" : "☐")
        })
        // Every run of a task's first paragraph carries its marker, however the runs split.
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
            if offered.contains(.subscript) || offered.contains(.superscript) {
                attrs[.baselineOffset] = offered.contains(.subscript) ? -size * 0.25 : size * 0.35
                #if os(macOS)
                var scriptFont = NSFont.systemFont(ofSize: size * 0.8, weight: bold ? .bold : .regular)
                if italic { scriptFont = NSFontManager.shared.convert(scriptFont, toHaveTrait: .italicFontMask) }
                attrs[.font] = scriptFont
                #else
                var scriptFont = UIFont.systemFont(ofSize: size * 0.8, weight: bold ? .bold : .regular)
                if italic, let descriptor = scriptFont.fontDescriptor.withSymbolicTraits(scriptFont.fontDescriptor.symbolicTraits.union(.traitItalic)) {
                    scriptFont = UIFont(descriptor: descriptor, size: size * 0.8)
                }
                attrs[.font] = UIFontMetrics(forTextStyle: .body).scaledFont(for: scriptFont)
                #endif
            }
            if let link = run.link { attrs[.link] = link }
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 5
            if run.presentationIntent?.components.contains(where: { if case .listItem = $0.kind { true } else if case .blockQuote = $0.kind { true } else { false } }) == true {
                paragraph.headIndent = 18; paragraph.firstLineHeadIndent = 18
            }
            if let marker = listMarker(run.presentationIntent) {
                let label = taskMarkers[paragraphStart] ?? marker.label
                attrs[.relayListMarker] = label
                let width = (label as NSString).size(withAttributes: [.font: font]).width
                paragraph.headIndent = CGFloat(marker.depth - 1) * 24 + max(24, width + 10)
                paragraph.firstLineHeadIndent = paragraph.headIndent
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
        for block in emptyBlocks where block.offset - base >= 0 && block.offset - base < result.length {
            // Style the existing newline glyph only. Its semantic attributes stay
            // absent, preserving the exact canonical attributed-text roundtrip.
            if let paragraph = emptyAttributes(block.intent)[.paragraphStyle] {
                result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: block.offset - base, length: 1))
            }
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
            result.addAttribute(.relayCallout, value: RelayCalloutStyle(identity: callout.id.hashValue,
                tone: callout.tone, strong: callout.emphasis == "strong"), range: calloutRange)
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
        return result
    }

    /// The paper as the editor shows it: each table is one attachment character
    /// whose cells hold their own text. `tables` supplies the attachment of a table
    /// identity, so an unchanged table keeps its attachment and grid.
    static func viewText(_ value: AttributedString, emptyBlocks: [RelayEmptyProseBlock] = [],
                         tableCells: [RelayMarkCollaborativeProse.TableCell] = [],
                         callouts: [RelayMarkCollaborativeProse.Callout] = [],
                         taskItems: [RelayMarkCollaborativeProse.TaskItem] = [],
                         inlineAtoms: [RelayMarkCollaborativeProse.InlineAtom] = [],
                         blockAtoms: [RelayMarkCollaborativeProse.BlockAtom] = [],
                         authoredWidgets: [RelayMarkCollaborativeProse.AuthoredWidget] = [],
                         entityReferenceAtoms: [RelayMarkCollaborativeProse.EntityReferenceAtom] = [],
                         mediaAtoms: [RelayMarkCollaborativeProse.MediaAtom] = [],
                         suggestionAtoms: [RelayMarkCollaborativeProse.SuggestionAtom] = [],
                         mediaImages: RelayMarkImageStore? = nil, startingAt base: Int = 0,
                         tables: (Int, Int, [RelayTableCellModel]) -> RelayTableAttachment) -> (text: NSAttributedString, spans: [RelayTableSpan]) {
        let full = attributed(value, emptyBlocks: emptyBlocks, tableCells: tableCells, callouts: callouts, taskItems: taskItems,
            inlineAtoms: inlineAtoms, blockAtoms: blockAtoms, authoredWidgets: authoredWidgets,
            entityReferenceAtoms: entityReferenceAtoms, mediaAtoms: mediaAtoms, suggestionAtoms: suggestionAtoms,
            mediaImages: mediaImages, startingAt: base)
        guard !tableCells.isEmpty else { return (full, []) }
        let groups = tableModels(tableCells, in: full, base: base)
        guard !groups.isEmpty else { return (full, []) }
        let result = NSMutableAttributedString()
        var spans: [RelayTableSpan] = [], copied = 0
        for group in groups {
            let local = NSRange(location: group.range.location - base, length: group.range.length)
            result.append(full.attributedSubstring(from: NSRange(location: copied, length: local.location - copied)))
            let table = tables(group.identity, group.range.location, group.cells)
            spans.append(RelayTableSpan(view: base + result.length, table: table))
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

    static func tableAttributes(_ table: RelayTableAttachment) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 5
        return [.attachment: table, .font: PlatformFont.systemFont(ofSize: 15), .paragraphStyle: paragraph]
    }

    /// Renders `range` of the session text into `old` of a view showing the
    /// text before a leaf-only change. A leaf lies inside one block, so its
    /// rendered block style, including table and callout geometry, carries over.
    static func splice(_ storage: NSTextStorage, replacing old: NSRange, with value: AttributedString, range: NSRange,
                       taskItems: [RelayMarkCollaborativeProse.TaskItem]) -> Bool {
        guard old.location >= 0, old.length > 0, NSMaxRange(old) <= storage.length,
              let bounds = Range(range, in: value),
              let paragraph = storage.attribute(.paragraphStyle, at: old.location, effectiveRange: nil) else { return false }
        let piece = NSMutableAttributedString(attributedString: attributed(AttributedString(value[bounds]),
            taskItems: taskItems, startingAt: range.location, inParagraphAt: taskParagraph(containing: range, taskItems)))
        piece.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: piece.length))
        for key in blockKeys where key != .paragraphStyle {
            if let value = storage.attribute(key, at: old.location, effectiveRange: nil) {
                piece.addAttribute(key, value: value, range: NSRange(location: 0, length: piece.length))
            }
        }
        storage.replaceCharacters(in: old, with: piece)
        return true
    }

    /// Presentation that belongs to a whole block, carried over by leaf edits.
    static let blockKeys: [NSAttributedString.Key] = [.paragraphStyle, .relayCallout]

    private static func taskParagraph(containing range: NSRange, _ taskItems: [RelayMarkCollaborativeProse.TaskItem]) -> Int? {
        taskItems.first { $0.firstParagraphRange.location <= range.location &&
            NSMaxRange($0.firstParagraphRange) >= NSMaxRange(range) }?.firstParagraphRange.location
    }

    /// Gives characters TextKit just typed their canonical rendering from the
    /// session text. TextKit's typing attributes can differ, for example past a
    /// link's end; the paragraph style stays TextKit's, which keeps it uniform.
    /// `paper` is where the characters are in `value`, when `range` in the view differs.
    static func restyle(_ storage: NSTextStorage, range: NSRange, paper: Int? = nil, from value: AttributedString,
                        taskItems: [RelayMarkCollaborativeProse.TaskItem]) {
        let source = NSRange(location: paper ?? range.location, length: range.length)
        guard range.length > 0, NSMaxRange(range) <= storage.length, let bounds = Range(source, in: value) else { return }
        let piece = attributed(AttributedString(value[bounds]), taskItems: taskItems, startingAt: source.location,
                               inParagraphAt: taskParagraph(containing: source, taskItems))
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
            storage.setAttributes(attributes, range: target)
        }
    }

    static func emptyAttributes(_ intent: PresentationIntent, inlineIntent: InlinePresentationIntent = [], link: URL? = nil, typingStyle: AttributedString? = nil) -> [NSAttributedString.Key: Any] {
        var sample = typingStyle ?? AttributedString("x")
        sample.presentationIntent = intent
        if typingStyle == nil { sample.inlinePresentationIntent = inlineIntent; sample.link = link }
        return attributed(sample).attributes(at: 0, effectiveRange: nil)
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
        let size = (visible as NSString).size(withAttributes: [.font: font])
        let bounds = CGRect(x: 0, y: -3, width: ceil(size.width) + 14, height: max(20, ceil(size.height) + 5))
        let attachment = NSTextAttachment(data: nil, ofType: nil)
        attachment.bounds = bounds
        #if os(macOS)
        let image = NSImage(size: bounds.size, flipped: false) { rect in
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5).fill()
            NSColor.labelColor.set()
            (visible as NSString).draw(at: CGPoint(x: 7, y: (rect.height - size.height) / 2), withAttributes: [.font: font])
            return true
        }
        image.accessibilityDescription = description
        attachment.image = image
        #else
        let image = UIGraphicsImageRenderer(size: bounds.size).image { context in
            UIColor.systemFill.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: bounds.size), cornerRadius: 5).fill()
            UIColor.label.set()
            (visible as NSString).draw(at: CGPoint(x: 7, y: (bounds.height - size.height) / 2), withAttributes: [.font: font])
        }
        attachment.image = image
        attachment.accessibilityLabel = description
        #endif
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

/// Geometry follows the text container, including list indentation and window resizing.
@MainActor
private final class ThematicBreakAttachment: NSTextAttachment {
    static let shared: ThematicBreakAttachment = {
        let attachment = ThematicBreakAttachment(data: nil, ofType: nil)
        #if !os(macOS)
        attachment.accessibilityLabel = String(localized: "Horizontal rule", bundle: .module, comment: "VoiceOver label for a horizontal rule in the paper.")
        #endif
        return attachment
    }()

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation,
                                   textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, position: CGPoint) -> CGRect {
        let padding = textContainer?.lineFragmentPadding ?? 0
        return CGRect(x: 0, y: 0, width: max(1, lineFrag.width - max(padding, position.x - lineFrag.minX) - padding), height: 18)
    }

    override func image(for imageBounds: CGRect, attributes: [NSAttributedString.Key: Any],
                        location: any NSTextLocation, textContainer: NSTextContainer?) -> PlatformImage? {
        let size = CGSize(width: max(1, imageBounds.width), height: 18)
        #if os(macOS)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.separatorColor.setFill()
            NSBezierPath(rect: CGRect(x: 0, y: rect.midY, width: rect.width, height: 1)).fill()
            return true
        }
        image.accessibilityDescription = String(localized: "Horizontal rule", bundle: .module, comment: "VoiceOver label for a horizontal rule in the paper.")
        #else
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.separator.setFill()
            context.fill(CGRect(x: 0, y: size.height / 2, width: size.width, height: 1))
        }
        #endif
        return image
    }
}

private extension PlatformColor {
    static var labelColorCompat: PlatformColor {
        #if os(macOS)
        .labelColor
        #else
        .label
        #endif
    }
    static var secondaryLabelColorCompat: PlatformColor {
        #if os(macOS)
        .secondaryLabelColor
        #else
        .secondaryLabel
        #endif
    }
    /// A published collaborator color, as the host resolves it.
    static func collaborator(_ value: String, resolve: (String) -> Color) -> PlatformColor {
        PlatformColor(resolve(value))
    }
}

/// Native undo must target CRDT origins, never a second text-system history.
private final class CollaborationUndoManager: UndoManager, @unchecked Sendable {
    override init() { super.init(); disableUndoRegistration() }
    @MainActor var undoAction: (() -> Void)?
    @MainActor var redoAction: (() -> Void)?
    override var canUndo: Bool { true }
    override var canRedo: Bool { true }
    override func undo() { MainActor.assumeIsolated { undoAction?() } }
    override func redo() { MainActor.assumeIsolated { redoAction?() } }
}

#if os(macOS)
@MainActor
/// The paper's text view: TextKit 2 over one editor session.
public struct RelayMarkEditorView: NSViewRepresentable {
    typealias Session = RelayMarkEditorSession
    var session: Session
    var accessibilityLabel: String
    var services = RelayMarkEditorServices()

    public init(session: RelayMarkEditorSession, accessibilityLabel: String, services: RelayMarkEditorServices = .init()) {
        self.session = session; self.accessibilityLabel = accessibilityLabel; self.services = services
    }

    public func makeCoordinator() -> Coordinator { Coordinator(text: TextCoordinator(session: session)) }
    /// Owns the view's text system for SwiftUI; its members are internal.
    @MainActor public final class Coordinator {
        let text: TextCoordinator
        init(text: TextCoordinator) { self.text = text }
    }
    public func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.text.services = services
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = context.coordinator.text.makeTextView(accessibilityLabel: accessibilityLabel)
        return scroll
    }
    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        _ = services.imageStore?.revision
        context.coordinator.text.services = services
        if context.coordinator.text.session !== session {
            let previous = scroll.documentView as? CollaborationTextView
            let wasFocused = previous.map { $0.window?.firstResponder === $0 } ?? false
            if let previous { context.coordinator.text.retire(previous) }
            context.coordinator.text.session = session
            let replacement = context.coordinator.text.makeTextView(accessibilityLabel: accessibilityLabel)
            scroll.documentView = replacement
            if wasFocused { scroll.window?.makeFirstResponder(replacement) }
        } else if let view = scroll.documentView as? CollaborationTextView { context.coordinator.text.update(view) }
    }
    public static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let view = scroll.documentView as? CollaborationTextView { coordinator.text.retire(view) }
    }
    @MainActor final class TextCoordinator: NSObject, NSTextViewDelegate {
        /// The host's services; tests may set the closures below directly.
        var services = RelayMarkEditorServices() {
            didSet {
                mediaImages = services.imageStore
                onActivatePaperButton = services.paperControls.map { controls in { controls.activatePaperButton(id: $0) } }
                onActivateFragmentLink = services.links.map { links in { links.activateFragmentLink($0) } }
                onImageInputFailure = services.inputRefused
                onBeginImageInput = services.images.map { images in { images.beginImageInput(at: $0, filename: $1, contentType: $2) } }
                onBeginImageBatchInputs = services.images.map { images in { images.beginImageInputs(at: $0, files: $1) } }
                onBeginStructuredPaste = services.paste.map { paste in { paste.beginStructuredPaste(at: $0, itemCount: $1, plainText: $2) } }
            }
        }
        var mediaImages: RelayMarkImageStore? {
            get { editor.mediaImages }
            set { editor.mediaImages = newValue }
        }
        var onActivatePaperButton: ((String) -> Void)?
        var onActivateFragmentLink: ((String) -> Void)?
        var onImageInputFailure: ((String) -> Void)?
        var onBeginImageBatchInputs: ((NSRange, [RelayMarkImageFile]) -> [RelayMarkImageIntake]?)?
        var onBeginImageInput: ((NSRange, String, String) -> RelayMarkImageIntake?)?
        var onBeginStructuredPaste: ((NSRange, Int, String?) -> RelayMarkPasteIntake?)?
        let editor: RelayPaperEditor<Session>
        var session: Session {
            get { editor.session }
            set { editor.session = newValue }
        }
        var composition: Session.Composition? {
            get { editor.composition }
            set { editor.composition = newValue }
        }
        /// A keystroke inside one text leaf, applied without reading the whole paper.
        var pendingTyping: (range: NSRange, text: String)? { editor.pendingTyping.map { ($0.paper, $0.text) } }
        init(session: Session) { editor = RelayPaperEditor(session: session) }
        func makeTextView(accessibilityLabel: String) -> CollaborationTextView {
            let view = CollaborationTextView.textKit2()
            // Enable AppKit responder routing; the custom manager keeps only canonical history.
            view.allowsUndo = true
            view.editingSession = session
            apply(services, to: view)
            editor.attach(view)
            view.onImageInputFailure = { [weak self, weak view] message in
                guard let self, let view, view.editingSession === session, !session.isInvalidated else { return }
                onImageInputFailure?(message)
            }
            view.onBeginImageInput = { [weak self, weak view] range, filename, contentType in
                guard let self, let view, !view.retired, view.editingSession === session,
                      !session.isInvalidated, session.isEditable else { return nil }
                return onBeginImageInput?(view.paper.tables.paper(range), filename, contentType)
            }
            view.onBeginImageBatchInputs = { [weak self, weak view] range, files in
                guard let self, let view, !view.retired, view.editingSession === session,
                      !session.isInvalidated, session.isEditable else { return nil }
                return onBeginImageBatchInputs?(view.paper.tables.paper(range), files)
            }
            view.onBeginStructuredPaste = { [weak self, weak view] range, itemCount, plainText in
                guard let self, let view, !view.retired, view.editingSession === session,
                      !session.isInvalidated, session.isEditable else { return nil }
                return onBeginStructuredPaste?(view.paper.tables.paper(range), itemCount, plainText)
            }
            view.delegate = self
            view.onPaperButton = { [weak self, weak view] offset in
                guard let self, let view, view.editingSession === session, !session.isInvalidated,
                      let activate = onActivatePaperButton else { return false }
                let paper = view.paper.tables.paper(offset)
                guard let atom = session.nativeBlockAtoms.first(where: { $0.control == .button && NSLocationInRange(paper, $0.range) }) else { return false }
                activate(atom.id)
                return true
            }
            view.onCompositionStart = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                composition = try? session.beginComposition()
            }
            if let native = session as? RelayMarkEditorSession {
                view.onDeclaredMarkedInput = { [weak self, weak view, weak native] literal, replacement, selection, supplied, final in
                    guard let self, let view, let native, !view.retired, view.editingSession === session,
                          let token = self.composition as? RelayMarkEditorSession.Composition else { return false }
                    let tables = view.paper.tables
                    return native.declareMarkedInput(literal, replacement: tables.paper(replacement), selection: selection,
                        platform: .appKit, suppliedReplacement: supplied.map { $0.location == NSNotFound ? $0 : tables.paper($0) },
                        phase: final ? .final : .marked, from: token)
                }
            }
            view.onCompositionEnd = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                endComposition(view)
            }
            view.registerForDraggedTypes(Array(Set(view.registeredDraggedTypes + [.fileURL] +
                view.imagePolicy.acceptedIdentifiers.map { NSPasteboard.PasteboardType($0) })))
            view.isRichText = true; view.drawsBackground = false
            view.isVerticallyResizable = true; view.isHorizontallyResizable = false
            view.autoresizingMask = [.width]
            view.textContainer?.widthTracksTextView = true
            view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            // NSTextView's inset is the same on both sides: half the margins each,
            // and textContainerOrigin moves the container toward the trailing edge.
            view.textContainerInset = NSSize(width: (RelayPaperMargins.leading + RelayPaperMargins.trailing) / 2, height: 20)
            view.setAccessibilityLabel(accessibilityLabel)
            view.onSessionEdit = { [weak self, weak view] in
                guard let self, let view, !view.retired else { return }
                self.update(view)
            }
            session.onFocusRequest = { [weak self, weak view] in
                guard let self, let view else { return }
                takeFocusIfRequested(view)
            }
            view.onMovedToWindow = { [weak self, weak view] in
                guard let self, let view else { return }
                takeFocusIfRequested(view)
            }
            if let taskSession = session as? RelayMarkEditorSession {
                view.onTaskCheckbox = { [weak self, weak view] offset in
                    guard let self, let view, view.editingSession === session,
                          taskSession.toggleTaskItem(atUTF16: view.paper.tables.paper(offset)) else { return false }
                    self.update(view)
                    return true
                }
            }
            view.collaborationUndo.undoAction = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                session.undo(); self.update(view)
            }
            view.collaborationUndo.redoAction = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                session.redo(); self.update(view)
            }
            view.finalizerRegistration = session.registerNativeCompositionFinalizer({ [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                try finishComposition(view)
            }, refresh: { [weak self, weak view] in
                guard let self, let view, !view.retired, view.editingSession === session else { return }
                self.update(view)
            })
            update(view)
            return view
        }
        func finishComposition(_ view: CollaborationTextView) throws { try editor.finishComposition(view) }
        func retire(_ view: CollaborationTextView) {
            guard !view.retired else { return }
            editor.updating = true
            defer { editor.updating = false }
            if view.editingSession === session, session.isEditable { try? finishComposition(view) }
            if let composition, view.editingSession === session { session.cancelComposition(composition) }
            composition = nil
            if let registration = view.finalizerRegistration { view.editingSession?.unregisterNativeCompositionFinalizer(registration) }
            view.finalizerRegistration = nil
            view.retireInput()
            view.delegate = nil
            view.unmarkText()
            view.isEditable = false
            if view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
            view.textStorage?.setAttributedString(NSAttributedString(string: ""))
            view.paper.tables = RelayTableSpans(); view.paper.tableAttachments = [:]
            view.setSelectedRange(NSRange(location: 0, length: 0))
            view.paper.remoteSelections = []
            view.unlinkPreviousTextElement()
            if view.editingSession === session { session.onFocusRequest = nil }
            view.editingSession = nil
        }
        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            guard let view = view as? CollaborationTextView, !view.retired else { return menu }
            let entries = view.sectionMenuEntries(link: services.sectionLink)
            guard !entries.isEmpty else { return menu }
            menu.insertItem(.separator(), at: 0)
            for entry in entries.reversed() { menu.insertItem(RelayMenuAction.item(entry.title, entry.run), at: 0) }
            return menu
        }
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let href = (link as? URL)?.absoluteString ?? (link as? String), href.hasPrefix("#"),
                  let activate = onActivateFragmentLink,
                  let view = textView as? CollaborationTextView, !view.retired,
                  view.editingSession === session, !session.isInvalidated else { return false }
            activate(href)
            update(view)
            return true
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !editor.updating, let view = textView as? CollaborationTextView, !view.retired,
                view.editingSession == nil || view.editingSession === session else { return false }
            // A formatting-only callback (no replacement string) keeps the pending keystroke.
            guard let replacementString else {
                return session.isEditable && NSMaxRange(affectedCharRange) <= view.viewLength
            }
            return editor.shouldChange(view, range: affectedCharRange, replacement: replacementString, pasting: false)
        }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? CollaborationTextView else { return }
            editor.didChange(view)
        }
        func endComposition(_ view: CollaborationTextView) {
            guard !editor.updating, !view.retired, composition != nil, !view.hasMarkedText(),
                view.editingSession == nil || view.editingSession === session else { return }
            textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        }
        /// Writing Tools rewrites the paper's prose; each table cell is its own text view.
        func textView(_ textView: NSTextView, writingToolsIgnoredRangesInEnclosingRange enclosingRange: NSRange) -> [NSValue] {
            guard let view = textView as? CollaborationTextView else { return [] }
            return view.paper.tables.spans.filter { NSLocationInRange($0.view, enclosingRange) }
                .map { NSValue(range: NSRange(location: $0.view, length: 1)) }
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? CollaborationTextView else { return }
            editor.selectionDidChange(view)
        }
        func update(_ view: CollaborationTextView) {
            apply(services, to: view)
            editor.update(view)
        }
        /// The host asked for focus in the paper: the view takes it, with the
        /// session's selection, once it is in a window.
        func takeFocusIfRequested(_ view: CollaborationTextView) {
            guard session.focusRequest != nil, !view.retired, view.editingSession === session, let window = view.window else { return }
            session.focusRequest = nil
            update(view)
            window.makeFirstResponder(view)
        }
        private func apply(_ services: RelayMarkEditorServices, to view: CollaborationTextView) {
            view.imagePolicy = .init(accepted: services.images?.acceptedImageTypes ?? [],
                                     maximumBytes: services.images?.maximumImageBytes ?? 0)
            view.collaboratorColor = services.collaboratorColor
            view.selectionActions = services.selectionActions
            view.previousTextElement = services.previousTextElement
            view.linkPreviousTextElement()
        }
    }
}

/// A menu item that runs a closure.
@MainActor final class RelayMenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func perform(_ sender: Any?) { run() }
    static func item(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let action = RelayMenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(perform(_:)), keyEquivalent: "")
        item.target = action; item.representedObject = action
        return item
    }
}

@MainActor
final class CollaborationTextView: NSTextView, RelayPaperTextView, NSTextContentStorageDelegate {
    /// The host's image capability and collaborator colors, from its services.
    var imagePolicy = RelayNativeImageRepresentation()
    var collaboratorColor: (String) -> Color = RelayMarkEditorServices.hexColor
    /// The only way to make the editor: Relay's TextKit 2 stack. A subclass
    /// built with `init(frame:)` starts in TextKit 1 compatibility mode.
    static func textKit2(frame: CGRect = .zero) -> CollaborationTextView {
        let storage = NSTextContentStorage(), manager = RelayTextLayoutManager()
        storage.addTextLayoutManager(manager)
        let container = NSTextContainer(size: CGSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude))
        manager.textContainer = container
        let view = Self(frame: frame, textContainer: container)
        view.contentStorage = storage
        #if os(macOS)
        view.paper.disclosuresFollowPointer = true
        #endif
        // Folded sections' paragraphs are skipped from layout, never removed from the text.
        storage.delegate = view
        // A table's grid stays with its attachment, wherever its paragraph is laid out.
        view.register([.onScrollingOutOfViewport, .onEditingInlineParagraphs],
                      forTextAttachmentViewProviderType: RelayTableAttachmentViewProvider.self)
        #if DEBUG
        RelayTextKit1Guard.install()
        #endif
        return view
    }
    /// The view does not own its content storage; this keeps the stack alive.
    private var contentStorage: NSTextContentStorage?
    let paper = RelayPaperViewState()
    var paperStorage: NSTextStorage { textStorage ?? NSTextStorage() }
    var selectionActions: [RelayMarkSelectionAction] = []
    var viewSelections: [NSRange] { selectedRanges.map(\.rangeValue) }
    /// A Genmoji has no RelayMark node: inserted, it would be lost on the next render.
    override var supportsAdaptiveImageGlyph: Bool { get { false } set {} }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        (super.accessibilityCustomActions() ?? []) + paperAccessibilityActions().map { action in
            NSAccessibilityCustomAction(name: action.name) { action.perform() }
        }
    }
    var isPaperEditable: Bool {
        get { isEditable }
        set { isEditable = newValue }
    }
    var hasMarkedInput: Bool { hasMarkedText() }
    var viewSelection: NSRange { selectedRange() }
    func showSelection(_ range: NSRange) { setSelectedRange(range); scrollRangeToVisible(range) }
    func unmarkPaperText() { unmarkText() }
    func paperNeedsDisplay() { needsDisplay = true }
    func replaceAllText(_ text: NSAttributedString) {
        performPaperEdit { textStorage?.setAttributedString(text) }
    }
    func focus(_ cell: RelayTableCellTextView, selecting range: NSRange) {
        if NSMaxRange(range) <= cell.string.utf16.count, cell.selectedRange() != range { cell.setSelectedRange(range) }
        if let window, window.firstResponder === self { window.makeFirstResponder(cell) }
    }
    var tableUndoManager: UndoManager? { collaborationUndo }
    /// Find in paper searches the paper's text, table cells included.
    private(set) lazy var paperFinder = RelayPaperFinder(view: self)
    override func performTextFinderAction(_ sender: Any?) {
        guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag, let action = NSTextFinder.Action(rawValue: tag) else { return }
        paperFinder.finder.findBarContainer = enclosingScrollView
        paperFinder.finder.performAction(action)
    }
    /// Format menu actions with no mark in the paper. TextKit would apply them to the
    /// view alone and the next redraw would undo them, so they are disabled and refused.
    static let unsupportedFormatting: Set<Selector> = [
        #selector(underline(_:)), #selector(changeColor(_:)), #selector(changeAttributes(_:)),
        #selector(alignLeft(_:)), #selector(alignCenter(_:)), #selector(alignRight(_:)),
        #selector(alignJustified(_:)),
        #selector(superscript(_:)), #selector(NSTextView.`subscript`(_:)), #selector(unscript(_:)),
        #selector(raiseBaseline(_:)), #selector(lowerBaseline(_:)),
        #selector(useStandardKerning(_:)), #selector(turnOffKerning(_:)),
        #selector(tightenKerning(_:)), #selector(loosenKerning(_:)),
        #selector(useStandardLigatures(_:)), #selector(turnOffLigatures(_:)), #selector(useAllLigatures(_:)),
        #selector(pasteFont(_:)), #selector(pasteRuler(_:)),
        #selector(makeBaseWritingDirectionLeftToRight(_:)), #selector(makeBaseWritingDirectionRightToLeft(_:)),
        #selector(makeBaseWritingDirectionNatural(_:)), #selector(makeTextWritingDirectionLeftToRight(_:)),
        #selector(makeTextWritingDirectionRightToLeft(_:)), #selector(makeTextWritingDirectionNatural(_:)),
    ]
    override func underline(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func changeColor(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func changeAttributes(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func alignLeft(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func alignCenter(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func alignRight(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func alignJustified(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func superscript(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func `subscript`(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func unscript(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func raiseBaseline(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func lowerBaseline(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func useStandardKerning(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func turnOffKerning(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func tightenKerning(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func loosenKerning(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func useStandardLigatures(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func turnOffLigatures(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func useAllLigatures(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func pasteFont(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func pasteRuler(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func makeBaseWritingDirectionLeftToRight(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func makeBaseWritingDirectionRightToLeft(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func makeBaseWritingDirectionNatural(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func makeTextWritingDirectionLeftToRight(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func makeTextWritingDirectionRightToLeft(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func makeTextWritingDirectionNatural(_ sender: Any?) { RelayPaperRefusal.feedback() }
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if let action = item.action, Self.unsupportedFormatting.contains(action) { return false }
        if item.action == #selector(performTextFinderAction(_:)) {
            paperFinder.finder.findBarContainer = enclosingScrollView
            return NSTextFinder.Action(rawValue: item.tag).map { paperFinder.finder.validateAction($0) } ?? false
        }
        return super.validateUserInterfaceItem(item)
    }
    private func changeListDepth(backward: Bool) -> Bool {
        guard !retired, isEditable, !hasMarkedText(), compositionCompletion == nil,
              let session = editingSession, session.isEditable else { return false }
        session.setNativeSelection(paperSelection)
        return session.handleNativeListIndent(backward: backward)
    }
    override func insertTab(_ sender: Any?) {
        if !changeListDepth(backward: false) { super.insertTab(sender) }
    }
    /// At the text's start or end there is no character to remove, but the
    /// browser keymaps can still lift or join blocks there.
    private func deleteAtEdge(backward: Bool) -> Bool {
        let selection = selectedRange()
        guard !retired, isEditable, !hasMarkedText(), compositionCompletion == nil, selection.length == 0,
              backward ? selection.location == 0 : selection.location == viewLength,
              let session = editingSession, session.isEditable else { return false }
        session.setNativeSelection(paperSelection)
        return session.handleNativeEdgeDeletion(backward: backward)
    }
    override func deleteBackward(_ sender: Any?) {
        if !deleteAtEdge(backward: true) { super.deleteBackward(sender) }
    }
    override func deleteForward(_ sender: Any?) {
        if !deleteAtEdge(backward: false) { super.deleteForward(sender) }
    }
    /// Copy, drags and Services write a selection holding tables with each
    /// table as rows of tab-separated cells.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let visible = paper.tables.readable(paperStorage, range: selectedRange()) else {
            return super.writeSelection(to: pboard, types: types)
        }
        pboard.clearContents()
        return pboard.writeObjects([visible])
    }
    override func copy(_ sender: Any?) {
        guard paper.tables.readable(paperStorage, range: selectedRange()) != nil else { return super.copy(sender) }
        _ = writeSelection(to: copyPasteboard, types: writablePasteboardTypes)
    }
    /// Where Copy writes; tests use a private pasteboard.
    var copyPasteboard: NSPasteboard = .general
    override func insertBacktab(_ sender: Any?) {
        if !changeListDepth(backward: true) { super.insertBacktab(sender) }
    }
    var onPaperButton: ((Int) -> Bool)?
    var onTaskCheckbox: ((Int) -> Bool)?
    /// The session changed outside TextKit's own editing; the coordinator shows it.
    var onSessionEdit: (() -> Void)?
    /// The view entered a window, where it can take keyboard focus.
    var onMovedToWindow: (() -> Void)?
    /// The host's text read before the paper. The paper holds it weakly; the title
    /// holds the paper, so VoiceOver reads them as one shared text.
    var previousTextElement: (() -> AnyObject?)?
    override func accessibilitySharedTextUIElements() -> [Any]? {
        guard let previous = previousTextElement?() else { return super.accessibilitySharedTextUIElements() }
        return [previous, self]
    }
    func linkPreviousTextElement() {
        guard let title = previousTextElement?() as? NSView else { return }
        title.setAccessibilitySharedTextUIElements([title, self])
    }
    func unlinkPreviousTextElement() {
        guard let title = previousTextElement?() as? NSView,
              (title.accessibilitySharedTextUIElements() ?? []).contains(where: { $0 as AnyObject === self }) else { return }
        title.setAccessibilitySharedTextUIElements(nil)
    }
    /// The paper's leading margin is wider than its trailing one by the gutter. The
    /// symmetric inset already leaves the container its width; only its origin moves,
    /// so the container agrees with the view's width tracking and layout settles.
    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        return NSPoint(x: origin.x + (RelayPaperMargins.leading - RelayPaperMargins.trailing) / 2, y: origin.y)
    }
    /// The pointer adapter: the heading under the pointer shows its chevron.
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let geometry = RelayTextGeometry(textLayoutManager)
        let line = geometry?.paragraphRange(atY: point.y - textContainerOrigin.y)
        hoverHeading(line.flatMap { headingParagraph(at: $0.location)?.location })
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoverHeading(nil)
    }
    private func hoverHeading(_ location: Int?) {
        guard paper.hoveredHeading != location else { return }
        paper.hoveredHeading = location
        needsDisplay = true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onMovedToWindow?()
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !retired, !hasMarkedText(), let geometry = RelayTextGeometry(textLayoutManager),
           let id = sectionDisclosureHit(at: CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y), geometry: geometry) {
            toggleSection(id); return
        }
        if !retired, !hasMarkedText(), let onPaperButton,
           let offset = characterOffset(at: point), onPaperButton(offset) { return }
        if !retired, isEditable, !hasMarkedText(), let onTaskCheckbox,
           let offset = taskCheckboxOffset(at: point), onTaskCheckbox(offset) { return }
        super.mouseDown(with: event)
    }
    /// The UTF-16 offset of the character drawn under `point` in view coordinates.
    func characterOffset(at point: CGPoint) -> Int? {
        let origin = textContainerOrigin
        return RelayTextGeometry(textLayoutManager)?.characterOffset(at: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
    }
    /// The task whose checkbox marker is under `point`, or the touched character
    /// when the paper has no task items.
    func taskCheckboxOffset(at point: CGPoint) -> Int? {
        guard let geometry = RelayTextGeometry(textLayoutManager) else { return nil }
        let origin = textContainerOrigin
        let location = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        let taskItems = paper.viewTaskItems
        if !taskItems.isEmpty { return taskMarkerHit(at: location, geometry: geometry, taskItems: taskItems) }
        return geometry.nearestCharacter(at: location)
    }
    var onImageInputFailure: ((String) -> Void)? = nil
    var onBeginImageInput: ((NSRange, String, String) -> RelayMarkImageIntake?)?
    var onBeginImageBatchInputs: ((NSRange, [RelayMarkImageFile]) -> [RelayMarkImageIntake]?)?
    var onBeginStructuredPaste: ((NSRange, Int, String?) -> RelayMarkPasteIntake?)?
    private func imageFile(_ item: NSPasteboardItem) -> (URL, String?)? {
        guard let literal = item.string(forType: .fileURL), let file = URL(string: literal), file.isFileURL,
              let values = try? file.resourceValues(forKeys: [.contentTypeKey]),
              let type = values.contentType, type.conforms(to: .image) else { return nil }
        return (file, imagePolicy.mime(type.identifier))
    }
    private func hasImage(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.pasteboardItems?.contains(where: { imageFile($0) != nil ||
            $0.types.contains(where: { RelayNativeImageRepresentation.isImage($0.rawValue) }) }) == true
    }
    private func receiveImage(_ pasteboard: NSPasteboard, range: NSRange) -> Bool {
        guard hasImage(pasteboard), let items = pasteboard.pasteboardItems else { return false }
        if items.count > 1 {
            guard items.count <= 4096 else { onImageInputFailure?(String(localized: "Too many images in this paste. No item was inserted.", bundle: .module, comment: "Shown when a paste holds more images than the paper accepts.")); return true }
            var files: [RelayMarkImageFile] = []
            var reads: [() -> Data?] = []; let maximumBytes = imagePolicy.maximumBytes
            for item in items {
                if let (file, possibleMime) = imageFile(item), let mime = possibleMime {
                    files.append(.init(filename: file.lastPathComponent, contentType: mime))
                    reads.append {
                        let access = file.startAccessingSecurityScopedResource()
                        defer { if access { file.stopAccessingSecurityScopedResource() } }
                        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        guard size > 0, size <= maximumBytes else { return nil }
                        return try? Data(contentsOf: file)
                    }
                } else if let type = item.types.first(where: { imagePolicy.mime($0.rawValue) != nil }),
                          let mime = imagePolicy.mime(type.rawValue) {
                    files.append(.init(filename: RelayNativeImageRepresentation.filename(nil, identifier: type.rawValue), contentType: mime))
                    reads.append { item.data(forType: type) }
                } else {
                    onImageInputFailure?(String(localized: "Every item must be a supported image. No subset was inserted.", bundle: .module, comment: "Shown when some pasted or dropped items are not supported images.")); return true
                }
            }
            // Every reservation precedes the first file/provider byte read.
            guard let intakes = onBeginImageBatchInputs?(range, files), intakes.count == reads.count else { return true }
            for (index, read) in reads.enumerated() { intakes[index].receive(read()) }
            return true
        }
        guard let item = items.first else { return true }
        if let (file, possibleMime) = imageFile(item) {
            guard let mime = possibleMime else { onImageInputFailure?(String(localized: "This image type is not supported. No image was inserted.", bundle: .module, comment: "Shown when a pasted or dropped image type is not supported.")); return true }
            guard let intake = onBeginImageInput?(range, file.lastPathComponent, mime) else { return true }
            let access = file.startAccessingSecurityScopedResource()
            defer { if access { file.stopAccessingSecurityScopedResource() } }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 0, size <= imagePolicy.maximumBytes else { intake.receive(nil); return true }
            intake.receive(try? Data(contentsOf: file)); return true
        }
        guard let type = item.types.first(where: { imagePolicy.mime($0.rawValue) != nil }) else {
            onImageInputFailure?(String(localized: "This image type is not supported. No image was inserted.", bundle: .module, comment: "Shown when a pasted or dropped image type is not supported.")); return true
        }
        guard let mime = imagePolicy.mime(type.rawValue),
              let intake = onBeginImageInput?(range, RelayNativeImageRepresentation.filename(nil, identifier: type.rawValue), mime)
        else { return true }
        intake.receive(item.data(forType: type)); return true
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !retired, isEditable else { return [] }
        if hasImage(sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !retired, isEditable, !hasMarkedText(), compositionCompletion == nil else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        let offset = characterIndexForInsertion(at: point)
        if hasImage(sender.draggingPasteboard) {
            guard offset <= viewLength, !paper.tables.touchesTableLine(NSRange(location: offset, length: 0)) else { return false }
            setSelectedRange(NSRange(location: offset, length: 0))
            return receiveImage(sender.draggingPasteboard, range: selectedRange())
        }
        return super.performDragOperation(sender)
    }
    override func paste(_ sender: Any?) {
        guard !retired, isEditable, !hasMarkedText(), compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange()) <= viewLength else { return }
        if NSPasteboard.general.types?.contains(.html) == true {
            // Snapshot ordered item handles before reserving or requesting bytes.
            let items = NSPasteboard.general.pasteboardItems ?? []
            guard !items.isEmpty, items.allSatisfy({ $0.types.contains(.html) }) else {
                onImageInputFailure?(String(localized: "Mixed clipboard representations cannot be inserted as a subset. No item was inserted.", bundle: .module, comment: "Shown when a paste mixes formatted and other items.")); return
            }
            guard let intake = onBeginStructuredPaste?(selectedRange(), items.count, NSPasteboard.general.string(forType: .string)) else { return }
            for (index, item) in items.enumerated() { intake.receive(item.data(forType: .html), at: index) }
            return
        }
        if receiveImage(NSPasteboard.general, range: selectedRange()) { return }
        if pastePlainText(richer: true) || pasteRichText() { return }
        NSSound.beep()
    }
    /// Formatted clipboard text becomes one windowed command with its marks.
    private func pasteRichText() -> Bool {
        let pasteboard = NSPasteboard.general
        guard let session = editingSession,
              let rich = pasteboard.data(forType: .rtfd).flatMap({ NSAttributedString(rtfd: $0, documentAttributes: nil) })
                ?? pasteboard.data(forType: .rtf).flatMap({ NSAttributedString(rtf: $0, documentAttributes: nil) }),
              session.pasteNatively(range: paperSelection, piece: NativeProseCodec.value(rich, inferFontChanges: true)) else { return false }
        onSessionEdit?()
        return true
    }
    /// Plain clipboard text becomes one windowed command; `richer` refuses
    /// when the clipboard also carries a formatted representation.
    private func pastePlainText(richer: Bool) -> Bool {
        let pasteboard = NSPasteboard.general
        guard let session = editingSession, let value = pasteboard.string(forType: .string),
              !richer || !(pasteboard.types ?? []).contains(where: { [.rtf, .rtfd, .html].contains($0) }),
              session.pastePlainTextNatively(range: paperSelection, text: value) else { return false }
        onSessionEdit?()
        return true
    }
    override func pasteAsRichText(_ sender: Any?) {
        guard !retired, isEditable, !hasMarkedText(), compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange()) <= viewLength else { return }
        if NSPasteboard.general.types?.contains(.html) == true {
            // Snapshot ordered item handles before reserving or requesting bytes.
            let items = NSPasteboard.general.pasteboardItems ?? []
            guard !items.isEmpty, items.allSatisfy({ $0.types.contains(.html) }) else {
                onImageInputFailure?(String(localized: "Mixed clipboard representations cannot be inserted as a subset. No item was inserted.", bundle: .module, comment: "Shown when a paste mixes formatted and other items.")); return
            }
            guard let intake = onBeginStructuredPaste?(selectedRange(), items.count, NSPasteboard.general.string(forType: .string)) else { return }
            for (index, item) in items.enumerated() { intake.receive(item.data(forType: .html), at: index) }
            return
        }
        if receiveImage(NSPasteboard.general, range: selectedRange()) { return }
        if pasteRichText() || pastePlainText(richer: false) { return }
        NSSound.beep()
    }
    override func pasteAsPlainText(_ sender: Any?) {
        guard !retired, isEditable, !hasMarkedText(), compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange()) <= viewLength else { return }
        if !pastePlainText(richer: false) { NSSound.beep() }
    }
    /// Bold and italic from the font menu or panel are the paper's marks; other
    /// font changes are not part of the paper.
    override func changeFont(_ sender: Any?) {
        guard !retired, isEditable, !hasMarkedText(), compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange()) <= viewLength else { return }
        // A font change with no mark in the paper (a size or family) is refused, not shown and undone.
        if let manager = sender as? NSFontManager, !formatNatively(convert: manager.convert) { RelayPaperRefusal.feedback() }
    }
    /// Bold or italic toggled through the font menu or panel becomes one
    /// windowed mark command when `convert` changes exactly that trait.
    func formatNatively(convert: (NSFont) -> NSFont) -> Bool {
        let selection = selectedRange()
        // At a caret the font is the one the next typed text takes.
        let shown = selection.length > 0 ? textStorage?.attribute(.font, at: selection.location, effectiveRange: nil) : typingAttributes[.font]
        guard let session = editingSession, let font = shown as? NSFont else { return false }
        let before = font.fontDescriptor.symbolicTraits, after = convert(font).fontDescriptor.symbolicTraits
        let changed = [(RelayMarkFormattingMark.bold, NSFontDescriptor.SymbolicTraits.bold), (.italic, .italic)]
            .filter { before.contains($0.1) != after.contains($0.1) }
        guard changed.count == 1, after.subtracting([.bold, .italic]) == before.subtracting([.bold, .italic]) else { return false }
        if selection.length == 0 {
            guard session.toggleMarkNatively(changed[0].0, range: paper.tables.paper(selection)) else { return false }
            typingAttributes[.font] = convert(font)
            return true
        }
        guard session.formatNatively(range: paper.tables.paper(selection), mark: changed[0].0, enabled: after.contains(changed[0].1)) else { return false }
        onSessionEdit?()
        return true
    }
    fileprivate let collaborationUndo = CollaborationUndoManager()
    weak var editingSession: (any RelayPaperTextEditing)?
    fileprivate var finalizerRegistration: UUID?
    private(set) var retired = false
    private var compositionGeneration = UUID()
    private var compositionCompletion: Task<Void, Never>?
    func cancelCompositionCompletion() {
        compositionGeneration = UUID()
        compositionCompletion?.cancel(); compositionCompletion = nil
    }
    func retireInput() {
        retired = true
        onTaskCheckbox = nil
        onSessionEdit = nil
        cancelCompositionCompletion()
        onCompositionStart = nil; onCompositionEnd = nil; onDeclaredMarkedInput = nil
        collaborationUndo.undoAction = nil; collaborationUndo.redoAction = nil
    }
    func applyEmptyTypingStyle() {
        let selection = paperSelection
        if selection.length == 0, let block = paper.emptyBlocks.first(where: { $0.offset == selection.location }) {
            typingAttributes = NativeProseCodec.emptyAttributes(block.intent, inlineIntent: block.inlineIntent, link: block.link, typingStyle: block.typingStyle)
        }
    }
    var onDeclaredMarkedInput: ((String?, NSRange, NSRange, NSRange?, Bool) -> Bool)?
    var onCompositionStart: (() -> Void)?
    var onCompositionEnd: (() -> Void)?
    override var undoManager: UndoManager? { collaborationUndo }
    @objc func undo(_ sender: Any?) {
        guard !retired, isEditable else { return }
        collaborationUndo.undo()
    }
    @objc func redo(_ sender: Any?) {
        guard !retired, isEditable else { return }
        collaborationUndo.redo()
    }
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard !retired, isEditable else { return }
        if !hasMarkedText() { cancelCompositionCompletion(); onCompositionStart?() }
        if let onDeclaredMarkedInput {
            let literal: String
            if let attributed = string as? NSAttributedString { literal = attributed.string }
            else if let value = string as? String { literal = value }
            else { return }
            let effective = replacementRange.location == NSNotFound ? (hasMarkedText() ? markedRange() : self.selectedRange()) : replacementRange
            guard onDeclaredMarkedInput(literal, effective, selectedRange, replacementRange, false) else { return }
        }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }
    override func unmarkText() {
        let wasMarked = hasMarkedText()
        super.unmarkText()
        if wasMarked, !retired {
            let generation = compositionGeneration
            compositionCompletion = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, !self.retired, generation == self.compositionGeneration, !self.hasMarkedText() else { return }
                self.compositionCompletion = nil
                self.onCompositionEnd?()
            }
        }
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard !retired, isEditable else { return }
        if (hasMarkedText() || compositionCompletion != nil), let onDeclaredMarkedInput {
            let literal: String
            if let value = insertString as? NSAttributedString { literal = value.string }
            else if let value = insertString as? String { literal = value }
            else { return }
            let effective = replacementRange.location == NSNotFound ? (hasMarkedText() ? markedRange() : selectedRange()) : replacementRange
            guard onDeclaredMarkedInput(literal, effective, selectedRange(), replacementRange, true) else { return }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }
    override func textViewportLayoutControllerDidLayout(_ controller: NSTextViewportLayoutController) {
        super.textViewportLayoutControllerDidLayout(controller)
        viewportDidLayout(controller)
    }

    nonisolated func textContentManager(_ textContentManager: NSTextContentManager, shouldEnumerate textElement: NSTextElement,
                                        options: NSTextContentManager.EnumerationOptions) -> Bool {
        nonisolated(unsafe) let element = textElement
        return MainActor.assumeIsolated { paperShows(element) }
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let geometry = RelayTextGeometry(textLayoutManager) else { return }
        drawListMarkers(geometry: geometry, origin: textContainerOrigin, laidOut: paper.laidOut,
                        emptyBlocks: paper.viewEmptyBlocks, taskItems: paper.viewTaskItems)
        drawSectionDisclosures(geometry: geometry, origin: textContainerOrigin)
        drawRemoteSelections(paper.remoteSelections.filter { !paper.isHidden($0.caretLocation) }, resolveColor: collaboratorColor, geometry: geometry,
            origin: textContainerOrigin, length: string.utf16.count) { [weak self] offset in
                guard let self, let window = self.window else { return nil }
                let screen = self.firstRect(forCharacterRange: NSRange(location: offset, length: 0), actualRange: nil)
                return self.convert(window.convertFromScreen(screen), from: nil)
            }
    }
}
#else
@MainActor
/// The paper's text view: TextKit 2 over one editor session.
public struct RelayMarkEditorView: UIViewRepresentable {
    typealias Session = RelayMarkEditorSession
    /// Names the editor's task-checkbox tap among the text view's recognizers.
    static let taskTapName = "relaymark.task-checkbox"
    var session: Session
    var accessibilityLabel: String
    var services = RelayMarkEditorServices()

    public init(session: RelayMarkEditorSession, accessibilityLabel: String, services: RelayMarkEditorServices = .init()) {
        self.session = session; self.accessibilityLabel = accessibilityLabel; self.services = services
    }
    public func makeCoordinator() -> Coordinator { Coordinator(text: TextCoordinator(session: session)) }
    /// Owns the view's text system for SwiftUI; its members are internal.
    @MainActor public final class Coordinator {
        let text: TextCoordinator
        init(text: TextCoordinator) { self.text = text }
    }
    public func makeUIView(context: Context) -> CollaborationTextContainer {
        context.coordinator.text.services = services
        let container = CollaborationTextContainer()
        container.install(context.coordinator.text.makeTextView(accessibilityLabel: accessibilityLabel))
        return container
    }
    public func updateUIView(_ container: CollaborationTextContainer, context: Context) {
        _ = services.imageStore?.revision
        context.coordinator.text.services = services
        if context.coordinator.text.session !== session {
            let previous = container.textView
            let wasFocused = previous?.isFirstResponder == true
            if let previous { context.coordinator.text.retire(previous) }
            context.coordinator.text.session = session
            let replacement = context.coordinator.text.makeTextView(accessibilityLabel: accessibilityLabel)
            container.install(replacement)
            if wasFocused { replacement.becomeFirstResponder() }
        } else if let view = container.textView { context.coordinator.text.update(view) }
    }
    public static func dismantleUIView(_ container: CollaborationTextContainer, coordinator: Coordinator) {
        if let view = container.textView { coordinator.text.retire(view) }
    }
    @MainActor final class TextCoordinator: NSObject, UITextViewDelegate, UITextPasteDelegate, UITextFormattingViewController.Delegate {
        /// The host's services; tests may set the closures below directly.
        var services = RelayMarkEditorServices() {
            didSet {
                mediaImages = services.imageStore
                onActivatePaperButton = services.paperControls.map { controls in { controls.activatePaperButton(id: $0) } }
                onActivateFragmentLink = services.links.map { links in { links.activateFragmentLink($0) } }
                onImageInputFailure = services.inputRefused
                onBeginImageInput = services.images.map { images in { images.beginImageInput(at: $0, filename: $1, contentType: $2) } }
                onBeginImageBatchInputs = services.images.map { images in { images.beginImageInputs(at: $0, files: $1) } }
                onBeginStructuredPaste = services.paste.map { paste in { paste.beginStructuredPaste(at: $0, itemCount: $1, plainText: $2) } }
            }
        }
        var mediaImages: RelayMarkImageStore? {
            get { editor.mediaImages }
            set { editor.mediaImages = newValue }
        }
        var onActivatePaperButton: ((String) -> Void)?
        var onActivateFragmentLink: ((String) -> Void)?
        var onImageInputFailure: ((String) -> Void)?
        var onBeginImageBatchInputs: ((NSRange, [RelayMarkImageFile]) -> [RelayMarkImageIntake]?)?
        var onBeginImageInput: ((NSRange, String, String) -> RelayMarkImageIntake?)?
        var onBeginStructuredPaste: ((NSRange, Int, String?) -> RelayMarkPasteIntake?)?
        let editor: RelayPaperEditor<Session>
        var session: Session {
            get { editor.session }
            set { editor.session = newValue }
        }
        var composition: Session.Composition? {
            get { editor.composition }
            set { editor.composition = newValue }
        }
        private var updating: Bool {
            get { editor.updating }
            set { editor.updating = newValue }
        }
        /// A keystroke inside one text leaf, applied without reading the whole paper.
        var pendingTyping: (range: NSRange, text: String)? { editor.pendingTyping.map { ($0.paper, $0.text) } }
        private var pasteCommands: [String: (command: RelayNativePasteCommand, owner: ObjectIdentifier, preservesFormatting: Bool)] = [:]
        var pendingPasteCount: Int { pasteCommands.count }
        init(session: Session) { editor = RelayPaperEditor(session: session) }
        func makeTextView(accessibilityLabel: String) -> CollaborationTextView {
            let view = CollaborationTextView.textKit2()
            view.editingSession = session
            apply(services, to: view)
            editor.attach(view)
            // Find in paper, including text inside table cells.
            view.installFind()
            view.onImageInputFailure = { [weak self, weak view] message in
                guard let self, let view, view.editingSession === session, !session.isInvalidated else { return }
                onImageInputFailure?(message)
            }
            view.onBeginImageInput = { [weak self, weak view] range, filename, contentType in
                guard let self, let view, !view.retired, view.editingSession === session,
                      !session.isInvalidated, session.isEditable else { return nil }
                return onBeginImageInput?(view.paper.tables.paper(range), filename, contentType)
            }
            view.onBeginImageBatchInputs = { [weak self, weak view] range, files in
                guard let self, let view, !view.retired, view.editingSession === session,
                      !session.isInvalidated, session.isEditable else { return nil }
                return onBeginImageBatchInputs?(view.paper.tables.paper(range), files)
            }
            view.onBeginStructuredPaste = { [weak self, weak view] range, itemCount, plainText in
                guard let self, let view, !view.retired, view.editingSession === session,
                      !session.isInvalidated, session.isEditable else { return nil }
                return onBeginStructuredPaste?(view.paper.tables.paper(range), itemCount, plainText)
            }
            view.delegate = self
            view.onPaperButton = { [weak self, weak view] offset in
                guard let self, let view, view.editingSession === session, !session.isInvalidated,
                      let activate = onActivatePaperButton else { return false }
                let paper = view.paper.tables.paper(offset)
                guard let atom = session.nativeBlockAtoms.first(where: { $0.control == .button && NSLocationInRange(paper, $0.range) }) else { return false }
                activate(atom.id)
                return true
            }
            view.textDropDelegate = view
            view.textDragDelegate = view
            view.pasteDelegate = self
            view.onCompositionStart = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                composition = try? session.beginComposition()
            }
            if let native = session as? RelayMarkEditorSession {
                view.onDeclaredMarkedInput = { [weak self, weak view, weak native] literal, replacement, selection, supplied, final in
                    guard let self, let view, let native, !view.retired, view.editingSession === session,
                          let token = self.composition as? RelayMarkEditorSession.Composition else { return false }
                    let tables = view.paper.tables
                    return native.declareMarkedInput(literal, replacement: tables.paper(replacement), selection: selection,
                        platform: .uiKit, suppliedReplacement: supplied.map { $0.location == NSNotFound ? $0 : tables.paper($0) },
                        phase: final ? .final : .marked, from: token)
                }
            }
            view.onCompositionEnd = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                endComposition(view)
            }
            view.backgroundColor = .clear
            view.textContainerInset = UIEdgeInsets(top: 20, left: RelayPaperMargins.leading, bottom: 8, right: RelayPaperMargins.trailing)
            view.allowsEditingTextAttributes = true
            view.textFormattingConfiguration = CollaborationTextView.formattingPanel
            view.adjustsFontForContentSizeCategory = true
            view.accessibilityLabel = accessibilityLabel
            view.onSessionEdit = { [weak self, weak view] in
                guard let self, let view, !view.retired else { return }
                self.update(view)
            }
            session.onFocusRequest = { [weak self, weak view] in
                guard let self, let view else { return }
                takeFocusIfRequested(view)
            }
            view.onMovedToWindow = { [weak self, weak view] in
                guard let self, let view else { return }
                takeFocusIfRequested(view)
            }
            if let taskSession = session as? RelayMarkEditorSession {
                view.onTaskCheckbox = { [weak self, weak view] offset in
                    guard let self, let view, view.editingSession === session,
                          taskSession.toggleTaskItem(atUTF16: view.paper.tables.paper(offset)) else { return false }
                    self.update(view)
                    return true
                }
                let tap = UITapGestureRecognizer(target: view, action: #selector(CollaborationTextView.handleTaskTap(_:)))
                tap.cancelsTouchesInView = false
                tap.name = RelayMarkEditorView.taskTapName
                // Recognized alongside UITextView's own taps, which place the caret.
                tap.delegate = view.taskTapDelegate
                view.addGestureRecognizer(tap)
            }
            view.collaborationUndo.undoAction = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                session.undo(); self.update(view)
            }
            view.collaborationUndo.redoAction = { [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                session.redo(); self.update(view)
            }
            view.finalizerRegistration = session.registerNativeCompositionFinalizer({ [weak self, weak view] in
                guard let self, let view, view.editingSession === session else { return }
                try finishComposition(view)
            }, refresh: { [weak self, weak view] in
                guard let self, let view, !view.retired, view.editingSession === session else { return }
                self.update(view)
            })
            update(view)
            return view
        }
        func finishComposition(_ view: CollaborationTextView) throws { try editor.finishComposition(view) }
        func retire(_ view: CollaborationTextView) {
            guard !view.retired else { return }
            updating = true
            defer { updating = false }
            if view.editingSession === session, session.isEditable { try? finishComposition(view) }
            if let composition, view.editingSession === session { session.cancelComposition(composition) }
            composition = nil
            if let registration = view.finalizerRegistration { view.editingSession?.unregisterNativeCompositionFinalizer(registration) }
            view.finalizerRegistration = nil
            view.retireInput()
            view.delegate = nil
            view.pasteDelegate = nil
            pasteCommands.removeAll()
            view.unmarkText()
            view.isEditable = false
            view.resignFirstResponder()
            view.attributedText = NSAttributedString(string: "")
            view.paper.tables = RelayTableSpans(); view.paper.tableAttachments = [:]
            view.selectedRange = NSRange(location: 0, length: 0)
            view.paper.remoteSelections = []
            view.unlinkPreviousTextElement()
            if view.editingSession === session { session.onFocusRequest = nil }
            view.editingSession = nil
        }
        func textView(_ textView: UITextView, editMenuForTextInRanges ranges: [NSValue],
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let view = textView as? CollaborationTextView, !view.retired else { return nil }
            let entries = view.sectionMenuEntries(link: services.sectionLink)
            guard !entries.isEmpty else { return nil }
            let section = UIMenu(options: .displayInline, children: entries.map { entry in UIAction(title: entry.title) { _ in entry.run() } })
            return UIMenu(children: suggestedActions + [section])
        }
        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content, url.absoluteString.hasPrefix("#"),
                  let view = textView as? CollaborationTextView,
                  let activate = onActivateFragmentLink else { return defaultAction }
            let href = url.absoluteString
            let owner = ObjectIdentifier(session)
            return UIAction { [weak self, weak view] _ in
                guard let self, let view, !view.retired, view.editingSession === session,
                      ObjectIdentifier(session) == owner, !session.isInvalidated else { return }
                activate(href)
                update(view)
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextInRanges ranges: [NSValue], replacementText text: String) -> Bool {
            guard !updating, let view = textView as? CollaborationTextView, !view.retired,
                view.editingSession == nil || view.editingSession === session else { return false }
            view.pasteCommand = nil
            return editor.shouldChange(view, ranges: ranges.map(\.rangeValue), replacement: text)
        }
        private static var pasteToken: NSAttributedString.Key { NSAttributedString.Key("RelayTransientPasteToken") }
        func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
                                             transform item: any UITextPasteItem) {
            // HTML may only use the scope captured by the explicit paste
            // command before UIKit begins asynchronous provider delivery.
            if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.html.identifier) {
                item.setNoResult()
                guard let view = textPasteConfigurationSupporting as? CollaborationTextView,
                      let intake = view.structuredPasteIntake else { return }
                view.structuredPasteIntake = nil
                item.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.html.identifier) { data, _ in
                    Task { @MainActor in intake.receive(data) }
                }
                return
            }
            guard let view = textPasteConfigurationSupporting as? CollaborationTextView,
                  !view.retired, view.editingSession === session, let command = view.pasteCommand else {
                item.setDefaultResult(); return
            }
            let rich = item.itemProvider.hasItemConformingToTypeIdentifier(UTType.rtf.identifier)
            guard rich || item.itemProvider.registeredTypeIdentifiers.allSatisfy({ UTType($0)?.conforms(to: .plainText) == true }) else {
                item.setDefaultResult(); return
            }
            let tokenID = command.id.uuidString
            let preservesFormatting = rich || pasteCommands[tokenID]?.preservesFormatting == true
            pasteCommands[tokenID] = (command, ObjectIdentifier(session), preservesFormatting)
            let complete: @MainActor @Sendable (NSAttributedString?) -> Void = { [weak self, weak view] payload in
                guard let self, let view else { item.setNoResult(); return }
                guard !view.retired, !self.session.isInvalidated, view.editingSession === self.session,
                      self.pasteCommands[tokenID]?.owner == ObjectIdentifier(self.session) else {
                    self.pasteCommands[tokenID] = nil
                    item.setNoResult(); return
                }
                guard let payload else { self.pasteCommands[tokenID] = nil; item.setNoResult(); return }
                let tagged = NSMutableAttributedString(attributedString: payload)
                tagged.addAttribute(Self.pasteToken, value: tokenID, range: NSRange(location: 0, length: tagged.length))
                item.setResult(attributedString: tagged)
            }
            // Decode with Foundation on the main actor. Provider callbacks carry
            // only Sendable bytes/text; the captured token retains exact owner,
            // baseline and selection fences for acceptance or draft recovery.
            if rich {
                item.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.rtf.identifier) { data, _ in
                    Task { @MainActor in
                        guard let data, data.count <= 4_194_304 else { complete(nil); return }
                        let decoded = try? NSAttributedString(data: data,
                            options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
                        complete(decoded)
                    }
                }
            } else {
                item.itemProvider.loadObject(ofClass: NSString.self) { value, _ in
                    let string = value as? String
                    Task { @MainActor in complete(string.map { NSAttributedString(string: $0) }) }
                }
            }
        }
        func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
                                             performPasteOf attributedString: NSAttributedString, to textRange: UITextRange) -> UITextRange {
            guard let view = textPasteConfigurationSupporting as? CollaborationTextView,
                  !updating, !view.retired, view.editingSession === session, session.isEditable else { return textRange }
            let range = NSRange(location: view.offset(from: view.beginningOfDocument, to: textRange.start),
                length: view.offset(from: textRange.start, to: textRange.end))
            let paperRange = view.paper.tables.paper(range)
            var tokens = Set<String>()
            var missingToken = false
            attributedString.enumerateAttribute(Self.pasteToken, in: NSRange(location: 0, length: attributedString.length)) { value, _, _ in
                if let value = value as? String { tokens.insert(value) } else { missingToken = true }
            }
            let token = view.pasteCommand
            let accepted = !missingToken && tokens.count == 1 && tokens.first == token?.id.uuidString &&
                pasteCommands[token?.id.uuidString ?? ""]?.owner == ObjectIdentifier(session) &&
                token?.baseline == view.paperValue() && token?.range == paperRange &&
                view.markedTextRange == nil && composition == nil
            // Unknown/foreign tokens cannot transfer any candidate into this owner.
            guard tokens.allSatisfy({ pasteCommands[$0]?.owner == ObjectIdentifier(session) }) else {
                return view.selectedTextRange ?? textRange
            }
            guard session.acceptsNativePastePayload(attributedString.string) else {
                for value in tokens { pasteCommands[value] = nil }
                if tokens.contains(view.pasteCommand?.id.uuidString ?? "") { view.pasteCommand = nil }
                return view.selectedTextRange ?? textRange
            }
            let richImport = tokens.contains { pasteCommands[$0]?.preservesFormatting == true }
            let clean = NSMutableAttributedString(attributedString: attributedString)
            clean.removeAttribute(Self.pasteToken, range: NSRange(location: 0, length: clean.length))
            if !accepted, !tokens.isEmpty {
                let entries = tokens.compactMap { pasteCommands[$0] }
                guard entries.count == tokens.count, let first = entries.first,
                      entries.allSatisfy({ $0.owner == ObjectIdentifier(session) &&
                          $0.command.baseline == first.command.baseline && $0.command.range == first.command.range }) else { return view.selectedTextRange ?? textRange }
                // Preserve each original paste scope without changing the active
                // view/selection or consuming a newer command's token.
                for value in tokens {
                    guard let entry = pasteCommands.removeValue(forKey: value), entry.owner == ObjectIdentifier(session) else { continue }
                    let original = entry.command
                    let candidate = NSMutableAttributedString(attributedString: NativeProseCodec.attributed(
                        original.baseline, tableCells: session.nativeTableCells,
                        callouts: session.nativeCallouts, inlineAtoms: session.nativeInlineAtoms,
                        blockAtoms: session.nativeBlockAtoms,
                                                      authoredWidgets: session.nativeAuthoredWidgets,
                        entityReferenceAtoms: session.nativeEntityReferenceAtoms,
                        mediaAtoms: session.nativeMediaAtoms,
                        suggestionAtoms: session.nativeSuggestionAtoms))
                    guard NSMaxRange(original.range) <= candidate.length else { continue }
                    // Mixed provider results are unproven, but every byte must
                    // remain reviewable, including untagged provider portions.
                    candidate.replaceCharacters(in: original.range, with: clean)
                    let rendered = NativeProseCodec.value(candidate, inferFontChanges: entry.preservesFormatting)
                    let replacement = RelayNativeTextReplacement(baseline: String(original.baseline.characters),
                        range: original.range, replacement: clean.string)
                    let scoped = entry.preservesFormatting
                        ? original.attributedCandidate(replacement: replacement, rendered: rendered)
                        : original.plainCandidate(replacement: replacement, rendered: String(rendered.characters))
                    session.preserveRejectedPaste(scoped ?? rendered, id: original.id)
                }
                return view.selectedTextRange ?? textRange
            }
            guard range.location >= 0, NSMaxRange(range) <= view.viewLength else { return view.selectedTextRange ?? textRange }
            if tokens.contains(view.pasteCommand?.id.uuidString ?? "") { view.pasteCommand = nil }
            for value in tokens { pasteCommands[value] = nil }
            // The paste is one windowed command over the selection, with its marks when it is rich.
            let pasted = richImport
                ? session.pasteNatively(range: paperRange, piece: NativeProseCodec.value(clean, inferFontChanges: true))
                : session.pastePlainTextNatively(range: paperRange, text: clean.string)
            if !pasted {
                // A paste the paper cannot take is kept for review and reported, never dropped.
                let baseline = view.paperString
                let replacement = RelayNativeTextReplacement(baseline: baseline, range: paperRange, replacement: clean.string)
                let rendered = (baseline as NSString).replacingCharacters(in: paperRange, with: clean.string)
                session.preserveRejectedPaste(token?.plainCandidate(replacement: replacement, rendered: rendered)
                    ?? AttributedString(rendered), id: token?.id ?? UUID())
            }
            update(view)
            return view.selectedTextRange ?? textRange
        }
        func textViewDidChange(_ textView: UITextView) {
            guard let view = textView as? CollaborationTextView else { return }
            editor.didChange(view)
        }
        func endComposition(_ view: CollaborationTextView) {
            guard !updating, !view.retired, composition != nil, view.markedTextRange == nil,
                view.editingSession == nil || view.editingSession === session else { return }
            textViewDidChange(view)
        }
        /// Writing Tools rewrites the paper's prose; each table cell is its own text view.
        func textView(_ textView: UITextView, writingToolsIgnoredRangesInEnclosingRange enclosingRange: NSRange) -> [NSValue] {
            guard let view = textView as? CollaborationTextView else { return [] }
            return view.paper.tables.spans.filter { NSLocationInRange($0.view, enclosingRange) }
                .map { NSValue(range: NSRange(location: $0.view, length: 1)) }
        }
        /// The formatting panel's changes are the paper's marks, applied by the
        /// session; a change the paper has no mark for is refused, never shown and lost.
        func textView(_ textView: UITextView, willBeginFormattingWith viewController: UITextFormattingViewController) {
            viewController.delegate = self
        }
        func textFormattingViewController(_ viewController: UITextFormattingViewController,
                                          didChangeValue changeValue: UITextFormattingViewController.ChangeValue) {
            guard let view = editor.attachedView as? CollaborationTextView, !view.retired, !updating, view.markedTextRange == nil,
                  view.editingSession === session, session.isEditable else { return }
            let applied: Bool
            switch changeValue {
            case .bold(let on): applied = view.setMark(.bold, enabled: on)
            case .italic(let on): applied = view.setMark(.italic, enabled: on)
            case .strikethrough(let on): applied = view.setMark(.strike, enabled: on)
            default: applied = false
            }
            guard applied else { RelayPaperRefusal.feedback(); return }
            update(view)
            viewController.formattingDescriptor = .init(string: view.textStorage, range: view.selectedRange)
        }
        func textViewDidChangeSelection(_ view: UITextView) {
            guard !updating, let view = view as? CollaborationTextView, !view.retired, view.markedTextRange == nil,
                view.editingSession == nil || view.editingSession === session else { return }
            if view.pasteCommand?.range != view.paperSelection { view.pasteCommand = nil }
            editor.selectionDidChange(view)
        }
        func update(_ view: CollaborationTextView) {
            guard !view.retired, view.editingSession == nil || view.editingSession === session else { return }
            if session.isInvalidated { pasteCommands.removeAll(); view.pasteCommand = nil; view.pasteDelegate = nil }
            apply(services, to: view)
            editor.update(view)
        }
        /// The host asked for focus in the paper: the view takes it, with the
        /// session's selection, once it is in a window.
        func takeFocusIfRequested(_ view: CollaborationTextView) {
            guard session.focusRequest != nil, !view.retired, view.editingSession === session, view.window != nil else { return }
            session.focusRequest = nil
            update(view)
            view.becomeFirstResponder()
        }
        private func apply(_ services: RelayMarkEditorServices, to view: CollaborationTextView) {
            view.imagePolicy = .init(accepted: services.images?.acceptedImageTypes ?? [],
                                     maximumBytes: services.images?.maximumImageBytes ?? 0)
            view.collaboratorColor = services.collaboratorColor
            view.selectionActions = services.selectionActions
            view.previousTextElement = services.previousTextElement
            view.linkPreviousTextElement()
        }
    }
}
/// Only the native input client changes with the paper; SwiftUI keeps its layout host.
@MainActor
public final class CollaborationTextContainer: UIView {
    private(set) var textView: CollaborationTextView?
    func install(_ view: CollaborationTextView) {
        textView?.removeFromSuperview()
        textView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
@MainActor
final class CollaborationTextView: UITextView, UITextDropDelegate, UITextDragDelegate, RelayPaperTextView, NSTextContentStorageDelegate {
    /// Lets the task-checkbox tap recognize together with the text view's own
    /// taps. Without it the checkbox tap wins and a tap never focuses the paper.
    final class SimultaneousTapDelegate: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
    let taskTapDelegate = SimultaneousTapDelegate()
    /// The host's image capability and collaborator colors, from its services.
    var imagePolicy = RelayNativeImageRepresentation()
    var collaboratorColor: (String) -> Color = RelayMarkEditorServices.hexColor
    /// The only way to make the editor: Relay's TextKit 2 stack. A subclass
    /// built with `init(frame:)` starts in TextKit 1 compatibility mode.
    static func textKit2(frame: CGRect = .zero) -> CollaborationTextView {
        let storage = NSTextContentStorage(), manager = RelayTextLayoutManager()
        storage.addTextLayoutManager(manager)
        let container = NSTextContainer(size: CGSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude))
        manager.textContainer = container
        let view = Self(frame: frame, textContainer: container)
        view.contentStorage = storage
        #if os(macOS)
        view.paper.disclosuresFollowPointer = true
        #endif
        // Folded sections' paragraphs are skipped from layout, never removed from the text.
        storage.delegate = view
        // A table's grid stays with its attachment, wherever its paragraph is laid out.
        view.register([.onScrollingOutOfViewport, .onEditingInlineParagraphs],
                      forTextAttachmentViewProviderType: RelayTableAttachmentViewProvider.self)
        return view
    }
    /// The view does not own its content storage; this keeps the stack alive.
    private var contentStorage: NSTextContentStorage?
    let paper = RelayPaperViewState()
    var paperStorage: NSTextStorage { textStorage }
    /// The host's text read before the paper. The paper holds it weakly; the title
    /// holds the paper, so VoiceOver's line reading crosses from one to the other.
    var previousTextElement: (() -> AnyObject?)?
    override var accessibilityPreviousTextNavigationElement: Any? {
        get { previousTextElement?() ?? super.accessibilityPreviousTextNavigationElement }
        set { super.accessibilityPreviousTextNavigationElement = newValue }
    }
    func linkPreviousTextElement() {
        (previousTextElement?() as? NSObject)?.accessibilityNextTextNavigationElement = self
    }
    func unlinkPreviousTextElement() {
        guard let title = previousTextElement?() as? NSObject,
              title.accessibilityNextTextNavigationElement as AnyObject? === self else { return }
        title.accessibilityNextTextNavigationElement = nil
    }
    /// The keyboard keeps its language per context; the paper and its cells are one.
    static let keyboardContext = "relay.paper"
    override var textInputContextIdentifier: String? { Self.keyboardContext }
    var selectionActions: [RelayMarkSelectionAction] = []
    var viewSelections: [NSRange] { selectedRanges }
    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            (super.accessibilityCustomActions ?? []) + paperAccessibilityActions().map { action in
                let custom = UIAccessibilityCustomAction(name: action.name) { _ in action.perform() }
                if action.edits { custom.category = UIAccessibilityCustomAction.editCategory }
                return custom
            }
        }
        set { super.accessibilityCustomActions = newValue }
    }
    /// Underline has no mark in the paper: TextKit would show it until the next
    /// render and then drop it, so it is not offered and is refused.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(toggleUnderline(_:)) { return false }
        return super.canPerformAction(action, withSender: sender)
    }
    override func toggleUnderline(_ sender: Any?) { RelayPaperRefusal.feedback() }
    /// The formatting panel offers only the paper's marks: bold, italic, underline
    /// (refused) and strikethrough. Fonts, sizes, colours and alignment are not paper.
    static var formattingPanel: UITextFormattingViewController.Configuration {
        UITextFormattingViewController.Configuration(groups: [.group([.component(.fontAttributes, .automatic)])])
    }
    var isPaperEditable: Bool {
        get { isEditable }
        set { isEditable = newValue }
    }
    var hasMarkedInput: Bool { markedTextRange != nil }
    var viewSelection: NSRange { selectedRange }
    func showSelection(_ range: NSRange) { selectedRange = range; scrollRangeToVisible(range) }
    func unmarkPaperText() { unmarkText() }
    func paperNeedsDisplay() { setNeedsDisplay() }
    func replaceAllText(_ text: NSAttributedString) {
        pasteCommand = nil
        attributedText = text
    }
    func focus(_ cell: RelayTableCellTextView, selecting range: NSRange) {
        if NSMaxRange(range) <= cell.text.utf16.count, cell.selectedRange != range { cell.selectedRange = range }
        if isFirstResponder { cell.becomeFirstResponder() }
    }
    var tableUndoManager: UndoManager? { collaborationUndo }
    /// Only the table rows near the screen keep cell text views.
    override func layoutSubviews() {
        super.layoutSubviews()
        assert(textLayoutManager != nil, "The paper switched to TextKit 1 compatibility mode")
        for span in paper.tables.spans where span.table.isGridLoaded && span.table.grid.superview != nil {
            span.table.grid.updateVisible(in: convert(bounds, to: span.table.grid))
        }
    }
    private func changeListDepth(backward: Bool) -> Bool {
        guard !retired, isEditable, markedTextRange == nil, compositionCompletion == nil,
              let session = editingSession, session.isEditable else { return false }
        session.setNativeSelection(paperSelection)
        return session.handleNativeListIndent(backward: backward)
    }
    /// A drag holding tables carries each as rows of tab-separated cells.
    func textDraggableView(_ textDraggableView: UIView & UITextDraggable, itemsForDrag dragRequest: UITextDragRequest) -> [UIDragItem] {
        guard let visible = paper.tables.readable(textStorage, range: viewRange(dragRequest.dragRange)) else {
            return dragRequest.suggestedItems
        }
        return [UIDragItem(itemProvider: NSItemProvider(object: visible))]
    }
    override func copy(_ sender: Any?) {
        guard let visible = paper.tables.readable(textStorage, range: selectedRange) else { return super.copy(sender) }
        var item: [String: Any] = [UTType.utf8PlainText.identifier: visible.string]
        if let rtf = try? visible.data(from: NSRange(location: 0, length: visible.length),
                                       documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            item[UTType.rtf.identifier] = rtf
        }
        copyPasteboard.items = [item]
    }
    /// Where Copy writes; tests use a private pasteboard.
    var copyPasteboard: UIPasteboard = .general
    override func deleteBackward() {
        if !retired, isEditable, markedTextRange == nil, compositionCompletion == nil,
           selectedRange.length == 0, selectedRange.location == 0,
           let session = editingSession, session.isEditable {
            session.setNativeSelection(paperSelection)
            if session.handleNativeEdgeDeletion(backward: true) { return }
        }
        super.deleteBackward()
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.count == 1, let key = presses.first?.key,
           key.charactersIgnoringModifiers == "\t",
           key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty,
           changeListDepth(backward: key.modifierFlags.contains(.shift)) { return }
        super.pressesBegan(presses, with: event)
    }
    fileprivate var pasteCommand: RelayNativePasteCommand?
    fileprivate var structuredPasteIntake: RelayMarkPasteIntake?
    private var dispatchingStructuredPaste = false
    var onImageInputFailure: ((String) -> Void)? = nil
    var onBeginImageInput: ((NSRange, String, String) -> RelayMarkImageIntake?)?
    var onBeginImageBatchInputs: ((NSRange, [RelayMarkImageFile]) -> [RelayMarkImageIntake]?)?
    var onBeginStructuredPaste: ((NSRange, Int, String?) -> RelayMarkPasteIntake?)?
    var onPaperButton: ((Int) -> Bool)?
    var onTaskCheckbox: ((Int) -> Bool)?
    /// The session changed outside TextKit's own editing; the coordinator shows it.
    var onSessionEdit: (() -> Void)?
    /// The view entered a window, where it can take keyboard focus.
    var onMovedToWindow: (() -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        onMovedToWindow?()
    }
    @objc func handleTaskTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, !retired, markedTextRange == nil else { return }
        let point = gesture.location(in: self)
        let location = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        guard let geometry = RelayTextGeometry(textLayoutManager) else { return }
        if let id = sectionDisclosureHit(at: location, geometry: geometry) { toggleSection(id); return }
        if let onPaperButton, let offset = geometry.characterOffset(at: location), onPaperButton(offset) { return }
        guard isEditable, let onTaskCheckbox, let offset = taskCheckboxOffset(at: point) else { return }
        _ = onTaskCheckbox(offset)
    }
    /// The task whose checkbox marker is under `point` in view coordinates.
    func taskCheckboxOffset(at point: CGPoint) -> Int? {
        let taskItems = paper.viewTaskItems
        guard !taskItems.isEmpty, let geometry = RelayTextGeometry(textLayoutManager) else { return nil }
        let location = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        return taskMarkerHit(at: location, geometry: geometry, taskItems: taskItems)
    }
    private func receiveImageProviders(_ providers: [NSItemProvider], range: NSRange) -> Bool {
        guard providers.contains(where: { $0.registeredTypeIdentifiers.contains(where: { RelayNativeImageRepresentation.isImage($0) }) }) else { return false }
        if providers.count > 1 {
            guard providers.count <= 4096 else { onImageInputFailure?(String(localized: "Too many images in this input. No item was inserted.", bundle: .module, comment: "Shown when a paste or drop holds more images than the paper accepts.")); return true }
            var files: [RelayMarkImageFile] = [], identifiers: [String] = []
            for provider in providers {
                guard let identifier = provider.registeredTypeIdentifiers.first(where: { imagePolicy.mime($0) != nil }),
                      let mime = imagePolicy.mime(identifier) else {
                    onImageInputFailure?(String(localized: "Every item must be a supported image. No subset was inserted.", bundle: .module, comment: "Shown when some pasted or dropped items are not supported images.")); return true
                }
                files.append(.init(filename: RelayNativeImageRepresentation.filename(provider.suggestedName, identifier: identifier), contentType: mime))
                identifiers.append(identifier)
            }
            guard let intakes = onBeginImageBatchInputs?(range, files), intakes.count == providers.count else { return true }
            for (index, provider) in providers.enumerated() {
                provider.loadDataRepresentation(forTypeIdentifier: identifiers[index]) { bytes, _ in
                    Task { @MainActor in intakes[index].receive(bytes) }
                }
            }
            return true
        }
        guard let provider = providers.first else { return true }
        guard let identifier = provider.registeredTypeIdentifiers.first(where: { imagePolicy.mime($0) != nil }) else {
            onImageInputFailure?(String(localized: "This image type is not supported. No image was inserted.", bundle: .module, comment: "Shown when a pasted or dropped image type is not supported.")); return true
        }
        guard let mime = imagePolicy.mime(identifier),
              let intake = onBeginImageInput?(range, RelayNativeImageRepresentation.filename(provider.suggestedName, identifier: identifier), mime)
        else { return true }
        provider.loadDataRepresentation(forTypeIdentifier: identifier) { bytes, _ in
            Task { @MainActor in intake.receive(bytes) }
        }
        return true
    }
    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, proposalForDrop drop: UITextDropRequest) -> UITextDropProposal {
        let providers = drop.dropSession.items.map(\.itemProvider)
        guard providers.contains(where: { $0.registeredTypeIdentifiers.contains(where: { RelayNativeImageRepresentation.isImage($0) }) })
        else { return drop.suggestedProposal }
        let allowed = !retired && isEditable && markedTextRange == nil && compositionCompletion == nil && !providers.isEmpty && providers.count <= 4096 &&
            providers.allSatisfy({ $0.registeredTypeIdentifiers.contains(where: { imagePolicy.mime($0) != nil }) })
        let proposal = UITextDropProposal(operation: allowed ? .copy : .cancel)
        proposal.dropPerformer = .delegate
        proposal.useFastSameViewOperations = false
        return proposal
    }
    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, willPerformDrop drop: UITextDropRequest) {
        guard !retired, isEditable, markedTextRange == nil, compositionCompletion == nil else { return }
        let providers = drop.dropSession.items.map(\.itemProvider)
        guard providers.contains(where: { $0.registeredTypeIdentifiers.contains(where: { RelayNativeImageRepresentation.isImage($0) }) }) else { return }
        let range = NSRange(location: offset(from: beginningOfDocument, to: drop.dropPosition), length: 0)
        guard NSMaxRange(range) <= viewLength, !paper.tables.touchesTableLine(range) else { return }
        selectedRange = range
        _ = receiveImageProviders(providers, range: range)
    }
    override func paste(_ sender: Any?) {
        guard !retired, isEditable, markedTextRange == nil, compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange) <= viewLength else { return }
        // Plain clipboard text becomes one windowed command.
        let pasteboard = UIPasteboard.general
        if let session = editingSession, let value = pasteboard.string,
           !pasteboard.contains(pasteboardTypes: [UTType.html.identifier, UTType.rtf.identifier, UTType.flatRTFD.identifier]),
           !pasteboard.hasImages, session.pastePlainTextNatively(range: paperSelection, text: value) {
            onSessionEdit?()
            return
        }
        guard let baseline = paperValue() else { return }
        pasteCommand = RelayNativePasteCommand(baseline: baseline, range: paperSelection)
        if UIPasteboard.general.contains(pasteboardTypes: [UTType.html.identifier]) {
            receiveHTMLProviders(UIPasteboard.general.itemProviders, plainText: pasteboard.string)
        } else {
            structuredPasteIntake = nil
            if receiveImageProviders(UIPasteboard.general.itemProviders, range: selectedRange) { pasteCommand = nil; return }
            super.paste(sender)
        }
    }
    override func paste(itemProviders: [NSItemProvider]) {
        guard !retired, isEditable, markedTextRange == nil, compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange) <= viewLength, let baseline = paperValue() else { return }
        pasteCommand = RelayNativePasteCommand(baseline: baseline, range: paperSelection)
        if itemProviders.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.html.identifier) }) {
            receiveHTMLProviders(itemProviders)
            return
        }
        structuredPasteIntake = nil
        if receiveImageProviders(itemProviders, range: selectedRange) { pasteCommand = nil; return }
        super.paste(itemProviders: itemProviders)
    }
    private func receiveHTMLProviders(_ providers: [NSItemProvider], plainText: String? = nil) {
        // HTML never falls through UIKit's default converter. A mixed item list
        // remains on the clipboard intact; all-HTML delivery is ordered by slot.
        guard !providers.isEmpty, providers.allSatisfy({ $0.hasItemConformingToTypeIdentifier(UTType.html.identifier) }) else {
            onImageInputFailure?(String(localized: "Mixed clipboard representations cannot be inserted as a subset. No item was inserted.", bundle: .module, comment: "Shown when a paste mixes formatted and other items.")); return
        }
        guard let intake = onBeginStructuredPaste?(selectedRange, providers.count, plainText) else { return }
        for (index, provider) in providers.enumerated() {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.html.identifier) { bytes, _ in
                Task { @MainActor in intake.receive(bytes, at: index) }
            }
        }
    }
    override func toggleBoldface(_ sender: Any?) {
        guard !retired, isEditable, markedTextRange == nil, compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange) <= viewLength else { return }
        if toggleMark(.bold) { onSessionEdit?() }
    }
    override func toggleItalics(_ sender: Any?) {
        guard !retired, isEditable, markedTextRange == nil, compositionCompletion == nil else { return }
        guard NSMaxRange(selectedRange) <= viewLength else { return }
        if toggleMark(.italic) { onSessionEdit?() }
    }
    fileprivate let collaborationUndo = CollaborationUndoManager()
    weak var editingSession: (any RelayPaperTextEditing)?
    fileprivate var finalizerRegistration: UUID?
    private(set) var retired = false
    private var compositionGeneration = UUID()
    private var compositionCompletion: Task<Void, Never>?
    func cancelCompositionCompletion() {
        compositionGeneration = UUID()
        compositionCompletion?.cancel(); compositionCompletion = nil
    }
    func retireInput() {
        retired = true
        pasteCommand = nil
        onTaskCheckbox = nil
        onSessionEdit = nil
        cancelCompositionCompletion()
        onCompositionStart = nil; onCompositionEnd = nil; onDeclaredMarkedInput = nil
        collaborationUndo.undoAction = nil; collaborationUndo.redoAction = nil
    }
    func applyEmptyTypingStyle() {
        let selection = paperSelection
        if selection.length == 0, let block = paper.emptyBlocks.first(where: { $0.offset == selection.location }) {
            typingAttributes = NativeProseCodec.emptyAttributes(block.intent, inlineIntent: block.inlineIntent, link: block.link, typingStyle: block.typingStyle)
        }
    }
    var onDeclaredMarkedInput: ((String?, NSRange, NSRange, NSRange?, Bool) -> Bool)?
    var onCompositionStart: (() -> Void)?
    var onCompositionEnd: (() -> Void)?
    override var undoManager: UndoManager? { collaborationUndo }
    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        guard !retired, isEditable else { return }
        pasteCommand = nil
        if markedTextRange == nil { cancelCompositionCompletion(); onCompositionStart?() }
        if let onDeclaredMarkedInput {
            guard let target = markedTextRange ?? selectedTextRange else { return }
            let start = offset(from: beginningOfDocument, to: target.start)
            let end = offset(from: beginningOfDocument, to: target.end)
            guard start >= 0, end >= start,
                  onDeclaredMarkedInput(markedText, NSRange(location: start, length: end - start),
                    selectedRange, nil, false) else { return }
        }
        super.setMarkedText(markedText, selectedRange: selectedRange)
    }
    override func unmarkText() {
        let wasMarked = markedTextRange != nil
        super.unmarkText()
        if wasMarked, !retired {
            let generation = compositionGeneration
            compositionCompletion = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, !self.retired, generation == self.compositionGeneration, self.markedTextRange == nil else { return }
                self.compositionCompletion = nil
                self.onCompositionEnd?()
            }
        }
    }
    func viewRange(_ range: UITextRange) -> NSRange {
        let start = offset(from: beginningOfDocument, to: range.start)
        return NSRange(location: start, length: offset(from: range.start, to: range.end))
    }
    /// Find in paper searches the paper's text, table cells included.
    private let search = RelayPaperTextSearch()
    private var paperFind: UIFindInteraction?
    func installFind() {
        search.view = self
        let interaction = UIFindInteraction(sessionDelegate: search)
        addInteraction(interaction)
        paperFind = interaction
    }
    override var findInteraction: UIFindInteraction? { paperFind ?? super.findInteraction }
    override func find(_ sender: Any?) { paperFind?.presentFindNavigator(showingReplace: false) }
    override func findNext(_ sender: Any?) { paperFind?.findNext() }
    override func findPrevious(_ sender: Any?) { paperFind?.findPrevious() }
    fileprivate func drawFound(in context: CGContext) {
        guard let geometry = RelayTextGeometry(textLayoutManager) else { return }
        for (range, style) in search.decorations {
            guard let shown = paper.tables.view(range) else { continue }
            context.setFillColor(UIColor.systemYellow.withAlphaComponent(style == .highlighted ? 0.6 : 0.3).cgColor)
            for frame in geometry.segmentFrames(shown) {
                context.fill(frame.offsetBy(dx: textContainerInset.left, dy: textContainerInset.top))
            }
        }
    }
    override func insertText(_ text: String) {
        guard !retired, isEditable else { return }
        if (markedTextRange != nil || compositionCompletion != nil), let onDeclaredMarkedInput {
            guard let target = markedTextRange ?? selectedTextRange else { return }
            let start = offset(from: beginningOfDocument, to: target.start)
            let end = offset(from: beginningOfDocument, to: target.end)
            guard start >= 0, end >= start,
                  onDeclaredMarkedInput(text, NSRange(location: start, length: end - start), selectedRange, nil, true) else { return }
        }
        super.insertText(text)
    }
    override func textViewportLayoutControllerDidLayout(_ controller: NSTextViewportLayoutController) {
        super.textViewportLayoutControllerDidLayout(controller)
        viewportDidLayout(controller)
    }

    nonisolated func textContentManager(_ textContentManager: NSTextContentManager, shouldEnumerate textElement: NSTextElement,
                                        options: NSTextContentManager.EnumerationOptions) -> Bool {
        nonisolated(unsafe) let element = textElement
        return MainActor.assumeIsolated { paperShows(element) }
    }
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let geometry = RelayTextGeometry(textLayoutManager) else { return }
        let origin = CGPoint(x: textContainerInset.left, y: textContainerInset.top)
        if let context = UIGraphicsGetCurrentContext() { drawFound(in: context) }
        drawListMarkers(geometry: geometry, origin: origin, laidOut: paper.laidOut,
                        emptyBlocks: paper.viewEmptyBlocks, taskItems: paper.viewTaskItems)
        drawSectionDisclosures(geometry: geometry, origin: origin)
        drawRemoteSelections(paper.remoteSelections.filter { !paper.isHidden($0.caretLocation) }, resolveColor: collaboratorColor, geometry: geometry, origin: origin, length: text.utf16.count) { [weak self] offset in
                guard let self, let position = self.position(from: self.beginningOfDocument, offset: offset) else { return nil }
                return self.caretRect(for: position)
            }
    }
}
#endif

/// TextKit 2 geometry in text-container coordinates; offsets remain canonical UTF-16.
/// Queries lay out only the fragments they touch, never the whole paper.
@MainActor
struct RelayTextGeometry {
    let manager: NSTextLayoutManager
    let content: NSTextContentManager
    let storage: NSTextStorage

    init?(_ manager: NSTextLayoutManager?) {
        guard let manager, let content = manager.textContentManager,
              let storage = (content as? NSTextContentStorage)?.textStorage else { return nil }
        self.manager = manager; self.content = content; self.storage = storage
    }

    var length: Int { storage.length }
    var padding: CGFloat { manager.textContainer?.lineFragmentPadding ?? 0 }

    func location(_ offset: Int) -> (any NSTextLocation)? {
        guard offset >= 0, offset <= length else { return nil }
        return content.location(content.documentRange.location, offsetBy: offset)
    }

    func offset(_ location: any NSTextLocation) -> Int {
        content.offset(from: content.documentRange.location, to: location)
    }

    func textRange(_ range: NSRange) -> NSTextRange? {
        guard let start = location(range.location), let end = location(NSMaxRange(range)) else { return nil }
        return NSTextRange(location: start, end: end)
    }

    func range(_ textRange: NSTextRange) -> NSRange {
        let start = offset(textRange.location)
        return NSRange(location: start, length: max(0, offset(textRange.endLocation) - start))
    }

    func segmentFrames(_ range: NSRange) -> [CGRect] {
        guard let textRange = textRange(range) else { return [] }
        var frames: [CGRect] = []
        manager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            frames.append(frame); return true
        }
        return frames
    }

    func characterFrame(at offset: Int) -> CGRect? {
        guard offset >= 0, offset < length else { return nil }
        return segmentFrames(NSRange(location: offset, length: 1)).first
    }

    /// The line holding `offset` across the container width, starting at the
    /// container's leading edge; at the end, the empty line after a final newline.
    func lineFrame(at offset: Int) -> CGRect? {
        guard offset >= 0, offset <= length else { return nil }
        if offset == length {
            guard let end = location(length) else { return nil }
            if let fragment = manager.textLayoutFragment(for: end), self.offset(fragment.rangeInElement.location) == length {
                manager.ensureLayout(for: fragment.rangeInElement)
                let frame = fragment.layoutFragmentFrame
                return CGRect(x: frame.minX - padding, y: frame.minY, width: frame.width + padding, height: frame.height)
            }
            guard length > 0, (storage.string as NSString).character(at: length - 1) == 10,
                  let last = lineFrame(at: length - 1) else { return nil }
            return last.offsetBy(dx: 0, dy: last.height)
        }
        guard let target = location(offset), let fragment = manager.textLayoutFragment(for: target) else { return nil }
        manager.ensureLayout(for: fragment.rangeInElement)
        let frame = fragment.layoutFragmentFrame
        let inner = offset - self.offset(fragment.rangeInElement.location)
        let lines = fragment.textLineFragments
        guard let line = lines.first(where: { NSLocationInRange(inner, $0.characterRange) }) ?? lines.last else { return nil }
        let bounds = line.typographicBounds
        return CGRect(x: frame.minX - padding, y: frame.minY + bounds.minY, width: frame.width + padding, height: bounds.height)
    }

    /// Whether TextKit resolved the paragraph at `offset` to run right to left.
    func isRightToLeft(at offset: Int) -> Bool {
        guard let location = location(offset) else { return false }
        return manager.baseWritingDirection(at: location) == .rightToLeft
    }

    /// The offsets of the laid-out paragraph across the line at `y`.
    func paragraphRange(atY y: CGFloat) -> NSRange? {
        let width = manager.textContainer?.size.width ?? 0
        return manager.textLayoutFragment(for: CGPoint(x: width / 2, y: y)).map { range($0.rangeInElement) }
    }

    /// Where a paragraph's list or task marker of `width` is drawn, on the
    /// paragraph's leading side: beside its first character, or inside the
    /// indent of an empty paragraph.
    func markerFrame(at offset: Int, width: CGFloat, empty: Bool, headIndent: CGFloat) -> CGRect? {
        let rightToLeft = isRightToLeft(at: offset)
        if empty {
            guard let line = lineFrame(at: offset), line.height > 0 else { return nil }
            let x = rightToLeft ? line.maxX - padding - headIndent + 7 : line.minX + padding + headIndent - width - 7
            return CGRect(x: x, y: line.minY, width: width, height: line.height)
        }
        guard let character = characterFrame(at: offset) else { return nil }
        let x = rightToLeft ? character.maxX + 7 : character.minX - width - 7
        return CGRect(x: x, y: character.minY, width: width, height: character.height)
    }

    /// The character whose drawn frame contains `point`, never the nearest one.
    func characterOffset(at point: CGPoint) -> Int? {
        guard let fragment = manager.textLayoutFragment(for: point) else { return nil }
        let frame = fragment.layoutFragmentFrame
        let base = offset(fragment.rangeInElement.location)
        for line in fragment.textLineFragments {
            let bounds = line.typographicBounds.offsetBy(dx: frame.minX, dy: frame.minY)
            guard point.y >= bounds.minY, point.y < bounds.maxY else { continue }
            let range = line.characterRange
            for inner in range.location..<NSMaxRange(range) {
                if let rect = characterFrame(at: base + inner), rect.contains(point) { return base + inner }
            }
            return nil
        }
        return nil
    }

    /// The nearest character to `point`, as a click on plain text resolves it.
    func nearestCharacter(at point: CGPoint) -> Int? {
        guard let fragment = manager.textLayoutFragment(for: point) else { return nil }
        let frame = fragment.layoutFragmentFrame
        let base = offset(fragment.rangeInElement.location)
        let lines = fragment.textLineFragments
        guard let line = lines.first(where: {
            let bounds = $0.typographicBounds.offsetBy(dx: frame.minX, dy: frame.minY)
            return point.y >= bounds.minY && point.y < bounds.maxY
        }) ?? lines.last else { return nil }
        let range = line.characterRange
        guard range.length > 0 else { return min(base + range.location, max(0, length - 1)) }
        var best = base + range.location, distance = CGFloat.greatestFiniteMagnitude
        for inner in range.location..<NSMaxRange(range) {
            guard let rect = characterFrame(at: base + inner) else { continue }
            let gap = point.x < rect.minX ? rect.minX - point.x : max(0, point.x - rect.maxX)
            if gap < distance { distance = gap; best = base + inner }
        }
        return best
    }
}

@MainActor
private func drawRemoteSelections(_ selections: [RelayMarkRemoteSelection], resolveColor: (String) -> Color, geometry: RelayTextGeometry,
                                  origin: CGPoint, length: Int, nativeCaret: (Int) -> CGRect?) {
    for selection in selections where NSMaxRange(selection.range) <= length {
        let color = PlatformColor.collaborator(selection.color, resolve: resolveColor)
        if selection.range.length > 0 {
            for rect in geometry.segmentFrames(selection.range) {
                color.withAlphaComponent(0.18).setFill()
                let shifted = rect.offsetBy(dx: origin.x, dy: origin.y)
                #if os(macOS)
                NSBezierPath(rect: shifted).fill()
                #else
                UIBezierPath(rect: shifted).fill()
                #endif
            }
        }
        var caret = CGRect(x: origin.x, y: origin.y, width: 2, height: 18)
        let end = selection.caretLocation
        if length > 0, let rect = geometry.characterFrame(at: min(end, length - 1)) {
            caret = CGRect(x: (end == length ? rect.maxX : rect.minX) + origin.x, y: rect.minY + origin.y, width: 2, height: max(16, rect.height))
        }
        if let native = nativeCaret(selection.caretLocation) { caret = CGRect(x: native.minX, y: native.minY, width: 2, height: max(16, native.height)) }
        color.setFill()
        #if os(macOS)
        NSBezierPath(rect: caret).fill()
        #else
        UIBezierPath(rect: caret).fill()
        #endif
        let label = NSAttributedString(string: String(selection.name.prefix(24)), attributes: [.font: PlatformFont.systemFont(ofSize: 10), .foregroundColor: color])
        label.draw(at: CGPoint(x: caret.maxX + 2, y: max(0, caret.minY - 12)))
    }
}

/// Markers are gutter drawings, not inserted characters: CRDT, marked input and
/// remote selections all retain the canonical UTF-16 coordinate space.
@MainActor
private func taskMarkerHit(at point: CGPoint, geometry: RelayTextGeometry,
                           taskItems: [RelayMarkCollaborativeProse.TaskItem]) -> Int? {
    // Only the tasks on the tapped line can have a checkbox under it.
    guard let line = geometry.paragraphRange(atY: point.y) else { return nil }
    let storage = geometry.storage
    for item in taskItems where item.firstParagraphRange.location >= line.location &&
        item.firstParagraphRange.location <= NSMaxRange(line) {
        let offset = item.firstParagraphRange.location
        guard offset >= 0, offset <= storage.length else { continue }
        let label = item.checked ? "☑" : "☐"
        let font = offset < storage.length
            ? (storage.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont ?? .systemFont(ofSize: 15))
            : PlatformFont.systemFont(ofSize: 15)
        let width = (label as NSString).size(withAttributes: [.font: font]).width
        let style = offset < storage.length
            ? storage.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
            : nil
        guard let marker = geometry.markerFrame(at: offset, width: width, empty: item.firstParagraphRange.length == 0,
                                                headIndent: style?.headIndent ?? 18) else { continue }
        if CGRect(x: marker.minX - 3, y: marker.minY - 3, width: width + 6,
                  height: max(marker.height, font.ascender - font.descender + font.leading) + 6).contains(point) { return offset }
    }
    return nil
}

extension RelayPaperTextView {
    /// Whether TextKit lays out a paragraph: not when it starts inside a folded section.
    func paperShows(_ element: NSTextElement) -> Bool {
        guard !paper.hidden.isEmpty, let range = element.elementRange, let content = textLayoutManager?.textContentManager else { return true }
        return !paper.isHidden(content.offset(from: content.documentRange.location, to: range.location))
    }

    /// The heading paragraph holding a view offset, as the view range of its text.
    /// Read from the view's own attributes, so it costs the same at any paper length.
    func headingParagraph(at location: Int) -> NSRange? {
        let storage = paperStorage, text = storage.string as NSString
        guard location >= 0, location <= text.length else { return nil }
        let paragraph = text.paragraphRange(for: NSRange(location: min(location, text.length), length: 0))
        let content = NSRange(location: paragraph.location,
                              length: paragraph.length - (NSMaxRange(paragraph) > paragraph.location &&
                                  text.character(at: NSMaxRange(paragraph) - 1) == 10 ? 1 : 0))
        let intent: PresentationIntent?
        if content.length > 0 {
            intent = (storage.attribute(.relayBlockIntent, at: content.location, effectiveRange: nil) as? RelayBlockIntent)?.intent
        } else {
            intent = paper.viewEmptyBlocks.first { $0.offset == content.location }?.intent
        }
        let heading = intent?.components.contains { if case .header = $0.kind { true } else { false } } == true
        return heading ? content : nil
    }

    /// The heading paragraphs that start in a view range.
    func headingParagraphs(in range: NSRange) -> [NSRange] {
        let text = paperStorage.string as NSString
        var result: [NSRange] = [], location = range.location
        while location <= min(NSMaxRange(range), text.length) {
            if let heading = headingParagraph(at: location) { result.append(heading) }
            guard location < text.length else { break }
            location = NSMaxRange(text.paragraphRange(for: NSRange(location: location, length: 0)))
        }
        return result
    }

    /// The destination name of the section whose heading starts at a view offset.
    func sectionID(atHeading location: Int) -> String? {
        let paper = paper.tables.paper(location)
        return editingSession?.sections.first { $0.heading.location == paper }?.id
    }

    /// Each laid-out heading's fold controls, in container coordinates, placed as
    /// the web places them: a 1.5rem chevron whose right edge meets the heading's
    /// text, 0.25em below its top, and when folded an expand control 0.5rem after
    /// the text. Section names are read only while a section is folded.
    func sectionDisclosures(geometry: RelayTextGeometry) -> [RelayHeadingDisclosure] {
        guard let session = editingSession else { return [] }
        let visible = paper.laidOut.map(geometry.range) ?? NSRange(location: 0, length: geometry.length)
        let folded: Set<Int> = session.foldedSections.isEmpty ? [] : Set(session.sections.compactMap { section in
            session.foldedSections.contains(section.id) ? paper.tables.view(section.heading.location) : nil
        })
        let size = RelayPaperMargins.gutter, caret = viewSelection.location
        return headingParagraphs(in: visible).compactMap { heading in
            guard !paper.isHidden(heading.location) else { return nil }
            let font = heading.location < geometry.length
                ? geometry.storage.attribute(.font, at: heading.location, effectiveRange: nil) as? PlatformFont : nil
            let em = font?.pointSize ?? 15
            let start: CGFloat, top: CGFloat, end: CGRect
            if heading.length == 0 {
                guard let line = geometry.lineFrame(at: heading.location), line.height > 0 else { return nil }
                start = line.minX + geometry.padding; top = line.minY
                end = CGRect(x: start, y: line.minY, width: 0, height: line.height)
            } else {
                guard let first = geometry.characterFrame(at: heading.location),
                      let last = geometry.characterFrame(at: NSMaxRange(heading) - 1) else { return nil }
                start = first.minX; top = first.minY; end = last
            }
            let isFolded = folded.contains(heading.location)
            let shown = !paper.disclosuresFollowPointer || paper.hoveredHeading == heading.location ||
                (caret >= heading.location && caret <= NSMaxRange(heading))
            return RelayHeadingDisclosure(heading: heading,
                chevron: CGRect(x: start - size, y: top + em * 0.25, width: size, height: size),
                expand: isFolded ? CGRect(x: end.maxX + 8, y: end.midY - size / 2, width: size, height: size) : nil,
                folded: isFolded, shown: shown)
        }
    }

    func drawSectionDisclosures(geometry: RelayTextGeometry, origin: CGPoint) {
        // Where every chevron always shows, it stays subtle; on hover it shows plainly.
        let tone: CGFloat = paper.disclosuresFollowPointer ? 1 : 0.55
        for disclosure in sectionDisclosures(geometry: geometry) {
            if disclosure.shown {
                drawSymbol(disclosure.folded ? "chevron.right" : "chevron.down",
                           in: disclosure.chevron.offsetBy(dx: origin.x, dy: origin.y), tone: tone)
            }
            if let expand = disclosure.expand { drawSymbol("ellipsis", in: expand.offsetBy(dx: origin.x, dy: origin.y), tone: 1) }
        }
    }

    private func drawSymbol(_ name: String, in rect: CGRect, tone: CGFloat) {
        let color = PlatformColor.secondaryLabelColorCompat.withAlphaComponent(tone)
        #if os(macOS)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold).applying(.init(hierarchicalColor: color))) else { return }
        let size = image.size
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        #else
        guard let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        let size = image.size
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        #endif
    }

    /// The heading menu's entries for the section at the caret: fold or unfold it,
    /// and copy its link when the host gives sections links.
    func sectionMenuEntries(link: ((String) -> URL?)?) -> [(title: String, run: () -> Void)] {
        guard let section = sectionAtCaret, let session = editingSession else { return [] }
        let folded = session.foldedSections.contains(section.id)
        var entries: [(title: String, run: () -> Void)] = [(folded
            ? String(localized: "Expand section", bundle: .module, comment: "Heading menu command that shows a folded section.")
            : String(localized: "Collapse section", bundle: .module, comment: "Heading menu command that hides a section's content."),
            { [weak self] in _ = self?.toggleSection(section.id) })]
        if let url = link?(section.id) {
            entries.append((String(localized: "Copy link to this section", bundle: .module, comment: "Heading menu command that copies a link to the section."), {
                #if os(macOS)
                NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([url as NSURL])
                #else
                UIPasteboard.general.url = url
                #endif
            }))
        }
        return entries
    }

    /// The section whose heading disclosure is under `point`, in container coordinates.
    func sectionDisclosureHit(at point: CGPoint, geometry: RelayTextGeometry) -> String? {
        guard let hit = sectionDisclosures(geometry: geometry).first(where: { disclosure in
            [disclosure.chevron, disclosure.expand].contains { $0?.insetBy(dx: -4, dy: -4).contains(point) == true } })
        else { return nil }
        return sectionID(atHeading: hit.heading.location)
    }
}

@MainActor
private func drawListMarkers(geometry: RelayTextGeometry, origin: CGPoint, laidOut: NSTextRange?,
                             emptyBlocks: [RelayEmptyProseBlock], taskItems: [RelayMarkCollaborativeProse.TaskItem]) {
    let storage = geometry.storage
    let source = storage.string as NSString
    let visible = laidOut.map(geometry.range) ?? NSRange(location: 0, length: storage.length)
    func isVisible(_ offset: Int) -> Bool { offset >= visible.location && offset <= NSMaxRange(visible) }
    let taskMarkers = Dictionary(uniqueKeysWithValues: taskItems.map {
        ($0.firstParagraphRange.location, $0.checked ? "☑" : "☐")
    })
    for block in emptyBlocks where block.offset >= 0 && block.offset <= storage.length && isVisible(block.offset) {
        guard let marker = NativeProseCodec.listMarker(block.intent) else { continue }
        let attrs = NativeProseCodec.emptyAttributes(block.intent)
        let style = attrs[.paragraphStyle] as? NSParagraphStyle
        let label = NSAttributedString(string: taskMarkers[block.offset] ?? marker.label, attributes: attrs)
        guard let frame = geometry.markerFrame(at: block.offset, width: label.size().width, empty: true,
                                               headIndent: style?.headIndent ?? 0) else { continue }
        label.draw(at: CGPoint(x: origin.x + frame.minX, y: origin.y + frame.minY))
    }
    storage.enumerateAttribute(.relayListMarker, in: NSIntersectionRange(visible, NSRange(location: 0, length: storage.length))) { value, range, _ in
        guard let label = value as? String, range.location < source.length,
              range.location == 0 || source.character(at: range.location - 1) == 10 else { return }
        let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont ?? .systemFont(ofSize: 15)
        let marker = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: PlatformColor.labelColorCompat])
        guard let frame = geometry.markerFrame(at: range.location, width: marker.size().width, empty: false,
                                               headIndent: 0) else { return }
        marker.draw(at: CGPoint(x: origin.x + frame.minX, y: origin.y + frame.minY))
    }
}
