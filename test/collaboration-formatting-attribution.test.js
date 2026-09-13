import test from 'node:test'
import assert from 'node:assert/strict'
import * as Y from 'yjs'
import {captureHistoryMarkerState,captureSelectedFormattingStates,captureHistoryFormatEvent,validateHistoryFormatEvent} from '../adapters/collaboration/history-lineage.js'
import {captureTextItems} from '../adapters/collaboration/text-items.js'

test('effective formatting witnesses distinguish initial absence and peer removal/addition ABA',()=>{
 const doc=new Y.Doc(),root=doc.getXmlFragment('default'),p=new Y.XmlElement('paragraph'),t=new Y.XmlText()
 p.insert(0,[t]);root.insert(0,[p]);t.insert(0,'Hello 🌍')
 const selected=captureTextItems(root,{path:[0,0],index:0,length:5}),before=captureHistoryMarkerState(doc)
 t.format(0,5,{bold:{}})
 const after=captureHistoryMarkerState(doc),states=captureSelectedFormattingStates(before,after,selected,'bold')
 assert.equal(states.length,5);assert.deepEqual(states[0].before,{marker:null,enabled:false})
 assert.equal(states[0].after.enabled,true);assert.ok(states[0].after.marker)
 const peer=new Y.Doc();Y.applyUpdate(peer,Y.encodeStateAsUpdate(doc));const vector=Y.encodeStateVector(peer)
 peer.getXmlFragment('default').get(0).get(0).format(0,5,{bold:null})
 Y.applyUpdate(doc,Y.encodeStateAsUpdate(peer,vector))
 const removed=captureHistoryMarkerState(doc)
 assert.equal(removed[0].marks.bold.enabled,false)
 assert.notDeepEqual(removed[0].marks.bold.marker,states[0].after.marker)
 const next=Y.encodeStateVector(peer);peer.getXmlFragment('default').get(0).get(0).format(0,5,{bold:{}})
 Y.applyUpdate(doc,Y.encodeStateAsUpdate(peer,next))
 const aba=captureHistoryMarkerState(doc)
 assert.equal(aba[0].marks.bold.enabled,true)
 assert.notDeepEqual(aba[0].marks.bold.marker,states[0].after.marker)
 assert.deepEqual(aba[0].unit,states[0].unit)
 peer.destroy();doc.destroy()
})

test('visible marker absence alone cannot distinguish removal ABA',()=>{
 const doc=new Y.Doc(),p=new Y.XmlElement('paragraph'),t=new Y.XmlText()
 p.insert(0,[t]);doc.getXmlFragment('default').insert(0,[p]);t.insert(0,'Hello',{bold:{}})
 t.format(0,5,{bold:null});const first=captureHistoryMarkerState(doc)[0].marks.bold
 const peer=new Y.Doc();Y.applyUpdate(peer,Y.encodeStateAsUpdate(doc));const vector=Y.encodeStateVector(peer)
 peer.getXmlFragment('default').get(0).get(0).format(0,5,{bold:{}})
 peer.getXmlFragment('default').get(0).get(0).format(0,5,{bold:null})
 Y.applyUpdate(doc,Y.encodeStateAsUpdate(peer,vector))
 const final=captureHistoryMarkerState(doc)[0].marks.bold
 assert.deepEqual(first,{marker:null,enabled:false})
 assert.deepEqual(final,first) // This is the proved limitation; never authorize ABA from it.
 peer.destroy();doc.destroy()
})


