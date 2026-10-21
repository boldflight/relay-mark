import Foundation

/// The name a tag atom carries: a normalized Relay tag name that starts with a
/// lowercase, modifier or other letter or a decimal digit from any script,
/// then those, combining marks and `-` (spec/relaymark/conformance/tag-names.json).
public enum RelayMarkTagName {
    public static func isNormalized(_ name: String) -> Bool {
        name.range(of: #"\A[\p{Ll}\p{Lm}\p{Lo}\p{Nd}][\p{Ll}\p{Lm}\p{Lo}\p{M}\p{Nd}-]*\z"#,
                   options: .regularExpression) != nil
    }
}
