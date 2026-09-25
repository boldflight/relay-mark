import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { tableProseMirrorToRelayMark, relayMarkTableToProseMirror } from '../src/collaboration-table-v3.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const fixture = JSON.parse(readFileSync(new URL('../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/table-experimental.json', import.meta.url), 'utf8'));
const concurrent = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/table-concurrent-v3-draft.json', import.meta.url), 'utf8'));
const astSchemaURL = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
const astSchema = JSON.parse(readFileSync(astSchemaURL, 'utf8'));
const clone = value => structuredClone(value);

function addIds(node) {
  if (node.type !== 'doc' && node.type !== 'text') {
    node.attrs = { ...node.attrs, relaymarkId: `b${randomUUID().replaceAll('-', '')}` };
  }
  for (const child of node.content || []) addIds(child);
  return node;
}

function eachBlock(block, visitor) {
  visitor(block);
  for (const child of block.content || []) {
    if (child.id) eachBlock(child, visitor);
  }
}

test('real community table cases project and invert with all cells, spans, widths, alignment and IDs intact', () => {
  assert.deepEqual(fixture.cases.map(item => item.name), ['rectangle', 'colspan', 'rowspan']);
  for (const item of fixture.cases) {
    const original = addIds(clone(item.prosemirror));
    const ast = tableProseMirrorToRelayMark(original);
    assert.deepEqual(validateDocument(ast), [], item.name);
    assert.deepEqual(validateJSONSchema(ast, astSchema, fileURLToPath(astSchemaURL)), [], item.name);
    assert.deepEqual(relayMarkTableToProseMirror(ast), original, item.name);
    const ids = [];
    ast.blocks.forEach(block => eachBlock(block, node => ids.push(node.id)));
    assert.equal(new Set(ids).size, ids.length);
    assert.equal(ast.blocks[0].type, 'table');
    assert.ok(ast.blocks[0].content.every(row => row.type === 'table_row'));
    assert.ok(ast.blocks[0].content.flatMap(row => row.content).every(cell => cell.type === 'table_cell'));
    if (item.name === 'colspan') {
      assert.deepEqual(ast.blocks[0].content[0].content[0].props,
        { header: true, colspan: 2, rowspan: 1, colwidth: [120, 180], align: null });
    }
    if (item.name === 'rowspan') {
      assert.deepEqual(ast.blocks[0].content[0].content[0].props,
        { header: false, colspan: 1, rowspan: 2, colwidth: [140], align: null });
    }
  }
});

test('alignment and multiple cell paragraphs remain explicit in both directions', () => {
  const original = addIds(clone(fixture.cases[1].prosemirror));
  const cell = original.content[0].content[0].content[0];
  cell.attrs.align = 'right';
  cell.content.push({ type: 'paragraph', attrs: { relaymarkId: `b${randomUUID().replaceAll('-', '')}` },
    content: [{ type: 'text', text: 'Second paragraph' }] });
  const ast = tableProseMirrorToRelayMark(original);
  assert.equal(ast.blocks[0].content[0].content[0].props.align, 'right');
  assert.equal(ast.blocks[0].content[0].content[0].content.length, 2);
  assert.deepEqual(relayMarkTableToProseMirror(ast), original);
});

test('real concurrent cell edits and addRowAfter require community schema defaults before the strict table mapping', () => {
  assert.equal(concurrent.fixture_version, 1);
  assert.equal(concurrent.root, 'default');
  assert.equal(concurrent.raw.content[0].content.length, 3);
  assert.equal(concurrent.raw.content[0].content[1].content[0].content[0].content[0].text, 'Alice');
  assert.equal(concurrent.raw.content[0].content[1].content[1].content[0].content[0].text, 'Bob');
  assert.equal('align' in concurrent.raw.content[0].content[1].content[0].attrs, false);
  assert.deepEqual(concurrent.normalized.content[0].content[1].content[0].attrs.colwidth, [120]);
  assert.equal(concurrent.normalized.content[0].content[1].content[0].attrs.align, null);
  assert.equal(concurrent.normalized.content[0].content[0].content[0].attrs.colspan, 2);
  assert.deepEqual(concurrent.normalized.content[0].content[0].content[0].attrs.colwidth, [120, 180]);
  assert.throws(() => tableProseMirrorToRelayMark(concurrent.raw), /align/);

  const ast = tableProseMirrorToRelayMark(concurrent.normalized);
  assert.deepEqual(validateDocument(ast), []);
  assert.deepEqual(validateJSONSchema(ast, astSchema, fileURLToPath(astSchemaURL)), []);
  assert.deepEqual(relayMarkTableToProseMirror(ast), concurrent.inverse);
  assert.equal(ast.blocks[0].content.length, 3);
  const ids = [];
  ast.blocks.forEach(block => eachBlock(block, node => ids.push(node.id)));
  assert.equal(ids.length, new Set(ids).size);
  assert.equal(ids.length, 14);
  assert.deepEqual(concurrent.inverse.content[0].content[2].content[0].content[0].content, []);
  assert.equal('content' in concurrent.normalized.content[0].content[2].content[0].content[0], false);
});

test('v3 table mapping rejects missing IDs, duplicate IDs, unknown attrs and unsupported content', () => {
  const base = () => addIds(clone(fixture.cases[1].prosemirror));
  const header = doc => doc.content[0].content[0].content[0];
  const noId = base();
  delete header(noId).attrs.relaymarkId;
  assert.throws(() => tableProseMirrorToRelayMark(noId), /relaymarkId/);

  const duplicate = base();
  header(duplicate).attrs.relaymarkId = duplicate.content[0].attrs.relaymarkId;
  assert.throws(() => tableProseMirrorToRelayMark(duplicate), /Duplicate/);

  const extra = base();
  header(extra).attrs.background = 'red';
  assert.throws(() => tableProseMirrorToRelayMark(extra), /Unsupported/);

  const mark = base();
  header(mark).content[0].content[0].marks = [{ type: 'bold' }];
  assert.throws(() => tableProseMirrorToRelayMark(mark), /Unsupported/);

  const badWidth = base();
  header(badWidth).attrs.colwidth = [120];
  assert.throws(() => tableProseMirrorToRelayMark(badWidth), /colwidth/);

  const badGrid = base();
  badGrid.content[0].content[1].content.pop();
  assert.throws(() => tableProseMirrorToRelayMark(badGrid), /rectangle/);

  const hugeSpan = base();
  header(hugeSpan).attrs.colspan = Number.MAX_SAFE_INTEGER;
  header(hugeSpan).attrs.colwidth = null;
  assert.throws(() => tableProseMirrorToRelayMark(hugeSpan), /column limit/);
});
