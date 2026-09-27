import { directiveForType } from "./registry.js";
import { isBlockNode } from "./node-kind.js";
import { sourceForV3Atom } from "./collaboration-atoms-v3.js";
import { assertV3EntityReferenceProps } from "./collaboration-entity-reference-v3.js";
import { assertV3PaperControlProps } from "./collaboration-paper-controls-v3.js";

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
  if (block.type === "relay.paper_control") {
    const { source } = assertV3PaperControlProps(block.props);
    if (!Array.isArray(block.content) || block.content.length !== 0) throw new TypeError("Paper control cannot have children");
    return source;
  }
  if (block.type === "relay.entity_reference" && block.props?.source !== undefined) {
    const authored = assertV3EntityReferenceProps(block.props);
    const content = block.content || [];
    const parsedBody = content.length === 1 && content[0].type === "paragraph" &&
      content[0].content?.length === 1 && content[0].content[0].type === "text" &&
      content[0].content[0].text === authored.body;
    if (content.length !== 0 && !parsedBody) {
      throw new TypeError("Entity reference source/content mismatch");
    }
    return authored.source;
  }
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
    // The reference source parser does not reconstruct rich inline wrappers or
    // hard breaks yet. Flattening them would turn a valid collaborative AST
    // into different authored content on a later source import.
    throw new TypeError(`Cannot losslessly serialize inline type '${String(node.type)}' to RelayMark source.`);
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
