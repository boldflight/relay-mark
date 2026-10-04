import Foundation
import CoreFoundation
import RelayMarkSwift

/// Authored media shape shared by native text admission and portable AST projection.
/// Media bytes, upload progress, playback and authorization stay with the host.
public enum RelayMarkMediaContract {
    public struct Validated {
        public let kind: RelayMarkCollaborativeProse.MediaAtom.Kind
        public let id: String
        public let source: String
        public let alt: String?
        public let title: String?
        public let width: Int?
        public let height: Int?
    }

    public enum Failure: Error { case unsupported }

    public static func validate(name: String, attributes: [String: Any], children: [[String: Any]]) throws -> Validated {
        guard children.isEmpty, let kind = RelayMarkCollaborativeProse.MediaAtom.Kind(rawValue: name),
              let id = attributes["relaymarkId"] as? String, !id.isEmpty else { throw Failure.unsupported }
        switch kind {
        case .image:
            guard Set(attributes.keys).isSubset(of: ["relaymarkId", "src", "alt", "title", "width", "height"]),
                  let source = attributes["src"] as? String, validImageSource(source) else {
                throw Failure.unsupported
            }
            return Validated(kind: kind, id: id, source: source,
                alt: try optionalImageText(attributes["alt"]),
                title: try optionalImageText(attributes["title"]),width:try dimension(attributes["width"]),height:try dimension(attributes["height"]))
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
            return Validated(kind: kind, id: id, source: source, alt: nil, title: nil,width:nil,height:nil)
        }
    }

    private static func dimension(_ value: Any?) throws -> Int? {
        guard let value,!(value is NSNull) else { return nil }
        guard let number=value as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),let integer=value as? Int,
              integer>0,integer<=9_007_199_254_740_991,number.doubleValue==Double(integer) else { throw Failure.unsupported }
        return integer
    }

    private static func optionalImageText(_ value: Any?) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let text = value as? String, text.utf16.count <= 4_096,
              !text.contains("\r"), !text.contains("\n") else { throw Failure.unsupported }
        return text
    }

    private static func validImageSource(_ source: String) -> Bool {
        (try? RelayMarkSourceCodec.isSafeImageSource(source)) == true
    }
}
