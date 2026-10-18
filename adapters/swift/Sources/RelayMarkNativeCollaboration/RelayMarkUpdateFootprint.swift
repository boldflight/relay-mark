import Foundation

/// The item IDs a Yjs v1 update inserts or deletes, read without applying it.
/// Only text-shaped content is decoded; anything else makes the footprint
/// structural, and the host then re-projects the whole paper.
struct RelayMarkUpdateFootprint {
    struct ID: Hashable { let client: UInt64; let clock: UInt64 }
    /// One ID per inserted struct and every deleted clock: one contiguous
    /// delete range can span text in a leaf and whole nodes made in between.
    private(set) var touched: [ID] = []
    /// Larger deletions re-project the paper rather than resolve each clock.
    static let deletedClockLimit: UInt64 = 4_096

    /// Nil when the update creates or removes XML nodes, edits maps, or is malformed.
    init?(_ update: Data) {
        var reader = Reader(bytes: [UInt8](update))
        guard let clients = reader.varUInt(), clients <= 1 << 20 else { return nil }
        for _ in 0..<clients {
            guard let structs = reader.varUInt(), let client = reader.varUInt(), var clock = reader.varUInt(),
                  structs <= 1 << 24 else { return nil }
            for _ in 0..<structs {
                guard let info = reader.byte() else { return nil }
                let reference = info & 0x1F
                if reference == 0 || reference == 10 { // GC or Skip
                    guard let length = reader.varUInt() else { return nil }
                    clock += length; continue
                }
                if info & 0x80 != 0 { guard reader.varUInt() != nil, reader.varUInt() != nil else { return nil } }
                if info & 0x40 != 0 { guard reader.varUInt() != nil, reader.varUInt() != nil else { return nil } }
                if info & 0xC0 == 0 {
                    guard let parentInfo = reader.varUInt() else { return nil }
                    if parentInfo == 1 { guard reader.string() != nil else { return nil } }
                    else { guard reader.varUInt() != nil, reader.varUInt() != nil else { return nil } }
                    if info & 0x20 != 0 { return nil } // a map entry, not text
                }
                let length: UInt64
                switch reference {
                case 1: // deleted content
                    guard let count = reader.varUInt() else { return nil }
                    length = count
                case 4: // string
                    guard let text = reader.string() else { return nil }
                    length = UInt64(text.utf16.count)
                case 6: // format marker
                    guard reader.string() != nil, reader.string() != nil else { return nil }
                    length = 1
                default: return nil // nodes, embeds and map values change structure
                }
                touched.append(ID(client: client, clock: clock))
                clock += length
            }
        }
        guard let deleteClients = reader.varUInt(), deleteClients <= 1 << 20 else { return nil }
        var deleted: UInt64 = 0
        for _ in 0..<deleteClients {
            guard let client = reader.varUInt(), let ranges = reader.varUInt(), ranges <= 1 << 24 else { return nil }
            for _ in 0..<ranges {
                guard let clock = reader.varUInt(), let length = reader.varUInt(),
                      length <= Self.deletedClockLimit - deleted else { return nil }
                deleted += length
                for offset in 0..<length { touched.append(ID(client: client, clock: clock + offset)) }
            }
        }
        guard reader.atEnd else { return nil }
    }

    /// The Yjs sticky index naming the item itself (`IndexScope::Relative`, assoc after).
    static func stickyIndex(_ id: ID) -> Data {
        var bytes: [UInt8] = []
        func write(_ value: UInt64) {
            var value = value
            while value >= 0x80 { bytes.append(UInt8(value & 0x7F) | 0x80); value >>= 7 }
            bytes.append(UInt8(value))
        }
        write(0); write(id.client); write(id.clock); bytes.append(0)
        return Data(bytes)
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        var atEnd: Bool { offset == bytes.count }
        mutating func byte() -> UInt8? {
            guard offset < bytes.count else { return nil }
            defer { offset += 1 }
            return bytes[offset]
        }
        mutating func varUInt() -> UInt64? {
            var value: UInt64 = 0, shift: UInt64 = 0
            while let byte = byte() {
                guard shift < 64 else { return nil }
                value |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }
            return nil
        }
        mutating func string() -> String? {
            guard let count = varUInt(), count <= UInt64(bytes.count - offset) else { return nil }
            defer { offset += Int(count) }
            return String(bytes: bytes[offset..<offset + Int(count)], encoding: .utf8)
        }
    }
}
