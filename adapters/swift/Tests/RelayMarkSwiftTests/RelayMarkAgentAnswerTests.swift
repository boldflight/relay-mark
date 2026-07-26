import Foundation
import Testing
@testable import RelayMarkSwift

struct RelayMarkAgentAnswerTests {
    @Test
    func validatesReceiptBoundAgentAnswerPairsAndReturnsExactByteDigests() throws {
        let receiptURL = repoRoot()
            .appendingPathComponent("spec/relaymark/conformance/agent-answer-fixture-receipt.json")
        let receipt = try JSONDecoder().decode(
            FixtureReceipt.self,
            from: Data(contentsOf: receiptURL)
        )

        #expect(receipt.type == "relaymark.fixture_receipt")
        #expect(receipt.version == "0.5.0-draft")
        #expect(receipt.algorithm == "sha256")
        #expect(receipt.pairs.map(\.id) == [
            "scripture-ask-answered",
            "scripture-ask-refused"
        ])

        for pair in receipt.pairs {
            let documentJSON = try receiptData(pair.document.path, relativeTo: receiptURL)
            let manifestJSON = try receiptData(pair.manifest.path, relativeTo: receiptURL)
            let result = try RelayMarkAgentAnswerValidator.validateTransport(
                documentJSON: documentJSON,
                manifestJSON: manifestJSON,
                context: .scriptureAsk
            )

            #expect(result.isValid)
            #expect(result.diagnostics.isEmpty)
            #expect(result.documentSHA256 == "sha256:\(pair.document.sha256)")
            #expect(result.manifestSHA256 == "sha256:\(pair.manifest.sha256)")

            let projection = try result.requireProjection()
            #expect(projection.document == result.document)
            #expect(projection.manifest == result.manifest)

            if pair.id == "scripture-ask-answered" {
                #expect(projection.outcome == .answered)
                #expect(projection.manifest.claims.count == 1)
                #expect(projection.manifest.sources.count == 2)
            } else {
                #expect(projection.outcome == .refused)
                #expect(projection.manifest.claims.isEmpty)
                #expect(projection.manifest.sources.isEmpty)
            }
        }
    }

    @Test
    func matchesPortableAgentAnswerDiagnosticsExactly() throws {
        for (documentName, diagnosticsName, context) in [
            (
                "invalid-agent-answer-question-id.ast.json",
                "invalid-agent-answer-question-id.diagnostics.json",
                RelayMarkAgentAnswerValidationContext.generic
            ),
            (
                "invalid-agent-answer-refusal.ast.json",
                "invalid-agent-answer-refusal.diagnostics.json",
                RelayMarkAgentAnswerValidationContext.generic
            ),
            (
                "invalid-agent-answer-scripture-evidence.ast.json",
                "invalid-agent-answer-scripture-evidence.diagnostics.json",
                RelayMarkAgentAnswerValidationContext.scriptureAsk
            )
        ] {
            let document = try RelayMarkDocument.decodeJSON(fixtureData(documentName))
            let expected = try RelayMarkDecoder.decode(
                [RelayMarkDiagnostic].self,
                from: fixtureData(diagnosticsName)
            )

            #expect(
                RelayMarkAgentAnswerValidator.diagnostics(
                    for: document,
                    context: context
                ) == expected,
                Comment(rawValue: documentName)
            )
        }
    }

    @Test
    func keepsScriptureEvidencePolicyInTheHostContext() throws {
        let document = try RelayMarkDocument.decodeJSON(
            fixtureData("invalid-agent-answer-scripture-evidence.ast.json")
        )

        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: document,
                context: .generic
            ).isEmpty
        )
        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: document,
                context: .scriptureAsk
            ).map(\.code) == ["relaymark.agent_answer.scripture_evidence"]
        )

        let combinedInvalid = try mutatedDocument(
            "invalid-agent-answer-scripture-evidence.ast.json"
        ) {
            var blocks = try requireArray($0["blocks"])
            var claim = try requireDictionary(blocks[1])
            var props = try requireDictionary(claim["props"])
            props["status"] = "disputed"
            claim["props"] = props
            var references = try requireArray(claim["evidence_refs"])
            references.append(references[0])
            claim["evidence_refs"] = references
            blocks[1] = claim
            $0["blocks"] = blocks
        }
        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: combinedInvalid,
                context: .scriptureAsk
            ).map(\.code) == [
                "relaymark.agent_answer.claim",
                "relaymark.agent_answer.claim_evidence",
                "relaymark.agent_answer.scripture_evidence"
            ]
        )
    }

    @Test
    func rejectsMissingProfileBeforeManifestComparison() throws {
        let documentJSON = try mutateJSON(fixtureData("scripture-ask-answered.ast.json")) {
            var frontmatter = try requireDictionary($0["frontmatter"])
            frontmatter.removeValue(forKey: "profile")
            $0["frontmatter"] = frontmatter
        }
        let result = try RelayMarkAgentAnswerValidator.validateTransport(
            documentJSON: documentJSON,
            manifestJSON: fixtureData("scripture-ask-answered.manifest.json"),
            context: .scriptureAsk
        )

        #expect(result.projection == nil)
        #expect(result.diagnostics == [
            RelayMarkDiagnostic(
                level: "error",
                code: "relaymark.agent_answer.profile",
                message: "Transported Agent Answer document must declare frontmatter.profile relaymark.agent_answer.v1."
            )
        ])
    }

    @Test
    func rejectsForgedManifestActionAndProjectionContentDrift() throws {
        let documentJSON = try fixtureData("scripture-ask-refused.ast.json")
        let forgedActionResult = try RelayMarkAgentAnswerValidator.validateTransport(
            documentJSON: documentJSON,
            manifestJSON: fixtureData("invalid-agent-answer-manifest-action.manifest.json")
        )

        #expect(forgedActionResult.projection == nil)
        #expect(forgedActionResult.diagnostics == [
            RelayMarkDiagnostic(
                level: "error",
                code: "relaymark.agent_answer.manifest_mismatch",
                message: "Transported relaymark.agent_answer.v1 manifest must exactly match the canonical projection of its document."
            )
        ])

        let answeredDocumentJSON = try fixtureData("scripture-ask-answered.ast.json")
        let alteredClaimManifest = try mutateJSON(
            fixtureData("scripture-ask-answered.manifest.json")
        ) {
            var claims = try requireArray($0["claims"])
            var claim = try requireDictionary(claims[0])
            claim["text"] = "Transported content drift."
            claims[0] = claim
            $0["claims"] = claims
        }
        let alteredClaimResult = try RelayMarkAgentAnswerValidator.validateTransport(
            documentJSON: answeredDocumentJSON,
            manifestJSON: alteredClaimManifest,
            context: .scriptureAsk
        )

        #expect(alteredClaimResult.diagnostics.map(\.code) == [
            "relaymark.agent_answer.manifest_mismatch"
        ])

        let alteredSourceManifest = try mutateJSON(
            fixtureData("scripture-ask-answered.manifest.json")
        ) {
            var sources = try requireArray($0["sources"])
            var evidence = try requireDictionary(sources[1])
            evidence["excerpt"] = "Transported source drift."
            sources[1] = evidence
            $0["sources"] = sources
        }
        let alteredSourceResult = try RelayMarkAgentAnswerValidator.validateTransport(
            documentJSON: answeredDocumentJSON,
            manifestJSON: alteredSourceManifest,
            context: .scriptureAsk
        )

        #expect(alteredSourceResult.diagnostics.map(\.code) == [
            "relaymark.agent_answer.manifest_mismatch"
        ])
    }

    @Test
    func preservesExactQuestionBytesAndFixedWhitespaceSemantics() throws {
        let exactQuestionDocument = try mutatedDocument(
            "scripture-ask-answered.ast.json"
        ) {
            var frontmatter = try requireDictionary($0["frontmatter"])
            frontmatter["question"] = "  Why did Priscilla travel? 🌿\n"
            frontmatter["question_id"] =
                "sha256:4028e93caf14fa131e71f9a4983efc2dcca8f1220d2e58e0deb386cb6e33ed23"
            $0["frontmatter"] = frontmatter
        }
        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: exactQuestionDocument
            ).isEmpty
        )

        let unicodeWhitespaceTitle = try mutatedDocument(
            "scripture-ask-answered.ast.json"
        ) {
            var frontmatter = try requireDictionary($0["frontmatter"])
            frontmatter["title"] = "\u{0085}"
            $0["frontmatter"] = frontmatter
        }
        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: unicodeWhitespaceTitle
            ).map(\.code) == ["relaymark.agent_answer.title"]
        )

        let byteOrderMarkTitle = try mutatedDocument(
            "scripture-ask-answered.ast.json"
        ) {
            var frontmatter = try requireDictionary($0["frontmatter"])
            frontmatter["title"] = "\u{FEFF}"
            $0["frontmatter"] = frontmatter
        }
        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: byteOrderMarkTitle
            ).isEmpty
        )
    }

    @Test
    func enforcesAnsweredAndRefusedStructureAndEvidenceRules() throws {
        let invalidClaim = try mutatedDocument("scripture-ask-answered.ast.json") {
            var blocks = try requireArray($0["blocks"])
            var claim = try requireDictionary(blocks[1])
            var props = try requireDictionary(claim["props"])
            props["status"] = "disputed"
            claim["props"] = props
            blocks[1] = claim
            $0["blocks"] = blocks
        }
        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: invalidClaim
            ).map(\.code) == ["relaymark.agent_answer.claim"]
        )

        let duplicateClaimEvidence = try mutatedDocument(
            "scripture-ask-answered.ast.json"
        ) {
            var blocks = try requireArray($0["blocks"])
            var claim = try requireDictionary(blocks[1])
            var references = try requireArray(claim["evidence_refs"])
            references.append(references[0])
            claim["evidence_refs"] = references
            blocks[1] = claim
            $0["blocks"] = blocks
        }
        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: duplicateClaimEvidence
            ).map(\.code) == ["relaymark.agent_answer.claim_evidence"]
        )

        let invalidHeading = try mutatedDocument("scripture-ask-answered.ast.json") {
            var blocks = try requireArray($0["blocks"])
            var heading = try requireDictionary(blocks[2])
            var content = try requireArray(heading["content"])
            var text = try requireDictionary(content[0])
            text["text"] = " Evidence"
            content[0] = text
            heading["content"] = content
            blocks[2] = heading
            $0["blocks"] = blocks
        }
        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: invalidHeading
            ).map(\.code) == ["relaymark.agent_answer.answered_structure"]
        )

        let invalidRefusal = try mutatedDocument("scripture-ask-refused.ast.json") {
            var frontmatter = try requireDictionary($0["frontmatter"])
            frontmatter["refusal_reason"] = "provider_failure"
            $0["frontmatter"] = frontmatter

            var blocks = try requireArray($0["blocks"])
            blocks.append([
                "id": "forbiddenRefusalSource",
                "type": "relay.source_bundle",
                "props": ["id": "forbidden-refusal-source"],
                "content": []
            ])
            $0["blocks"] = blocks
        }
        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: invalidRefusal
            ).map(\.code) == [
                "relaymark.agent_answer.refusal_reason",
                "relaymark.agent_answer.refused_structure",
                "relaymark.agent_answer.refused_content"
            ]
        )
    }

    private func mutatedDocument(
        _ name: String,
        mutate: (inout [String: Any]) throws -> Void
    ) throws -> RelayMarkDocument {
        try RelayMarkDocument.decodeJSON(
            mutateJSON(fixtureData(name), mutate: mutate)
        )
    }

    private func mutateJSON(
        _ data: Data,
        mutate: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        var object = try requireDictionary(
            JSONSerialization.jsonObject(with: data)
        )
        try mutate(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func requireDictionary(_ value: Any?) throws -> [String: Any] {
        try #require(value as? [String: Any])
    }

    private func requireArray(_ value: Any?) throws -> [Any] {
        try #require(value as? [Any])
    }

    private func receiptData(_ path: String, relativeTo receiptURL: URL) throws -> Data {
        try Data(
            contentsOf: receiptURL
                .deletingLastPathComponent()
                .appendingPathComponent(path)
                .standardizedFileURL
        )
    }

    private func fixtureData(_ name: String) throws -> Data {
        try Data(
            contentsOf: repoRoot()
                .appendingPathComponent("spec/relaymark/examples")
                .appendingPathComponent(name)
        )
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct FixtureReceipt: Decodable {
    let type: String
    let version: String
    let algorithm: String
    let pairs: [FixturePair]
}

private struct FixturePair: Decodable {
    let id: String
    let document: FixtureFile
    let manifest: FixtureFile
}

private struct FixtureFile: Decodable {
    let path: String
    let sha256: String
}
