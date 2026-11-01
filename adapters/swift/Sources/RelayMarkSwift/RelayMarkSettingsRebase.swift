import Foundation

/// relaymark-core's `settings_rebase` (spec/relaymark/editor/settings-rebase-v1.json):
/// conflict avoidance for one form question's settings without per-key storage.
///
/// Question and option settings are ONE aggregate `settings` attribute (the
/// October 18 decision; per-key `settings:<key>` storage killed performance and
/// must never return, Douglas 2026-11-02). Yjs keeps the last writer's whole
/// attribute, so a client that holds an unacknowledged settings edit and sees
/// that question's `settings` replaced calls this, then writes the answer (when
/// not nil) in one follow-up local transaction.
public enum RelayMarkSettingsRebase {
    /// The settings to write after the incoming change, or nil when the incoming
    /// value already holds every surviving local change. `base` is the value the
    /// local edit started from, `local` the value it wrote, `incoming` the value
    /// the document holds now (nil: the question is gone, nothing is rebased).
    public static func rebase(base: [String: Any]?, local: [String: Any]?, incoming: [String: Any]?) throws -> [String: Any]? {
        let input = try JSONSerialization.data(withJSONObject: [base ?? NSNull(), local ?? NSNull(), incoming ?? NSNull()] as [Any])
        let answer = try RelayMarkEngineCall.run("settings_rebase", input, options: [:])
        guard let result = try JSONSerialization.jsonObject(with: answer) as? [String: Any] else {
            throw RelayMarkSourceCodec.Failure.invalidAuthoredDocument
        }
        return result["settings"] as? [String: Any]
    }
}
