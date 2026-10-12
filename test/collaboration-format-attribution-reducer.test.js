import test from 'node:test'
import assert from 'node:assert/strict'
import * as Y from 'yjs'
import {readFileSync} from 'node:fs'
import {runInNewContext} from 'node:vm'
import {captureTextItems} from '../adapters/collaboration/text-items.js'
import {captureHistoryFormatEvent} from '../adapters/collaboration/history-lineage.js'
import {createPlacementState,preparePlacementReceipt,placementReceiptCopies,resolvePlacementUnits,placementUpdateHash} from '../adapters/collaboration/placement-lineage.js'
import {formatAttributionCut} from '../adapters/collaboration/format-attribution-cut.js'
import {createFormatAttribution,prepareFormatAttribution,prepareCopyAttribution,queryFormatInverse,fenceFormatAttribution} from '../adapters/collaboration/format-attribution.js'
const id=n=>`50000000-0000-4000-8000-${String(n).padStart(12,'0')}`
function seed(bold=false){const doc=new Y.Doc({gc:false}),p=new Y.XmlElement('paragraph'),t=new Y.XmlText();p.insert(0,[t]);doc.getXmlFragment('default').insert(0,[p]);t.insert(0,'Hello',bold?{bold:{}}:{});return doc}
function fork(doc){const next=new Y.Doc({gc:false});Y.applyUpdate(next,Y.encodeStateAsUpdate(doc));return next}
function format(doc,value,n,length=5){
 const producer=fork(doc),updates=[];producer.on('update',u=>updates.push(u))
 producer.getXmlFragment('default').get(0).get(0).format(0,length,{bold:value})
 const update=Y.mergeUpdates(updates),text_items=captureTextItems(doc.getXmlFragment('default'),{path:[0,0],index:0,length})
 const event=captureHistoryFormatEvent(doc,update,{operation_id:id(n),mark:'bold',text_items});producer.destroy();return {beforeDoc:doc,update,event}
}
const query=(s,n)=>queryFormatInverse(s,{operationID:id(n),resolveSuccessor:u=>u})
test('actual null-removal ABA replaces tokens even when final mark state matches; candidates do not mutate originals',()=>{
 const doc=seed(true);let state=createFormatAttribution(doc)
 for(const [n,value] of [[1,null],[2,{}],[3,null]]){
  const input=format(doc,value,n),before=Y.encodeStateAsUpdate(doc),next=prepareFormatAttribution(state,input)
  assert.deepEqual(Y.encodeStateAsUpdate(doc),before)
  if(n===2)assert.equal(query(state,1).targets.length,5)
  state=next;Y.applyUpdate(doc,input.update)
 }
 assert.deepEqual(query(state,1).targets,[]);assert.equal(query(state,1).kind,'noop');assert.equal(query(state,1).protected.length,5)
 assert.equal(query(state,3).targets.length,5);assert.ok(query(state,3).targets.every(t=>t.enabled))
 assert.equal(query(state,3).prestate_sha256,formatAttributionCut(doc))
 doc.destroy()
})
test('outside selection reset preserves attribution; unknown update fences and stale cut refuses',()=>{
 const doc=seed();let state=createFormatAttribution(doc)
 const full=format(doc,{},4);state=prepareFormatAttribution(state,full);Y.applyUpdate(doc,full.update)
 const partial=format(doc,null,5,2),next=prepareFormatAttribution(state,partial)
 assert.equal(query(next,4).targets.length,3);assert.equal(query(next,4).protected.length,2)
 Y.applyUpdate(doc,partial.update)
 assert.throws(()=>prepareFormatAttribution(state,format(doc,{},6)),/stale/)
 assert.equal(queryFormatInverse(fenceFormatAttribution(next),{operationID:id(4),resolveSuccessor:u=>u}).kind,'fenced')
 assert.throws(()=>prepareFormatAttribution(fenceFormatAttribution(next),format(doc,{},6)),/Fenced/)
 doc.destroy()
})
test('unproven survivor formatting cannot masquerade as a structural copy update',()=>{
 const doc=seed(),state=createFormatAttribution(doc),input=format(doc,{},7)
 assert.throws(()=>prepareCopyAttribution(state,{beforeDoc:doc,update:input.update,effectiveCopies:[]}),/Unproven surviving/)
 assert.throws(()=>prepareFormatAttribution(state,{...input,event:{...input.event,operation_id:'forged'}}))
 doc.destroy()
})
test('actual split and restored-tail copies transfer peer format tokens through existing placement projection',()=>{
 const doc=seed(),context={crypto:globalThis.crypto,TextEncoder,TextDecoder,console,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}}
 runInNewContext(readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js',import.meta.url),'utf8'),context)
 const call=(cmd,input=null)=>JSON.parse(context.relayCollaborationCall(cmd,JSON.stringify(input)))
 call('apply',[...Y.encodeStateAsUpdate(doc)])
 let state=createFormatAttribution(doc),graph=createPlacementState({document_id:id(90),incarnation:'one'});const ids=[],binding=graph.binding
 const key=u=>JSON.stringify([u.item.client,u.item.clock,u.type.client,u.type.clock])
 function copy(result,n,kind,reference){
  const update=Y.mergeUpdates(result.updates.map(u=>Uint8Array.from(u)))
  graph=preparePlacementReceipt(graph,{expected_binding:binding,trust:'local',update:[...update],receipt:{contract_version:1,kind:'placement_receipt',...binding,operation_id:id(n),update_sha256:placementUpdateHash(update),operation:{kind,reference},copies:result.lineage.copies}});ids.push(id(n))
  const pairs=placementReceiptCopies(graph,binding,ids,id(n))
  const before=Y.encodeStateAsUpdate(doc)
  const next=prepareCopyAttribution(state,{beforeDoc:doc,update,effectiveCopies:pairs})
  assert.deepEqual(Y.encodeStateAsUpdate(doc),before);state=next;Y.applyUpdate(doc,update)
 }
 copy(call('replaceProseWithLineage',{start:2,end:2,text:'\n',operation_id:id(10)}),10,'replace_prose',null)
 const producer=fork(doc),updates=[];producer.on('update',u=>updates.push(u))
 producer.transact(()=>{for(const p of producer.getXmlFragment('default').toArray())p.get(0).format(0,p.get(0).length,{bold:{}})})
 const update=Y.mergeUpdates(updates),selection={runs:[0,1].flatMap(i=>captureTextItems(doc.getXmlFragment('default'),{path:[i,0],index:0,length:doc.getXmlFragment('default').get(i).get(0).length}).runs)}
 state=prepareFormatAttribution(state,{beforeDoc:doc,update,event:captureHistoryFormatEvent(doc,update,{operation_id:id(11),mark:'bold',text_items:selection})});Y.applyUpdate(doc,update);call('apply',[...update])
 copy(call('undoWithEvidence',{operation_id:id(12)}),12,'undo',id(10))
 const projection=resolvePlacementUnits(graph,binding,ids,selection),successors=new Map(projection.map(p=>[key(p.source),p.destination]))
 const plan=queryFormatInverse(state,{operationID:id(11),resolveSuccessor:u=>successors.get(key(u))})
 assert.equal(plan.kind,'apply');assert.equal(plan.targets.length,5);assert.ok(plan.targets.every(t=>!t.enabled));assert.deepEqual(plan.protected,[])
 assert.deepEqual(doc.getXmlFragment('default').get(0).get(0).toDelta(),[{insert:'Hello',attributes:{bold:{}}}])
 producer.destroy();doc.destroy()
})

