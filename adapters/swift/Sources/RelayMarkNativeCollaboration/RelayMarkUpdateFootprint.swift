import Foundation

/// The item IDs a Yjs v1 update inserts or deletes, read without applying it.
struct RelayMarkUpdateFootprint {
    struct ID: Hashable { let client: UInt64; let clock: UInt64 }
    /// One ID per inserted struct and every deleted clock: one contiguous
    /// delete range can span text in a leaf and whole nodes made in between.
    private(set) var touched: [ID] = []
    /// `touched` lists inserted structs first, then deleted clocks.
    private(set) var insertedCount = 0
    /// Only text was inserted, deleted or formatted inside existing parents.
    private(set) var textOnly = true
    /// Larger deletions re-project the paper rather than resolve each clock.
    static let deletedClockLimit: UInt64 = 4_096

    /// Nil when the update is malformed or deletes more than the limit.
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
                    if info & 0x20 != 0 { guard reader.string() != nil else { return nil }; textOnly = false }
                }
                guard let length = reader.content(reference) else { return nil }
                if reference != 1 && reference != 4 && reference != 6 { textOnly = false }
                touched.append(ID(client: client, clock: clock))
                clock += length
            }
        }
        insertedCount = touched.count
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

    /// The item a branch's end-of-branch sticky index names (`IndexScope::Nested`).
    static func nestedID(_ stickyIndex: Data) -> ID? {
        var reader = Reader(bytes: [UInt8](stickyIndex))
        guard reader.byte() == 2, let client = reader.varUInt(), let clock = reader.varUInt() else { return nil }
        return ID(client: client, clock: clock)
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
        mutating func skip(_ count: UInt64) -> Bool {
            guard count <= UInt64(bytes.count - offset) else { return false }
            offset += Int(count); return true
        }
        /// Skips one item's content and returns its clock length.
        mutating func content(_ reference: UInt8) -> UInt64? {
            switch reference {
            case 1: return varUInt() // deleted
            case 2: // JSON
                guard let count = varUInt(), count <= UInt64(bytes.count) else { return nil }
                for _ in 0..<count { guard string() != nil else { return nil } }
                return count
            case 3: guard let count = varUInt(), skip(count) else { return nil }; return 1 // binary
            case 4: return string().map { UInt64($0.utf16.count) }
            case 5: return string() != nil ? 1 : nil // embed
            case 6: return string() != nil && string() != nil ? 1 : nil // format
            case 7: // type
                guard let type = varUInt() else { return nil }
                if type == 3 || type == 5 { guard string() != nil else { return nil } }
                return 1
            case 8: // any
                guard let count = varUInt(), count <= UInt64(bytes.count) else { return nil }
                for _ in 0..<count { guard any(depth: 0) else { return nil } }
                return count
            case 9: return string() != nil && any(depth: 0) ? 1 : nil // subdocument
            default: return nil
            }
        }
        /// Skips one lib0 `Any` value.
        mutating func any(depth: Int) -> Bool {
            guard depth < 64, let tag = byte() else { return false }
            switch tag {
            case 127, 126, 121, 120: return true
            case 125: // signed varint
                while let next = byte() { if next & 0x80 == 0 { return true } }
                return false
            case 124: return skip(4)
            case 123, 122: return skip(8)
            case 119: return string() != nil
            case 118:
                guard let count = varUInt(), count <= UInt64(bytes.count) else { return false }
                for _ in 0..<count { guard string() != nil, any(depth: depth + 1) else { return false } }
                return true
            case 117:
                guard let count = varUInt(), count <= UInt64(bytes.count) else { return false }
                for _ in 0..<count { guard any(depth: depth + 1) else { return false } }
                return true
            case 116: guard let count = varUInt() else { return false }; return skip(count)
            default: return false
            }
        }
        mutating func string() -> String? {
            guard let count = varUInt(), count <= UInt64(bytes.count - offset) else { return nil }
            defer { offset += Int(count) }
            return String(bytes: bytes[offset..<offset + Int(count)], encoding: .utf8)
        }
    }
}
