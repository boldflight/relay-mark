import Foundation
import RelayMarkProseProjection

/// Authored v3 suggestion commands over the existing YSwift/Yrs document.
/// The host owns proposal actions and authorization; these commands change
/// only the exact authored block the editor displayed.
@MainActor
public enum RelayMarkNativeAgentSuggestionMutation {
    /// A bounded shared converter handles one ordinary Markdown block. The host
    /// can hide Accept for every shape it cannot preserve.
    public static func canAccept(_ content: String) -> Bool {
        RelayMarkNativeMarkdownV3SingleBlock.canConvert(content)
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
        let block = try RelayMarkNativeMarkdownV3SingleBlock.parse(expectedContent)
        let headingID: String?
        switch block.kind {
        case .paragraph, .quote, .code, .rule, .bulletList, .orderedList: headingID = nil
        case .heading:
            // Browser PaperHeading assigns a fresh h-UUID on insertion. Keep
            // the same v3 attribute shape and avoid anchors already in paper.
            var candidate: String
            repeat { candidate = "h-" + UUID().uuidString.lowercased() }
            while blocks.contains(where: {
                ($0["attributes"] as? [String: Any])?["headingId"] as? String == candidate
            })
            headingID = candidate
        }
        let quoteParagraphID: String?
        if case .quote = block.kind {
            quoteParagraphID = "b" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        } else { quoteParagraphID = nil }
        func freshBlockID() -> String {
            "b" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        let listIDs = block.listItems.map { _ in (item: freshBlockID(), paragraph: freshBlockID()) }
        blocks[index] = try block.snapshot(id: newBlockID, headingID: headingID,
                                           quoteParagraphID: quoteParagraphID, listIDs: listIDs)
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
                                               block: block, newBlockID: newBlockID,
                                               headingID: headingID,
                                               quoteParagraphID: quoteParagraphID, listIDs: listIDs)
        guard try RelayMarkNativeMarkdownBlocksV3Projection.project(document: scratch) == expectedAST,
              try scratch.markdownV3ProseProjection().isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return try document.acceptAgentSuggestion(at: index, expectedID: expectedID,
                                                   block: block, newBlockID: newBlockID,
                                                   headingID: headingID,
                                                   quoteParagraphID: quoteParagraphID, listIDs: listIDs)
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
