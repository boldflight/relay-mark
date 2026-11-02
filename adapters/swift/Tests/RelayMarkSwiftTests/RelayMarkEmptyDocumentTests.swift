import Foundation
import Testing
@testable import RelayMarkSwift

/// The shared empty-document contract (spec/relaymark/editor/empty-document-v1.json) through the
/// Swift engine binding: an empty fragment, the empty document and the empty body agree.
struct RelayMarkEmptyDocumentTests {
    @Test func everySharedCaseAnswersAsTheContractSays() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("spec/relaymark/editor/empty-document-v1.json"))
        let fixture = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try #require(fixture["cases"] as? [[String: Any]])
        #expect(cases.count == 4)
        for item in cases {
            let name = item["name"] as? String ?? "?"
            let job = try #require(item["job"] as? String)
            let input = try JSONSerialization.data(withJSONObject: try #require(item["input"]))
            let answer = try RelayMarkEngineCall.run(job, input, options: [:])
            let actual = try JSONSerialization.jsonObject(with: answer) as? NSDictionary
            #expect(actual == (item["expected"] as? NSDictionary), "\(name)")
        }
    }
}
