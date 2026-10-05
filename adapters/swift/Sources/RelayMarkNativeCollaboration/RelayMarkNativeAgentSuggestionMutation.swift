import Foundation
import RelayMarkProseProjection
import RelayMarkSwift

/// Authored canonical suggestion commands over the existing YSwift/Yrs document.
/// The host owns proposal actions and authorization; these commands change
/// only the exact authored block the editor displayed.
@MainActor
public enum RelayMarkNativeAgentSuggestionMutation {
    /// Full canonical body-fragment grammar. Envelope metadata requires the
    /// separately reviewed document operation; it is never silently discarded.
    public static func canAccept(_ content: String) -> Bool {
        (try? fragment(content, firstID: "b00000000000040008000000000000001")) != nil
    }

    public static func accept(document: RelayMarkNativeDocument, atRootIndex index: Int,
                              expectedID: String, expectedReview: String, expectedKind: String,
                              expectedConfidence: Double?, expectedEvidence: [String],
                              expectedContent: String, newBlockID: String) throws -> RelayMarkNativeRichEditing.Change {
        let prose = try document.richProseProjection()
        guard prose.isEditable,
              let atom = prose.suggestionAtoms.first(where: { $0.path == [index] }),
              atom.id == expectedID, atom.review == expectedReview,
              atom.kind == expectedKind, atom.confidence == expectedConfidence,
              atom.evidence == expectedEvidence, atom.content == expectedContent,
              let root = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any],
              let blocks = root["children"] as? [[String: Any]], blocks.indices.contains(index),
              blocks[index]["name"] as? String == "agentSuggestion",
              let attributes = blocks[index]["attributes"] as? [String: Any],
              !blocks.contains(where: {
                  ($0["attributes"] as? [String: Any])?["relaymarkId"] as? String == newBlockID
              }) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let authored = try RelayMarkAgentSuggestionContract.validate(attributes: attributes)
        guard authored.id == expectedID, authored.review == expectedReview,
              authored.kind == expectedKind, authored.confidence == expectedConfidence,
              authored.evidence == expectedEvidence, authored.content == expectedContent else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let replacements = try fragment(expectedContent, firstID: newBlockID)
        return try RelayMarkNativeRichEditing.replaceRootChildren(document: document, tree: root,
            index: index, count: 1, replacements: replacements)
    }

    public static func dismiss(document: RelayMarkNativeDocument, atRootIndex index: Int,
                               expectedID: String, expectedReview: String, expectedKind: String,
                               expectedConfidence: Double?, expectedEvidence: [String],
                               expectedContent: String) throws -> RelayMarkNativeRichEditing.Change {
        let prose = try document.richProseProjection()
        guard prose.isEditable,
              let atom = prose.suggestionAtoms.first(where: { $0.path == [index] }),
              atom.id == expectedID, atom.review == expectedReview,
              atom.kind == expectedKind, atom.confidence == expectedConfidence,
              atom.evidence == expectedEvidence, atom.content == expectedContent,
              let root = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any],
              let blocks = root["children"] as? [[String: Any]], blocks.indices.contains(index),
              blocks[index]["name"] as? String == "agentSuggestion",
              let attributes = blocks[index]["attributes"] as? [String: Any] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let authored = try RelayMarkAgentSuggestionContract.validate(attributes: attributes)
        guard authored.id == expectedID, authored.review == expectedReview,
              authored.kind == expectedKind, authored.confidence == expectedConfidence,
              authored.evidence == expectedEvidence, authored.content == expectedContent else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }

        return try RelayMarkNativeRichEditing.removeWidget(document: document, tree: root, id: expectedID)
    }
    private static func fragment(_ source: String, firstID: String) throws -> [[String: Any]] {
        let parsed = try RelayMarkSourceCodec.parseDocument(source, namespace: "suggestion-" + firstID)
        guard var ast = try JSONSerialization.jsonObject(with: parsed) as? [String: Any],
              !["frontmatter", "annotations", "resources", "meta"].contains(where: { ast[$0] != nil }),
              var blocks = ast["blocks"] as? [[String: Any]], !blocks.isEmpty else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        blocks[0]["id"] = firstID; ast["blocks"] = blocks
        let snapshot = try RelayMarkSourceCodec.documentToSnapshot(JSONSerialization.data(withJSONObject: ast))
        guard let value = try JSONSerialization.jsonObject(with: snapshot) as? [String: Any],
              let children = value["children"] as? [[String: Any]] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return children
    }

}
