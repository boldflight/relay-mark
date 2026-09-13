import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import * as Y from 'yjs'
import {formatAttributionCut} from '../adapters/collaboration/format-attribution-cut.js'
const fixture=JSON.parse(readFileSync(new URL('./fixtures/server-format-reconciliation.json',import.meta.url),'utf8'))
for(const example of fixture.cases) for(const gc of [false,true]) test(`Yex reconciliation ${example.name} matches Yjs retained cut (gc=${gc})`,()=>{
 const doc=new Y.Doc({gc})
 try{
  Y.applyUpdate(doc,Uint8Array.from(example.before_update))
  for(const packet of example.packets){
   if(packet.authored_update)Y.applyUpdate(doc,Uint8Array.from(packet.authored_update))
   if(packet.correction_update)Y.applyUpdate(doc,Uint8Array.from(packet.correction_update))
   assert.equal(formatAttributionCut(doc),packet.normalized_cut)
  }
  assert.deepEqual(doc.getXmlFragment('default').get(0).get(0).toDelta(),example.delta)
  assert.equal(formatAttributionCut(doc),example.normalized_cut)
  for(const packet of [...example.packets].reverse()){
   if(packet.correction_update)Y.applyUpdate(doc,Uint8Array.from(packet.correction_update))
   if(packet.authored_update)Y.applyUpdate(doc,Uint8Array.from(packet.authored_update))
  }
  assert.equal(formatAttributionCut(doc),example.normalized_cut)
  const restarted=new Y.Doc({gc})
  try{Y.applyUpdate(restarted,Y.encodeStateAsUpdate(doc));assert.equal(formatAttributionCut(restarted),example.normalized_cut)}finally{restarted.destroy()}
  const reordered=new Y.Doc({gc})
  try{
   for(const packet of [...example.packets].reverse()){
    if(packet.correction_update)Y.applyUpdate(reordered,Uint8Array.from(packet.correction_update))
    if(packet.authored_update)Y.applyUpdate(reordered,Uint8Array.from(packet.authored_update))
   }
   Y.applyUpdate(reordered,Uint8Array.from(example.before_update))
   assert.equal(formatAttributionCut(reordered),example.normalized_cut)
  }finally{reordered.destroy()}
 }finally{doc.destroy()}
})
