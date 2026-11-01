import Foundation
import Testing
import RelayMarkSwift
import RelayMarkProseProjection
@testable import RelayMarkNativeCollaboration

/// A question card's ranges are what the editor draws its card, option states and answer
/// slot from, so each must cover exactly the authored paragraph it names.
struct RelayMarkNativeQuestionProjectionTests {
    static let source = "Intro\n\n<!-- relay:question id=\"q-one\" type=\"multiple_choice\" -->\n**Capital?**\n- ( ) Paris\n- ( ) London\n- ( ) Rome\n<!-- /relay:question -->"

    @MainActor static func projection() throws -> (RelayMarkNativeDocument, RelayMarkCollaborativeProse) {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "question-card"))
        return (document, try document.richProseProjection())
    }

    private func slices(_ prose: RelayMarkCollaborativeProse) throws -> (question: String, label: String, options: [String]) {
        let text = String(prose.text.characters) as NSString
        let question = try #require(prose.questions.first)
        return (text.substring(with: question.range), text.substring(with: question.labelRange),
                question.options.map { text.substring(with: $0.range) })
    }

    @Test @MainActor func questionCoversItsLabelAndEachOption() throws {
        let (_, prose) = try Self.projection()
        let question = try #require(prose.questions.first)
        #expect(prose.questions.count == 1)
        #expect(question.id == "q-one")
        #expect(question.type == "multiple_choice")
        let found = try slices(prose)
        #expect(found.label == "Capital?")
        #expect(found.options == ["Paris", "London", "Rome"])
        #expect(found.question == "Capital?\nParis\nLondon\nRome")
        #expect(Set(question.options.map(\.id)).count == 3)
    }

    @Test @MainActor func rangesFollowAnEditBeforeTheQuestion() throws {
        let (document, before) = try Self.projection()
        let edit = try RelayMarkNativeRichEditing.replace(document: document, range: NSRange(location: 0, length: 0),
            runs: [("Hello ", [:])], inheritMarks: true, expectedSnapshot: document.snapshot())
        _ = edit
        let after = try document.richProseProjection()
        #expect(after.questions[0].range.location == before.questions[0].range.location + 6)
        #expect(try slices(after).options == ["Paris", "London", "Rome"])
        // Typing inside the label moves the options without re-projecting the paper.
        let label = before.questions[0].labelRange
        let typed = try #require(before.replacingText(in: NSRange(location: label.location, length: 0), with: "Hey ", attributes: [:]))
        let found = try slices(typed)
        #expect(found.label == "Hey Capital?")
        #expect(found.options == ["Paris", "London", "Rome"])
        #expect(found.question == "Hey Capital?\nParis\nLondon\nRome")
    }
}
