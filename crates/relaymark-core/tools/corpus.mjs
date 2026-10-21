// Drives the JavaScript reference runtime over a Markdown corpus so that
// `record.mjs` records an oracle for every job on realistic and hostile input.
//
//   RELAYMARK_RECORD=calls.jsonl node --import ./crates/relaymark-core/tools/record.mjs \
//     crates/relaymark-core/tools/corpus.mjs [--mutate N] [--max-bytes B] <input>...
//
// Inputs: a CommonMark `spec.json` (its examples), a JSON array of sources, a JSONL oracle (its
// recorded parseDocument sources), Markdown/RelayMark files, HTML files or
// `.html.json` arrays of HTML (rendered or written by other applications), or
// directories of them.
// `--mutate N` adds N deterministic line-level mutations of the collected
// sources, `--mutate-chars N` N character-level ones and `--mutate-html N` N
// tag-level mutations of rendered and foreign HTML, read both as retained
// HTML and as clipboard HTML.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import {
  parseDocument, serializeDocument, projectDocumentMarkdown, renderDocument,
  documentToSnapshot, snapshotToDocument
} from '../../../src/document-source.js';
import { relayMarkToProseMirror, proseMirrorToRelayMark } from '../../../src/document-adapter.js';
import { compileRelayMark } from '../../../src/runtime.js';
import { importDocumentHTML, importClipboardHTML } from '../../../src/document-html.js';

const args = process.argv.slice(2);
let mutations = 0;
let characterMutations = 0;
let htmlMutations = 0;
const htmlSources = [];
let maxBytes = 200_000;
const sources = [];

function walk(path) {
  if (statSync(path).isDirectory()) {
    for (const entry of readdirSync(path).sort()) {
      if (entry === 'node_modules' || entry.startsWith('.')) continue;
      walk(join(path, entry));
    }
  } else if (path.endsWith('.html')) {
    htmlSources.push(readFileSync(path, 'utf8'));
  } else if (path.endsWith('.html.json')) {
    htmlSources.push(...JSON.parse(readFileSync(path, 'utf8')));
  } else if (/\.(md|relaymark)$/.test(path)) {
    sources.push(readFileSync(path, 'utf8'));
  } else if (path.endsWith('.json')) {
    // A CommonMark spec.json (its examples) or a plain array of sources.
    const items = JSON.parse(readFileSync(path, 'utf8'));
    if (!Array.isArray(items)) return;
    for (const item of items) {
      const source = typeof item === 'string' ? item : item?.markdown;
      if (typeof source === 'string') sources.push(source);
    }
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
  else if (args[i] === '--mutate-chars') characterMutations = Number(args[++i]);
  else if (args[i] === '--mutate-html') htmlMutations = Number(args[++i]);
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

const characters = ['`', '``', '*', '_', '~', '~~', '[', ']', '[[', ']]', '(', ')', '<', '>', '!', '\\', '&', '#', '|', '\n', '\n\n', ' ', '  ', '\t', '\u00a0', '"', ':', '-', '{', '}', '@', 'é', '👩🏽‍💻'];
for (let n = 0; n < characterMutations && base.length; n++) {
  let text = pick(base);
  const steps = 1 + Math.floor(random() * 4);
  for (let s = 0; s < steps; s++) {
    const at = Math.floor(random() * (text.length + 1));
    text = random() < 0.8 ? text.slice(0, at) + pick(characters) + text.slice(at) : text.slice(0, at) + text.slice(at + 1);
  }
  sources.push(text);
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
  const html = attempt(() => renderDocument(ast));
  if (html !== undefined) htmlSources.push(html);
  const snapshot = attempt(() => documentToSnapshot(ast));
  if (snapshot) attempt(() => snapshotToDocument(snapshot));
  const pm = attempt(() => relayMarkToProseMirror(ast));
  if (pm) attempt(() => proseMirrorToRelayMark(pm));
}
// Rendered HTML stripped of Relay's attributes reads like another application's.
const foreign = html => html.replace(/ (data-[a-z-]+|class|id)(="[^"]*")?/g, '');
const tags = ['<b>', '</b>', '<b style="font-weight: normal">', '<span style="font-weight: 700">', '<span style="font-weight:400">',
  '<i style="font-style: normal">', '<span style="font-style: italic">', '<span style="text-decoration: underline line-through">',
  '<span style="vertical-align: super">', '<sub>', '<del>', '<strike>', '</span>', '<br>', '<br/>', '\n', '  ', '\t', '&nbsp;', '<div>', '</div>',
  '<ul>', '<ol start="3" type="a">', '<li>', '</li>', '</ul>', '<ul data-type="taskList"><li data-type="taskItem" data-checked>',
  '<table>', '<tr>', '<td colspan="2" colwidth="80,90">', '<th>', '</table>', '<pre style="white-space: pre-wrap">', '<pre><code class="language-js">',
  '</code></pre>', '<h3>', '</h3>', '<blockquote>', '<hr>', '<img src="https://example.test/a.png" alt="a">', '<img src="data:image/png;base64,AA">',
  '<a href="https://example.test/x">', '<a href="javascript:alert(1)">', '</a>', '<!-- c -->', '<script>x()</script>', '<style>p{}</style>',
  '<meta charset="utf-8">', '<p data-pm-slice="1 1 []">', '<p data-relaymarkid="legacy">', '<span data-ai-authored data-run-id="r1">', '<code>', '</p>', '<p>'];
const htmlBase = htmlSources.slice();
for (const html of htmlBase) htmlSources.push(foreign(html));
for (let n = 0; n < htmlMutations && htmlBase.length; n++) {
  let html = pick(htmlBase);
  if (random() < 0.5) html = foreign(html);
  const steps = 1 + Math.floor(random() * 4);
  for (let s = 0; s < steps; s++) {
    const at = Math.floor(random() * (html.length + 1));
    html = random() < 0.85 ? html.slice(0, at) + pick(tags) + html.slice(at) : html.slice(0, at) + html.slice(at + 1 + Math.floor(random() * 8));
  }
  htmlSources.push(html);
}
for (const html of htmlSources) {
  if (Buffer.byteLength(html) > maxBytes) continue;
  attempt(() => importDocumentHTML({ html, namespace: 'corpus-html' }));
  attempt(() => importClipboardHTML({ html, namespace: 'corpus-clipboard' }));
}
console.error(`corpus: ${sources.length} sources, ${parsed} parsed, ${htmlSources.length} HTML`);
