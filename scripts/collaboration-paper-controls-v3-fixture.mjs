// bun scripts/collaboration-paper-controls-v3-fixture.mjs /absolute/web/assets --write|--check
import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
import { proseMirrorToRelayMark, relayMarkToProseMirror } from '../src/document-adapter.js';
import { serializeRelayMark } from '../src/serializer.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const [assetsInput, mode] = process.argv.slice(2);
if (!assetsInput || !['--write', '--check'].includes(mode)) {
  throw new Error('Usage: bun scripts/collaboration-paper-controls-v3-fixture.mjs /absolute/web/assets --write|--check');
}
const assets = resolve(assetsInput);
const esm = file => import(pathToFileURL(join(assets, 'node_modules', file)));
const { getSchema, Extension } = await esm('@tiptap/core/dist/index.js');
const { default: StarterKit } = await esm('@tiptap/starter-kit/dist/index.js');
const { prosemirrorToYXmlFragment, yDocToProsemirrorJSON } = await esm('@tiptap/y-tiptap/dist/y-tiptap.js');
const Y = await esm('yjs/dist/yjs.mjs');
const { PaperButton, PaperAnchor, PaperConnection } = await import(pathToFileURL(join(assets, 'js/editors/extensions/paper-controls.js')));

const stableIDs = Extension.create({ name: 'fixtureStableIDs', addGlobalAttributes() {
  return [{ types: ['paragraph', 'relayButton', 'relayAnchor', 'relayConnection'],
    attributes: { relaymarkId: { default: null } } }];
} });
const schema = getSchema([StarterKit.configure({ trailingNode: false }), PaperButton, PaperAnchor, PaperConnection, stableIDs]);
const b = number => `b0000000000004000800000000000006${number}`;
const raw = { type: 'doc', content: [
  { type: 'paragraph', attrs: { relaymarkId: b(1) }, content: [{ type: 'text', text: 'Before' }] },
  { type: 'relayAnchor', attrs: { relaymarkId: b(2), name: 'next' } },
  { type: 'relayButton', attrs: { relaymarkId: b(3), label: 'Next', kind: 'anchor', target: 'next' } },
  { type: 'relayButton', attrs: { relaymarkId: b(4), label: 'Search Alex', kind: 'command', target: '/search Alex' } },
  { type: 'relayButton', attrs: { relaymarkId: b(5), label: 'Docs', kind: 'link', target: 'https://example.com/docs' } },
  { type: 'relayConnection', attrs: { relaymarkId: b(6), provider: 'google' } },
  { type: 'paragraph', attrs: { relaymarkId: b(7) }, content: [{ type: 'text', text: 'After' }] },
] };
const normalized = JSON.parse(JSON.stringify(schema.nodeFromJSON(raw).toJSON()));
const doc = new Y.Doc();
doc.clientID = 91_511;
prosemirrorToYXmlFragment(schema.nodeFromJSON(normalized), doc.getXmlFragment('default'));
const update = Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64');
const replay = new Y.Doc();
Y.applyUpdate(replay, Buffer.from(update, 'base64'));
assert.deepEqual(JSON.parse(JSON.stringify(schema.nodeFromJSON(yDocToProsemirrorJSON(replay, 'default')).toJSON())), normalized);
const expectedAST = proseMirrorToRelayMark(normalized);
assert.deepEqual(relayMarkToProseMirror(expectedAST), normalized);
const schemaPath = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
assert.deepEqual(validateDocument(expectedAST), []);
assert.deepEqual(validateJSONSchema(expectedAST, JSON.parse(await readFile(schemaPath, 'utf8')), schemaPath.pathname), []);
const authoredSource = serializeRelayMark(expectedAST);
const fixture = { fixture_version: 1, root: 'default', client_id: doc.clientID,
  source: 'Relay TipTap PaperButton/PaperAnchor/PaperConnection + community y-tiptap/Yjs',
  normalized, expected_ast: expectedAST, authored_source: authoredSource, update };
const output = `${JSON.stringify(fixture, null, 2)}\n`;
for (const path of [
  new URL('../spec/relaymark/collaboration/fixtures/paper-controls-v3-draft.json', import.meta.url),
  new URL('../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/paper-controls-v3-draft.json', import.meta.url)
]) {
  if (mode === '--write') await writeFile(path, output);
  else assert.equal(await readFile(path, 'utf8'), output);
}
console.log(`Community v3 Paper controls fixture ${mode === '--write' ? 'written' : 'matches'}`);
doc.destroy();
replay.destroy();
