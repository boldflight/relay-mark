// node scripts/collaboration-task-list-v3-fixture.mjs /absolute/web/assets --write|--check
// Generate a draft fixture with the installed community TipTap schema and Yjs converter.
import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
import { proseMirrorV3ToRelayMark, relayMarkV3ToProseMirror } from '../src/collaboration-table-v3.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const [assetsInput, mode] = process.argv.slice(2);
if (!assetsInput || !['--write', '--check'].includes(mode)) {
  throw new Error('Usage: node scripts/collaboration-task-list-v3-fixture.mjs /absolute/web/assets --write|--check');
}
const assets = resolve(assetsInput);
const esm = file => import(pathToFileURL(join(assets, 'node_modules', file)));
const { getSchema, Extension } = await esm('@tiptap/core/dist/index.js');
const { default: StarterKit } = await esm('@tiptap/starter-kit/dist/index.js');
const { default: TaskList } = await esm('@tiptap/extension-task-list/dist/index.js');
const { default: TaskItem } = await esm('@tiptap/extension-task-item/dist/index.js');
const { prosemirrorToYXmlFragment, yDocToProsemirrorJSON } = await esm('@tiptap/y-tiptap/dist/y-tiptap.js');
const Y = await esm('yjs/dist/yjs.mjs');

const LinkedTaskItem = TaskItem.extend({
  addAttributes() {
    return { ...this.parent?.(), entityId: { default: null } };
  },
});
let nextID = 0;
const generateID = () => `b0000000000004000800000000000${(++nextID).toString(16).padStart(4, '0')}`;
const identifiedTypes = ['paragraph', 'taskList', 'taskItem', 'bulletList', 'orderedList', 'listItem'];
const stableIDs = Extension.create({ name: 'relaymarkBlockIdentity',
  addGlobalAttributes() {
    return [{ types: identifiedTypes, attributes: { relaymarkId: { default: null } } }];
  },
});
const schema = getSchema([StarterKit.configure({ trailingNode: false }), TaskList,
  LinkedTaskItem.configure({ nested: true }), stableIDs]);
assert.equal(schema.nodes.taskList.spec.content, 'taskItem+');
assert.equal(schema.nodes.taskItem.spec.content, 'paragraph block*');
for (const name of identifiedTypes) assert.ok(schema.nodes[name].spec.attrs.relaymarkId);
const id = generateID;
const text = value => ({ type: 'text', text: value });
const paragraph = value => ({ type: 'paragraph', attrs: { relaymarkId: id() },
  ...(value ? { content: [text(value)] } : {}) });
const task = (checked, entityId, ...content) => ({ type: 'taskItem', attrs: { relaymarkId: id(), checked, entityId }, content });
const tasks = (...content) => ({ type: 'taskList', attrs: { relaymarkId: id() }, content });
const bullet = value => ({ type: 'bulletList', attrs: { relaymarkId: id() }, content: [
  { type: 'listItem', attrs: { relaymarkId: id() }, content: [paragraph(value)] },
] });
const linkedEntityId = '123e4567-e89b-42d3-a456-426614174000';
const raw = { type: 'doc', content: [
  paragraph('Before tasks'),
  tasks(
    task(true, linkedEntityId, paragraph('Done today'), paragraph('More detail'),
      tasks(task(false, null, paragraph('Nested Ω'))), bullet('Related bullet')),
    task(false, null, paragraph('Next')),
  ),
  paragraph('After tasks'),
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
assert.deepEqual(validateJSONSchema(expectedAST, JSON.parse(await readFile(astSchemaPath, 'utf8')),
  astSchemaPath.pathname), []);
assert.deepEqual(relayMarkV3ToProseMirror(expectedAST), normalized);
const fixture = { fixture_version: 1, root: 'default', client_id: doc.clientID,
  source: 'Community TipTap StarterKit/TaskList/TaskItem with RelayMark identity attributes + y-tiptap + Yjs',
  linked_entity_id: linkedEntityId, normalized, expected_ast: expectedAST, update };
const path = new URL('../spec/relaymark/collaboration/fixtures/task-list-v3-draft.json', import.meta.url);
const encoded = `${JSON.stringify(fixture, null, 2)}\n`;
if (mode === '--write') await writeFile(path, encoded);
else assert.equal(await readFile(path, 'utf8'), encoded);
// A second real community update exercises the bounded native task editor.
// The richer fixture above remains the portable read/projection contract.
const flatRaw = { type: 'doc', content: [tasks(
  task(true, linkedEntityId, paragraph('Done today')),
  task(false, null, paragraph('Next')),
)] };
const flatNormalized = JSON.parse(JSON.stringify(schema.nodeFromJSON(flatRaw).toJSON()));
const flatDoc = new Y.Doc();
flatDoc.clientID = 91_505;
prosemirrorToYXmlFragment(schema.nodeFromJSON(flatNormalized), flatDoc.getXmlFragment('default'));
const flatUpdate = Buffer.from(Y.encodeStateAsUpdate(flatDoc)).toString('base64');
const flatAST = proseMirrorV3ToRelayMark(flatNormalized);
assert.deepEqual(validateDocument(flatAST), []);
assert.deepEqual(relayMarkV3ToProseMirror(flatAST), flatNormalized);
const flatFixture = { fixture_version: 1, root: 'default', client_id: flatDoc.clientID,
  source: fixture.source, linked_entity_id: linkedEntityId,
  normalized: flatNormalized, expected_ast: flatAST, update: flatUpdate };
const flatPath = new URL('../spec/relaymark/collaboration/fixtures/task-list-flat-v3-draft.json', import.meta.url);
const flatEncoded = `${JSON.stringify(flatFixture, null, 2)}\n`;
if (mode === '--write') await writeFile(flatPath, flatEncoded);
else assert.equal(await readFile(flatPath, 'utf8'), flatEncoded);
console.log(`Community v3 task-list fixture ${mode === '--write' ? 'written' : 'matches'}`);
doc.destroy();
replay.destroy();
flatDoc.destroy();
