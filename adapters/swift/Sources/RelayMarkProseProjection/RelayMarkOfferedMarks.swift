import Foundation

/// TipTap's additional canonical inline marks have empty authored attributes. Keep
/// their exact identities on native text without treating display colors or
/// baseline offsets as document source.
public enum RelayMarkOfferedMark: String, CaseIterable, Codable, Hashable, Sendable {
    case underline, highlight, superscript, `subscript`
}

public struct RelayMarkOfferedMarksAttribute: AttributedStringKey {
    public typealias Value = Set<RelayMarkOfferedMark>
    public static let name = "relay.rich.offeredMarks"
}

/// Text an agent run wrote: the `ai_authored` mark's `run_id`. Hosts show it
/// apart from a person's words; it is never part of a person's own input.
public struct RelayMarkAIAuthoredAttribute: AttributedStringKey {
    public typealias Value = String
    public static let name = "relay.rich.aiAuthored"
}
