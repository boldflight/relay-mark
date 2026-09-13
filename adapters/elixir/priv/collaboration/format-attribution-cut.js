import * as Y from 'yjs'
import {placementUpdateHash} from './placement-lineage.js'

const maximumBytes = 8 * 1024 * 1024
function settled(doc) {
 if(!Object.hasOwn(doc.store,'pendingStructs') || !Object.hasOwn(doc.store,'pendingDs') ||
    doc.store.pendingStructs!==null || doc.store.pendingDs!==null)throw Error('Incomplete attribution cut')
}
// Internal cut equality only. A fresh GC-enabled clone normalizes deleted
// payload retention (gc:false mirrors and UndoManager keep flags), retaining
// live structs, causal clocks and deletion state. This is neither authorization
// nor snapshot restoration; original receipt/update byte hashes remain exact.
export function formatAttributionCut(doc) {
 settled(doc)
 const bytes=Y.encodeStateAsUpdate(doc)
 if(bytes.length>maximumBytes)throw Error('Oversized attribution cut')
 const normalized=new Y.Doc({gc:true})
 try {
  Y.applyUpdate(normalized,bytes);settled(normalized)
  const encoded=Y.encodeStateAsUpdate(normalized)
  if(encoded.length>maximumBytes)throw Error('Oversized attribution cut')
  return placementUpdateHash(encoded)
 } finally {normalized.destroy()}
}
