import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as Y from 'yjs';
import { proseMirrorToRelayMark, relayMarkToProseMirror } from '../src/document-adapter.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/rich-video-v3-draft.json', import.meta.url)));
const schemaURL = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
const schema = JSON.parse(readFileSync(schemaURL));

test('TipTap/Yjs video preserves only its durable ID in the portable AST', () => {
  const doc = new Y.Doc();
  try {
    Y.applyUpdate(doc, Buffer.from(fixture.update, 'base64'));
    const xml = doc.getXmlFragment(fixture.root).toArray();
    assert.deepEqual(xml.map(node => node.nodeName), ['paragraph', 'videoEmbed', 'paragraph']);
    assert.equal(xml[1].getAttribute('videoId'), fixture.normalized.content[1].attrs.videoId);
    assert.equal(xml[1].getAttribute('source'), 'mux');
    assert.equal(xml[1].getAttribute('status'), 'ready');
    assert.deepEqual(proseMirrorToRelayMark(fixture.normalized), fixture.expected_ast);
    assert.deepEqual(validateDocument(fixture.expected_ast), []);
    assert.deepEqual(validateJSONSchema(fixture.expected_ast, schema, fileURLToPath(schemaURL)), []);
    assert.deepEqual(relayMarkToProseMirror(fixture.expected_ast), fixture.normalized);
  } finally { doc.destroy(); }
});

test('v3 video rejects hydrated or malformed source state', () => {
  const rejectNode = (edit, reason) => {
    const document = structuredClone(fixture.normalized);
    edit(document.content[1]);
    assert.throws(() => proseMirrorToRelayMark(document), reason);
  };
  for (const [key, value] of [
    ['playbackId', 'mux-playback'], ['title', 'Hydrated title'], ['source', 'youtube'],
    ['thumbnailUrl', 'https://example.org/preview.jpg'], ['status', 'preparing'],
    ['youtubeId', 'external'], ['uploadPercent', 50]
  ]) rejectNode(video => { video.attrs[key] = value; }, /Video/);
  for (const value of ['11111111-1111-4111-8111-11111111111A', '../private', null]) {
    rejectNode(video => { video.attrs.videoId = value; }, /Video ID/);
  }
  rejectNode(video => { video.content = [{ type: 'text', text: 'hidden' }]; }, /Video cannot/);
  rejectNode(video => { video.attrs.extra = 'hidden'; }, /Unsupported/);

  const ast = structuredClone(fixture.expected_ast);
  ast.blocks[1].props.status = 'ready';
  assert.throws(() => relayMarkToProseMirror(ast), /Unsupported/);
  const malformedAST = structuredClone(fixture.expected_ast);
  malformedAST.blocks[1].props.videoId = '../private';
  assert.deepEqual(validateDocument(malformedAST).map(diagnostic => diagnostic.code),
    ['relaymark.video_embed.id']);
  const hiddenAST = structuredClone(fixture.expected_ast);
  hiddenAST.blocks[1].content = [{ type: 'text', text: 'hidden' }];
  assert.deepEqual(validateDocument(hiddenAST).map(diagnostic => diagnostic.code),
    ['relaymark.video_embed.children']);
});
