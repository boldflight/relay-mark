import { directiveForType } from "./registry.js";
import { isBlockNode } from "./node-kind.js";

const fallbackKinds = new Set(["children", "plain_text", "summary", "omit"]);

/**
 * Resolves registry-owned renderer requirements without executing or mutating a document.
 * Unsupported blocks remain explicit and receive the directive's deterministic fallback.
 */
export function negotiateRendererCapabilities(document, supported = []) {
  const supportedSet = new Set(supported);
  const resolutions = [];

  visitBlocks(document.blocks || [], (block) => {
    const directive = directiveForType(block.type);
    if (!directive?.capability) return;

    const fallback = fallbackKinds.has(directive.fallback)
      ? directive.fallback
      : "plain_text";

    resolutions.push({
      block_id: block.id,
      capability: directive.capability,
      supported: supportedSet.has(directive.capability),
      disposition: supportedSet.has(directive.capability) ? "render" : fallback
    });
  });

  return resolutions;
}

function visitBlocks(blocks, visitor) {
  for (const block of blocks) {
    visitor(block);
    if (Array.isArray(block.content)) {
      visitBlocks(block.content.filter(isBlockNode), visitor);
    }
  }
}
