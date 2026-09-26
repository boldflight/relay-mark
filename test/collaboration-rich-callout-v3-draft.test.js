import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as Y from 'yjs';
import { proseMirrorV3ToRelayMark, relayMarkV3ToProseMirror } from '../src/collaboration-table-v3.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';
import { parseRelayMark } from '../src/parser.js';
import { compileParsedDocument } from '../src/compiler.js';

const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/rich-callout-v3-draft.json', import.meta.url)));
const schemaURL = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
const schema = JSON.parse(readFileSync(schemaURL));

test('community TipTap/Yjs callout keeps title, marks, body and stable IDs in the portable AST', () => {
  const doc = new Y.Doc();
  try {
    Y.applyUpdate(doc, Buffer.from(fixture.update, 'base64'));
    const xml = doc.getXmlFragment(fixture.root).toArray();
    assert.deepEqual(xml.map(node => node.nodeName), ['paragraph', 'callout', 'paragraph']);
    assert.deepEqual(xml[1].toArray().map(node => node.nodeName), ['calloutTitle', 'paragraph']);
    const ast = proseMirrorV3ToRelayMark(fixture.normalized);
    assert.deepEqual(ast.blocks.map(block => block.type), ['paragraph', 'relay.callout', 'paragraph']);
    assert.deepEqual(ast.blocks[1].props, { tone: 'warning', emphasis: 'strong' });
    assert.deepEqual(ast.blocks[1].content.map(block => block.type), ['relay.callout_title', 'paragraph']);
    assert.deepEqual(ast.blocks[1].content[0].content,
      [{ type: 'strong', content: [{ type: 'text', text: 'Pay attention' }] }]);
    assert.deepEqual(validateDocument(ast), []);
    assert.deepEqual(validateJSONSchema(ast, schema, fileURLToPath(schemaURL)), []);
    assert.deepEqual(relayMarkV3ToProseMirror(ast), fixture.normalized);
  } finally { doc.destroy(); }
});

test('callout projection rejects missing identity, extra metadata and invalid title placement', () => {
  const rejectNode = (mutate, message) => {
    const input = structuredClone(fixture.normalized);
    mutate(input.content[1]);
    assert.throws(() => proseMirrorV3ToRelayMark(input), message);
  };
  rejectNode(node => { node.attrs.tone = 'custom'; }, /tone or emphasis/);
  rejectNode(node => { node.attrs.uploadPercent = 40; }, /Unsupported/);
  rejectNode(node => { node.content[0].attrs.relaymarkId = node.attrs.relaymarkId; }, /Duplicate/);
  rejectNode(node => { delete node.content[0].attrs.relaymarkId; }, /relaymarkId/);
  rejectNode(node => { node.content = [node.content[0]]; }, /body block/);
  rejectNode(node => { node.content[0].content = [{ type: 'hardBreak' }]; }, /title inline node/);

  const ast = proseMirrorV3ToRelayMark(fixture.normalized);
  const misplaced = structuredClone(ast);
  misplaced.blocks[1].content.reverse();
  assert.throws(() => relayMarkV3ToProseMirror(misplaced), /title must be first/);
  assert.ok(validateDocument(misplaced).some(diagnostic => diagnostic.code === 'relaymark.callout.children'));
});

test('plain @Callout source compiles to the same structural title contract', () => {
  const compiled = compileParsedDocument(parseRelayMark(
    '@Callout(title: "Pay attention", tone: "warning", emphasis: "strong") {\nShared note\n}'));
  assert.deepEqual(compiled.diagnostics, []);
  assert.deepEqual(validateDocument(compiled.document), []);
  const callout = compiled.document.blocks[0];
  assert.deepEqual(callout.props, { tone: 'warning', emphasis: 'strong' });
  assert.deepEqual(callout.content.map(block => block.type), ['relay.callout_title', 'paragraph']);
  assert.deepEqual(callout.content[0].content, [{ type: 'text', text: 'Pay attention' }]);
});
