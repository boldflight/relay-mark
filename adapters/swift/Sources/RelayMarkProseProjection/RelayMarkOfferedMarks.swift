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
