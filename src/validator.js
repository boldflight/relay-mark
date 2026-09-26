import { createHash } from "node:crypto";
import { directiveForType } from "./registry.js";
import { isBlockNode } from "./node-kind.js";

export function validateDocument(document, validationContext = {}) {
  const diagnostics = [];

  if (document.type !== "relaymark.document") {
    diagnostics.push(error("relaymark.document.type", "Document type must be relaymark.document."));
  }

  if (!Number.isInteger(document.version) || document.version < 1) {
    diagnostics.push(error("relaymark.document.version", "Document version must be a positive integer."));
  }

  const seenIds = new Set();
  const evidenceTargets = collectEvidenceTargets(document);
  const scriptureResources = collectScriptureResources(document);

  validateScriptureResources(document, diagnostics);

  for (const block of document.blocks || []) {
    validateBlock(block, diagnostics, seenIds, evidenceTargets, scriptureResources);
  }

  validateAgentAnswerProfile(document, diagnostics, validationContext);
  validateDocumentIdentities(document, diagnostics);

  return diagnostics;
}

export function validateDirectiveNode(block) {
  const diagnostics = [];
  validateRelayBlock(block, diagnostics, null);
  return diagnostics;
}

function validateBlock(block, diagnostics, seenIds, evidenceTargets, scriptureResources, parentType = null, taskDepth = 0) {
  if (!block.id) {
    diagnostics.push(error("relaymark.block.id", "Every block must have an id."));
  } else if (seenIds.has(block.id)) {
    diagnostics.push(error("relaymark.block.duplicate_id", `Duplicate block id '${block.id}'.`));
  } else {
    seenIds.add(block.id);
  }

  if (!block.type) {
    diagnostics.push(error("relaymark.block.type", `Block '${block.id || "unknown"}' must have a type.`));
  }

  if (block.type?.startsWith("relay.")) {
    validateRelayBlock(block, diagnostics, evidenceTargets, scriptureResources);
  }

  if (block.type === "relay.callout") {
    const children = block.content || [];
    const titles = children.filter((child) => child.type === "relay.callout_title");
    if (titles.length > 1 || (titles.length === 1 && children[0] !== titles[0]) ||
        children.length <= titles.length) {
      diagnostics.push(error("relaymark.callout.children", "Callout needs body blocks and at most one first title."));
    }
  }
  if (block.type === "relay.callout_title" && parentType !== "relay.callout") {
    diagnostics.push(error("relaymark.callout.title_parent", "Callout title must be a direct callout child."));
  }

  if (block.type === "task_list") {
    if (taskDepth >= 16 || !Array.isArray(block.content) || block.content.length < 1 ||
        block.content.length > 4_096 || block.content.some(child => child?.type !== "task_item")) {
      diagnostics.push(error("relaymark.task_list.children", "Task list needs task items within the depth and size limits."));
    }
    if (block.props !== undefined && Object.keys(block.props).length > 0) {
      diagnostics.push(error("relaymark.task_list.props", "Task list has no properties."));
    }
  }
  if (block.type === "task_item") {
    const props = block.props || {};
    const validEntity = props.entityId === null ||
      (typeof props.entityId === "string" &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u.test(props.entityId));
    if (typeof props.checked !== "boolean" || !validEntity ||
        Object.keys(props).some(key => key !== "checked" && key !== "entityId")) {
      diagnostics.push(error("relaymark.task_item.props", "Task item needs checked and canonical entityId properties."));
    }
    if (parentType !== "task_list" || !Array.isArray(block.content) || block.content.length < 1 ||
        block.content.length > 4_096 || block.content[0]?.type !== "paragraph" ||
        block.content.slice(1).some(child => !["paragraph", "task_list", "list"].includes(child?.type))) {
      diagnostics.push(error("relaymark.task_item.children", "Task item needs a first paragraph and supported child blocks."));
    }
  }

  for (const child of block.content || []) {
    if (isBlockNode(child)) {
      validateBlock(child, diagnostics, seenIds, evidenceTargets, scriptureResources, block.type,
        taskDepth + (block.type === "task_list" ? 1 : 0));
    }
  }
}

