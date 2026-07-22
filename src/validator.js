import { directiveForType } from "./registry.js";
import { isBlockNode } from "./node-kind.js";

export function validateDocument(document) {
  const diagnostics = [];

  if (document.type !== "relaymark.document") {
    diagnostics.push(error("relaymark.document.type", "Document type must be relaymark.document."));
  }

  if (!Number.isInteger(document.version) || document.version < 1) {
    diagnostics.push(error("relaymark.document.version", "Document version must be a positive integer."));
  }

  const seenIds = new Set();
  const evidenceTargets = collectEvidenceTargets(document);

  for (const block of document.blocks || []) {
    validateBlock(block, diagnostics, seenIds, evidenceTargets);
  }

  validateDocumentIdentities(document, diagnostics);

  return diagnostics;
}

export function validateDirectiveNode(block) {
  const diagnostics = [];
  validateRelayBlock(block, diagnostics, null);
  return diagnostics;
}

function validateBlock(block, diagnostics, seenIds, evidenceTargets) {
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
    validateRelayBlock(block, diagnostics, evidenceTargets);
  }

  for (const child of block.content || []) {
    if (isBlockNode(child)) {
      validateBlock(child, diagnostics, seenIds, evidenceTargets);
    }
  }
}

function validateRelayBlock(block, diagnostics, evidenceTargets) {
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

  if (directive.policy?.requires_review && block.props?.review === undefined) {
    diagnostics.push(error("relaymark.policy.review_required", `${block.type} requires a review state.`));
  }

  const evidenceRefs = evidenceRefsFor(block);

  if (directive.policy?.requires_evidence) {

    if (!evidenceRefs.some((reference) => typeof reference === "string" && reference.trim().length > 0)) {
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
    validateEvidenceRef(block, diagnostics);
  }

  if (block.type === "relay.claim") {
    validateClaim(block, diagnostics);
  }

  if (block.type === "relay.comparison") {
    validateComparison(block, diagnostics);
  }
}

function validateActionProposal(block, diagnostics) {
  const props = block.props || {};
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

function validateEvidenceRef(block, diagnostics) {
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
}

function validateClaim(block, diagnostics) {
  const confidence = block.props?.confidence;

  if (typeof confidence === "number" && Number.isFinite(confidence) && (confidence < 0 || confidence > 1)) {
    diagnostics.push(
      error("relaymark.claim.confidence_range", "relay.claim.confidence must be between 0.0 and 1.0.")
    );
  }
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
  return typeof value === "string" && value.trim().length > 0;
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
