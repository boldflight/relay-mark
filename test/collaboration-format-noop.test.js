import test from 'node:test'
import assert from 'node:assert/strict'
import * as Y from 'yjs'
import {captureTextItems} from '../adapters/collaboration/text-items.js'
import {captureHistoryFormatEvent} from '../adapters/collaboration/history-lineage.js'
import {createFormatAttribution,prepareFormatAttribution,prepareNoEffectFormatAttribution,queryFormatInverse,fenceFormatAttribution} from '../adapters/collaboration/format-attribution.js'
import {replayFormatAttribution} from '../adapters/collaboration/format-attribution-replay.js'
import {placementUpdateHash} from '../adapters/collaboration/placement-lineage.js'
const id=n=>`70000000-0000-4000-8000-${String(n).padStart(12,'0')}`
function fixture(bold=false){
 const doc=new Y.Doc({gc:false}),p=new Y.XmlElement('paragraph'),text=new Y.XmlText()
 p.insert(0,[text]);doc.getXmlFragment('default').insert(0,[p]);text.insert(0,'Hello',bold?{bold:{}}:{})
 const baseline=[...Y.encodeStateAsUpdate(doc)],steps=[];let state=createFormatAttribution(doc)
 const resolver=u=>u
 const format=(value,n,operation=null)=>{
  const peer=new Y.Doc({gc:false});Y.applyUpdate(peer,Y.encodeStateAsUpdate(doc));const updates=[];peer.on('update',u=>updates.push(u))
  peer.getXmlFragment('default').get(0).get(0).format(0,5,{bold:value})
  const update=Y.mergeUpdates(updates),event=captureHistoryFormatEvent(doc,update,{operation_id:id(n),mark:'bold',
   text_items:captureTextItems(doc.getXmlFragment('default'),{path:[0,0],index:0,length:5})})
  state=prepareFormatAttribution(state,{beforeDoc:doc,update,event,operation,resolveSuccessor:resolver})
  Y.applyUpdate(doc,update);steps.push({kind:'format',update:[...update],event,operation});peer.destroy()
 }
 const noop=(n,kind,reference)=>{
  const step={kind:'format_noop',event:{version:1,operation_id:id(n),mark:'bold'},operation:{kind,reference:id(reference)}}
  const before=Y.encodeStateAsUpdate(doc),vector=Y.encodeStateVector(doc),old=state
  state=prepareNoEffectFormatAttribution(state,{beforeDoc:doc,...step,resolveSuccessor:resolver})
  assert.deepEqual(Y.encodeStateAsUpdate(doc),before);assert.deepEqual(Y.encodeStateVector(doc),vector);assert.equal(state.cut,old.cut)
  assert.equal(Object.hasOwn(step,'update'),false);steps.push(step);return step
 }
 const query=n=>queryFormatInverse(state,{operationID:id(n),resolveSuccessor:resolver})
 const replay=()=>{
  const recipe={version:1,scope_token:'qualified-test-scope',binding:{document_id:id(99),incarnation:'one'},baseline,steps}
  const json=JSON.stringify(recipe),expected={scope_token:recipe.scope_token,binding:recipe.binding,replay_sha256:placementUpdateHash(new TextEncoder().encode(json)),cut:state.cut}
  return {json,expected,result:replayFormatAttribution(json,expected)}
 }
 return {doc,format,noop,query,replay,steps,get state(){return state}}
}
test('fully masked undo retires its contribution without Yjs bytes; peer undo cannot resurrect it and redo replays',()=>{
 const f=fixture();try{
  f.format({},1);f.format(null,2)
  assert.equal(f.query(1).kind,'noop');f.noop(3,'undo',1)
  assert.equal(f.query(2).kind,'noop','peer removal must not restore retired owner bold')
  f.noop(4,'undo',2)
  assert.equal(f.query(3).kind,'apply');f.format({},5,{kind:'redo',reference:id(3)})
  assert.deepEqual(f.doc.getXmlFragment('default').get(0).get(0).toDelta(),[{insert:'Hello',attributes:{bold:{}}}])
  const restored=f.replay().result.state
  assert.equal(restored.cut,f.state.cut)
  assert.deepEqual(queryFormatInverse(restored,{operationID:id(5),resolveSuccessor:u=>u}),f.query(5))
  assert.throws(()=>prepareNoEffectFormatAttribution(f.state,{beforeDoc:f.doc,event:{version:1,operation_id:id(6),mark:'bold'},operation:{kind:'undo',reference:id(1)},resolveSuccessor:u=>u}),/Consumed/)
 }finally{f.doc.destroy()}
})
test('masked undo and redo advance distinct identities at one cut and stale references cannot toggle again',()=>{
 const f=fixture();try{
  f.format({},10);f.format(null,11);f.noop(12,'undo',10);f.noop(13,'redo',12)
  const before=Y.encodeStateAsUpdate(f.doc),state=f.state
  assert.throws(()=>prepareNoEffectFormatAttribution(state,{beforeDoc:f.doc,event:{version:1,operation_id:id(14),mark:'bold'},operation:{kind:'undo',reference:id(10)},resolveSuccessor:u=>u}),/Consumed/)
  f.noop(14,'undo',13)
  assert.equal(f.query(11).kind,'noop');assert.deepEqual(Y.encodeStateAsUpdate(f.doc),before)
  assert.equal(f.replay().result.state.cut,state.cut)
 }finally{f.doc.destroy()}
})
test('no-effect candidates refuse effective, stale, fenced, duplicate and malformed claims without state mutation',()=>{
 const f=fixture();try{
  f.format({},20)
  const input={beforeDoc:f.doc,event:{version:1,operation_id:id(22),mark:'bold'},operation:{kind:'undo',reference:id(20)},resolveSuccessor:u=>u}
  assert.throws(()=>prepareNoEffectFormatAttribution(f.state,input),/Effective/)
  f.format(null,21)
  const before=Y.encodeStateAsUpdate(f.doc),state=f.state
  for(const change of [
   {event:{...input.event,operation_id:'invalid'}},{event:{...input.event,mark:'italic'}},
   {event:{...input.event,update_sha256:'0'.repeat(64)}},{operation:{kind:'redo',reference:id(20)}},
   {operation:{kind:'undo',reference:id(99)}},{event:{...input.event,operation_id:id(21)}}
  ])assert.throws(()=>prepareNoEffectFormatAttribution(state,{...input,...change}))
  assert.throws(()=>prepareNoEffectFormatAttribution(fenceFormatAttribution(state),input),/Fenced/)
  const stale=new Y.Doc({gc:false});try{assert.throws(()=>prepareNoEffectFormatAttribution(state,{...input,beforeDoc:stale}),/stale/)}finally{stale.destroy()}
  assert.deepEqual(Y.encodeStateAsUpdate(f.doc),before);assert.equal(f.query(20).kind,'noop')
  f.noop(22,'undo',20)
  const {json,expected}=f.replay(),recipe=JSON.parse(json)
  recipe.steps.at(-1).update=[0,0]
  const forged=JSON.stringify(recipe)
  assert.throws(()=>replayFormatAttribution(forged,{...expected,replay_sha256:placementUpdateHash(new TextEncoder().encode(forged))}),/fields/)
  assert.throws(()=>prepareNoEffectFormatAttribution(f.state,input),/Duplicate/)
 }finally{f.doc.destroy()}
})
test('same-value removal ABA remains masked when an earlier removal is retired without update bytes',()=>{
 const f=fixture(true);try{
  f.format(null,30);f.format({},31);f.format(null,32)
  f.noop(33,'undo',30)
  assert.equal(f.query(32).kind,'apply');assert.ok(f.query(32).targets.every(t=>t.enabled))
  const restored=f.replay().result.state
  assert.deepEqual(queryFormatInverse(restored,{operationID:id(32),resolveSuccessor:u=>u}),f.query(32))
 }finally{f.doc.destroy()}
})
