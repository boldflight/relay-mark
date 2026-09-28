import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as Y from 'yjs';
import { proseMirrorV3ToRelayMark, relayMarkV3ToProseMirror } from '../src/collaboration-table-v3.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/task-list-v3-draft.json', import.meta.url)));
const flatFixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/task-list-flat-v3-draft.json', import.meta.url)));
const schemaURL = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
const schema = JSON.parse(readFileSync(schemaURL));

test('bounded native task fixture is real Yjs with the same portable task identities', () => {
  const replica = new Y.Doc();
  Y.applyUpdate(replica, Buffer.from(flatFixture.update, 'base64'));
  const [list] = replica.getXmlFragment('default').toArray();
  assert.equal(list.nodeName, 'taskList');
  assert.deepEqual(list.getAttributes(), flatFixture.normalized.content[0].attrs);
  assert.deepEqual(list.toArray().map(item => item.getAttributes()),
    flatFixture.normalized.content[0].content.map(item => {
      const { entityId, ...attrs } = item.attrs;
      return entityId === null ? attrs : item.attrs;
    }));
  const ast = proseMirrorV3ToRelayMark(flatFixture.normalized);
  assert.deepEqual(ast, flatFixture.expected_ast);
  assert.deepEqual(validateDocument(ast), []);
  assert.deepEqual(relayMarkV3ToProseMirror(ast), flatFixture.normalized);
  replica.destroy();
});

test('community TipTap/Yjs task items keep checked state, optional entity UUID and nested block identities', () => {
  const replica = new Y.Doc();
  Y.applyUpdate(replica, Buffer.from(fixture.update, 'base64'));
  const root = replica.getXmlFragment('default');
  assert.deepEqual(root.toArray().map(node => node.nodeName), ['paragraph', 'taskList', 'paragraph']);
  const list = root.toArray()[1];
  assert.deepEqual(list.getAttributes(), fixture.normalized.content[1].attrs);
  assert.deepEqual(list.toArray()[0].getAttributes(), fixture.normalized.content[1].content[0].attrs);
  const ast = proseMirrorV3ToRelayMark(fixture.normalized);
  assert.deepEqual(ast, fixture.expected_ast);
  assert.deepEqual(ast.blocks[1].content[0].props,
    { checked: true, entityId: fixture.linked_entity_id });
  assert.deepEqual(ast.blocks[1].content[1].props, { checked: false, entityId: null });
  assert.deepEqual(ast.blocks[1].content[0].content.map(child => child.type),
    ['paragraph', 'paragraph', 'task_list', 'list']);
  assert.deepEqual(validateDocument(ast), []);
  assert.deepEqual(validateJSONSchema(ast, schema, fileURLToPath(schemaURL)), []);
  assert.deepEqual(relayMarkV3ToProseMirror(ast), fixture.normalized);
  replica.destroy();
});

test('task projection rejects executable or ambiguous task metadata and invalid nesting', () => {
  const reject = (edit, reason) => {
    const doc = structuredClone(fixture.normalized);
    edit(doc.content[1].content[0], doc);
    assert.throws(() => proseMirrorV3ToRelayMark(doc), reason);
  };
  reject(item => { item.attrs.entityId = 'Task-1'; }, /entityId/);
  reject(item => { item.attrs.checked = 'true'; }, /checked/);
  reject(item => { item.attrs.deleted = false; }, /Unsupported/);
  reject(item => { item.attrs.lastText = 'shadow'; }, /Unsupported/);
  reject(item => { item.content[0].type = 'heading'; }, /task item children/);
  reject(item => { item.content.push({ type: 'horizontalRule', attrs: { relaymarkId: item.attrs.relaymarkId } }); },
    /Duplicate/);
  reject((item, doc) => { item.attrs.relaymarkId = doc.content[1].attrs.relaymarkId; }, /Duplicate/);

  const ast = structuredClone(fixture.expected_ast);
  ast.blocks[1].content[0].props.checked = 1;
  assert.throws(() => relayMarkV3ToProseMirror(ast), /checked/);
  assert.ok(validateDocument(ast).some(issue => issue.code === 'relaymark.task_item.props'));

  const nested = structuredClone(fixture.expected_ast);
  let item = nested.blocks[1].content[0];
  for (let level = 2; level <= 17; level++) {
    const list = { id: `b${level.toString(16).padStart(12, '0')}40008000000000000000`, type: 'task_list', content: [
      { id: `b${(level + 32).toString(16).padStart(12, '0')}40008000000000000000`, type: 'task_item',
        props: { checked: false, entityId: null }, content: [
          { id: `b${(level + 64).toString(16).padStart(12, '0')}40008000000000000000`,
            type: 'paragraph', content: [] },
        ] },
    ] };
    item.content.push(list);
    item = list.content[0];
  }
  assert.throws(() => relayMarkV3ToProseMirror(nested), /nesting/);
  assert.ok(validateDocument(nested).some(issue => issue.code === 'relaymark.task_list.children'));
});


test('community task and table-cell bodies retain full authored block structures', () => {
  const rich = JSON.parse(readFileSync(new URL('../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/rich-containers-v3.json', import.meta.url)));
  const ast = proseMirrorV3ToRelayMark(rich.normalized);
  assert.deepEqual(ast, rich.expected_ast);
  assert.deepEqual(validateDocument(ast), []);
  assert.deepEqual(proseMirrorV3ToRelayMark(relayMarkV3ToProseMirror(ast)), ast);
});
