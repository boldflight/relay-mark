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
test('implicit formatting dispatch proves restarted current owner and redo without host reference',()=>{
 const call=owner()
 call('restoreHistorySnapshot',{snapshot:fixture.owner_snapshot,scope_token:fixture.expected.scope_token,transaction_ids:fixture.transaction_ids})
 const undone=call('undoWithAttributedEvidence',{operation_id:fixture.undo_id,replay_json:fixture.replay_json,expected:fixture.expected})
 assert.deepEqual(call('snapshot'),fixture.plain_snapshot)
 const redone=call('redoWithAttributedEvidence',{operation_id:fixture.redo_id,replay_json:undone.replay_json,expected:expected(undone)})
 assert.deepEqual(call('snapshot'),fixture.bold_snapshot)
 assert.notEqual(redone.replay_sha256,undone.replay_sha256)
})
test('implicit dispatch refuses peer-only and untracked owner stacks without mutation',()=>{
 const call=owner(),recipe=JSON.parse(fixture.replay_json)
 call('apply',recipe.baseline)
 let replay=call('createAttributionReplay',{scope_token:fixture.expected.scope_token,binding:fixture.expected.binding})
 for(const step of recipe.steps)replay=call('applyAttributionRecord',{record_json:JSON.stringify(step),replay_json:replay.replay_json,expected:expected(replay)})
 const before=call('snapshot')
 assert.throws(()=>call('undoWithAttributedEvidence',{operation_id:fixture.undo_id,replay_json:replay.replay_json,expected:expected(replay)}))
 assert.deepEqual(call('snapshot'),before)
 // Untracked local edit changes the cut and must not be converted into attribution.
 call('edit',{kind:'formatText',path:[0,0],index:0,length:1,attributes:{italic:{}}})
 const changed=call('snapshot')
 assert.throws(()=>call('undoWithAttributedEvidence',{operation_id:fixture.undo_id,replay_json:replay.replay_json,expected:expected(replay)}))
 assert.deepEqual(call('snapshot'),changed)
})
test('masked current formatting candidate refuses rather than skipping into older history',()=>{
 const a=owner(),b=owner(),recipe=JSON.parse(fixture.replay_json)
 a('apply',recipe.baseline);b('apply',recipe.baseline)
 let replay=a('createAttributionReplay',{scope_token:fixture.expected.scope_token,binding:fixture.expected.binding})
 const format=(call,peer,value,id)=>{
  const result=call('nativeFormattingWithAttribution',{operation:{kind:'formatText',path:[0,0],index:0,length:1,attributes:{bold:value},operation_id:id},replay_json:replay.replay_json,expected:expected(replay)})
  peer('applyAttributionRecord',{record_json:result.record_json,replay_json:replay.replay_json,expected:expected(replay)})
  replay=result
 }
 format(a,b,{},'00000000-0000-4000-8000-000000000091')
 format(b,a,null,'00000000-0000-4000-8000-000000000092')
 const before=a('snapshot')
 assert.throws(()=>a('undoWithAttributedEvidence',{operation_id:'00000000-0000-4000-8000-000000000093',replay_json:replay.replay_json,expected:expected(replay)}))
 assert.deepEqual(a('snapshot'),before)
 a('validateAttributionReplay',{replay_json:replay.replay_json,expected:expected(replay)})
})
test('attributed prose typing, split, join and styled paste retain exact peer replay',()=>{
 const a=owner(),b=owner(),recipe=JSON.parse(fixture.replay_json)
 a('apply',recipe.baseline);b('apply',recipe.baseline)
 let replay=a('createAttributionReplay',{scope_token:fixture.expected.scope_token,binding:fixture.expected.binding})
 for(const [i,operation] of [{start:1,end:1,text:'日本',attributes:{bold:{}}},{start:1,end:1,text:'\n'},{start:1,end:2,text:''},{start:1,end:1,text:'A\nB\n',attributes:{italic:{}}}].entries()){
  const input={operation:{...operation,operation_id:`00000000-0000-4000-8000-00000000010${i}`},replay_json:replay.replay_json,expected:expected(replay)}
  const result=a('replaceProseWithAttribution',input)
  const received=b('applyAttributionRecord',{record_json:result.record_json,replay_json:replay.replay_json,expected:expected(replay)})
  assert.equal(received.replay_json,result.replay_json)
  assert.deepEqual(a('snapshot'),b('snapshot'))
  const before=a('snapshot')
  assert.throws(()=>a('replaceProseWithAttribution',input))
  assert.deepEqual(a('snapshot'),before)
  replay=result
 }
})
test('implicit structural split undo and redo retain peer formatting and exact peer recipes',()=>{
 const a=owner(),b=owner(),recipe=JSON.parse(fixture.replay_json)
 a('apply',recipe.baseline);b('apply',recipe.baseline)
 let replay=a('createAttributionReplay',{scope_token:fixture.expected.scope_token,binding:fixture.expected.binding})
 const advance=(sender,peer,command,args)=>{
  const result=sender(command,{...args,replay_json:replay.replay_json,expected:expected(replay)})
  const received=peer('applyAttributionRecord',{record_json:result.record_json,replay_json:replay.replay_json,expected:expected(replay)})
  assert.equal(received.replay_json,result.replay_json);assert.deepEqual(sender('snapshot'),peer('snapshot'))
  replay=result;return result
 }
 advance(a,b,'replaceProseWithAttribution',{operation:{start:2,end:2,text:'\n',operation_id:'00000000-0000-4000-8000-000000000201'}})
 advance(b,a,'nativeFormattingWithAttribution',{operation:{kind:'formatText',ranges:[{path:[0,0],index:0,length:2},{path:[1,0],index:0,length:3}],attributes:{bold:{}},operation_id:'00000000-0000-4000-8000-000000000202'}})
 const split=a('snapshot')
 const undone=advance(a,b,'undoWithAttributedEvidence',{operation_id:'00000000-0000-4000-8000-000000000203'})
 assert.equal(undone.kind,'prose')
 const redone=advance(a,b,'redoWithAttributedEvidence',{operation_id:'00000000-0000-4000-8000-000000000204'})
 assert.equal(redone.kind,'prose');assert.deepEqual(a('snapshot'),split)
})
test('implicit attributed typing undo restores exact baseline',()=>{
 const call=owner(),recipe=JSON.parse(fixture.replay_json)
 call('apply',recipe.baseline)
 const baseline=call('snapshot'),replay=call('createAttributionReplay',{scope_token:fixture.expected.scope_token,binding:fixture.expected.binding})
 const forward=call('replaceProseWithAttribution',{operation:{start:1,end:1,text:'日本',operation_id:'00000000-0000-4000-8000-000000000211'},replay_json:replay.replay_json,expected:expected(replay)})
 call('undoWithAttributedEvidence',{operation_id:'00000000-0000-4000-8000-000000000212',replay_json:forward.replay_json,expected:expected(forward)})
 assert.deepEqual(call('snapshot'),baseline)
})
test('batch validates every record before live mutation and retains exact final recipe',()=>{
 const recipe=JSON.parse(fixture.replay_json), call=owner()
 call('apply',recipe.baseline)
 const replay=call('createAttributionReplay',{scope_token:fixture.expected.scope_token,binding:fixture.expected.binding})
 const records=recipe.steps.map(step=>JSON.stringify(step)), before=call('snapshot')
 for(const candidate of [[records[0],'{"kind":"unknown","update":[0,0]}'],[records[0],records[0]],[records[1],records[0]]]){
  assert.throws(()=>call('applyAttributionRecords',{records_json:candidate,replay_json:replay.replay_json,expected:expected(replay)}))
  assert.deepEqual(call('snapshot'),before)
  call('validateAttributionReplay',{replay_json:replay.replay_json,expected:expected(replay)})
 }
 const first=call('applyAttributionRecords',{records_json:records.slice(0,2),replay_json:replay.replay_json,expected:expected(replay)})
 assert.equal(JSON.parse(first.replay_json).steps.length,2)
 const final=records.length===2?first:call('applyAttributionRecords',{records_json:records.slice(2),replay_json:first.replay_json,expected:expected(first)})
 assert.equal(final.replay_json,fixture.replay_json)
 const visible=call('snapshot');call('undo');assert.deepEqual(call('snapshot'),visible)
})
