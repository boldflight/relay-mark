// bun scripts/collaboration-inline-atoms-v3-fixture.mjs /absolute/web/assets --write|--check
// Real Relay TipTap atoms on the installed community ProseMirror/Yjs bridge.
import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
import { proseMirrorV3ToRelayMark, relayMarkV3ToProseMirror } from '../src/collaboration-table-v3.js';
import { serializeRelayMark } from '../src/serializer.js';
import { compileRelayMark } from '../src/runtime.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const [assetsInput, mode] = process.argv.slice(2);
if (!assetsInput || !['--write', '--check'].includes(mode)) {
  throw new Error('Usage: bun scripts/collaboration-inline-atoms-v3-fixture.mjs /absolute/web/assets --write|--check');
}
const assets = resolve(assetsInput);
const esm = file => import(pathToFileURL(join(assets, 'node_modules', file)));
const { getSchema, Extension } = await esm('@tiptap/core/dist/index.js');
const { default: StarterKit } = await esm('@tiptap/starter-kit/dist/index.js');
const { prosemirrorToYXmlFragment, yDocToProsemirrorJSON } = await esm('@tiptap/y-tiptap/dist/y-tiptap.js');
const Y = await esm('yjs/dist/yjs.mjs');
const { PaperHeading } = await import(pathToFileURL(join(assets, 'js/editors/extensions/paper-heading.js')));
const { RelayReference, RelayTag } = await import(pathToFileURL(join(assets, 'js/editors/extensions/relay-inline.js')));

const stableIDs = Extension.create({ name: 'fixtureStableIDs', addGlobalAttributes() {
  return [{ types: ['paragraph', 'heading'], attributes: { relaymarkId: { default: null } } }];
} });
const schema = getSchema([StarterKit.configure({ trailingNode: false, heading: false }), PaperHeading,
  RelayReference, RelayTag, stableIDs]);
const person = '9f815b37-67b3-4101-868c-5335351feb6a';
const tag = '9712027d-18db-448e-8514-cea7c215d6f7';
const task = '12345678-1234-4234-8234-123456789abc';
const reference = (entityType, entityId, label) => ({ type: 'relayReference', attrs: {
  entityType, entityId, label, source: `[[${entityType}: ${entityId} | ${label}]]`, status: null, subtitle: null } });
const raw = { type: 'doc', content: [
  { type: 'paragraph', attrs: { relaymarkId: 'b00000000000040008000000000000031' }, content: [
    { type: 'text', text: 'Meet ' }, reference('Person', person, 'Ada Lovelace'),
    { type: 'text', text: ' for ' }, { type: 'relayTag', attrs: {
      id: tag, name: 'today', color: null, source: `[[Tag: ${tag} | #today]]` } },
    { type: 'text', text: '. [[unknown]] stays text.' },
  ] },
  { type: 'heading', attrs: { relaymarkId: 'b00000000000040008000000000000032',
    level: 2, headingId: 'task-reference' }, content: [reference('Task', task, 'Prepare review')] },
] };
const normalized = JSON.parse(JSON.stringify(schema.nodeFromJSON(raw).toJSON()));
const doc = new Y.Doc();
doc.clientID = 91_506;
prosemirrorToYXmlFragment(schema.nodeFromJSON(normalized), doc.getXmlFragment('default'));
const update = Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64');
const replay = new Y.Doc();
Y.applyUpdate(replay, Buffer.from(update, 'base64'));
assert.deepEqual(JSON.parse(JSON.stringify(schema.nodeFromJSON(yDocToProsemirrorJSON(replay, 'default')).toJSON())), normalized);
const expectedAST = proseMirrorV3ToRelayMark(normalized);
assert.deepEqual(relayMarkV3ToProseMirror(expectedAST), normalized);
const schemaPath = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
assert.deepEqual(validateDocument(expectedAST), []);
assert.deepEqual(validateJSONSchema(expectedAST, JSON.parse(await readFile(schemaPath, 'utf8')), schemaPath.pathname), []);
const source = serializeRelayMark(expectedAST);
assert.deepEqual(compileRelayMark(source).document.blocks.map(block => block.content), expectedAST.blocks.map(block => block.content));
const fixture = { fixture_version: 1, root: 'default', client_id: doc.clientID,
  source: 'Relay TipTap RelayReference/RelayTag/PaperHeading + community StarterKit/y-tiptap/Yjs',
  normalized, expected_ast: expectedAST, relaymark_source: source, update };
const output = `${JSON.stringify(fixture, null, 2)}\n`;
for (const path of [
  new URL('../spec/relaymark/collaboration/fixtures/inline-atoms-v3-draft.json', import.meta.url),
  new URL('../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/inline-atoms-v3-draft.json', import.meta.url)
]) {
  if (mode === '--write') await writeFile(path, output);
  else assert.equal(await readFile(path, 'utf8'), output);
}
console.log(`Community v3 inline-atom fixture ${mode === '--write' ? 'written' : 'matches'}`);
doc.destroy();
replay.destroy();
