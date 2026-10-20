import Foundation
import RelayMarkSwift

/// Host authoring policy only. The portable replica preserves other existing URLs.
/// Shared positive/negative cases live in link-authoring-policy.json.
public enum RelayMarkLinkDestination {
    public static func accepted(_ value: String) -> String? {
        guard !value.isEmpty, value.utf8.count <= 2048,
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              !value.contains("<"), !value.contains(">"), !value.contains("\\"),
              value.range(of: "%(?![0-9A-Fa-f]{2})", options: .regularExpression) == nil,
              let decoded = value.removingPercentEncoding,
              !decoded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        if value.hasPrefix("#") {
            // Fragment syntax belongs to the same portable link owner as the
            // authored document. Creating a link grants no target authority.
            do {
                try RelayMarkSourceCodec.validateTextAttributes(["link": [
                    "href": value, "target": "_blank", "rel": "noopener noreferrer nofollow",
                    "class": NSNull(), "title": NSNull()
                ]])
                return value
            } catch { return nil }
        }
        guard let parts = URLComponents(string: value), let scheme = parts.scheme?.lowercased(),
              parts.url != nil else { return nil }
        if scheme == "relay" {
            let prefix = "relay:entity/"
            guard value.hasPrefix(prefix), let id = UUID(uuidString: String(value.dropFirst(prefix.count))),
                  value == prefix + id.uuidString.lowercased() else { return nil }
            return value
        }
        if scheme == "http" || scheme == "https" {
            guard let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
                  parts.port == nil || (0...65535).contains(parts.port!) else { return nil }
            return value
        }
        if scheme == "mailto" {
            let recipient = parts.path
            guard value.hasPrefix("mailto:"), parts.host == nil, parts.fragment == nil,
                  let split = recipient.firstIndex(of: "@") else { return nil }
            let local = String(recipient[..<split]), domain = String(recipient[recipient.index(after: split)...])
            guard local.range(of: "^[A-Za-z0-9._%+-]+$", options: .regularExpression) != nil,
                  !local.hasPrefix("."), !local.hasSuffix("."), !local.contains(".."),
                  domain.range(of: "^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*$", options: .regularExpression) != nil else { return nil }
            if let query = parts.percentEncodedQuery {
                guard query.range(of: "^[A-Za-z0-9=&%._~+@-]*$", options: .regularExpression) != nil else { return nil }
                var keys = Set<String>()
                for pair in query.split(separator: "&", omittingEmptySubsequences: false) {
                    guard let equals = pair.firstIndex(of: "=") else { return nil }
                    let key = String(pair[..<equals])
                    guard ["subject", "body"].contains(key), keys.insert(key).inserted else { return nil }
                }
            }
            return value
        }
        return nil
    }
}
