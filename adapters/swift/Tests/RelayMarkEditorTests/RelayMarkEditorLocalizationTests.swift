import Foundation
import Testing

struct RelayMarkEditorLocalizationTests {
    // Bug caught: a new editor string (a VoiceOver label, a paste failure)
    // shipping in English to a Japanese reader, or a translation that drops a
    // placeholder and shows the wrong text.
    @Test("Every editor string has Japanese with the same placeholders")
    func everyStringHasJapanese() throws {
        let catalog = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/RelayMarkEditor/Resources/Localizable.xcstrings")
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: [String: Any]])
        let specifier = /%(?:\d+\$)?(lld|ld|d|@|lf|f)/
        func placeholders(_ text: String) -> [String] { text.matches(of: specifier).map { String($0.output.1) }.sorted() }
        var problems: [String] = []
        for (key, entry) in strings where entry["extractionState"] as? String != "stale" {
            let unit = ((entry["localizations"] as? [String: Any])?["ja"] as? [String: Any])?["stringUnit"] as? [String: Any]
            guard let value = unit?["value"] as? String, !value.isEmpty, unit?["state"] as? String == "translated" else {
                problems.append("untranslated: \(key)"); continue
            }
            if placeholders(value) != placeholders(key) { problems.append("placeholders: \(key) → \(value)") }
        }
        #expect(problems.isEmpty, "\(problems.sorted().joined(separator: "\n"))")
    }
}
