import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {runInNewContext} from 'node:vm'
import {build} from 'esbuild'
import * as Y from 'yjs'
import {historyHookPlugin} from '../scripts/yjs-history-hook.mjs'
import {captureTextItems} from '../adapters/collaboration/text-items.js'
import {captureHistoryFormatEvent} from '../adapters/collaboration/history-lineage.js'
import {createPlacementState,preparePlacementReceipt,placementReceiptCopies,createPlacementResolver,placementUpdateHash} from '../adapters/collaboration/placement-lineage.js'
import {replayFormatAttribution} from '../adapters/collaboration/format-attribution-replay.js'
import {formatAttributionCut} from '../adapters/collaboration/format-attribution-cut.js'
import {createFormatAttribution,prepareFormatAttribution,prepareCopyAttribution,queryFormatInverse} from '../adapters/collaboration/format-attribution.js'

// Exercise the real staged/live UndoManager hook with a private test-only entry.
// Public commands still cannot accept a plan until host receipt delivery is wired.
const privateEntry={name:'test-attribution-entry',setup(build){build.onLoad({filter:/[/\\]collaboration[/\\]runtime\.js$/},({path})=>{
 const source=readFileSync(path,'utf8'),needle='prepareHistoryEvidence(doc, undo, redo, input, lineageKey)'
 assert.equal(source.split(needle).length,2)
 return {contents:source.replace(needle,'prepareHistoryEvidence(doc, undo, redo, input, lineageKey, globalThis.testFormattingPlan || null)'),loader:'js'}
})}}
const built=await build({entryPoints:['adapters/collaboration/runtime.js'],plugins:[privateEntry,historyHookPlugin],bundle:true,write:false,format:'iife',platform:'browser',target:'es2020'})
const publicBuilt=await build({entryPoints:['adapters/collaboration/runtime.js'],plugins:[historyHookPlugin],bundle:true,write:false,format:'iife',platform:'browser',target:'es2020'})
const uuid=n=>`60000000-0000-4000-8000-${String(n).padStart(12,'0')}`
const key=u=>`${u.item.client}:${u.item.clock}@${u.type.client}:${u.type.clock}`
function setup(bold=false,extra=false,publicBridge=false){
 const doc=new Y.Doc({gc:false}),p=new Y.XmlElement('paragraph'),t=new Y.XmlText();p.insert(0,[t]);doc.getXmlFragment('default').insert(0,[p]);t.insert(0,'Hello',bold?{bold:{}}:{});if(extra){t.insert(5,' ');t.insert(6,'X',{bold:{}})}
 const baseline=[...Y.encodeStateAsUpdate(doc)],steps=[]
 function client(initialize=true){const context={crypto:globalThis.crypto,TextEncoder,TextDecoder,console,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}};runInNewContext((publicBridge?publicBuilt:built).outputFiles[0].text,context)
 const call=(cmd,input=null)=>JSON.parse(context.relayCollaborationCall(cmd,JSON.stringify(input)));if(initialize)call('apply',[...Y.encodeStateAsUpdate(doc)]);return {call,plan:value=>{context.testFormattingPlan=value}}
 }
 const a=client(),b=client(),binding={document_id:uuid(90),incarnation:'test'}
 let state=createFormatAttribution(doc),graph=createPlacementState(binding);const ids=[]
 const selection=()=>({version:1,runs:doc.getXmlFragment('default').toArray().flatMap((p,i)=>captureTextItems(doc.getXmlFragment('default'),{path:[i,0],index:0,length:p.get(0).length}).runs)})
 const bytes=result=>Y.mergeUpdates((Array.isArray(result)?result:result.updates).map(u=>Uint8Array.from(u)))
 function apply(update,peer){Y.applyUpdate(doc,update);peer.call('apply',[...update])}
 function structural(owner,peer,command,input,kind,reference){
  const result=owner.call(command,input),update=bytes(result)
  const receipt={version:1,...binding,operation_id:input.operation_id,update_sha256:placementUpdateHash(update),operation:{kind,reference},copies:result.lineage.copies}
  graph=preparePlacementReceipt(graph,{expected_binding:binding,trust:'local',update:[...update],receipt});ids.push(input.operation_id)
  steps.push({kind:'placement',update:[...update],receipt,trust:'local'})
  state=prepareCopyAttribution(state,{beforeDoc:doc,update,effectiveCopies:placementReceiptCopies(graph,binding,ids,input.operation_id)});apply(update,peer)
 }
 function formatting(owner,peer,value,n,range=null){
  const ranges=range?(Array.isArray(range)?range:[range]).map(r=>({path:[0,0],...r})):doc.getXmlFragment('default').toArray().map((p,i)=>({path:[i,0],index:0,length:p.get(0).length}))
  const selected={version:1,runs:ranges.flatMap(r=>captureTextItems(doc.getXmlFragment('default'),r).runs)}
  const update=bytes(owner.call('nativeFormatting',{kind:'formatText',ranges,attributes:{bold:value},operation_id:uuid(n)}))
  const event=captureHistoryFormatEvent(doc,update,{operation_id:uuid(n),mark:'bold',text_items:selected})
  state=prepareFormatAttribution(state,{beforeDoc:doc,update,event});steps.push({kind:'format',update:[...update],event,operation:null});apply(update,peer)
 }
 function successor(){return createPlacementResolver(graph,binding,ids)}
 function plan(n){return queryFormatInverse(state,{operationID:uuid(n),resolveSuccessor:successor(n)})}
 function checkpoint(){const replayJSON=JSON.stringify({version:1,scope_token:'owner-test',binding,baseline,steps});return {replayJSON,expected:{scope_token:'owner-test',binding,replay_sha256:placementUpdateHash(new TextEncoder().encode(replayJSON)),cut:formatAttributionCut(doc)}}}
 return {doc,a,b,structural,formatting,plan,checkpoint,
  restart(){
   const saved=checkpoint(),restored=replayFormatAttribution(saved.replayJSON,saved.expected)
   const transaction_ids=steps.map(s=>s.kind==='format'?s.event.operation_id:s.receipt.operation_id)
   for(const owner of [a,b]) {
    const snapshot=owner.call('exportHistorySnapshot',{scope_token:'owner-test'}),fresh=client(false)
    fresh.call('restoreHistorySnapshot',{snapshot,scope_token:'owner-test',transaction_ids})
    Object.assign(owner,fresh)
   }
   state=restored.state;graph=restored.placementState;ids.splice(0,ids.length,...restored.placementReceiptIDs)
  },
  inverse(owner,peer,n,newID,redo=false){const p=plan(n);owner.plan(p);const selected={version:1,runs:p.targets.map(t=>({...t.unit,count:1}))}
   try {const saved=checkpoint(),result=publicBridge?owner.call(redo?'redoWithAttributedEvidence':'undoWithAttributedEvidence',{operation_id:uuid(newID),reference_id:uuid(n),replay_json:saved.replayJSON,expected:saved.expected}):owner.call(redo?'redoWithEvidence':'undoWithEvidence',{operation_id:uuid(newID)}),update=bytes(result)
    const event=captureHistoryFormatEvent(doc,update,{operation_id:uuid(newID),mark:'bold',text_items:selected}),operation={kind:redo?'redo':'undo',reference:uuid(n)}
    state=prepareFormatAttribution(state,{beforeDoc:doc,update,event,operation,resolveSuccessor:successor(n)});steps.push({kind:'format',update:[...update],event,operation});apply(update,peer);
    if(publicBridge){
     const rebuilt=replayFormatAttribution(result.replay_json,{...saved.expected,replay_sha256:result.replay_sha256,cut:result.cut}),recipe=JSON.parse(result.replay_json),last=recipe.steps.at(-1)
     assert.equal(rebuilt.state.cut,state.cut);assert.deepEqual(recipe.steps.slice(0,-1),steps.slice(0,-1))
     assert.deepEqual(last.update,[...update]);assert.deepEqual(last.operation,operation)
     assert.deepEqual({...last.event,text_items:null},{...event,text_items:null})
     assert.deepEqual(queryFormatInverse(rebuilt.state,{operationID:uuid(newID),resolveSuccessor:successor()}),plan(newID))
     // Runtime coalesces adjacent selected units into bounded exact runs.
     // Persist its exact emitted JSON, not an independently re-encoded witness.
     steps[steps.length-1]=last;assert.equal(result.replay_json,checkpoint().replayJSON)
    }
    return result
   }finally{owner.plan(null)}
  },delta:()=>doc.getXmlFragment('default').toArray().map(p=>p.get(0).toDelta()),close:()=>doc.destroy()}
}
test('verified attribution uses the existing UndoManager to undo and redo peer formatting across restored tail',()=>{
 const h=setup();try{
 h.structural(h.a,h.b,'replaceProseWithLineage',{start:2,end:2,text:'\n',operation_id:uuid(1)},'replace_prose',null)
 h.formatting(h.b,h.a,{},2)
 h.structural(h.a,h.b,'undoWithEvidence',{operation_id:uuid(3)},'undo',uuid(1))
 assert.equal(h.plan(2).targets.length,5)
 h.inverse(h.b,h.a,2,4);assert.deepEqual(h.delta(),[[{insert:'Hello'}]])
 h.inverse(h.b,h.a,4,5,true);assert.deepEqual(h.delta(),[[{insert:'Hello',attributes:{bold:{}}}]])
 const replicas=[h.a,h.b].map(client=>{const doc=new Y.Doc({gc:false});Y.applyUpdate(doc,Uint8Array.from(client.call('state')));return doc})
 try {
  assert.deepEqual(replicas[0].getXmlFragment('default').toJSON(),replicas[1].getXmlFragment('default').toJSON())
  assert.deepEqual(Y.encodeStateVector(replicas[0]),Y.encodeStateVector(replicas[1]))
  assert.equal(formatAttributionCut(replicas[0]),formatAttributionCut(replicas[1]))
 } finally {replicas.forEach(doc=>doc.destroy())}
 }finally{h.close()}
})
test('peer null ABA leaves an explicit noop and refuses before mutating owner state',()=>{
 const h=setup(true);try{
 h.formatting(h.a,h.b,null,10);h.formatting(h.b,h.a,{},11);h.formatting(h.b,h.a,null,12)
 assert.equal(h.plan(10).kind,'noop');const before=h.a.call('state')
 assert.throws(()=>h.inverse(h.a,h.b,10,13),/Unavailable or stale formatting attribution plan/)
 assert.deepEqual(h.a.call('state'),before);assert.deepEqual(h.delta(),[[{insert:'Hello'}]])
 }finally{h.close()}
})

