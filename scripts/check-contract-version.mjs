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

const documentedVersion = specReadme.match(/^- Spec version: `([^`]+)`$/m)?.[1];
if (!documentedVersion) {
  throw new Error("Unable to find the documented RelayMark spec version.");
}

const versions = new Map([
  ["spec documentation", documentedVersion],
  ["conformance suite", suite.version],
  ["Agent Answer receipt", receipt.version]
]);

for (const [source, version] of versions) {
  if (version !== suite.version) {
    throw new Error(
      `${source} declares ${version}; expected portable contract ${suite.version}.`
    );
  }
}

console.log(`RelayMark portable contract ${suite.version} is consistent.`);
