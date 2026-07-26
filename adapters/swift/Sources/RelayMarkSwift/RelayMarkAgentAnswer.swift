import CryptoKit
import Foundation

public enum RelayMarkAgentAnswerOutcome: String, Codable, Equatable, Sendable {
    case answered
    case refused
}

public enum RelayMarkAgentAnswerValidationContext: String, Codable, Equatable, Sendable {
    case generic
    case scriptureAsk = "scripture_ask"
}

public struct RelayMarkAgentAnswerProjection: Equatable, Sendable {
    public let title: String
    public let scope: String
    public let question: String
    public let questionID: String
    public let outcome: RelayMarkAgentAnswerOutcome
    public let document: RelayMarkDocument
    public let manifest: RelayMarkManifest

    public init(
        title: String,
        scope: String,
        question: String,
        questionID: String,
        outcome: RelayMarkAgentAnswerOutcome,
        document: RelayMarkDocument,
        manifest: RelayMarkManifest
    ) {
        self.title = title
        self.scope = scope
        self.question = question
        self.questionID = questionID
        self.outcome = outcome
        self.document = document
        self.manifest = manifest
    }
}

public struct RelayMarkAgentAnswerTransport: Equatable, Sendable {
    public let document: RelayMarkDocument
    public let manifest: RelayMarkManifest
    public let documentSHA256: String
    public let manifestSHA256: String
    public let diagnostics: [RelayMarkDiagnostic]
    public let projection: RelayMarkAgentAnswerProjection?

    public var isValid: Bool {
        diagnostics.isEmpty && projection != nil
    }

    public init(
        document: RelayMarkDocument,
        manifest: RelayMarkManifest,
        documentSHA256: String,
        manifestSHA256: String,
        diagnostics: [RelayMarkDiagnostic],
        projection: RelayMarkAgentAnswerProjection?
    ) {
        self.document = document
        self.manifest = manifest
        self.documentSHA256 = documentSHA256
        self.manifestSHA256 = manifestSHA256
        self.diagnostics = diagnostics
        self.projection = projection
    }

    public func requireProjection() throws -> RelayMarkAgentAnswerProjection {
        guard let projection, diagnostics.isEmpty else {
            throw RelayMarkAgentAnswerValidationError.diagnostics(diagnostics)
        }

        return projection
    }
}

public enum RelayMarkAgentAnswerValidationError: Error, Equatable, Sendable {
    case diagnostics([RelayMarkDiagnostic])
    case invalidProjection
}

public enum RelayMarkAgentAnswerValidator {
    private static let profile = "relaymark.agent_answer.v1"
    private static let canonicalScopes = ["private", "org", "unlisted", "public"]

    public static func diagnostics(
        for document: RelayMarkDocument,
        context: RelayMarkAgentAnswerValidationContext = .generic
    ) -> [RelayMarkDiagnostic] {
        guard document.frontmatter["profile"]?.stringValue == profile else {
            return [
                diagnostic(
                    "relaymark.agent_answer.profile",
                    "Transported Agent Answer document must declare frontmatter.profile relaymark.agent_answer.v1."
                )
            ]
        }

        var diagnostics = canonicalDocumentDiagnostics(for: document)
        diagnostics.append(contentsOf: profileDiagnostics(for: document, context: context))
        diagnostics.append(contentsOf: duplicateEvidenceIdentityDiagnostics(for: document))
        return diagnostics
    }

    public static func project(
        document: RelayMarkDocument,
        manifest: RelayMarkManifest,
        context: RelayMarkAgentAnswerValidationContext = .generic
    ) throws -> RelayMarkAgentAnswerProjection {
        let diagnostics = diagnostics(for: document, context: context)

        guard diagnostics.isEmpty else {
            throw RelayMarkAgentAnswerValidationError.diagnostics(diagnostics)
        }

        let canonicalManifest = try canonicalManifest(for: document, diagnostics: [])

        guard canonicalManifest == manifest else {
            throw RelayMarkAgentAnswerValidationError.diagnostics([
                manifestMismatchDiagnostic()
            ])
        }

        return try makeProjection(document: document, manifest: canonicalManifest)
    }

    public static func validateTransport(
        documentJSON: Data,
        manifestJSON: Data,
        context: RelayMarkAgentAnswerValidationContext = .generic
    ) throws -> RelayMarkAgentAnswerTransport {
        let document = try RelayMarkDocument.decodeJSON(documentJSON)
        let manifest = try RelayMarkManifest.decodeJSON(manifestJSON)
        let diagnostics = diagnostics(for: document, context: context)
        let documentSHA256 = "sha256:\(sha256Hex(documentJSON))"
        let manifestSHA256 = "sha256:\(sha256Hex(manifestJSON))"

        guard diagnostics.isEmpty else {
            return RelayMarkAgentAnswerTransport(
                document: document,
                manifest: manifest,
                documentSHA256: documentSHA256,
                manifestSHA256: manifestSHA256,
                diagnostics: diagnostics,
                projection: nil
            )
        }

        let canonicalManifest = try canonicalManifest(for: document, diagnostics: [])
        let encoder = JSONEncoder()
        let canonicalManifestJSON = try encoder.encode(canonicalManifest)
        let transportedValue = try RelayMarkDecoder.decode(RelayMarkValue.self, from: manifestJSON)
        let canonicalValue = try RelayMarkDecoder.decode(RelayMarkValue.self, from: canonicalManifestJSON)

        guard canonicalManifest == manifest, canonicalValue == transportedValue else {
            return RelayMarkAgentAnswerTransport(
                document: document,
                manifest: manifest,
                documentSHA256: documentSHA256,
                manifestSHA256: manifestSHA256,
                diagnostics: [manifestMismatchDiagnostic()],
                projection: nil
            )
        }

        return RelayMarkAgentAnswerTransport(
            document: document,
            manifest: manifest,
            documentSHA256: documentSHA256,
            manifestSHA256: manifestSHA256,
            diagnostics: [],
            projection: try makeProjection(document: document, manifest: canonicalManifest)
        )
    }

