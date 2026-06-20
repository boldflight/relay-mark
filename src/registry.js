import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const directiveDir = join(repoRoot, "spec", "relaymark", "directives");

let cachedRegistry;

export function loadDirectiveRegistry() {
  if (cachedRegistry) {
    return cachedRegistry;
  }

  const byName = new Map();
  const byType = new Map();

  for (const entry of readdirSync(directiveDir).filter((file) => file.endsWith(".json")).sort()) {
    const path = join(directiveDir, entry);
    const directive = JSON.parse(readFileSync(path, "utf8"));
    byName.set(directive.name, directive);
    byType.set(directive.ast_type, directive);
  }

  cachedRegistry = { byName, byType };
  return cachedRegistry;
}

export function directiveForName(name) {
  return loadDirectiveRegistry().byName.get(name);
}

export function directiveForType(type) {
  return loadDirectiveRegistry().byType.get(type);
}
