import Foundation
import Testing
import RelayMarkSwift
import RelayMarkNativeCollaboration

/// A 1 MB paper must not leave its conversion's memory behind, nor hold every
/// intermediate of its import at once: on a phone either gets the app killed.
@MainActor @Suite("Large paper memory", .serialized)
struct RelayMarkLargePaperMemoryTests {
    private static func vmInfo() -> task_vm_info_data_t {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return info
    }
    private static func footprint() -> Int { Int(vmInfo().phys_footprint) / 1_048_576 }
    /// The process's highest footprint so far.
    private static func peak() -> Int { Int(vmInfo().ledger_phys_footprint_peak) / 1_048_576 }

    private static let source: String = {
        let block = "## Section heading\n\nA paragraph with **bold**, *italic*, `code` and a [link](https://example.com/x). More words follow here.\n\n- First item\n- Second item\n  - Nested item\n\n> A quoted line.\n\n"
        return String(repeating: block, count: 1_048_576 / block.utf8.count)
    }()

    /// A 1 MB parse must stay far below what got the app killed: the bundled
    /// JavaScript peaked near 490 MB on the iPhone simulator.
    @Test func aLargeParsePeaksWithinItsBudget() throws {
        _ = try RelayMarkSourceCodec.parseDocument("# Warm", namespace: "warm")
        let before = Self.footprint(), earlier = Self.peak()
        try autoreleasepool { _ = try RelayMarkSourceCodec.parseDocument(Self.source, namespace: "large") }
        let grown = Self.peak() - before
        print("1 MB parse: peak +\(grown) MB")
        // An earlier, higher peak in this process would hide this one.
        if earlier - before < 300 {
            #expect(grown < 300, "a 1 MB parse peaked \(grown) MB above its start")
        }
    }

    /// A large conversion returns its memory rather than keeping it.
    @Test func largeConversionReturnsItsMemory() throws {
        _ = try RelayMarkSourceCodec.parseDocument("# Warm", namespace: "warm")
        let baseline = Self.footprint()
        try autoreleasepool { _ = try RelayMarkSourceCodec.parseDocument(Self.source, namespace: "large") }
        let settled = Self.footprint()
        #expect(settled - baseline < 100, "a 1 MB parse kept \(settled - baseline) MB")
    }

    /// Writing a whole paper into the replica releases each node's bridged
    /// values as it goes, rather than when the caller's run loop turn ends.
    @Test func initializingALargePaperDoesNotHoldEveryIntermediate() throws {
        let ast = try RelayMarkSourceCodec.parseDocument(Self.source, namespace: "large-write")
        let document = RelayMarkNativeDocument()
        Thread.sleep(forTimeInterval: 1)
        let before = Self.footprint()
        _ = try document.initializeDocument(authoredAST: ast)
        let grown = Self.footprint() - before
        #expect(grown < 400, "initializing a 1 MB paper held \(grown) MB")
    }
}