test('partial peer ABA remains protected while attributable suffix undo and redo still work',()=>{
 const h=setup();try{
 h.formatting(h.a,h.b,{},20)
 h.formatting(h.b,h.a,null,21,{index:0,length:2})
 h.formatting(h.b,h.a,{},22,{index:0,length:2})
 assert.equal(h.plan(20).targets.length,3);assert.equal(h.plan(20).protected.length,2)
 h.inverse(h.a,h.b,20,23)
 assert.deepEqual(h.delta(),[[{insert:'He',attributes:{bold:{}}},{insert:'llo'}]])
 h.inverse(h.a,h.b,23,24,true)
 assert.deepEqual(h.delta(),[[{insert:'Hello',attributes:{bold:{}}}]])
 }finally{h.close()}
})

test('undoing a peer override restores the earlier owner contribution and preserves later redo eligibility',()=>{
 const h=setup();try{
 h.formatting(h.a,h.b,{},30);h.formatting(h.b,h.a,null,31)
 h.inverse(h.b,h.a,31,32)
 assert.equal(h.plan(30).targets.length,5)
 h.inverse(h.a,h.b,30,33);assert.deepEqual(h.delta(),[[{insert:'Hello'}]])
 assert.equal(h.plan(32).kind,'noop')
 h.inverse(h.a,h.b,33,34,true);assert.deepEqual(h.delta(),[[{insert:'Hello',attributes:{bold:{}}}]])
 assert.equal(h.plan(32).targets.length,5)
 h.inverse(h.b,h.a,32,35,true);assert.deepEqual(h.delta(),[[{insert:'Hello'}]])
 }finally{h.close()}
})

