import Foundation
import Testing
@testable import RelayMarkSwift

struct RelayMarkSwiftTests {
    @Test
    func decodesAgentPaperCompositionBindingsAndCapabilities() throws {
        let document = try RelayMarkDocument.decodeJSON(fixtureData("person-paper.ast.json"))
        let manifest = try RelayMarkManifest.decodeJSON(fixtureData("person-paper.manifest.json"))

        #expect(document.blocks.map(\.type) == ["heading", "relay.property_sheet", "paragraph", "relay.data_view", "relay.data_view"])
        #expect(manifest.propertySheets.first?.binding == "paper.person.properties")
        #expect(manifest.propertySheets.first?.fields == ["full_name", "emails", "phones", "company"])
        #expect(manifest.dataViews.map(\.source) == ["paper.related_commitments", "paper.journey_summary"])
        #expect(manifest.capabilities.map(\.id) == [.propertySheet, .dataView, .dataView])
    }

    @Test
    func decodesPortableLayerRolesAnchorsAndFallbacksWithoutAccessRules() throws {
        let composition = try RelayMarkLayerComposition.decodeJSON(fixtureData("layered-meeting.composition.json"))

        #expect(composition.type == "relaymark.layer_composition")
        #expect(composition.layers.map(\.role) == [.authored, .generated, .source, .discussion])
        #expect(composition.layers[1].items[0].placement?.anchor?.blockID == "meeting_heading")
        #expect(composition.layers[1].items[1].placement?.anchorState == .stale)
        #expect(composition.layers[1].items[1].placement?.fallback == .appendToLayer)
        #expect(composition.layers[3].items[0].placement?.anchor == nil)
        #expect(composition.layers[3].items[0].placement?.anchorState == .undisclosed)
    }

    @Test
    func decodesInlineEntityReferenceWithIDAsInlineContent() throws {
        let data = Data(
            #"{"type":"relaymark.document","blocks":[{"id":"b1","type":"paragraph","content":[{"type":"relay.entity_ref","id":"product-1","label":"Mac mini"}]}]}"#.utf8
        )

        let document = try RelayMarkDocument.decodeJSON(data)

        guard case let .inline(reference) = document.blocks[0].content[0] else {
            Issue.record("Expected an inline entity reference")
            return
        }

        #expect(reference.type == "relay.entity_ref")
        #expect(reference.id == "product-1")
        #expect(reference.label == "Mac mini")
    }

    @Test
    func decodesRelayMarkDocumentFixture() throws {
        let document = try RelayMarkDocument.decodeJSON(fixtureData("mentor-meeting.ast.json"))

        #expect(document.type == "relaymark.document")
        #expect(document.frontmatter["title"]?.stringValue == "Marcus interview prep")
        #expect(document.blocks.count == 5)

        let sourceBundle = document.blocks[2]
        #expect(sourceBundle.id == "b3")
        #expect(sourceBundle.props["id"]?.stringValue == "src-1")
        #expect(sourceBundle.type == "relay.source_bundle")
        #expect(sourceBundle.props["scope"]?.stringValue == "private")
        #expect(sourceBundle.childBlocks.first?.type == "relay.transcript_segment")

        let action = document.blocks[4]
        #expect(action.type == "relay.action_row")
        #expect(action.props["action"]?.stringValue == "relay.task.create")
        #expect(action.evidenceRefs == ["src-1"])
        #expect(action.plainText == "Send interview prep resources before Thursday.")
    }

    @Test
    func decodesRelayMarkManifestFixture() throws {
        let manifest = try RelayMarkManifest.decodeJSON(fixtureData("mentor-meeting.manifest.json"))

        #expect(manifest.type == "relaymark.manifest")
        #expect(manifest.actions.count == 1)
        #expect(manifest.actions[0].blockID == "b6")
        #expect(manifest.actions[0].proposalID == nil)
        #expect(manifest.actions[0].proposalRecordID == nil)
        #expect(manifest.actions[0].proposalRevision == nil)
        #expect(manifest.actions[0].action == "relay.task.create")
        #expect(manifest.actions[0].args["title"]?.stringValue == "Send interview prep resources before Thursday.")
        #expect(manifest.sources.map(\.kind) == ["source_bundle", "transcript_range"])
        #expect(manifest.diagnostics.isEmpty)
    }

