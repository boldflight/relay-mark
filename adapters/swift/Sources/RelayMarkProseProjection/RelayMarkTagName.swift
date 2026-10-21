import Foundation

/// The name a tag atom carries: a normalized Relay tag name of lowercase,
/// modifier and other letters, marks and numbers from any script, `_` and
/// `-` after the first character (spec/relaymark/conformance/tag-names.json).
public enum RelayMarkTagName {
    public static func isNormalized(_ name: String) -> Bool {
        name.range(of: #"\A[\p{Ll}\p{Lm}\p{Lo}\p{M}\p{N}_][\p{Ll}\p{Lm}\p{Lo}\p{M}\p{N}_-]*\z"#,
                   options: .regularExpression) != nil
    }
}
