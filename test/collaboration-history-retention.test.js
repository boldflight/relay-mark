import test from 'node:test'
import assert from 'node:assert/strict'
import * as Y from 'yjs'
import {captureTextItems} from '../adapters/collaboration/text-items.js'
import {installHistoryCounterpartRetention,exportHistorySnapshot} from '../adapters/collaboration/history-lineage.js'
import {formatAttributionCut} from '../adapters/collaboration/format-attribution-cut.js'

function fixture(mode='formatting') {
 const doc=new Y.Doc(),root=doc.getXmlFragment('default')
 for(const text of ['Hello','unreferenced']){const p=new Y.XmlElement('paragraph'),t=new Y.XmlText();p.insert(0,[t]);root.insert(root.length,[p]);t.insert(0,text)}
 const selected=captureTextItems(root,{path:[0,0],index:0,length:5}),parentID={...root.get(0)._item.id},otherID={...root.get(1)._item.id}
 const key=Symbol('test-history'),owner=new Y.UndoManager(root,{trackedOrigins:new Set(['local']),captureTimeout:0})
 const metadata={operationID:'70000000-0000-4000-8000-000000000001',copies:[]}
 if(mode==='formatting')metadata.formattingTextItems=selected
 else if(mode==='inserted')metadata.insertedTextItems=selected
 else metadata.copies=[{source:selected,destination:selected}]
 const previous=doc.gcFilter,dispose=installHistoryCounterpartRetention(doc,owner,key)
 doc.transact(()=>root.get(0).get(0).format(0,5,{bold:{}}),'local')
 owner.undoStack[0].meta.set(key,metadata)
 const peer=new Y.Doc();Y.applyUpdate(peer,Y.encodeStateAsUpdate(doc))
 const updates=[];peer.on('update',u=>updates.push(u));peer.getXmlFragment('default').delete(0,2)
 return {doc,owner,key,metadata,selected,parentID,otherID,previous,dispose,peer,update:Y.mergeUpdates(updates),
  close(){dispose();owner.destroy();doc.destroy();peer.destroy()}}
}
for(const mode of ['formatting','inserted','copy'])test(`remote deletion retains ${mode} counterparts and ancestors; clearing history releases them`,()=>{
 const h=fixture(mode);try{
  Y.applyUpdate(h.doc,h.update,'remote')
  const parent=Y.getItem(h.doc.store,h.parentID),text=Y.getItem(h.doc.store,h.selected.runs[0].item)
  assert.ok(parent.content instanceof Y.ContentType)
  assert.ok(text.content instanceof Y.ContentString)
  assert.equal(text.keep,false,'extra retention must not take ownership of Yjs keep flags')
  assert.ok(Y.getItem(h.doc.store,h.otherID).content instanceof Y.ContentDeleted,'unreferenced parent is collected')
  const cut=formatAttributionCut(h.doc)
  h.owner.clear();Y.tryGc(Y.createDeleteSetFromStructStore(h.doc.store),h.doc.store,h.doc.gcFilter)
  assert.ok(Y.getItem(h.doc.store,h.parentID).content instanceof Y.ContentDeleted)
  assert.equal(formatAttributionCut(h.doc),cut,'collection does not change the causal/content cut')
 }finally{h.close()}
})

test('currently popped and in-flight metadata remain protected while absent from stacks',()=>{
 for(const mode of ['popped','inflight']){
  const h=fixture();try{
   const entry=h.owner.undoStack.pop();h.dispose()
   if(mode==='popped')h.owner.currStackItem=entry
   let active=mode==='inflight'?[h.metadata]:[]
   const dispose=installHistoryCounterpartRetention(h.doc,h.owner,h.key,()=>active)
   try{
    Y.applyUpdate(h.doc,h.update,'remote')
    assert.ok(Y.getItem(h.doc.store,h.parentID).content instanceof Y.ContentType)
    h.owner.currStackItem=null;active=[]
    // A later transaction invalidates the transient reference index.
    h.doc.transact(()=>{})
    Y.tryGc(Y.createDeleteSetFromStructStore(h.doc.store),h.doc.store,h.doc.gcFilter)
    assert.ok(Y.getItem(h.doc.store,h.parentID).content instanceof Y.ContentDeleted)
   }finally{dispose()}
  }finally{h.close()}
 }
})

test('counterpart retention composes with and restores the existing GC policy',()=>{
 const h=fixture();try{
  h.dispose();const original=item=>item.id.client!==h.otherID.client || item.id.clock!==h.otherID.clock
  h.doc.gcFilter=original
  const dispose=installHistoryCounterpartRetention(h.doc,h.owner,h.key)
  Y.applyUpdate(h.doc,h.update,'remote');h.owner.clear()
  Y.tryGc(Y.createDeleteSetFromStructStore(h.doc.store),h.doc.store,h.doc.gcFilter)
  assert.ok(Y.getItem(h.doc.store,h.otherID).content instanceof Y.ContentType)
  assert.ok(Y.getItem(h.doc.store,h.parentID).content instanceof Y.ContentDeleted)
  dispose();assert.equal(h.doc.gcFilter,original)
 }finally{h.close()}
})


test('disposing an inner retention filter cannot leave stale protection in a later wrapper',()=>{
 const h=fixture(),other=new Y.UndoManager(h.doc.getXmlFragment('default'),{trackedOrigins:new Set(),captureTimeout:0})
 const disposeOuter=installHistoryCounterpartRetention(h.doc,other,Symbol('other'))
 try{
  assert.equal(h.doc.gcFilter(Y.getItem(h.doc.store,h.parentID)),false)
  h.dispose();h.owner.clear()
  Y.applyUpdate(h.doc,h.update,'remote')
  assert.ok(Y.getItem(h.doc.store,h.parentID).content instanceof Y.ContentDeleted)
 }finally{disposeOuter();other.destroy();h.close()}
})

test('oversized metadata preserves bytes during GC and refuses checkpoint until history is cleared',()=>{
 const h=fixture();try{
  h.owner.undoStack=Array(4097).fill(h.owner.undoStack[0])
  assert.doesNotThrow(()=>Y.applyUpdate(h.doc,h.update,'remote'))
  assert.ok(Y.getItem(h.doc.store,h.parentID).content instanceof Y.ContentType)
  assert.throws(()=>exportHistorySnapshot(h.doc,h.owner,{scope_token:'bounded'},h.key),/counterpart retention limit/)
  h.owner.clear();Y.tryGc(Y.createDeleteSetFromStructStore(h.doc.store),h.doc.store,h.doc.gcFilter)
  assert.ok(Y.getItem(h.doc.store,h.parentID).content instanceof Y.ContentDeleted)
 }finally{h.close()}
})
