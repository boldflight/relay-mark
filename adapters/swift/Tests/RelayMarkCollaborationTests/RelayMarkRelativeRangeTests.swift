import Foundation
import Testing
@testable import RelayMarkCollaboration

@MainActor
struct RelayMarkRelativeRangeTests {
    struct Fixture: Decodable {
        let seed: Data
        let ranges: [Entry]
        struct Entry: Decodable {
            let name: String
            let range: RelayMarkCollaborationDocument.RelativeRange
            let expected: RelayMarkCollaborationDocument.ResolvedRange?
        }
    }
    private func fixture() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: #require(Bundle.module.url(forResource: "relative-ranges-v1", withExtension: "json"))))
    }
    @Test func nodeFixturesResolveAndReencodeExactly() throws {
        let fixture = try fixture(), doc = try RelayMarkCollaborationDocument()
        try doc.applyUpdate(fixture.seed)
        for entry in fixture.ranges {
            #expect(try doc.resolve(range: entry.range) == entry.expected)
            #expect(try JSONDecoder().decode(RelayMarkCollaborationDocument.RelativeRange.self,
                from: JSONEncoder().encode(entry.range)) == entry.range)
            if let expected = entry.expected {
                #expect(try doc.relativeRange(anchor: expected.anchor, head: expected.head) == entry.range)
            }
        }
    }
    @Test func concurrentEditsAndDeletionKeepUnicodeRangeStable() throws {
        let fixture = try fixture(), alice = try RelayMarkCollaborationDocument(), bob = try RelayMarkCollaborationDocument()
        try alice.applyUpdate(fixture.seed); try bob.applyUpdate(fixture.seed)
        let original = try #require(fixture.ranges.first?.range)
        let aliceUpdates = try alice.replaceProse(start: 6, end: 6, text: "!")
        let bobUpdates = try bob.replaceProse(start: 0, end: 0, text: "++")
        for update in bobUpdates { try alice.applyUpdate(update) }
        for update in aliceUpdates { try bob.applyUpdate(update) }
        #expect(try alice.resolve(range: original) == bob.resolve(range: original))
        let moved = try #require(try alice.resolve(range: original))
        #expect(moved.anchor.index == 3 && moved.head.index == 7)
        let deletion = try alice.replaceProse(start: 3, end: 7, text: "")
        for update in deletion { try bob.applyUpdate(update) }
        let collapsed = try #require(try bob.resolve(range: original))
        #expect(collapsed.anchor.index == 3 && collapsed.head.index == 3)
        #expect(try alice.resolve(range: original) == collapsed)
        // Removal of the endpoint's shared container invalidates the range; never guess a nearby block.
        _ = try bob.edit(Data(#"{"kind":"deleteNodes","path":[],"index":0,"length":1}"#.utf8))
        #expect(try bob.resolve(range: original) == nil)
    }
    @Test func malformedRangesFailWithoutChangingDocument() throws {
        let fixture = try fixture(), doc = try RelayMarkCollaborationDocument()
        try doc.applyUpdate(fixture.seed)
        let valid = try #require(fixture.ranges.first?.range)
        let before = try doc.encodeUpdate()
        for bytes in [Data([0]), Data([3,0]), valid.anchor + Data([0]), Data([128,0,1,1,0])] {
            let invalid = try RelayMarkCollaborationDocument.RelativeRange(anchor: bytes, head: valid.head)
            #expect(throws: (any Error).self) { try doc.resolve(range: invalid) }
        }
        #expect(throws: (any Error).self) { try RelayMarkCollaborationDocument.RelativeRange(anchor: Data(), head: valid.head) }
        #expect(throws: (any Error).self) { try RelayMarkCollaborationDocument.RelativeRange(anchor: Data(repeating: 0, count: 257), head: valid.head) }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RelayMarkCollaborationDocument.RelativeRange.self, from: Data(#"{"version":2,"anchor":"AAA=","head":"AAA="}"#.utf8))
        }
        #expect(try doc.encodeUpdate() == before)
    }
    @Test func portableRangesDoNotFollowLocalUndoOnlyMappings() throws {
        let fixture = try fixture(), alice = try RelayMarkCollaborationDocument(), bob = try RelayMarkCollaborationDocument()
        try alice.applyUpdate(fixture.seed); try bob.applyUpdate(fixture.seed)
        let range = try #require(fixture.ranges.first?.range)
        for update in try alice.replaceProse(start: 1, end: 5, text: "replacement") { try bob.applyUpdate(update) }
        for update in try alice.undo() { try bob.applyUpdate(update) }
        #expect(try alice.snapshot() == bob.snapshot())
        #expect(try alice.resolve(range: range) == bob.resolve(range: range))
    }
}
