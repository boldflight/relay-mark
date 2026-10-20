import Foundation
@testable import RelayMarkEditor
import RelayMarkNativeCollaboration
import Testing

@MainActor
@Suite("Native v3 selection replacement")
struct RelayMarkEditorSelectionReplacementTests {
    private func path(of id: String, in node: [String: Any], prefix: [Int] = []) -> [Int]? {
        if (node["attributes"] as? [String: Any])?["relaymarkId"] as? String == id { return prefix }
        for (index, child) in (node["children"] as? [[String: Any]] ?? []).enumerated() {
            if let found = path(of: id, in: child, prefix: prefix + [index]) { return found }
        }
        return nil
    }

    private func withoutIDs(_ value: Any) -> Any {
        if var object = value as? [String: Any] {
            if var attributes = object["attributes"] as? [String: Any], object["kind"] as? String == "element" {
                attributes["relaymarkId"] = nil
                object["attributes"] = attributes
            }
            return object.mapValues(withoutIDs)
        }
        if let array = value as? [Any] { return array.map(withoutIDs) }
        return value
    }

    private func canonical(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: withoutIDs(value), options: [.sortedKeys]),
               as: UTF8.self)
    }

    /// Selections into and out of isolating table cells, across a callout
    /// into code, and across nested list levels go through the native
    /// replacement path and adopt ProseMirror's structure and caret.
    @Test("Cross-container native replacement adopts ProseMirror's result and caret")
    func crossContainerReplacement() throws {
        let url = try #require(Bundle.module.url(forResource: "native-selection-v3",
                                                 withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seedText = try #require(fixture["seed"] as? String)
        let seed = try #require(Data(base64Encoded: seedText))
        let cases = try #require(fixture["cases"] as? [[String: Any]])
        #expect(cases.count == 15)
        for entry in cases {
            let action = try #require(entry["action"] as? String)
            let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            try document.applyUpdate(seed)
            try peer.applyUpdate(seed)
            var saved: [Data] = []
            let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
            let tree = try #require(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
            let prose = try document.richProseProjection()
            func location(_ key: String) throws -> Int {
                let endpoint = try #require(entry[key] as? [String: Any])
                let id = try #require(endpoint["id"] as? String), offset = try #require(endpoint["offset"] as? Int)
                let blockPath = try #require(path(of: id, in: tree))
                let block = try #require(prose.blockPaths.firstIndex(of: blockPath))
                return prose.blockRanges[block].location + offset
            }
            let start = try location("from"), end = try location("to")
            let range = NSRange(location: start, length: end - start)
            let inserted = action == "delete" ? "" : action == "insertText" ? "X" : "P1\nP2"
            let baseline = String(editor.text.characters)
            #expect(editor.acceptsNativeReplacement(baseline: baseline, range: range, replacement: inserted), "\(action)")
            let candidate = AttributedString((baseline as NSString).replacingCharacters(in: range, with: inserted))
            editor.setNativeSelection(NSRange(location: start + inserted.utf16.count, length: 0))
            editor.edit(candidate, nativeReplacement: RelayNativeTextReplacement(baseline: baseline, range: range,
                replacement: inserted), nativePaste: nil)
            #expect(editor.failure == nil && saved.count == 1, "\(action): \(editor.failure ?? "not saved")")
            let after = try #require(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
            let expected = try #require(entry["after_xml"] as? [String: Any])
            #expect(try canonical(after) == canonical(expected), "\(action)")
            let projected = try document.richProseProjection()
            #expect(String(editor.text.characters) == String(projected.text.characters))
            let selection = try #require(entry["selection_after"] as? [String: Any])
            if let id = selection["id"] as? String, let caretPath = path(of: id, in: expected),
               let offset = selection["offset"] as? Int, let block = projected.blockPaths.firstIndex(of: caretPath) {
                #expect(editor.nativeSelection == NSRange(location: projected.blockRanges[block].location + offset, length: 0),
                        "\(action) caret")
            }
            try peer.applyUpdate(try #require(saved.last))
            #expect(try document.snapshot() == peer.snapshot())
        }
    }

    /// A native deletion of a block separator beside a collapsed caret is
    /// Backspace or Delete through the browser's keymaps: list and quote
    /// lifts, item joins, and no change at isolating table cells.
    @Test("Boundary Backspace and Delete follow the browser keymaps")
    func boundaryKeys() throws {
        let url = try #require(Bundle.module.url(forResource: "native-selection-v3",
                                                 withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seedText = try #require(fixture["seed"] as? String)
        let seed = try #require(Data(base64Encoded: seedText))
        let cases = try #require(fixture["keys"] as? [[String: Any]])
        #expect(cases.count == 12)
        for entry in cases {
            let action = try #require(entry["action"] as? String)
            let document = RelayMarkNativeDocument()
            try document.applyUpdate(seed)
            var saved: [Data] = []
            let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
            let tree = try #require(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
            let prose = try document.richProseProjection()
            let endpoint = try #require(entry["from"] as? [String: Any])
            let id = try #require(endpoint["id"] as? String), offset = try #require(endpoint["offset"] as? Int)
            let blockPath = try #require(path(of: id, in: tree))
            let block = try #require(prose.blockPaths.firstIndex(of: blockPath))
            let caret = prose.blockRanges[block].location + offset
            let range = NSRange(location: action == "Backspace" ? caret - 1 : caret, length: 1)
            let baseline = String(editor.text.characters), original = editor.text
            editor.setNativeSelection(NSRange(location: caret, length: 0))
            #expect(editor.acceptsNativeReplacement(baseline: baseline, range: range, replacement: ""), "\(action) \(id)")
            let candidate = AttributedString((baseline as NSString).replacingCharacters(in: range, with: ""))
            let before = try document.snapshot()
            editor.edit(candidate, nativeReplacement: RelayNativeTextReplacement(baseline: baseline, range: range,
                replacement: ""), nativePaste: nil)
            #expect(editor.failure == nil, "\(action) \(id): \(editor.failure ?? "")")
            let unchanged = (entry["update"] as? String).map { $0.count < 8 } ?? true
            if unchanged {
                let current = try document.snapshot()
                #expect(saved.isEmpty && current == before && editor.text == original, "\(action) \(id)")
                continue
            }
            #expect(saved.count == 1, "\(action) \(id)")
            let after = try #require(JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any])
            let expected = try #require(entry["after_xml"] as? [String: Any])
            #expect(try canonical(after) == canonical(expected), "\(action) \(id)")
            let projected = try document.richProseProjection()
            #expect(String(editor.text.characters) == String(projected.text.characters))
            let selection = try #require(entry["selection_after"] as? [String: Any])
            if let selected = selection["id"] as? String, let caretPath = path(of: selected, in: expected),
               let caretOffset = selection["offset"] as? Int, let row = projected.blockPaths.firstIndex(of: caretPath) {
                #expect(editor.nativeSelection == NSRange(location: projected.blockRanges[row].location + caretOffset, length: 0),
                        "\(action) \(id) caret")
            }
        }
    }

    @Test("Reference and tag pickers insert linked labels and stable tags at the bound caret")
    func referenceInsertion() throws {
        let url = try #require(Bundle.module.url(forResource: "native-selection-v3",
                                                 withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seedText = try #require(fixture["seed"] as? String)
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let seed = try #require(Data(base64Encoded: seedText))
        try document.applyUpdate(seed)
        try peer.applyUpdate(seed)
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let quote = (String(editor.text.characters) as NSString).range(of: "Quote five")
        editor.setNativeSelection(NSRange(location: NSMaxRange(quote), length: 0))
        let stale = try editor.prepareReferenceInsertion(.tag)
        editor.setNativeSelection(NSRange(location: quote.location, length: 0))
        editor.insertTag(id: "11111111-2222-4333-8444-555555555555", name: "native-proof", using: stale)
        #expect(editor.failure != nil && saved.isEmpty)

        let fresh = RelayMarkNativeDocument()
        try fresh.applyUpdate(seed)
        let session = try RelayMarkEditorSession(document: fresh, persist: { saved.append($0.update) })
        session.setNativeSelection(NSRange(location: NSMaxRange(quote), length: 0))
        let tag = try session.prepareReferenceInsertion(.tag)
        session.insertTag(id: "11111111-2222-4333-8444-555555555555", name: "native-proof", using: tag)
        #expect(session.failure == nil && saved.count == 1)
        let entity = try session.prepareEntityReferenceInsertion()
        session.insertEntityReference(id: "66666666-7777-4888-8999-aaaaaaaaaaaa", label: "Alex", using: entity)
        #expect(session.failure == nil && saved.count == 2)
        let text = String(session.text.characters)
        #expect(text.contains("Quote five\u{FFFC} Alex "))
        #expect(session.nativeSelection == NSRange(location: NSMaxRange(quote) + 7, length: 0))
        let snapshot = String(decoding: try fresh.snapshot(), as: UTF8.self)
        #expect(snapshot.replacingOccurrences(of: "\\/", with: "/").contains("relay:entity/66666666-7777-4888-8999-aaaaaaaaaaaa"))
        #expect(snapshot.contains("[[Tag: 11111111-2222-4333-8444-555555555555 | #native-proof]]"))
        for update in saved { try peer.applyUpdate(update) }
        #expect(try fresh.snapshot() == peer.snapshot())
    }

    @Test("Host Atlas choices cannot insert through a stale native caret")
    func staleAtlasReferenceInsertion() throws {
        let (document, _) = try seededDocument()
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let quote = (String(editor.text.characters) as NSString).range(of: "Quote five")
        editor.setNativeSelection(NSRange(location: NSMaxRange(quote), length: 0))
        let insertion = try editor.prepareEntityReferenceInsertion()
        let before = try document.snapshot()
        editor.setNativeSelection(NSRange(location: quote.location, length: 0))
        editor.insertEntityReference(id: "66666666-7777-4888-8999-aaaaaaaaaaaa", label: "Atlas item", using: insertion)
        #expect(editor.failure == RelayMarkEditorSession.InlineAtomEditFailure.changed.localizedDescription)
        #expect(saved.isEmpty)
        #expect(try document.snapshot() == before)
    }

    private func seededDocument() throws -> (RelayMarkNativeDocument, Data) {
        let url = try #require(Bundle.module.url(forResource: "native-selection-v3",
                                                 withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let seedText = try #require(fixture["seed"] as? String)
        let seed = try #require(Data(base64Encoded: seedText))
        let document = RelayMarkNativeDocument()
        try document.applyUpdate(seed)
        return (document, seed)
    }

    @Test("Return over a selection deletes it and splits the list item in one undo step")
    func returnOverSelection() throws {
        let (document, _) = try seededDocument()
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let before = try document.snapshot(), baseline = String(editor.text.characters)
        let bullet = (baseline as NSString).range(of: "Bullet one")
        let range = NSRange(location: bullet.location + 4, length: 4)
        editor.setNativeSelection(range)
        #expect(editor.acceptsNativeReplacement(baseline: baseline, range: range, replacement: "\n"))
        let candidate = AttributedString((baseline as NSString).replacingCharacters(in: range, with: "\n"))
        editor.edit(candidate, nativeReplacement: RelayNativeTextReplacement(baseline: baseline, range: range,
            replacement: "\n"), nativePaste: nil)
        #expect(editor.failure == nil && saved.count == 1, "\(editor.failure ?? "")")
        #expect(String(editor.text.characters).contains("Bull\nne\n"))
        let prose = try document.richProseProjection()
        let tail = try #require(prose.blockRanges.firstIndex { ($0.location, $0.length) == (bullet.location + 5, 2) })
        #expect(prose.blockPaths[tail] == [2, 1, 0], "the tail becomes a new list item")
        #expect(editor.nativeSelection == NSRange(location: bullet.location + 5, length: 0))
        editor.undo()
        #expect(try document.snapshot() == before)
    }

    @Test("Backspace at the document start lifts a first list item as the browser does")
    func backspaceAtDocumentStart() throws {
        let (document, _) = try seededDocument()
        let prose = try document.richProseProjection()
        let start = (String(prose.text.characters) as NSString).range(of: "Bullet one").location
        _ = try RelayMarkNativeRichEditing.replace(document: document, range: NSRange(location: 0, length: start),
                                                         runs: [], expectedSnapshot: document.snapshot())
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        #expect(String(editor.text.characters).hasPrefix("Bullet one\n"))
        #expect(try document.richProseProjection().blockPaths.first == [0, 0, 0])
        editor.setNativeSelection(NSRange(location: 0, length: 0))
        #expect(editor.handleNativeEdgeDeletion(backward: true))
        #expect(editor.failure == nil && saved.count == 1)
        #expect(try document.richProseProjection().blockPaths.first == [0])
        #expect(editor.nativeSelection == NSRange(location: 0, length: 0))
        editor.setNativeSelection(NSRange(location: 3, length: 0))
        #expect(!editor.handleNativeEdgeDeletion(backward: true))
    }

    @Test("Insert Table and Image place blocks at the caret with the browser's caret and one undo each")
    func blockInsertion() throws {
        let (document, _) = try seededDocument()
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let before = try document.snapshot()
        let alpha = (String(editor.text.characters) as NSString).range(of: "Alpha one")
        editor.setNativeSelection(NSRange(location: alpha.location + 5, length: 0))
        #expect(editor.canInsertBlock)
        editor.insertTable()
        #expect(editor.failure == nil && saved.count == 1)
        let prose = try document.richProseProjection()
        #expect(prose.tableCells.filter { $0.tableIdentity == prose.tableCells.first?.tableIdentity }.count == 9)
        let caret = try #require(editor.nativeSelection)
        #expect(prose.tableCells.first.map { NSLocationInRange(caret.location, $0.range) || $0.range.location == caret.location } == true)
        editor.undo()
        #expect(try document.snapshot() == before)

        let bullet = (String(editor.text.characters) as NSString).range(of: "Bullet four")
        editor.setNativeSelection(NSRange(location: bullet.location + 6, length: 0))
        let image = try editor.prepareReferenceInsertion(.image)
        editor.insertImage(try #require(URL(string: "https://example.com/b.png")), alt: " B ", using: image)
        #expect(editor.failure == nil && saved.count == 3)
        let media = try document.richProseProjection().mediaAtoms
        #expect(media.contains { $0.source == "https://example.com/b.png" && $0.alt == "B" })
    }
    @Test("Uploaded images use canonical media identities and reject stale insertion captures")
    func uploadedImageInsertion() throws {
        let (document, _) = try seededDocument()
        var saved: [Data] = []
        let editor = try RelayMarkEditorSession(document: document, persist: { saved.append($0.update) })
        let alpha = (String(editor.text.characters) as NSString).range(of: "Alpha one")
        editor.setNativeSelection(NSRange(location: alpha.location + 5, length: 0))
        let insertion = try editor.prepareReferenceInsertion(.image)
        let src = "/m/" + UUID().uuidString.lowercased()
        try editor.insertImageSource(src, alt: " Native photo ", using: insertion)
        #expect(saved.count == 1)
        #expect(try document.richProseProjection().mediaAtoms.contains { $0.source == src && $0.alt == "Native photo" })
        let after = try document.snapshot()
        #expect(throws: (any Error).self) {
            try editor.insertImageSource(src, alt: "Late upload", using: insertion)
        }
        #expect(try document.snapshot() == after)
        #expect(saved.count == 1)
        editor.undo()
        editor.setNativeSelection(NSRange(location: alpha.location + 5, length: 0))
        let fresh = try editor.prepareReferenceInsertion(.image)
        editor.setNativeSelection(NSRange(location: alpha.location + 6, length: 0))
        let beforeMoved = try document.snapshot()
        #expect(throws: (any Error).self) {
            try editor.insertImageSource(src, alt: "Moved cursor", using: fresh)
        }
        #expect(try document.snapshot() == beforeMoved)
    }

}