const operationID=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`
test('paired format events retain actual removal IDs and distinguish peer removal ABA',()=>{
 const producer=new Y.Doc(),p=new Y.XmlElement('paragraph'),t=new Y.XmlText()
 p.insert(0,[t]);producer.getXmlFragment('default').insert(0,[p]);t.insert(0,'Hello',{bold:{}})
 const receiver=new Y.Doc();Y.applyUpdate(receiver,Y.encodeStateAsUpdate(producer))
 const selected=captureTextItems(receiver.getXmlFragment('default'),{path:[0,0],index:0,length:5})
 const events=[],updates=[]
 for(const [n,value] of [[1,null],[2,{}],[3,null]]) {
  let bytes;const listener=update=>{bytes=update};producer.on('update',listener)
  t.format(0,5,{bold:value});producer.off('update',listener)
  const before=Y.encodeStateAsUpdate(receiver)
  const event=captureHistoryFormatEvent(receiver,bytes,{operation_id:operationID(n),mark:'bold',text_items:selected})
  assert.deepEqual(validateHistoryFormatEvent(receiver,bytes,JSON.parse(JSON.stringify(event))),event)
  assert.deepEqual(Y.encodeStateAsUpdate(receiver),before)
  assert.throws(()=>validateHistoryFormatEvent(receiver,bytes,{...event,update_sha256:'a'.repeat(64)}),/Mismatched/)
  events.push(event);updates.push(bytes);Y.applyUpdate(receiver,bytes)
 }
 assert.equal(events[0].changes[0].after.enabled,false)
 assert.equal(events[2].changes[0].after.enabled,false)
 assert.notDeepEqual(events[0].deleted_markers,events[2].deleted_markers)
 // The two removals are distinguished by real deleted IDs, not their equal null values.
 assert.ok(events[0].deleted_markers.length);assert.ok(events[2].deleted_markers.length)
 const empty=new Y.Doc();Y.applyUpdate(empty,Y.encodeStateAsUpdate(receiver))
 assert.throws(()=>captureHistoryFormatEvent(empty,updates[2],{operation_id:operationID(4),mark:'bold',text_items:selected}))
 empty.destroy();receiver.destroy();producer.destroy()
})

test('merged GC formatting events and text edits cannot manufacture a marker witness',()=>{
 const doc=new Y.Doc(),p=new Y.XmlElement('paragraph'),t=new Y.XmlText()
 p.insert(0,[t]);doc.getXmlFragment('default').insert(0,[p]);t.insert(0,'Hello')
 const before=new Y.Doc();Y.applyUpdate(before,Y.encodeStateAsUpdate(doc))
 const vector=Y.encodeStateVector(doc),selected=captureTextItems(before.getXmlFragment('default'),{path:[0,0],index:0,length:5})
 t.format(0,5,{bold:{}});t.format(0,5,{bold:null})
 assert.throws(()=>captureHistoryFormatEvent(before,Y.encodeStateAsUpdate(doc,vector),{operation_id:operationID(5),mark:'bold',text_items:selected}),/Unprovable/)
 const next=Y.encodeStateVector(doc);t.insert(0,'X')
 assert.throws(()=>captureHistoryFormatEvent(before,Y.encodeStateAsUpdate(doc,next),{operation_id:operationID(6),mark:'bold',text_items:selected}),/non-format/)
 before.destroy();doc.destroy()
})

test('a boundary reset outside selected identities is structure, not formatting intent',()=>{
 const producer=new Y.Doc(),p=new Y.XmlElement('paragraph'),t=new Y.XmlText()
 p.insert(0,[t]);producer.getXmlFragment('default').insert(0,[p]);t.insert(0,'Hello 🌍')
 const receiver=new Y.Doc();Y.applyUpdate(receiver,Y.encodeStateAsUpdate(producer))
 const selected=captureTextItems(receiver.getXmlFragment('default'),{path:[0,0],index:0,length:2})
 const before=captureHistoryMarkerState(receiver),beforeBytes=Y.encodeStateAsUpdate(receiver)
 let update;const listener=u=>{update=u};producer.on('update',listener)
 t.format(0,2,{bold:{}});producer.off('update',listener)
 const after=captureHistoryMarkerState(producer)
 const event=captureHistoryFormatEvent(receiver,update,{operation_id:operationID(7),mark:'bold',text_items:selected})
 assert.equal(event.changes.length,2)
 assert.deepEqual(event.changes.map(change=>change.unit),before.slice(0,2).map(row=>row.unit))
 for(let i=2;i<before.length;i++) {
  assert.equal(before[i].marks.bold.enabled,false);assert.equal(after[i].marks.bold.enabled,false)
  assert.equal(before[i].marks.bold.marker,null);assert.ok(after[i].marks.bold.marker)
  assert.ok(event.inserted_markers.some(id=>id.client===after[i].marks.bold.marker.client && id.clock===after[i].marks.bold.marker.clock))
  assert.ok(!event.changes.some(change=>change.unit.item.client===after[i].unit.item.client && change.unit.item.clock===after[i].unit.item.clock))
 }
 // The reset allocation is retained for exact-update verification, but its outside
 // effective marker transitions cannot be added to the selected-intent witness.
 const forged=JSON.parse(JSON.stringify(event))
 forged.changes.push({unit:before[2].unit,before:before[2].marks.bold,after:after[2].marks.bold})
 assert.throws(()=>validateHistoryFormatEvent(receiver,update,forged),/Mismatched/)
 const underscoped=captureTextItems(receiver.getXmlFragment('default'),{path:[0,0],index:0,length:1})
 assert.throws(()=>captureHistoryFormatEvent(receiver,update,{operation_id:operationID(7),mark:'bold',text_items:underscoped}),/untargeted marks/)
 assert.deepEqual(validateHistoryFormatEvent(receiver,update,event),event)
 assert.deepEqual(Y.encodeStateAsUpdate(receiver),beforeBytes)
 receiver.destroy();producer.destroy()
})

test('one transaction combining mark removal and addition refuses a single-mark witness',()=>{
 const producer=new Y.Doc(),p=new Y.XmlElement('paragraph'),t=new Y.XmlText()
 p.insert(0,[t]);producer.getXmlFragment('default').insert(0,[p]);t.insert(0,'Hello',{italic:{}})
 const receiver=new Y.Doc();Y.applyUpdate(receiver,Y.encodeStateAsUpdate(producer))
 const beforeBytes=Y.encodeStateAsUpdate(receiver)
 const selected=captureTextItems(receiver.getXmlFragment('default'),{path:[0,0],index:0,length:5})
 let update;const listener=u=>{update=u};producer.on('update',listener)
 producer.transact(()=>{t.format(0,5,{italic:null});t.format(0,5,{bold:{}})})
 producer.off('update',listener)
 const decoded=Y.decodeUpdate(update)
 assert.ok(decoded.structs.some(item=>item.content instanceof Y.ContentFormat && item.content.key==='bold'))
 assert.ok([...decoded.ds.clients.values()].some(ranges=>ranges.some(range=>range.len>0)))
 assert.deepEqual(t.toDelta(),[{insert:'Hello',attributes:{bold:{}}}])
 // Although this is valid Yjs formatting, a witness for bold cannot erase the
 // exact italic-removal event (nor can an italic witness omit bold allocations).
 assert.throws(()=>captureHistoryFormatEvent(receiver,update,{operation_id:operationID(8),mark:'bold',text_items:selected}),/Unprovable/)
 assert.throws(()=>captureHistoryFormatEvent(receiver,update,{operation_id:operationID(8),mark:'italic',text_items:selected}),/Unprovable/)
 assert.deepEqual(Y.encodeStateAsUpdate(receiver),beforeBytes)
 receiver.destroy();producer.destroy()
})