function validateRelayBlock(block, diagnostics, evidenceTargets, scriptureResources) {
  const directive = directiveForType(block.type);

  if (!directive) {
    diagnostics.push(error("relaymark.directive.unknown_type", `Unknown Relay block type '${block.type}'.`));
    return;
  }

  for (const [name, attribute] of Object.entries(directive.attributes || {})) {
    const value = block.props?.[name];

    if (attribute.required && value === undefined) {
      diagnostics.push(error("relaymark.attribute.required", `${block.type}.${name} is required.`));
      continue;
    }

    if (value !== undefined) {
      validateAttribute(block.type, name, value, attribute, diagnostics);
    }
  }

  for (const name of Object.keys(block.props || {})) {
    if (!Object.hasOwn(directive.attributes || {}, name)) {
      diagnostics.push(
        error("relaymark.attribute.unknown", `${block.type}.${name} is not declared by the directive contract.`)
      );
    }
  }

  if (directive.policy?.requires_review && block.props?.review === undefined) {
    diagnostics.push(error("relaymark.policy.review_required", `${block.type} requires a review state.`));
  }

  const evidenceRefs = evidenceRefsFor(block);

  if (directive.policy?.requires_evidence) {
    if (!evidenceRefs.some(nonEmptyString)) {
      diagnostics.push(error("relaymark.policy.evidence_required", `${block.type} requires at least one evidence reference.`));
    }
  }

  if (evidenceRefs.length > 0) {
    validateEvidenceReferences(block, evidenceRefs, evidenceTargets, diagnostics);
  }

  if (block.type === "relay.action_row") {
    validateActionProposal(block, diagnostics);
  }

  if (block.type === "relay.source_bundle") {
    validateSourceBundle(block, diagnostics);
  }

  if (block.type === "relay.evidence_ref") {
    validateEvidenceRef(block, diagnostics, scriptureResources);
  }

  if (block.type === "relay.claim") {
    validateClaim(block, diagnostics);
  }

  if (block.type === "relay.comparison") {
    validateComparison(block, diagnostics);
  }

  if (block.type === "relay.entity_reference") {
    validateEntityReference(block, diagnostics);
  }

  if (block.type === "relay.video_embed") {
    if (typeof block.props?.videoId !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u.test(block.props.videoId)) {
      diagnostics.push(error("relaymark.video_embed.id", "relay.video_embed.videoId must be a canonical lowercase UUID."));
    }
    if ((block.content || []).length !== 0) {
      diagnostics.push(error("relaymark.video_embed.children", "relay.video_embed cannot have children."));
    }
  }

  if (block.type === "relay.property_sheet") {
    validatePropertySheet(block, diagnostics);
  }

  if (block.type === "relay.data_view") {
    validateDataView(block, diagnostics);
  }

  if (block.type === "relay.layout") {
    validateLayout(block, diagnostics);
  }
}

function validateEntityReference(block, diagnostics) {
  if (!nonEmptyString(block.props?.id)) {
    diagnostics.push(
      error("relaymark.entity_reference.id", "relay.entity_reference.id must be a non-empty host reference.")
    );
  }
}

function validatePropertySheet(block, diagnostics) {
  validateBindingAddress(block.props?.binding, "relay.property_sheet.binding", diagnostics);
  validateDistinctKeys(block.props?.fields, "relay.property_sheet.fields", diagnostics);
}

function validateDataView(block, diagnostics) {
  validateBindingAddress(block.props?.source, "relay.data_view.source", diagnostics);

  for (const [field, value] of [
    ["columns", block.props?.columns],
    ["sort", block.props?.sort]
  ]) {
    if (value !== undefined) validateDistinctKeys(value, `relay.data_view.${field}`, diagnostics);
  }

  if (block.props?.group !== undefined && !bindingSegment(block.props.group)) {
    diagnostics.push(
      error("relaymark.data_view.group", "relay.data_view.group must be a host field key.")
    );
  }

  const limit = block.props?.limit;
  if (limit !== undefined && (!Number.isInteger(limit) || limit < 1 || limit > 1000)) {
    diagnostics.push(
      error("relaymark.data_view.limit", "relay.data_view.limit must be an integer from 1 through 1000.")
    );
  }
}

function validateLayout(block, diagnostics) {
  const columns = block.props?.columns;

  if (columns !== undefined && (!Number.isInteger(columns) || columns < 1 || columns > 4)) {
    diagnostics.push(
      error("relaymark.layout.columns", "relay.layout.columns must be an integer from 1 through 4.")
    );
  }
}

function validateBindingAddress(value, label, diagnostics) {
  if (!nonEmptyString(value) || !/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/u.test(value)) {
    diagnostics.push(
      error("relaymark.binding.invalid", `${label} must be a dotted host binding address.`)
    );
  }
}

function validateDistinctKeys(value, label, diagnostics) {
  if (
    !Array.isArray(value) ||
    value.length === 0 ||
    value.some((item) => !bindingSegment(item)) ||
    new Set(value).size !== value.length
  ) {
    diagnostics.push(
      error("relaymark.binding.keys", `${label} must contain distinct, non-empty host field keys.`)
    );
  }
}

function bindingSegment(value) {
  return nonEmptyString(value) && /^-?[a-z][a-z0-9_]*$/u.test(value);
}

