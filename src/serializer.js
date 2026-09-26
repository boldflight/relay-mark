import { directiveForType } from "./registry.js";
import { isBlockNode } from "./node-kind.js";
import { sourceForV3Atom } from "./collaboration-atoms-v3.js";

/** Serializes the supported human-authored subset to one deterministic source form. */
export function serializeRelayMark(document) {
  const sections = [];
  const frontmatter = document.frontmatter || {};

  if (Object.keys(frontmatter).length > 0) {
    const lines = Object.entries(frontmatter)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, value]) => `${key}: ${serializeFrontmatterValue(value)}`);
    sections.push(`---\n${lines.join("\n")}\n---`);
  }

  sections.push((document.blocks || []).map(serializeBlock).join("\n\n"));
  return `${sections.filter(Boolean).join("\n\n")}\n`;
}

function serializeBlock(block) {
  if (block.type === "heading") {
    return `${"#".repeat(block.props?.level || 1)} ${serializeInline(block.content || [])}`;
  }

  if (block.type === "paragraph") {
    return serializeInline(block.content || []);
  }

  const directive = directiveForType(block.type);
  if (!directive) throw new Error(`Cannot serialize unknown RelayMark block type '${block.type}'.`);

  const attributes = Object.entries(block.props || {})
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, value]) => `${key}: ${serializeValue(value)}`)
    .join(", ");
  const header = attributes ? `@${directive.name}(${attributes})` : `@${directive.name}`;
  const childBlocks = (block.content || []).filter(isBlockNode);
  const body = childBlocks.length > 0
    ? childBlocks.map(serializeBlock).join("\n\n")
    : serializeInline(block.content || []);

  return `${header} {\n${indent(body)}\n}`;
}

function serializeInline(nodes) {
  return nodes.map((node) => {
    if (node.type === "text") return node.text || "";
    if ((node.type === "relay.entity_ref" || node.type === "relay.tag_ref") &&
        node.props && Object.keys(node.props).length > 0) {
      return sourceForV3Atom(node);
    }
    if (node.type?.startsWith("relay.") && node.type.endsWith("_ref")) {
      const kind = node.type.slice("relay.".length, -"_ref".length);
      return `[${node.label || node.id || "reference"}](relay:${kind}/${node.id || ""})`;
    }
    if (Array.isArray(node.content)) return serializeInline(node.content);
    return node.text || node.label || "";
  }).join("");
}

function serializeFrontmatterValue(value) {
  return typeof value === "string" && /^[A-Za-z0-9._:-]+$/u.test(value)
    ? value
    : JSON.stringify(value);
}

function serializeValue(value) {
  if (Array.isArray(value)) return `[${value.map(serializeValue).join(", ")}]`;
  if (value && typeof value === "object") {
    return `{${Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => `${JSON.stringify(key)}: ${serializeValue(item)}`)
      .join(", ")}}`;
  }
  return JSON.stringify(value);
}

function indent(value) {
  return value.split("\n").map((line) => line ? `  ${line}` : "").join("\n");
}
