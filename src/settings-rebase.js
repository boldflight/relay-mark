// Conflict avoidance for a form question's settings without per-key storage.
// Question and option settings are ONE aggregate `settings` attribute (October 18
// decision; per-key `settings:<key>` storage killed performance and must never
// return; Douglas, 2026-11-02). A client holding an unacknowledged settings edit
// that sees the attribute replaced re-applies the keys it changed onto the
// incoming value. A key both sides changed stays the incoming (last writer's)
// value. Mirrors relaymark-core `settings_rebase`;
// spec/relaymark/editor/settings-rebase-v1.json is the shared contract.

import { equalCanonicalJSON } from "./canonical-json.js";

const object = (value) => {
  if (value === null || value === undefined) return {};
  if (typeof value !== "object" || Array.isArray(value)) throw new Error("Settings must be an object or null");
  return value;
};

const same = (a, b) => (a === undefined || b === undefined ? a === b : equalCanonicalJSON(a, b));

/** `[base, local, incoming]` to `{settings}`: what to write after the incoming
 * change, or `{settings: null}` when there is nothing left to write. */
export function settingsRebase(input) {
  if (!Array.isArray(input) || input.length !== 3) throw new Error("Settings rebase takes [base, local, incoming]");
  if (input[2] === null) return { settings: null };
  const [base, local, incoming] = input.map(object);
  const merged = { ...incoming };
  const keys = [...Object.keys(base), ...Object.keys(local).filter((key) => !(key in base))];
  for (const key of keys) {
    const before = base[key], mine = local[key], theirs = incoming[key];
    if (same(mine, before) || same(theirs, mine) || !same(theirs, before)) continue;
    if (mine === undefined) delete merged[key];
    else merged[key] = mine;
  }
  return { settings: equalCanonicalJSON(merged, incoming) ? null : merged };
}
