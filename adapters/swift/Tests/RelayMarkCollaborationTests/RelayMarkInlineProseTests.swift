import Foundation
import Testing
@testable import RelayMarkCollaboration

@MainActor
@Suite("Authored v1 inline and rule parity")
struct RelayMarkInlineProseTests {
    private func fixture() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "inline-v1", withExtension: "json"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    private enum FixtureError: Error { case invalid }
    private func binary(_ value: Any?) throws -> Data {
        guard let string = value as? String, let bytes = Data(base64Encoded: string) else { throw FixtureError.invalid }
        return bytes
    }
    private func seeded(_ fixture: [String: Any]) throws -> RelayMarkCollaborationDocument {
        let doc = try RelayMarkCollaborationDocument()
        try doc.applyUpdate(binary(fixture["seed"]))
        return doc
    }
    @Test func binaryFixturesAndNativeExportsConverge() throws {
        let fixture = try fixture()
        var exported: [[String: String]] = []
        for item in try #require(fixture["cases"] as? [[String: Any]]) {
            let doc = try seeded(fixture), peer = try seeded(fixture)
            let initial = try RelayMarkCollaborativeProse(snapshot: doc.snapshot())
            #expect(initial.isEditable)
            #expect(String(initial.text.characters) == fixture["initial_text"] as? String)
            let updates = try doc.replaceProse(start: #require(item["start"] as? Int), end: #require(item["end"] as? Int), text: #require(item["text"] as? String))
            for update in updates.reversed() { try peer.applyUpdate(update); try peer.applyUpdate(update) }
            let projection = try RelayMarkCollaborativeProse(snapshot: doc.snapshot())
            #expect(projection.isEditable)
            #expect(String(projection.text.characters) == item["expected"] as? String)
            #expect(try doc.snapshot() == peer.snapshot())
            exported.append(["id": try #require(item["id"] as? String), "update": try doc.encodeUpdate().base64EncodedString()])
        }
        let doc = try seeded(fixture)
        let anchor = try doc.anchor(path: [0, 3], index: 0)
        _ = try doc.replaceProse(start: 3, end: 4, text: "")
        try doc.applyUpdate(binary(fixture["remote_update"]))
        let resolved = try #require(try doc.resolve(anchor: anchor))
        #expect(resolved.path == [0, 2] && resolved.index == 0)
        #expect(try String(RelayMarkCollaborativeProse(snapshot: doc.snapshot()).text.characters) == "A🌍BC!\n\u{FFFC}\nD\ne\u{2028}f\nlet x\n")
        exported.append(["id": "concurrent", "update": try doc.encodeUpdate().base64EncodedString()])
        if let output = ProcessInfo.processInfo.environment["RELAY_INLINE_CONFORMANCE_OUTPUT"] {
            try JSONSerialization.data(withJSONObject: exported, options: [.sortedKeys]).write(to: URL(fileURLWithPath: output))
        }
    }
    @Test func mixedTextFormattingAndEveryUTF16PositionMapToRealTypes() throws {
        let doc = try seeded(fixture())
        let projection = try RelayMarkCollaborativeProse(snapshot: doc.snapshot())
        let count = String(projection.text.characters).utf16.count
        let leaves = projection.textRanges(in: NSRange(location: 0, length: count))
        #expect(leaves.map(\.path) == [[0,0], [0,2], [0,3], [2,0], [3,0,0], [3,0,2], [4,0], [4,1]])
        for offset in 0...count {
            let position = try #require(projection.position(atUTF16: offset))
            let anchor = try doc.anchor(path: position.path, index: position.index)
            let restored = try #require(try doc.resolve(anchor: anchor))
            #expect(projection.offset(for: restored) == offset, "UTF16 offset \(offset)")
        }
        for span in projection.textRanges(in: NSRange(location: 2, length: 4)) {
            _ = try doc.edit(JSONSerialization.data(withJSONObject: ["kind":"formatText", "path":span.path,
                "index":span.index, "length":span.length, "attributes":["bold":[:]]]))
        }
        #expect(try RelayMarkCollaborativeProse(snapshot: doc.snapshot()).isEditable)
        #expect(String(decoding: try doc.snapshot(), as: UTF8.self).contains("relay:entity/person-1"))
    }
    @Test func ruleOnlyDocumentSupportsAtomicSelectionDeletionAndUndo() throws {
        let doc = try RelayMarkCollaborationDocument()
        _ = try doc.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"horizontalRule","children":[]}]}"#.utf8))
        let projection = try RelayMarkCollaborativeProse(snapshot: doc.snapshot())
        #expect(projection.isEditable && String(projection.text.characters) == "\u{FFFC}")
        for offset in 0...1 {
            let position = try #require(projection.position(atUTF16: offset))
            let anchor = try doc.anchor(path: position.path, index: position.index)
            #expect(try projection.offset(for: #require(try doc.resolve(anchor: anchor))) == offset)
        }
        _ = try doc.replaceProse(start: 0, end: 1, text: "")
        #expect(try RelayMarkCollaborativeProse(snapshot: doc.snapshot()).isEditable)
        #expect(try String(RelayMarkCollaborativeProse(snapshot: doc.snapshot()).text.characters).isEmpty)
        _ = try doc.undo()
        #expect(try String(RelayMarkCollaborativeProse(snapshot: doc.snapshot()).text.characters) == "\u{FFFC}")
    }
    @Test func unknownInlineFailsClosedWithoutMutation() throws {
        for child in [#"{"kind":"element","name":"mention","children":[]}"#,
                      #"{"kind":"element","name":"hardBreak","attributes":{"unknown":true},"children":[]}"#] {
            let doc = try RelayMarkCollaborationDocument()
            _ = try doc.edit(Data("{\"kind\":\"insertNodes\",\"path\":[],\"index\":0,\"nodes\":[{\"kind\":\"element\",\"name\":\"paragraph\",\"children\":[\(child)]}]}".utf8))
            let before = try doc.encodeUpdate()
            #expect(try !RelayMarkCollaborativeProse(snapshot: doc.snapshot()).isEditable)
            #expect(throws: (any Error).self) { try doc.replaceProse(start: 0, end: 0, text: "No") }
            #expect(try doc.encodeUpdate() == before)
        }
    }
    @Test func crossBlockMergeIntoCodeRejectsWithoutDurableMutation() throws {
        let doc = try RelayMarkCollaborationDocument()
        _ = try doc.edit(Data(#"{"kind":"insertNodes","path":[],"index":0,"nodes":[{"kind":"element","name":"codeBlock","children":[{"kind":"text","delta":[{"insert":"x"}]}]},{"kind":"element","name":"paragraph","children":[{"kind":"text","delta":[{"insert":"bold","attributes":{"bold":{}}}]}]}]}"#.utf8))
        #expect(try RelayMarkCollaborativeProse(snapshot: doc.snapshot()).isEditable)
        let before = try doc.encodeUpdate()
        #expect(throws: (any Error).self) { try doc.replaceProse(start: 1, end: 2, text: "") }
        #expect(try doc.encodeUpdate() == before)
        #expect(try String(RelayMarkCollaborativeProse(snapshot: doc.snapshot()).text.characters) == "x\nbold")
    }

}
