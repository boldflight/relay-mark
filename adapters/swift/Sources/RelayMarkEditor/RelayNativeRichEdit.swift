import Foundation
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkProseProjection

/// Maps native attributed-text changes onto canonical Yrs XML.
/// Native typing marks resolve replacement across formatting boundaries.
/// Structural commands use the same document and durable host journal.
@MainActor
enum RelayNativeRichEdit {
    typealias ListReturnKind = RelayMarkNativeRichReturn.Kind
    struct ListReturnResult {
        let change: RelayMarkNativeRichEditing.Change
        let kind: ListReturnKind
    }
    struct Result {
        let update: Data
        let text: AttributedString
        init(update: Data, text: AttributedString) {
            self.update = update; self.text = text
        }
    }

    static func apply(document: RelayMarkNativeDocument, candidate: AttributedString) throws -> Result {
        let before = try document.richProseProjection()
        guard before.isEditable else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let replacement = replacement(from: documentSemantics(before.text, includeBlockIntent: false),
                                      to: documentSemantics(candidate, includeBlockIntent: false))
        let range = NSRange(location: replacement.start, length: replacement.end - replacement.start)
        let multiline = replacement.text.contains("\n") && !isCodeBlock(document: document, at: range.location)
        let location = multiline ? nil : try? textLocation(in: before, range: range)

        let runs = try insertionRuns(candidate: candidate, start: replacement.start,
            text: replacement.text, document: document, location: location)
        func apply(to target: RelayMarkNativeDocument) throws -> RelayMarkNativeRichEditing.Change {
            try RelayMarkNativeRichEditing.replace(document: target, range: range,
                runs: runs, expectedSnapshot: target.snapshot())
        }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        _ = try apply(to: scratch)
        let expected = try scratch.richProseProjection()
        guard expected.isEditable,
              documentSemantics(expected.text, includeBlockIntent: false) ==
                documentSemantics(candidate, includeBlockIntent: false) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let change = try apply(to: document)
        return Result(update: change.update, text: expected.text)
    }

    struct SelectionResult {
        let update: Data
        let text: AttributedString
        let caret: Int?
    }

    /// A native deletion of exactly one block separator with a collapsed
    /// caret beside it is Backspace (caret after) or Delete (caret before),
    /// which ProseMirror resolves through its keymaps rather than as a range.
    static func boundaryKey(document: RelayMarkNativeDocument, range: NSRange, replacement: String,
                            caret: NSRange?) -> (key: RelayMarkNativeRichEditing.Key, offset: Int)? {
        guard replacement.isEmpty, range.length == 1, let caret, caret.length == 0,
              let projection = try? document.richProseProjection(), projection.isEditable,
              let block = projection.blockRanges.firstIndex(where: { NSMaxRange($0) == range.location }),
              block + 1 < projection.blockRanges.count,
              projection.blockRanges[block + 1].location == NSMaxRange(range) else { return nil }
        if caret.location == NSMaxRange(range) { return (.backspace, NSMaxRange(range)) }
        if caret.location == range.location { return (.delete, range.location) }
        return nil
    }

    /// Whether ProseMirror must resolve this replacement structurally: it
    /// spans projected blocks, or inserts lines outside a code block.
    static func isStructuralSelection(document: RelayMarkNativeDocument, range: NSRange, replacement: String) -> Bool {
        guard let projection = try? document.richProseProjection(), projection.isEditable else { return false }
        func block(_ offset: Int) -> Int? {
            projection.blockRanges.firstIndex { offset >= $0.location && offset <= NSMaxRange($0) }
        }
        if replacement.contains("\n") { return !isCodeBlock(document: document, at: range.location) }
        return range.length > 0 && block(range.location) != block(NSMaxRange(range))
    }

