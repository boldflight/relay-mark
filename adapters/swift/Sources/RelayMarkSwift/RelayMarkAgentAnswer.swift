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
    private static let portableBlockReferenceTypes: Set<String> = [
        "relay.evidence_ref",
        "relay.file_ref",
        "relay.note_ref",
        "relay.url_ref"
    ]
    private static let portableCommonMarkBlockTypes: Set<String> = [
        "paragraph",
        "heading",
        "list",
        "list_item",
        "quote",
        "code",
        "table",
        "table_row",
        "table_cell",
        "image",
        "horizontal_rule"
    ]
    private static let portableAnnotationTypes: Set<String> = [
        "comment",
        "private_note",
        "highlight",
        "agent_suggestion",
        "redaction",
        "source_grounding",
        "review_decision"
    ]
    private static let portableResourceTypes: Set<String> = [
        "transcript",
        "file",
        "url",
        "image",
        "video",
        "audio",
        "entity",
        "event",
        "note",
        "form_submission",
        "scripture"
    ]

    private enum DirectiveAttributeKind {
        case string
        case integer
        case number
        case boolean
        case object
        case stringArray
        case enumeration([String])
    }

    private struct DirectiveAttribute {
        let name: String
        let kind: DirectiveAttributeKind
        let required: Bool
    }

    private struct DirectiveDefinition {
        let attributes: [DirectiveAttribute]
        let requiresReview: Bool
        let requiresEvidence: Bool
    }

    private static let directiveRegistry: [String: DirectiveDefinition] = {
        func attribute(
            _ name: String,
            _ kind: DirectiveAttributeKind,
            required: Bool = false
        ) -> DirectiveAttribute {
            DirectiveAttribute(name: name, kind: kind, required: required)
        }

        func directive(
            _ attributes: [DirectiveAttribute],
            requiresReview: Bool = false,
            requiresEvidence: Bool = false
        ) -> DirectiveDefinition {
            DirectiveDefinition(
                attributes: attributes,
                requiresReview: requiresReview,
                requiresEvidence: requiresEvidence
            )
        }

        let scopes = ["private", "org", "unlisted", "public"]

        return [
            "relay.action_row": directive(
                [
                    attribute("proposal_id", .string),
                    attribute("proposal_record_id", .string),
                    attribute("proposal_revision", .integer),
                    attribute("action", .string, required: true),
                    attribute("target", .string),
                    attribute("destination", .string),
                    attribute("visibility", .enumeration(scopes)),
                    attribute(
                        "review",
                        .enumeration(["draft", "ready", "accepted", "rejected", "undone"])
                    ),
                    attribute("decision_id", .string),
                    attribute("execution_id", .string),
                    attribute("undo_id", .string),
                    attribute("confidence", .number),
                    attribute("evidence", .stringArray),
                    attribute("args", .object)
                ],
                requiresReview: true
            ),
            "relay.agent_suggestion": directive(
                [
                    attribute("confidence", .number),
                    attribute("evidence", .stringArray),
                    attribute(
                        "review",
                        .enumeration(["draft", "ready", "accepted", "rejected"])
                    ),
                    attribute(
                        "kind",
                        .enumeration(["note", "action", "match", "journey", "source", "share"])
                    ),
                    attribute("anchor", .string)
                ],
                requiresReview: true
            ),
            "relay.claim": directive(
                [
                    attribute("key", .string, required: true),
                    attribute("subject", .string),
                    attribute(
                        "status",
                        .enumeration(["unverified", "supported", "disputed", "refuted", "resolved"])
                    ),
                    attribute("confidence", .number),
                    attribute("evidence", .stringArray)
                ],
                requiresEvidence: true
            ),
            "relay.comparison": directive(
                [
                    attribute("title", .string),
                    attribute("subjects", .stringArray, required: true),
                    attribute("criteria", .stringArray, required: true),
                    attribute("values", .object, required: true),
                    attribute("preferred", .string),
                    attribute(
                        "layout",
                        .enumeration(["table", "bar", "timeline", "checklist", "radar", "heatmap"])
                    ),
                    attribute("evidence", .stringArray)
                ],
                requiresEvidence: true
            ),
            "relay.evidence_ref": directive([
                attribute("id", .string, required: true),
                attribute("source", .string, required: true),
                attribute("source_type", .string),
                attribute("source_revision", .string),
                attribute("selector", .object),
                attribute("label", .string),
                attribute("scope", .enumeration(scopes))
            ]),
            "relay.file_ref": directive([
                attribute("id", .string),
                attribute("uri", .string),
                attribute("label", .string),
                attribute("scope", .enumeration(scopes))
            ]),
            "relay.form_question": directive([
                attribute("key", .string, required: true),
                attribute("label", .string, required: true),
                attribute(
                    "field_type",
                    .enumeration([
                        "short_text",
                        "long_text",
                        "single_select",
                        "multi_select",
                        "number",
                        "date",
                        "entity_ref",
                        "file"
                    ]),
                    required: true
                ),
                attribute("required", .boolean),
                attribute("options", .stringArray),
                attribute("visibility", .enumeration(scopes))
            ]),
            "relay.note_ref": directive([
                attribute("document", .string),
                attribute("block", .string),
                attribute("label", .string),
                attribute("scope", .enumeration(scopes))
            ]),
            "relay.source_bundle": directive([
                attribute("id", .string, required: true),
                attribute("title", .string),
                attribute("revision", .integer),
                attribute("source_hash", .string),
                attribute("scope", .enumeration(scopes)),
                attribute("confidence", .number)
            ]),
            "relay.transcript_segment": directive([
                attribute("source", .string),
                attribute("speaker", .string),
                attribute("speaker_entity", .string),
                attribute("start", .string, required: true),
                attribute("end", .string, required: true),
                attribute("confidence", .number)
            ]),
            "relay.url_ref": directive([
                attribute("url", .string, required: true),
                attribute("label", .string),
                attribute("scope", .enumeration(scopes))
            ])
        ]
    }()

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
        diagnostics.append(contentsOf: documentIdentityDiagnostics(for: document))
        return diagnostics
    }

    public static func project(
        document: RelayMarkDocument,
        manifest: RelayMarkManifest,
        context: RelayMarkAgentAnswerValidationContext = .generic
    ) throws -> RelayMarkAgentAnswerProjection {
        let schemaDiagnostics = portableSchemaDiagnostics(for: document)
        guard schemaDiagnostics.isEmpty else {
            throw RelayMarkAgentAnswerValidationError.diagnostics(schemaDiagnostics)
        }

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
        let rawDocument = try RelayMarkDecoder.decode(RelayMarkValue.self, from: documentJSON)
        let schemaDiagnostics = portableSchemaDiagnostics(for: rawDocument)

        guard schemaDiagnostics.isEmpty else {
            throw RelayMarkAgentAnswerValidationError.diagnostics(schemaDiagnostics)
        }

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

            if block.type.hasPrefix("relay.") {
                diagnostics.append(
                    contentsOf: relayBlockDiagnostics(
                        for: block,
                        evidenceTargets: evidenceTargets,
                        scriptureResources: scriptureResources
                    )
                )
            }
        }

        return diagnostics
    }

    private static func portableSchemaDiagnostics(
        for document: RelayMarkDocument
    ) -> [RelayMarkDiagnostic] {
        guard
            document.type == "relaymark.document",
            document.version >= 1,
            document.blocks.allSatisfy(blockHasPortableSchemaShape),
            document.annotations.allSatisfy(annotationHasPortableSchemaShape),
            document.resources.allSatisfy(resourceHasPortableSchemaShape)
        else {
            return [schemaDiagnostic()]
        }

        return []
    }

    private static func portableSchemaDiagnostics(
        for rawDocument: RelayMarkValue
    ) -> [RelayMarkDiagnostic] {
        rawDocumentHasPortableSchemaShape(rawDocument)
            ? []
            : [schemaDiagnostic()]
    }

    private static func rawDocumentHasPortableSchemaShape(_ value: RelayMarkValue) -> Bool {
        guard
            let document = value.objectValue,
            hasOnlyKeys(
                document,
                allowed: [
                    "type",
                    "version",
                    "frontmatter",
                    "blocks",
                    "annotations",
                    "resources",
                    "meta"
                ]
            ),
            document["type"]?.stringValue == "relaymark.document",
            integerValue(document["version"]).map({ $0 >= 1 }) == true,
            document["frontmatter"].map({ $0.objectValue != nil }) != false,
            document["meta"].map({ $0.objectValue != nil }) != false,
            let blocks = document["blocks"]?.arrayValue,
            blocks.allSatisfy(rawBlockHasPortableSchemaShape),
            optionalArray(
                document["annotations"],
                hasElementsSatisfying: rawAnnotationHasPortableSchemaShape
            ),
            optionalArray(
                document["resources"],
                hasElementsSatisfying: rawResourceHasPortableSchemaShape
            )
        else {
            return false
        }

        return true
    }

    private static func rawBlockHasPortableSchemaShape(_ value: RelayMarkValue) -> Bool {
        guard
            let block = value.objectValue,
            hasOnlyKeys(
                block,
                allowed: [
                    "id",
                    "type",
                    "props",
                    "content",
                    "evidence_refs",
                    "source_location",
                    "meta"
                ]
            ),
            block["id"]?.stringValue.map(isPortableID) == true,
            block["type"]?.stringValue.map(isPortableBlockType) == true,
            block["props"].map({ $0.objectValue != nil }) != false,
            optionalArray(
                block["evidence_refs"],
                hasElementsSatisfying: {
                    isNonEmptySchemaString($0.stringValue)
                }
            ),
            block["source_location"].map(rawLocationHasPortableSchemaShape) != false,
            block["meta"].map({ $0.objectValue != nil }) != false
        else {
            return false
        }

        let type = block["type"]?.stringValue
        let props = block["props"]?.objectValue

        if type == "relay.source_bundle" {
            guard isNonEmptySchemaString(props?["id"]?.stringValue) else {
                return false
            }
        }

        if type == "relay.evidence_ref" {
            guard
                isNonEmptySchemaString(props?["id"]?.stringValue),
                isNonEmptySchemaString(props?["source"]?.stringValue)
            else {
                return false
            }

            if props?["source_type"]?.stringValue == "scripture" {
                guard
                    isNonEmptySchemaString(props?["source_revision"]?.stringValue),
                    scriptureSpanHasSchemaShape(props?["selector"]?.objectValue),
                    props?["scope"]?.stringValue.map({ canonicalScopes.contains($0) }) == true,
                    props?["label"].map({ $0.stringValue != nil }) != false,
                    block["content"]?.arrayValue?.isEmpty == false
                else {
                    return false
                }
            }
        }

        guard let content = block["content"] else {
            return true
        }

        guard let values = content.arrayValue else {
            return false
        }

        return values.allSatisfy { child in
            guard let type = child.objectValue?["type"]?.stringValue else {
                return false
            }

            if isPortableInlineType(type) {
                return rawInlineHasPortableSchemaShape(child)
            }

            return isPortableBlockType(type) &&
                rawBlockHasPortableSchemaShape(child)
        }
    }

    private static func rawInlineHasPortableSchemaShape(_ value: RelayMarkValue) -> Bool {
        guard
            let inline = value.objectValue,
            hasOnlyKeys(
                inline,
                allowed: ["type", "text", "id", "label", "href", "props", "content"]
            ),
            inline["type"]?.stringValue.map(isPortableInlineType) == true,
            inline["text"].map({ $0.stringValue != nil }) != false,
            inline["id"].map({ $0.stringValue != nil }) != false,
            inline["label"].map({ $0.stringValue != nil }) != false,
            inline["href"].map({ $0.stringValue != nil }) != false,
            inline["props"].map({ $0.objectValue != nil }) != false
        else {
            return false
        }

        guard let content = inline["content"] else {
            return true
        }

        guard let values = content.arrayValue else {
            return false
        }

        return values.allSatisfy(rawInlineHasPortableSchemaShape)
    }

    private static func rawAnnotationHasPortableSchemaShape(
        _ value: RelayMarkValue
    ) -> Bool {
        guard
            let annotation = value.objectValue,
            hasOnlyKeys(
                annotation,
                allowed: ["id", "type", "anchor", "props", "content"]
            ),
            annotation["id"]?.stringValue.map(isPortableID) == true,
            annotation["type"]?.stringValue.map({
                portableAnnotationTypes.contains($0)
            }) == true,
            annotation["props"].map({ $0.objectValue != nil }) != false,
            annotation["anchor"].map(rawAnchorHasPortableSchemaShape) == true
        else {
            return false
        }

        guard let content = annotation["content"] else {
            return true
        }

        guard let values = content.arrayValue else {
            return false
        }

        return values.allSatisfy(rawInlineHasPortableSchemaShape)
    }

    private static func rawAnchorHasPortableSchemaShape(_ value: RelayMarkValue) -> Bool {
        guard
            let anchor = value.objectValue,
            hasOnlyKeys(anchor, allowed: ["block_id", "start", "end", "quote"]),
            anchor["block_id"]?.stringValue.map(isPortableID) == true,
            anchor["quote"].map({ $0.stringValue != nil }) != false
        else {
            return false
        }

        for field in ["start", "end"] {
            if
                let value = anchor[field],
                integerValue(value).map({ $0 >= 0 }) != true
            {
                return false
            }
        }

        return true
    }

    private static func rawResourceHasPortableSchemaShape(
        _ value: RelayMarkValue
    ) -> Bool {
        guard
            let resource = value.objectValue,
            hasOnlyKeys(
                resource,
                allowed: ["id", "type", "uri", "label", "scope", "props"]
            ),
            resource["id"]?.stringValue.map(isPortableID) == true,
            resource["type"]?.stringValue.map({
                portableResourceTypes.contains($0)
            }) == true,
            resource["uri"].map({ $0.stringValue != nil }) != false,
            resource["label"].map({ $0.stringValue != nil }) != false,
            resource["scope"].map({
                $0.stringValue.map({ canonicalScopes.contains($0) }) == true
            }) != false,
            resource["props"].map({ $0.objectValue != nil }) != false
        else {
            return false
        }

        guard resource["type"]?.stringValue == "scripture" else {
            return true
        }

        guard
            resource["scope"]?.stringValue.map({ canonicalScopes.contains($0) }) == true,
            let props = resource["props"]?.objectValue
        else {
            return false
        }

        return scriptureReleaseHasSchemaShape(props)
    }

    private static func rawLocationHasPortableSchemaShape(
        _ value: RelayMarkValue
    ) -> Bool {
        guard
            let location = value.objectValue,
            hasOnlyKeys(
                location,
                allowed: ["line", "column", "end_line", "end_column"]
            )
        else {
            return false
        }

        for field in ["line", "column", "end_line", "end_column"] {
            if
                let value = location[field],
                integerValue(value).map({ $0 >= 1 }) != true
            {
                return false
            }
        }

        return true
    }

    private static func hasOnlyKeys(
        _ object: [String: RelayMarkValue],
        allowed: Set<String>
    ) -> Bool {
        Set(object.keys).isSubset(of: allowed)
    }

    private static func optionalArray(
        _ value: RelayMarkValue?,
        hasElementsSatisfying predicate: (RelayMarkValue) -> Bool
    ) -> Bool {
        guard let value else { return true }
        guard let values = value.arrayValue else { return false }
        return values.allSatisfy(predicate)
    }

    private static func blockHasPortableSchemaShape(_ block: RelayMarkBlock) -> Bool {
        guard
            isPortableID(block.id),
            isPortableBlockType(block.type),
            block.evidenceRefs.allSatisfy(isNonEmptySchemaString)
        else {
            return false
        }

        if block.type == "relay.source_bundle" {
            guard isNonEmptySchemaString(block.props["id"]?.stringValue) else {
                return false
            }
        }

        if block.type == "relay.evidence_ref" {
            guard
                isNonEmptySchemaString(block.props["id"]?.stringValue),
                isNonEmptySchemaString(block.props["source"]?.stringValue)
            else {
                return false
            }

            if block.props["source_type"]?.stringValue == "scripture" {
                guard
                    isNonEmptySchemaString(block.props["source_revision"]?.stringValue),
                    scriptureSpanHasSchemaShape(block.props["selector"]?.objectValue),
                    block.props["scope"]?.stringValue.map({ canonicalScopes.contains($0) }) == true,
                    block.props["label"].map({ $0.stringValue != nil }) != false,
                    !block.content.isEmpty
                else {
                    return false
                }
            }
        }

        return block.content.allSatisfy { content in
            switch content {
            case .block(let child):
                return blockHasPortableSchemaShape(child)
            case .inline(let inline):
                return inlineHasPortableSchemaShape(inline)
            }
        }
    }

    private static func inlineHasPortableSchemaShape(_ inline: RelayMarkInline) -> Bool {
        isPortableInlineType(inline.type) &&
            inline.content.allSatisfy(inlineHasPortableSchemaShape)
    }

    private static func annotationHasPortableSchemaShape(
        _ annotation: RelayMarkAnnotation
    ) -> Bool {
        isPortableID(annotation.id) &&
            portableAnnotationTypes.contains(annotation.type) &&
            isPortableID(annotation.anchor.blockID) &&
            annotation.anchor.start.map({ $0 >= 0 }) != false &&
            annotation.anchor.end.map({ $0 >= 0 }) != false &&
            annotation.content.allSatisfy(inlineHasPortableSchemaShape)
    }

    private static func resourceHasPortableSchemaShape(_ resource: RelayMarkResource) -> Bool {
        guard
            isPortableID(resource.id),
            portableResourceTypes.contains(resource.type),
            resource.scope.map({ canonicalScopes.contains($0) }) != false
        else {
            return false
        }

        guard resource.type == "scripture" else {
            return true
        }

        guard
            resource.scope.map({ canonicalScopes.contains($0) }) == true,
            scriptureReleaseHasSchemaShape(resource.props)
        else {
            return false
        }

        return true
    }

    private static func scriptureReleaseHasSchemaShape(
        _ props: [String: RelayMarkValue]
    ) -> Bool {
        guard
            props["profile"]?.stringValue == "relaymark.scripture_release.v1",
            isNonEmptySchemaString(props["translation_id"]?.stringValue),
            isNonEmptySchemaString(props["edition_id"]?.stringValue),
            isNonEmptySchemaString(props["corpus_release_id"]?.stringValue),
            isNonEmptySchemaString(props["versification_id"]?.stringValue),
            isNonEmptySchemaString(props["attribution"]?.stringValue),
            scriptureSourceHasSchemaShape(props["source"]?.objectValue),
            scriptureLicenseHasSchemaShape(props["license"]?.objectValue),
            scriptureProvenanceHasSchemaShape(props["provenance"]?.objectValue)
        else {
            return false
        }

        return Set(props.keys).isSubset(
            of: [
                "profile",
                "translation_id",
                "edition_id",
                "corpus_release_id",
                "versification_id",
                "source",
                "license",
                "attribution",
                "provenance"
            ]
        )
    }

    private static func scriptureSourceHasSchemaShape(
        _ source: [String: RelayMarkValue]?
    ) -> Bool {
        guard let source else { return false }
        return Set(source.keys).isSubset(of: ["name", "uri", "digest"]) &&
            isNonEmptySchemaString(source["name"]?.stringValue) &&
            isNonEmptySchemaString(source["uri"]?.stringValue) &&
            isSHA256Digest(source["digest"]?.stringValue)
    }

    private static func scriptureLicenseHasSchemaShape(
        _ license: [String: RelayMarkValue]?
    ) -> Bool {
        guard let license else { return false }
        return Set(license.keys).isSubset(of: ["id", "name", "url"]) &&
            isNonEmptySchemaString(license["id"]?.stringValue) &&
            isNonEmptySchemaString(license["name"]?.stringValue) &&
            isNonEmptySchemaString(license["url"]?.stringValue)
    }

    private static func scriptureProvenanceHasSchemaShape(
        _ provenance: [String: RelayMarkValue]?
    ) -> Bool {
        guard let provenance else { return false }
        let allowedKeys: Set<String> = [
            "coordinate_inventory_digest",
            "normalized_index_input_digest",
            "source_archive_digest",
            "authority",
            "imported_at"
        ]

        guard
            Set(provenance.keys).isSubset(of: allowedKeys),
            isSHA256Digest(provenance["coordinate_inventory_digest"]?.stringValue),
            isSHA256Digest(provenance["normalized_index_input_digest"]?.stringValue)
        else {
            return false
        }

        if
            let digest = provenance["source_archive_digest"],
            !isSHA256Digest(digest.stringValue)
        {
            return false
        }

        for field in ["authority", "imported_at"]
        where provenance[field] != nil &&
            !isNonEmptySchemaString(provenance[field]?.stringValue) {
            return false
        }

        return true
    }

    private static func scriptureSpanHasSchemaShape(
        _ selector: [String: RelayMarkValue]?
    ) -> Bool {
        guard let selector else { return false }
        let allowedKeys: Set<String> = [
            "profile",
            "start",
            "end",
            "content_digest",
            "display_label"
        ]

        return Set(selector.keys).isSubset(of: allowedKeys) &&
            selector["profile"]?.stringValue == "relaymark.scripture_span.v1" &&
            scriptureCoordinateHasSchemaShape(selector["start"]?.objectValue) &&
            scriptureCoordinateHasSchemaShape(selector["end"]?.objectValue) &&
            isSHA256Digest(selector["content_digest"]?.stringValue) &&
            (
                selector["display_label"] == nil ||
                isNonEmptySchemaString(selector["display_label"]?.stringValue)
            )
    }

    private static func scriptureCoordinateHasSchemaShape(
        _ coordinate: [String: RelayMarkValue]?
    ) -> Bool {
        guard
            let coordinate,
            isNonEmptySchemaString(coordinate["book_id"]?.stringValue),
            isNonEmptySchemaString(coordinate["verse_label"]?.stringValue)
        else {
            return false
        }

        switch coordinate["coordinate_kind"]?.stringValue {
        case "chapter":
            return Set(coordinate.keys).isSubset(
                of: ["book_id", "coordinate_kind", "chapter", "verse_label"]
            ) &&
                integerValue(coordinate["chapter"]).map({ $0 >= 1 }) == true
        case "section":
            return Set(coordinate.keys).isSubset(
                of: ["book_id", "coordinate_kind", "section_id", "verse_label"]
            ) &&
                isNonEmptySchemaString(coordinate["section_id"]?.stringValue)
        default:
            return false
        }
    }

    private static func isPortableID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard let first = bytes.first, isASCIIAlpha(first) else {
            return false
        }

        return bytes.dropFirst().allSatisfy {
            isASCIIAlpha($0) ||
                (48...57).contains($0) ||
                $0 == 45 ||
                $0 == 95
        }
    }

    private static func isNonEmptySchemaString(_ value: String?) -> Bool {
        value?.isEmpty == false
    }

    private static func isPortableBlockType(_ value: String) -> Bool {
        if portableCommonMarkBlockTypes.contains(value) {
            return true
        }

        if value.hasPrefix("widget.") {
            return isPortableTypeSuffix(String(value.dropFirst("widget.".count)))
        }

        guard value.hasPrefix("relay.") else {
            return false
        }

        let suffix = String(value.dropFirst("relay.".count))
        guard isPortableTypeSuffix(suffix) else {
            return false
        }

        return !suffix.hasSuffix("_ref") || portableBlockReferenceTypes.contains(value)
    }

    private static func isPortableInlineType(_ value: String) -> Bool {
        let commonMarkTypes: Set<String> = [
            "text",
            "hard_break",
            "soft_break",
            "link",
            "emphasis",
            "strong",
            "code_span"
        ]

        if commonMarkTypes.contains(value) {
            return true
        }

        return value.hasPrefix("relay.") &&
            value.hasSuffix("_ref") &&
            !portableBlockReferenceTypes.contains(value) &&
            isPortableTypeSuffix(String(value.dropFirst("relay.".count)))
    }

    private static func isPortableTypeSuffix(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard let first = bytes.first, (97...122).contains(first) else {
            return false
        }

        return bytes.dropFirst().allSatisfy {
            (97...122).contains($0) ||
                (48...57).contains($0) ||
                $0 == 95
        }
    }

    private static func isASCIIAlpha(_ value: UInt8) -> Bool {
        (65...90).contains(value) || (97...122).contains(value)
    }

    private static func relayBlockDiagnostics(
        for block: RelayMarkBlock,
        evidenceTargets: Set<String>,
        scriptureResources: [String: [RelayMarkResource]]
    ) -> [RelayMarkDiagnostic] {
        guard let directive = directiveRegistry[block.type] else {
            return [
                diagnostic(
                    "relaymark.directive.unknown_type",
                    "Unknown Relay block type '\(block.type)'."
                )
            ]
        }

        var diagnostics: [RelayMarkDiagnostic] = []

        for attribute in directive.attributes {
            guard let value = block.props[attribute.name] else {
                if attribute.required {
                    diagnostics.append(
                        diagnostic(
                            "relaymark.attribute.required",
                            "\(block.type).\(attribute.name) is required."
                        )
                    )
                }
                continue
            }

            diagnostics.append(
                contentsOf: attributeDiagnostics(
                    value,
                    named: attribute.name,
                    on: block.type,
                    kind: attribute.kind
                )
            )
        }

        if directive.requiresReview, block.props["review"] == nil {
            diagnostics.append(
                diagnostic(
                    "relaymark.policy.review_required",
                    "\(block.type) requires a review state."
                )
            )
        }

        let references = evidenceReferences(for: block)

        if directive.requiresEvidence, !references.contains(where: isNonEmptyString) {
            diagnostics.append(
                diagnostic(
                    "relaymark.policy.evidence_required",
                    "\(block.type) requires at least one evidence reference."
                )
            )
        }

        if !references.isEmpty {
            diagnostics.append(
                contentsOf: evidenceReferenceListDiagnostics(
                    for: block,
                    references: references,
                    evidenceTargets: evidenceTargets
                )
            )
        }

        switch block.type {
        case "relay.action_row":
            diagnostics.append(contentsOf: actionProposalDiagnostics(for: block))
        case "relay.source_bundle":
            diagnostics.append(contentsOf: sourceBundleDiagnostics(for: block))
        case "relay.evidence_ref":
            diagnostics.append(
                contentsOf: evidenceReferenceDiagnostics(
                    for: block,
                    scriptureResources: scriptureResources
                )
            )
        case "relay.claim":
            diagnostics.append(contentsOf: claimConfidenceDiagnostics(for: block))
        case "relay.comparison":
            diagnostics.append(contentsOf: comparisonDiagnostics(for: block))
        default:
            break
        }

        return diagnostics
    }

    private static func attributeDiagnostics(
        _ value: RelayMarkValue,
        named name: String,
        on type: String,
        kind: DirectiveAttributeKind
    ) -> [RelayMarkDiagnostic] {
        switch kind {
        case .enumeration(let values):
            guard
                let string = value.stringValue,
                values.contains(string)
            else {
                return [
                    diagnostic(
                        "relaymark.attribute.enum",
                        "\(type).\(name) must be one of \(values.joined(separator: ", "))."
                    )
                ]
            }
        case .stringArray:
            guard let values = value.arrayValue else {
                return [
                    diagnostic(
                        "relaymark.attribute.array",
                        "\(type).\(name) must be an array."
                    )
                ]
            }

            guard values.allSatisfy({ $0.stringValue != nil }) else {
                return [
                    diagnostic(
                        "relaymark.attribute.array_items",
                        "\(type).\(name) must contain only strings."
                    )
                ]
            }
        case .integer:
            guard integerValue(value) != nil else {
                return [
                    diagnostic(
                        "relaymark.attribute.integer",
                        "\(type).\(name) must be an integer."
                    )
                ]
            }
        case .number:
            guard value.numberValue != nil else {
                return [
                    diagnostic(
                        "relaymark.attribute.number",
                        "\(type).\(name) must be a number."
                    )
                ]
            }
        case .boolean:
            guard value.boolValue != nil else {
                return [
                    diagnostic(
                        "relaymark.attribute.boolean",
                        "\(type).\(name) must be a boolean."
                    )
                ]
            }
        case .object:
            guard value.objectValue != nil else {
                return [
                    diagnostic(
                        "relaymark.attribute.object",
                        "\(type).\(name) must be an object."
                    )
                ]
            }
        case .string:
            guard value.stringValue != nil else {
                return [
                    diagnostic(
                        "relaymark.attribute.string",
                        "\(type).\(name) must be a string."
                    )
                ]
            }
        }

        return []
    }

    private static func evidenceReferenceListDiagnostics(
        for block: RelayMarkBlock,
        references: [String],
        evidenceTargets: Set<String>
    ) -> [RelayMarkDiagnostic] {
        var diagnostics: [RelayMarkDiagnostic] = []

        for reference in references {
            guard isNonEmptyString(reference) else {
                diagnostics.append(
                    diagnostic(
                        "relaymark.evidence.invalid_reference",
                        "\(block.type) evidence references must be non-empty strings."
                    )
                )
                continue
            }

            if !evidenceTargets.contains(reference) {
                diagnostics.append(
                    diagnostic(
                        "relaymark.evidence.unresolved_reference",
                        "\(block.type) evidence reference '\(reference)' does not resolve."
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

    private static func actionProposalDiagnostics(
        for block: RelayMarkBlock
    ) -> [RelayMarkDiagnostic] {
        let props = block.props
        let lifecycleFields = [
            "proposal_record_id",
            "proposal_revision",
            "decision_id",
            "execution_id",
            "undo_id"
        ]
        let lifecycleAware =
            props["review"]?.stringValue == "undone" ||
            props["proposal_id"] != nil ||
            lifecycleFields.contains(where: { props[$0] != nil })

        guard lifecycleAware else { return [] }

        guard isNonEmptyString(props["proposal_id"]?.stringValue) else {
            return [
                diagnostic(
                    "relaymark.action.proposal_id",
                    "relay.action_row lifecycle fields require a non-empty proposal_id."
                )
            ]
        }

        var diagnostics: [RelayMarkDiagnostic] = []

        if !isNonEmptyString(props["proposal_record_id"]?.stringValue) {
            diagnostics.append(
                diagnostic(
                    "relaymark.action.proposal_record_id",
                    "relay.action_row lifecycle fields require a non-empty proposal_record_id for authorized review and undo."
                )
            )
        } else if props["proposal_record_id"]?.stringValue == props["proposal_id"]?.stringValue {
            diagnostics.append(
                diagnostic(
                    "relaymark.action.proposal_identity",
                    "relay.action_row.proposal_record_id must be distinct from the generator/client proposal_id."
                )
            )
        }

        if integerValue(props["proposal_revision"]).map({ $0 >= 1 }) != true {
            diagnostics.append(
                diagnostic(
                    "relaymark.action.proposal_revision",
                    "relay.action_row.proposal_revision must be a positive integer for lifecycle-aware proposals."
                )
            )
        }

        for field in ["decision_id", "execution_id", "undo_id"]
        where props[field] != nil && !isNonEmptyString(props[field]?.stringValue) {
            diagnostics.append(
                diagnostic(
                    "relaymark.action.lifecycle_id",
                    "relay.action_row.\(field) must be a non-empty string when present."
                )
            )
        }

        switch props["review"]?.stringValue {
        case "draft", "ready":
            if ["decision_id", "execution_id", "undo_id"].contains(where: { props[$0] != nil }) {
                diagnostics.append(
                    diagnostic(
                        "relaymark.action.lifecycle_state",
                        "relay.action_row in \(props["review"]?.stringValue ?? "") review must not carry decision, execution, or undo ids."
                    )
                )
            }
        case "accepted":
            if
                !isNonEmptyString(props["decision_id"]?.stringValue) ||
                !isNonEmptyString(props["execution_id"]?.stringValue) ||
                props["undo_id"] != nil
            {
                diagnostics.append(
                    diagnostic(
                        "relaymark.action.lifecycle_state",
                        "Accepted relay.action_row proposals require decision_id and execution_id and must not carry undo_id."
                    )
                )
            }
        case "rejected":
            if
                !isNonEmptyString(props["decision_id"]?.stringValue) ||
                props["execution_id"] != nil ||
                props["undo_id"] != nil
            {
                diagnostics.append(
                    diagnostic(
                        "relaymark.action.lifecycle_state",
                        "Rejected relay.action_row proposals require decision_id and must not carry execution_id or undo_id."
                    )
                )
            }
        case "undone":
            if
                !isNonEmptyString(props["decision_id"]?.stringValue) ||
                !isNonEmptyString(props["execution_id"]?.stringValue) ||
                !isNonEmptyString(props["undo_id"]?.stringValue) ||
                props["decision_id"]?.stringValue == props["undo_id"]?.stringValue
            {
                diagnostics.append(
                    diagnostic(
                        "relaymark.action.lifecycle_state",
                        "Undone relay.action_row proposals retain the accept decision_id and execution_id and require a distinct undo_id."
                    )
                )
            }
        default:
            break
        }

        return diagnostics
    }

    private static func sourceBundleDiagnostics(
        for block: RelayMarkBlock
    ) -> [RelayMarkDiagnostic] {
        var diagnostics: [RelayMarkDiagnostic] = []

        if !isNonEmptyString(block.props["id"]?.stringValue) {
            diagnostics.append(
                diagnostic(
                    "relaymark.source_bundle.identity",
                    "relay.source_bundle requires a non-empty host id."
                )
            )
        }

        if
            let revision = block.props["revision"],
            integerValue(revision).map({ $0 >= 0 }) != true
        {
            diagnostics.append(
                diagnostic(
                    "relaymark.source_bundle.revision",
                    "relay.source_bundle.revision must be a non-negative integer."
                )
            )
        }

        return diagnostics
    }

    private static func claimConfidenceDiagnostics(
        for block: RelayMarkBlock
    ) -> [RelayMarkDiagnostic] {
        if
            let confidence = block.props["confidence"]?.numberValue,
            !confidence.isFinite || confidence < 0 || confidence > 1
        {
            return [
                diagnostic(
                    "relaymark.claim.confidence_range",
                    "relay.claim.confidence must be between 0.0 and 1.0."
                )
            ]
        }

        return []
    }

    private static func comparisonDiagnostics(
        for block: RelayMarkBlock
    ) -> [RelayMarkDiagnostic] {
        let subjects =
            block.props["subjects"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let criteria =
            block.props["criteria"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let validSubjects = subjects.filter(isNonEmptyString)
        let validCriteria = criteria.filter(isNonEmptyString)
        var diagnostics: [RelayMarkDiagnostic] = []

        if validSubjects.count < 2 || Set(validSubjects).count != validSubjects.count {
            diagnostics.append(
                diagnostic(
                    "relaymark.comparison.subjects",
                    "relay.comparison.subjects must contain at least two distinct, non-empty references."
                )
            )
        }

        if validCriteria.isEmpty || Set(validCriteria).count != validCriteria.count {
            diagnostics.append(
                diagnostic(
                    "relaymark.comparison.criteria",
                    "relay.comparison.criteria must contain at least one distinct, non-empty key."
                )
            )
        }

        if
            let preferred = block.props["preferred"]?.stringValue,
            !subjects.contains(preferred)
        {
            diagnostics.append(
                diagnostic(
                    "relaymark.comparison.preferred",
                    "relay.comparison.preferred must be one of relay.comparison.subjects."
                )
            )
        }

        if let values = block.props["values"]?.objectValue {
            for criterion in unique(validCriteria) {
                guard let criterionValues = values[criterion]?.objectValue else {
                    diagnostics.append(
                        diagnostic(
                            "relaymark.comparison.values_criterion",
                            "relay.comparison.values.\(criterion) must be an object keyed by subject reference."
                        )
                    )
                    continue
                }

                for subject in unique(validSubjects) where criterionValues[subject] == nil {
                    diagnostics.append(
                        diagnostic(
                            "relaymark.comparison.values_coverage",
                            "relay.comparison.values.\(criterion) must include '\(subject)' with a value or explicit null."
                        )
                    )
                }
            }
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

    private static func documentIdentityDiagnostics(
        for document: RelayMarkDocument
    ) -> [RelayMarkDiagnostic] {
        var evidenceIdentities: [String: String] = [:]
        var proposalIdentities: [String: String] = [:]
        var proposalRecordIdentities: [String: String] = [:]
        var decisionIdentities: [String: String] = [:]
        var executionIdentities: [String: String] = [:]
        var undoIdentities: [String: String] = [:]
        var diagnostics: [RelayMarkDiagnostic] = []

        visitBlocks(document.blocks) { block in
            if isNonEmptyString(block.id), evidenceIdentities[block.id] == nil {
                evidenceIdentities[block.id] = "AST block '\(block.id)'"
            }
        }

        for resource in document.resources {
            registerDocumentIdentity(
                resource.id,
                namespace: "evidence",
                origin: "resource '\(resource.id)'",
                identities: &evidenceIdentities,
                diagnostics: &diagnostics
            )
        }

        visitBlocks(document.blocks) { block in
            if block.type == "relay.source_bundle" || block.type == "relay.evidence_ref" {
                let value = block.props["id"]?.stringValue

                if value != block.id {
                    registerDocumentIdentity(
                        value,
                        namespace: "evidence",
                        origin: "\(block.type).props.id on block '\(block.id)'",
                        identities: &evidenceIdentities,
                        diagnostics: &diagnostics
                    )
                }
            }

            guard block.type == "relay.action_row" else { return }

            for (field, namespace) in [
                ("proposal_id", "proposal"),
                ("proposal_record_id", "proposal_record"),
                ("decision_id", "decision"),
                ("execution_id", "execution"),
                ("undo_id", "undo")
            ] {
                let origin = "relay.action_row.\(field) on block '\(block.id)'"

                switch namespace {
                case "proposal":
                    registerDocumentIdentity(
                        block.props[field]?.stringValue,
                        namespace: namespace,
                        origin: origin,
                        identities: &proposalIdentities,
                        diagnostics: &diagnostics
                    )
                case "proposal_record":
                    registerDocumentIdentity(
                        block.props[field]?.stringValue,
                        namespace: namespace,
                        origin: origin,
                        identities: &proposalRecordIdentities,
                        diagnostics: &diagnostics
                    )
                case "decision":
                    registerDocumentIdentity(
                        block.props[field]?.stringValue,
                        namespace: namespace,
                        origin: origin,
                        identities: &decisionIdentities,
                        diagnostics: &diagnostics
                    )
                case "execution":
                    registerDocumentIdentity(
                        block.props[field]?.stringValue,
                        namespace: namespace,
                        origin: origin,
                        identities: &executionIdentities,
                        diagnostics: &diagnostics
                    )
                case "undo":
                    registerDocumentIdentity(
                        block.props[field]?.stringValue,
                        namespace: namespace,
                        origin: origin,
                        identities: &undoIdentities,
                        diagnostics: &diagnostics
                    )
                default:
                    break
                }
            }
        }

        return diagnostics
    }

    private static func registerDocumentIdentity(
        _ value: String?,
        namespace: String,
        origin: String,
        identities: inout [String: String],
        diagnostics: inout [RelayMarkDiagnostic]
    ) {
        guard let value, isNonEmptyString(value) else { return }

        if let prior = identities[value] {
            diagnostics.append(
                diagnostic(
                    "relaymark.identity.duplicate_\(namespace)",
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

    private static func schemaDiagnostic() -> RelayMarkDiagnostic {
        diagnostic(
            "relaymark.schema.invalid",
            "Document does not conform to the RelayMark document schema."
        )
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
        self.entityReferences = []
        self.propertySheets = []
        self.dataViews = []
        self.layouts = []
        self.capabilities = []
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
