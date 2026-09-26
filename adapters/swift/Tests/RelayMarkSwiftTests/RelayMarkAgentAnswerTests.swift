import CryptoKit
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
        #expect(receipt.version == "0.9.0-draft")
        #expect(receipt.algorithm == "sha256")
        #expect(receipt.pairs.map(\.id) == [
            "scripture-ask-answered",
            "scripture-ask-refused"
        ])

        for pair in receipt.pairs {
            let documentJSON = try receiptData(pair.document.path, relativeTo: receiptURL)
            let manifestJSON = try receiptData(pair.manifest.path, relativeTo: receiptURL)

            #expect(sha256Hex(documentJSON) == pair.document.sha256)
            #expect(sha256Hex(manifestJSON) == pair.manifest.sha256)

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
    func rejectsInvalidDocumentEnvelopeAndDuplicateBlockIDsBeforeProjection() throws {
        let invalidEnvelopeJSON = try mutateJSON(
            fixtureData("scripture-ask-answered.ast.json")
        ) {
            $0["type"] = "relaymark.manifest"
            $0["version"] = 0
        }
        let invalidEnvelope = try RelayMarkDocument.decodeJSON(invalidEnvelopeJSON)
        let expectedEnvelopeDiagnostics = [
            RelayMarkDiagnostic(
                level: "error",
                code: "relaymark.document.type",
                message: "Document type must be relaymark.document."
            ),
            RelayMarkDiagnostic(
                level: "error",
                code: "relaymark.document.version",
                message: "Document version must be a positive integer."
            )
        ]

        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: invalidEnvelope,
                context: .scriptureAsk
            ) == expectedEnvelopeDiagnostics
        )

        let answeredManifest = try fixtureData("scripture-ask-answered.manifest.json")
        #expect(
            transportValidationError(
                documentJSON: invalidEnvelopeJSON,
                manifestJSON: answeredManifest,
                context: .scriptureAsk
            ) == .diagnostics([schemaDiagnostic()])
        )

        let duplicateBlockJSON = try mutateJSON(
            fixtureData("scripture-ask-answered.ast.json")
        ) {
            var blocks = try requireArray($0["blocks"])
            var evidenceHeading = try requireDictionary(blocks[2])
            evidenceHeading["id"] = "askClaim1"
            blocks[2] = evidenceHeading
            $0["blocks"] = blocks
        }
        let duplicateBlock = try RelayMarkDocument.decodeJSON(duplicateBlockJSON)
        let expectedDuplicateDiagnostics = [
            RelayMarkDiagnostic(
                level: "error",
                code: "relaymark.block.duplicate_id",
                message: "Duplicate block id 'askClaim1'."
            )
        ]

        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: duplicateBlock,
                context: .scriptureAsk
            ) == expectedDuplicateDiagnostics
        )

        let duplicateBlockTransport = try RelayMarkAgentAnswerValidator.validateTransport(
            documentJSON: duplicateBlockJSON,
            manifestJSON: fixtureData("scripture-ask-answered.manifest.json"),
            context: .scriptureAsk
        )
        #expect(duplicateBlockTransport.projection == nil)
        #expect(duplicateBlockTransport.diagnostics == expectedDuplicateDiagnostics)
    }

    @Test
    func rejectsNonPortableTransportedDocumentAndDirectiveShapes() throws {
        let answeredManifest = try fixtureData("scripture-ask-answered.manifest.json")

        let unknownDirectiveJSON = try mutateJSON(
            fixtureData("scripture-ask-answered.ast.json")
        ) {
            var blocks = try requireArray($0["blocks"])
            var sourceBundle = try requireDictionary(blocks[3])
            var content = try requireArray(sourceBundle["content"])
            content.append([
                "id": "unknownNestedDirective",
                "type": "relay.fake",
                "props": [:]
            ])
            sourceBundle["content"] = content
            blocks[3] = sourceBundle
            $0["blocks"] = blocks
        }
        let unknownDirective = try RelayMarkAgentAnswerValidator.validateTransport(
            documentJSON: unknownDirectiveJSON,
            manifestJSON: answeredManifest,
            context: .scriptureAsk
        )
        #expect(unknownDirective.diagnostics == [
            RelayMarkDiagnostic(
                level: "error",
                code: "relaymark.directive.unknown_type",
                message: "Unknown Relay block type 'relay.fake'."
            )
        ])

        let missingRequiredAttributeJSON = try mutateJSON(
            fixtureData("scripture-ask-answered.ast.json")
        ) {
            var blocks = try requireArray($0["blocks"])
            var sourceBundle = try requireDictionary(blocks[3])
            var content = try requireArray(sourceBundle["content"])
            content.append([
                "id": "missingURLAttribute",
                "type": "relay.url_ref",
                "props": [:]
            ])
            sourceBundle["content"] = content
            blocks[3] = sourceBundle
            $0["blocks"] = blocks
        }
        let missingRequiredAttribute =
            try RelayMarkAgentAnswerValidator.validateTransport(
                documentJSON: missingRequiredAttributeJSON,
                manifestJSON: answeredManifest,
                context: .scriptureAsk
            )
        #expect(missingRequiredAttribute.diagnostics == [
            RelayMarkDiagnostic(
                level: "error",
                code: "relaymark.attribute.required",
                message: "relay.url_ref.url is required."
            )
        ])

        let negativeRevisionDocument = try mutateJSON(
            fixtureData("scripture-ask-answered.ast.json")
        ) {
            var blocks = try requireArray($0["blocks"])
            var sourceBundle = try requireDictionary(blocks[3])
            var props = try requireDictionary(sourceBundle["props"])
            props["revision"] = -1
            sourceBundle["props"] = props
            blocks[3] = sourceBundle
            $0["blocks"] = blocks
        }
        let negativeRevisionManifest = try mutateJSON(answeredManifest) {
            var sources = try requireArray($0["sources"])
            var sourceBundle = try requireDictionary(sources[0])
            sourceBundle["bundle_revision"] = -1
            sources[0] = sourceBundle
            $0["sources"] = sources
        }
        let negativeRevision = try RelayMarkAgentAnswerValidator.validateTransport(
            documentJSON: negativeRevisionDocument,
            manifestJSON: negativeRevisionManifest,
            context: .scriptureAsk
        )
        #expect(negativeRevision.diagnostics == [
            RelayMarkDiagnostic(
                level: "error",
                code: "relaymark.source_bundle.revision",
                message: "relay.source_bundle.revision must be a non-negative integer."
            )
        ])

        let illegalBlockIDJSON = try mutateJSON(
            fixtureData("scripture-ask-answered.ast.json")
        ) {
            var blocks = try requireArray($0["blocks"])
            var heading = try requireDictionary(blocks[0])
            heading["id"] = "1-illegal"
            blocks[0] = heading
            $0["blocks"] = blocks
        }
        #expect(
            transportValidationError(
                documentJSON: illegalBlockIDJSON,
                manifestJSON: answeredManifest,
                context: .scriptureAsk
            ) == .diagnostics([schemaDiagnostic()])
        )

        let additionalPropertyJSON = try mutateJSON(
            fixtureData("scripture-ask-answered.ast.json")
        ) {
            $0["unexpected"] = true
        }
        #expect(
            transportValidationError(
                documentJSON: additionalPropertyJSON,
                manifestJSON: answeredManifest,
                context: .scriptureAsk
            ) == .diagnostics([schemaDiagnostic()])
        )
    }

    @Test
    func enforcesPortableScriptureReleaseAndSpanSemanticsBeforeProjection() throws {
        let missingRelease = try mutatedDocument("scripture-ask-answered.ast.json") {
            try mutateFirstEvidence(in: &$0) {
                var props = try requireDictionary($0["props"])
                props["source"] = "missing-scripture-release"
                $0["props"] = props
            }
        }
        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: missingRelease,
                context: .scriptureAsk
            ) == [
                RelayMarkDiagnostic(
                    level: "error",
                    code: "relaymark.scripture.source_resolution",
                    message: "relay.evidence_ref scripture source 'missing-scripture-release' must resolve to exactly one scripture resource."
                )
            ]
        )

        let invalidRelease = try mutatedDocument("scripture-ask-answered.ast.json") {
            try mutateFirstResource(in: &$0) {
                var props = try requireDictionary($0["props"])
                var source = try requireDictionary(props["source"])
                var provenance = try requireDictionary(props["provenance"])
                props["profile"] = "relaymark.scripture_release.v2"
                source["digest"] = "SHA256:not-canonical"
                provenance["coordinate_inventory_digest"] = "not-a-digest"
                props["source"] = source
                props["provenance"] = provenance
                $0["props"] = props
                $0["scope"] = "invalid"
            }
        }
        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: invalidRelease,
                context: .scriptureAsk
            ).map(\.code) == [
                "relaymark.scripture.release_profile",
                "relaymark.scripture.digest",
                "relaymark.scripture.digest",
                "relaymark.scripture.release_scope",
                "relaymark.scripture.scope"
            ]
        )

        let invalidEvidence = try mutatedDocument("scripture-ask-answered.ast.json") {
            try mutateFirstResource(in: &$0) {
                $0["scope"] = "org"
            }
            try mutateFirstEvidence(in: &$0) {
                var props = try requireDictionary($0["props"])
                var selector = try requireDictionary(props["selector"])
                var end = try requireDictionary(selector["end"])
                props["source_revision"] = "stale-release"
                end["book_id"] = "ROM"
                selector["end"] = end
                selector["content_digest"] = "not-a-digest"
                props["selector"] = selector
                $0["props"] = props
            }
        }
        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: invalidEvidence,
                context: .scriptureAsk
            ).map(\.code) == [
                "relaymark.scripture.source_revision",
                "relaymark.scripture.scope",
                "relaymark.scripture.span_boundary",
                "relaymark.scripture.content_digest"
            ]
        )

        let invalidSelector = try mutatedDocument("scripture-ask-answered.ast.json") {
            try mutateFirstEvidence(in: &$0) {
                var props = try requireDictionary($0["props"])
                var selector = try requireDictionary(props["selector"])
                var start = try requireDictionary(selector["start"])
                selector["profile"] = "relaymark.scripture_span.v2"
                start["chapter"] = 0
                selector["start"] = start
                props["selector"] = selector
                $0["props"] = props
            }
        }
        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: invalidSelector,
                context: .scriptureAsk
            ).map(\.code) == [
                "relaymark.scripture.selector_profile",
                "relaymark.scripture.coordinate"
            ]
        )
    }

    @Test
    func preservesDepthFirstClaimAndScriptureDiagnosticOrder() throws {
        let document = try mutatedDocument("scripture-ask-answered.ast.json") {
            var blocks = try requireArray($0["blocks"])
            var claim = try requireDictionary(blocks[1])
            var claimProps = try requireDictionary(claim["props"])
            claimProps["confidence"] = 2
            claim["props"] = claimProps
            blocks[1] = claim
            $0["blocks"] = blocks

            try mutateFirstEvidence(in: &$0) {
                var evidenceProps = try requireDictionary($0["props"])
                evidenceProps["source_revision"] = "stale-release"
                $0["props"] = evidenceProps
            }
        }

        #expect(
            RelayMarkAgentAnswerValidator.diagnostics(
                for: document,
                context: .scriptureAsk
            ) == [
                RelayMarkDiagnostic(
                    level: "error",
                    code: "relaymark.claim.confidence_range",
                    message: "relay.claim.confidence must be between 0.0 and 1.0."
                ),
                RelayMarkDiagnostic(
                    level: "error",
                    code: "relaymark.scripture.source_revision",
                    message: "relay.evidence_ref.source_revision must equal the scripture resource corpus_release_id."
                )
            ]
        )
    }

    @Test
    func validatesSchemaBeforeTypedDecodeProfileAndSemantics() throws {
        let document = try fixtureData("scripture-ask-answered.ast.json")
        let manifest = try fixtureData("scripture-ask-answered.manifest.json")
        let expectedSchemaError = RelayMarkAgentAnswerValidationError.diagnostics([
            schemaDiagnostic()
        ])
        let expectedProfileDiagnostic = RelayMarkDiagnostic(
            level: "error",
            code: "relaymark.agent_answer.profile",
            message: "Transported Agent Answer document must declare frontmatter.profile relaymark.agent_answer.v1."
        )

        let missingTypeAndProfile = try mutateJSON(document) {
            $0.removeValue(forKey: "type")
            var frontmatter = try requireDictionary($0["frontmatter"])
            frontmatter.removeValue(forKey: "profile")
            $0["frontmatter"] = frontmatter
        }
        #expect(
            transportValidationError(
                documentJSON: missingTypeAndProfile,
                manifestJSON: manifest,
                context: .scriptureAsk
            ) == expectedSchemaError
        )

        let illegalIDAndWrongProfile = try mutateJSON(document) {
            var frontmatter = try requireDictionary($0["frontmatter"])
            frontmatter["profile"] = "relaymark.agent_answer.v2"
            $0["frontmatter"] = frontmatter
            var blocks = try requireArray($0["blocks"])
            var heading = try requireDictionary(blocks[0])
            heading["id"] = "1-illegal"
            blocks[0] = heading
            $0["blocks"] = blocks
        }
        #expect(
            transportValidationError(
                documentJSON: illegalIDAndWrongProfile,
                manifestJSON: manifest,
                context: .scriptureAsk
            ) == expectedSchemaError
        )

        let emptyEvidenceReference = try mutateJSON(document) {
            var blocks = try requireArray($0["blocks"])
            var claim = try requireDictionary(blocks[1])
            claim["evidence_refs"] = [""]
            blocks[1] = claim
            $0["blocks"] = blocks
        }
        #expect(
            transportValidationError(
                documentJSON: emptyEvidenceReference,
                manifestJSON: manifest,
                context: .scriptureAsk
            ) == expectedSchemaError
        )

        let numericScriptureEvidenceLabel = try mutateJSON(document) {
            try mutateFirstEvidence(in: &$0) {
                var props = try requireDictionary($0["props"])
                props["label"] = 123
                $0["props"] = props
            }
        }
        #expect(
            transportValidationError(
                documentJSON: numericScriptureEvidenceLabel,
                manifestJSON: manifest,
                context: .scriptureAsk
            ) == expectedSchemaError
        )

        for profile in [nil, "relaymark.agent_answer.v2"] as [String?] {
            let schemaValidDocument = try mutateJSON(document) {
                var frontmatter = try requireDictionary($0["frontmatter"])
                frontmatter["profile"] = profile
                $0["frontmatter"] = frontmatter
            }
            let result = try RelayMarkAgentAnswerValidator.validateTransport(
                documentJSON: schemaValidDocument,
                manifestJSON: manifest,
                context: .scriptureAsk
            )

            #expect(result.projection == nil)
            #expect(result.diagnostics == [expectedProfileDiagnostic])
        }
    }

    @Test
    func enforcesStrictPortableUTF8AndJSONAtTheTransportBoundary() throws {
        let refusedDocument = try fixtureData("scripture-ask-refused.ast.json")
        let refusedManifest = try fixtureData("scripture-ask-refused.manifest.json")
        let titleField = Data(#""title": "Answer unavailable""#.utf8)
        let invalidUTF8 = try replacingFirst(
            in: refusedDocument,
            target: titleField,
            replacement: Data(#""title": """#.utf8) + Data([0x80]) + Data(#""""#.utf8)
        )
        let rawControlCharacter = try replacingFirst(
            in: refusedDocument,
            target: titleField,
            replacement: Data("\"title\": \"Bad\nTitle\"".utf8)
        )
        let loneEscapedSurrogate = try replacingFirst(
            in: refusedDocument,
            target: titleField,
            replacement: Data(#""title": "\uD800""#.utf8)
        )

        for invalidDocument in [invalidUTF8, rawControlCharacter, loneEscapedSurrogate] {
            #expect(throws: (any Error).self) {
                try RelayMarkAgentAnswerValidator.validateTransport(
                    documentJSON: invalidDocument,
                    manifestJSON: refusedManifest,
                    context: .scriptureAsk
                )
            }
        }

        let escapedSurrogatePair = try replacingFirst(
            in: refusedDocument,
            target: titleField,
            replacement: Data(#""title": "\uD83D\uDE00""#.utf8)
        )
        let accepted = try RelayMarkAgentAnswerValidator.validateTransport(
            documentJSON: escapedSurrogatePair,
            manifestJSON: refusedManifest,
            context: .scriptureAsk
        )
        #expect(accepted.isValid)
        #expect(accepted.projection?.title == "😀")
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

    private func replacingFirst(
        in data: Data,
        target: Data,
        replacement: Data
    ) throws -> Data {
        let range = try #require(data.range(of: target))
        var result = data
        result.replaceSubrange(range, with: replacement)
        return result
    }

    private func requireDictionary(_ value: Any?) throws -> [String: Any] {
        try #require(value as? [String: Any])
    }

    private func requireArray(_ value: Any?) throws -> [Any] {
        try #require(value as? [Any])
    }

    private func mutateFirstResource(
        in document: inout [String: Any],
        mutate: (inout [String: Any]) throws -> Void
    ) throws {
        var resources = try requireArray(document["resources"])
        var resource = try requireDictionary(resources[0])
        try mutate(&resource)
        resources[0] = resource
        document["resources"] = resources
    }

    private func mutateFirstEvidence(
        in document: inout [String: Any],
        mutate: (inout [String: Any]) throws -> Void
    ) throws {
        var blocks = try requireArray(document["blocks"])
        var sourceBundle = try requireDictionary(blocks[3])
        var content = try requireArray(sourceBundle["content"])
        var evidence = try requireDictionary(content[0])
        try mutate(&evidence)
        content[0] = evidence
        sourceBundle["content"] = content
        blocks[3] = sourceBundle
        document["blocks"] = blocks
    }

    private func receiptData(_ path: String, relativeTo receiptURL: URL) throws -> Data {
        try Data(
            contentsOf: receiptURL
                .deletingLastPathComponent()
                .appendingPathComponent(path)
                .standardizedFileURL
        )
    }

    private func transportValidationError(
        documentJSON: Data,
        manifestJSON: Data,
        context: RelayMarkAgentAnswerValidationContext
    ) -> RelayMarkAgentAnswerValidationError? {
        do {
            _ = try RelayMarkAgentAnswerValidator.validateTransport(
                documentJSON: documentJSON,
                manifestJSON: manifestJSON,
                context: context
            )
            return nil
        } catch let error as RelayMarkAgentAnswerValidationError {
            return error
        } catch {
            return nil
        }
    }

    private func schemaDiagnostic() -> RelayMarkDiagnostic {
        RelayMarkDiagnostic(
            level: "error",
            code: "relaymark.schema.invalid",
            message: "Document does not conform to the RelayMark document schema."
        )
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
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
