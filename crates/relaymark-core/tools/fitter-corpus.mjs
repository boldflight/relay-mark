// Records prosemirror-transform's replace fitting as an oracle for the
// crate's Fitter, which no editing job reaches with arbitrary slices:
//
//   node crates/relaymark-core/tools/fitter-corpus.mjs [--replaces N] <input>... > fitter.jsonl
//
// Inputs are Markdown papers and ProseMirror document JSON (for shapes
// RelayMark Markdown does not write, such as an empty question option, which
// nothing outside its question holds). The first line holds the papers' documents;
// every further line is one Transform.replace of a slice of a paper into
// another, {paper, from, to, slice, steps} or {paper, from, to, slice,
// error}. Slices are cut anywhere, often at a container's end, so they open
// into lists, rows and quotes, and land in code blocks, headings and cells,
// where the Fitter opens, wraps and drops nodes.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { Transform } from 'prosemirror-transform';
import { parseDocument } from '../../../src/document-source.js';
import { relayMarkToProseMirror } from '../../../src/document-adapter.js';
import { createCanonicalEditorSchema } from '../../../src/editor-model.js';

const schema = createCanonicalEditorSchema();
const args = process.argv.slice(2);
let replaces = 200;
const sources = [], docs = [];
function walk(path) {
  if (statSync(path).isDirectory()) for (const entry of readdirSync(path).sort()) walk(join(path, entry));
  else if (/\.md$/.test(path)) sources.push(readFileSync(path, 'utf8'));
  else if (/\.json$/.test(path)) {
    const value = JSON.parse(readFileSync(path, 'utf8'));
    if (value.type === 'doc') docs.push(value);
  }
}
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--replaces') replaces = Number(args[++i]);
  else walk(args[i]);
}
let seed = 0x5eed;
const random = () => {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const pick = list => list[Math.floor(random() * list.length)];
const papers = sources.map((text, n) => schema.nodeFromJSON(relayMarkToProseMirror(parseDocument(text, { namespace: 'fitter-' + n }))))
  .concat(docs.map(json => schema.nodeFromJSON(json)));
// Positions between blocks, inside textblocks whose content is narrow
// (code, headings, cells), and anywhere.
function positions(doc) {
  const out = [];
  doc.descendants((node, pos) => {
    if (node.isBlock) out.push(pos);
    if (node.isTextblock) out.push(pos + 1, pos + 1 + node.content.size);
  });
  for (let i = 0; i < out.length / 2; i++) out.push(Math.floor(random() * (doc.content.size + 1)));
  return out;
}
const targets = papers.map(positions);
// Ends of containers (rows, lists, quotes): a slice cut there opens on an
// empty container that nothing on the frontier holds, so the Fitter drops it.
const ends = papers.map(doc => {
  const out = [];
  doc.descendants((node, pos) => { if (!node.isTextblock && !node.isLeaf && node.childCount) out.push(pos + node.nodeSize - 1); });
  return out;
});
// Starts of nodes with at most one child: cut there, a slice opens on a node
// that, when nothing on the frontier holds it (an empty question option),
// the Fitter drops together with its open parent.
const starts = papers.map(doc => {
  const out = [];
  doc.descendants((node, pos) => { if (!node.isLeaf && node.childCount <= 1) out.push(pos + 1); });
  return out;
});
console.log(JSON.stringify({ papers: papers.map(doc => doc.toJSON()) }));
function record(p, from, to, slice) {
  const line = { paper: p, from, to, slice: slice.toJSON() };
  try {
    const tr = new Transform(papers[p]).replace(from, to, slice);
    line.steps = tr.steps.map(step => step.toJSON());
  } catch (error) { line.error = String(error.message); }
  console.log(JSON.stringify(line));
}
// Every slice that opens on an empty node, between every pair of blocks at
// the top and inside containers.
for (const source of papers) {
  source.descendants((node, pos) => {
    if (node.isLeaf || node.content.size) return;
    // A few positions on, and the end of and after each ancestor, where the
    // dropped node closes the slice's end.
    const $a = source.resolve(pos + 1), ends = new Set();
    for (let k = 1; k <= 6 && pos + 1 + k <= source.content.size; k++) ends.add(pos + 1 + k);
    for (let d = $a.depth; d >= 1; d--) ends.add($a.end(d)).add($a.after(d));
    for (const end of ends) {
      if (end <= pos + 1) continue;
      const slice = source.slice(pos + 1, end);
      for (let p = 0; p < papers.length; p++) {
        papers[p].forEach((_, offset) => record(p, offset, offset, slice));
        papers[p].descendants((node, at) => { if (node.type.spec.content && !node.isTextblock && node.type.name !== 'doc') node.forEach((_, offset) => record(p, at + 1 + offset, at + 1 + offset, slice)); return !node.isTextblock; });
      }
    }
  });
}
for (let p = 0; p < papers.length; p++) {
  const doc = papers[p];
  for (let n = 0; n < replaces; n++) {
    const index = Math.floor(random() * papers.length), source = papers[index];
    const choice = random();
    const a = choice < 0.3 && ends[index].length ? pick(ends[index])
      : choice < 0.6 && starts[index].length ? pick(starts[index]) : Math.floor(random() * (source.content.size + 1));
    const b = Math.min(source.content.size, a + Math.floor(random() * 24));
    const slice = source.slice(a, b);
    const from = pick(targets[p]), to = random() < 0.7 ? from : Math.min(doc.content.size, from + Math.floor(random() * 12));
    record(p, from, to, slice);
  }
}
