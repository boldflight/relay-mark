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
const uuid=n=>`60000000-0000-4000-8000-${String(n).padStart(12,'0')}`
const key=u=>`${u.item.client}:${u.item.clock}@${u.type.client}:${u.type.clock}`
function setup(bold=false,extra=false){
 const doc=new Y.Doc({gc:false}),p=new Y.XmlElement('paragraph'),t=new Y.XmlText();p.insert(0,[t]);doc.getXmlFragment('default').insert(0,[p]);t.insert(0,'Hello',bold?{bold:{}}:{});if(extra){t.insert(5,' ');t.insert(6,'X',{bold:{}})}
 function client(){const context={crypto:globalThis.crypto,TextEncoder,TextDecoder,console,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}};runInNewContext(built.outputFiles[0].text,context)
 const call=(cmd,input=null)=>JSON.parse(context.relayCollaborationCall(cmd,JSON.stringify(input)));call('apply',[...Y.encodeStateAsUpdate(doc)]);return {call,plan:value=>{context.testFormattingPlan=value}}
 }
 const a=client(),b=client(),binding={document_id:uuid(90),incarnation:'test'}
 let state=createFormatAttribution(doc),graph=createPlacementState(binding);const ids=[]
 const selection=()=>({version:1,runs:doc.getXmlFragment('default').toArray().flatMap((p,i)=>captureTextItems(doc.getXmlFragment('default'),{path:[i,0],index:0,length:p.get(0).length}).runs)})
 const bytes=result=>Y.mergeUpdates((Array.isArray(result)?result:result.updates).map(u=>Uint8Array.from(u)))
 function apply(update,peer){Y.applyUpdate(doc,update);peer.call('apply',[...update])}
 function structural(owner,peer,command,input,kind,reference){
  const result=owner.call(command,input),update=bytes(result)
  graph=preparePlacementReceipt(graph,{expected_binding:binding,trust:'local',update:[...update],receipt:{version:1,...binding,operation_id:input.operation_id,update_sha256:placementUpdateHash(update),operation:{kind,reference},copies:result.lineage.copies}});ids.push(input.operation_id)
  state=prepareCopyAttribution(state,{beforeDoc:doc,update,effectiveCopies:placementReceiptCopies(graph,binding,ids,input.operation_id)});apply(update,peer)
 }
 function formatting(owner,peer,value,n,range=null){
  const ranges=range?(Array.isArray(range)?range:[range]).map(r=>({path:[0,0],...r})):doc.getXmlFragment('default').toArray().map((p,i)=>({path:[i,0],index:0,length:p.get(0).length}))
  const selected={version:1,runs:ranges.flatMap(r=>captureTextItems(doc.getXmlFragment('default'),r).runs)}
  const update=bytes(owner.call('nativeFormatting',{kind:'formatText',ranges,attributes:{bold:value},operation_id:uuid(n)}))
  state=prepareFormatAttribution(state,{beforeDoc:doc,update,event:captureHistoryFormatEvent(doc,update,{operation_id:uuid(n),mark:'bold',text_items:selected})});apply(update,peer)
 }
 function successor(){return createPlacementResolver(graph,binding,ids)}
 function plan(n){return queryFormatInverse(state,{operationID:uuid(n),resolveSuccessor:successor(n)})}
 return {doc,a,b,structural,formatting,plan,
  inverse(owner,peer,n,newID,redo=false){const p=plan(n);owner.plan(p);const selected={version:1,runs:p.targets.map(t=>({...t.unit,count:1}))}
   try {const result=owner.call(redo?'redoWithEvidence':'undoWithEvidence',{operation_id:uuid(newID)}),update=bytes(result)
    state=prepareFormatAttribution(state,{beforeDoc:doc,update,event:captureHistoryFormatEvent(doc,update,{operation_id:uuid(newID),mark:'bold',text_items:selected}),operation:{kind:redo?'redo':'undo',reference:uuid(n)},resolveSuccessor:successor(n)});apply(update,peer);return result
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
