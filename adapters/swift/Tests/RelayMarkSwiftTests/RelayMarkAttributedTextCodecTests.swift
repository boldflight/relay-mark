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

    @Test("server-canonical angle destinations retain the link ID and formatted label")
    func extractsServerCanonicalEntityLink() {
        let id = "9f815b37-67b3-4101-868c-5335351feb6a"
        let source = "Meet [Ada **Lovelace**](<relay:entity/\(id)>). " +
            "[Ada again](relay:entity/\(id)) also appears."

        #expect(RelayMarkAttributedTextCodec.entityReferences(in: source) == [
            RelayMarkSourceEntityReference(id: id, label: "Ada Lovelace")
        ])
    }
}
