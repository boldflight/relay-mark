import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as Y from 'yjs';
import { proseMirrorV3ToRelayMark, relayMarkV3ToProseMirror } from '../src/collaboration-table-v3.js';
import { serializeRelayMark } from '../src/serializer.js';
import { validateDocument } from '../src/validator.js';
import { compileRelayMark } from '../src/runtime.js';

const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/agent-suggestion-v3-draft.json', import.meta.url)));

test('community TipTap/Yjs authored AgentSuggestion preserves Markdown and stable ID', () => {
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

test('same-document evidence ID projects without rewriting identity', () => {
  const input = structuredClone(fixture.normalized);
  const evidenceID = input.content[0].attrs.relaymarkId;
  input.content[1].attrs.evidence = [evidenceID];
  const ast = proseMirrorV3ToRelayMark(input);
  assert.deepEqual(ast.blocks[1].props.evidence, [evidenceID]);
  assert.deepEqual(validateDocument(ast), []);
  assert.deepEqual(relayMarkV3ToProseMirror(ast), input);
});

test('v3 AgentSuggestion fails closed on host action metadata and malformed authored data', () => {
  const reject = edit => {
    const input = structuredClone(fixture.normalized);
    edit(input.content[1]);
    assert.throws(() => proseMirrorV3ToRelayMark(input));
  };
  reject(node => { node.attrs.proposalId = 'proposal-1'; });
  reject(node => { node.attrs.proposalStatus = 'accepted'; });
  reject(node => { node.attrs.title = 'Host title'; });
  reject(node => { node.attrs.undoable = true; });
  reject(node => { node.attrs.source = '@AgentSuggestion() {}'; });
  reject(node => { node.attrs.review = 'accepted'; });
  reject(node => { node.attrs.confidence = 1.1; });
  reject(node => { node.attrs.content = '  unnormalized'; });
  reject(node => { node.content = [{ type: 'text', text: 'hidden' }]; });
  const ast = structuredClone(fixture.expected_ast);
  ast.blocks[1].props.proposal_id = 'proposal-1';
  assert.throws(() => relayMarkV3ToProseMirror(ast));
});
