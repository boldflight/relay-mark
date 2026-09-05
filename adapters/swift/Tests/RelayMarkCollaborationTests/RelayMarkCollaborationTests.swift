import Foundation
import Testing
@testable import RelayMarkCollaboration

@MainActor
struct RelayMarkCollaborationTests {
    private func seed(_ doc: RelayMarkCollaborationDocument) throws {
        _ = try doc.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"paragraph","attributes":{},"children":[{"kind":"text","delta":[{"insert":"Hello 🌍","attributes":{"bold":{},"link":{"href":"relay:entity/123"}}}]}]}]}"#.utf8))
    }

    @Test func concurrentOfflineRestartAndSelectiveUndo() throws {
        let alice = try RelayMarkCollaborationDocument()
        try seed(alice)
        let bob = try RelayMarkCollaborationDocument()
        try bob.applyUpdate(alice.encodeUpdate())
        let anchor = try bob.anchor(path: [0, 0], index: 6)
        let a = try alice.insertText("Alice ", at: 0, path: [0, 0])
        let b = try bob.insertText(" Bob", at: 8, path: [0, 0])
        let restarted = try RelayMarkCollaborationDocument()
        try restarted.applyUpdate(bob.encodeUpdate())
        for update in a { try restarted.applyUpdate(update) }
        for update in b { try alice.applyUpdate(update) }
        #expect(try alice.snapshot() == restarted.snapshot())
        #expect(try restarted.resolve(anchor: anchor)?.index == 12)
        let undo = try alice.undo()
        for update in undo { try restarted.applyUpdate(update) }
        #expect(try alice.snapshot() == restarted.snapshot())
        let json = String(decoding: try alice.snapshot(), as: UTF8.self)
        #expect(json.contains(" Bob"))
        #expect(!json.contains("Alice "))
        #expect(json.contains("relay:entity/123"))
    }

    @Test func deletionDiffAndInvalidEdit() throws {
        let alice = try RelayMarkCollaborationDocument()
        try seed(alice)
        let bob = try RelayMarkCollaborationDocument()
        try bob.applyUpdate(alice.encodeUpdate())
        let vector = try bob.stateVector()
        _ = try alice.deleteText(at: 0, length: 1, path: [0, 0])
        let update = try alice.encodeUpdate(since: vector)
        try bob.applyUpdate(update)
        try bob.applyUpdate(update)
        #expect(try bob.snapshot() == alice.snapshot())
        let before = try alice.snapshot()
        #expect(throws: RelayMarkCollaborationDocument.Failure.self) {
            try alice.deleteText(at: -1, length: 200, path: [0, 0])
        }
        #expect(try before == alice.snapshot())
    }
    @Test func nodeYjsBinaryInteroperability() throws {
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf:
            Bundle.module.url(forResource: "yjs-v13-xml", withExtension: "json")!)) as! [String: String]
        let doc = try RelayMarkCollaborationDocument()
        try doc.applyUpdate(Data(base64Encoded: fixture["seed"]!)!)
        _ = try doc.insertText("Swift ", at: 0, path: [0, 0])
        try doc.applyUpdate(Data(base64Encoded: fixture["browserUpdate"]!)!)
        let json = String(decoding: try doc.snapshot(), as: UTF8.self)
        #expect(json.contains("Swift "))
        #expect(json.contains("Hello 🌍 browser"))
        #expect(json.contains("relay:entity/123"))
        if let path = ProcessInfo.processInfo.environment["RELAY_COLLABORATION_INTEROP_OUTPUT"] {
            let output = ["update": try doc.encodeUpdate().base64EncodedString()]
            try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]).write(to: URL(fileURLWithPath: path))
        }
    }

    @Test func paragraphSplitMergePreservesSuffixAndUnknownNodes() throws {
        let doc = try RelayMarkCollaborationDocument()
        try seed(doc)
        _ = try doc.replaceProse(start: 5, end: 5, text: "\nnew")
        var prose = try RelayMarkCollaborativeProse(snapshot: doc.snapshot())
        #expect(String(prose.text.characters) == "Hello\nnew 🌍")
        #expect(prose.isEditable)
        #expect(prose.blockRanges.count == 2)
        _ = try doc.replaceProse(start: 5, end: 9, text: " again")
        prose = try RelayMarkCollaborativeProse(snapshot: doc.snapshot())
        #expect(String(prose.text.characters) == "Hello again 🌍")
        #expect(prose.blockRanges.count == 1)
        #expect(String(decoding: try doc.snapshot(), as: UTF8.self).contains("relay:entity/123"))
        _ = try doc.edit(Data(#"{"kind":"insertNodes","path":[],"index":1,"nodes":[{"kind":"element","name":"customWidget","attributes":{"secret":"opaque"},"children":[]}]}"#.utf8))
        #expect(try !RelayMarkCollaborativeProse(snapshot: doc.snapshot()).isEditable)
    }

    @Test func replacementUsesGraphemeBoundariesAndUTF16() {
        let diff = RelayMarkCollaborativeProse.replacement(from: "Hi 🌍!", to: "Hi 👨‍👩‍👧‍👦!")
        #expect(diff.start == 3)
        #expect(diff.end == 5)
        #expect(diff.text == "👨‍👩‍👧‍👦")
    }

}
