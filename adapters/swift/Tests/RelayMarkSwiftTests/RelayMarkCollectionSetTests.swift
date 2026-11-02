import CryptoKit
import Foundation
import Testing
@testable import RelayMarkSwift

/// The shared smart-list contract (relay-elixir test/fixtures/collection_set_v1.json,
/// vendored as spec/relaymark/collection-set-v1.json) through the Swift engine
/// binding, so Apple lists the same members in the same order as the web.
struct RelayMarkCollectionSetTests {
    static let pinnedSHA256 = "c6acd58492a589707e7a63d4033982c5974ca5d634ce333a44c81ea1cc1a408e"

    @Test func everySharedCaseListsAsTheContractSays() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("spec/relaymark/collection-set-v1.json"))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == Self.pinnedSHA256, "re-vendor from relay-elixir test/fixtures/collection_set_v1.json")
        let fixture = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sharedRecords = try #require(fixture["records"] as? [[String: Any]])
        let cases = try #require(fixture["cases"] as? [[String: Any]])
        #expect(cases.count == 36)
        for item in cases {
            let name = item["name"] as? String ?? "?"
            let list = try #require(RelayMarkCollectionSet.List(rawValue: item["list"] as? String ?? ""), "\(name)")
            let shell = try #require(RelayMarkCollectionSet.ShellCoverage(rawValue: item["shell_entity_types"] as? String ?? ""), "\(name)")
            // A case's own records replace the shared ones.
            let records = item["records"] as? [[String: Any]] ?? sharedRecords
            let expectedGroups = item["groups"] as? [String: Any]
            let grouping = (expectedGroups?["grouping"] as? String).flatMap(RelayMarkCollectionSet.Grouping.init(rawValue:))
            let query = RelayMarkCollectionSet.Query(list: list, entityID: item["entity_id"] as? String, account: item["account"] as? String,
                params: item["params"] as? [String: Any] ?? [:], page: item["page"] as? Int ?? 1, pageSize: item["page_size"] as? Int ?? 24, grouping: grouping)
            let page = try RelayMarkCollectionSet.evaluate(records: records, shellEntityTypes: shell, query: query)
            let expected = try #require(item["expect"] as? [String: Any], "\(name)")
            #expect(page.ids == expected["ids"] as? [String], "\(name)")
            #expect(page.total == expected["total"] as? Int, "\(name)")
            #expect(page.page == expected["page"] as? Int, "\(name)")
            #expect(page.pageCount == expected["page_count"] as? Int, "\(name)")
            #expect(page.status == .complete, "\(name)")
            if let expectedGroups {
                let descriptors = (expectedGroups["descriptors"] as? [[String]] ?? []).map { RelayMarkCollectionSet.Groups.Descriptor(key: $0[0], label: $0[1]) }
                #expect(page.groups?.descriptors == descriptors, "\(name)")
                #expect(page.groups?.entityGroupKeys == expectedGroups["entity_group_keys"] as? [String: String], "\(name)")
            } else {
                #expect(page.groups == nil, "\(name)")
            }
        }
    }

    @Test func aCollectionThatIsNotHeldIsPartial() throws {
        let page = try RelayMarkCollectionSet.evaluate(records: [], shellEntityTypes: .complete, query: .init(list: .collection, entityID: "gone"))
        #expect(page == .init(status: .partial, ids: [], total: nil, page: 1, pageCount: nil, groups: nil))
    }
}
