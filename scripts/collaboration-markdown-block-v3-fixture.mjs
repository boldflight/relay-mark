// bun scripts/collaboration-markdown-block-v3-fixture.mjs /absolute/web/assets --write|--check
// Uses the installed community TipTap schema, UniqueID attributes, y-tiptap, and Yjs.
import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
import { proseMirrorToRelayMark, relayMarkToProseMirror } from '../src/document-adapter.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const [assetsInput, mode] = process.argv.slice(2);
if (!assetsInput || !['--write', '--check'].includes(mode)) {
  throw new Error('Usage: bun scripts/collaboration-markdown-block-v3-fixture.mjs /absolute/web/assets --write|--check');
}
const assets = resolve(assetsInput);
const esm = file => import(pathToFileURL(join(assets, 'node_modules', file)));
const { getSchema } = await esm('@tiptap/core/dist/index.js');
const { default: StarterKit } = await esm('@tiptap/starter-kit/dist/index.js');
const { UniqueID } = await esm('@tiptap/extension-unique-id/dist/index.js');
const { TableKit } = await esm('@tiptap/extension-table/dist/index.js');
const { prosemirrorToYXmlFragment, yDocToProsemirrorJSON } = await esm('@tiptap/y-tiptap/dist/y-tiptap.js');
const Y = await esm('yjs/dist/yjs.mjs');
const { PaperHeading } = await import(pathToFileURL(join(assets, 'js/editors/extensions/paper-heading.js')));

let nextID = 0;
const generateID = () => `b0000000000004000800000000000${(++nextID).toString(16).padStart(4, '0')}`;
const unique = UniqueID.configure({
  attributeName: 'relaymarkId',
  types: ['paragraph', 'heading', 'blockquote', 'bulletList', 'orderedList', 'listItem',
    'codeBlock', 'horizontalRule', 'table', 'tableRow', 'tableHeader', 'tableCell'],
  generateID,
});
const schema = getSchema([StarterKit.configure({ heading: false, trailingNode: false }), PaperHeading,
  TableKit, unique]);
for (const name of unique.options.types) {
  assert.ok(schema.nodes[name].spec.attrs.relaymarkId, `${name} must have the community UniqueID attribute`);
}
const id = () => unique.options.generateID();
const text = value => ({ type: 'text', text: value });
const paragraph = (...content) => ({ type: 'paragraph', attrs: { relaymarkId: id() },
  ...(content.length ? { content } : {}) });
const item = (value, nested = null) => ({ type: 'listItem', attrs: { relaymarkId: id() },
  content: [paragraph(text(value)), ...(nested ? [nested] : [])] });
const ordered = (start, ...items) => ({ type: 'orderedList', attrs: { relaymarkId: id(), start }, content: items });
const bullet = (...items) => ({ type: 'bulletList', attrs: { relaymarkId: id() }, content: items });
const raw = { type: 'doc', content: [
  paragraph(text('Before 🌍'), { type: 'hardBreak' }, text('second line')),
  { type: 'heading', attrs: { relaymarkId: id(), level: 2, headingId: 'shared-heading' },
    content: [text('Shared heading')] },
  { type: 'blockquote', attrs: { relaymarkId: id() },
    content: [paragraph(text('First quote')), paragraph(text('Second quote'))] },
  bullet(item('Outer', ordered(3, item('Nested Ω'))), item('Sibling')),
  ordered(7, item('Numbered')),
  { type: 'codeBlock', attrs: { relaymarkId: id(), language: 'swift' },
    content: [text('let earth = "🌍"\nprint(earth)')] },
  { type: 'horizontalRule', attrs: { relaymarkId: id() } },
  paragraph(text('After')),
] };
const normalized = JSON.parse(JSON.stringify(schema.nodeFromJSON(raw).toJSON()));
const doc = new Y.Doc();
doc.clientID = 91_503;
prosemirrorToYXmlFragment(schema.nodeFromJSON(normalized), doc.getXmlFragment('default'));
const update = Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64');
const replay = new Y.Doc();
Y.applyUpdate(replay, Buffer.from(update, 'base64'));
assert.deepEqual(JSON.parse(JSON.stringify(schema.nodeFromJSON(yDocToProsemirrorJSON(replay, 'default')).toJSON())), normalized);
const expectedAST = proseMirrorToRelayMark(normalized);
const astSchemaPath = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
assert.deepEqual(validateDocument(expectedAST), []);
assert.deepEqual(validateJSONSchema(expectedAST, JSON.parse(await readFile(astSchemaPath, 'utf8')),
  astSchemaPath.pathname), []);
assert.deepEqual(relayMarkToProseMirror(expectedAST), normalized);
const fixture = { fixture_version: 1, root: 'default', client_id: doc.clientID,
  source: 'Community TipTap StarterKit/PaperHeading/UniqueID + y-tiptap + Yjs',
  normalized, expected_ast: expectedAST, update };
const path = new URL('../spec/relaymark/collaboration/fixtures/markdown-blocks-v3-draft.json', import.meta.url);
const encoded = `${JSON.stringify(fixture, null, 2)}\n`;
if (mode === '--write') await writeFile(path, encoded);
else assert.equal(await readFile(path, 'utf8'), encoded);
console.log(`Community v3 Markdown-block fixture ${mode === '--write' ? 'written' : 'matches'}`);
doc.destroy();
replay.destroy();
