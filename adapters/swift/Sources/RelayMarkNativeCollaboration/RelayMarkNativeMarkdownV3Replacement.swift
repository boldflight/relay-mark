import Foundation

/// Selection replacement over authored inline XML and adjacent textblocks.
/// Yrs supplies the transaction and undo; no Markdown serialization or CRDT
/// replacement is involved. Untouched prefix nodes stay in the same replica.
@MainActor
public enum RelayMarkNativeMarkdownV3Replacement {
    private typealias XML = RelayMarkNativeMarkdownV3XML

    public static func replace(document: RelayMarkNativeDocument, range: NSRange,
                               runs: [(text: String, attributes: [String: Any])],
                               expectedSnapshot: Data) throws -> Data {
        guard document.integrationStatus().isComplete, try document.snapshot() == expectedSnapshot,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let projection = try document.markdownV3ProseProjection(), text = String(projection.text.characters)
        guard projection.isEditable, range.location >= 0, range.length >= 0,
              NSMaxRange(range) <= text.utf16.count, Range(range, in: text) != nil,
              let first = projection.blockRanges.firstIndex(where: {
                  range.location >= $0.location && range.location <= NSMaxRange($0)
              }), let last = projection.blockRanges.firstIndex(where: {
                  NSMaxRange(range) >= $0.location && NSMaxRange(range) <= NSMaxRange($0)
              }), first <= last else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let firstPath = projection.blockPaths[first], lastPath = projection.blockPaths[last]
        let startNode = try XML.node(at: firstPath, in: tree), endNode = try XML.node(at: lastPath, in: tree)
        guard ["paragraph", "heading"].contains(startNode["name"] as? String ?? ""),
              ["paragraph", "heading"].contains(endNode["name"] as? String ?? "") else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let startOffset = range.location - projection.blockRanges[first].location
        let endOffset = NSMaxRange(range) - projection.blockRanges[last].location
        let prefix = try XML.splitInline(XML.children(startNode), at: startOffset, path: firstPath)
        let suffix = try XML.splitInline(XML.children(endNode), at: endOffset, path: lastPath).suffix
        var insertedRuns: [[String: Any]] = [], length = 0
        for run in runs {
            guard !run.text.isEmpty, run.text.utf16.count <= 131_072 - length,
                  JSONSerialization.isValidJSONObject(run.attributes),
                  !run.text.unicodeScalars.contains(where: {
                      $0 == "\u{FFFC}" || $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}"
                  }) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            length += run.text.utf16.count
            insertedRuns.append(["insert": run.text, "attributes": run.attributes])
        }
        let inline = (insertedRuns.isEmpty ? [] : [["kind": "text", "delta": insertedRuns]]) + suffix
        var edits = [RelayMarkNativeDocument.SnapshotNodeReplacement(parentPath: firstPath,
            start: prefix.removeFrom, count: try XML.children(startNode).count - prefix.removeFrom, nodes: inline)]
        if firstPath != lastPath {
            let parentPath = Array(firstPath.dropLast()), endParentPath = Array(lastPath.dropLast())
            if parentPath == endParentPath {
                guard let startIndex = firstPath.last, let endIndex = lastPath.last, startIndex < endIndex,
                      last - first == endIndex - startIndex else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                let parent = try XML.node(at: parentPath, in: tree), body = try XML.children(parent)
                guard body[(startIndex + 1)...endIndex].allSatisfy({
                    ["paragraph", "heading"].contains($0["name"] as? String ?? "")
                }) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                edits.append(.init(parentPath: parentPath, start: startIndex + 1, count: endIndex - startIndex, nodes: []))
            } else {
                // Joining sibling list items preserves the first item's identity,
                // checked state and relationship. The right item's remaining
                // body becomes part of the left item, like community list joins.
                let listPath = Array(parentPath.dropLast())
                guard listPath == Array(endParentPath.dropLast()),
                      let startItem = parentPath.last, let endItem = endParentPath.last, startItem < endItem,
                      let firstBlock = firstPath.last, lastPath.last == 0 else {
                    throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
                }
                let list = try XML.node(at: listPath, in: tree), items = try XML.children(list)
                let itemName = list["name"] as? String == "taskList" ? "taskItem" : "listItem"
                guard ["bulletList", "orderedList", "taskList"].contains(list["name"] as? String ?? ""),
                      try XML.children(items[startItem]).count == firstBlock + 1,
                      items[startItem...endItem].allSatisfy({ $0["name"] as? String == itemName }) else {
                    throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
                }
                for index in (startItem + 1)...endItem {
                    let item = items[index], body = try XML.children(item)
                    let entity = (item["attributes"] as? [String: Any])?["entityId"]
                    guard entity == nil || entity is NSNull else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                    if index < endItem {
                        guard body.count == 1, body[0]["name"] as? String == "paragraph" else {
                            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
                        }
                    }
                }
                guard last - first == endItem - startItem else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                let tail = Array(try XML.children(items[endItem]).dropFirst())
                if !tail.isEmpty { edits.append(.init(parentPath: parentPath, start: firstBlock + 1, count: 0, nodes: tail)) }
                edits.append(.init(parentPath: listPath, start: startItem + 1, count: endItem - startItem, nodes: []))
            }
            // Synthetic cell delimiters and non-text block placeholders are not
            // prose: replacing them requires their structural editor command.
            for row in first..<last {
                let gap = NSRange(location: NSMaxRange(projection.blockRanges[row]),
                                  length: projection.blockRanges[row + 1].location - NSMaxRange(projection.blockRanges[row]))
                guard gap.length == 1, (text as NSString).substring(with: gap) == "\n" else {
                    throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
                }
            }
        }
        return try XML.apply(document: document, tree: tree, edits: edits, trims: prefix.trim.map { [$0] } ?? [])
    }
}