test('unchanged link attributes survive formatting and copy checks; href mutation refuses',()=>{
 const doc=seed(),leaf=doc.getXmlFragment('default').get(0).get(0)
 leaf.format(0,5,{link:{href:'https://example.test/original',title:'kept'}})
 let state=createFormatAttribution(doc),input=format(doc,{},20)
 state=prepareFormatAttribution(state,input);Y.applyUpdate(doc,input.update)
 assert.equal(query(state,20).targets.length,5)
 assert.deepEqual(leaf.toDelta()[0].attributes.link,{href:'https://example.test/original',title:'kept'})
 const peer=fork(doc),updates=[];peer.on('update',u=>updates.push(u))
 peer.getXmlFragment('default').get(0).get(0).format(0,5,{link:{href:'https://example.test/changed'}})
 assert.throws(()=>prepareCopyAttribution(state,{beforeDoc:doc,update:Y.mergeUpdates(updates),effectiveCopies:[]}),/Unproven surviving/)
 peer.destroy();doc.destroy()
})
test('same-value marker changes inside declared selection are retained but omitted from effective inverse targets',()=>{
 const doc=seed(),state=createFormatAttribution(doc),peer=fork(doc),updates=[]
 peer.on('update',u=>updates.push(u));peer.getXmlFragment('default').get(0).get(0).format(0,2,{bold:{}})
 const update=Y.mergeUpdates(updates),event=captureHistoryFormatEvent(doc,update,{operation_id:id(21),mark:'bold',text_items:captureTextItems(doc.getXmlFragment('default'),{path:[0,0],index:0,length:5})})
 assert.equal(event.changes.length,5)
 const next=prepareFormatAttribution(state,{beforeDoc:doc,update,event}),plan=query(next,21)
 assert.equal(plan.targets.length,2);assert.equal(plan.protected.length,0)
 peer.destroy();doc.destroy()
})

