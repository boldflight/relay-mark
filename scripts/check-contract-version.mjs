import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

async function readJSON(path) {
  return JSON.parse(await readFile(resolve(repositoryRoot, path), "utf8"));
}

const [packageMetadata, suite, receipt, specReadme] = await Promise.all([
  readJSON("package.json"),
  readJSON("spec/relaymark/conformance/suite.json"),
  readJSON("spec/relaymark/conformance/agent-answer-fixture-receipt.json"),
  readFile(resolve(repositoryRoot, "spec/relaymark/README.md"), "utf8")
]);

if (Object.hasOwn(packageMetadata, "version")) {
  throw new Error(
    "The private reference-runtime package must not duplicate a release version."
  );
}

const contract = await readJSON("spec/relaymark/contract.json");
const documentedVersion = Number(specReadme.match(/^- Contract version: `([^`]+)`$/m)?.[1] ??
  specReadme.match(/^- Contract version: `([^`]+)` /m)?.[1]);
for (const [source, value] of [["documentation", documentedVersion], ["suite", suite.contract_version], ["receipt", receipt.contract_version]]) {
  if (value !== contract.contract_version) throw new Error(`${source} drifted from canonical contract.json.`);
}
const { readContractInputs, verifyContractBindings } = await import("./canonical-contract-bindings.mjs");
const bindingPaths = [
  "src/contract.js",
  "adapters/elixir/priv/relaymark/contract.json",
  "adapters/swift/Sources/RelayMarkSwift/RelayMarkContract.swift"
];
const bindingSources = Object.fromEntries(await Promise.all(bindingPaths.map(async path =>
  [path, await readFile(resolve(repositoryRoot, path), "utf8")]
)));
verifyContractBindings(await readContractInputs(), bindingSources);
console.log(`Canonical editor/sync contract ${contract.contract_version} is consistent.`);

const actualRegistry = await import('../src/directive-registry.js');
const { readdir } = await import('node:fs/promises');
const directiveFiles = (await readdir(resolve(repositoryRoot,'spec/relaymark/directives'))).filter(name => name.endsWith('.json')).sort();
const expectedRegistry = await Promise.all(directiveFiles.map(async name => JSON.parse(await readFile(resolve(repositoryRoot,'spec/relaymark/directives/' + name), 'utf8'))));
assert.deepEqual(actualRegistry.directiveSpecifications, expectedRegistry, 'Browser directive registry must be generated from canonical spec');