function validateActionProposal(block, diagnostics) {
  const props = block.props || {};

  if (!nonEmptyString(props.action) || !/^[a-z][a-z0-9_.-]*$/u.test(props.action)) {
    diagnostics.push(
      error("relaymark.action.id", "relay.action_row.action must be a stable registered action id.")
    );
  }
  const lifecycleFields = ["proposal_record_id", "proposal_revision", "decision_id", "execution_id", "undo_id"];
  const lifecycleAware =
    props.review === "undone" ||
    props.proposal_id !== undefined ||
    lifecycleFields.some((field) => props[field] !== undefined);

  if (!lifecycleAware) return;

  if (!nonEmptyString(props.proposal_id)) {
    diagnostics.push(
      error("relaymark.action.proposal_id", "relay.action_row lifecycle fields require a non-empty proposal_id.")
    );
    return;
  }

  if (!nonEmptyString(props.proposal_record_id)) {
    diagnostics.push(
      error(
        "relaymark.action.proposal_record_id",
        "relay.action_row lifecycle fields require a non-empty proposal_record_id for authorized review and undo."
      )
    );
  } else if (props.proposal_record_id === props.proposal_id) {
    diagnostics.push(
      error(
        "relaymark.action.proposal_identity",
        "relay.action_row.proposal_record_id must be distinct from the generator/client proposal_id."
      )
    );
  }

  if (!Number.isInteger(props.proposal_revision) || props.proposal_revision < 1) {
    diagnostics.push(
      error(
        "relaymark.action.proposal_revision",
        "relay.action_row.proposal_revision must be a positive integer for lifecycle-aware proposals."
      )
    );
  }

  for (const field of ["decision_id", "execution_id", "undo_id"]) {
    if (props[field] !== undefined && !nonEmptyString(props[field])) {
      diagnostics.push(
        error("relaymark.action.lifecycle_id", `relay.action_row.${field} must be a non-empty string when present.`)
      );
    }
  }

  if (["draft", "ready"].includes(props.review)) {
    if (["decision_id", "execution_id", "undo_id"].some((field) => props[field] !== undefined)) {
      diagnostics.push(
        error(
          "relaymark.action.lifecycle_state",
          `relay.action_row in ${props.review} review must not carry decision, execution, or undo ids.`
        )
      );
    }

    return;
  }

  if (props.review === "accepted") {
    if (!nonEmptyString(props.decision_id) || !nonEmptyString(props.execution_id) || props.undo_id !== undefined) {
      diagnostics.push(
        error(
          "relaymark.action.lifecycle_state",
          "Accepted relay.action_row proposals require decision_id and execution_id and must not carry undo_id."
        )
      );
    }

    return;
  }

  if (props.review === "rejected") {
    if (!nonEmptyString(props.decision_id) || props.execution_id !== undefined || props.undo_id !== undefined) {
      diagnostics.push(
        error(
          "relaymark.action.lifecycle_state",
          "Rejected relay.action_row proposals require decision_id and must not carry execution_id or undo_id."
        )
      );
    }

    return;
  }

  if (props.review === "undone") {
    if (
      !nonEmptyString(props.decision_id) ||
      !nonEmptyString(props.execution_id) ||
      !nonEmptyString(props.undo_id) ||
      props.decision_id === props.undo_id
    ) {
      diagnostics.push(
        error(
          "relaymark.action.lifecycle_state",
          "Undone relay.action_row proposals retain the accept decision_id and execution_id and require a distinct undo_id."
        )
      );
    }
  }
}

function validateSourceBundle(block, diagnostics) {
  if (!nonEmptyString(block.props?.id)) {
    diagnostics.push(
      error("relaymark.source_bundle.identity", "relay.source_bundle requires a non-empty host id.")
    );
  }

  const revision = block.props?.revision;

  if (revision !== undefined && (!Number.isInteger(revision) || revision < 0)) {
    diagnostics.push(
      error("relaymark.source_bundle.revision", "relay.source_bundle.revision must be a non-negative integer.")
    );
  }
}

function validateEvidenceRef(block, diagnostics, scriptureResources) {
  const props = block.props || {};

  if (!nonEmptyString(props.id) || !nonEmptyString(props.source)) {
    diagnostics.push(
      error(
        "relaymark.evidence.identity",
        "relay.evidence_ref requires non-empty id and source values."
      )
    );
  }

  for (const field of ["source_type", "source_revision"]) {
    if (props[field] !== undefined && !nonEmptyString(props[field])) {
      diagnostics.push(
        error("relaymark.evidence.source", `relay.evidence_ref.${field} must be a non-empty string when present.`)
      );
    }
  }

  if (props.source_type === "scripture") {
    validateScriptureEvidenceRef(block, scriptureResources, diagnostics);
  }
}