test('undo of a partial peer override cannot resurrect an earlier retired contribution',()=>{
 const h=setup();try{
 h.formatting(h.a,h.b,{},40);h.formatting(h.b,h.a,null,41,{index:0,length:2})
 h.inverse(h.a,h.b,40,42);assert.deepEqual(h.delta(),[[{insert:'Hello'}]])
 assert.equal(h.plan(41).kind,'noop')
 const before=h.b.call('state')
 assert.throws(()=>h.inverse(h.b,h.a,41,43),/Unavailable or stale formatting attribution plan/)
 assert.deepEqual(h.b.call('state'),before);assert.deepEqual(h.delta(),[[{insert:'Hello'}]])
 }finally{h.close()}
})

test('disjoint attributable islands undo and redo without widening through a peer-owned middle unit',()=>{
 const h=setup();try{
 h.formatting(h.a,h.b,{},50);h.formatting(h.b,h.a,null,51,{index:2,length:1});h.formatting(h.b,h.a,{},52,{index:2,length:1})
 assert.equal(h.plan(50).targets.length,4);assert.equal(h.plan(50).protected.length,1)
 h.inverse(h.a,h.b,50,53)
 assert.deepEqual(h.delta(),[[{insert:'He'},{insert:'l',attributes:{bold:{}}},{insert:'lo'}]])
 h.inverse(h.a,h.b,53,54,true);assert.deepEqual(h.delta(),[[{insert:'Hello',attributes:{bold:{}}}]])
 }finally{h.close()}
})
test('redo reactivates full logical scope after an effective peer inverse unmasks previously protected units',()=>{
 const h=setup(false,true);try{
 h.formatting(h.a,h.b,{},60,{index:0,length:5})
 h.formatting(h.b,h.a,null,61,[{index:0,length:2},{index:6,length:1}])
 h.inverse(h.a,h.b,60,62);assert.deepEqual(h.delta(),[[{insert:'Hello X'}]])
 h.inverse(h.b,h.a,61,63);assert.deepEqual(h.delta(),[[{insert:'Hello '},{insert:'X',attributes:{bold:{}}}]])
 assert.equal(h.plan(62).targets.length,5)
 h.inverse(h.a,h.b,62,64,true)
 assert.deepEqual(h.delta(),[[{insert:'Hello',attributes:{bold:{}}},{insert:' '},{insert:'X',attributes:{bold:{}}}]])
 }finally{h.close()}
})

