import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import * as Y from 'yjs'
import {createFormatAttribution,prepareFormatAttribution,prepareNoEffectFormatAttribution,prepareCopyAttribution,prepareFormatInverseReconciliation,queryFormatInverse} from '../adapters/collaboration/format-attribution.js'
import {formatAttributionCut} from '../adapters/collaboration/format-attribution-cut.js'
const fixture=JSON.parse(readFileSync(new URL('./fixtures/concurrent-format-inverses.json',import.meta.url),'utf8'))
const resolveSuccessor=u=>u
function setup(){
 const doc=new Y.Doc({gc:false});Y.applyUpdate(doc,Uint8Array.from(fixture.baseline));let state=createFormatAttribution(doc)
 for(const record of [fixture.records.add,fixture.records.clear]){
  const update=Uint8Array.from(record.update)
  state=prepareFormatAttribution(state,{beforeDoc:doc,update,event:record.event,operation:record.operation,resolveSuccessor});Y.applyUpdate(doc,update)
 }
 return {doc,state,resolveSuccessor}
}
function integrate(doc,result){if(result.authoredUpdate)Y.applyUpdate(doc,Uint8Array.from(result.authoredUpdate));if(result.correctionUpdate)Y.applyUpdate(doc,Uint8Array.from(result.correctionUpdate))}
for(const order of [['aUndo','bUndo'],['bUndo','aUndo']])test(`concurrent immutable inverses reconcile ${order.join(' then ')} without caller mutation`,()=>{
 const basis=setup(),current=setup();let state=current.state
 try{
  for(const name of order){
   const before=Y.encodeStateAsUpdate(current.doc),json=JSON.stringify(fixture.records[name])
   const result=prepareFormatInverseReconciliation(state,{beforeDoc:current.doc,basis,recordJSON:json,resolveSuccessor})
   assert.deepEqual(Y.encodeStateAsUpdate(current.doc),before)
   assert.equal(result.recordJSON,json);assert.deepEqual(result.authoredUpdate,fixture.records[name].update||null)
   assert.ok(Object.isFrozen(result));if(result.authoredUpdate)assert.ok(Object.isFrozen(result.authoredUpdate))
   integrate(current.doc,result);assert.equal(formatAttributionCut(current.doc),result.cut);state=result.state
  }
  assert.deepEqual(current.doc.getXmlFragment('default').get(0).get(0).toDelta(),[{insert:'Hello'}])
  assert.equal(queryFormatInverse(state,{operationID:fixture.records.aUndo.event.operation_id,resolveSuccessor}).kind,'apply')
  const before=Y.encodeStateAsUpdate(current.doc)
  assert.throws(()=>prepareFormatInverseReconciliation(state,{beforeDoc:current.doc,basis,recordJSON:JSON.stringify(fixture.records.aUndo),resolveSuccessor}),/Duplicate/)
  assert.deepEqual(Y.encodeStateAsUpdate(current.doc),before)
 }finally{basis.doc.destroy();current.doc.destroy()}
})
test('strict APIs still reject changed-effect inverses; forged basis and original records refuse',()=>{
 const basis=setup(),current=setup();try{
  const a=fixture.records.aUndo,b=fixture.records.bUndo
  const state=prepareNoEffectFormatAttribution(current.state,{beforeDoc:current.doc,event:a.event,operation:a.operation,resolveSuccessor})
  assert.throws(()=>prepareFormatAttribution(state,{beforeDoc:current.doc,event:b.event,operation:b.operation,update:Uint8Array.from(b.update),resolveSuccessor}),/Ineffective/)
  const before=Y.encodeStateAsUpdate(current.doc)
  const changed=structuredClone(b);changed.operation.reference='91000000-0000-4000-8000-000000000098'
  for(const recordJSON of [JSON.stringify(changed),JSON.stringify(b)+' ',JSON.stringify({...a,update:[0,0]})])
   assert.throws(()=>prepareFormatInverseReconciliation(state,{beforeDoc:current.doc,basis,recordJSON,resolveSuccessor}))
  assert.throws(()=>prepareFormatInverseReconciliation(state,{beforeDoc:current.doc,basis:{...basis,state:{}},recordJSON:JSON.stringify(b),resolveSuccessor}),/Unknown/)
  const stale=new Y.Doc();try{assert.throws(()=>prepareFormatInverseReconciliation(state,{beforeDoc:current.doc,basis:{...basis,doc:stale},recordJSON:JSON.stringify(b),resolveSuccessor}),/stale/)}finally{stale.destroy()}
  assert.deepEqual(Y.encodeStateAsUpdate(current.doc),before)
 }finally{basis.doc.destroy();current.doc.destroy()}
})
test('concurrent peer text and unrelated marks survive original integration and correction',()=>{
 const basis=setup(),current=setup();try{
  const peer=new Y.Doc({gc:false});Y.applyUpdate(peer,Y.encodeStateAsUpdate(current.doc));const updates=[];peer.on('update',u=>updates.push(u))
  peer.getXmlFragment('default').get(0).get(0).insert(2,'PEER',{italic:{},link:{href:'https://example.test'}})
  const update=Y.mergeUpdates(updates)
  let state=prepareCopyAttribution(current.state,{beforeDoc:current.doc,update,effectiveCopies:[]});Y.applyUpdate(current.doc,update);peer.destroy()
  const beforePeer=current.doc.getXmlFragment('default').get(0).get(0).toDelta()
  for(const name of ['aUndo','bUndo']){const result=prepareFormatInverseReconciliation(state,{beforeDoc:current.doc,basis,recordJSON:JSON.stringify(fixture.records[name]),resolveSuccessor});integrate(current.doc,result);state=result.state}
  assert.deepEqual(current.doc.getXmlFragment('default').get(0).get(0).toDelta(),beforePeer)
 }finally{basis.doc.destroy();current.doc.destroy()}
})

