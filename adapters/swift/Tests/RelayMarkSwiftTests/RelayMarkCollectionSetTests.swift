import CryptoKit
import Foundation
import Testing
@testable import RelayMarkSwift

/// The shared smart-list contract (relay-elixir test/fixtures/collection_set_v1.json,
/// vendored as spec/relaymark/collection-set-v1.json) through the Swift engine
/// binding, so Apple lists the same members in the same order as the web.
struct RelayMarkCollectionSetTests {
    static let pinnedSHA256 = "4b9cbc0022124a3b6c25d03f35f629ebac668e63d563680cc5641a9c1f78ff6f"

    @Test func everySharedCaseListsAsTheContractSays() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("spec/relaymark/collection-set-v1.json"))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == Self.pinnedSHA256, "re-vendor from relay-elixir test/fixtures/collection_set_v1.json")
        let fixture = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sharedRecords = try #require(fixture["records"] as? [[String: Any]])
        let cases = try #require(fixture["cases"] as? [[String: Any]])
        #expect(cases.count == 42)
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
            let projected = Set(item["server_projected"] as? [String] ?? [])
            let page = try RelayMarkCollectionSet.evaluate(records: records, shellEntityTypes: shell, serverProjected: projected, query: query)
            // The pre-encoded entry point answers identically.
            let encoded = try JSONSerialization.data(withJSONObject: records)
            #expect(try RelayMarkCollectionSet.evaluate(recordsJSON: encoded, shellEntityTypes: shell, serverProjected: projected, query: query) == page, "\(name)")
            let expected = try #require(item["expect"] as? [String: Any], "\(name)")
            #expect(page.ids == expected["ids"] as? [String], "\(name)")
            #expect(page.total == expected["total"] as? Int, "\(name)")
            #expect(page.page == expected["page"] as? Int, "\(name)")
            #expect(page.pageCount == expected["page_count"] as? Int, "\(name)")
            #expect(page.status == (expected["total"] is NSNull ? .partial : .complete), "\(name)")
            if let expectedGroups {
                let descriptors = (expectedGroups["descriptors"] as? [[String]] ?? []).map { RelayMarkCollectionSet.Groups.Descriptor(key: $0[0], label: $0.count > 1 ? $0[1] : nil) }
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

    @Test func malformedRecordsJSONThrowsAndNeverCrashes() {
        let query = RelayMarkCollectionSet.Query(list: .inbox)
        for bytes in ["", "[", "[{\"projection\":", "{\"not\":\"an array\"}", "[1,2]", "[] trailing", "\u{0}"] {
            #expect(throws: (any Error).self, "\(bytes)") {
                _ = try RelayMarkCollectionSet.evaluate(recordsJSON: Data(bytes.utf8), shellEntityTypes: .complete, query: query)
            }
        }
    }

    // Measures what the pre-encoded entry point saves on a native-sized input (a few thousand cards).
    @Test func aLargeInputEvaluatesThroughBothEntryPoints() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("spec/relaymark/collection-set-v1.json"))) as? [String: Any])
        let shared = try #require(fixture["records"] as? [[String: Any]])
        var records: [[String: Any]] = []
        for copy in 0..<500 {
            for var record in shared where record["projection"] as? String == "entity.card" {
                var payload = try #require(record["payload"] as? [String: Any])
                let id = "\(payload["entity_id"] ?? "x")-\(copy)"
                payload["entity_id"] = id; record["key"] = id; record["payload"] = payload
                records.append(record)
            }
        }
        let query = RelayMarkCollectionSet.Query(list: .inbox, pageSize: 50)
        let clock = ContinuousClock()
        var viaDictionaries: RelayMarkCollectionSet.Page?
        let slow = try clock.measure { viaDictionaries = try RelayMarkCollectionSet.evaluate(records: records, shellEntityTypes: .complete, query: query) }
        let encoded = try JSONSerialization.data(withJSONObject: records)
        var viaBytes: RelayMarkCollectionSet.Page?
        let fast = try clock.measure { viaBytes = try RelayMarkCollectionSet.evaluate(recordsJSON: encoded, shellEntityTypes: .complete, query: query) }
        print("collection-set \(records.count) records, \(encoded.count) bytes: dictionaries \(slow), pre-encoded \(fast)")
        #expect(viaDictionaries == viaBytes && (viaBytes?.total ?? 0) > 1_000)
    }
}
