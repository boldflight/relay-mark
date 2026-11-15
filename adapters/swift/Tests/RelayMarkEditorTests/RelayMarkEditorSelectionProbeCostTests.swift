import Foundation
@testable import RelayMarkEditorCore
import Testing
@testable import RelayMarkNativeCollaboration
import RelayMarkSwift

/// What a host's selection commands cost while someone types. The host asks
/// for every structure command's availability after each selection change, so
/// this records (does not assert) the time and whole-paper reads per keystroke
/// in a realistic paper with the caret in a paragraph, a table cell and an
/// ordered-list item.
@MainActor @Suite("Selection command probe cost", .serialized)
struct RelayMarkEditorSelectionProbeCostTests {
    /// About 330 blocks: headings, paragraphs, bullet and ordered lists, and four tables.
    static let markdown: String = {
        var parts: [String] = []
        for section in 0..<25 {
            parts.append("## Section \(section)")
            for paragraph in 0..<6 {
                parts.append("Paragraph para-\(section)-\(paragraph) holds a few ordinary words of prose.")
            }
            parts.append((0..<3).map { "- bullet-\(section)-\($0) item" }.joined(separator: "\n"))
            parts.append((0..<3).map { "\($0 + 1). ordered-\(section)-\($0) item" }.joined(separator: "\n"))
            if section % 6 == 3 {
                let table = section / 6
                var rows = ["| Name | Note | Owner |", "| --- | --- | --- |"]
                for row in 0..<3 {
                    rows.append("| " + (0..<3).map { "cell-t\(table)-r\(row)c\($0)" }.joined(separator: " | ") + " |")
                }
                parts.append(rows.joined(separator: "\n"))
            }
        }
        return parts.joined(separator: "\n\n")
    }()

    private struct Sample {
        let elapsed: Duration
        let snapshots: Int
        let encodes: Int
        let typed: Int
    }

    /// Types `count` characters after `needle`, with the two selection changes a
    /// real keystroke reports, each answered by the host's structure probes.
    private func type(after needle: String, count: Int, probes: Bool = true) throws -> Sample {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(Self.markdown, namespace: "probe-cost"))
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
        if probes { editor.onSelectionChange = { [unowned editor] in
            _ = try? editor.prepareTableEdit()
            _ = try? editor.prepareListStartEdit()
            _ = try? editor.prepareCalloutAppearanceEdit()
            _ = try? editor.prepareCalloutTitleInsertion()
        } }
        let found = (String(editor.text.characters) as NSString).range(of: needle)
        #expect(found.location != NSNotFound, "\(needle) is in the paper")
        var caret = NSMaxRange(found), typed = 0
        editor.setNativeSelection(NSRange(location: caret, length: 0))
        let snapshots = document.wholePaperSnapshots, encodes = document.wholePaperEncodes
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<count {
                if editor.typeNatively(range: NSRange(location: caret, length: 0), replacement: "x") { typed += 1 }
                caret += 1
                // The text view reports its selection again once it adopts the edit.
                editor.setNativeSelection(NSRange(location: caret, length: 0))
            }
        }
        return Sample(elapsed: elapsed, snapshots: document.wholePaperSnapshots - snapshots,
                      encodes: document.wholePaperEncodes - encodes, typed: typed)
    }

    @Test("Typing with selection probes records its cost in a paragraph, a table cell and a list item")
    func recordsProbeCost() throws {
        let count = 40
        let carets = [("paragraph without probes", "para-12-3", false), ("paragraph", "para-12-3", true),
                      ("table cell", "cell-t1-r1c1", true), ("ordered item", "ordered-14-1", true)]
        for (label, needle, probes) in carets {
            let sample = try type(after: needle, count: count, probes: probes)
            #expect(sample.typed == count, "\(label) accepted every character")
            print("probe-cost \(label): \(count) keystrokes \(sample.elapsed) " +
                  "(\(sample.elapsed / count) each), snapshots \(sample.snapshots), full encodes \(sample.encodes)")
        }
    }

    /// The availability a caret had before the cheap prechecks: the whole
    /// paper's blocks and tree, read for every probe.
    /// The paper is not edited during the sweep, so its blocks and tree are read once.
    private struct Paper { let ranges: [NSRange]; let paths: [[Int]]; let tree: [String: Any] }

    private func paperWideTableCell(_ paper: Paper, at location: Int) -> Bool {
        let ranges = paper.ranges
        let candidates = ranges.indices.filter { location >= ranges[$0].location && location <= NSMaxRange(ranges[$0]) }
        guard candidates.count == 1 else { return false }
        var node = paper.tree
        var depth = 0, found = false
        for index in paper.paths[candidates[0]] {
            guard let children = node["children"] as? [[String: Any]], children.indices.contains(index) else { return false }
            node = children[index]; depth += 1
            if ["tableCell", "tableHeader"].contains(node["name"] as? String ?? ""),
               (node["attributes"] as? [String: Any])?["relaymarkId"] is String { found = depth >= 3 }
        }
        return found
    }

    private func paperWideListStart(_ paper: Paper, selection: NSRange) -> Int? {
        guard let row = paper.ranges.firstIndex(where: {
            selection.location >= $0.location && NSMaxRange(selection) <= NSMaxRange($0)
        }) else { return nil }
        var node = paper.tree
        for index in paper.paths[row].dropLast(2) {
            guard let children = node["children"] as? [[String: Any]], children.indices.contains(index) else { return nil }
            node = children[index]
        }
        guard node["name"] as? String == "orderedList" else { return nil }
        return (node["attributes"] as? [String: Any])?["start"] as? Int ?? 1
    }

    @Test("Cheap prechecks offer table and list-start commands at exactly the carets the whole paper does")
    func prechecksKeepTheOfferedCommands() throws {
        let nested = """
        Intro paragraph

        | A | B |
        | --- | --- |
        | one | two |
        | three | four |

        1. first
        2. second
           - nested bullet
           - another
             3. deep ordered
             4. deeper
        3. third

           with a second paragraph

        - bullet top
          5. ordered in bullet
          6. more

        > 7. quoted ordered
        > 8. quoted more

        | C |
        | --- |
        | lone |

        Last paragraph
        """
        let sections = Self.markdown.components(separatedBy: "## Section 4")[0]
        for markdown in [nested, sections] {
            let document = RelayMarkNativeDocument()
            _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(markdown, namespace: "probe-equivalence"))
            let editor = try RelayMarkEditorSession(document: document, persist: { _ in })
            let length = editor.text.utf16.count, projection = try editor.currentProjection()
            let paper = Paper(ranges: projection.blockRanges, paths: projection.blockPaths,
                              tree: try #require(try document.editingTree()))
            var tables = 0, lists = 0
            for location in 0...length {
                editor.setNativeSelection(NSRange(location: location, length: 0))
                let table = (try? editor.prepareTableEdit()) != nil
                #expect(table == paperWideTableCell(paper, at: location), "table command at \(location)")
                for span in [0, 1, 4] where location + span <= length {
                    let selection = NSRange(location: location, length: span)
                    editor.setNativeSelection(selection)
                    let start = try? editor.prepareListStartEdit().start
                    #expect(start == paperWideListStart(paper, selection: selection), "list start at \(selection)")
                    if span == 0, start != nil { lists += 1 }
                }
                if table { tables += 1 }
            }
            #expect(tables > 0 && lists > 0, "the paper offers both commands somewhere")
        }
    }
}