test('actual original owners apply correction remotely and retain their manager for follow-up redo',async()=>{
 const {build}=await import('esbuild'),{runInNewContext}=await import('node:vm'),{historyHookPlugin}=await import('../scripts/yjs-history-hook.mjs')
 const {captureHistoryFormatEvent}=await import('../adapters/collaboration/history-lineage.js')
 const privatePlan={name:'reconciliation-owner-proof',setup(build){build.onLoad({filter:/[/\\]collaboration[/\\]collaboration-runtime\.js$/},({path})=>{
  const source=readFileSync(path,'utf8'),needle='prepareHistoryEvidence(doc, undo, redo, input, lineageKey)'
  assert.equal(source.split(needle).length,2)
  return {contents:source.replace(needle,'prepareHistoryEvidence(doc, undo, redo, input, lineageKey, globalThis.reconciliationTestPlan || null)'),loader:'js'}
 })}}
 const built=await build({entryPoints:['adapters/collaboration/runtime.js'],plugins:[privatePlan,historyHookPlugin],bundle:true,write:false,format:'iife',platform:'browser',target:'es2020'})
 for(const order of [['aUndo','bUndo'],['bUndo','aUndo']]){
  function owner(){
   const context={crypto:globalThis.crypto,TextEncoder,TextDecoder,console,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}}
   runInNewContext(built.outputFiles[0].text,context)
   const call=(command,input=null)=>JSON.parse(context.relayCollaborationCall(command,JSON.stringify(input)))
   call('apply',fixture.baseline)
   const scope='reconciliation-owner-test';let replay=call('createAttributionReplay',{scope_token:scope,binding:fixture.binding})
   const input=()=>({replay_json:replay.replay_json,expected:{scope_token:scope,binding:fixture.binding,replay_sha256:replay.replay_sha256,cut:replay.cut}})
   return {call,plan:p=>{context.reconciliationTestPlan=p},
    receive(record){replay=call('applyAttributionRecord',{...input(),record_json:record})},
    format(value,id){const result=call('nativeFormattingWithAttribution',{...input(),operation:{kind:'formatText',path:[0,0],index:0,length:5,attributes:{bold:value},operation_id:id}});replay=result;return result},
    undo(id){const result=call('undoWithAttributedEvidence',{...input(),operation_id:id,allow_no_effect:true});replay=result;return result}}
  }
  const a=owner(),b=owner(),ids=fixture.records
  const add=a.format({},ids.add.event.operation_id);b.receive(add.record_json)
  const clear=b.format(null,ids.clear.event.operation_id);a.receive(clear.record_json)
  const doc=new Y.Doc({gc:false});Y.applyUpdate(doc,Uint8Array.from(fixture.baseline));let state=createFormatAttribution(doc)
  for(const result of [add,clear]){const record=JSON.parse(result.record_json),update=Uint8Array.from(record.update);state=prepareFormatAttribution(state,{beforeDoc:doc,update,event:record.event,resolveSuccessor});Y.applyUpdate(doc,update)}
  const basisDoc=new Y.Doc({gc:false});Y.applyUpdate(basisDoc,Y.encodeStateAsUpdate(doc));const basis={doc:basisDoc,state,resolveSuccessor}
  const records={aUndo:a.undo(ids.aUndo.event.operation_id),bUndo:b.undo(ids.bUndo.event.operation_id)}
  try{
   for(const name of order){
    const result=prepareFormatInverseReconciliation(state,{beforeDoc:doc,basis,recordJSON:records[name].record_json,resolveSuccessor})
    integrate(doc,result);state=result.state
    for(const target of [a,b]){if(result.authoredUpdate)target.call('apply',result.authoredUpdate);if(result.correctionUpdate)target.call('apply',result.correctionUpdate)}
   }
   assert.deepEqual(a.call('snapshot'),b.call('snapshot'))
   for(const target of [a,b]){
    const replica=new Y.Doc();try{Y.applyUpdate(replica,Uint8Array.from(target.call('state')));assert.equal(formatAttributionCut(replica),state.cut)}finally{replica.destroy()}
   }
   const plan=queryFormatInverse(state,{operationID:ids.aUndo.event.operation_id,resolveSuccessor})
   assert.equal(plan.targets.length,5)
   a.plan(plan)
   const operationID='91000000-0000-4000-8000-000000000005'
   const redo=a.call('redoWithEvidence',{operation_id:operationID});a.plan(null)
   const update=Y.mergeUpdates(redo.updates.map(u=>Uint8Array.from(u)))
   const event=captureHistoryFormatEvent(doc,update,{operation_id:operationID,mark:'bold',text_items:{version:1,runs:plan.targets.map(t=>({...t.unit,count:1}))}})
   state=prepareFormatAttribution(state,{beforeDoc:doc,update,event,operation:{kind:'redo',reference:ids.aUndo.event.operation_id},resolveSuccessor})
   Y.applyUpdate(doc,update);b.call('apply',[...update])
   assert.deepEqual(doc.getXmlFragment('default').get(0).get(0).toDelta(),[{insert:'Hello',attributes:{bold:{}}}])
   assert.deepEqual(a.call('snapshot'),b.call('snapshot'))
  }finally{doc.destroy();basisDoc.destroy()}
 }
})

