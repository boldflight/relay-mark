import { isBlockNode } from "./node-kind.js";

const roles = new Set(["authored", "source", "generated", "discussion", "ink"]);
const placements = new Set(["before", "after", "slot"]);
const fallbacks = new Set(["append_to_layer", "omit", "unresolved"]);
const anchorStates = new Set(["present", "absent", "stale", "undisclosed"]);

/**
 * Deterministically composes already-authorized layer contributions into a linear list.
 * It never performs authorization and never copies the result back into authored source.
 */
export function composeLayerContributions(layers) {
  const diagnostics = [];
  const items = [];
  const orderedLayers = [...(layers || [])].sort(compareRankAndID);

  for (const layer of orderedLayers) {
    if (!roles.has(layer.role)) {
      diagnostics.push(error("relaymark.layer.role", `Layer '${layer.id || "unknown"}' has an unsupported semantic role.`));
      continue;
    }

    for (const item of [...(layer.items || [])].sort(compareRankAndID)) {
      if (!isBlockNode(item.block)) {
        diagnostics.push(error("relaymark.layer.block", `Layer item '${item.id || "unknown"}' must contain one RelayMark block.`));
        continue;
      }

      const contribution = {
        layer_id: layer.id,
        layer_role: layer.role,
        item_id: item.id,
        block: item.block
      };

      if (!item.placement || item.placement.kind === "slot") {
        items.push(contribution);
        continue;
      }

      const { kind, anchor, anchor_state: anchorState = "present", fallback = "unresolved" } = item.placement;

      if (!placements.has(kind) || !anchorStates.has(anchorState) || !fallbacks.has(fallback)) {
        diagnostics.push(error("relaymark.layer.placement", `Layer item '${item.id || "unknown"}' has invalid placement metadata.`));
        continue;
      }

      const anchorIndex = anchorState === "present"
        ? items.findIndex(({ block }) => block.id === anchor?.block_id)
        : -1;

      if (anchorIndex >= 0) {
        items.splice(kind === "before" ? anchorIndex : anchorIndex + 1, 0, contribution);
        continue;
      }

      applyFallback(items, contribution, item, anchorState, fallback, diagnostics);
    }
  }

  return {
    type: "relaymark.composed_paper",
    items,
    diagnostics
  };
}

function applyFallback(items, contribution, item, anchorState, fallback, diagnostics) {
  const safeState = anchorState === "undisclosed" ? "undisclosed" : anchorState;

  if (fallback === "append_to_layer") {
    const lastLayerIndex = items.findLastIndex(({ layer_id: layerID }) => layerID === contribution.layer_id);
    items.splice(lastLayerIndex < 0 ? items.length : lastLayerIndex + 1, 0, contribution);
    diagnostics.push(warning("relaymark.layer.anchor_fallback", `Layer item '${item.id}' used append_to_layer because its anchor is ${safeState}.`));
    return;
  }

  if (fallback === "omit") {
    diagnostics.push(warning("relaymark.layer.anchor_omitted", `Layer item '${item.id}' was omitted because its anchor is ${safeState}.`));
    return;
  }

  diagnostics.push(error("relaymark.layer.anchor_unresolved", `Layer item '${item.id}' remains unresolved because its anchor is ${safeState}.`));
}

function compareRankAndID(left, right) {
  const rank = (left.rank || 0) - (right.rank || 0);
  return rank || String(left.id || "").localeCompare(String(right.id || ""));
}

function warning(code, message) {
  return { level: "warning", code, message };
}

function error(code, message) {
  return { level: "error", code, message };
}