    @Test
    func decodesStableEvidenceAndActionLifecycleFixture() throws {
        let document = try RelayMarkDocument.decodeJSON(fixtureData("agent-paper-review.ast.json"))
        let manifest = try RelayMarkManifest.decodeJSON(fixtureData("agent-paper-review.manifest.json"))

        let sourceBundle = document.blocks[2]
        #expect(sourceBundle.id == "b3")
        #expect(sourceBundle.props["id"]?.stringValue == "source-review-1")
        #expect(sourceBundle.props["revision"]?.numberValue == 2)
        #expect(sourceBundle.childBlocks.map(\.type) == [
            "relay.evidence_ref",
            "relay.evidence_ref",
            "relay.evidence_ref"
        ])

        let transcriptEvidence = sourceBundle.childBlocks[0]
        #expect(transcriptEvidence.id == "b4")
        #expect(transcriptEvidence.props["id"]?.stringValue == "70000000-0000-4000-8000-000000000001")
        #expect(transcriptEvidence.props["source_type"]?.stringValue == "transcript")

        #expect(manifest.actions.map(\.proposalID) == [
            "practice-task",
            "coaching-touchpoint",
            "interview-journey",
            "practice-resource",
            "practice-follow-up"
        ])
        #expect(manifest.actions.map(\.proposalRecordID) == [
            "10000000-0000-4000-8000-000000000001",
            "10000000-0000-4000-8000-000000000002",
            "10000000-0000-4000-8000-000000000003",
            "10000000-0000-4000-8000-000000000004",
            "10000000-0000-4000-8000-000000000005"
        ])
        #expect(manifest.actions.map(\.proposalRevision) == [1, 2, 1, 1, 1])
        #expect(manifest.actions.map(\.review) == ["ready", "accepted", "rejected", "undone", "ready"])
        #expect(manifest.actions[1].executionID == "30000000-0000-4000-8000-000000000002")
        #expect(manifest.actions[3].decisionID == "20000000-0000-4000-8000-000000000004")
        #expect(manifest.actions[3].undoID == "40000000-0000-4000-8000-000000000004")
        #expect(manifest.actions[0].args["name"]?.stringValue == "Practice interview answers twice")
        #expect(manifest.actions[0].args["title"]?.stringValue == "Create Jordan's edited practice task.")
        #expect(manifest.actions.last?.action == "follow_up_create")

        #expect(manifest.sources.map(\.kind) == [
            "source_bundle",
            "evidence_ref",
            "evidence_ref",
            "evidence_ref"
        ])
        #expect(manifest.sources[1].blockID == "b4")
        #expect(manifest.sources[1].evidenceID == "70000000-0000-4000-8000-000000000001")
        #expect(manifest.sources[1].sourceRevision == "1")
        #expect(manifest.sources[1].selector?["start_ms"]?.numberValue == 724000)
        #expect(manifest.sources[1].excerpt == "I will practice twice before Thursday.")
    }

    @Test
    func decodesProductResearchDocumentFixture() throws {
        let document = try RelayMarkDocument.decodeJSON(fixtureData("product-research.ast.json"))

        #expect(document.blocks.count == 9)

        guard case let .inline(productReference) = document.blocks[1].content[1] else {
            Issue.record("Expected a product reference to remain inline")
            return
        }

        #expect(productReference.type == "relay.product_ref")
        #expect(productReference.id == "product-mac-mini-m4-pro")
        #expect(productReference.label == "Mac mini with M4 Pro")

        let sourceBundle = document.blocks[2]
        #expect(sourceBundle.childBlocks.map(\.type) == ["relay.url_ref", "relay.url_ref"])

        let comparison = document.blocks[4]
        #expect(comparison.type == "relay.comparison")
        #expect(comparison.evidenceRefs == ["src-apple", "src-mbench"])
        #expect(comparison.plainText == "Mac mini with M4 Pro is the lower-cost fit; Mac Studio with M4 Max leads on memory bandwidth and the imported CPU score.")
    }

    @Test
    func decodesProductResearchManifestFixture() throws {
        let manifest = try RelayMarkManifest.decodeJSON(fixtureData("product-research.manifest.json"))

        #expect(manifest.actions.map(\.review) == ["accepted", "rejected"])
        #expect(manifest.references.map(\.type) == [
            "relay.product_ref",
            "relay.product_ref",
            "relay.entity_ref",
            "relay.product_ref",
            "relay.product_ref"
        ])
        #expect(manifest.claims.map(\.status) == ["disputed", "disputed"])
        #expect(manifest.claims.map(\.evidenceRefs) == [["src-apple"], ["src-mbench"]])
        #expect(manifest.comparisons.count == 1)
        #expect(manifest.comparisons[0].layout == "table")
        #expect(manifest.comparisons[0].preferred == "entity:product-mac-mini-m4-pro")
        #expect(manifest.comparisons[0].values["price_usd"]?.objectValue?["entity:product-mac-mini-m4-pro"]?.numberValue == 1399)
    }

    @Test
    func decodesPortableScriptureEvidenceFixture() throws {
        let document = try RelayMarkDocument.decodeJSON(fixtureData("scripture-evidence.ast.json"))
        let manifest = try RelayMarkManifest.decodeJSON(fixtureData("scripture-evidence.manifest.json"))

        let resource = try #require(document.resources.first)
        let release = try resource.decodeScriptureRelease()
        #expect(release.translationID == "urn:relay:scripture:translation:kjv")
        #expect(release.corpusReleaseID == "urn:relay:scripture:corpus:kjv:1769-fixture-1")

        let source = try #require(manifest.sources.first)
        let evidence = try source.decodeScriptureEvidence()
        #expect(evidence.sourceRevision == release.corpusReleaseID)
        #expect(evidence.release.versificationID == "urn:relay:scripture:versification:kjv")

        guard case let .chapter(bookID, chapter, startVerseLabel) = evidence.span.start,
              case let .chapter(endBookID, endChapter, endVerseLabel) = evidence.span.end else {
            Issue.record("Expected chapter coordinates")
            return
        }

        #expect(bookID == "ACT")
        #expect(chapter == 18)
        #expect(startVerseLabel == "2")
        #expect(endBookID == "ACT")
        #expect(endChapter == 18)
        #expect(endVerseLabel == "3")

        let section = try RelayMarkDecoder.decode(
            RelayMarkScriptureCoordinate.self,
            from: Data(
                #"{"book_id":"SIR","coordinate_kind":"section","section_id":"prologue","verse_label":"prologue"}"#.utf8
            )
        )
        #expect(section == .section(bookID: "SIR", sectionID: "prologue", verseLabel: "prologue"))
    }

    @Test
    func decodesAnsweredAgentPaperFixture() throws {
        let document = try RelayMarkDocument.decodeJSON(fixtureData("scripture-ask-answered.ast.json"))
        let manifest = try RelayMarkManifest.decodeJSON(fixtureData("scripture-ask-answered.manifest.json"))

        #expect(document.frontmatter["profile"]?.stringValue == "relaymark.agent_answer.v1")
        #expect(document.frontmatter["outcome"]?.stringValue == "answered")
        #expect(document.frontmatter["question_id"]?.stringValue == "sha256:6640f17d592931bf54f6d3bdf1c1b5f1a7a302bcdc4b7a2e626fd9671b6a1da8")
        #expect(document.frontmatter["question"]?.stringValue == "What does Acts 18:2-3 say about Aquila and Priscilla?")
        #expect(document.frontmatter["refusal_reason"] == nil)

        let claim = try #require(manifest.claims.first)
        #expect(manifest.claims.count == 1)
        #expect(claim.blockID == "askClaim1")
        #expect(claim.key == "scripture.ask.aquila-priscilla.acts-18-2-3")
        #expect(claim.status == "supported")
        #expect(claim.evidenceRefs == ["urn:relay:scripture:evidence:acts-18-2-3"])
        #expect(claim.text == "Acts 18:2-3 identifies Aquila as a Jewish man from Pontus, names Priscilla as his wife, and says their occupation was tentmaking.")

        #expect(manifest.sources.count == 2)
        let sourceBundle = manifest.sources[0]
        #expect(sourceBundle.kind == "source_bundle")
        #expect(sourceBundle.sourceID == "urn:relay:scripture:source-bundle:ask-aquila-priscilla-1")
        #expect(sourceBundle.bundleRevision == 1)

        let source = manifest.sources[1]
        let evidence = try source.decodeScriptureEvidence()
        #expect(source.blockID == "askEvidence1")
        #expect(evidence.evidenceID == "urn:relay:scripture:evidence:acts-18-2-3")
        #expect(evidence.sourceID == "askScriptureRelease1")
        #expect(evidence.sourceRevision == "urn:relay:scripture:corpus:kjv:1769-fixture-1")
        #expect(evidence.scope == "public")
        #expect(evidence.release.profile == "relaymark.scripture_release.v1")
        #expect(evidence.release.translationID == "urn:relay:scripture:translation:kjv")
        #expect(evidence.release.editionID == "urn:relay:scripture:edition:kjv-1769-fixture")
        #expect(evidence.release.corpusReleaseID == evidence.sourceRevision)
        #expect(evidence.release.versificationID == "urn:relay:scripture:versification:kjv")
        #expect(evidence.release.source.digest == evidence.span.contentDigest)

        guard case let .chapter(bookID, chapter, startVerseLabel) = evidence.span.start,
              case let .chapter(endBookID, endChapter, endVerseLabel) = evidence.span.end else {
            Issue.record("Expected chapter coordinates")
            return
        }

        #expect(bookID == "ACT")
        #expect(chapter == 18)
        #expect(startVerseLabel == "2")
        #expect(endBookID == "ACT")
        #expect(endChapter == 18)
        #expect(endVerseLabel == "3")

        let resource = try #require(document.resources.first)
        let release = try resource.decodeScriptureRelease()
        #expect(document.resources.count == 1)
        #expect(resource.id == evidence.sourceID)
        #expect(release == evidence.release)
        #expect(manifest.actions.isEmpty)
    }

    @Test
    func decodesRefusedAgentPaperFixture() throws {
        let document = try RelayMarkDocument.decodeJSON(fixtureData("scripture-ask-refused.ast.json"))
        let manifest = try RelayMarkManifest.decodeJSON(fixtureData("scripture-ask-refused.manifest.json"))

        #expect(document.frontmatter["profile"]?.stringValue == "relaymark.agent_answer.v1")
        #expect(document.frontmatter["outcome"]?.stringValue == "refused")
        #expect(document.frontmatter["question_id"]?.stringValue == "sha256:b776b0f739964c4ebe9826ffef5212952a7a1ec9e90e2ac22f7839ae7ae56052")
        #expect(document.frontmatter["question"]?.stringValue == "Was Priscilla the author of Hebrews?")
        #expect(document.frontmatter["refusal_reason"]?.stringValue == "insufficient_evidence")

        #expect(document.blocks.map(\.type) == ["heading", "paragraph"])
        #expect(document.resources.isEmpty)
        #expect(manifest.claims.isEmpty)
        #expect(manifest.sources.isEmpty)
        #expect(manifest.actions.isEmpty)
    }

    private func fixtureData(_ name: String) throws -> Data {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repoRoot
            .appendingPathComponent("spec")
            .appendingPathComponent("relaymark")
            .appendingPathComponent("examples")
            .appendingPathComponent(name)
        return try Data(contentsOf: fixtureURL)
    }
}
