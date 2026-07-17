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

  if (directive.policy?.requires_evidence) {
    const evidenceRefs = evidenceRefsFor(block);

    if (!evidenceRefs.some((reference) => typeof reference === "string" && reference.trim().length > 0)) {
      diagnostics.push(error("relaymark.policy.evidence_required", `${block.type} requires at least one evidence reference.`));
    }

    validateEvidenceReferences(block, evidenceRefs, evidenceTargets, diagnostics);
  }

  if (block.type === "relay.claim") {
    validateClaim(block, diagnostics);
  }

  if (block.type === "relay.comparison") {
    validateComparison(block, diagnostics);
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