function validateScriptureResources(document, diagnostics) {
  for (const resource of document.resources || []) {
    if (resource?.type !== "scripture") continue;

    const props = resource.props || {};

    for (const field of [
      "profile",
      "translation_id",
      "edition_id",
      "corpus_release_id",
      "versification_id",
      "attribution"
    ]) {
      if (!nonEmptyString(props[field])) {
        diagnostics.push(
          error("relaymark.scripture.release", `scripture resource '${resource.id || "unknown"}' requires ${field}.`)
        );
      }
    }

    if (props.profile !== "relaymark.scripture_release.v1") {
      diagnostics.push(
        error(
          "relaymark.scripture.release_profile",
          `scripture resource '${resource.id || "unknown"}' must use relaymark.scripture_release.v1.`
        )
      );
    }

    validateRequiredStringObject(
      props.source,
      ["name", "uri", "digest"],
      "source",
      resource.id,
      diagnostics
    );
    validateRequiredStringObject(
      props.license,
      ["id", "name", "url"],
      "license",
      resource.id,
      diagnostics
    );
    validateRequiredStringObject(
      props.provenance,
      ["coordinate_inventory_digest", "normalized_index_input_digest"],
      "provenance",
      resource.id,
      diagnostics
    );
    validateDigest(props.source?.digest, "source.digest", resource.id, diagnostics);
    validateDigest(
      props.provenance?.coordinate_inventory_digest,
      "provenance.coordinate_inventory_digest",
      resource.id,
      diagnostics
    );
    validateDigest(
      props.provenance?.normalized_index_input_digest,
      "provenance.normalized_index_input_digest",
      resource.id,
      diagnostics
    );

    if (props.provenance?.source_archive_digest !== undefined) {
      validateDigest(
        props.provenance.source_archive_digest,
        "provenance.source_archive_digest",
        resource.id,
        diagnostics
      );
    }

    if (!["private", "org", "unlisted", "public"].includes(resource.scope)) {
      diagnostics.push(
        error(
          "relaymark.scripture.release_scope",
          `scripture resource '${resource.id || "unknown"}' requires an explicit valid scope.`
        )
      );
    }
  }
}

function validateScriptureEvidenceRef(block, scriptureResources, diagnostics) {
  const props = block.props || {};
  const matches = scriptureResources?.get(props.source) || [];

  if (matches.length !== 1) {
    diagnostics.push(
      error(
        "relaymark.scripture.source_resolution",
        `relay.evidence_ref scripture source '${props.source || ""}' must resolve to exactly one scripture resource.`
      )
    );
    return;
  }

  const resource = matches[0];
  const release = resource.props || {};

  if (props.source_revision !== release.corpus_release_id) {
    diagnostics.push(
      error(
        "relaymark.scripture.source_revision",
        "relay.evidence_ref.source_revision must equal the scripture resource corpus_release_id."
      )
    );
  }

  if (!scopeAllows(resource.scope, props.scope)) {
    diagnostics.push(
      error(
        "relaymark.scripture.scope",
        "relay.evidence_ref scope must not be broader than its scripture resource scope."
      )
    );
  }

  const selector = props.selector;

  if (!selector || typeof selector !== "object" || Array.isArray(selector)) {
    diagnostics.push(
      error("relaymark.scripture.selector", "Scripture evidence requires a scripture span selector.")
    );
    return;
  }

  if (selector.profile !== "relaymark.scripture_span.v1") {
    diagnostics.push(
      error(
        "relaymark.scripture.selector_profile",
        "Scripture evidence selector must use relaymark.scripture_span.v1."
      )
    );
  }

  const startValid = validateScriptureCoordinate(selector.start, "start", diagnostics);
  const endValid = validateScriptureCoordinate(selector.end, "end", diagnostics);

  if (
    startValid &&
    endValid &&
    (selector.start.book_id !== selector.end.book_id ||
      selector.start.coordinate_kind !== selector.end.coordinate_kind)
  ) {
    diagnostics.push(
      error(
        "relaymark.scripture.span_boundary",
        "Scripture span start and end must use the same book and coordinate kind."
      )
    );
  }

  if (!sha256Digest(selector.content_digest)) {
    diagnostics.push(
      error(
        "relaymark.scripture.content_digest",
        "Scripture evidence requires a lowercase sha256 content_digest."
      )
    );
  }

  if (!nonEmptyString(plainText(block))) {
    diagnostics.push(
      error("relaymark.scripture.excerpt", "Scripture evidence requires a non-empty exact excerpt.")
    );
  }
}

