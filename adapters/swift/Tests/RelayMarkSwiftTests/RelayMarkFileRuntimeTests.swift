import Foundation
import Testing
import RelayMarkSwift

@Suite("Packaged canonical File conversion")
struct RelayMarkFileRuntimeTests {
    @Test("A canonical empty File survives the packaged Swift grammar with its exact prose")
    func fileOmittedPMContentPreservesDescriptorAndProse() throws {
        let expected: [String: Any] = ["type": "relaymark.document", "blocks": [
            ["id": "b00000000000040008000000000000061", "type": "relay.file_ref",
             "props": ["id": "11111111-1111-4111-8111-111111111111",
                       "uri": "/m/11111111-1111-4111-8111-111111111111",
                       "label": "Care Ω.pdf", "scope": "private"], "content": []] as [String: Any],
            ["id": "b00000000000040008000000000000062", "type": "paragraph", "content": [
                ["type": "strong", "content": [["type": "text", "text": "Keep 世界"]]],
                ["type": "text", "text": " beside the file."]
            ]] as [String: Any]
        ]]
        let authored = try JSONSerialization.data(withJSONObject: expected)
        print("FILE_RUNTIME_READY:canonical-file-and-prose")
        let snapshot: Data
        do {
            snapshot = try RelayMarkSourceCodec.documentToSnapshot(authored)
        } catch {
            if let failure = error as? RelayMarkSourceCodec.Failure,
               failure == .invalidAuthoredDocument {
                print("FILE_RUNTIME_ORIGINAL:source-normalization-invalidAuthoredDocument")
            }
            throw error
        }
        // The source owner itself performs the actual maintained PM Node.toJSON.
        let roundTrip = try RelayMarkSourceCodec.snapshotToDocument(snapshot)
        let roundTripObject = try #require(JSONSerialization.jsonObject(with: roundTrip) as? [String: Any])
        #expect(NSDictionary(dictionary: roundTripObject).isEqual(to: expected))
        print("FILE_RUNTIME_DONE:exact-descriptor-prose-and-outer-identities")
    }
}
