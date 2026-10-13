import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import * as Y from 'yjs';
import { replayContentEditMutation } from '../adapters/collaboration/content-edit-mutation.js';
import { captureContentEditSnapshot } from '../adapters/collaboration/content-edit-observer.js';
const fixtures = new URL('../spec/relaymark/collaboration/fixtures/', import.meta.url);
const load = name => JSON.parse(fs.readFileSync(new URL(name, fixtures)));
function receipt(row) {
  const { before_snapshot_base64, ...operation } = row.content_edit;
  return { transaction_id: row.transaction_id, sender_state_base64: row.before_state_base64,
    update_base64: row.update_base64, operation: { kind: 'content_edit', ...operation } };
}
function snapshot(base64) {
  const doc = new Y.Doc({ gc: false });
  try { Y.applyUpdate(doc, new Uint8Array(Buffer.from(base64, 'base64')));
    return captureContentEditSnapshot(doc.getXmlFragment('default'));
  } finally { doc.destroy(); }
}

test('same-account manager Enter undo/redo preserves a later independently owned peer paragraph', () => {
  const f = load('content-edit-two-manager-history.json');
  assert.notEqual(f.owner_origin, f.peer_origin);
  assert.notEqual(f.operations[0].content_edit.group.owner_id,f.operations[1].content_edit.group.owner_id);
  assert.deepEqual(f.operations[1].text_items.runs, [{ type: { client: 303, clock: 1 },
    item: { client: 303, clock: 3 }, count: 13 }]);
  for (const [index, effect] of f.proofs.entries()) {
    const result = replayContentEditMutation(effect.evidence);
    assert.equal(result.complete_mutation_correspondence, true);
    assert.equal(result.owned_history_correspondence, true);
    const relabeled=structuredClone(effect.evidence);relabeled.operation.history.owner_id=f.operations[1].content_edit.group.owner_id;assert.throws(()=>replayContentEditMutation(relabeled),/Mixed maintained history owner/);
    assert.deepEqual(result.proven_copies, effect.expected_restored_copies);
    assert.deepEqual(result.text_items, { runs: [] });
    const row = f.operations[index + 2];
    assert.deepEqual(snapshot(row.before_state_base64).children[1],
      snapshot(row.after_state_base64).children[1]);
    const actorOnly = { ...effect.evidence, receipts: f.operations.slice(0, index + 2).map(receipt) };
    assert.throws(() => replayContentEditMutation(actorOnly),
      /Mixed maintained history owner|Owned history differs|Actual maintained inverse|accepted group|prefix differs/);
  }
});

test('pure-delete owned inverse cannot infer manager scope from fresh writer IDs', () => {
  const f = load('current-content-edit-two-manager-delete.json'), result = replayContentEditMutation(f.proof);
  assert.equal(f.proof.writer_client, null);
  assert.equal(result.complete_mutation_correspondence, true);
  assert.equal(result.owned_history_correspondence, true);
  assert.deepEqual(result.fresh_items, { runs: [] });
  assert.deepEqual(result.restored_copies, []);
  const row = f.operations[2];
  assert.deepEqual(snapshot(row.before_state_base64).children[1],
    snapshot(row.after_state_base64).children[1]);
  assert.throws(() => replayContentEditMutation({ ...f.proof,
    receipts: f.operations.slice(0, 2).map(receipt) }),
  /Mixed maintained history owner|Owned history differs|Actual maintained inverse|accepted group|prefix differs/);
});

 test('retained manager reconnect uses one owner across new groups and cannot undo an older group out of order',()=>{
 const f=load('current-content-edit-reconnect-groups.json'),first=f.operations[0],second=f.operations[1];
 assert.notEqual(first.origin,second.origin);
 assert.equal(first.content_edit.group.owner_id,second.content_edit.group.owner_id);
 assert.notEqual(first.content_edit.group.reference,second.content_edit.group.reference);
 for(const effect of f.proofs)assert.equal(replayContentEditMutation(effect.evidence).owned_history_correspondence,true);
 const premature=structuredClone(f.proofs[0].evidence);premature.operation.history={kind:'undo',...first.content_edit.group};
 assert.throws(()=>replayContentEditMutation(premature),/actual accepted group/);
 const originOnly={...f.proofs[1].evidence,receipts:f.operations.slice(0,3).filter(row=>row.origin===second.origin).map(receipt)};
 assert.throws(()=>replayContentEditMutation(originOnly),/actual accepted group/);
 for(const row of f.operations.slice(2))assert.deepEqual(snapshot(row.before_state_base64).children[1],snapshot(row.after_state_base64).children[1]);
 });
