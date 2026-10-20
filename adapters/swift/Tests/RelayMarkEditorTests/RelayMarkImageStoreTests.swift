#if os(macOS)
import AppKit
@testable import RelayMarkEditor
import Testing

@MainActor
@Suite("Paper media images")
struct RelayPaperMediaImageStoreTests {
    private func png() throws -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 3), flipped: false) { rect in
            NSColor.systemBlue.setFill(); rect.fill(); return true
        }
        let tiff = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    @Test("Images load once through the host loader and drop when the loader changes")
    func loadsThroughHost() async throws {
        let store = RelayMarkImageStore()
        let data = try png()
        var requests: [String] = []
        #expect(store.image(for: "/m/a") == nil, "no loader yet")
        store.setLoader { source in requests.append(source); return data }
        let start = store.revision
        #expect(store.image(for: "/m/a") == nil)
        #expect(store.image(for: "/m/a") == nil, "one request per source")
        for _ in 0..<100 where store.revision == start { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.image(for: "/m/a")?.size == NSSize(width: 4, height: 3))
        #expect(requests == ["/m/a"])
        store.setLoader(nil)
        #expect(store.image(for: "/m/a") == nil, "another account never sees earlier bytes")
    }
}
#endif
