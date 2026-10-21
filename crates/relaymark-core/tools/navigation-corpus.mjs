// Drives the reference runtime's clipboard navigation plans over generated
// pastes so that `record.mjs` records an oracle for them:
//
//   RELAYMARK_RECORD=calls.jsonl node --import ./crates/relaymark-core/tools/record.mjs \
//     crates/relaymark-core/tools/navigation-corpus.mjs [--pastes N] <input>...
//
// Inputs are Markdown files (papers with headings, anchors, fragment links and
// anchor buttons). Each paste copies a slice of one paper into another, as the
// native commit does: maintained steps, then fresh identities for copies. A
// paste of closed blocks at a block boundary also carries the positional
// source trace the native fitter reports, singly and as a two-item batch.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { Transform } from 'prosemirror-transform';
import { Slice } from 'prosemirror-model';
import { parseDocument } from '../../../src/document-source.js';
import { relayMarkToProseMirror } from '../../../src/document-adapter.js';
import { createCanonicalEditorSchema } from '../../../src/editor-model.js';
import { planClipboardAnchorAllocation, planClipboardHeadingNavigation } from '../../../src/content-edit.js';

const schema = createCanonicalEditorSchema();
const args = process.argv.slice(2);
let pastes = 40;
const sources = [];
function walk(path) {
  if (statSync(path).isDirectory()) for (const entry of readdirSync(path).sort()) walk(join(path, entry));
  else if (/\.md$/.test(path)) sources.push(readFileSync(path, 'utf8'));
}
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--pastes') pastes = Number(args[++i]);
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
const attempt = fn => { try { return fn(); } catch { return undefined; } };
let namespace = 0;
const parse = text => schema.nodeFromJSON(relayMarkToProseMirror(parseDocument(text, { namespace: 'navigation-' + namespace++ })));
const papers = sources.map(text => attempt(() => parse(text))).filter(Boolean);
const named = doc => {
  const tr = new Transform(doc);
  doc.forEach((node, offset) => { if (node.type.name === 'heading' && random() < 0.5) tr.setNodeAttribute(offset, 'headingId', pick(['chapter', 'section', 'intro', 'h-' + Math.floor(random() * 9)])); });
  return tr.doc;
};
function freshIdentities(tr) {
  let serial = Math.floor(random() * 1e6);
  const seen = new Set();
  tr.doc.descendants((node, pos) => {
    const id = node.attrs.relaymarkId;
    if (typeof id !== 'string') return;
    if (seen.has(id)) tr.setNodeAttribute(pos, 'relaymarkId', 'b' + (serial++).toString(16).padStart(32, '0'));
    else seen.add(id);
  });
}
function tokens(fragment) {
  const nodes = [];
  const visit = (frag, path, start) => {
    let pos = start;
    frag.forEach((node, _, i) => {
      const child = path.concat(i), inner = node.isLeaf ? pos : pos + 1;
      nodes.push({ source_path: child, from: pos, to: pos + node.nodeSize, content_from: inner, content_to: node.isLeaf ? pos + node.nodeSize : pos + node.nodeSize - 1, type: node.type.name });
      if (!node.isText && !node.isLeaf) visit(node.content, child, pos + 1);
      pos += node.nodeSize;
    });
  };
  visit(fragment, [], 0);
  return nodes;
}
function trace(fragment, step, at) {
  return { source_nodes: tokens(fragment), placements: [{ source_from: 0, source_to: fragment.size, target_from: at, target_to: at + fragment.size }], omitted_source_tokens: [], events: [], step };
}
function plans(input) {
  const anchors = attempt(() => planClipboardAnchorAllocation(input));
  const steps = [...input.steps, ...(anchors ? anchors.steps : [])];
  if (anchors && random() < 0.5) {
    const tr = new Transform(schema.nodeFromJSON(anchors.document));
    tr.doc.descendants((node, pos) => { if (node.type.name === 'heading' && random() < 0.4) tr.setNodeAttribute(pos, 'headingId', 'h-' + Math.floor(random() * 99)); });
    steps.push(...tr.steps.map(step => step.toJSON()));
  }
  attempt(() => planClipboardHeadingNavigation({ ...input, steps }));
}

