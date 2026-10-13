// Fresh operations on maintained Yjs managers, after explicit seed conversion.
// Old fixture files remain historical evidence; their command intents and
// independent expected text are inputs, never rewritten binary histories.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import * as Y from 'yjs';
import {Step} from 'prosemirror-transform';
import {currentOperationSeed} from './current-operation-seed.js';
import {initProseMirrorDoc,updateYFragment} from './canonical-binding.js';
import {createCanonicalEditorSchema,createContentEditWrite} from '../../src/content-edit.js';
import {captureContentEditFootprint} from '../../adapters/collaboration/content-edit-observer.js';
import {bindOwnedHistoryOwner,bindOwnedCommandGroup} from '../../adapters/collaboration/owned-command-group.js';
const directory=new URL('../../spec/relaymark/collaboration/fixtures/',import.meta.url),schema=createCanonicalEditorSchema();
const enc=bytes=>Buffer.from(bytes).toString('base64');
if(process.env.RELAYMARK_WRITE_CURRENT_MANAGERS) for(const name of ['two-manager-delete','reconnect-groups']) {
 const old=JSON.parse(fs.readFileSync(new URL(`content-edit-${name}.json`,directory)));
 const initial=currentOperationSeed(old.initial_state_base64),doc=new Y.Doc({gc:false});Y.applyUpdate(doc,Buffer.from(initial,'base64'));
 const managers=new Map(),rows=[],receipts=new Map();let command;
 for(const row of old.operations){
  const owner=(row.content_edit.group??row.content_edit.history).owner_id;
  if(!managers.has(owner)){
   const origins=new Set(old.operations.filter(r=>(r.content_edit.group??r.content_edit.history).owner_id===owner).map(r=>r.origin));
   const manager=new Y.UndoManager(doc.getXmlFragment('default'),{trackedOrigins:origins,captureTimeout:Infinity});
   bindOwnedHistoryOwner(manager,owner);
   manager.on('stack-item-added',event=>{if(!manager.undoing&&!manager.redoing)bindOwnedCommandGroup(manager,event,command)});
   managers.set(owner,manager);
  }
 }
 const proofs=[];
 for(const [index,row]of old.operations.entries()){
  if(index===2&&old.peer_update_base64)Y.applyUpdate(doc,Buffer.from(old.peer_update_base64,'base64'));
  const {before_snapshot_base64:unused,...declaration}=row.content_edit;
  const owner=(declaration.group??declaration.history).owner_id,manager=managers.get(owner),root=doc.getXmlFragment('default');
  const before=enc(Y.encodeStateAsUpdate(doc)),beforeSnapshot=enc(Y.encodeSnapshot(Y.snapshot(doc))),updates=[];
  const on=update=>updates.push(update);doc.on('update',on);command=row.transaction_id;
  doc.clientID=name==='two-manager-delete'&&index===1?303:101;
  if(declaration.history)manager[declaration.history.kind]();
  else {
   manager.stopCapturing();const initialized=initProseMirrorDoc(root,schema);let target=initialized.doc;
   for(const json of declaration.steps)target=Step.fromJSON(schema,json).apply(target).doc;
   initialized.meta.contentEditWrite=createContentEditWrite(initialized.doc,declaration.steps,target);
   doc.transact(()=>updateYFragment(doc,root,target,initialized.meta),row.origin);
  }
  doc.off('update',on);assert.equal(updates.length,1);
  const operation={kind:'content_edit',...declaration},after=enc(Y.encodeStateAsUpdate(doc));
  rows.push({...row,before_state_base64:before,after_state_base64:after,update_base64:enc(updates[0]),content_edit:{...declaration,before_snapshot_base64:beforeSnapshot}});
  if(declaration.history){
   const original=old.proof??old.proofs[proofs.length].evidence;
   const evidence={...original,initial_state_base64:initial,sender_state_base64:before,current_state_base64:before,
    receipts:original.receipts.map(r=>receipts.get(r.transaction_id)),operation,footprint:captureContentEditFootprint(doc,updates[0])};
   proofs.push(evidence);
  }
  receipts.set(row.transaction_id,{transaction_id:row.transaction_id,sender_state_base64:before,update_base64:enc(updates[0]),operation});
 }
 assert.equal(doc.getXmlFragment('default').get(0).get(0).toString(),'A🌍Z');
 assert.equal(doc.getXmlFragment('default').get(1).get(1).get(0).toString(),'One peer');
 const fixture={...old,description:'Current canonical physical seed and newly emitted maintained manager commands',initial_state_base64:initial,operations:rows};
 if(old.proof)fixture.proof=proofs[0];else fixture.proofs=old.proofs.map((p,i)=>({...p,evidence:proofs[i]}));
 fs.writeFileSync(new URL(`current-content-edit-${name}.json`,directory),JSON.stringify(fixture,null,2)+'\n');
 for(const manager of managers.values())manager.destroy();doc.destroy();
}
