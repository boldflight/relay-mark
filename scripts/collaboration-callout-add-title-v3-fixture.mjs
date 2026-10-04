// bun scripts/collaboration-callout-add-title-v3-fixture.mjs /absolute/web/assets --write|--check
import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
import { proseMirrorToRelayMark } from '../src/document-adapter.js';

const [assetsInput, mode] = process.argv.slice(2);
if (!assetsInput || !['--write', '--check'].includes(mode)) throw new Error('assets path and --write|--check required');
const assets = resolve(assetsInput);
const esm = file => import(pathToFileURL(join(assets, 'node_modules', file)));
const { getSchema } = await esm('@tiptap/core/dist/index.js');
const { prosemirrorToYXmlFragment, yDocToProsemirrorJSON } = await esm('@tiptap/y-tiptap/dist/y-tiptap.js');
const Y = await esm('yjs/dist/yjs.mjs');
const { getCoreExtensions } = await import(pathToFileURL(join(assets, 'js/editors/extensions/core.js')));
const schema = getSchema(getCoreExtensions({ collaborative: true,
  collaborationSchema: 'relaymark-prosemirror-v3', hostCapabilities: [] }));
const b = number => `b0000000000004000800000000000008${number}`;
const before = { type: 'doc', content: [
  { type: 'paragraph', attrs: { relaymarkId: b(1) }, content: [{ type: 'text', text: 'Before' }] },
  { type: 'callout', attrs: { relaymarkId: b(2), tone: 'warning', emphasis: 'strong' }, content: [
    { type: 'paragraph', attrs: { relaymarkId: b(3) }, content: [{ type: 'text', text: 'Shared note' }] },
  ] },
  { type: 'paragraph', attrs: { relaymarkId: b(4) }, content: [{ type: 'text', text: 'After' }] },
] };
const normalize = value => JSON.parse(JSON.stringify(schema.nodeFromJSON(value).toJSON()));
const normalized = normalize(before);
const withTitle = structuredClone(normalized);
withTitle.content[1].content.unshift({ type: 'calloutTitle', attrs: { relaymarkId: b(5) },
  content: [{ type: 'text', text: 'Title' }] });
const expected = normalize(withTitle);
schema.nodeFromJSON(expected).check();
const doc = new Y.Doc();
doc.clientID = 91_513;
prosemirrorToYXmlFragment(schema.nodeFromJSON(normalized), doc.getXmlFragment('default'));
const update = Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64');
const replay = new Y.Doc();
Y.applyUpdate(replay, Buffer.from(update, 'base64'));
assert.deepEqual(normalize(yDocToProsemirrorJSON(replay, 'default')), normalized);
const nested = structuredClone(normalized);
nested.content[1].content.push({ type: 'blockquote', attrs: { relaymarkId: b(6) }, content: [
  { type: 'paragraph', attrs: { relaymarkId: b(7) }, content: [{ type: 'text', text: 'Nested' }] },
] });
const nestedNormalized = normalize(nested);
schema.nodeFromJSON(nestedNormalized).check();
const nestedDoc = new Y.Doc();
nestedDoc.clientID = 91_514;
prosemirrorToYXmlFragment(schema.nodeFromJSON(nestedNormalized), nestedDoc.getXmlFragment('default'));
const nestedUpdate = Buffer.from(Y.encodeStateAsUpdate(nestedDoc)).toString('base64');
const emptyTitle = structuredClone(expected);
delete emptyTitle.content[1].content[0].content;
const emptyNormalized = normalize(emptyTitle);
schema.nodeFromJSON(emptyNormalized).check();
const emptyDoc = new Y.Doc();
emptyDoc.clientID = 91_515;
prosemirrorToYXmlFragment(schema.nodeFromJSON(emptyNormalized), emptyDoc.getXmlFragment('default'));
const emptyTitleUpdate = Buffer.from(Y.encodeStateAsUpdate(emptyDoc)).toString('base64');
const fixture = { fixture_version: 1, root: 'default', client_id: doc.clientID,
  source: 'Relay v3 TipTap Callout/UniqueID + community y-tiptap/Yjs',
  normalized, expected_after_add_title: expected,
  expected_ast_after_add_title: proseMirrorToRelayMark(expected), update,
  nested_body_update: nestedUpdate, empty_title_update: emptyTitleUpdate };
const output = `${JSON.stringify(fixture, null, 2)}\n`;
const path = new URL('../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/callout-add-title-v3-draft.json', import.meta.url);
if (mode === '--write') await writeFile(path, output);
else assert.equal(await readFile(path, 'utf8'), output);
console.log(`Community v3 callout Add title fixture ${mode === '--write' ? 'written' : 'matches'}`);
doc.destroy(); replay.destroy(); nestedDoc.destroy(); emptyDoc.destroy();
