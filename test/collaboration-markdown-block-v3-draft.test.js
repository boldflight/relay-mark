import test from 'node:test';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as Y from 'yjs';
import { proseMirrorV3ToRelayMark, relayMarkV3ToProseMirror } from '../src/collaboration-table-v3.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/markdown-blocks-v3-draft.json', import.meta.url)));
const schemaURL = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
const schema = JSON.parse(readFileSync(schemaURL));
const clone = structuredClone;

function blockIDs(nodes, result = []) {
  for (const node of nodes) {
    result.push(node.id);
    blockIDs((node.content || []).filter(child => child.id), result);
  }
  return result;
}

test('community TipTap/Yjs Markdown blocks project to valid RelayMark AST and invert exactly', () => {
  assert.equal(fixture.root, 'default');
  const replica = new Y.Doc();
  Y.applyUpdate(replica, Buffer.from(fixture.update, 'base64'));
  const xml = replica.getXmlFragment('default');
  assert.deepEqual(xml.toArray().map(node => node.nodeName),
    ['paragraph', 'heading', 'blockquote', 'bulletList', 'orderedList', 'codeBlock',
      'horizontalRule', 'paragraph']);
  assert.equal(xml.toArray()[0].toArray()[1].nodeName, 'hardBreak');
  assert.deepEqual(xml.toArray()[0].toArray()[1].getAttributes(), {});
  const ast = proseMirrorV3ToRelayMark(fixture.normalized);
  assert.deepEqual(ast.blocks.map(block => block.type),
    ['paragraph', 'heading', 'quote', 'list', 'list', 'code', 'horizontal_rule', 'paragraph']);
  assert.deepEqual(ast.blocks[0].content[1], { type: 'hard_break' });
  assert.deepEqual(ast.blocks[1].props, { level: 2, headingId: 'shared-heading' });
  assert.deepEqual(ast.blocks[2].content.map(block => block.type), ['paragraph', 'paragraph']);
  assert.deepEqual(ast.blocks[3].props, { kind: 'bullet' });
  assert.deepEqual(ast.blocks[3].content[0].content[1].props, { kind: 'ordered', start: 3 });
  assert.deepEqual(ast.blocks[4].props, { kind: 'ordered', start: 7 });
  assert.deepEqual(ast.blocks[5].props, { language: 'swift' });
  assert.deepEqual(ast.blocks[6].content, []);
  const ids = blockIDs(ast.blocks);
  assert.equal(ids.length, new Set(ids).size);
  assert.ok(ids.every(id => /^b[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$/u.test(id)));
  assert.deepEqual(validateDocument(ast), []);
  assert.deepEqual(validateJSONSchema(ast, schema, fileURLToPath(schemaURL)), []);
  assert.deepEqual(ast, fixture.expected_ast);
  assert.deepEqual(relayMarkV3ToProseMirror(ast), fixture.normalized);
  assert.deepEqual(proseMirrorV3ToRelayMark(relayMarkV3ToProseMirror(ast)), ast);
  replica.destroy();
});

test('v3 Markdown block mapper rejects unsupported content before source projection', () => {
  const base = () => clone(fixture.normalized);
  const heading = doc => doc.content[1];
  const quote = doc => doc.content[2];
  const nestedList = doc => doc.content[3].content[0].content[1];
  const code = doc => doc.content[5];
  const rule = doc => doc.content[6];
  const reject = (edit, reason) => {
    const doc = base();
    edit(doc);
    assert.throws(() => proseMirrorV3ToRelayMark(doc), reason);
  };
  reject(doc => { delete heading(doc).attrs.relaymarkId; }, /relaymarkId/);
  reject(doc => { heading(doc).attrs.relaymarkId = doc.content[0].attrs.relaymarkId; }, /Duplicate/);
  reject(doc => { heading(doc).attrs.level = 7; }, /heading level/);
  reject(doc => { heading(doc).attrs.headingId = 'space in anchor'; }, /headingId/);
  reject(doc => { quote(doc).content.push(clone(doc.content[3])); }, /paragraph/);
  reject(doc => { nestedList(doc).attrs.type = 'A'; }, /ordered-list type/);
  reject(doc => {
    let current = nestedList(doc);
    for (let depth = 2; depth <= 16; depth++) {
      const child = { type: 'bulletList', attrs: { relaymarkId: `b${randomUUID().replaceAll('-', '')}` },
        content: [{ type: 'listItem', attrs: { relaymarkId: `b${randomUUID().replaceAll('-', '')}` },
          content: [{ type: 'paragraph', attrs: { relaymarkId: `b${randomUUID().replaceAll('-', '')}` }, content: [] }] }] };
      current.content[0].content.push(child);
      current = child;
    }
  }, /nested list depth/);
  reject(doc => { doc.content[3].content[0].content.push(clone(doc.content[0])); }, /Duplicate/);
  reject(doc => { code(doc).content[0].marks = [{ type: 'bold' }]; }, /Unsupported/);
  reject(doc => { rule(doc).content = [{ type: 'text', text: 'hidden' }]; }, /rule cannot/);
  reject(doc => { doc.content[0].content[1].attrs = { relaymarkId: 'extra' }; }, /Unsupported/);
  reject(doc => { doc.content[0].content[0].marks = [{ type: 'textStyle' }]; }, /Unsupported/);
  reject(doc => { doc.content[0].attrs.style = 'hidden'; }, /Unsupported/);
});

test('inverse mapping rejects malformed portable block properties and nested shapes', () => {
  const original = proseMirrorV3ToRelayMark(fixture.normalized);
  const reject = (edit, reason) => {
    const ast = clone(original);
    edit(ast);
    assert.throws(() => relayMarkV3ToProseMirror(ast), reason);
  };
  reject(ast => { ast.blocks[1].props.level = 0; }, /heading level/);
  reject(ast => { ast.blocks[2].content.push(clone(ast.blocks[3])); }, /paragraph/);
  reject(ast => { ast.blocks[3].props.start = 1; }, /Bullet list/);
  reject(ast => { ast.blocks[4].props.kind = 'bullet'; }, /Bullet list/);
  reject(ast => { ast.blocks[5].props.language = 'swift\njs'; }, /code language/);
  reject(ast => { ast.blocks[6].content = [{ type: 'text', text: 'hidden' }]; }, /rule cannot/);
  reject(ast => { ast.blocks[0].content[1].id = 'hidden'; }, /Unsupported/);
});


test('community list-item blocks preserve headings code and multiple paragraphs', () => {
  const doc = clone(fixture.normalized);
  function copyWithIDs(node) {
    const copy = clone(node);
    if (copy.attrs?.relaymarkId) copy.attrs.relaymarkId = `b${randomUUID().replaceAll('-', '')}`;
    if (copy.content) copy.content = copy.content.map(copyWithIDs);
    return copy;
  }
  doc.content[3].content[0].content.push(...[doc.content[0], doc.content[1], doc.content[5]].map(copyWithIDs));
  const ast = proseMirrorV3ToRelayMark(doc);
  assert.deepEqual(validateDocument(ast), []);
  assert.deepEqual(validateJSONSchema(ast, schema, fileURLToPath(schemaURL)), []);
  assert.deepEqual(relayMarkV3ToProseMirror(ast), doc);
});