    private static func makeProjection(
        document: RelayMarkDocument,
        manifest: RelayMarkManifest
    ) throws -> RelayMarkAgentAnswerProjection {
        guard
            let title = document.frontmatter["title"]?.stringValue,
            let scope = document.frontmatter["scope"]?.stringValue,
            let question = document.frontmatter["question"]?.stringValue,
            let questionID = document.frontmatter["question_id"]?.stringValue,
            let outcomeValue = document.frontmatter["outcome"]?.stringValue,
            let outcome = RelayMarkAgentAnswerOutcome(rawValue: outcomeValue)
        else {
            throw RelayMarkAgentAnswerValidationError.invalidProjection
        }

        return RelayMarkAgentAnswerProjection(
            title: title,
            scope: scope,
            question: question,
            questionID: questionID,
            outcome: outcome,
            document: document,
            manifest: manifest
        )
    }

    private static func canonicalDocumentDiagnostics(
        for document: RelayMarkDocument
    ) -> [RelayMarkDiagnostic] {
        var diagnostics: [RelayMarkDiagnostic] = []

        if document.type != "relaymark.document" {
            diagnostics.append(
                diagnostic(
                    "relaymark.document.type",
                    "Document type must be relaymark.document."
                )
            )
        }

        if document.version < 1 {
            diagnostics.append(
                diagnostic(
                    "relaymark.document.version",
                    "Document version must be a positive integer."
                )
            )
        }

        diagnostics.append(contentsOf: scriptureResourceDiagnostics(for: document))

        let scriptureResources = scriptureResourcesByID(in: document)
        let evidenceTargets = evidenceTargets(in: document)
        var seenBlockIDs = Set<String>()

        visitBlocks(document.blocks) { block in
            if block.id.isEmpty {
                diagnostics.append(
                    diagnostic(
                        "relaymark.block.id",
                        "Every block must have an id."
                    )
                )
            } else if !seenBlockIDs.insert(block.id).inserted {
                diagnostics.append(
                    diagnostic(
                        "relaymark.block.duplicate_id",
                        "Duplicate block id '\(block.id)'."
                    )
                )
            }

            if block.type.isEmpty {
                diagnostics.append(
                    diagnostic(
                        "relaymark.block.type",
                        "Block '\(block.id.isEmpty ? "unknown" : block.id)' must have a type."
                    )
                )
            }

            if block.type == "relay.claim" {
                diagnostics.append(
                    contentsOf: claimDiagnostics(
                        for: block,
                        evidenceTargets: evidenceTargets
                    )
                )
            } else if block.type == "relay.evidence_ref" {
                diagnostics.append(
                    contentsOf: evidenceReferenceDiagnostics(
                        for: block,
                        scriptureResources: scriptureResources
                    )
                )
            }
        }

        return diagnostics
    }

    private static func scriptureResourceDiagnostics(
        for document: RelayMarkDocument
    ) -> [RelayMarkDiagnostic] {
        var diagnostics: [RelayMarkDiagnostic] = []

        for resource in document.resources where resource.type == "scripture" {
            let props = resource.props
            let resourceID = resource.id.isEmpty ? "unknown" : resource.id

            for field in [
                "profile",
                "translation_id",
                "edition_id",
                "corpus_release_id",
                "versification_id",
                "attribution"
            ] where !isNonEmptyString(props[field]?.stringValue) {
                diagnostics.append(
                    diagnostic(
                        "relaymark.scripture.release",
                        "scripture resource '\(resourceID)' requires \(field)."
                    )
                )
            }

            if props["profile"]?.stringValue != "relaymark.scripture_release.v1" {
                diagnostics.append(
                    diagnostic(
                        "relaymark.scripture.release_profile",
                        "scripture resource '\(resourceID)' must use relaymark.scripture_release.v1."
                    )
                )
            }

            diagnostics.append(
                contentsOf: requiredStringObjectDiagnostics(
                    props["source"]?.objectValue,
                    fields: ["name", "uri", "digest"],
                    label: "source",
                    resourceID: resourceID
                )
            )
            diagnostics.append(
                contentsOf: requiredStringObjectDiagnostics(
                    props["license"]?.objectValue,
                    fields: ["id", "name", "url"],
                    label: "license",
                    resourceID: resourceID
                )
            )
            diagnostics.append(
                contentsOf: requiredStringObjectDiagnostics(
                    props["provenance"]?.objectValue,
                    fields: [
                        "coordinate_inventory_digest",
                        "normalized_index_input_digest"
                    ],
                    label: "provenance",
                    resourceID: resourceID
                )
            )

            let source = props["source"]?.objectValue
            let provenance = props["provenance"]?.objectValue

            diagnostics.append(
                contentsOf: scriptureDigestDiagnostics(
                    source?["digest"]?.stringValue,
                    field: "source.digest",
                    resourceID: resourceID
                )
            )
            diagnostics.append(
                contentsOf: scriptureDigestDiagnostics(
                    provenance?["coordinate_inventory_digest"]?.stringValue,
                    field: "provenance.coordinate_inventory_digest",
                    resourceID: resourceID
                )
            )
            diagnostics.append(
                contentsOf: scriptureDigestDiagnostics(
                    provenance?["normalized_index_input_digest"]?.stringValue,
                    field: "provenance.normalized_index_input_digest",
                    resourceID: resourceID
                )
            )

            if let sourceArchiveDigest = provenance?["source_archive_digest"] {
                diagnostics.append(
                    contentsOf: scriptureDigestDiagnostics(
                        sourceArchiveDigest.stringValue,
                        field: "provenance.source_archive_digest",
                        resourceID: resourceID
                    )
                )
            }

            if !canonicalScopes.contains(resource.scope ?? "") {
                diagnostics.append(
                    diagnostic(
                        "relaymark.scripture.release_scope",
                        "scripture resource '\(resourceID)' requires an explicit valid scope."
                    )
                )
            }
        }

        return diagnostics
    }

