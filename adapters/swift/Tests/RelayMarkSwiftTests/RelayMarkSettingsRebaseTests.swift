import Foundation
import Testing
@testable import RelayMarkSwift

/// The shared settings-rebase contract through the Swift engine binding, so native
/// merges a concurrent change to one question's aggregate settings exactly as the web does.
struct RelayMarkSettingsRebaseTests {
    @Test func everySharedCaseAnswersAsTheContractSays() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("spec/relaymark/editor/settings-rebase-v1.json"))
        let fixture = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try #require(fixture["cases"] as? [[String: Any]])
        #expect(cases.count >= 15)
        for item in cases {
            let name = item["name"] as? String ?? "?"
            let input = try #require(item["input"] as? [Any])
            if let refusal = item["expected_error"] as? String {
                let bytes = try JSONSerialization.data(withJSONObject: input)
                #expect(throws: (any Error).self, "\(name)") { _ = try RelayMarkEngineCall.run("settings_rebase", bytes, options: [:]) }
                _ = refusal
                continue
            }
            let answer = try RelayMarkSettingsRebase.rebase(base: input[0] as? [String: Any], local: input[1] as? [String: Any],
                incoming: input[2] as? [String: Any])
            let expected = (item["expected"] as? [String: Any])?["settings"] as? [String: Any]
            #expect(answer.map { NSDictionary(dictionary: $0) } == expected.map { NSDictionary(dictionary: $0) }, "\(name)")
        }
    }
}
