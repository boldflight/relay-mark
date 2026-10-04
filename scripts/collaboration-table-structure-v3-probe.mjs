// node scripts/collaboration-table-structure-v3-probe.mjs /absolute/web/assets --write|--check
// Community TipTap table commands + UniqueID + y-tiptap/Yjs evidence for
// unmerged row/column insertion. This does not enroll the v3 schema.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { proseMirrorToRelayMark } from '../src/document-adapter.js';

const [assetsInput, mode] = process.argv.slice(2);
if (!assetsInput || !['--write', '--check'].includes(mode)) throw Error('assets path and --write|--check required');
const assets = resolve(assetsInput);
const require = createRequire(`${assets}/package.json`);
const { JSDOM } = await import(require.resolve('jsdom'));
const dom = new JSDOM('<html><body></body></html>');
Object.assign(globalThis, { window: dom.window, document: dom.window.document,
  HTMLElement: dom.window.HTMLElement, Node: dom.window.Node,
  MutationObserver: dom.window.MutationObserver,
  getSelection: dom.window.getSelection.bind(dom.window) });
Object.defineProperty(globalThis, 'navigator', { configurable: true, value: dom.window.navigator });
const [{ Editor }, { StarterKit }, { TableKit }, { UniqueID }, { Collaboration }, Y, binding] =
  await Promise.all(['@tiptap/core', '@tiptap/starter-kit', '@tiptap/extension-table',
    '@tiptap/extension-unique-id', '@tiptap/extension-collaboration', 'yjs',
    '@tiptap/y-tiptap'].map(name => import(require.resolve(name))));

const id = n => `b0000000000004000800000000000${n.toString(16).padStart(4, '0')}`;
let next = 99;
const extensions = [UniqueID.configure({ attributeName: 'relaymarkId',
  types: ['paragraph', 'table', 'tableRow', 'tableHeader', 'tableCell'],
  generateID: () => id(++next) }), StarterKit.configure({ trailingNode: false, undoRedo: false }), TableKit];
const paragraph = (n, text) => ({ type: 'paragraph', attrs: { relaymarkId: id(n) },
  content: [{ type: 'text', text, ...(text === 'Bold' ? { marks: [{ type: 'bold' }] } : {}) }] });
const cell = (n, p, text, header, width) => ({ type: header ? 'tableHeader' : 'tableCell',
  attrs: { relaymarkId: id(n), colspan: 1, rowspan: 1, colwidth: [width], align: null },
  content: [paragraph(p, text)] });
const row = (n, cells) => ({ type: 'tableRow', attrs: { relaymarkId: id(n) }, content: cells });
const source = { type: 'doc', content: [{ type: 'table', attrs: { relaymarkId: id(1) }, content: [
  row(2, [cell(3, 4, 'Name', true, 120), cell(5, 6, 'Value', true, 180)]),
  row(7, [cell(8, 9, 'Alpha', false, 120), cell(10, 11, 'Bold', false, 180)]),
] }] };
const snapshot = node => node instanceof Y.XmlText ? { kind: 'text', delta: node.toDelta() } :
  { kind: node instanceof Y.XmlElement ? 'element' : 'fragment',
    ...(node instanceof Y.XmlElement ? { name: node.nodeName, attributes: node.getAttributes() } : {}),
    children: node.toArray().map(snapshot) };
const initial = new Editor({ element: document.createElement('div'), extensions, content: source });
const normalized = JSON.parse(JSON.stringify(initial.getJSON()));
assert.deepEqual(normalized, source);
const doc = new Y.Doc();
doc.clientID = 91731;
const root = doc.getXmlFragment('default');
binding.prosemirrorToYXmlFragment(initial.state.doc, root);
initial.destroy();
const before = snapshot(root);
const seed = Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64');
const vector = Y.encodeStateVector(doc);
const editor = new Editor({ element: document.createElement('div'),
  extensions: [...extensions, Collaboration.configure({ document: doc, field: 'default' })] });