    private static func requiredStringObjectDiagnostics(
        _ object: [String: RelayMarkValue]?,
        fields: [String],
        label: String,
        resourceID: String
    ) -> [RelayMarkDiagnostic] {
        guard let object else {
            return [
                diagnostic(
                    "relaymark.scripture.release",
                    "scripture resource '\(resourceID)' requires a \(label) object."
                )
            ]
        }

        return fields.compactMap { field in
            guard !isNonEmptyString(object[field]?.stringValue) else {
                return nil
            }

            return diagnostic(
                "relaymark.scripture.release",
                "scripture resource '\(resourceID)' requires \(label).\(field)."
            )
        }
    }

    private static func scriptureDigestDiagnostics(
        _ value: String?,
        field: String,
        resourceID: String
    ) -> [RelayMarkDiagnostic] {
        guard isSHA256Digest(value) else {
            return [
                diagnostic(
                    "relaymark.scripture.digest",
                    "scripture resource '\(resourceID)' requires \(field) as a lowercase sha256 digest."
                )
            ]
        }

        return []
    }

    private static func scriptureResourcesByID(
        in document: RelayMarkDocument
    ) -> [String: [RelayMarkResource]] {
        var resources: [String: [RelayMarkResource]] = [:]

        for resource in document.resources
        where resource.type == "scripture" && isNonEmptyString(resource.id) {
            resources[resource.id, default: []].append(resource)
        }

        return resources
    }

    private static func evidenceReferenceDiagnostics(
        for block: RelayMarkBlock,
        scriptureResources: [String: [RelayMarkResource]]
    ) -> [RelayMarkDiagnostic] {
        let props = block.props
        var diagnostics: [RelayMarkDiagnostic] = []

        if
            !isNonEmptyString(props["id"]?.stringValue) ||
            !isNonEmptyString(props["source"]?.stringValue)
        {
            diagnostics.append(
                diagnostic(
                    "relaymark.evidence.identity",
                    "relay.evidence_ref requires non-empty id and source values."
                )
            )
        }

        for field in ["source_type", "source_revision"]
        where props[field] != nil && !isNonEmptyString(props[field]?.stringValue) {
            diagnostics.append(
                diagnostic(
                    "relaymark.evidence.source",
                    "relay.evidence_ref.\(field) must be a non-empty string when present."
                )
            )
        }

        guard props["source_type"]?.stringValue == "scripture" else {
            return diagnostics
        }

        diagnostics.append(
            contentsOf: scriptureEvidenceDiagnostics(
                for: block,
                scriptureResources: scriptureResources
            )
        )
        return diagnostics
    }

    private static func scriptureEvidenceDiagnostics(
        for block: RelayMarkBlock,
        scriptureResources: [String: [RelayMarkResource]]
    ) -> [RelayMarkDiagnostic] {
        let props = block.props
        let sourceID = props["source"]?.stringValue ?? ""
        let matches = scriptureResources[sourceID] ?? []

        guard matches.count == 1, let resource = matches.first else {
            return [
                diagnostic(
                    "relaymark.scripture.source_resolution",
                    "relay.evidence_ref scripture source '\(sourceID)' must resolve to exactly one scripture resource."
                )
            ]
        }

        var diagnostics: [RelayMarkDiagnostic] = []
        let release = resource.props

        if props["source_revision"]?.stringValue != release["corpus_release_id"]?.stringValue {
            diagnostics.append(
                diagnostic(
                    "relaymark.scripture.source_revision",
                    "relay.evidence_ref.source_revision must equal the scripture resource corpus_release_id."
                )
            )
        }

        if !scopeAllows(resourceScope: resource.scope, evidenceScope: props["scope"]?.stringValue) {
            diagnostics.append(
                diagnostic(
                    "relaymark.scripture.scope",
                    "relay.evidence_ref scope must not be broader than its scripture resource scope."
                )
            )
        }

        guard let selector = props["selector"]?.objectValue else {
            diagnostics.append(
                diagnostic(
                    "relaymark.scripture.selector",
                    "Scripture evidence requires a scripture span selector."
                )
            )
            return diagnostics
        }

        if selector["profile"]?.stringValue != "relaymark.scripture_span.v1" {
            diagnostics.append(
                diagnostic(
                    "relaymark.scripture.selector_profile",
                    "Scripture evidence selector must use relaymark.scripture_span.v1."
                )
            )
        }

        let start = scriptureCoordinate(
            selector["start"]?.objectValue,
            endpoint: "start",
            diagnostics: &diagnostics
        )
        let end = scriptureCoordinate(
            selector["end"]?.objectValue,
            endpoint: "end",
            diagnostics: &diagnostics
        )

        if
            let start,
            let end,
            start.bookID != end.bookID || start.kind != end.kind
        {
            diagnostics.append(
                diagnostic(
                    "relaymark.scripture.span_boundary",
                    "Scripture span start and end must use the same book and coordinate kind."
                )
            )
        }

        if !isSHA256Digest(selector["content_digest"]?.stringValue) {
            diagnostics.append(
                diagnostic(
                    "relaymark.scripture.content_digest",
                    "Scripture evidence requires a lowercase sha256 content_digest."
                )
            )
        }

        if !isNonEmptyString(validationPlainText(block)) {
            diagnostics.append(
                diagnostic(
                    "relaymark.scripture.excerpt",
                    "Scripture evidence requires a non-empty exact excerpt."
                )
            )
        }

        return diagnostics
    }

    private struct ValidatedScriptureCoordinate {
        let bookID: String
        let kind: String
    }

    private static func scriptureCoordinate(
        _ coordinate: [String: RelayMarkValue]?,
        endpoint: String,
        diagnostics: inout [RelayMarkDiagnostic]
    ) -> ValidatedScriptureCoordinate? {
        guard let coordinate else {
            diagnostics.append(
                diagnostic(
                    "relaymark.scripture.coordinate",
                    "Scripture selector \(endpoint) must be a coordinate object."
                )
            )
            return nil
        }

        let bookID = coordinate["book_id"]?.stringValue
        let verseLabel = coordinate["verse_label"]?.stringValue
        let kind = coordinate["coordinate_kind"]?.stringValue
        let commonValid = isNonEmptyString(bookID) && isNonEmptyString(verseLabel)
        let shapeValid: Bool

        switch kind {
        case "chapter":
            shapeValid =
                integerValue(coordinate["chapter"]).map { $0 > 0 } == true &&
                coordinate["section_id"] == nil
        case "section":
            shapeValid =
                isNonEmptyString(coordinate["section_id"]?.stringValue) &&
                coordinate["chapter"] == nil
        default:
            shapeValid = false
        }

        guard commonValid, shapeValid, let bookID, let kind else {
            diagnostics.append(
                diagnostic(
                    "relaymark.scripture.coordinate",
                    "Scripture selector \(endpoint) must be a lossless chapter or section coordinate with a string verse_label."
                )
            )
            return nil
        }

        return ValidatedScriptureCoordinate(bookID: bookID, kind: kind)
    }

