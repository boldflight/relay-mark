// Drives the reference runtime's editing jobs over generated edits so that
// `record.mjs` records an oracle for them:
//
//   RELAYMARK_RECORD=calls.jsonl node --import ./crates/relaymark-core/tools/record.mjs \
//     crates/relaymark-core/tools/edit-corpus.mjs [--edits N] <input>...
//
// Inputs are read as by corpus.mjs (Markdown files, JSON source arrays, JSONL
// oracles). Each parsed paper gets N random maintained Transform edits, whose
// steps are replayed through applyContentEdit and prepareContentEditWrite, and
// random editor commands at random selections through createContentEditCommand.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { Transform } from 'prosemirror-transform';
import { Slice, Fragment } from 'prosemirror-model';
import { parseDocument } from '../../../src/document-source.js';
import { relayMarkToProseMirror } from '../../../src/document-adapter.js';
import { createCanonicalEditorSchema } from '../../../src/editor-model.js';
import { applyContentEdit, prepareContentEditWrite, createContentEditCommand, planContentEditTextWrite } from '../../../src/content-edit.js';

const schema = createCanonicalEditorSchema();
const args = process.argv.slice(2);
let edits = 20;
const sources = [];
function walk(path) {
  if (statSync(path).isDirectory()) {
    for (const entry of readdirSync(path).sort()) if (entry !== 'node_modules' && !entry.startsWith('.')) walk(join(path, entry));
  } else if (/\.(md|relaymark)$/.test(path)) sources.push(readFileSync(path, 'utf8'));
  else if (path.endsWith('.jsonl')) {
    for (const line of readFileSync(path, 'utf8').split('\n')) {
      if (!line) continue;
      const call = JSON.parse(line);
      if (call.fn === 'document-source.parseDocument' && typeof call.args[0] === 'string') sources.push(call.args[0]);
    }
  }
}
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--edits') edits = Number(args[++i]);
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
const position = doc => Math.floor(random() * (doc.content.size + 1));
const attempt = fn => { try { return fn(); } catch { return undefined; } };
const markTypes = Object.values(schema.marks).filter(type => type.name !== 'link' && type.name !== 'ai_authored');

// One random maintained operation on a Transform.
function edit(tr) {
  const doc = tr.doc, a = position(doc), b = position(doc), from = Math.min(a, b), to = Math.max(a, b);
  switch (Math.floor(random() * 11)) {
    case 0: return tr.delete(from, to);
    case 1: return tr.replaceWith(from, from, schema.text(pick(['x', ' ', 'Ω', '😀', 'two words'])));
    case 2: { const c = position(doc), d = Math.min(doc.content.size, c + Math.floor(random() * 30)); return tr.replace(from, to, doc.slice(c, d)); }
    case 3: return tr.addMark(from, to, pick(markTypes).create());
    case 4: return tr.removeMark(from, to, pick(markTypes));
    case 5: return tr.split(from, 1 + Math.floor(random() * 2));
    case 6: { const $f = doc.resolve(from), $t = doc.resolve(to), range = $f.blockRange($t); return range ? tr.lift(range, Math.max(0, range.depth - 1)) : tr; }
    case 7: { const c = position(doc), d = Math.min(doc.content.size, c + Math.floor(random() * 40)); return tr.replaceRange(from, to, doc.slice(c, d)); }
    case 8: return tr.deleteRange(from, to);
    case 9: { const node = doc.nodeAt(from); return node && !node.isText && 'relaymarkId' in node.attrs ? tr.setNodeAttribute(from, 'relaymarkId', 'b' + Math.floor(random() * 1e9).toString(16).padStart(32, '0')) : tr; }
    default: return tr.replaceRangeWith(from, to, schema.nodes.horizontalRule.create());
  }
}

const commands = ['return', 'sink_list_item', 'lift_list_item', 'addRowBefore', 'addRowAfter', 'deleteRow', 'addColumnBefore', 'addColumnAfter',
  'deleteColumn', 'mergeCells', 'splitCell', 'toggleHeaderRow', 'toggleHeaderColumn', 'toggleHeaderCell', 'deleteTable'];
function selections(doc) {
  const out = [];
  for (let i = 0; i < 6; i++) {
    const a = position(doc), b = random() < 0.6 ? a : position(doc);
    out.push({ type: 'text', anchor: a, head: b });
  }
  doc.descendants((node, pos) => {
    if (node.type.spec.tableRole === 'cell' || node.type.spec.tableRole === 'header_cell') {
      if (random() < 0.3) out.push({ type: 'cell', anchor: pos, head: pos });
      if (random() < 0.3) out.push({ type: 'text', anchor: pos + 2, head: pos + 2 });
    }
    if (node.type.name === 'listItem' || node.type.name === 'taskItem') if (random() < 0.4) out.push({ type: 'text', anchor: pos + 2, head: pos + 2 });
    if (!node.isText && node.isBlock && random() < 0.05) out.push({ type: 'node', anchor: pos });
  });
  return out;
}

let papers = 0;
for (const source of sources) {
  if (Buffer.byteLength(source) > 20000) continue;
  const ast = attempt(() => parseDocument(source, { namespace: 'edit-corpus' }));
  if (!ast) continue;
  const json = attempt(() => relayMarkToProseMirror(ast));
  if (!json) continue;
  papers++;
  const doc = schema.nodeFromJSON(json);
  for (let n = 0; n < edits; n++) {
    const tr = new Transform(doc);
    const count = 1 + Math.floor(random() * 3);
    for (let k = 0; k < count; k++) attempt(() => edit(tr));
    if (!tr.steps.length) continue;
    const steps = tr.steps.map(step => step.toJSON());
    attempt(() => applyContentEdit(json, { kind: 'content_edit', steps }));
    const prepared = attempt(() => prepareContentEditWrite(json, steps, tr.doc.toJSON()));
    if (prepared) for (const target of Object.values(prepared.after_groups)) {
      const source = prepared.before_groups[target.parent + ':' + target.index] || pick(Object.values(prepared.before_groups));
      if (!source) continue;
      attempt(() => planContentEditTextWrite(prepared, source.parent, source.index, target.parent, target.index));
      const offset = Math.floor(random() * (source.text.length + 1)), length = Math.floor(random() * (source.text.length - offset + 1));
      attempt(() => planContentEditTextWrite(prepared, source.parent, source.index, target.parent, target.index, { offset, length }));
    }
  }
  for (const selection of selections(doc)) attempt(() => createContentEditCommand(json, { command: pick(commands), selection }));
}
console.error(`edit-corpus: ${sources.length} sources, ${papers} papers`);