test('stale or mismatched plans refuse before changing owner bytes or undo metadata',()=>{
 const h=setup();try{
 h.formatting(h.a,h.b,{},70)
 const plan=h.plan(70),before=h.a.call('exportHistorySnapshot',{scope_token:'attribution-refusal'})
 for(const bad of [{...plan,prestate_sha256:'0'.repeat(64)},{...plan,operationID:uuid(99)}]) {
  h.a.plan(bad)
  try {assert.throws(()=>h.a.call('undoWithEvidence',{operation_id:uuid(71)}),/attribution/)}finally{h.a.plan(null)}
  assert.deepEqual(h.a.call('exportHistorySnapshot',{scope_token:'attribution-refusal'}),before)
 }
 h.inverse(h.a,h.b,70,72);assert.deepEqual(h.delta(),[[{insert:'Hello'}]])
 }finally{h.close()}
})


test('serialized evidence replay plus fresh owner runtimes preserves restored-tail undo and redo',()=>{
 const h=setup();try{
  h.structural(h.a,h.b,'replaceProseWithLineage',{start:2,end:2,text:'\n',operation_id:uuid(80)},'replace_prose',null)
  h.formatting(h.b,h.a,{},81)
  h.structural(h.a,h.b,'undoWithEvidence',{operation_id:uuid(82)},'undo',uuid(80))
  const before=h.plan(81);h.restart();assert.deepEqual(h.plan(81),before)
  h.inverse(h.b,h.a,81,83);assert.deepEqual(h.delta(),[[{insert:'Hello'}]])
  const redo=h.plan(83);h.restart();assert.deepEqual(h.plan(83),redo)
  h.inverse(h.b,h.a,83,84,true);assert.deepEqual(h.delta(),[[{insert:'Hello',attributes:{bold:{}}}]])
 }finally{h.close()}
})

