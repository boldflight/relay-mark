import test from 'node:test'
import assert from 'node:assert/strict'
import * as Y from 'yjs'
import {formatAttributionCut} from '../adapters/collaboration/format-attribution-cut.js'
function seed(doc) {const p=new Y.XmlElement('paragraph'),t=new Y.XmlText();p.insert(0,[t]);doc.getXmlFragment('default').insert(0,[p]);t.insert(0,'Hello world');return t}
function leaf(doc){return doc.getXmlFragment('default').get(0).get(0)}
test('GC-normalized cut matches gc:true owner with UndoManager and gc:false mirror without mutating either',()=>{
 const owner=new Y.Doc({gc:true}),text=seed(owner),mirror=new Y.Doc({gc:false}),peer=new Y.Doc({gc:true})
 Y.applyUpdate(mirror,Y.encodeStateAsUpdate(owner));Y.applyUpdate(peer,Y.encodeStateAsUpdate(owner))
 const local={},manager=new Y.UndoManager(owner.getXmlFragment('default'),{trackedOrigins:new Set([local]),captureTimeout:0})
 owner.on('update',u=>Y.applyUpdate(mirror,u))
 owner.transact(()=>text.delete(0,1),local)
 Y.applyUpdate(peer,Y.encodeStateAsUpdate(owner))
 const vector=Y.encodeStateVector(peer);leaf(peer).delete(1,1);Y.applyUpdate(owner,Y.encodeStateAsUpdate(peer,vector))
 const a=Y.encodeStateAsUpdate(owner),b=Y.encodeStateAsUpdate(mirror),stack=manager.undoStack.length
 assert.notDeepEqual(a,b,'fixture must exercise actual retained-payload divergence')
 assert.equal(formatAttributionCut(owner),formatAttributionCut(mirror))
 assert.deepEqual(Y.encodeStateAsUpdate(owner),a);assert.deepEqual(Y.encodeStateAsUpdate(mirror),b);assert.equal(manager.undoStack.length,stack)
 manager.destroy();owner.destroy();mirror.destroy();peer.destroy()
})
test('equal visible text and marks do not erase hidden format ABA or deleted insertion history',()=>{
 const doc=new Y.Doc({gc:false}),text=seed(doc),before=formatAttributionCut(doc),plain=text.toDelta()
 text.format(0,5,{bold:{}});text.format(0,5,{bold:null})
 assert.deepEqual(text.toDelta(),plain);const aba=formatAttributionCut(doc);assert.notEqual(aba,before)
 text.insert(0,'x');text.delete(0,1)
 assert.deepEqual(text.toDelta(),plain);assert.notEqual(formatAttributionCut(doc),aba)
 const gc=new Y.Doc({gc:true});Y.applyUpdate(gc,Y.encodeStateAsUpdate(doc))
 assert.equal(formatAttributionCut(gc),formatAttributionCut(doc));gc.destroy();doc.destroy()
})
test('same state vector with a new deletion still changes normalized cut',()=>{
 const doc=new Y.Doc({gc:false}),text=seed(doc),vector=Y.encodeStateVector(doc),before=formatAttributionCut(doc)
 text.delete(0,1)
 assert.deepEqual(Y.encodeStateVector(doc),vector);assert.notEqual(formatAttributionCut(doc),before);doc.destroy()
})
test('unsettled out-of-order updates refuse cut hashing',()=>{
 const source=new Y.Doc({gc:false}),text=seed(source),vector=Y.encodeStateVector(source)
 text.insert(0,'later');const incomplete=new Y.Doc()
 Y.applyUpdate(incomplete,Y.encodeStateAsUpdate(source,vector))
 assert.throws(()=>formatAttributionCut(incomplete),/Incomplete/);source.destroy();incomplete.destroy()
})