function validateScriptureCoordinate(coordinate, endpoint, diagnostics) {
  if (!coordinate || typeof coordinate !== "object" || Array.isArray(coordinate)) {
    diagnostics.push(
      error("relaymark.scripture.coordinate", `Scripture selector ${endpoint} must be a coordinate object.`)
    );
    return false;
  }

  const kind = coordinate.coordinate_kind;
  const commonValid = nonEmptyString(coordinate.book_id) && nonEmptyString(coordinate.verse_label);
  let shapeValid = false;

  if (kind === "chapter") {
    shapeValid =
      Number.isInteger(coordinate.chapter) &&
      coordinate.chapter > 0 &&
      coordinate.section_id === undefined;
  } else if (kind === "section") {
    shapeValid = nonEmptyString(coordinate.section_id) && coordinate.chapter === undefined;
  }

  if (!commonValid || !shapeValid) {
    diagnostics.push(
      error(
        "relaymark.scripture.coordinate",
        `Scripture selector ${endpoint} must be a lossless chapter or section coordinate with a string verse_label.`
      )
    );
    return false;
  }

  return true;
}

function validateRequiredStringObject(value, fields, label, resourceId, diagnostics) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    diagnostics.push(
      error(
        "relaymark.scripture.release",
        `scripture resource '${resourceId || "unknown"}' requires a ${label} object.`
      )
    );
    return;
  }

  for (const field of fields) {
    if (!nonEmptyString(value[field])) {
      diagnostics.push(
        error(
          "relaymark.scripture.release",
          `scripture resource '${resourceId || "unknown"}' requires ${label}.${field}.`
        )
      );
    }
  }
}

function validateDigest(value, field, resourceId, diagnostics) {
  if (!sha256Digest(value)) {
    diagnostics.push(
      error(
        "relaymark.scripture.digest",
        `scripture resource '${resourceId || "unknown"}' requires ${field} as a lowercase sha256 digest.`
      )
    );
  }
}

function collectScriptureResources(document) {
  const resources = new Map();

  for (const resource of document.resources || []) {
    if (resource?.type !== "scripture" || !nonEmptyString(resource.id)) continue;
    const matches = resources.get(resource.id) || [];
    matches.push(resource);
    resources.set(resource.id, matches);
  }

  return resources;
}

function scopeAllows(resourceScope, evidenceScope) {
  const rank = new Map([
    ["private", 0],
    ["org", 1],
    ["unlisted", 2],
    ["public", 3]
  ]);

  return rank.has(resourceScope) && rank.has(evidenceScope) && rank.get(evidenceScope) <= rank.get(resourceScope);
}

function plainText(node) {
  if (!node) return "";
  if (Array.isArray(node)) return node.map(plainText).join("");
  if (node.type === "text") return node.text || "";
  if (Array.isArray(node.content)) return node.content.map(plainText).join("");
  return "";
}

function validateClaim(block, diagnostics) {
  const confidence = block.props?.confidence;

  if (
    typeof confidence === "number" &&
    (!Number.isFinite(confidence) || confidence < 0 || confidence > 1)
  ) {
    diagnostics.push(
      error("relaymark.claim.confidence_range", "relay.claim.confidence must be between 0.0 and 1.0.")
    );
  }
}

function validateAgentAnswerProfile(document, diagnostics, validationContext) {
  const frontmatter = document.frontmatter || {};

  if (frontmatter.profile !== "relaymark.agent_answer.v1") return;

  if (!nonEmptyString(frontmatter.title)) {
    diagnostics.push(
      error("relaymark.agent_answer.title", "relaymark.agent_answer.v1 requires a non-empty title.")
    );
  }

  if (!["private", "org", "unlisted", "public"].includes(frontmatter.scope)) {
    diagnostics.push(
      error(
        "relaymark.agent_answer.scope",
        "relaymark.agent_answer.v1 requires an explicit private, org, unlisted, or public scope."
      )
    );
  }

  if (!nonEmptyString(frontmatter.question)) {
    diagnostics.push(
      error("relaymark.agent_answer.question", "relaymark.agent_answer.v1 requires a non-empty exact question.")
    );
  } else {
    const expectedQuestionID = `sha256:${createHash("sha256").update(frontmatter.question, "utf8").digest("hex")}`;

    if (frontmatter.question_id !== expectedQuestionID) {
      diagnostics.push(
        error(
          "relaymark.agent_answer.question_id",
          "relaymark.agent_answer.v1 question_id must be the lowercase SHA-256 digest of the exact question UTF-8 bytes."
        )
      );
    }
  }

  if (!["answered", "refused"].includes(frontmatter.outcome)) {
    diagnostics.push(
      error(
        "relaymark.agent_answer.outcome",
        "relaymark.agent_answer.v1 outcome must be answered or refused."
      )
    );
    return;
  }

  if (frontmatter.outcome === "answered") {
    validateAnsweredAgentPaper(document, diagnostics, validationContext);
  } else {
    validateRefusedAgentPaper(document, diagnostics);
  }
}