let position;
editor.state.doc.descendants((node, pos) => { if (node.isText && node.text === 'Alpha') position = pos + 2; });
assert.notEqual(position, undefined);
editor.commands.setTextSelection(position);
assert.equal(editor.state.selection.$from.parent.type.name, 'paragraph');
assert.equal(editor.state.selection.$from.parent.textContent, 'Alpha');
assert.equal(editor.commands.addRowAfter(), true);
const after = editor.getJSON();
const expected = after.content[0].content[2];
assert.deepEqual(expected.content.map(c => c.attrs.colwidth), [[120], [180]]);
assert.deepEqual(expected.content.map(c => c.type), ['tableCell', 'tableCell']);
assert.ok(expected.content.every(c => !c.content[0].content));
const fixture = { source: 'TipTap 3.30.5 TableKit/UniqueID/Collaboration + y-tiptap/Yjs 13.6.32',
  command: 'addRowAfter', normalized, before_xml: before, after,
  after_xml: snapshot(root), seed,
  update: Buffer.from(Y.encodeStateAsUpdate(doc, vector)).toString('base64'),
  expected_ast: proseMirrorToRelayMark(after) };
const mergedSource = { type: 'doc', content: [{ ...source.content[0], content: [
  row(2, [{ ...cell(3, 4, 'Merged', true, 120),
    attrs: { relaymarkId: id(3), colspan: 2, rowspan: 1, colwidth: [120, 180], align: null } }]),
  source.content[0].content[1],
] }] };
const mergedEditor = new Editor({ element: document.createElement('div'), extensions, content: mergedSource });
const mergedDoc = new Y.Doc();
mergedDoc.clientID = 91732;
binding.prosemirrorToYXmlFragment(mergedEditor.state.doc, mergedDoc.getXmlFragment('default'));
fixture.merged_seed = Buffer.from(Y.encodeStateAsUpdate(mergedDoc)).toString('base64');
mergedEditor.destroy(); mergedDoc.destroy();
next = 99;
const columnInitial = new Editor({ element: document.createElement('div'), extensions, content: source });
const columnNormalized = JSON.parse(JSON.stringify(columnInitial.getJSON()));
const columnDoc = new Y.Doc();
columnDoc.clientID = 91733;
const columnRoot = columnDoc.getXmlFragment('default');
binding.prosemirrorToYXmlFragment(columnInitial.state.doc, columnRoot);
columnInitial.destroy();
const columnBefore = snapshot(columnRoot);
const columnSeed = Buffer.from(Y.encodeStateAsUpdate(columnDoc)).toString('base64');
const columnVector = Y.encodeStateVector(columnDoc);
const columnEditor = new Editor({ element: document.createElement('div'),
  extensions: [...extensions, Collaboration.configure({ document: columnDoc, field: 'default' })] });
let columnPosition;
columnEditor.state.doc.descendants((node, pos) => { if (node.isText && node.text === 'Alpha') columnPosition = pos + 2; });
columnEditor.commands.setTextSelection(columnPosition);
assert.equal(columnEditor.state.selection.$from.parent.textContent, 'Alpha');
assert.equal(columnEditor.commands.addColumnAfter(), true);
assert.equal(columnEditor.state.selection.$from.parent.textContent, 'Alpha');
assert.equal(columnEditor.state.selection.$from.parentOffset, 2);
const columnAfter = columnEditor.getJSON();
assert.deepEqual(columnAfter.content[0].content.map(item => item.content[1].type),
  ['tableHeader', 'tableCell']);
assert.ok(columnAfter.content[0].content.every(item =>
  item.content[1].attrs.colwidth === null && !item.content[1].content[0].content));
const columnFixture = { source: fixture.source, command: 'addColumnAfter',
  normalized: columnNormalized, before_xml: columnBefore, after: columnAfter,
  after_xml: snapshot(columnRoot), seed: columnSeed,
  update: Buffer.from(Y.encodeStateAsUpdate(columnDoc, columnVector)).toString('base64'),
  expected_ast: proseMirrorToRelayMark(columnAfter), merged_seed: fixture.merged_seed,
  selection_after: { cell_id: id(8), text_offset: 2 } };
columnEditor.destroy(); columnDoc.destroy();
for (const [name, value] of [['row', fixture], ['column', columnFixture]]) {
  const path = new URL(`../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/table-add-${name}-v3.json`, import.meta.url);
  const encoded = `${JSON.stringify(value, null, 2)}\n`;
  if (mode === '--write') writeFileSync(path, encoded);
  else assert.equal(readFileSync(path, 'utf8'), encoded);
}
editor.destroy(); doc.destroy(); dom.window.close();
console.log(`Community table additions ${mode === '--write' ? 'written' : 'verified'}`);
