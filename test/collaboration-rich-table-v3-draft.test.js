import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  tableProseMirrorToRelayMark, relayMarkTableToProseMirror,
  proseMirrorToRelayMark, relayMarkToProseMirror,
} from '../src/document-adapter.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';
import * as Y from 'yjs';

const fixture = JSON.parse(readFileSync(new URL('../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/table-experimental.json', import.meta.url), 'utf8'));
const concurrent = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/table-concurrent-v3-draft.json', import.meta.url), 'utf8'));
const mixed = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/table-mixed-v3-draft.json', import.meta.url), 'utf8'));
const astSchemaURL = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
const astSchema = JSON.parse(readFileSync(astSchemaURL, 'utf8'));
const clone = value => structuredClone(value);
const proseID = suffix => `b0000000000004000800000000000000${suffix}`;

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

test('table cell paragraphs use the same bounded inline grammar as ordinary paragraphs', () => {
  const original = addIds(clone(fixture.cases[0].prosemirror));
  const paragraph = original.content[0].content[0].content[0].content[0];
  paragraph.content = [
    { type: 'text', text: 'Bold', marks: [{ type: 'bold' }] },
    { type: 'hardBreak' },
    { type: 'text', text: ' linked', marks: [{ type: 'link', attrs: {
      href: 'relay:entity/12345678-1234-4234-8234-123456789abc',
      target: '_blank', rel: 'noopener noreferrer nofollow', class: null, title: null,
    } }] },
    { type: 'relayTag', attrs: { id: '12345678-1234-4234-8234-123456789abc',
      name: 'planning', color: null,
      source: '[[Tag: 12345678-1234-4234-8234-123456789abc | #planning]]' } },
  ];
  const ast = tableProseMirrorToRelayMark(original);
  const inline = ast.blocks[0].content[0].content[0].content[0].content;
  assert.deepEqual(inline.map(item => item.type), ['strong', 'hard_break', 'link', 'relay.tag_ref']);
  assert.deepEqual(validateDocument(ast), []);
  assert.deepEqual(validateJSONSchema(ast, astSchema, fileURLToPath(astSchemaURL)), []);
  assert.deepEqual(relayMarkTableToProseMirror(ast), original);

  const unsupported = clone(original);
  unsupported.content[0].content[0].content[0].content[0].content[0].marks = [{ type: 'textStyle' }];
  assert.throws(() => tableProseMirrorToRelayMark(unsupported), /Unsupported/);
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

test('normalized concurrent table round-trips with ordered prose before and after it', () => {
  const tableBytes = Buffer.from(concurrent.update, 'base64');
  assert.equal(mixed.base_table_update_sha256, createHash('sha256').update(tableBytes).digest('hex'));
  assert.equal(mixed.root, concurrent.root);
  const doc = new Y.Doc();
  Y.applyUpdate(doc, Buffer.from(mixed.update, 'base64'));
  const [beforeXML, tableXML, emptyXML, afterXML] = doc.getXmlFragment(mixed.root).toArray();
  assert.deepEqual([beforeXML.nodeName, tableXML.nodeName, emptyXML.nodeName, afterXML.nodeName],
    ['paragraph', 'table', 'paragraph', 'paragraph']);
  assert.equal(beforeXML.toArray()[0].toString(), 'Before 🌍 <table>');
  assert.equal(emptyXML.toArray().length, 0);
  assert.equal(afterXML.toArray()[0].toString(), 'After the shared table');
  assert.deepEqual(mixed.normalized.content[1], concurrent.normalized.content[0]);
  const [before, , empty, after] = mixed.normalized.content;
  assert.equal(before.attrs.relaymarkId, beforeXML.getAttribute('relaymarkId'));
  assert.equal(empty.attrs.relaymarkId, emptyXML.getAttribute('relaymarkId'));
  assert.equal(after.attrs.relaymarkId, afterXML.getAttribute('relaymarkId'));
  const ast = proseMirrorToRelayMark(mixed.normalized);

  assert.deepEqual(ast.blocks.map(block => block.type), ['paragraph', 'table', 'paragraph', 'paragraph']);
  assert.equal(ast.blocks[0].id, before.attrs.relaymarkId);
  assert.equal(ast.blocks[2].id, empty.attrs.relaymarkId);
  assert.deepEqual(ast.blocks[2].content, []);
  assert.equal(ast.blocks[3].content[0].text, 'After the shared table');
  assert.deepEqual(ast.blocks[1].content[0].content[0].props,
    { header: true, colspan: 2, rowspan: 1, colwidth: [120, 180], align: null });
  assert.equal(ast.blocks[1].content[1].content[0].content[0].content[0].text, 'Alice');
  assert.equal(ast.blocks[1].content[1].content[1].content[0].content[0].text, 'Bob');
  assert.deepEqual(validateDocument(ast), []);
  assert.deepEqual(validateJSONSchema(ast, astSchema, fileURLToPath(astSchemaURL)), []);

  const inverse = relayMarkToProseMirror(ast);
  assert.deepEqual(inverse.content[0], before);
  assert.deepEqual(inverse.content[1], concurrent.inverse.content[0]);
  assert.deepEqual(inverse.content[2], { ...empty, content: [] });
  assert.deepEqual(inverse.content[3], after);
  assert.deepEqual(proseMirrorToRelayMark(inverse), ast);
  assert.throws(() => tableProseMirrorToRelayMark(mixed.normalized), /Table-only/);
  assert.throws(() => relayMarkTableToProseMirror(ast), /Table-only/);
  doc.destroy();
});

test('mixed projection rejects unsupported prose nodes, marks, attributes and cross-block duplicate IDs', () => {
  const paragraph = { type: 'paragraph', attrs: { relaymarkId: proseID(1) },
    content: [{ type: 'text', text: 'Plain' }] };
  const base = () => ({ type: 'doc', content: [clone(paragraph), clone(concurrent.normalized.content[0])] });
  const marked = base();
  marked.content[0].content[0].marks = [{ type: 'textStyle' }];
  assert.throws(() => proseMirrorToRelayMark(marked), /Unsupported/);
  const attributed = base();
  attributed.content[0].attrs.class = 'unexpected';
  assert.throws(() => proseMirrorToRelayMark(attributed), /Unsupported/);
  const duplicate = base();
  duplicate.content[0].attrs.relaymarkId = duplicate.content[1].attrs.relaymarkId;
  assert.throws(() => proseMirrorToRelayMark(duplicate), /Duplicate/);
  const unsupported = base();
  unsupported.content.push({ type: 'unsupportedBlock', attrs: { relaymarkId: proseID(2) } });
  assert.throws(() => proseMirrorToRelayMark(unsupported), /Unsupported v3 block/);
  const invalidAst = proseMirrorToRelayMark(base());
  invalidAst.blocks[0].props = { style: 'unexpected' };
  assert.throws(() => relayMarkToProseMirror(invalidAst), /Unsupported/);
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