// A target anchor already named as an allocated copy name forces suffixes.
function reserving(target, copy) {
  const ids = [];
  copy.descendants(node => { if (node.type.name === 'relayAnchor' && typeof node.attrs.relaymarkId === 'string') ids.push(node.attrs.relaymarkId); });
  if (!ids.length || random() < 0.5) return target;
  const tr = new Transform(target);
  // The anchors keep their names (so copies collide); a heading takes the
  // allocated name, so allocation must suffix it.
  target.descendants((node, pos) => { if (node.type.name === 'heading') tr.setNodeAttribute(pos, 'headingId', 'a-' + pick(ids) + (random() < 0.5 ? '' : '-2')); });
  return tr.doc;
}
for (let n = 0; n < pastes * papers.length && papers.length > 1; n++) {
  const copy = named(pick(papers)), target = reserving(named(pick(papers)), copy);
  // Arbitrary paste: a slice anywhere, fitted by replaceRange.
  const a = Math.floor(random() * (copy.content.size + 1)), b = Math.min(copy.content.size, a + Math.floor(random() * 80));
  const slice = random() < 0.5 ? new Slice(copy.content, 0, 0) : copy.slice(a, b);
  if (slice.size > 0) {
    const tr = new Transform(target), at = Math.floor(random() * (target.content.size + 1));
    if (attempt(() => tr.replaceRange(at, random() < 0.8 ? at : Math.min(target.content.size, at + 5), slice))) {
      freshIdentities(tr);
      plans({ clipboard_slice: slice.toJSON(), before_document: target.toJSON(), steps: tr.steps.map(step => step.toJSON()) });
    }
  }
  // Closed blocks at a block boundary, with the native fitter's trace.
  const blocks = copy.content.cut(0, copy.child(0).nodeSize + (copy.childCount > 1 ? copy.child(1).nodeSize : 0));
  let boundary = 0;
  const index = Math.floor(random() * (target.childCount + 1));
  for (let i = 0; i < index; i++) boundary += target.child(i).nodeSize;
  const tr = new Transform(target);
  if (!attempt(() => tr.replace(boundary, boundary, new Slice(blocks, 0, 0))) || !tr.steps.length) continue;
  const first = tr.steps[0].toJSON();
  freshIdentities(tr);
  const steps = tr.steps.map(step => step.toJSON());
  const single = { clipboard_slice: { content: blocks.toJSON(), openStart: 0, openEnd: 0 }, before_document: target.toJSON(), steps, source_trace: trace(blocks, first, boundary) };
  plans(single);
  // A second item pasted after the first, as one batch.
  const second = copy.content.cut(copy.content.size - copy.lastChild.nodeSize);
  const end = boundary + blocks.size, batch = new Transform(target);
  batch.replace(boundary, boundary, new Slice(blocks, 0, 0));
  if (!attempt(() => batch.replace(end, end, new Slice(second, 0, 0)))) continue;
  const firstStep = batch.steps[0].toJSON(), secondStep = batch.steps[1]?.toJSON();
  if (!secondStep) continue;
  freshIdentities(batch);
  plans({
    clipboard_items: [
      { clipboard_slice: { content: blocks.toJSON(), openStart: 0, openEnd: 0 }, source_trace: trace(blocks, firstStep, boundary), step_index: 0 },
      { clipboard_slice: { content: second.toJSON(), openStart: 0, openEnd: 0 }, source_trace: trace(second, secondStep, end), step_index: 1 },
    ],
    before_document: target.toJSON(),
    steps: batch.steps.map(step => step.toJSON()),
  });
}
console.error(`navigation-corpus: ${papers.length} papers`);
