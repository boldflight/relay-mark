import Foundation

/// TipTap's additional v3 inline marks have empty authored attributes. Keep
/// their exact identities on native text without treating display colors or
/// baseline offsets as document source.
public enum RelayMarkV3OfferedMark: String, CaseIterable, Codable, Hashable, Sendable {
    case underline, highlight, superscript, `subscript`
}

public struct RelayMarkV3OfferedMarksAttribute: AttributedStringKey {
    public typealias Value = Set<RelayMarkV3OfferedMark>
    public static let name = "relay.markdownV3.offeredMarks"
}
