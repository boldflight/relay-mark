import Observation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Images for one editor's media blocks, loaded through the host's
/// authorized media capability. Each editor owns its store, so cached bytes
/// never cross accounts or papers.
@MainActor
@Observable
public final class RelayMarkImageStore {
    #if os(macOS)
    public typealias Image = NSImage
    #else
    public typealias Image = UIImage
    #endif

    /// Increments whenever a requested image finishes loading.
    private(set) var revision = 0
    @ObservationIgnored private var images: [String: Image] = [:]
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loader: (@MainActor (String) async throws -> Data)?

    public init() {}

    /// Replacing the loader (for example after an account switch) drops
    /// everything loaded through the previous one.
    public func setLoader(_ loader: (@MainActor (String) async throws -> Data)?) {
        generation += 1
        self.loader = loader
        images = [:]
        requested = []
        revision += 1
    }

    /// The loaded image, or nil while it loads, is unavailable or has no loader.
    public func image(for source: String) -> Image? {
        if let image = images[source] { return image }
        guard let loader, requested.insert(source).inserted else { return nil }
        let current = generation
        Task { @MainActor [weak self] in
            guard let data = try? await loader(source), let self, self.generation == current,
                  let image = Image(data: data) else { return }
            self.images[source] = image
            self.revision += 1
        }
        return nil
    }
}
