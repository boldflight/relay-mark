import Foundation

/// A selection as two portable Yjs relative positions (anchor and head). It
/// survives concurrent edits; resolve it against the same document.
public struct RelayMarkRelativeRange: Codable, Equatable, Sendable {
    public enum Failure: Error { case invalidLength }
    public let version: Int
    public let anchor: Data
    public let head: Data

    public init(anchor: Data, head: Data) throws {
        guard (1...256).contains(anchor.count), (1...256).contains(head.count) else { throw Failure.invalidLength }
        self.version = 1; self.anchor = anchor; self.head = head
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        guard try fields.decode(Int.self, forKey: .version) == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: fields, debugDescription: "Unsupported relative range version")
        }
        try self.init(anchor: fields.decode(Data.self, forKey: .anchor), head: fields.decode(Data.self, forKey: .head))
    }
}
