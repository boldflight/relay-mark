#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { compileRelayMark } from "../src/index.js";
import { runConformanceSuite } from "../src/conformance.js";

const [, , command, ...args] = process.argv;

function usage() {
  console.error(`Usage:
  relaymark compile <file> [--manifest]
  relaymark conformance <suite.json>`);
}

if (!command) {
  usage();
  process.exit(1);
}

if (command === "compile") {
  const file = args[0];

  if (!file) {
    usage();
    process.exit(1);
  }

  const source = readFileSync(resolve(file), "utf8");
  const result = compileRelayMark(source);
  const output = args.includes("--manifest") ? result.manifest : result.document;
  console.log(JSON.stringify(output, null, 2));
  process.exit(result.diagnostics.some((diagnostic) => diagnostic.level === "critical") ? 1 : 0);
}

if (command === "conformance") {
  const suite = args[0];

  if (!suite) {
    usage();
    process.exit(1);
  }

  const result = runConformanceSuite(resolve(suite));

  for (const fixture of result.fixtures) {
    console.log(`${fixture.ok ? "ok" : "not ok"} - ${fixture.id}`);

    for (const error of fixture.errors) {
      console.log(`  ${error}`);
    }
  }

  process.exit(result.ok ? 0 : 1);
}

usage();
process.exit(1);
