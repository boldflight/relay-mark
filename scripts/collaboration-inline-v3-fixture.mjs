// bun scripts/collaboration-inline-v3-fixture.mjs /absolute/web/assets --write|--check
// Uses installed community TipTap StarterKit, y-tiptap and Yjs with stable block IDs.
import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
import { proseMirrorV3ToRelayMark, relayMarkV3ToProseMirror } from '../src/collaboration-table-v3.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const [assetsInput, mode] = process.argv.slice(2);
if (!assetsInput || !['--write', '--check'].includes(mode)) {
  throw new Error('Usage: bun scripts/collaboration-inline-v3-fixture.mjs /absolute/web/assets --write|--check');
}
const assets = resolve(assetsInput);
const esm = file => import(pathToFileURL(join(assets, 'node_modules', file)));
const { getSchema, Extension } = await esm('@tiptap/core/dist/index.js');
const { default: StarterKit } = await esm('@tiptap/starter-kit/dist/index.js');
const { prosemirrorToYXmlFragment, yDocToProsemirrorJSON } = await esm('@tiptap/y-tiptap/dist/y-tiptap.js');
const Y = await esm('yjs/dist/yjs.mjs');
const { PaperHeading } = await import(pathToFileURL(join(assets, 'js/editors/extensions/paper-heading.js')));

const stableIDs = Extension.create({ name: 'fixtureStableIDs', addGlobalAttributes() {
  return [{ types: ['paragraph', 'heading', 'listItem', 'bulletList'],
    attributes: { relaymarkId: { default: null } } }];
} });
const schema = getSchema([StarterKit.configure({ trailingNode: false, heading: false }), PaperHeading, stableIDs]);
const id = number => `b0000000000004000800000000000${number.toString(16).padStart(4, '0')}`;
const text = (value, marks) => ({ type: 'text', text: value, ...(marks ? { marks } : {}) });
const raw = { type: 'doc', content: [
  { type: 'paragraph', attrs: { relaymarkId: id(1) }, content: [
    text('Plain '), text('bold italic strike', [{ type: 'strike' }, { type: 'italic' }, { type: 'bold' }]),
    text(' then '), text('code `x`', [{ type: 'code' }]),
    { type: 'hardBreak' },
    text('web', [{ type: 'link', attrs: { href: 'https://example.org/path?q=relay#part' } }]),
    text(' and '), text('Relay entity', [{ type: 'link', attrs: { href: 'relay:entity/12345678-1234-4234-8234-123456789abc' } }, { type: 'bold' }]),
  ] },
  { type: 'heading', attrs: { relaymarkId: id(2), level: 2, headingId: 'marked-heading' },
    content: [text('Marked heading', [{ type: 'italic' }])] },
  { type: 'bulletList', attrs: { relaymarkId: id(3) }, content: [
    { type: 'listItem', attrs: { relaymarkId: id(4) }, content: [
      { type: 'paragraph', attrs: { relaymarkId: id(5) }, content: [text('List link', [{ type: 'link', attrs: { href: 'mailto:relay@example.org' } }])] }
    ] }
  ] }
] };
const normalized = JSON.parse(JSON.stringify(schema.nodeFromJSON(raw).toJSON()));
const doc = new Y.Doc();
doc.clientID = 91_504;
prosemirrorToYXmlFragment(schema.nodeFromJSON(normalized), doc.getXmlFragment('default'));
const update = Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64');
const replay = new Y.Doc();
Y.applyUpdate(replay, Buffer.from(update, 'base64'));
assert.deepEqual(JSON.parse(JSON.stringify(schema.nodeFromJSON(yDocToProsemirrorJSON(replay, 'default')).toJSON())), normalized);
const expectedAST = proseMirrorV3ToRelayMark(normalized);
const astSchemaPath = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
assert.deepEqual(validateDocument(expectedAST), []);
assert.deepEqual(validateJSONSchema(expectedAST, JSON.parse(await readFile(astSchemaPath, 'utf8')), astSchemaPath.pathname), []);
assert.deepEqual(relayMarkV3ToProseMirror(expectedAST), normalized);
const fixture = { fixture_version: 1, root: 'default', client_id: doc.clientID,
  source: 'Community TipTap StarterKit/PaperHeading + stable relaymarkId attrs + y-tiptap + Yjs', normalized,
  expected_ast: expectedAST, update };
const output = `${JSON.stringify(fixture, null, 2)}\n`;
for (const path of [
  new URL('../spec/relaymark/collaboration/fixtures/inline-marks-v3-draft.json', import.meta.url),
  new URL('../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/inline-marks-v3-draft.json', import.meta.url)
]) {
  if (mode === '--write') await writeFile(path, output);
  else assert.equal(await readFile(path, 'utf8'), output);
}
console.log(`Community v3 inline fixture ${mode === '--write' ? 'written' : 'matches'}`);
doc.destroy();
replay.destroy();