    /// Replaces the native selection exactly as ProseMirror would for the
    /// same range and inserted runs. The result may differ from a naive text
    /// replacement (for example around isolating table cells); the caller
    /// adopts ProseMirror's text and caret, as a browser peer would see them.
    static func replaceSelection(document: RelayMarkNativeDocument, range: NSRange,
                                 candidate: AttributedString, insertedLength: Int, storedTextAttributes: Data? = nil) throws -> SelectionResult {
        let plain = String(candidate.characters) as NSString
        guard range.location >= 0, range.location + insertedLength <= plain.length else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let inserted = plain.substring(with: NSRange(location: range.location, length: insertedLength))
        let runs: [(text: String, attributes: [String: Any])]
        if let storedTextAttributes {
            _ = try RelayMarkCollaborativeProse.attributedText(text: inserted, attributes: storedTextAttributes)
            guard let attrs = try JSONSerialization.jsonObject(with: storedTextAttributes) as? [String: Any] else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            runs = inserted.isEmpty ? [] : [(inserted, attrs)]
        } else {
            runs = try insertionRuns(candidate: candidate, start: range.location, text: inserted,
                document: document, location: nil)
        }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        _ = try RelayMarkNativeRichEditing.replace(document: scratch, range: range, runs: runs,
                                                         expectedSnapshot: scratch.snapshot())
        let expected = try scratch.richProseProjection()
        guard expected.isEditable else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let change = try RelayMarkNativeRichEditing.replace(document: document, range: range, runs: runs,
                                                                  expectedSnapshot: document.snapshot())
        let caret = change.caret.flatMap { caret in
            expected.blockPaths.firstIndex(of: caret.blockPath).map { expected.blockRanges[$0].location + caret.offset }
        }
        return SelectionResult(update: change.update, text: expected.text, caret: caret)
    }