test('pending local metadata redo reconciles after its parent acquired a different current effect',async()=>{
 const {runInNewContext}=await import('node:vm')
 const bundle=readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js',import.meta.url),'utf8')
 function owner(){
  const context={crypto:globalThis.crypto,TextEncoder,TextDecoder,console,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}}
  runInNewContext(bundle,context)
  const call=(name,value=null)=>JSON.parse(context.relayCollaborationCall(name,JSON.stringify(value)))
  call('apply',fixture.baseline)
  let replay=call('createAttributionReplay',{scope_token:'pending-local-basis',binding:fixture.binding})
  const invoke=(name,extra)=>{const result=call(name,{replay_json:replay.replay_json,expected:{scope_token:'pending-local-basis',binding:fixture.binding,replay_sha256:replay.replay_sha256,cut:replay.cut},...extra});replay=result;return result}
  return {call,invoke}
 }
 const a=owner(),b=owner(),id=n=>`92000000-0000-4000-8000-${String(n).padStart(12,'0')}`
 const add=a.invoke('nativeFormattingWithAttribution',{operation:{kind:'formatText',path:[0,0],index:0,length:5,attributes:{bold:{}},operation_id:id(1)}})
 b.invoke('applyAttributionRecord',{record_json:add.record_json})
 const clear=b.invoke('nativeFormattingWithAttribution',{operation:{kind:'formatText',path:[0,0],index:0,length:5,attributes:{bold:null},operation_id:id(2)}})
 a.invoke('applyAttributionRecord',{record_json:clear.record_json})
 const aUndo=a.invoke('undoWithAttributedEvidence',{operation_id:id(3),allow_no_effect:true})
 const aRedo=a.invoke('redoWithAttributedEvidence',{operation_id:id(5),allow_no_effect:true})
 const bUndo=b.invoke('undoWithAttributedEvidence',{operation_id:id(4),allow_no_effect:true})
 assert.equal(JSON.parse(aUndo.record_json).kind,'format_noop');assert.equal(JSON.parse(aRedo.record_json).kind,'format_noop')
 const doc=new Y.Doc({gc:false});Y.applyUpdate(doc,Uint8Array.from(fixture.baseline));let state=createFormatAttribution(doc)
 const basisDoc=new Y.Doc({gc:false})
 try{
  for(const result of [add,clear]){const r=JSON.parse(result.record_json),update=Uint8Array.from(r.update);state=prepareFormatAttribution(state,{beforeDoc:doc,update,event:r.event,resolveSuccessor});Y.applyUpdate(doc,update)}
  Y.applyUpdate(basisDoc,Y.encodeStateAsUpdate(doc))
  const basis={doc:basisDoc,state,resolveSuccessor},originalUndo=JSON.parse(aUndo.record_json)
  const localBasis={...basis,state:prepareNoEffectFormatAttribution(state,{beforeDoc:basisDoc,event:originalUndo.event,operation:originalUndo.operation,resolveSuccessor})}
  const receipts=[]
  for(const [record,observed] of [[bUndo,basis],[aUndo,basis],[aRedo,localBasis]]){
   const result=prepareFormatInverseReconciliation(state,{beforeDoc:doc,basis:observed,recordJSON:record.record_json,resolveSuccessor})
   assert.equal(result.recordJSON,record.record_json);integrate(doc,result);state=result.state;receipts.push(result)
  }
  assert.ok(receipts[1].correctionUpdate);assert.ok(receipts[2].correctionUpdate)
  assert.deepEqual(doc.getXmlFragment('default').get(0).get(0).toDelta(),[{insert:'Hello',attributes:{bold:{}}}])
  for(const target of [a,b])for(const receipt of receipts){if(receipt.authoredUpdate)target.call('apply',receipt.authoredUpdate);if(receipt.correctionUpdate)target.call('apply',receipt.correctionUpdate)}
  assert.deepEqual(a.call('snapshot'),b.call('snapshot'))
  const replica=new Y.Doc();try{Y.applyUpdate(replica,Uint8Array.from(a.call('state')));assert.equal(formatAttributionCut(replica),state.cut)}finally{replica.destroy()}
 }finally{doc.destroy();basisDoc.destroy()}
})

