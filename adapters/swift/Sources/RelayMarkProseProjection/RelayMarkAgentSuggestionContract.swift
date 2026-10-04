import CoreFoundation
import Foundation

/// Authored-only canonical suggestion. Proposal identity, review actions and UI state are host-owned.
public enum RelayMarkAgentSuggestionContract {
    public struct Validated: Sendable {
        public let id: String
        public let review: String
        public let kind: String
        public let confidence: Double?
        public let evidence: [String]
        public let content: String
    }

    public enum Failure: Error { case unsupported }

    public static func validate(attributes: [String: Any]) throws -> Validated {
        guard Set(attributes.keys) == Set(["relaymarkId", "review", "kind", "confidence", "evidence", "content"]),
              let id = attributes["relaymarkId"] as? String,
              id.range(of: #"\Ab[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}\z"#,
                       options: .regularExpression) != nil,
              let review = attributes["review"] as? String, ["draft", "ready"].contains(review),
              let kind = attributes["kind"] as? String,
              ["note", "action", "match", "journey", "source", "share"].contains(kind),
              let evidence = attributes["evidence"] as? [String], evidence.count <= 64,
              Set(evidence).count == evidence.count,
              evidence.allSatisfy({ !$0.isEmpty && $0.utf16.count <= 128 &&
                  !$0.unicodeScalars.contains(where: { $0.value <= 31 || $0.value == 127 }) }),
              let content = attributes["content"] as? String, !content.isEmpty,
              content.utf16.count <= 32_768,
              content == content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.contains("\r"), !content.contains("\0") else { throw Failure.unsupported }
        let confidence: Double?
        if attributes["confidence"] is NSNull {
            confidence = nil
        } else {
            guard let value = attributes["confidence"] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite, (0...1).contains(value.doubleValue) else {
                throw Failure.unsupported
            }
            confidence = value.doubleValue
        }
        return Validated(id: id, review: review, kind: kind, confidence: confidence,
                         evidence: evidence, content: content)
    }
}
