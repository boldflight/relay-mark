import Foundation
import Testing
import RelayMarkSwift
import RelayMarkNativeCollaboration

/// A 1 MB paper must not leave its conversion's memory behind, nor hold every
/// intermediate of its import at once: on a phone either gets the app killed.
@MainActor @Suite("Large paper memory", .serialized)
struct RelayMarkLargePaperMemoryTests {
    private static func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return Int(info.phys_footprint) / 1_048_576
    }

    private static let source: String = {
        let block = "## Section heading\n\nA paragraph with **bold**, *italic*, `code` and a [link](https://example.com/x). More words follow here.\n\n- First item\n- Second item\n  - Nested item\n\n> A quoted line.\n\n"
        return String(repeating: block, count: 1_048_576 / block.utf8.count)
    }()

    /// The JavaScript heap a large conversion grows stays with its context, so
    /// that context must be released, not kept for the next call. iOS grows it
    /// to several hundred megabytes for this paper; macOS far less.
    @Test func largeConversionReturnsItsJavaScriptHeap() async throws {
        _ = try RelayMarkSourceCodec.parseDocument("# Warm", namespace: "warm")
        let baseline = Self.footprint()
        try autoreleasepool { _ = try RelayMarkSourceCodec.parseDocument(Self.source, namespace: "large") }
        // The context goes once the main thread idles, as it does between the
        // app's run loop turns; suspending lets the main queue run. A nested
        // run loop would not: this test is itself a main-queue job.
        var settled = Self.footprint()
        for _ in 0..<50 where settled - baseline >= 100 {
            try await Task.sleep(for: .milliseconds(100)); settled = Self.footprint()
        }
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