test('same UUID and visible contribution cannot substitute a different authored receipt in the basis',()=>{
 const current=setup(),basisDoc=new Y.Doc({gc:false});Y.applyUpdate(basisDoc,Uint8Array.from(fixture.baseline));let basisState=createFormatAttribution(basisDoc)
 try{
  for(const original of [fixture.records.add,fixture.records.clear]){
   const record=structuredClone(original)
   if(record.event.operation_id===fixture.records.clear.event.operation_id){
    const run=record.event.text_items.runs[0]
    record.event.text_items.runs=Array.from({length:run.count},(_,i)=>({...run,item:{client:run.item.client,clock:run.item.clock+i},count:1}))
   }
   const update=Uint8Array.from(record.update)
   basisState=prepareFormatAttribution(basisState,{beforeDoc:basisDoc,update,event:record.event,resolveSuccessor});Y.applyUpdate(basisDoc,update)
  }
  assert.equal(basisState.cut,current.state.cut)
  const before=Y.encodeStateAsUpdate(current.doc)
  assert.throws(()=>prepareFormatInverseReconciliation(current.state,{beforeDoc:current.doc,
   basis:{state:basisState,doc:basisDoc,resolveSuccessor},recordJSON:JSON.stringify(fixture.records.aUndo),resolveSuccessor}),/Incompatible reconciliation event basis/)
  assert.deepEqual(Y.encodeStateAsUpdate(current.doc),before)
 }finally{basisDoc.destroy();current.doc.destroy()}
})
