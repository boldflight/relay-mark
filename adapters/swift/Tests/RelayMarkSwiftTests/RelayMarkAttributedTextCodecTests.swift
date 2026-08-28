import Foundation
import Testing

@testable import RelayMarkSwift

@Suite("RelayMark attributed text codec")
struct RelayMarkAttributedTextCodecTests {
    @Test("portable prose and entity links survive a native attributed-text round trip")
    func roundTripsPortableSource() {
        let source = """
            # Launch review

            We met with **[Jordan Hale](relay:entity/person-42)**.

            ## Decisions

            - Ship the native canvas
            - Keep the transcript read-only
            """

        let encoded = RelayMarkAttributedTextCodec.source(
            from: RelayMarkAttributedTextCodec.attributedString(from: source)
        )

        #expect(encoded.contains("# Launch review"))
        #expect(encoded.contains("## Decisions"))
        #expect(encoded.contains("- Ship the native canvas"))
        #expect(encoded.contains("relay:entity/person-42"))
        #expect(
            RelayMarkAttributedTextCodec.entityReferences(in: encoded)
                == [RelayMarkSourceEntityReference(id: "person-42", label: "Jordan Hale")]
        )
    }

    @Test("entity links use the canonical readable source form")
    func createsCanonicalEntityLink() {
        #expect(
            RelayMarkAttributedTextCodec.entityLink(label: "Jordan Hale", id: "person-42")
                == "[Jordan Hale](relay:entity/person-42)"
        )
    }
}
