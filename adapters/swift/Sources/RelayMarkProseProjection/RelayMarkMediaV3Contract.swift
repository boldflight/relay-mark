import Foundation

/// Authored media shape shared by native text admission and portable AST projection.
/// Media bytes, upload progress, playback and authorization stay with the host.
public enum RelayMarkMediaV3Contract {
    public struct Validated {
        public let kind: RelayMarkCollaborativeProse.MediaAtom.Kind
        public let id: String
        public let source: String
        public let alt: String?
        public let title: String?
    }

    public enum Failure: Error { case unsupported }

    public static func validate(name: String, attributes: [String: Any], children: [[String: Any]]) throws -> Validated {
        guard children.isEmpty, let kind = RelayMarkCollaborativeProse.MediaAtom.Kind(rawValue: name),
              let id = attributes["relaymarkId"] as? String, !id.isEmpty else { throw Failure.unsupported }
        switch kind {
        case .image:
            guard Set(attributes.keys).isSubset(of: ["relaymarkId", "src", "alt", "title", "width", "height"]),
                  attributes["width"] == nil || attributes["width"] is NSNull,
                  attributes["height"] == nil || attributes["height"] is NSNull,
                  let source = attributes["src"] as? String, validImageSource(source) else {
                throw Failure.unsupported
            }
            return Validated(kind: kind, id: id, source: source,
                alt: try optionalImageText(attributes["alt"]),
                title: try optionalImageText(attributes["title"]))
        case .videoEmbed:
            guard Set(attributes.keys).isSubset(of: ["relaymarkId", "videoId", "playbackId", "title",
                                                    "source", "thumbnailUrl", "status", "youtubeId", "uploadPercent"]),
                  let source = attributes["videoId"] as? String,
                  source.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
                               options: .regularExpression) != nil,
                  ["playbackId", "title", "thumbnailUrl", "youtubeId", "uploadPercent"].allSatisfy({
                      attributes[$0] == nil || attributes[$0] is NSNull
                  }),
                  attributes["source"] == nil || attributes["source"] as? String == "mux",
                  attributes["status"] == nil || attributes["status"] as? String == "ready" else {
                throw Failure.unsupported
            }
            return Validated(kind: kind, id: id, source: source, alt: nil, title: nil)
        }
    }

    private static func optionalImageText(_ value: Any?) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let text = value as? String, text.utf16.count <= 4_096,
              !text.contains("\r"), !text.contains("\n") else { throw Failure.unsupported }
        return text
    }

    private static func validImageSource(_ source: String) -> Bool {
        guard source.utf16.count <= 2_048,
              source.trimmingCharacters(in: .whitespacesAndNewlines) == source,
              source.rangeOfCharacter(from: .controlCharacters) == nil,
              !source.contains("\\") else { return false }
        if source.range(of: "^/m/[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil { return true }
        guard source.hasPrefix("https://"), let url = URLComponents(string: source),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return false }
        return true
    }
}
