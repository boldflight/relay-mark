import Foundation
import RelayMarkProseProjection

/// A heading's section, as the web's paper headings define it: everything after
/// the heading up to the next heading of the same or a higher level among its
/// siblings, or the end of its container.
public struct RelayPaperSection: Equatable, Sendable {
    /// The section's destination name: the heading's anchor, or one derived from
    /// its text exactly as `paperDocumentDestinations` derives it.
    public let id: String
    public let level: Int
    /// The heading's text, in paper offsets.
    public let heading: NSRange
    /// What the section holds after the heading, in paper offsets; may be empty.
    public let body: NSRange
}

extension RelayMarkEditorSession {
    /// The paper's sections in document order.
    public var sections: [RelayPaperSection] {
        if let cached = sectionCache, cached.revision == textRevision { return cached.sections }
        let sections = (try? currentProjection()).map { Self.sections(in: $0, text: text) } ?? []
        sectionCache = (textRevision, sections)
        return sections
    }

    /// Folds or unfolds a section. Folding moves a caret out of the section first,
    /// so it does not unfold again at once. Fold state is this session's view
    /// state: never saved, synced or kept across opens.
    @discardableResult public func toggleSection(_ id: String) -> Bool {
        guard let section = sections.first(where: { $0.id == id }) else { return false }
        if foldedSections.contains(id) { foldedSections.remove(id); return true }
        if let selection = nativeSelection, Self.holds(section, selection.location) {
            setNativeSelection(NSRange(location: section.heading.location, length: 0))
        }
        foldedSections.insert(id)
        return true
    }

    /// Unfolds a section and every section that contains it, as navigating to
    /// its link does.
    @discardableResult public func revealSection(_ id: String) -> Bool {
        let sections = sections
        guard let target = sections.first(where: { $0.id == id }) else { return false }
        for section in sections where section.id == id || Self.holds(section, target.heading.location) {
            foldedSections.remove(section.id)
        }
        return true
    }

    /// Paper ranges hidden by folded sections, in order. Fold state of headings
    /// that no longer exist is dropped here.
    var hiddenSectionRanges: [NSRange] {
        guard !foldedSections.isEmpty else { return [] }
        let sections = sections
        let present = Set(sections.map(\.id))
        if !foldedSections.isSubset(of: present) { foldedSections.formIntersection(present) }
        var hidden: [NSRange] = []
        for section in sections where foldedSections.contains(section.id) && section.body.length > 0 {
            if let last = hidden.last, NSMaxRange(last) >= section.body.location {
                hidden[hidden.count - 1] = NSUnionRange(last, section.body)
            } else {
                hidden.append(section.body)
            }
        }
        return hidden
    }

    /// A selection moved into a folded section unfolds it.
    func revealSections(holding location: Int) {
        guard !foldedSections.isEmpty else { return }
        for section in sections where foldedSections.contains(section.id) && Self.holds(section, location) {
            foldedSections.remove(section.id)
        }
    }

    private static func holds(_ section: RelayPaperSection, _ location: Int) -> Bool {
        location >= section.body.location && location < NSMaxRange(section.body)
    }

    static func sections(in projection: RelayMarkCollaborativeProse, text: AttributedString) -> [RelayPaperSection] {
        let headings = projection.headings
        guard !headings.isEmpty else { return [] }
        let string = String(text.characters) as NSString
        let paths = projection.blockPaths, ranges = projection.blockRanges
        // Destination names, as paperDocumentDestinations gives them: valid
        // Anchor names first, then each heading's anchor or derived name.
        var used = Set(projection.blockAtoms.filter { $0.control == .anchor && anchorName($0.displayLabel) }.map(\.displayLabel))
        let names = headings.map { heading -> String in
            let text = string.substring(with: heading.range).replacingOccurrences(of: "\u{FFFC}", with: "")
                .replacingOccurrences(of: "\u{2028}", with: "")
            let identity = heading.headingID.flatMap { anchorName($0) ? $0 : nil } ?? slug(text)
            var name = identity, suffix = 2
            while used.contains(name) { name = "\(identity)-\(suffix)"; suffix += 1 }
            used.insert(name)
            return name
        }
        // A container ends where its last block ends; the paper ends at its text's end.
        func containerEnd(_ parent: [Int]) -> Int {
            guard !parent.isEmpty else { return string.length }
            var end = 0
            for (index, path) in paths.enumerated() where path.starts(with: parent) { end = max(end, NSMaxRange(ranges[index])) }
            return end
        }
        return headings.enumerated().map { index, heading in
            let parent = Array(heading.path.dropLast())
            let next = headings[(index + 1)...].first {
                Array($0.path.dropLast()) == parent && $0.level <= heading.level
            }
            let start = min(string.length, NSMaxRange(heading.range) + 1)
            let end = next.map { $0.range.location - 1 } ?? containerEnd(parent)
            return RelayPaperSection(id: names[index], level: heading.level, heading: heading.range,
                                     body: NSRange(location: start, length: max(0, end - start)))
        }
    }

    /// The anchor-name rule shared with the web: ASCII letters and digits, then
    /// letters, digits, `_` and `-`, at most 128 characters.
    static func anchorName(_ value: String) -> Bool {
        guard (1...128).contains(value.utf16.count), let first = value.unicodeScalars.first,
              first.isASCII, first.properties.isAlphabetic || ("0"..."9").contains(first) else { return false }
        return value.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-") }
    }

    /// A heading's derived destination name, as the web derives it: lower case,
    /// accents removed, other runs of characters as one `-`, at most 110 long.
    static func slug(_ text: String) -> String {
        let folded = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .decomposedStringWithCompatibilityMapping.unicodeScalars
            .filter { !(0x300...0x36F).contains($0.value) }
        var result = "", dash = false
        for scalar in folded {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-" {
                if dash, !result.isEmpty { result.append("-") }
                dash = false
                result.unicodeScalars.append(scalar)
            } else {
                dash = true
            }
        }
        // A leading run never added a dash; trailing runs are dropped by the flag.
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "section" : String(trimmed.prefix(110))
    }
}