test('explicit B undo restores A provenance; A undo and B redo remain selective',()=>{
 const doc=seed();let state=createFormatAttribution(doc)
 function apply(value,n,operation=null){const input=format(doc,value,n);state=prepareFormatAttribution(state,{...input,operation,resolveSuccessor:u=>u});Y.applyUpdate(doc,input.update)}
 apply({},30);apply(null,31)
 assert.equal(query(state,30).kind,'noop')
 apply({},32,{kind:'undo',reference:id(31)})
 assert.equal(query(state,30).targets.length,5,'B undo restores A attribution')
 assert.equal(query(state,32).targets.length,5,'B redo can invert its own undo')
 const branch=fork(doc),branchInput=format(branch,null,33)
 const branchState=prepareFormatAttribution(state,{...branchInput,operation:{kind:'redo',reference:id(32)},resolveSuccessor:u=>u})
 assert.equal(query(branchState,30).kind,'noop','B redo restores B removal token')
 apply(null,34,{kind:'undo',reference:id(30)})
 assert.equal(query(state,32).kind,'noop','A undo prevents stale B redo from undoing a later change')
 assert.deepEqual(doc.getXmlFragment('default').get(0).get(0).toDelta(),[{insert:'Hello'}])
 branch.destroy();doc.destroy()
})
test('inverse provenance refuses wrong kinds, unknown references and mismatched target witnesses',()=>{
 const doc=seed();let state=createFormatAttribution(doc),input=format(doc,{},40)
 state=prepareFormatAttribution(state,input);Y.applyUpdate(doc,input.update)
 const inverse=format(doc,null,41),resolveSuccessor=u=>u
 for(const operation of [{kind:'redo',reference:id(40)},{kind:'undo',reference:id(99)},{kind:'undo',reference:id(41)}])
  assert.throws(()=>prepareFormatAttribution(state,{...inverse,operation,resolveSuccessor}),/inverse attribution/)
 const partial=format(doc,null,42,2)
 assert.throws(()=>prepareFormatAttribution(state,{...partial,operation:{kind:'undo',reference:id(40)},resolveSuccessor}),/does not match/)
 assert.equal(query(state,40).targets.length,5)
 doc.destroy()
})

test('retiring A while B masks its prefix prevents B undo from resurrecting retired A',()=>{
 const doc=seed();let state=createFormatAttribution(doc)
 function apply(value,n,length=5,operation=null){const input=format(doc,value,n,length);state=prepareFormatAttribution(state,{...input,operation,resolveSuccessor:u=>u});Y.applyUpdate(doc,input.update)}
 apply({},50);apply(null,51,2)
 const aPlan=query(state,50);assert.equal(aPlan.targets.length,3);assert.equal(aPlan.protected.length,2)
 const peer=fork(doc),updates=[];peer.on('update',u=>updates.push(u));peer.getXmlFragment('default').get(0).get(0).format(2,3,{bold:null})
 const update=Y.mergeUpdates(updates),event=captureHistoryFormatEvent(doc,update,{operation_id:id(52),mark:'bold',text_items:captureTextItems(doc.getXmlFragment('default'),{path:[0,0],index:2,length:3})})
 state=prepareFormatAttribution(state,{beforeDoc:doc,update,event,operation:{kind:'undo',reference:id(50)},resolveSuccessor:u=>u});Y.applyUpdate(doc,update)
 const bPlan=query(state,51)
 assert.equal(bPlan.kind,'noop');assert.deepEqual(bPlan.targets,[]);assert.deepEqual(bPlan.protected,[])
 assert.deepEqual(doc.getXmlFragment('default').get(0).get(0).toDelta(),[{insert:'Hello'}])
 assert.equal(query(state,52).targets.length,3,'redo reactivates A only where this inverse actually changed the document')
 peer.destroy();doc.destroy()
})

