import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as Y from 'yjs';
import { proseMirrorV3ToRelayMark, relayMarkV3ToProseMirror } from '../src/collaboration-table-v3.js';
import { serializeRelayMark } from '../src/serializer.js';
import { validateDocument } from '../src/validator.js';
import { compileRelayMark } from '../src/runtime.js';

const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/paper-controls-v3-draft.json', import.meta.url)));

test('community TipTap/Yjs Paper controls retain authored fields and stable IDs', () => {
  const doc = new Y.Doc();
  try {
    Y.applyUpdate(doc, Buffer.from(fixture.update, 'base64'));
    assert.deepEqual(doc.getXmlFragment(fixture.root).toArray().map(node => node.nodeName),
      fixture.normalized.content.map(node => node.type));
    assert.deepEqual(proseMirrorV3ToRelayMark(fixture.normalized), fixture.expected_ast);
    assert.deepEqual(relayMarkV3ToProseMirror(fixture.expected_ast), fixture.normalized);
    assert.deepEqual(validateDocument(fixture.expected_ast), []);
    assert.equal(serializeRelayMark(fixture.expected_ast), fixture.authored_source);
    const compiled = compileRelayMark(fixture.authored_source);
    assert.deepEqual(compiled.diagnostics, []);
    assert.equal(serializeRelayMark(compiled.document), fixture.authored_source);
  } finally { doc.destroy(); }
});

test('v3 Paper controls reject hidden children, unknown state, and source drift', () => {
  const reject = edit => {
    const input = structuredClone(fixture.normalized);
    edit(input.content[2]);
    assert.throws(() => proseMirrorV3ToRelayMark(input));
  };
  reject(node => { node.content = [{ type: 'text', text: 'hidden' }]; });
  reject(node => { node.attrs.authorized = true; });
  reject(node => { node.attrs.kind = 'action'; });
  reject(node => { node.attrs.target = '//evil'; });
  const ast = structuredClone(fixture.expected_ast);
  ast.blocks[2].props.target = 'other';
  assert.throws(() => relayMarkV3ToProseMirror(ast), /source\/fields/);
  assert.throws(() => serializeRelayMark(ast), /source\/fields/);
  assert.deepEqual(validateDocument(ast).map(item => item.code), ['relaymark.paper_control.source']);
});

test('existing ordinary source spellings normalize to canonical portable source', () => {
  const source = `@Anchor(name: 'next')\n\n@Button( target : 'next' , kind:'anchor', label: 'Next' )\n\n@Connection(provider:'google')\n`;
  const compiled = compileRelayMark(source);
  assert.deepEqual(compiled.diagnostics, []);
  assert.equal(serializeRelayMark(compiled.document),
    '@Anchor(name: "next")\n\n@Button(label: "Next", kind: "anchor", target: "next")\n\n@Connection(provider: "google")\n');
  assert.deepEqual(compiled.document.blocks.map(block => block.type),
    ['relay.paper_control', 'relay.paper_control', 'relay.paper_control']);
});
