import Foundation
import Markdown
import RelayMarkProseProjection

/// Authored v3 suggestion commands over the existing YSwift/Yrs document.
/// The host owns proposal actions and authorization; these commands change
/// only the exact authored block the editor displayed.
@MainActor
public enum RelayMarkNativeAgentSuggestionMutation {
    private struct Run {
        let text: String
        let attributes: [String: Any]
    }

    /// The first native Accept slice admits one Markdown paragraph with
    /// ordinary text, emphasis, strong, code, and untitled links only.
    public static func canAccept(_ content: String) -> Bool {
        (try? parsedRuns(content)) != nil
    }

    public static func accept(document: RelayMarkNativeDocument, atRootIndex index: Int,
                              expectedID: String, expectedReview: String, expectedKind: String,
                              expectedConfidence: Double?, expectedEvidence: [String],
                              expectedContent: String, newBlockID: String) throws -> Data {
        let prose = try document.markdownV3ProseProjection()
        guard prose.isEditable,
              let atom = prose.suggestionAtoms.first(where: { $0.path == [index] }),
              atom.id == expectedID, atom.review == expectedReview,
              atom.kind == expectedKind, atom.confidence == expectedConfidence,
              atom.evidence == expectedEvidence, atom.content == expectedContent,
              let root = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any],
              var blocks = root["children"] as? [[String: Any]], blocks.indices.contains(index),
              blocks[index]["name"] as? String == "agentSuggestion",
              let attributes = blocks[index]["attributes"] as? [String: Any],
              !blocks.contains(where: {
                  ($0["attributes"] as? [String: Any])?["relaymarkId"] as? String == newBlockID
              }) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let authored = try RelayMarkAgentSuggestionV3Contract.validate(attributes: attributes)
        guard authored.id == expectedID, authored.review == expectedReview,
              authored.kind == expectedKind, authored.confidence == expectedConfidence,
              authored.evidence == expectedEvidence, authored.content == expectedContent else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let runs = try parsedRuns(expectedContent)
        let paragraph: [String: Any] = [
            "kind": "element", "name": "paragraph", "attributes": ["relaymarkId": newBlockID],
            "children": [["kind": "text", "delta": runs.map {
                ["insert": $0.text, "attributes": $0.attributes] as [String: Any]
            }]]
        ]
        blocks[index] = paragraph
        var candidate = root
        candidate["children"] = blocks
        let candidateData = try JSONSerialization.data(withJSONObject: candidate)
        let expectedAST = try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: candidateData)
        guard try RelayMarkCollaborativeProse(snapshot: candidateData, dialect: .markdownV3).isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        _ = try scratch.acceptAgentSuggestion(at: index, expectedID: expectedID,
                                               newBlockID: newBlockID, runs: runs.map { ($0.text, $0.attributes) })
        guard try RelayMarkNativeMarkdownBlocksV3Projection.project(document: scratch) == expectedAST,
              try scratch.markdownV3ProseProjection().isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return try document.acceptAgentSuggestion(at: index, expectedID: expectedID,
                                                   newBlockID: newBlockID,
                                                   runs: runs.map { ($0.text, $0.attributes) })
    }

    private static func parsedRuns(_ content: String) throws -> [Run] {
        guard !content.isEmpty, content.utf16.count <= 32_768,
              content == content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.contains("\r"), !content.contains("\0") else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let parsed = Document(parsing: content)
        guard parsed.childCount == 1, let paragraph = parsed.child(at: 0) as? Paragraph,
              paragraph.childCount > 0 else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        var runs: [Run] = []
        func append(_ markup: Markup, marks: [String: Any]) throws {
            if let value = markup as? Text {
                if !value.string.isEmpty { runs.append(Run(text: value.string, attributes: marks)) }
            } else if let value = markup as? InlineCode {
                guard marks.isEmpty else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                if !value.code.isEmpty { runs.append(Run(text: value.code, attributes: ["code": [String: Any]()])) }
            } else if let value = markup as? Strong {
                var nested = marks
                nested["bold"] = [String: Any]()
                for child in value.children { try append(child, marks: nested) }
            } else if let value = markup as? Emphasis {
                var nested = marks
                nested["italic"] = [String: Any]()
                for child in value.children { try append(child, marks: nested) }
            } else if let value = markup as? Link {
                guard marks["link"] == nil, value.title == nil,
                      let href = value.destination, !href.isEmpty,
                      let url = URL(string: href), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      url.host != nil else {
                    throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
                }
                var nested = marks
                nested["link"] = ["href": href, "target": "_blank",
                                  "rel": "noopener noreferrer nofollow", "class": NSNull(),
                                  "title": NSNull()] as [String: Any]
                for child in value.children { try append(child, marks: nested) }
            } else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        }
        for child in paragraph.children { try append(child, marks: [:]) }
        guard !runs.isEmpty, runs.count <= 4_096 else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return runs
    }

    public static func dismiss(document: RelayMarkNativeDocument, atRootIndex index: Int,
                               expectedID: String, expectedReview: String, expectedKind: String,
                               expectedConfidence: Double?, expectedEvidence: [String],
                               expectedContent: String) throws -> Data {
        let prose = try document.markdownV3ProseProjection()
        guard prose.isEditable,
              let atom = prose.suggestionAtoms.first(where: { $0.path == [index] }),
              atom.id == expectedID, atom.review == expectedReview,
              atom.kind == expectedKind, atom.confidence == expectedConfidence,
              atom.evidence == expectedEvidence, atom.content == expectedContent,
              let root = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any],
              var blocks = root["children"] as? [[String: Any]], blocks.indices.contains(index),
              blocks[index]["name"] as? String == "agentSuggestion",
              let attributes = blocks[index]["attributes"] as? [String: Any] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let authored = try RelayMarkAgentSuggestionV3Contract.validate(attributes: attributes)
        guard authored.id == expectedID, authored.review == expectedReview,
              authored.kind == expectedKind, authored.confidence == expectedConfidence,
              authored.evidence == expectedEvidence, authored.content == expectedContent else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }

        blocks.remove(at: index)
        var candidate = root
        candidate["children"] = blocks
        let candidateData = try JSONSerialization.data(withJSONObject: candidate)
        let expectedAST = try RelayMarkNativeMarkdownBlocksV3Projection.project(snapshot: candidateData)
        guard try RelayMarkCollaborativeProse(snapshot: candidateData, dialect: .markdownV3).isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }

        // The scratch replica proves that the Yrs mutation produces precisely
        // the canonical v3 result before touching the live document.
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        let change = RelayMarkNativeDocument.PaperControlChange.remove(
            tag: "agentSuggestion", expectedID: expectedID)
        _ = try scratch.mutatePaperControl(at: index, change: change)
        guard try RelayMarkNativeMarkdownBlocksV3Projection.project(document: scratch) == expectedAST,
              try scratch.markdownV3ProseProjection().isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return try document.mutatePaperControl(at: index, change: change)
    }
}
