// Drives the JavaScript reference runtime over a Markdown corpus so that
// `record.mjs` records an oracle for every job on realistic and hostile input.
//
//   RELAYMARK_RECORD=calls.jsonl node --import ./crates/relaymark-core/tools/record.mjs \
//     crates/relaymark-core/tools/corpus.mjs [--mutate N] [--max-bytes B] <input>...
//
// Inputs: a CommonMark `spec.json` (its examples), a JSONL oracle (its
// recorded parseDocument sources), Markdown/RelayMark files, or directories of
// them. `--mutate N` adds N deterministic line-level mutations of the
// collected sources.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import {
  parseDocument, serializeDocument, projectDocumentMarkdown, renderDocument,
  documentToSnapshot, snapshotToDocument
} from '../../../src/document-source.js';
import { relayMarkToProseMirror, proseMirrorToRelayMark } from '../../../src/document-adapter.js';
import { compileRelayMark } from '../../../src/runtime.js';

const args = process.argv.slice(2);
let mutations = 0;
let maxBytes = 200_000;
const sources = [];

function walk(path) {
  if (statSync(path).isDirectory()) {
    for (const entry of readdirSync(path).sort()) {
      if (entry === 'node_modules' || entry.startsWith('.')) continue;
      walk(join(path, entry));
    }
  } else if (/\.(md|relaymark)$/.test(path)) {
    sources.push(readFileSync(path, 'utf8'));
  } else if (path.endsWith('spec.json')) {
    for (const example of JSON.parse(readFileSync(path, 'utf8'))) sources.push(example.markdown);
  } else if (path.endsWith('.jsonl')) {
    for (const line of readFileSync(path, 'utf8').split('\n')) {
      if (!line) continue;
      const call = JSON.parse(line);
      if (call.fn === 'document-source.parseDocument' && typeof call.args[0] === 'string') sources.push(call.args[0]);
    }
  }
}

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--mutate') mutations = Number(args[++i]);
  else if (args[i] === '--max-bytes') maxBytes = Number(args[++i]);
  else walk(args[i]);
}

// Deterministic PRNG (mulberry32) so a corpus is reproducible.
let seed = 0x5eed;
const random = () => {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const pick = list => list[Math.floor(random() * list.length)];
const fragments = ['  ', '    ', '> ', '- ', '1. ', '* ', '- [ ] ', '- [x] ', '# ', '```', '~~~', '| a | b |', '| --- | :-: |',
  '@Callout(tone: "info") {', '}', '[[Person: 11111111-1111-4111-8111-111111111111 | Ada]]', '[[Tag: care | Care]]',
  '<!-- relay:question id="q" type="short_text" -->', '<!-- /relay:question -->', '![x](/m/a.png)', '**', '_', '`', '\\',
  '<div>', '</div>', '&amp;', '\t', '[a](https://example.com "t")', '::video[/v/11111111-1111-4111-8111-111111111111]', ''];
const base = sources.slice();
for (let n = 0; n < mutations && base.length; n++) {
  const lines = pick(base).split('\n');
  const steps = 1 + Math.floor(random() * 3);
  for (let s = 0; s < steps; s++) {
    const at = Math.floor(random() * (lines.length + 1));
    switch (Math.floor(random() * 5)) {
      case 0: lines.splice(at, 1); break;
      case 1: lines.splice(at, 0, pick(fragments)); break;
      case 2: if (lines[at] !== undefined) lines[at] = pick(fragments) + lines[at]; break;
      case 3: if (lines[at] !== undefined) lines.splice(at, 0, lines[at]); break;
      default: if (lines[at] !== undefined) lines[at] = lines[at] + pick(fragments);
    }
  }
  sources.push(lines.join('\n'));
}

const attempt = fn => { try { return fn(); } catch { return undefined; } };
let parsed = 0;
for (const source of sources) {
  if (Buffer.byteLength(source) > maxBytes) continue;
  const ast = attempt(() => parseDocument(source, { namespace: 'corpus' }));
  attempt(() => compileRelayMark(source));
  if (!ast) continue;
  parsed++;
  attempt(() => serializeDocument(ast));
  const markdown = attempt(() => projectDocumentMarkdown(ast));
  if (markdown !== undefined) attempt(() => parseDocument(markdown, { namespace: 'corpus-markdown' }));
  attempt(() => renderDocument(ast));
  const snapshot = attempt(() => documentToSnapshot(ast));
  if (snapshot) attempt(() => snapshotToDocument(snapshot));
  const pm = attempt(() => relayMarkToProseMirror(ast));
  if (pm) attempt(() => proseMirrorToRelayMark(pm));
}
console.error(`corpus: ${sources.length} sources, ${parsed} parsed`);
