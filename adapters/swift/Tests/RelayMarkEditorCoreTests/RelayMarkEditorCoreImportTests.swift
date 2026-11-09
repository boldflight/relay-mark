import Foundation
import Testing

/// RelayMarkEditorCore stays headless, so a host's session and its tests run
/// without a UI framework; views, drawing and colours belong to RelayMarkEditor.
struct RelayMarkEditorCoreImportTests {
    // Bug caught: a session file importing SwiftUI (for a Color or a shortcut)
    // and pulling every UI framework into each headless host target.
    @Test("The editor core imports no UI framework")
    func noUIFramework() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/RelayMarkEditorCore")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        let forbidden: Set<String> = ["SwiftUI", "AppKit", "UIKit", "RelayMarkEditor"]
        var found: [String] = []
        for file in files {
            for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
                let words = line.split(whereSeparator: \.isWhitespace).drop { $0.hasPrefix("@") }
                guard words.first == "import", let module = words.dropFirst().last?.split(separator: ".").first,
                      forbidden.contains(String(module)) else { continue }
                found.append("\(file.lastPathComponent): \(module)")
            }
        }
        #expect(found.isEmpty, "\(found.sorted().joined(separator: "\n"))")
    }
}
