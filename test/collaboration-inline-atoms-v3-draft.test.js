import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as Y from 'yjs';
import { proseMirrorToRelayMark, relayMarkToProseMirror } from '../src/document-adapter.js';
import { serializeRelayMark } from '../src/serializer.js';
import { compileRelayMark } from '../src/runtime.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/inline-atoms-v3-draft.json', import.meta.url)));
const schemaURL = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
const schema = JSON.parse(readFileSync(schemaURL));
const clone = structuredClone;

test('real Relay TipTap atoms survive Yjs replay, portable inverse and exact source', () => {
  const doc = new Y.Doc();
  Y.applyUpdate(doc, Buffer.from(fixture.update, 'base64'));
  assert.deepEqual(doc.getXmlFragment('default').toArray().map(node => node.nodeName), ['paragraph', 'heading']);
  assert.deepEqual(doc.getXmlFragment('default').toArray()[0].toArray().map(node => node.nodeName),
    [undefined, 'relayReference', undefined, 'relayTag', undefined]);
  const ast = proseMirrorToRelayMark(fixture.normalized);
  assert.deepEqual(ast, fixture.expected_ast);
  assert.deepEqual(validateDocument(ast), []);
  assert.deepEqual(validateJSONSchema(ast, schema, fileURLToPath(schemaURL)), []);
  assert.deepEqual(relayMarkToProseMirror(ast), fixture.normalized);
  assert.equal(serializeRelayMark(ast), fixture.relaymark_source);
  assert.deepEqual(compileRelayMark(fixture.relaymark_source).document.blocks.map(block => block.content),
    ast.blocks.map(block => block.content));
  assert.deepEqual(ast.blocks[0].content.at(-1), { type: 'text', text: '. [[unknown]] stays text.' });
  doc.destroy();
});

test('v3 atom mapping rejects unresolved identity, inconsistent source and host presentation fields', () => {
  const rejectPM = edit => {
    const value = clone(fixture.normalized);
    edit(value);
    assert.throws(() => proseMirrorToRelayMark(value));
  };
  rejectPM(value => { value.content[0].content[1].attrs.entityId = null; });
  rejectPM(value => { value.content[0].content[1].attrs.source = '[[Ada]]'; });
  rejectPM(value => { value.content[0].content[1].attrs.status = 'resolved'; });
  rejectPM(value => { value.content[0].content[1].attrs.html = '<span>'; });
  rejectPM(value => { value.content[0].content[3].attrs.color = 'green'; });
  rejectPM(value => { value.content[0].content[3].attrs.name = 'Today'; });
  const rejectAST = edit => {
    const value = clone(fixture.expected_ast);
    edit(value);
    assert.throws(() => relayMarkToProseMirror(value));
    assert.throws(() => serializeRelayMark(value));
  };
  rejectAST(value => { value.blocks[0].content[1].props.source = '[[Person: bad | Ada]]'; });
  rejectAST(value => { delete value.blocks[0].content[1].props.source; });
  rejectAST(value => { value.blocks[0].content[3].label = '#tomorrow'; });
  const plain = compileRelayMark('[[unknown]]\n').document.blocks[0].content;
  assert.deepEqual(plain, [{ type: 'text', text: '[[unknown]]' }]);
});

// Collaboration excludes presentation attributes rather than persisting null placeholders.
test('v3 atoms accept omitted hydration fields from the current collaboration schema', () => {
  const document = clone(fixture.normalized);
  delete document.content[0].content[1].attrs.status;
  delete document.content[0].content[1].attrs.subtitle;
  delete document.content[0].content[3].attrs.color;
  const ast = proseMirrorToRelayMark(document);
  assert.deepEqual(ast, fixture.expected_ast);
  assert.deepEqual(proseMirrorToRelayMark(relayMarkToProseMirror(ast)), ast);
});
