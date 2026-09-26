import Foundation

/// The authored, inert v3 Paper control contract shared by portable AST and
/// native prose projections. The host owns presentation and execution.
public enum RelayMarkPaperControlContract {
    public enum Control: String, Sendable {
        case button
        case anchor
        case connection
    }

    public struct Validated: Sendable {
        public let id: String
        public let control: Control
        public let authored: [String: String]
        public let source: String
        public let displayLabel: String
    }

    public enum Failure: Error {
        case unsupported
    }

    public static func validate(nodeName: String, attributes: [String: Any]) throws -> Validated {
        let control: Control
        let fields: [String]
        let directive: String
        switch nodeName {
        case "relayButton": control = .button; fields = ["label", "kind", "target"]; directive = "Button"
        case "relayAnchor": control = .anchor; fields = ["name"]; directive = "Anchor"
        case "relayConnection": control = .connection; fields = ["provider"]; directive = "Connection"
        default: throw Failure.unsupported
        }
        guard Set(attributes.keys) == Set(["relaymarkId"] + fields),
              let id = attributes["relaymarkId"] as? String else { throw Failure.unsupported }
        let chars = Array(id), hex = Set("0123456789abcdef")
        guard chars.count == 33, chars[0] == "b", chars[13] == "4",
              Set("89ab").contains(chars[17]), chars.dropFirst().allSatisfy(hex.contains) else {
            throw Failure.unsupported
        }
        var authored = [String: String]()
        for field in fields {
            guard let value = attributes[field] as? String else { throw Failure.unsupported }
            authored[field] = value
        }
        let anchor = #"\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z"#
        func matches(_ value: String, _ pattern: String) -> Bool {
            value.range(of: pattern, options: .regularExpression) != nil
        }
        func json(_ value: String) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self)
        }
        let displayLabel: String
        switch control {
        case .button:
            let label = authored["label"]!, kind = authored["kind"]!, target = authored["target"]!
            let safe = !matches(target, #"[\s\x00-\x1f\x7f\\]"#) &&
                (matches(target, #"^/(?!/)"#) || matches(target, #"(?i)^https?://[^/?#]+"#) ||
                 matches(target, #"(?i)^mailto:[^?]+"#))
            guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  kind == "anchor" ? matches(target, anchor) :
                    kind == "command" ? matches(target, #"\A/[a-z][a-z0-9._-]*(?: [^\x00-\x1f\x7f]+)?\z"#) :
                    kind == "link" && safe else { throw Failure.unsupported }
            displayLabel = label
        case .anchor:
            guard matches(authored["name"]!, anchor) else { throw Failure.unsupported }
            displayLabel = authored["name"]!
        case .connection:
            guard matches(authored["provider"]!, #"\A[a-z][a-z0-9_-]*\z"#) else { throw Failure.unsupported }
            displayLabel = authored["provider"]!
        }
        let source = "@\(directive)(\(try fields.map { "\($0): \(try json(authored[$0]!))" }.joined(separator: ", ")))"
        guard source.utf16.count <= 16_384 else { throw Failure.unsupported }
        return Validated(id: id, control: control, authored: authored, source: source,
                         displayLabel: displayLabel)
    }
}