test('restart preserves retired masked contributions and full-scope redo after peer undo',()=>{
 const h=setup(false,true);try{
  h.formatting(h.a,h.b,{},85,{index:0,length:5})
  h.formatting(h.b,h.a,null,86,[{index:0,length:2},{index:6,length:1}])
  h.inverse(h.a,h.b,85,87);h.restart()
  assert.equal(h.plan(86).targets.length,1)
  h.inverse(h.b,h.a,86,88);assert.deepEqual(h.delta(),[[{insert:'Hello '},{insert:'X',attributes:{bold:{}}}]])
  h.restart();assert.equal(h.plan(87).targets.length,5)
  h.inverse(h.a,h.b,87,89,true);assert.deepEqual(h.delta(),[[{insert:'Hello',attributes:{bold:{}}},{insert:' '},{insert:'X',attributes:{bold:{}}}]])
 }finally{h.close()}
})

test('replay refuses altered ordering, missing ABA evidence, malformed witnesses and incorrect host expectations',()=>{
 const h=setup();try{
  h.formatting(h.a,h.b,{},100);h.formatting(h.b,h.a,null,101);h.formatting(h.b,h.a,{},102)
  const {replayJSON,expected}=h.checkpoint(),recipe=JSON.parse(replayJSON)
  const before=h.a.call('exportHistorySnapshot',{scope_token:'refusal'})
  const mutations=[r=>r.steps.reverse(),r=>r.steps.splice(1,1),r=>r.steps.push(r.steps[0]),
   r=>r.steps[0].event.changes[0].after.enabled=false,r=>r.steps[0].update[0]=256,
   r=>r.steps[0].extra='unknown',r=>r.scope_token='another-owner',r=>r.binding.incarnation='another-incarnation']
  for(const mutate of mutations){const changed=JSON.parse(replayJSON);mutate(changed)
   const json=JSON.stringify(changed)
   assert.throws(()=>replayFormatAttribution(json,expected),/digest mismatch/)
  }
  // Even with a host-approved envelope, witnesses and bytes still need proof.
  for(const mutate of [r=>r.steps[0].event.changes[0].after.enabled=false,r=>r.steps.push(r.steps[0]),r=>r.steps[0].update[0]=256]){
   const changed=JSON.parse(replayJSON);mutate(changed);const json=JSON.stringify(changed)
   assert.throws(()=>replayFormatAttribution(json,{...expected,replay_sha256:placementUpdateHash(new TextEncoder().encode(json))}))
  }
  for(const bad of [{...expected,cut:'0'.repeat(64)},{...expected,scope_token:'another-owner'},
   {...expected,binding:{...expected.binding,incarnation:'another-incarnation'}}])assert.throws(()=>replayFormatAttribution(replayJSON,bad))
  // CRDT hydration is order-insensitive: final cut is deliberately insufficient
  // as a substitute for the independently retained ordered evidence digest.
  const reversed=new Y.Doc({gc:false});try{
   Y.applyUpdate(reversed,Uint8Array.from(recipe.baseline))
   for(const step of [...recipe.steps].reverse())Y.applyUpdate(reversed,Uint8Array.from(step.update))
   assert.equal(formatAttributionCut(reversed),expected.cut)
  }finally{reversed.destroy()}
  assert.deepEqual(h.a.call('exportHistorySnapshot',{scope_token:'refusal'}),before)
  h.restart();assert.equal(h.plan(100).kind,'noop')
 }finally{h.close()}
})


