import Foundation
import Testing
@testable import RelayMarkSwift
struct RelayMarkContractTests {
    @Test func unversionedASTAndOldNumberCollision() throws {
        #expect(RelayMarkContract.version == 1)
        #expect(RelayMarkContract.schema == "relaymark-prosemirror")
        #expect(RelayMarkContract.sourceContract == "relaymark_ast")
        let source = Data(#"{"type":"relaymark.document","blocks":[]}"#.utf8)
        let ast = try RelayMarkDocument.decodeJSON(source)
        #expect(ast.blocks.isEmpty)
        #expect(throws: (any Error).self) {
            try RelayMarkDocument.decodeJSON(Data(#"{"type":"relaymark.document","version":1,"blocks":[]}"#.utf8))
        }
    }
}