function validateAnsweredAgentPaper(document, diagnostics, validationContext) {
  const blocks = document.blocks || [];
  const evidenceHeadingIndex = blocks.findIndex(
    (block) => headingLevel(block) === 2 && plainText(block) === "Evidence"
  );
  const claims = evidenceHeadingIndex > 1 ? blocks.slice(1, evidenceHeadingIndex) : [];
  const sourceBundles = evidenceHeadingIndex >= 0 ? blocks.slice(evidenceHeadingIndex + 1) : [];
  let levelOneHeadingCount = 0;
  let levelTwoHeadingCount = 0;

  visitBlocks(blocks, (block) => {
    if (headingLevel(block) === 1) levelOneHeadingCount += 1;
    if (headingLevel(block) === 2) levelTwoHeadingCount += 1;
  });

  const structureValid =
    blocks.length >= 4 &&
    headingLevel(blocks[0]) === 1 &&
    levelOneHeadingCount === 1 &&
    levelTwoHeadingCount === 1 &&
    claims.length > 0 &&
    claims.every((block) => block.type === "relay.claim") &&
    sourceBundles.length > 0 &&
    sourceBundles.every((block) => block.type === "relay.source_bundle");

  if (!structureValid) {
    diagnostics.push(
      error(
        "relaymark.agent_answer.answered_structure",
        "An answered relaymark.agent_answer.v1 paper requires one level-one heading, supported claims, an Evidence level-two heading, and source bundles in that order."
      )
    );
  }

  const evidenceCounts = new Map();
  const evidenceBlocks = new Map();

  for (const sourceBundle of sourceBundles.filter((block) => block.type === "relay.source_bundle")) {
    visitBlocks([sourceBundle], (block) => {
      if (block.type !== "relay.evidence_ref" || !nonEmptyString(block.props?.id)) return;
      evidenceCounts.set(block.props.id, (evidenceCounts.get(block.props.id) || 0) + 1);
      const blocksForID = evidenceBlocks.get(block.props.id) || [];
      blocksForID.push(block);
      evidenceBlocks.set(block.props.id, blocksForID);
    });
  }

  for (const claim of claims.filter((block) => block.type === "relay.claim")) {
    const refs = evidenceRefsFor(claim);
    const distinctRefs = new Set(refs);

    if (
      !nonEmptyString(claim.props?.key) ||
      claim.props?.status !== "supported" ||
      !nonEmptyString(plainText(claim))
    ) {
      diagnostics.push(
        error(
          "relaymark.agent_answer.claim",
          `Answered claim '${claim.id || "unknown"}' requires a non-empty key and text with supported status.`
        )
      );
    }

    if (
      refs.length === 0 ||
      distinctRefs.size !== refs.length ||
      refs.some((reference) => !nonEmptyString(reference) || evidenceCounts.get(reference) !== 1)
    ) {
      diagnostics.push(
        error(
          "relaymark.agent_answer.claim_evidence",
          `Answered claim '${claim.id || "unknown"}' must cite one or more unique concrete evidence refs that each resolve exactly once inside the paper's source bundles.`
        )
      );
    }
  }

  if (validationContext?.surface === "scripture_ask") {
    const hasInvalidScriptureEvidence = claims
      .filter((block) => block.type === "relay.claim")
      .some((claim) =>
        evidenceRefsFor(claim).some((reference) => {
          const matches = evidenceBlocks.get(reference) || [];
          return matches.length !== 1 || matches[0].props?.source_type !== "scripture";
        })
      );

    if (hasInvalidScriptureEvidence) {
      diagnostics.push(
        error(
          "relaymark.agent_answer.scripture_evidence",
          "A Scripture Ask host context requires every answered claim evidence ref to resolve to relay.evidence_ref source_type scripture."
        )
      );
    }
  }

  const forbiddenTypes = new Set(["relay.agent_suggestion", "relay.action_row"]);
  let containsForbiddenBlock = false;

  visitBlocks(blocks, (block) => {
    if (forbiddenTypes.has(block.type)) containsForbiddenBlock = true;
  });

  if (containsForbiddenBlock) {
    diagnostics.push(
      error(
        "relaymark.agent_answer.read_only",
        "An answered relaymark.agent_answer.v1 paper must not contain agent suggestions or action rows."
      )
    );
  }

  if (document.frontmatter?.refusal_reason !== undefined) {
    diagnostics.push(
      error(
        "relaymark.agent_answer.refusal_reason",
        "An answered relaymark.agent_answer.v1 paper must not contain refusal_reason."
      )
    );
  }
}

