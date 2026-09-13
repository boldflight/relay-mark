import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {runInNewContext} from 'node:vm'
const fixture=JSON.parse(readFileSync(new URL('../adapters/swift/Tests/RelayMarkCollaborationTests/Fixtures/attributed-history-v1.json',import.meta.url),'utf8'))
function owner(){
 const context={crypto:globalThis.crypto,TextEncoder,TextDecoder,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}}
 runInNewContext(readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js',import.meta.url),'utf8'),context)
 return (command,input=null)=>JSON.parse(context.relayCollaborationCall(command,JSON.stringify(input)))
}
const expected=r=>({...fixture.expected,replay_sha256:r.replay_sha256,cut:r.cut})
test('ordered actual placement and formatting records reconstruct exact recipe without local capture',()=>{
 const call=owner(), recipe=JSON.parse(fixture.replay_json)
 call('apply',recipe.baseline)
 let replay=call('createAttributionReplay',{scope_token:fixture.expected.scope_token,binding:fixture.expected.binding})
 for(const step of recipe.steps){
  const prior=replay,record=JSON.stringify(step),before=call('snapshot')
  call('validateAttributionReplay',{replay_json:prior.replay_json,expected:expected(prior)})
  assert.deepEqual(call('snapshot'),before)
  assert.throws(()=>call('applyAttributionRecord',{record_json:record+' ',replay_json:prior.replay_json,expected:expected(prior)}))
  assert.deepEqual(call('snapshot'),before)
  replay=call('applyAttributionRecord',{record_json:record,replay_json:prior.replay_json,expected:expected(prior)})
  const after=call('snapshot')
  assert.throws(()=>call('applyAttributionRecord',{record_json:record,replay_json:replay.replay_json,expected:expected(replay)}))
  assert.deepEqual(call('snapshot'),after)
 }
 assert.equal(replay.replay_json,fixture.replay_json)
 const snapshot=call('snapshot')
 call('undo')
 assert.deepEqual(call('snapshot'),snapshot)
 // The separately authenticated owner stack can now be restored at the same cut.
 const restored=owner()
 restored('restoreHistorySnapshot',{snapshot:fixture.owner_snapshot,scope_token:fixture.expected.scope_token,transaction_ids:fixture.transaction_ids})
 restored('validateAttributionReplay',{replay_json:replay.replay_json,expected:expected(replay)})
 restored('undoWithAttributedEvidence',{operation_id:fixture.undo_id,reference_id:fixture.reference_id,replay_json:replay.replay_json,expected:expected(replay)})
 assert.deepEqual(restored('snapshot'),fixture.plain_snapshot)
})
test('out-of-order and unknown records refuse without changing document or history',()=>{
 const call=owner(),recipe=JSON.parse(fixture.replay_json)
 call('apply',recipe.baseline)
 const replay=call('createAttributionReplay',{scope_token:fixture.expected.scope_token,binding:fixture.expected.binding})
 const before=call('snapshot')
 for(const record of [recipe.steps.at(-1),{kind:'unknown',update:[0,0]}]){
  assert.throws(()=>call('applyAttributionRecord',{record_json:JSON.stringify(record),replay_json:replay.replay_json,expected:expected(replay)}))
  assert.deepEqual(call('snapshot'),before)
 }
 call('validateAttributionReplay',{replay_json:replay.replay_json,expected:expected(replay)})
})
