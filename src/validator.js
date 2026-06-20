import { directiveForType } from "./registry.js";

export function validateDocument(document) {
  const diagnostics = [];

  if (document.type !== "relaymark.document") {
    diagnostics.push(error("relaymark.document.type", "Document type must be relaymark.document."));
  }

  if (!Number.isInteger(document.version) || document.version < 1) {
    diagnostics.push(error("relaymark.document.version", "Document version must be a positive integer."));
  }

  const seenIds = new Set();

  for (const block of document.blocks || []) {
    validateBlock(block, diagnostics, seenIds);
  }

  return diagnostics;
}

export function validateDirectiveNode(block) {
  const diagnostics = [];
  validateRelayBlock(block, diagnostics);
  return diagnostics;
}

function validateBlock(block, diagnostics, seenIds) {
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
    validateRelayBlock(block, diagnostics);
  }

  for (const child of block.content || []) {
    if (child && typeof child === "object" && "id" in child && "type" in child) {
      validateBlock(child, diagnostics, seenIds);
    }
  }
}

function validateRelayBlock(block, diagnostics) {
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
