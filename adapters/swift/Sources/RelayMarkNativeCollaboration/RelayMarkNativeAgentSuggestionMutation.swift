import Foundation
import RelayMarkProseProjection

/// Authored v3 suggestion commands over the existing YSwift/Yrs document.
/// The host owns proposal actions and authorization; this only dismisses the
/// exact authored block the editor displayed.
@MainActor
public enum RelayMarkNativeAgentSuggestionMutation {
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
