import Foundation

/// The name a tag atom carries: a normalized Relay tag name that starts with a
/// lowercase, modifier or other letter, a decimal digit or a letter number (〇)
/// from any script, then those, combining marks and `-` (spec/relaymark/conformance/tag-names.json).
public enum RelayMarkTagName {
    public static func isNormalized(_ name: String) -> Bool {
        name.range(of: #"\A[\p{Ll}\p{Lm}\p{Lo}\p{Nd}\p{Nl}][\p{Ll}\p{Lm}\p{Lo}\p{M}\p{Nd}\p{Nl}-]*\z"#,
                   options: .regularExpression) != nil
    }
}