function validateRefusedAgentPaper(document, diagnostics) {
  const blocks = document.blocks || [];
  let nestedBlockCount = 0;
  let levelOneHeadingCount = 0;

  visitBlocks(blocks, (block) => {
    nestedBlockCount += 1;
    if (headingLevel(block) === 1) levelOneHeadingCount += 1;
  });

  if (document.frontmatter?.refusal_reason !== "insufficient_evidence") {
    diagnostics.push(
      error(
        "relaymark.agent_answer.refusal_reason",
        "A refused relaymark.agent_answer.v1 paper requires refusal_reason insufficient_evidence."
      )
    );
  }

  if (
    blocks.length !== 2 ||
    nestedBlockCount !== 2 ||
    headingLevel(blocks[0]) !== 1 ||
    levelOneHeadingCount !== 1 ||
    plainText(blocks[0]) !== "Answer unavailable" ||
    blocks[1]?.type !== "paragraph" ||
    !nonEmptyString(plainText(blocks[1]))
  ) {
    diagnostics.push(
      error(
        "relaymark.agent_answer.refused_structure",
        "A refused relaymark.agent_answer.v1 paper requires only an Answer unavailable level-one heading followed by one non-empty explanation paragraph."
      )
    );
  }

  const forbiddenTypes = new Set([
    "relay.claim",
    "relay.source_bundle",
    "relay.evidence_ref",
    "relay.agent_suggestion",
    "relay.action_row"
  ]);
  let containsForbiddenBlock = false;

  visitBlocks(blocks, (block) => {
    if (forbiddenTypes.has(block.type)) containsForbiddenBlock = true;
  });

  if (containsForbiddenBlock || (document.resources || []).length > 0) {
    diagnostics.push(
      error(
        "relaymark.agent_answer.refused_content",
        "A refused relaymark.agent_answer.v1 paper must not contain claims, sources, resources, evidence, suggestions, or actions."
      )
    );
  }
}

function headingLevel(block) {
  return block?.type === "heading" && Number.isInteger(block.props?.level) ? block.props.level : null;
}

function validateComparison(block, diagnostics) {
  const subjects = Array.isArray(block.props?.subjects) ? block.props.subjects : [];
  const criteria = Array.isArray(block.props?.criteria) ? block.props.criteria : [];
  const values = block.props?.values;
  const validSubjects = subjects.filter(nonEmptyString);
  const validCriteria = criteria.filter(nonEmptyString);

  if (validSubjects.length < 2 || new Set(validSubjects).size !== validSubjects.length) {
    diagnostics.push(
      error(
        "relaymark.comparison.subjects",
        "relay.comparison.subjects must contain at least two distinct, non-empty references."
      )
    );
  }

  if (validCriteria.length < 1 || new Set(validCriteria).size !== validCriteria.length) {
    diagnostics.push(
      error(
        "relaymark.comparison.criteria",
        "relay.comparison.criteria must contain at least one distinct, non-empty key."
      )
    );
  }

  const preferred = block.props?.preferred;

  if (typeof preferred === "string" && !subjects.includes(preferred)) {
    diagnostics.push(
      error("relaymark.comparison.preferred", "relay.comparison.preferred must be one of relay.comparison.subjects.")
    );
  }

  if (values && typeof values === "object" && !Array.isArray(values)) {
    for (const criterion of new Set(validCriteria)) {
      const criterionValues = values[criterion];

      if (!criterionValues || typeof criterionValues !== "object" || Array.isArray(criterionValues)) {
        diagnostics.push(
          error(
            "relaymark.comparison.values_criterion",
            `relay.comparison.values.${criterion} must be an object keyed by subject reference.`
          )
        );
        continue;
      }

      for (const subject of new Set(validSubjects)) {
        if (!Object.hasOwn(criterionValues, subject)) {
          diagnostics.push(
            error(
              "relaymark.comparison.values_coverage",
              `relay.comparison.values.${criterion} must include '${subject}' with a value or explicit null.`
            )
          );
        }
      }
    }
  }
}

function validateEvidenceReferences(block, evidenceRefs, evidenceTargets, diagnostics) {
  for (const reference of evidenceRefs) {
    if (!nonEmptyString(reference)) {
      diagnostics.push(
        error("relaymark.evidence.invalid_reference", `${block.type} evidence references must be non-empty strings.`)
      );
      continue;
    }

    if (evidenceTargets && !evidenceTargets.has(reference)) {
      diagnostics.push(
        error("relaymark.evidence.unresolved_reference", `${block.type} evidence reference '${reference}' does not resolve.`)
      );
    }
  }
}

function collectEvidenceTargets(document) {
  const targets = new Set();

  for (const resource of document.resources || []) {
    if (nonEmptyString(resource?.id)) targets.add(resource.id);
  }

  visitBlocks(document.blocks || [], (block) => {
    if (nonEmptyString(block.id)) targets.add(block.id);

    if (block.type === "relay.source_bundle" && nonEmptyString(block.props?.id)) {
      targets.add(block.props.id);
    }

    if (block.type === "relay.evidence_ref" && nonEmptyString(block.props?.id)) {
      targets.add(block.props.id);
    }

    if (block.type === "relay.transcript_segment" && nonEmptyString(block.props?.source)) {
      targets.add(block.props.source);
    }

    if (block.type === "relay.file_ref" && nonEmptyString(block.props?.id)) {
      targets.add(block.props.id);
    }

    if (block.type === "relay.note_ref") {
      if (nonEmptyString(block.props?.document)) targets.add(block.props.document);
      if (nonEmptyString(block.props?.block)) targets.add(block.props.block);
    }
  });

  return targets;
}

