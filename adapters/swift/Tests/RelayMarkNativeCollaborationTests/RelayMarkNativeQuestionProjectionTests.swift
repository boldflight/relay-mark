import Foundation
import Testing
import RelayMarkSwift
import RelayMarkProseProjection
@testable import RelayMarkNativeCollaboration

/// A question's range is what the editor draws its card from, so it must cover exactly the
/// authored label and options and follow edits.
struct RelayMarkNativeQuestionProjectionTests {
    static let source = "Intro\n\n<!-- relay:question id=\"q-one\" type=\"multiple_choice\" -->\n**Capital?**\n- ( ) Paris\n- ( ) London\n- ( ) Rome\n<!-- /relay:question -->"

    @MainActor static func projection() throws -> (RelayMarkNativeDocument, RelayMarkCollaborativeProse) {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "question-card"))
        return (document, try document.richProseProjection())
    }

    private func slice(_ prose: RelayMarkCollaborativeProse) throws -> String {
        let question = try #require(prose.questions.first)
        return (String(prose.text.characters) as NSString).substring(with: question.range)
    }

    @Test @MainActor func questionCoversItsLabelAndEachOption() throws {
        let (_, prose) = try Self.projection()
        #expect(prose.questions.count == 1)
        #expect(try slice(prose) == "Capital?\nParis\nLondon\nRome")
    }

    @Test @MainActor func rangesFollowAnEditBeforeTheQuestion() throws {
        let (document, before) = try Self.projection()
        let edit = try RelayMarkNativeRichEditing.replace(document: document, range: NSRange(location: 0, length: 0),
            runs: [("Hello ", [:])], inheritMarks: true, expectedSnapshot: document.snapshot())
        _ = edit
        let after = try document.richProseProjection()
        #expect(after.questions[0].range.location == before.questions[0].range.location + 6)
        #expect(try slice(after) == "Capital?\nParis\nLondon\nRome")
        // Typing inside the label moves the options without re-projecting the paper.
        let label = before.questions[0].range
        let typed = try #require(before.replacingText(in: NSRange(location: label.location, length: 0), with: "Hey ", attributes: [:]))
        #expect(try slice(typed) == "Hey Capital?\nParis\nLondon\nRome")
    }
}