test('public attributed history bridge undoes and redoes restored peer formatting across fresh owners',()=>{
 const h=setup(false,false,true);try{
  h.structural(h.a,h.b,'replaceProseWithLineage',{start:2,end:2,text:'\n',operation_id:uuid(110)},'replace_prose',null)
  h.formatting(h.b,h.a,{},111)
  h.structural(h.a,h.b,'undoWithEvidence',{operation_id:uuid(112)},'undo',uuid(110))
  h.restart();h.inverse(h.b,h.a,111,113);assert.deepEqual(h.delta(),[[{insert:'Hello'}]])
  h.restart();h.inverse(h.b,h.a,113,114,true);assert.deepEqual(h.delta(),[[{insert:'Hello',attributes:{bold:{}}}]])
 }finally{h.close()}
})

test('public attributed history preserves disjoint peer islands and refuses fully masked noops',()=>{
 const h=setup(false,false,true);try{
  h.formatting(h.a,h.b,{},120);h.formatting(h.b,h.a,null,121,{index:2,length:1});h.formatting(h.b,h.a,{},122,{index:2,length:1})
  h.inverse(h.a,h.b,120,123);assert.deepEqual(h.delta(),[[{insert:'He'},{insert:'l',attributes:{bold:{}}},{insert:'lo'}]])
  h.restart();h.inverse(h.a,h.b,123,124,true)
  assert.deepEqual(h.delta(),[[{insert:'Hello',attributes:{bold:{}}}]])
  h.formatting(h.b,h.a,null,125);h.formatting(h.b,h.a,{},126)
  const before=h.a.call('exportHistorySnapshot',{scope_token:'no-effect'}),saved=h.checkpoint()
  assert.throws(()=>h.inverse(h.a,h.b,124,127),/Unavailable or stale formatting attribution plan/)
  assert.deepEqual(h.a.call('exportHistorySnapshot',{scope_token:'no-effect'}),before)
  assert.deepEqual(h.checkpoint(),saved)
 }finally{h.close()}
})

test('public attributed history rejects foreign references, stale cuts and cross-kind duplicate operation IDs before mutation',()=>{
 const h=setup(false,false,true);try{
  h.structural(h.a,h.b,'replaceProseWithLineage',{start:2,end:2,text:'\n',operation_id:uuid(130)},'replace_prose',null)
  h.formatting(h.b,h.a,{},131)
  const saved=h.checkpoint(),input={operation_id:uuid(132),reference_id:uuid(131),replay_json:saved.replayJSON,expected:saved.expected}
  const before=h.b.call('exportHistorySnapshot',{scope_token:'refusal'})
  for(const bad of [{...input,operation_id:uuid(130)},{...input,reference_id:uuid(130)},
   {...input,expected:{...input.expected,cut:'0'.repeat(64)}},{...input,replay_json:input.replay_json+' '}]) {
   assert.throws(()=>h.b.call('undoWithAttributedEvidence',bad))
   assert.deepEqual(h.b.call('exportHistorySnapshot',{scope_token:'refusal'}),before)
  }
  h.inverse(h.b,h.a,131,133);assert.deepEqual(h.delta(),[[{insert:'He'}],[{insert:'llo'}]])
 }finally{h.close()}
})