function validateDocumentIdentities(document, diagnostics) {
  const identities = {
    evidence: new Map(),
    proposal: new Map(),
    proposal_record: new Map(),
    decision: new Map(),
    execution: new Map(),
    undo: new Map()
  };

  visitBlocks(document.blocks || [], (block) => {
    if (nonEmptyString(block.id) && !identities.evidence.has(block.id)) {
      identities.evidence.set(block.id, `AST block '${block.id}'`);
    }
  });

  for (const resource of document.resources || []) {
    registerDocumentIdentity(
      identities.evidence,
      resource?.id,
      "evidence",
      `resource '${resource?.id}'`,
      diagnostics
    );
  }

  visitBlocks(document.blocks || [], (block) => {
    if (["relay.source_bundle", "relay.evidence_ref"].includes(block.type)) {
      if (block.props?.id !== block.id) {
        registerDocumentIdentity(
          identities.evidence,
          block.props?.id,
          "evidence",
          `${block.type}.props.id on block '${block.id}'`,
          diagnostics
        );
      }
    }

    if (block.type !== "relay.action_row") return;

    for (const [field, namespace] of [
      ["proposal_id", "proposal"],
      ["proposal_record_id", "proposal_record"],
      ["decision_id", "decision"],
      ["execution_id", "execution"],
      ["undo_id", "undo"]
    ]) {
      registerDocumentIdentity(
        identities[namespace],
        block.props?.[field],
        namespace,
        `relay.action_row.${field} on block '${block.id}'`,
        diagnostics
      );
    }
  });
}

function registerDocumentIdentity(registry, value, namespace, origin, diagnostics) {
  if (!nonEmptyString(value)) return;

  const prior = registry.get(value);

  if (prior) {
    diagnostics.push(
      error(
        `relaymark.identity.duplicate_${namespace}`,
        `Identity '${value}' is ambiguous between ${prior} and ${origin}.`
      )
    );
  } else {
    registry.set(value, origin);
  }
}

function visitBlocks(blocks, visitor) {
  for (const block of blocks) {
    visitor(block);

    for (const child of block.content || []) {
      if (isBlockNode(child)) visitBlocks([child], visitor);
    }
  }
}

function evidenceRefsFor(block) {
  if (Array.isArray(block.evidence_refs) && block.evidence_refs.length > 0) {
    return block.evidence_refs;
  }

  return Array.isArray(block.props?.evidence) ? block.props.evidence : [];
}

function nonEmptyString(value) {
  return (
    typeof value === "string" &&
    !/^[\u0009-\u000D\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]*$/u.test(
      value
    )
  );
}

function sha256Digest(value) {
  return typeof value === "string" && /^sha256:[0-9a-f]{64}$/u.test(value);
}

function validateAttribute(type, name, value, attribute, diagnostics) {
  if (attribute.type === "enum") {
    if (!attribute.values?.includes(value)) {
      diagnostics.push(error("relaymark.attribute.enum", `${type}.${name} must be one of ${attribute.values.join(", ")}.`));
    }

    return;
  }

  if (attribute.type === "array") {
    if (!Array.isArray(value)) {
      diagnostics.push(error("relaymark.attribute.array", `${type}.${name} must be an array.`));
    } else if (attribute.items === "string" && value.some((item) => typeof item !== "string")) {
      diagnostics.push(error("relaymark.attribute.array_items", `${type}.${name} must contain only strings.`));
    }

    return;
  }

  if (attribute.type === "integer") {
    if (!Number.isInteger(value)) {
      diagnostics.push(error("relaymark.attribute.integer", `${type}.${name} must be an integer.`));
    }

    return;
  }

  if (attribute.type === "number") {
    if (typeof value !== "number") {
      diagnostics.push(error("relaymark.attribute.number", `${type}.${name} must be a number.`));
    }

    return;
  }

  if (attribute.type === "boolean") {
    if (typeof value !== "boolean") {
      diagnostics.push(error("relaymark.attribute.boolean", `${type}.${name} must be a boolean.`));
    }

    return;
  }

  if (attribute.type === "object") {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      diagnostics.push(error("relaymark.attribute.object", `${type}.${name} must be an object.`));
    }

    return;
  }

  if (attribute.type === "string" && typeof value !== "string") {
    diagnostics.push(error("relaymark.attribute.string", `${type}.${name} must be a string.`));
  }
}

function error(code, message) {
  return { level: "error", code, message };
}