    static func supportsNativeReplacement(document: RelayMarkNativeDocument,
                                          baseline: String, range: NSRange,
                                          replacement: String) -> Bool {
        let code = isCodeBlock(document: document, at: range.location)
        if replacement == "\n", range.length == 0, range.location >= 0,
           range.location <= baseline.utf16.count,
           Range(range, in: baseline) != nil {
            do {
                let before = try document.richProseProjection()
                guard before.isEditable, baseline == String(before.text.characters) else { return false }
                let scratch = RelayMarkNativeDocument()
                try scratch.applyUpdate(document.encodeUpdate())
                let result = try structuralReturn(document: scratch, at: range.location)
                let after = try scratch.richProseProjection()
                let expected = result.kind == .exit ? baseline :
                    (baseline as NSString).replacingCharacters(in: range, with: "\n")
                return after.isEditable && String(after.text.characters) == expected
            } catch { return false }
        }
        guard range.location >= 0, range.length >= 0, replacement.utf16.count <= 131_072,
              !replacement.unicodeScalars.contains(where: {
                  $0 == "\u{FFFC}" || (!code && ($0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}"))
              }), NSMaxRange(range) <= baseline.utf16.count,
              Range(range, in: baseline) != nil else { return false }
        if isStructuralSelection(document: document, range: range, replacement: replacement) {
            do {
                guard try baseline == String(document.richProseProjection().text.characters) else { return false }
                let scratch = RelayMarkNativeDocument()
                try scratch.applyUpdate(document.encodeUpdate())
                _ = try RelayMarkNativeRichEditing.replace(document: scratch, range: range,
                    runs: replacement.isEmpty ? [] : [(replacement, [:])], expectedSnapshot: scratch.snapshot())
                return try scratch.richProseProjection().isEditable
            } catch { return false }
        }
        do {
            let before = try document.richProseProjection()
            guard before.isEditable, baseline == String(before.text.characters) else { return false }
            let scratch = RelayMarkNativeDocument()
            try scratch.applyUpdate(document.encodeUpdate())
            if !replacement.contains("\n") || code,
               let location = try? textLocation(in: before, range: range) {
                _ = try RelayMarkNativeRichTextMutation.replace(
                    document: scratch, path: location.path, start: location.start,
                    end: location.end, text: replacement, attributes: [:])
            } else {
                _ = try RelayMarkNativeRichReplacement.replace(document: scratch,
                    range: range, runs: replacement.isEmpty ? [] : [(replacement, [:])],
                    expectedSnapshot: scratch.snapshot())
            }
            let after = try scratch.richProseProjection()
            return after.isEditable && String(after.text.characters) ==
                (baseline as NSString).replacingCharacters(in: range, with: replacement)
        } catch { return false }
    }

    static func structuralReturn(document: RelayMarkNativeDocument, at offset: Int, selectionEnd: Int? = nil) throws -> ListReturnResult {
        let projection = try document.richProseProjection()
        guard projection.isEditable,
              let row = projection.blockRanges.enumerated().first(where: { _, range in
                  offset >= range.location && offset <= NSMaxRange(range)
              }) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let end: RelayMarkNativeRichEditing.Caret?
        if let selectionEnd {
            guard let head = projection.blockRanges.enumerated().first(where: { selectionEnd >= $0.element.location && selectionEnd <= NSMaxRange($0.element) }) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            end = .init(blockPath: projection.blockPaths[head.offset], offset: selectionEnd - head.element.location)
        } else { end = nil }
        let result = try RelayMarkNativeRichReturn.apply(document: document,
            blockPath: projection.blockPaths[row.offset], utf16Offset: offset - row.element.location, selectionEnd: end,
            expectedSnapshot: document.snapshot())
        return ListReturnResult(change: result.change, kind: result.kind)
    }

    private static func isCodeBlock(document: RelayMarkNativeDocument, at offset: Int) -> Bool {
        guard offset >= 0, let projection = try? document.richProseProjection(),
              let row = projection.blockRanges.enumerated().first(where: { _, range in
                  offset >= range.location && offset <= NSMaxRange(range)
              }), var node = (try? JSONSerialization.jsonObject(with: document.snapshot())) as? [String: Any] else { return false }
        for index in projection.blockPaths[row.offset] {
            guard let children = node["children"] as? [[String: Any]], children.indices.contains(index) else { return false }
            node = children[index]
        }
        return node["name"] as? String == "codeBlock"
    }

    private struct Location {
        let path: [Int]
        let start: Int
        let end: Int
    }

    private static func textLocation(in before: RelayMarkCollaborativeProse,
                                     range: NSRange) throws -> Location {
        let path: [Int]
        let start: Int
        let end: Int
        if range.length == 0 {
            guard let position = before.position(atUTF16: range.location) else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            path = position.path
            start = position.index
            end = position.index
        } else {
            let ranges = before.textRanges(in: range)
            guard ranges.count == 1, let slice = ranges.first,
                  slice.length == range.length else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            path = slice.path
            start = slice.index
            end = slice.index + slice.length
        }
        return Location(path: path, start: start, end: end)
    }

    static func format(document: RelayMarkNativeDocument, candidate: AttributedString,
                       range: NSRange, attributes: [String: Any]) throws -> Result {
        let before = try document.richProseProjection()
        guard before.isEditable, formattingSlices(in: before, range: range) != nil else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        func apply(to target: RelayMarkNativeDocument) throws -> Data {
            let vector = target.stateVector()
            var changed = false
            let ordered = attributes.keys.sorted { lhs, rhs in
                let leftRemoval = attributes[lhs] is NSNull, rightRemoval = attributes[rhs] is NSNull
                return leftRemoval == rightRemoval ? lhs < rhs : leftRemoval
            }
            for mark in ordered {
                guard let value = attributes[mark] else { continue }
                let enabled = !(value is NSNull)
                let attrs = enabled ? (value as? [String: Any] ?? [:]) : [:]
                if try RelayMarkNativeRichEditing.format(document: target, range: range,
                    mark: mark, attributes: attrs, enabled: enabled, expectedSnapshot: target.snapshot()) != nil {
                    changed = true
                }
            }
            guard changed else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            return try target.encodeUpdate(since: vector)
        }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        _ = try apply(to: scratch)
        let expected = try scratch.richProseProjection()
        guard expected.isEditable,
              formattingSemantics(expected.text, projection: before) ==
                formattingSemantics(candidate, projection: before) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return Result(update: try apply(to: document), text: expected.text)
    }

    static func supportsFormatting(_ projection: RelayMarkCollaborativeProse, range: NSRange) -> Bool {
        projection.isEditable && formattingSlices(in: projection, range: range) != nil
    }

    /// The shared PM mark command formats text across rich blocks and skips
    /// structural separators and nodes that disallow marks.
    private static func formattingSlices(in projection: RelayMarkCollaborativeProse,
                                         range: NSRange) -> [RelayMarkCollaborativeProse.TextRange]? {
        let plain = String(projection.text.characters)
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= plain.utf16.count,
              Range(range, in: plain) != nil else { return nil }
        for (index, block) in projection.blockRanges.enumerated()
            where NSIntersectionRange(block, range).length > 0 {
            guard projection.blockIntents.indices.contains(index) else { return nil }
            if projection.blockIntents[index].components.contains(where: {
                if case .codeBlock = $0.kind { return true }
                return false
            }) { return nil }
        }
        let slices = projection.textRanges(in: range)
        guard !slices.isEmpty else { return nil }
        // The maintained PM mark command skips nodes that disallow the mark.
        // Native separator/attachment presentation is not authored text.
        return slices
    }

    private static func formattingSemantics(_ value: AttributedString,
                                            projection: RelayMarkCollaborativeProse) -> AttributedString {
        var result = documentSemantics(value, includeBlockIntent: false)
        let range = NSRange(location: 0, length: String(projection.text.characters).utf16.count)
        var covered = Set<Int>()
        for slice in projection.textRanges(in: range) {
            guard let offset = projection.offset(path: slice.path, index: slice.index) else { continue }
            covered.formUnion(offset..<(offset + slice.length))
        }
        var offset = 0, index = value.startIndex
        while index < value.endIndex {
            let next = value.characters.index(after: index)
            let count = String(value[index..<next].characters).utf16.count
            if !(offset..<(offset + count)).contains(where: covered.contains) {
                result[index..<next].setAttributes(AttributeContainer())
            }
            offset += count; index = next
        }
        return result
    }

    // Compare Foundation attributed characters, including portable marks, so
    // rich paste can change formatting even when text shares a prefix/suffix.
    private static func replacement(from old: AttributedString, to new: AttributedString)
        -> (start: Int, end: Int, text: String) {
        var oldStart = old.startIndex, newStart = new.startIndex
        while oldStart < old.endIndex && newStart < new.endIndex {
            let oldNext = old.characters.index(after: oldStart)
            let newNext = new.characters.index(after: newStart)
            guard old[oldStart..<oldNext] == new[newStart..<newNext] else { break }
            oldStart = oldNext; newStart = newNext
        }
        var oldEnd = old.endIndex, newEnd = new.endIndex
        while oldEnd > oldStart && newEnd > newStart {
            let oldPrevious = old.characters.index(before: oldEnd)
            let newPrevious = new.characters.index(before: newEnd)
            guard old[oldPrevious..<oldEnd] == new[newPrevious..<newEnd] else { break }
            oldEnd = oldPrevious; newEnd = newPrevious
        }
        return (String(old[old.startIndex..<oldStart].characters).utf16.count,
                String(old[old.startIndex..<oldEnd].characters).utf16.count,
                String(new[newStart..<newEnd].characters))
    }

    /// The runs, with their marks, of rich text inserted as one piece.
    static func runs(of piece: AttributedString, document: RelayMarkNativeDocument) throws -> [(text: String, attributes: [String: Any])] {
        try insertionRuns(candidate: piece, start: 0, text: String(piece.characters), document: document, location: nil)
    }

    private static func insertionRuns(candidate: AttributedString, start: Int, text: String,
                                            document: RelayMarkNativeDocument,
                                            location: Location?) throws -> [(text: String, attributes: [String: Any])] {
        guard !text.isEmpty else { return [] }
        let plain = String(candidate.characters)
        guard let range = Range(NSRange(location: start, length: text.utf16.count), in: plain),
              let lower = AttributedString.Index(range.lowerBound, within: candidate),
              let upper = AttributedString.Index(range.upperBound, within: candidate) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        var resolved: [(text: String, attributes: [String: Any])] = []
        for run in candidate[lower..<upper].runs {
            var marks: [String: Any] = [:]
            let intent = run.inlinePresentationIntent ?? []
            for (flag, name) in [(InlinePresentationIntent.stronglyEmphasized, "bold"),
                                 (.emphasized, "italic"), (.strikethrough, "strike"), (.code, "code")]
                where intent.contains(flag) { marks[name] = [String: Any]() }
            for mark in run[RelayMarkOfferedMarksAttribute.self] ?? [] {
                marks[mark.rawValue] = [String: Any]()
            }
            if let link = run.link {
                let existing = try location.flatMap {
                    try existingLink(document: document, location: $0, href: link.absoluteString)
                }
                marks["link"] = existing ?? ["href": link.absoluteString, "target": "_blank",
                     "rel": "noopener noreferrer nofollow", "class": NSNull(), "title": NSNull()]
            }
            resolved.append((String(candidate[run.range].characters), marks))
        }
        return resolved
    }

    // Preserve authored link metadata when native typing retains that link.
    // Display attributes do not carry target/rel/class/title, so read the nearby
    // existing Yrs run rather than silently replacing its declaration.
    private static func existingLink(document: RelayMarkNativeDocument, location: Location,
                                     href: String) throws -> [String: Any]? {
        guard var node = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any] else {
            return nil
        }
        for index in location.path {
            guard let children = node["children"] as? [[String: Any]],
                  children.indices.contains(index) else { return nil }
            node = children[index]
        }
        var offset = 0
        for run in node["delta"] as? [[String: Any]] ?? [] {
            let end = offset + (run["insert"] as? String ?? "").utf16.count
            if location.start >= offset, location.start <= end,
               let marks = run["attributes"] as? [String: Any],
               let link = marks["link"] as? [String: Any], link["href"] as? String == href {
                return link
            }
            offset = end
        }
        return nil
    }