test('partial inverse retains full logical scope for redo after a masking contribution is retired elsewhere',()=>{
 const doc=seed();let state=createFormatAttribution(doc)
 function changed(index,length,value,n,operation=null){
  const peer=fork(doc),updates=[];peer.on('update',u=>updates.push(u));peer.getXmlFragment('default').get(0).get(0).format(index,length,{bold:value})
  const update=Y.mergeUpdates(updates),event=captureHistoryFormatEvent(doc,update,{operation_id:id(n),mark:'bold',text_items:captureTextItems(doc.getXmlFragment('default'),{path:[0,0],index,length})})
  state=prepareFormatAttribution(state,{beforeDoc:doc,update,event,operation,resolveSuccessor:u=>u});Y.applyUpdate(doc,update);peer.destroy()
 }
 // A owns Hell; B clears He and also independently clears initially-bold o.
 doc.getXmlFragment('default').get(0).get(0).format(4,1,{bold:{}});state=createFormatAttribution(doc)
 changed(0,4,{},60)
 const peer=fork(doc),updates=[];peer.on('update',u=>updates.push(u))
 peer.transact(()=>{peer.getXmlFragment('default').get(0).get(0).format(0,2,{bold:null});peer.getXmlFragment('default').get(0).get(0).format(4,1,{bold:null})})
 const update=Y.mergeUpdates(updates),root=doc.getXmlFragment('default'),text_items={runs:[...captureTextItems(root,{path:[0,0],index:0,length:2}).runs,...captureTextItems(root,{path:[0,0],index:4,length:1}).runs]}
 state=prepareFormatAttribution(state,{beforeDoc:doc,update,event:captureHistoryFormatEvent(doc,update,{operation_id:id(61),mark:'bold',text_items})});Y.applyUpdate(doc,update)
 changed(2,2,null,62,{kind:'undo',reference:id(60)})
 assert.equal(query(state,61).targets.length,1,'B undo must affect only independent final o')
 changed(4,1,{},63,{kind:'undo',reference:id(61)})
 const redo=query(state,62)
 assert.equal(redo.targets.length,4,'A redo recovers masked prefix as well as originally changed tail')
 assert.ok(redo.targets.every(t=>t.enabled));assert.deepEqual(redo.protected,[])
 changed(0,4,{},64,{kind:'redo',reference:id(62)})
 assert.deepEqual(doc.getXmlFragment('default').get(0).get(0).toDelta(),[{insert:'Hello',attributes:{bold:{}}}])
 peer.destroy();doc.destroy()
})

test('same-value logical ownership survives partial undo and redo until the contribution retires',()=>{
 const doc=new Y.Doc({gc:false}),p=new Y.XmlElement('paragraph'),text=new Y.XmlText()
 p.insert(0,[text]);doc.getXmlFragment('default').insert(0,[p]);text.insert(0,'abc')
 let state=createFormatAttribution(doc)
 function apply(positions,enabled,selectedPositions,n,operation=null){
  const peer=fork(doc),updates=[];peer.on('update',u=>updates.push(u))
  peer.transact(()=>{for(const index of positions)peer.getXmlFragment('default').get(0).get(0).format(index,1,{bold:enabled?{}:null})})
  const update=Y.mergeUpdates(updates),root=doc.getXmlFragment('default')
  const text_items={runs:selectedPositions.flatMap(index=>captureTextItems(root,{path:[0,0],index,length:1}).runs)}
  const event=captureHistoryFormatEvent(doc,update,{operation_id:id(n),mark:'bold',text_items})
  state=prepareFormatAttribution(state,{beforeDoc:doc,update,event,operation,resolveSuccessor:u=>u})
  Y.applyUpdate(doc,update);peer.destroy();return event
 }
 apply([2],true,[0,1,2],70) // F bolds c.
 const a=apply([1,2],true,[1,2],71) // A bolds bc; c changes marker, not value.
 assert.ok(a.changes.some(change=>change.before.enabled&&change.after.enabled))
 apply([1],false,[1],72,{kind:'undo',reference:id(71)})
 apply([1,2],false,[1,2],73) // B clears bc after A's partial inverse.
 apply([1],true,[1],74,{kind:'redo',reference:id(72)}) // A reactivates its full bc scope.
 apply([2],true,[2],75,{kind:'undo',reference:id(73)}) // B undo exposes A on c.
 assert.deepEqual(text.toDelta(),[{insert:'a'},{insert:'bc',attributes:{bold:{}}}])
 assert.equal(query(state,70).kind,'noop');assert.equal(query(state,70).protected.length,1)
 const aUndo=query(state,74)
 assert.equal(aUndo.targets.length,1);assert.equal(aUndo.targets[0].enabled,false)
 apply([1],false,[1],76,{kind:'undo',reference:id(74)}) // A retires; c keeps F's value.
 const fUndo=query(state,70)
 assert.equal(fUndo.kind,'apply');assert.equal(fUndo.targets.length,1);assert.equal(fUndo.targets[0].enabled,false)
 apply([2],false,[2],77,{kind:'undo',reference:id(70)})
 assert.deepEqual(text.toDelta(),[{insert:'abc'}]);doc.destroy()
})