    private static func scopeAllows(
        resourceScope: String?,
        evidenceScope: String?
    ) -> Bool {
        let ranks = [
            "private": 0,
            "org": 1,
            "unlisted": 2,
            "public": 3
        ]

        guard
            let resourceScope,
            let evidenceScope,
            let resourceRank = ranks[resourceScope],
            let evidenceRank = ranks[evidenceScope]
        else {
            return false
        }

        return evidenceRank <= resourceRank
    }

    private static func isSHA256Digest(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        let bytes = Array(value.utf8)
        guard
            bytes.count == 71,
            bytes.starts(with: Array("sha256:".utf8))
        else {
            return false
        }

        return bytes.dropFirst(7).allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func claimDiagnostics(
        for block: RelayMarkBlock,
        evidenceTargets: Set<String>
    ) -> [RelayMarkDiagnostic] {
        var diagnostics: [RelayMarkDiagnostic] = []

        let references = evidenceReferences(for: block)

        if !references.contains(where: isNonEmptyString) {
            diagnostics.append(
                diagnostic(
                    "relaymark.policy.evidence_required",
                    "relay.claim requires at least one evidence reference."
                )
            )
        }

        for reference in references {
            guard isNonEmptyString(reference) else {
                diagnostics.append(
                    diagnostic(
                        "relaymark.evidence.invalid_reference",
                        "relay.claim evidence references must be non-empty strings."
                    )
                )
                continue
            }

            if !evidenceTargets.contains(reference) {
                diagnostics.append(
                    diagnostic(
                        "relaymark.evidence.unresolved_reference",
                        "relay.claim evidence reference '\(reference)' does not resolve."
                    )
                )
            }
        }

        if
            let confidence = block.props["confidence"]?.numberValue,
            !confidence.isFinite || confidence < 0 || confidence > 1
        {
            diagnostics.append(
                diagnostic(
                    "relaymark.claim.confidence_range",
                    "relay.claim.confidence must be between 0.0 and 1.0."
                )
            )
        }

        return diagnostics
    }

    private static func profileDiagnostics(
        for document: RelayMarkDocument,
        context: RelayMarkAgentAnswerValidationContext
    ) -> [RelayMarkDiagnostic] {
        let frontmatter = document.frontmatter
        var diagnostics: [RelayMarkDiagnostic] = []

        if !isNonEmptyString(frontmatter["title"]?.stringValue) {
            diagnostics.append(
                diagnostic(
                    "relaymark.agent_answer.title",
                    "relaymark.agent_answer.v1 requires a non-empty title."
                )
            )
        }

        if
            frontmatter["scope"]?.stringValue.map({ canonicalScopes.contains($0) }) != true
        {
            diagnostics.append(
                diagnostic(
                    "relaymark.agent_answer.scope",
                    "relaymark.agent_answer.v1 requires an explicit private, org, unlisted, or public scope."
                )
            )
        }

        if let question = frontmatter["question"]?.stringValue, isNonEmptyString(question) {
            let expectedQuestionID = "sha256:\(sha256Hex(Data(question.utf8)))"

            if frontmatter["question_id"]?.stringValue != expectedQuestionID {
                diagnostics.append(
                    diagnostic(
                        "relaymark.agent_answer.question_id",
                        "relaymark.agent_answer.v1 question_id must be the lowercase SHA-256 digest of the exact question UTF-8 bytes."
                    )
                )
            }
        } else {
            diagnostics.append(
                diagnostic(
                    "relaymark.agent_answer.question",
                    "relaymark.agent_answer.v1 requires a non-empty exact question."
                )
            )
        }

        guard
            let outcomeValue = frontmatter["outcome"]?.stringValue,
            let outcome = RelayMarkAgentAnswerOutcome(rawValue: outcomeValue)
        else {
            diagnostics.append(
                diagnostic(
                    "relaymark.agent_answer.outcome",
                    "relaymark.agent_answer.v1 outcome must be answered or refused."
                )
            )
            return diagnostics
        }

        switch outcome {
        case .answered:
            diagnostics.append(contentsOf: answeredDiagnostics(for: document, context: context))
        case .refused:
            diagnostics.append(contentsOf: refusedDiagnostics(for: document))
        }

        return diagnostics
    }

    private static func answeredDiagnostics(
        for document: RelayMarkDocument,
        context: RelayMarkAgentAnswerValidationContext
    ) -> [RelayMarkDiagnostic] {
        let blocks = document.blocks
        let evidenceHeadingIndex = blocks.firstIndex {
            headingLevel($0) == 2 && validationPlainText($0) == "Evidence"
        }
        let claims: [RelayMarkBlock]
        let sourceBundles: [RelayMarkBlock]

        if let evidenceHeadingIndex, evidenceHeadingIndex > 1 {
            claims = Array(blocks[1..<evidenceHeadingIndex])
        } else {
            claims = []
        }

        if let evidenceHeadingIndex {
            sourceBundles = Array(blocks.dropFirst(evidenceHeadingIndex + 1))
        } else {
            sourceBundles = []
        }

        var levelOneHeadingCount = 0
        var levelTwoHeadingCount = 0

        visitBlocks(blocks) { block in
            if headingLevel(block) == 1 { levelOneHeadingCount += 1 }
            if headingLevel(block) == 2 { levelTwoHeadingCount += 1 }
        }

        let structureValid =
            blocks.count >= 4 &&
            blocks.first.map(headingLevel) == 1 &&
            levelOneHeadingCount == 1 &&
            levelTwoHeadingCount == 1 &&
            !claims.isEmpty &&
            claims.allSatisfy { $0.type == "relay.claim" } &&
            !sourceBundles.isEmpty &&
            sourceBundles.allSatisfy { $0.type == "relay.source_bundle" }

        var diagnostics: [RelayMarkDiagnostic] = []

        if !structureValid {
            diagnostics.append(
                diagnostic(
                    "relaymark.agent_answer.answered_structure",
                    "An answered relaymark.agent_answer.v1 paper requires one level-one heading, supported claims, an Evidence level-two heading, and source bundles in that order."
                )
            )
        }

        var evidenceCounts: [String: Int] = [:]
        var concreteEvidenceByID: [String: [RelayMarkBlock]] = [:]

        for sourceBundle in sourceBundles where sourceBundle.type == "relay.source_bundle" {
            visitBlocks([sourceBundle]) { block in
                guard
                    block.type == "relay.evidence_ref",
                    let evidenceID = block.props["id"]?.stringValue,
                    isNonEmptyString(evidenceID)
                else {
                    return
                }

                evidenceCounts[evidenceID, default: 0] += 1
                concreteEvidenceByID[evidenceID, default: []].append(block)
            }
        }

        let answerClaims = claims.filter { $0.type == "relay.claim" }

        for claim in answerClaims {
            let references = evidenceReferences(for: claim)

            if
                !isNonEmptyString(claim.props["key"]?.stringValue) ||
                claim.props["status"]?.stringValue != "supported" ||
                !isNonEmptyString(validationPlainText(claim))
            {
                diagnostics.append(
                    diagnostic(
                        "relaymark.agent_answer.claim",
                        "Answered claim '\(claim.id.isEmpty ? "unknown" : claim.id)' requires a non-empty key and text with supported status."
                    )
                )
            }

            if
                references.isEmpty ||
                Set(references).count != references.count ||
                references.contains(where: {
                    !isNonEmptyString($0) || evidenceCounts[$0] != 1
                })
            {
                diagnostics.append(
                    diagnostic(
                        "relaymark.agent_answer.claim_evidence",
                        "Answered claim '\(claim.id.isEmpty ? "unknown" : claim.id)' must cite one or more unique concrete evidence refs that each resolve exactly once inside the paper's source bundles."
                    )
                )
            }
        }

        if context == .scriptureAsk {
            let invalidScriptureEvidence = answerClaims
                .flatMap(evidenceReferences)
                .contains { reference in
                    guard
                        concreteEvidenceByID[reference]?.count == 1,
                        let block = concreteEvidenceByID[reference]?.first
                    else {
                        return true
                    }

                    return block.props["source_type"]?.stringValue != "scripture"
                }

            if invalidScriptureEvidence {
                diagnostics.append(
                    diagnostic(
                        "relaymark.agent_answer.scripture_evidence",
                        "A Scripture Ask host context requires every answered claim evidence ref to resolve to relay.evidence_ref source_type scripture."
                    )
                )
            }
        }

        var containsForbiddenBlock = false

        visitBlocks(blocks) { block in
            if block.type == "relay.agent_suggestion" || block.type == "relay.action_row" {
                containsForbiddenBlock = true
            }
        }

        if containsForbiddenBlock {
            diagnostics.append(
                diagnostic(
                    "relaymark.agent_answer.read_only",
                    "An answered relaymark.agent_answer.v1 paper must not contain agent suggestions or action rows."
                )
            )
        }

        if document.frontmatter["refusal_reason"] != nil {
            diagnostics.append(
                diagnostic(
                    "relaymark.agent_answer.refusal_reason",
                    "An answered relaymark.agent_answer.v1 paper must not contain refusal_reason."
                )
            )
        }

        return diagnostics
    }

    private static func refusedDiagnostics(
        for document: RelayMarkDocument
    ) -> [RelayMarkDiagnostic] {
        let blocks = document.blocks
        var nestedBlockCount = 0
        var levelOneHeadingCount = 0

        visitBlocks(blocks) { block in
            nestedBlockCount += 1
            if headingLevel(block) == 1 { levelOneHeadingCount += 1 }
        }

        var diagnostics: [RelayMarkDiagnostic] = []

        if document.frontmatter["refusal_reason"]?.stringValue != "insufficient_evidence" {
            diagnostics.append(
                diagnostic(
                    "relaymark.agent_answer.refusal_reason",
                    "A refused relaymark.agent_answer.v1 paper requires refusal_reason insufficient_evidence."
                )
            )
        }

        let structureValid =
            blocks.count == 2 &&
            nestedBlockCount == 2 &&
            blocks.first.map(headingLevel) == 1 &&
            levelOneHeadingCount == 1 &&
            blocks.first.map(validationPlainText) == "Answer unavailable" &&
            blocks.dropFirst().first?.type == "paragraph" &&
            isNonEmptyString(blocks.dropFirst().first.map(validationPlainText))

        if !structureValid {
            diagnostics.append(
                diagnostic(
                    "relaymark.agent_answer.refused_structure",
                    "A refused relaymark.agent_answer.v1 paper requires only an Answer unavailable level-one heading followed by one non-empty explanation paragraph."
                )
            )
        }

        var containsForbiddenBlock = false
        let forbiddenTypes: Set<String> = [
            "relay.claim",
            "relay.source_bundle",
            "relay.evidence_ref",
            "relay.agent_suggestion",
            "relay.action_row"
        ]

        visitBlocks(blocks) { block in
            if forbiddenTypes.contains(block.type) {
                containsForbiddenBlock = true
            }
        }

        if containsForbiddenBlock || !document.resources.isEmpty {
            diagnostics.append(
                diagnostic(
                    "relaymark.agent_answer.refused_content",
                    "A refused relaymark.agent_answer.v1 paper must not contain claims, sources, resources, evidence, suggestions, or actions."
                )
            )
        }

        return diagnostics
    }

    private static func duplicateEvidenceIdentityDiagnostics(
        for document: RelayMarkDocument
    ) -> [RelayMarkDiagnostic] {
        var identities: [String: String] = [:]
        var diagnostics: [RelayMarkDiagnostic] = []

        visitBlocks(document.blocks) { block in
            if isNonEmptyString(block.id), identities[block.id] == nil {
                identities[block.id] = "AST block '\(block.id)'"
            }
        }

        for resource in document.resources {
            registerEvidenceIdentity(
                resource.id,
                origin: "resource '\(resource.id)'",
                identities: &identities,
                diagnostics: &diagnostics
            )
        }

        visitBlocks(document.blocks) { block in
            guard block.type == "relay.source_bundle" || block.type == "relay.evidence_ref" else {
                return
            }

            let value = block.props["id"]?.stringValue

            if value != block.id {
                registerEvidenceIdentity(
                    value,
                    origin: "\(block.type).props.id on block '\(block.id)'",
                    identities: &identities,
                    diagnostics: &diagnostics
                )
            }
        }

        return diagnostics
    }

    private static func registerEvidenceIdentity(
        _ value: String?,
        origin: String,
        identities: inout [String: String],
        diagnostics: inout [RelayMarkDiagnostic]
    ) {
        guard let value, isNonEmptyString(value) else { return }

        if let prior = identities[value] {
            diagnostics.append(
                diagnostic(
                    "relaymark.identity.duplicate_evidence",
                    "Identity '\(value)' is ambiguous between \(prior) and \(origin)."
                )
            )
        } else {
            identities[value] = origin
        }
    }

    private static func canonicalManifest(
        for document: RelayMarkDocument,
        diagnostics: [RelayMarkDiagnostic]
    ) throws -> RelayMarkManifest {
        var resourcesByID: [String: RelayMarkResource] = [:]
        for resource in document.resources {
            resourcesByID[resource.id] = resource
        }

        var actions: [RelayMarkAction] = []
        var mentions: [RelayMarkMention] = []
        var references: [RelayMarkReference] = []
        var forms: [RelayMarkFormQuestion] = []
        var sources: [RelayMarkSource] = []
        var claims: [RelayMarkClaim] = []
        var comparisons: [RelayMarkComparison] = []

        try visitBlocksThrowing(document.blocks) { block in
            switch block.type {
            case "relay.action_row":
                guard
                    let action = block.props["action"]?.stringValue,
                    let review = block.props["review"]?.stringValue
                else {
                    throw RelayMarkAgentAnswerValidationError.invalidProjection
                }

                var args = block.props["args"]?.objectValue ?? [:]
                args["title"] = .string(projectionPlainText(block).trimmingRelayMarkWhitespace())
                actions.append(
                    RelayMarkAction(
                        blockID: block.id,
                        proposalID: block.props["proposal_id"]?.stringValue,
                        proposalRecordID: block.props["proposal_record_id"]?.stringValue,
                        proposalRevision: integerValue(block.props["proposal_revision"]),
                        action: action,
                        args: args,
                        target: block.props["target"]?.stringValue,
                        destination: block.props["destination"]?.stringValue,
                        visibility: block.props["visibility"]?.stringValue,
                        review: review,
                        decisionID: block.props["decision_id"]?.stringValue,
                        executionID: block.props["execution_id"]?.stringValue,
                        undoID: block.props["undo_id"]?.stringValue,
                        evidenceRefs: evidenceReferences(for: block)
                    )
                )

                if
                    let target = block.props["target"]?.stringValue,
                    target.hasPrefix("entity:")
                {
                    mentions.append(
                        RelayMarkMention(
                            blockID: block.id,
                            kind: "entity",
                            id: String(target.dropFirst("entity:".count)),
                            label: target
                        )
                    )
                }

            case "relay.claim":
                guard let key = block.props["key"]?.stringValue else {
                    throw RelayMarkAgentAnswerValidationError.invalidProjection
                }

                claims.append(
                    RelayMarkClaim(
                        blockID: block.id,
                        key: key,
                        subject: block.props["subject"]?.stringValue,
                        status: block.props["status"]?.stringValue ?? "unverified",
                        confidence: block.props["confidence"]?.numberValue,
                        evidenceRefs: evidenceReferences(for: block),
                        text: projectionPlainText(block).trimmingRelayMarkWhitespace()
                    )
                )

            case "relay.comparison":
                comparisons.append(
                    RelayMarkComparison(
                        blockID: block.id,
                        title: block.props["title"]?.stringValue,
                        subjects: stringArray(block.props["subjects"]) ?? [],
                        criteria: stringArray(block.props["criteria"]) ?? [],
                        values: block.props["values"]?.objectValue ?? [:],
                        preferred: block.props["preferred"]?.stringValue,
                        layout: block.props["layout"]?.stringValue ?? "table",
                        evidenceRefs: evidenceReferences(for: block),
                        summary: projectionPlainText(block).trimmingRelayMarkWhitespace()
                    )
                )

            case "relay.form_question":
                guard
                    let key = block.props["key"]?.stringValue,
                    let label = block.props["label"]?.stringValue,
                    let fieldType = block.props["field_type"]?.stringValue
                else {
                    throw RelayMarkAgentAnswerValidationError.invalidProjection
                }

                forms.append(
                    RelayMarkFormQuestion(
                        blockID: block.id,
                        key: key,
                        label: label,
                        fieldType: fieldType,
                        required: block.props["required"]?.boolValue ?? false,
                        options: stringArray(block.props["options"]) ?? []
                    )
                )

            case "relay.source_bundle":
                sources.append(
                    RelayMarkSource(
                        blockID: block.id,
                        kind: "source_bundle",
                        sourceID: block.props["id"]?.stringValue,
                        bundleRevision: integerValue(block.props["revision"]),
                        sourceHash: block.props["source_hash"]?.stringValue,
                        label: block.props["title"]?.stringValue
                    )
                )

            case "relay.evidence_ref":
                let sourceID = block.props["source"]?.stringValue
                let sourceType = block.props["source_type"]?.stringValue
                var scriptureRelease: RelayMarkScriptureRelease?

                if
                    sourceType == "scripture",
                    let sourceID,
                    let resource = resourcesByID[sourceID],
                    resource.type == "scripture"
                {
                    scriptureRelease = try resource.decodeScriptureRelease()
                }

                sources.append(
                    RelayMarkSource(
                        blockID: block.id,
                        kind: "evidence_ref",
                        evidenceID: block.props["id"]?.stringValue,
                        sourceID: sourceID,
                        sourceType: sourceType,
                        sourceRevision: block.props["source_revision"]?.stringValue,
                        selector: block.props["selector"]?.objectValue,
                        scope: block.props["scope"]?.stringValue,
                        label: block.props["label"]?.stringValue,
                        excerpt: projectionPlainText(block)
                            .trimmingRelayMarkWhitespace()
                            .nilIfEmpty,
                        scriptureRelease: scriptureRelease
                    )
                )

            case "relay.transcript_segment":
                guard
                    let sourceID = block.props["source"]?.stringValue,
                    let start = block.props["start"]?.stringValue,
                    let end = block.props["end"]?.stringValue
                else {
                    throw RelayMarkAgentAnswerValidationError.invalidProjection
                }

                sources.append(
                    RelayMarkSource(
                        blockID: block.id,
                        kind: "transcript_range",
                        sourceID: sourceID,
                        start: start,
                        end: end,
                        label: block.props["speaker"]?.stringValue
                    )
                )

            case "relay.file_ref":
                sources.append(
                    RelayMarkSource(
                        blockID: block.id,
                        kind: "file_ref",
                        sourceID: block.props["id"]?.stringValue,
                        uri: block.props["uri"]?.stringValue,
                        label: block.props["label"]?.stringValue
                    )
                )

            case "relay.note_ref":
                sources.append(
                    RelayMarkSource(
                        blockID: block.id,
                        kind: "note_ref",
                        sourceID: block.props["document"]?.stringValue ??
                            block.props["block"]?.stringValue,
                        label: block.props["label"]?.stringValue
                    )
                )

            case "relay.url_ref":
                sources.append(
                    RelayMarkSource(
                        blockID: block.id,
                        kind: "url_ref",
                        uri: block.props["url"]?.stringValue,
                        label: block.props["label"]?.stringValue
                    )
                )

            default:
                break
            }

            collectInlineReferences(
                in: block,
                mentions: &mentions,
                references: &references
            )
        }

        return RelayMarkManifest(
            type: "relaymark.manifest",
            version: 1,
            actions: actions,
            mentions: unique(mentions),
            references: unique(references),
            forms: forms,
            sources: sources,
            claims: claims,
            comparisons: comparisons,
            diagnostics: diagnostics
        )
    }

    private static func collectInlineReferences(
        in block: RelayMarkBlock,
        mentions: inout [RelayMarkMention],
        references: inout [RelayMarkReference]
    ) {
        for content in block.content {
            guard case let .inline(inline) = content else { continue }
            collectInlineReference(
                inline,
                blockID: block.id,
                mentions: &mentions,
                references: &references
            )
        }
    }

    private static func collectInlineReference(
        _ inline: RelayMarkInline,
        blockID: String,
        mentions: inout [RelayMarkMention],
        references: inout [RelayMarkReference]
    ) {
        if inline.type.hasPrefix("relay."), inline.type.hasSuffix("_ref") {
            references.append(
                RelayMarkReference(
                    blockID: blockID,
                    type: inline.type,
                    id: inline.id,
                    label: inline.label,
                    href: inline.href
                )
            )
        }

        if inline.type == "relay.entity_ref" {
            mentions.append(
                RelayMarkMention(
                    blockID: blockID,
                    kind: "entity",
                    id: inline.id,
                    label: inline.label ?? ""
                )
            )
        }

        for child in inline.content {
            collectInlineReference(
                child,
                blockID: blockID,
                mentions: &mentions,
                references: &references
            )
        }
    }

    private static func evidenceTargets(in document: RelayMarkDocument) -> Set<String> {
        var targets = Set(
            document.resources.map(\.id).filter(isNonEmptyString)
        )

        visitBlocks(document.blocks) { block in
            if isNonEmptyString(block.id) {
                targets.insert(block.id)
            }

            if
                block.type == "relay.source_bundle",
                let value = block.props["id"]?.stringValue,
                isNonEmptyString(value)
            {
                targets.insert(value)
            }

            if
                block.type == "relay.evidence_ref",
                let value = block.props["id"]?.stringValue,
                isNonEmptyString(value)
            {
                targets.insert(value)
            }

            if
                block.type == "relay.transcript_segment",
                let value = block.props["source"]?.stringValue,
                isNonEmptyString(value)
            {
                targets.insert(value)
            }

            if
                block.type == "relay.file_ref",
                let value = block.props["id"]?.stringValue,
                isNonEmptyString(value)
            {
                targets.insert(value)
            }

            if block.type == "relay.note_ref" {
                for key in ["document", "block"] {
                    if
                        let value = block.props[key]?.stringValue,
                        isNonEmptyString(value)
                    {
                        targets.insert(value)
                    }
                }
            }
        }

        return targets
    }

    private static func headingLevel(_ block: RelayMarkBlock) -> Int? {
        guard
            block.type == "heading",
            let value = block.props["level"]?.numberValue,
            value.isFinite,
            value.rounded(.towardZero) == value,
            value >= Double(Int.min),
            value <= Double(Int.max)
        else {
            return nil
        }

        return Int(value)
    }

    private static func validationPlainText(_ block: RelayMarkBlock) -> String {
        block.content.map(validationPlainText).joined()
    }

    private static func validationPlainText(_ content: RelayMarkContent) -> String {
        switch content {
        case .block(let block):
            return validationPlainText(block)
        case .inline(let inline):
            return validationPlainText(inline)
        }
    }

    private static func validationPlainText(_ inline: RelayMarkInline) -> String {
        if inline.type == "text" {
            return inline.text ?? ""
        }

        return inline.content.map(validationPlainText).joined()
    }

    private static func projectionPlainText(_ block: RelayMarkBlock) -> String {
        block.content.map(projectionPlainText).joined()
    }

    private static func projectionPlainText(_ content: RelayMarkContent) -> String {
        switch content {
        case .block(let block):
            return projectionPlainText(block)
        case .inline(let inline):
            return projectionPlainText(inline)
        }
    }

    private static func projectionPlainText(_ inline: RelayMarkInline) -> String {
        if inline.type == "text" {
            return inline.text ?? ""
        }

        if
            inline.type.hasPrefix("relay."),
            inline.type.hasSuffix("_ref"),
            let label = inline.label
        {
            return label
        }

        return inline.content.map(projectionPlainText).joined()
    }

    private static func evidenceReferences(for block: RelayMarkBlock) -> [String] {
        if !block.evidenceRefs.isEmpty {
            return block.evidenceRefs
        }

        return stringArray(block.props["evidence"]) ?? []
    }

    private static func stringArray(_ value: RelayMarkValue?) -> [String]? {
        guard let values = value?.arrayValue else { return nil }
        let strings = values.compactMap(\.stringValue)
        return strings.count == values.count ? strings : nil
    }

    private static func integerValue(_ value: RelayMarkValue?) -> Int? {
        guard
            let number = value?.numberValue,
            number.isFinite,
            number.rounded(.towardZero) == number,
            number >= Double(Int.min),
            number <= Double(Int.max)
        else {
            return nil
        }

        return Int(number)
    }

    private static func isNonEmptyString(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.unicodeScalars.contains { !isRelayMarkWhitespace($0.value) }
    }

    private static func isRelayMarkWhitespace(_ value: UInt32) -> Bool {
        switch value {
        case 0x0009...0x000D, 0x0020, 0x0085, 0x00A0, 0x1680,
             0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    private static func visitBlocks(
        _ blocks: [RelayMarkBlock],
        _ visitor: (RelayMarkBlock) -> Void
    ) {
        for block in blocks {
            visitor(block)
            visitBlocks(block.childBlocks, visitor)
        }
    }

    private static func visitBlocksThrowing(
        _ blocks: [RelayMarkBlock],
        _ visitor: (RelayMarkBlock) throws -> Void
    ) throws {
        for block in blocks {
            try visitor(block)
            try visitBlocksThrowing(block.childBlocks, visitor)
        }
    }

    private static func unique<T: Equatable>(_ values: [T]) -> [T] {
        var result: [T] = []

        for value in values where !result.contains(value) {
            result.append(value)
        }

        return result
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func diagnostic(_ code: String, _ message: String) -> RelayMarkDiagnostic {
        RelayMarkDiagnostic(level: "error", code: code, message: message)
    }

    private static func manifestMismatchDiagnostic() -> RelayMarkDiagnostic {
        diagnostic(
            "relaymark.agent_answer.manifest_mismatch",
            "Transported relaymark.agent_answer.v1 manifest must exactly match the canonical projection of its document."
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func trimmingRelayMarkWhitespace() -> String {
        let scalars = unicodeScalars
        var lowerBound = scalars.startIndex
        var upperBound = scalars.endIndex

        while
            lowerBound < upperBound,
            RelayMarkAgentAnswerValidator.isProjectionWhitespace(scalars[lowerBound].value)
        {
            lowerBound = scalars.index(after: lowerBound)
        }

        while upperBound > lowerBound {
            let prior = scalars.index(before: upperBound)
            guard RelayMarkAgentAnswerValidator.isProjectionWhitespace(scalars[prior].value) else {
                break
            }
            upperBound = prior
        }

        return String(scalars[lowerBound..<upperBound])
    }
}

private extension RelayMarkAgentAnswerValidator {
    static func isProjectionWhitespace(_ value: UInt32) -> Bool {
        switch value {
        case 0x0009...0x000D, 0x0020, 0x0085, 0x00A0, 0x1680,
             0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }
}

private extension RelayMarkManifest {
    init(
        type: String,
        version: Int,
        actions: [RelayMarkAction],
        mentions: [RelayMarkMention],
        references: [RelayMarkReference],
        forms: [RelayMarkFormQuestion],
        sources: [RelayMarkSource],
        claims: [RelayMarkClaim],
        comparisons: [RelayMarkComparison],
        diagnostics: [RelayMarkDiagnostic]
    ) {
        self.type = type
        self.version = version
        self.actions = actions
        self.mentions = mentions
        self.references = references
        self.forms = forms
        self.sources = sources
        self.claims = claims
        self.comparisons = comparisons
        self.diagnostics = diagnostics
    }
}

private extension RelayMarkAction {
    init(
        blockID: String,
        proposalID: String?,
        proposalRecordID: String?,
        proposalRevision: Int?,
        action: String,
        args: [String: RelayMarkValue],
        target: String?,
        destination: String?,
        visibility: String?,
        review: String,
        decisionID: String?,
        executionID: String?,
        undoID: String?,
        evidenceRefs: [String]
    ) {
        self.blockID = blockID
        self.proposalID = proposalID
        self.proposalRecordID = proposalRecordID
        self.proposalRevision = proposalRevision
        self.action = action
        self.args = args
        self.target = target
        self.destination = destination
        self.visibility = visibility
        self.review = review
        self.decisionID = decisionID
        self.executionID = executionID
        self.undoID = undoID
        self.evidenceRefs = evidenceRefs
    }
}

private extension RelayMarkSource {
    init(
        blockID: String,
        kind: String,
        evidenceID: String? = nil,
        sourceID: String? = nil,
        sourceType: String? = nil,
        sourceRevision: String? = nil,
        selector: [String: RelayMarkValue]? = nil,
        scope: String? = nil,
        bundleRevision: Int? = nil,
        sourceHash: String? = nil,
        start: String? = nil,
        end: String? = nil,
        uri: String? = nil,
        label: String? = nil,
        excerpt: String? = nil,
        scriptureRelease: RelayMarkScriptureRelease? = nil
    ) {
        self.blockID = blockID
        self.kind = kind
        self.evidenceID = evidenceID
        self.sourceID = sourceID
        self.sourceType = sourceType
        self.sourceRevision = sourceRevision
        self.selector = selector
        self.scope = scope
        self.bundleRevision = bundleRevision
        self.sourceHash = sourceHash
        self.start = start
        self.end = end
        self.uri = uri
        self.label = label
        self.excerpt = excerpt
        self.scriptureRelease = scriptureRelease
    }
}
