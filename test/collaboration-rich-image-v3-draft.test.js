import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as Y from 'yjs';
import { proseMirrorV3ToRelayMark, relayMarkV3ToProseMirror } from '../src/collaboration-table-v3.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/rich-image-v3-draft.json', import.meta.url)));
const schemaURL = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
const schema = JSON.parse(readFileSync(schemaURL));
const clone = structuredClone;

test('community TipTap/Yjs image keeps durable source, text and stable identity through RelayMark AST', () => {
  const replica = new Y.Doc();
  try {
    Y.applyUpdate(replica, Buffer.from(fixture.update, 'base64'));
    const xml = replica.getXmlFragment(fixture.root).toArray();
    assert.deepEqual(xml.map(node => node.nodeName), ['paragraph', 'image', 'paragraph']);
    assert.equal(xml[1].getAttribute('relaymarkId'), fixture.normalized.content[1].attrs.relaymarkId);
    assert.equal(xml[1].getAttribute('src'), '/m/11111111-1111-4111-8111-111111111111');
    assert.deepEqual(fixture.raw.content[1].attrs, {
      relaymarkId: fixture.normalized.content[1].attrs.relaymarkId,
      src: '/m/11111111-1111-4111-8111-111111111111', alt: 'Shared diagram', title: 'Planning'
    });
    const ast = proseMirrorV3ToRelayMark(fixture.normalized);
    assert.deepEqual(ast.blocks.map(block => block.type), ['paragraph', 'image', 'paragraph']);
    assert.deepEqual(ast.blocks[1], {
      id: fixture.normalized.content[1].attrs.relaymarkId,
      type: 'image',
      props: { src: '/m/11111111-1111-4111-8111-111111111111', alt: 'Shared diagram', title: 'Planning' },
      content: []
    });
    assert.deepEqual(validateDocument(ast), []);
    assert.deepEqual(validateJSONSchema(ast, schema, fileURLToPath(schemaURL)), []);
    const inverse = relayMarkV3ToProseMirror(ast);
    assert.deepEqual(inverse, fixture.normalized);
    assert.deepEqual(proseMirrorV3ToRelayMark(inverse), ast);
  } finally { replica.destroy(); }
});

test('draft image projection rejects temporary media, unsupported attrs and hidden children', () => {
  const rejectNode = (edit, reason) => {
    const document = clone(fixture.normalized);
    edit(document.content[1], document);
    assert.throws(() => proseMirrorV3ToRelayMark(document), reason);
  };
  for (const src of ['blob:preview', 'data:image/png;base64,AA==', 'javascript:alert(1)',
    'http://example.org/image.png', '/m/../private', ' https://example.org/image.png',
    'https://example.org\\@evil.test/image.png', 'https://user:pass@example.org/image.png']) {
    rejectNode(image => { image.attrs.src = src; }, /Image src/);
  }
  rejectNode(image => { image.attrs.width = 120; }, /dimensions/);
  rejectNode(image => { image.attrs.status = 'uploading'; }, /Unsupported/);
  rejectNode(image => { image.attrs.alt = { text: 'wrong' }; }, /image alt/);
  rejectNode(image => { image.attrs.title = 'two\nlines'; }, /image title/);
  rejectNode(image => { image.content = [{ type: 'text', text: 'hidden' }]; }, /Image cannot/);
  rejectNode(image => { delete image.attrs.relaymarkId; }, /relaymarkId/);
  rejectNode((image, document) => { image.attrs.relaymarkId = document.content[0].attrs.relaymarkId; }, /Duplicate/);

  const ast = proseMirrorV3ToRelayMark(fixture.normalized);
  const rejectAST = (edit, reason) => {
    const candidate = clone(ast);
    edit(candidate.blocks[1]);
    assert.throws(() => relayMarkV3ToProseMirror(candidate), reason);
  };
  rejectAST(image => { image.props.src = 'blob:lost'; }, /Image src/);
  rejectAST(image => { image.props.uploadPercent = 50; }, /Unsupported/);
  rejectAST(image => { image.content = [{ type: 'text', text: 'hidden' }]; }, /Image cannot/);
});

test('a durable HTTPS image with nullable optional text is portable', () => {
  const document = clone(fixture.normalized);
  Object.assign(document.content[1].attrs, {
    src: 'https://images.example.org/figure.png', alt: null, title: null
  });
  const ast = proseMirrorV3ToRelayMark(document);
  assert.deepEqual(ast.blocks[1].props,
    { src: 'https://images.example.org/figure.png', alt: null, title: null });
  assert.deepEqual(relayMarkV3ToProseMirror(ast), document);
});
