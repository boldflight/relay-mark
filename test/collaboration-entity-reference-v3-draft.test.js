import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as Y from 'yjs';
import { proseMirrorV3ToRelayMark, relayMarkV3ToProseMirror } from '../src/collaboration-table-v3.js';
import { compileRelayMark } from '../src/runtime.js';
import { serializeRelayMark } from '../src/serializer.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/entity-reference-v3-draft.json', import.meta.url)));
const schemaURL = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
const schema = JSON.parse(readFileSync(schemaURL));

test('real TipTap/Yjs EntityRef atom preserves authored source and stable block identity', () => {
  const doc = new Y.Doc();
  try {
    Y.applyUpdate(doc, Buffer.from(fixture.update, 'base64'));
    const xml = doc.getXmlFragment(fixture.root).toArray();
    assert.deepEqual(xml.map(node => node.nodeName), ['paragraph', 'relayEntityReference', 'paragraph']);
    assert.equal(xml[1].getAttribute('source'), fixture.authored_source);
    assert.equal(xml[1].getAttribute('relaymarkId'), fixture.expected_ast.blocks[1].id);
    assert.deepEqual(proseMirrorV3ToRelayMark(fixture.normalized), fixture.expected_ast);
    assert.deepEqual(relayMarkV3ToProseMirror(fixture.expected_ast), fixture.normalized);
    assert.deepEqual(validateDocument(fixture.expected_ast), []);
    assert.deepEqual(validateJSONSchema(fixture.expected_ast, schema, fileURLToPath(schemaURL)), []);
    assert.equal(serializeRelayMark(fixture.expected_ast), `Before\n\n${fixture.authored_source}\n\nAfter\n`);
    const compiled = compileRelayMark(fixture.authored_source);
    assert.equal(compiled.document.blocks[0].props.source, fixture.authored_source);
    assert.equal(serializeRelayMark(compiled.document), `${fixture.authored_source}\n`);
  } finally { doc.destroy(); }
});

test('v3 EntityRef rejects contradictory, hydrated, or unsupported atom state', () => {
  const reject = (edit, reason = /Entity reference|Unsupported/) => {
    const input = structuredClone(fixture.normalized);
    edit(input.content[1]);
    assert.throws(() => proseMirrorV3ToRelayMark(input), reason);
  };
  reject(node => { node.attrs.entityRef = 'entity:other'; });
  reject(node => { node.attrs.entityId = 'other'; });
  reject(node => { node.attrs.entityType = 'Person'; });
  reject(node => { node.attrs.label = 'Hydrated label'; });
  reject(node => { node.attrs.projection = 'chip'; });
  reject(node => { node.attrs.source = '@EntityRef(id: "other") {\n  Wrong\n}'; });
  reject(node => { node.attrs.authorized = true; });
  reject(node => { node.content = [{ type: 'text', text: 'hidden' }]; });
  const ast = structuredClone(fixture.expected_ast);
  ast.blocks[1].props.label = 'Hydrated label';
  assert.throws(() => relayMarkV3ToProseMirror(ast), /source\/identity/);
  assert.throws(() => serializeRelayMark(ast), /source\/identity/);
  assert.deepEqual(validateDocument(ast).map(item => item.code), ['relaymark.entity_reference.source']);
});

test('v3 EntityRef accepts authored defaults and multiline attributes without rewriting source', () => {
  const input = structuredClone(fixture.normalized);
  const source = `@EntityRef(\r\n  id: "entity:${input.content[1].attrs.entityId}"\r\n) {\r\n  Fallback\r\n}`;
  Object.assign(input.content[1].attrs, { label: 'Fallback', projection: 'link', source });
  const ast = proseMirrorV3ToRelayMark(input);
  assert.equal(ast.blocks[1].props.source, source);
  assert.deepEqual(relayMarkV3ToProseMirror(ast), input);
  assert.deepEqual(validateDocument(ast), []);
  assert.equal(serializeRelayMark(ast), `Before\n\n${source}\n\nAfter\n`);
  assert.equal(compileRelayMark(source).document.blocks[0].props.source, source);
});
