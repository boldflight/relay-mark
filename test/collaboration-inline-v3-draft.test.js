import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as Y from 'yjs';
import { proseMirrorV3ToRelayMark, relayMarkV3ToProseMirror } from '../src/collaboration-table-v3.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/inline-marks-v3-draft.json', import.meta.url)));
const schemaURL = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
const schema = JSON.parse(readFileSync(schemaURL));
const clone = structuredClone;

test('community TipTap/Yjs v3 marks have an exact, valid portable round trip', () => {
  const replica = new Y.Doc();
  Y.applyUpdate(replica, Buffer.from(fixture.update, 'base64'));
  assert.deepEqual(replica.getXmlFragment('default').toArray().map(node => node.nodeName),
    ['paragraph', 'heading', 'bulletList']);
  const ast = proseMirrorV3ToRelayMark(fixture.normalized);
  assert.deepEqual(ast, fixture.expected_ast);
  assert.deepEqual(validateDocument(ast), []);
  assert.deepEqual(validateJSONSchema(ast, schema, fileURLToPath(schemaURL)), []);
  assert.deepEqual(relayMarkV3ToProseMirror(ast), fixture.normalized);
  assert.deepEqual(proseMirrorV3ToRelayMark(relayMarkV3ToProseMirror(ast)), ast);
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
    assert.throws(() => proseMirrorV3ToRelayMark(doc));
  };
  rejectPM(doc => { doc.content[0].content[1].marks[0].attrs = { color: 'red' }; });
  rejectPM(doc => { doc.content[0].content[1].marks.reverse(); });
  rejectPM(doc => { doc.content[0].content[5].marks[0].attrs.title = 'hidden'; });
  rejectPM(doc => { doc.content[0].content[7].marks[0].attrs.target = '_self'; });
  rejectPM(doc => { doc.content[0].content[3].marks.push({ type: 'italic' }); });
  const rejectAST = edit => {
    const ast = clone(fixture.expected_ast);
    edit(ast);
    assert.throws(() => relayMarkV3ToProseMirror(ast));
  };
  rejectAST(ast => { ast.blocks[0].content[5].props = { title: 'hidden' }; });
  rejectAST(ast => { ast.blocks[0].content[7].content.push({ type: 'text', text: 'hidden' }); });
  rejectAST(ast => { ast.blocks[0].content[1].content[0].content[0].content[0].type = 'unknown'; });
  rejectAST(ast => { ast.blocks[0].content[3].content[0] = { type: 'strong', content: [{ type: 'text', text: 'x' }] }; });
});
