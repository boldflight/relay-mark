import Foundation

/// relaymark-core's draft-Task rules (spec/relaymark/editor/task-drafts-v1.json),
/// called by job name as every editor calls them. The armed set is the
/// caller's local state; documents are ProseMirror JSON with block identity.
public enum RelayMarkTaskDraftCodec {
    /// Every unlinked task item with a well-formed identity, as
    /// `[{block_id, operation_id, title, text, done, intent, parent_entity_id, path}]`.
    public static func drafts(document: Data, armed: [String]) throws -> [[String: Any]] {
        let answer = try RelayMarkEngineCall.run("task_drafts", document, options: ["armed": armed])
        guard let drafts = try JSONSerialization.jsonObject(with: answer) as? [[String: Any]] else {
            throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument
        }
        return drafts
    }

    /// The armed block ids after an editing event (`input_rule`, `command`,
    /// `split` with `from`, `arm`/`disarm` with `ids`, or `external`).
    public static func arm(before: Data?, after: Data, armed: [String], event: [String: Any]) throws -> [String] {
        let documents = RelayMarkEngineCall.array([before ?? Data("null".utf8), after])
        let answer = try RelayMarkEngineCall.run("task_draft_arm", documents, options: ["armed": armed, "event": event])
        guard let result = try JSONSerialization.jsonObject(with: answer) as? [String: Any],
              let ids = result["armed"] as? [String] else { throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument }
        return ids
    }

    /// The armed drafts a boundary finishes: `key` `return` or `move` with
    /// `before` (and `after`) ProseMirror carets, or `checkbox` with `block`.
    public static func finished(document: Data, armed: [String], boundary: [String: Any]) throws -> [String] {
        var options = boundary
        options["armed"] = armed
        let answer = try RelayMarkEngineCall.run("task_draft_boundary", document, options: options)
        guard let ids = try JSONSerialization.jsonObject(with: answer) as? [String] else {
            throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument
        }
        return ids
    }
}
