// bun scripts/collaboration-entity-reference-v3-fixture.mjs /absolute/web/assets --write|--check
import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
import { proseMirrorToRelayMark, relayMarkToProseMirror } from '../src/document-adapter.js';
import { serializeRelayMark } from '../src/serializer.js';
import { compileRelayMark } from '../src/runtime.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const [assetsInput, mode] = process.argv.slice(2);
if (!assetsInput || !['--write', '--check'].includes(mode)) {
  throw new Error('Usage: bun scripts/collaboration-entity-reference-v3-fixture.mjs /absolute/web/assets --write|--check');
}
const assets = resolve(assetsInput);
const esm = file => import(pathToFileURL(join(assets, 'node_modules', file)));
const { getSchema, Extension } = await esm('@tiptap/core/dist/index.js');
const { default: StarterKit } = await esm('@tiptap/starter-kit/dist/index.js');
const { prosemirrorToYXmlFragment, yDocToProsemirrorJSON } = await esm('@tiptap/y-tiptap/dist/y-tiptap.js');
const Y = await esm('yjs/dist/yjs.mjs');
const { RelayEntityReference } = await import(pathToFileURL(join(assets, 'js/editors/extensions/relay-inline.js')));

const stableIDs = Extension.create({ name: 'fixtureStableIDs', addGlobalAttributes() {
  return [{ types: ['paragraph', 'relayEntityReference'], attributes: { relaymarkId: { default: null } } }];
} });
const schema = getSchema([StarterKit.configure({ trailingNode: false }), RelayEntityReference, stableIDs]);
const entityId = '9f815b37-67b3-4101-868c-5335351feb6a';
const source = `@EntityRef(id: "entity:${entityId}", label: "Ada Lovelace", projection: "card") {\r\n  Authored fallback\r\n}`;
const raw = { type: 'doc', content: [
  { type: 'paragraph', attrs: { relaymarkId: 'b00000000000040008000000000000061' },
    content: [{ type: 'text', text: 'Before' }] },
  { type: 'relayEntityReference', attrs: { relaymarkId: 'b00000000000040008000000000000062',
    entityRef: `entity:${entityId}`, entityId, entityType: 'Entity', label: 'Ada Lovelace',
    projection: 'card', source } },
  { type: 'paragraph', attrs: { relaymarkId: 'b00000000000040008000000000000063' },
    content: [{ type: 'text', text: 'After' }] }
] };
const normalized = JSON.parse(JSON.stringify(schema.nodeFromJSON(raw).toJSON()));
const doc = new Y.Doc();
doc.clientID = 91_510;
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
const serialized = serializeRelayMark(expectedAST);
assert.equal(serialized, `Before\n\n${source}\n\nAfter\n`);
const compiled = compileRelayMark(source);
assert.equal(compiled.document.blocks[0].props.source, source);
assert.equal(serializeRelayMark(compiled.document), `${source}\n`);
const fixture = { fixture_version: 1, root: 'default', client_id: doc.clientID,
  source: 'Relay TipTap RelayEntityReference/StarterKit + community y-tiptap/Yjs',
  normalized, expected_ast: expectedAST, authored_source: source, update };
const output = `${JSON.stringify(fixture, null, 2)}\n`;
for (const path of [
  new URL('../spec/relaymark/collaboration/fixtures/entity-reference-v3-draft.json', import.meta.url),
  new URL('../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/entity-reference-v3-draft.json', import.meta.url)
]) {
  if (mode === '--write') await writeFile(path, output);
  else assert.equal(await readFile(path, 'utf8'), output);
}
console.log(`Community v3 EntityRef fixture ${mode === '--write' ? 'written' : 'matches'}`);
doc.destroy();
replay.destroy();
