import CryptoKit
import Foundation
import Testing
@testable import RelayMarkSwift

/// The shared smart-list contract (relay-elixir test/fixtures/collection_set_v1.json,
/// vendored as spec/relaymark/collection-set-v1.json) through the Swift engine
/// binding, so Apple lists the same members in the same order as the web.
struct RelayMarkCollectionSetTests {
    static let pinnedSHA256 = "e9833051a50a4bd32b496147e804e54bdf130b549262b3cbb7df87ccb295a4fd"

    @Test func everySharedCaseListsAsTheContractSays() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("spec/relaymark/collection-set-v1.json"))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == Self.pinnedSHA256, "re-vendor from relay-elixir test/fixtures/collection_set_v1.json")
        let fixture = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let records = try #require(fixture["records"] as? [[String: Any]])
        let cases = try #require(fixture["cases"] as? [[String: Any]])
        #expect(cases.count == 24)
        for item in cases {
            let name = item["name"] as? String ?? "?"
            let list = try #require(RelayMarkCollectionSet.List(rawValue: item["list"] as? String ?? ""), "\(name)")
            let shell = try #require(RelayMarkCollectionSet.ShellCoverage(rawValue: item["shell_entity_types"] as? String ?? ""), "\(name)")
            let query = RelayMarkCollectionSet.Query(list: list, entityID: item["entity_id"] as? String, account: item["account"] as? String,
                params: item["params"] as? [String: Any] ?? [:], page: item["page"] as? Int ?? 1, pageSize: item["page_size"] as? Int ?? 24)
            let page = try RelayMarkCollectionSet.evaluate(records: records, shellEntityTypes: shell, query: query)
            let expected = try #require(item["expect"] as? [String: Any], "\(name)")
            #expect(page.ids == expected["ids"] as? [String], "\(name)")
            #expect(page.total == expected["total"] as? Int, "\(name)")
            #expect(page.page == expected["page"] as? Int, "\(name)")
            #expect(page.pageCount == expected["page_count"] as? Int, "\(name)")
            #expect(page.status == .complete, "\(name)")
        }
    }

    @Test func aCollectionThatIsNotHeldIsPartial() throws {
        let page = try RelayMarkCollectionSet.evaluate(records: [], shellEntityTypes: .complete, query: .init(list: .collection, entityID: "gone"))
        #expect(page == .init(status: .partial, ids: [], total: nil, page: 1, pageCount: nil))
    }
}
