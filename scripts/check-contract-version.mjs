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
const packaged = await readJSON("adapters/elixir/priv/relaymark/contract.json");
const { canonicalContract } = await import("../src/contract.js");
const expected = JSON.stringify(contract);
if (JSON.stringify(packaged) !== expected || JSON.stringify(canonicalContract) !== expected) {
  throw new Error("Canonical JS/Elixir bindings drifted from contract.json.");
}
const swift = await readFile(resolve(repositoryRoot, "adapters/swift/Sources/RelayMarkSwift/RelayMarkContract.swift"), "utf8");
for (const [name, value] of [["version", contract.contract_version], ["schema", contract.schema], ["sourceContract", contract.source_contract]]) {
  if (!swift.includes(`public static let ${name} = ${JSON.stringify(value)}`)) {
    throw new Error(`Swift canonical contract binding ${name} drifted.`);
  }
}
console.log(`Canonical editor/sync contract ${contract.contract_version} is consistent.`);
