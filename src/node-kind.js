import { directiveForType } from "./registry.js";

const commonMarkInlineTypes = new Set([
  "text",
  "hard_break",
  "soft_break",
  "link",
  "emphasis",
  "strong",
  "strikethrough",
  "code_span"
]);

export function isInlineNode(node) {
  if (!node || typeof node !== "object" || typeof node.type !== "string") {
    return false;
  }

  if (commonMarkInlineTypes.has(node.type)) {
    return true;
  }

  return node.type.startsWith("relay.") && node.type.endsWith("_ref") && !directiveForType(node.type);
}

export function isBlockNode(node) {
  return (
    node &&
    typeof node === "object" &&
    typeof node.type === "string" &&
    !isInlineNode(node)
  );
}
