import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as Y from 'yjs';
import { proseMirrorToRelayMark, relayMarkToProseMirror } from '../src/document-adapter.js';
import { serializeRelayMark } from '../src/serializer.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/inline-marks-v3-draft.json', import.meta.url)));
const offered = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/inline-offered-marks-v3-draft.json', import.meta.url)));
const schemaURL = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
const schema = JSON.parse(readFileSync(schemaURL));
const clone = structuredClone;

test('community TipTap/Yjs v3 marks have an exact, valid portable round trip', () => {
  const replica = new Y.Doc();
  Y.applyUpdate(replica, Buffer.from(fixture.update, 'base64'));
  assert.deepEqual(replica.getXmlFragment('default').toArray().map(node => node.nodeName),
    ['paragraph', 'heading', 'bulletList']);
  const ast = proseMirrorToRelayMark(fixture.normalized);
  assert.deepEqual(ast, fixture.expected_ast);
  assert.deepEqual(validateDocument(ast), []);
  assert.deepEqual(validateJSONSchema(ast, schema, fileURLToPath(schemaURL)), []);
  assert.deepEqual(relayMarkToProseMirror(ast), fixture.normalized);
  assert.deepEqual(proseMirrorToRelayMark(relayMarkToProseMirror(ast)), ast);
  assert.throws(() => serializeRelayMark(ast), /Cannot losslessly serialize inline type 'strong'/);
  assert.deepEqual(ast.blocks[0].content[1], { type: 'strong', content: [{ type: 'emphasis',
    content: [{ type: 'strikethrough', content: [{ type: 'text', text: 'bold italic strike' }] }] }] });
  assert.deepEqual(ast.blocks[0].content[7], { type: 'link',
    href: 'relay:entity/12345678-1234-4234-8234-123456789abc',
    content: [{ type: 'strong', content: [{ type: 'text', text: 'Relay entity' }] }] });
  replica.destroy();
});

test('v3 marks reject unknown attrs, noncanonical order and lossy wrappers', () => {
  const rejectPM = edit => {
    const doc = clone(fixture.normalized);
    edit(doc);
    assert.throws(() => proseMirrorToRelayMark(doc));
  };
  rejectPM(doc => { doc.content[0].content[1].marks[0].attrs = { color: 'red' }; });
  rejectPM(doc => { doc.content[0].content[1].marks.reverse(); });
  rejectPM(doc => { doc.content[0].content[5].marks[0].attrs.title = 42; });
  rejectPM(doc => { doc.content[0].content[7].marks[0].attrs.target = '_unknown'; });
  rejectPM(doc => { doc.content[0].content[3].marks.push({ type: 'italic' }); });
  const rejectAST = edit => {
    const ast = clone(fixture.expected_ast);
    edit(ast);
    assert.throws(() => relayMarkToProseMirror(ast));
  };
  rejectAST(ast => { ast.blocks[0].content[5].props = { title: 42 }; });
  rejectAST(ast => { ast.blocks[0].content[7].content.push({ type: 'text', text: 'hidden' }); });
  rejectAST(ast => { ast.blocks[0].content[1].content[0].content[0].content[0].type = 'unknown'; });
  rejectAST(ast => { ast.blocks[0].content[3].content[0] = { type: 'strong', content: [{ type: 'text', text: 'x' }] }; });
});

test('community TipTap/Yjs offered marks preserve exact wrappers, order, IDs and entity links', () => {
  const replica = new Y.Doc();
  Y.applyUpdate(replica, Buffer.from(offered.update, 'base64'));
  assert.deepEqual(replica.getXmlFragment('default').toArray().map(node => node.nodeName),
    ['paragraph', 'heading', 'paragraph']);
  const ast = proseMirrorToRelayMark(offered.normalized);
  assert.deepEqual(ast, offered.expected_ast);
  assert.deepEqual(validateDocument(ast), []);
  assert.deepEqual(validateJSONSchema(ast, schema, fileURLToPath(schemaURL)), []);
  assert.deepEqual(relayMarkToProseMirror(ast), offered.normalized);
  assert.throws(() => serializeRelayMark(ast), /Cannot losslessly serialize inline type/);
  assert.deepEqual(ast.blocks.map(block => block.id), [21, 22, 23].map(n =>
    `b0000000000004000800000000000${n.toString(16).padStart(4, '0')}`));
  assert.deepEqual(ast.blocks[0].content[8], { type: 'strong', content: [{ type: 'underline',
    content: [{ type: 'highlight', content: [{ type: 'superscript',
      content: [{ type: 'subscript', content: [{ type: 'text', text: 'All offered' }] }] }] }] }] });
  assert.deepEqual(ast.blocks[2].content[0], { type: 'link',
    href: 'relay:entity/12345678-1234-4234-8234-123456789abc',
    content: [{ type: 'underline', content: [{ type: 'highlight',
      content: [{ type: 'text', text: 'Entity link' }] }] }] });
  replica.destroy();
});

test('offered mark mapping rejects attributed, repeated, reordered or lossy marks', () => {
  const rejectPM = edit => {
    const doc = clone(offered.normalized);
    edit(doc);
    assert.throws(() => proseMirrorToRelayMark(doc));
  };
  rejectPM(doc => { doc.content[0].content[0].marks[0].attrs = { color: 'red' }; });
  rejectPM(doc => { doc.content[0].content[2].marks[0].attrs = { color: null }; });
  rejectPM(doc => { doc.content[0].content[8].marks.reverse(); });
  rejectPM(doc => { doc.content[0].content[8].marks.push({ type: 'subscript' }); });
  rejectPM(doc => { doc.content[0].content[8].marks.push({ type: 'unknown' }); });
  const rejectAST = edit => {
    const ast = clone(offered.expected_ast);
    edit(ast);
    assert.throws(() => relayMarkToProseMirror(ast));
  };
  rejectAST(ast => { ast.blocks[0].content[0].props = { style: 'single' }; });
  rejectAST(ast => { ast.blocks[0].content[8].content[0].content.push({ type: 'text', text: 'extra' }); });
  rejectAST(ast => { ast.blocks[0].content[8].content[0].content[0].type = 'unknown'; });
});