    private static func documentSemantics(_ value: AttributedString, includeBlockIntent: Bool = true) -> AttributedString {
        var result = value
        for run in value.runs {
            result[run.range].setAttributes(AttributeContainer())
            let inline = run.inlinePresentationIntent ?? []
            result[run.range].inlinePresentationIntent = inline.isEmpty ? nil : inline
            result[run.range].link = run.link
            if includeBlockIntent { result[run.range].presentationIntent = run.presentationIntent }
            result[run.range][RelayMarkOfferedMarksAttribute.self] = run[RelayMarkOfferedMarksAttribute.self]
        }
        if !includeBlockIntent {
            // Native rich paste carries font/link attributes on line endings.
            // Paragraph separators are structural in Yjs, not authored XmlText;
            // the replica supplies their presentation after applying the edit.
            var index = value.startIndex
            while index < value.endIndex {
                let next = value.characters.index(after: index)
                if String(value[index..<next].characters) == "\n" {
                    result[index..<next].setAttributes(AttributeContainer())
                }
                index = next
            }
        }
        return result
    }
}

@MainActor
extension RelayNativeRichEdit {
    static func formattingChange(before: AttributedString, after: AttributedString, range: NSRange,
                                         mark: RelayMarkFormattingMark?, exclusiveCode: Bool = false) -> RelayNativeFormattingChange? {
        let plain = String(before.characters)
        guard range.location >= 0, range.length > 0, range.location <= plain.utf16.count,
              range.length <= plain.utf16.count - range.location,
              let nativeRange = Range(range, in: plain),
              let lower = AttributedString.Index(nativeRange.lowerBound, within: before),
              let upper = AttributedString.Index(nativeRange.upperBound, within: before) else { return nil }
        for mark in mark.map({ [$0] }) ?? [.bold, .italic] {
            let flag = mark.inlineIntent
            for enabled in [false, true] {
                var expected = before
                for run in before[lower..<upper].runs {
                    var intent = run.inlinePresentationIntent ?? []
                    if enabled {
                        if exclusiveCode {
                            if mark == .code {
                                intent.remove([.stronglyEmphasized, .emphasized, .strikethrough])
                                expected[run.range].link = nil
                            } else { intent.remove(.code) }
                        }
                        intent.insert(flag)
                    } else { intent.remove(flag) }
                    expected[run.range].inlinePresentationIntent = intent
                }
                if formattingComparable(expected) != formattingComparable(before), formattingComparable(expected) == formattingComparable(after) {
                    return .init(startUTF16: range.location, lengthUTF16: range.length, mark: mark, enabled: enabled)
                }
            }
        }
        return nil
    }

    /// Paragraph separators have no Yjs text identities or stored inline marks.
    static func formattingComparable(_ value: AttributedString) -> AttributedString {
        var result = value
        for index in value.characters.indices where value.characters[index] == "\n" {
            let next = value.characters.index(after: index)
            var intent = result[index..<next].inlinePresentationIntent ?? []
            intent.remove([.stronglyEmphasized, .emphasized, .strikethrough, .code])
            result[index..<next].inlinePresentationIntent = intent.isEmpty ? nil : intent
        }
        return result
    }

}
