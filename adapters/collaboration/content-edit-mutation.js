/** Complete command mutation replay through the maintained editor/CRDT owners.
 * Inputs are trusted retained states and an independently observed footprint.
 * This proves correspondence against trusted receipts, never actor/source authority. */
import * as Y from 'yjs';
import {digest} from 'lib0/hash/sha256';
import {Step} from 'prosemirror-transform';
import {initProseMirrorDoc,updateYFragment} from '@tiptap/y-tiptap';
/*! @license @stablelib/base64 2.0.1
This software is licensed under the MIT license:

Copyright (C) 2016 Dmitry Chestnykh

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
import {decode as decodeBase64} from '@stablelib/base64';
import btoa from 'core-js-pure/actual/btoa.js';
const toBase64=bytes=>{
 const chunks=[];
 for(let i=0;i<bytes.length;i+=3072)chunks.push(btoa(String.fromCharCode(...bytes.subarray(i,i+3072))));
 return chunks.join('');
};
const fromBase64=value=>{
 try{return decodeBase64(value);}catch(error){
  if(error instanceof Error&&(error.message==='Base64Coder: incorrect characters for decoding'||error.message==='Base64Coder: incorrect padding'))throw TypeError('Noncanonical retained replay bytes');
  throw error;
 }
};
import {createCanonicalEditorSchema} from '../../src/editor-model.js';
import {canonicalAttributeCodec} from '../../src/document-attributes.js';
import {physicalAttributeSchemaHash} from '../../src/document-attribute-policy.js';
import {finiteSettingsInputCodec,expectedFiniteVideoDocument,expectedFiniteSlotDocument,prepareAggregateSettingsTransform,aggregateSettingsHistoryGroups,finiteAggregateAttributeCodec,finiteSettingsDependencyRelations} from './finite-settings-history-cut.js';
import {proseMirrorToRelayMark} from '../../src/document-adapter.js';
import {applyContentEdit,createContentEditWrite,buildContentEditWitness} from '../../src/content-edit.js';
import {contentEditWritePlan,contentEditWriteCallbacks} from '../../src/content-edit-write.js';
import {stableStringify,cloneCanonicalJSON as clone} from '../../src/canonical-json.js';
import {bindOwnedHistoryOwner,readOwnedCommandGroup,bindOwnedCommandGroup,bindOwnedCommandHistory,validateOwnedCommandGroup,validateOwnedHistory,retireOwnedHistoryGroups,readOwnedHistoryGroups} from './owned-command-group.js';
import {captureContentEditFootprint,captureContentEditSnapshot} from './content-edit-observer.js';
import {canonicalOperationID} from '../../src/owned-command-group.js';
import {planDocumentDifference} from '../../src/document-patch.js';
import {planRecoveryRetirement,restoreRecoveryDependencyCohort,observeDependencyPredecessors,finalizeRecoveryDependencyCohort} from './reviewed-recovery-retirement.js';
import {protectOwnedHistoryBranches} from './owned-history-branches.js';
import {contentEditIdentityLayout,buildWitness} from '../../src/content-edit-witness.js';
import {importAggregateSettingsSnapshot} from '../../src/document-snapshot.js';
const schema=createCanonicalEditorSchema(),MAX_BYTES=8*1024*1024;
const same=(a,b)=>stableStringify(a)===stableStringify(b);
function fields(value,allowed,required=allowed){if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!allowed.includes(k))||required.some(k=>!Object.hasOwn(value,k)))throw TypeError('Invalid mutation replay evidence');}
function bytes(value){if(typeof value!=='string'||value.length>4*Math.ceil(MAX_BYTES/3))throw TypeError('Invalid retained replay bytes');const result=fromBase64(value,{lastChunkHandling:'strict'});if(result.length>MAX_BYTES||toBase64(result)!==value)throw TypeError('Noncanonical retained replay bytes');return result;}
// A proof doc imports original remote writers between explicit local effects.
// Choose only its unused ephemeral client; never rewrite retained update IDs.
function applyRetainedUpdate(doc,update,origin){const incoming=Y.parseUpdateMeta(update).to;let client=0;while(doc.store.clients.has(client)||incoming.has(client))client++;doc.clientID=client;Y.applyUpdate(doc,update,origin);}
function owner(state){const doc=new Y.Doc({gc:false,guid:'relaymark:ephemeral-command-proof'});applyRetainedUpdate(doc,state);if(doc.store.pendingStructs||doc.store.pendingDs)throw TypeError('Unsettled retained replay state');for(const name of doc.share.keys())if(!['default','relaymark'].includes(name))throw TypeError('Unknown retained replay root');if(!doc.share.has('default'))throw TypeError('Missing retained editor root');const root=doc.getXmlFragment('default');if(root._map.size)throw TypeError('Hidden editor root attributes');if(doc.share.has('relaymark'))doc.getMap('relaymark');captureContentEditSnapshot(doc.getXmlFragment('default'));return doc;}
function fragment(content,offset,count,total){if(offset===0&&count===total)return clone(content);if(content.kind==='string')return {...content,text:content.text.slice(offset,offset+count)};if(['any','json'].includes(content.kind))return {...content,values:content.values.slice(offset,offset+count)};throw TypeError('Unsupported retained item fragmentation');}
function part(record,start,count){const offset=start-record.item.clock;return {...record,item:{client:record.item.client,clock:start},count,origin:offset?{client:record.item.client,clock:start-1}:record.origin,content:fragment(record.content,offset,count,record.count)};}
function retainedPrefix(record,count,known){let clock=record.item.clock,end=clock+count;const records=known.get(record.item.client)||[];let left=0,right=records.length;while(left<right){const mid=(left+right)>>>1;if(records[mid].item.clock+records[mid].count<=clock)left=mid+1;else right=mid;}for(let i=left;i<records.length;i++){const saved=records[i];if(saved.item.clock>clock)break;const n=Math.min(end,saved.item.clock+saved.count)-clock,a=part(record,clock,n),b=part(saved,clock,n);delete a.deleted;delete b.deleted;if(!same(a,b))throw TypeError('Original update rewrites retained item identity');clock+=n;if(clock===end)return;}throw TypeError('Unavailable retained original prefix');}
function intervals(ranges){const result=[];for(const r of ranges.sort((a,b)=>a.item.client-b.item.client||a.item.clock-b.item.clock)){const prev=result.at(-1);if(prev&&prev.item.client===r.item.client&&prev.item.clock+prev.count>=r.item.clock)prev.count=Math.max(prev.item.clock+prev.count,r.item.clock+r.count)-prev.item.clock;else result.push(clone(r));}return result;}
function subtract(range,deleted){let pieces=[range];for(const old of deleted){if(old.item.client!==range.item.client)continue;pieces=pieces.flatMap(p=>{const a=p.item.clock,b=a+p.count,c=old.item.clock,d=c+old.count;if(c>=b||d<=a)return[p];return [...(a<c?[{item:p.item,count:c-a}]:[]),...(d<b?[{item:{client:p.item.client,clock:d},count:b-d}]:[])];});}return pieces;}
function mergeRecords(records,withOrigins){const out=[];for(const r of records.sort((a,b)=>a.item.client-b.item.client||a.item.clock-b.item.clock)){const p=out.at(-1);if(p&&p.item.client===r.item.client&&p.item.clock+p.count===r.item.clock&&same(p.parent,r.parent)&&p.key===r.key&&p.deleted===r.deleted&&p.content.kind===r.content.kind&&['string','any','json'].includes(r.content.kind)&&(!withOrigins||(same(p.right_origin,r.right_origin)&&same(r.origin,{client:p.item.client,clock:r.item.clock-1})))){p.count+=r.count;if(p.content.kind==='string')p.content.text+=r.content.text;else p.content.values.push(...r.content.values);}else out.push(clone(r));}return out;}
function normalized(footprint,before,known,deleted){fields(footprint,['state_vector','structs','declared_deletes','deleted_items']);if(!Array.isArray(footprint.structs)||!Array.isArray(footprint.deleted_items)||!Array.isArray(footprint.declared_deletes)||footprint.structs.length+footprint.deleted_items.length+footprint.declared_deletes.length>1_000_000)throw TypeError('Invalid original mutation footprint');const structs=[];
 for(const r of footprint.structs){const prefix=Math.min(r.count,Math.max(0,(before.get(r.item.client)||0)-r.item.clock));if(prefix)retainedPrefix(r,prefix,known);if(prefix<r.count)structs.push(part(r,r.item.clock+prefix,r.count-prefix));}
 const effective=intervals(footprint.declared_deletes.flatMap(r=>subtract(r,deleted))),deleted_items=[];
 for(const r of footprint.deleted_items){for(const p of subtract({item:r.item,count:r.count},deleted)){const offset=p.item.clock-r.stored_item.clock;deleted_items.push({item:p.item,count:p.count,parent:r.parent,key:r.key,content:fragment(r.content,offset,p.count,r.stored_count)});}}
 return {state_vector:footprint.state_vector,structs:mergeRecords(structs,true),declared_deletes:effective,deleted_items:mergeRecords(deleted_items,false)};
}
function effectiveFootprint(before,footprint){
 const state=Y.encodeStateAsUpdate(before),known=new Map();for(const record of captureContentEditFootprint(before,state).structs){const list=known.get(record.item.client)||[];list.push(record);known.set(record.item.client,list);}
 const deleted=[];for(const [client,ranges]of Y.createDeleteSetFromStructStore(before.store).clients)for(const range of ranges)deleted.push({item:{client,clock:range.clock},count:range.len});
 return normalized(footprint,Y.decodeStateVector(Y.encodeStateVector(before)),known,deleted);
}
export function replayContentEditMutation(evidence){return replayMutation(evidence,canonicalAttributeCodec);}
// Codec selection is private. Only the closed finite input verifier below may
// use the recognized aggregate input; every ordinary exported path is current.
function replayMutation(evidence,attributeCodec){
 if(evidence.operation?.history)return replayOwnedHistory(evidence,attributeCodec);
 fields(evidence,['sender_state_base64','current_state_base64','writer_client','operation','footprint']);const senderBase64=evidence.sender_state_base64,senderBytes=bytes(senderBase64),currentBase64=evidence.current_state_base64,currentBytes=currentBase64===senderBase64?senderBytes:bytes(currentBase64),sender=owner(senderBytes),current=owner(currentBytes);try{
  const before=Y.decodeStateVector(Y.encodeStateVector(current)),clients=new Set();for(const r of evidence.footprint.structs??[])if(r.item.clock+r.count>(before.get(r.item.client)||0))clients.add(r.item.client);
  if(clients.size>1||(clients.size===0?evidence.writer_client!==null:!clients.has(evidence.writer_client)||!Number.isSafeInteger(evidence.writer_client)||evidence.writer_client<0))throw TypeError('Replay writer must be independently observed from fresh structs');
  const initialized=initProseMirrorDoc(sender.getXmlFragment('default'),schema,attributeCodec),expected=applyContentEdit(initialized.doc.toJSON(),evidence.operation);let result=initialized.doc;
  for(const json of evidence.operation.steps){const applied=Step.fromJSON(schema,json).apply(result);if(applied.failed)throw TypeError('Refused maintained command');result=applied.doc;}
  if(!same(result.toJSON(),expected.document))throw TypeError('Maintained command execution disagrees');
  sender.clientID=evidence.writer_client??0;const updates=[];sender.on('update',update=>updates.push(update));initialized.meta.contentEditWrite=contentEditWriteCallbacks(contentEditWritePlan(initialized.doc,result,expected.retained_ranges),result);updateYFragment(sender,sender.getXmlFragment('default'),result,initialized.meta);
  if(updates.length!==1)throw TypeError('Command must produce one maintained mutation transaction');const update=updates[0];
  const known=new Map();for(const record of captureContentEditFootprint(current,currentBytes).structs){const list=known.get(record.item.client)||[];list.push(record);known.set(record.item.client,list);}const ds=Y.createDeleteSetFromStructStore(current.store),deleted=[];for(const [client,ranges]of ds.clients)for(const r of ranges)deleted.push({item:{client,clock:r.clock},count:r.len});
  applyRetainedUpdate(current,update);const footprint=captureContentEditFootprint(current,update),actual=normalized(evidence.footprint,before,known,deleted),replayed=normalized(footprint,before,known,deleted);
  if(!same(actual,replayed))throw TypeError('Original mutation differs from executed maintained command');
  return {footprint,expected_update_base64:toBase64(update),complete_mutation_correspondence:true,retained_field_changes:fieldChanges(replayed)};
 }finally{sender.destroy();current.destroy();}
}

/** Read the admitted retained owner through the same canonical PM binding.
 * Returned JSON is a projection, never a new writable replica or authority. */
export function readContentEditDocument(state_base64){
 const doc=owner(bytes(state_base64));
 try{return clone(initProseMirrorDoc(doc.getXmlFragment('default'),schema,canonicalAttributeCodec).doc.toJSON());}
 finally{doc.destroy();}
}

/** One DOM-free command through the same maintained PM/Yjs writer. The host
 * supplies admitted state and fresh command/manager UUIDs; no actor, grant,
 * draft, source authority or persisted history is manufactured here. */
export function produceContentEdit(input){
 fields(input,['state_base64','writer_client','transaction_id','owner_id','steps']);
 canonicalOperationID(input.transaction_id);canonicalOperationID(input.owner_id);
 if(input.writer_client!==null&&(!Number.isSafeInteger(input.writer_client)||input.writer_client<0))throw TypeError('Invalid actual command writer');
 const state=bytes(input.state_base64),doc=owner(state),origin={};let manager;
 try{
  const root=doc.getXmlFragment('default'),metadata=doc.getMap('relaymark');
  const beforeSnapshot=captureContentEditSnapshot(root),beforeClocks=captureContentEditFootprint(doc,Uint8Array.of(0,0)).state_vector;
  const before_snapshot_base64=toBase64(Y.encodeSnapshot(Y.snapshot(doc)));
  const initialized=initProseMirrorDoc(root,schema,canonicalAttributeCodec),operation={kind:'content_edit',steps:input.steps};
  const expected=applyContentEdit(initialized.doc.toJSON(),operation);
  let result=initialized.doc;
  for(const json of input.steps){const applied=Step.fromJSON(schema,json).apply(result);if(applied.failed)throw TypeError('Refused maintained command');result=applied.doc;}
  if(!same(result.toJSON(),expected.document))throw TypeError('Maintained command execution disagrees');
  manager=new Y.UndoManager([root,metadata],{trackedOrigins:new Set([origin]),captureTimeout:Infinity});
  protectOwnedHistoryBranches(manager);bindOwnedHistoryOwner(manager,input.owner_id);
  const bind=event=>bindOwnedCommandGroup(manager,event,input.transaction_id);
  manager.on('stack-item-added',bind);manager.on('stack-item-updated',bind);
  doc.clientID=input.writer_client??0;
  const updates=[];doc.on('update',update=>updates.push(update));
  initialized.meta.contentEditWrite=createContentEditWrite(initialized.doc,input.steps,result);
  doc.transact(()=>updateYFragment(doc,root,result,initialized.meta),origin);
  if(updates.length!==1)throw TypeError('Command must produce one maintained mutation transaction');
  const update=updates[0],footprint=captureContentEditFootprint(doc,update),group=readOwnedCommandGroup(manager,input.transaction_id);
  const clocks=new Map(beforeClocks.map(v=>[v.client,v.clock]));
  const freshClients=new Set(footprint.structs.filter(item=>item.item.clock+item.count>(clocks.get(item.item.client)||0)).map(item=>item.item.client));
  if(freshClients.size>1)throw TypeError('Multiple actual command writers');
  const actualWriter=freshClients.size?[...freshClients][0]:null;
  if(actualWriter!==null&&actualWriter!==input.writer_client)throw TypeError('Supplied command writer differs from actual fresh allocation');
  const afterSnapshot=captureContentEditSnapshot(root);
  const witness=buildContentEditWitness({sender_before_snapshot:beforeSnapshot,sender_after_snapshot:afterSnapshot,before_snapshot:beforeSnapshot,after_snapshot:afterSnapshot,before_state_vector:beforeClocks,operation:{...operation,group},footprint});
  const content_edit={before_snapshot_base64,steps:input.steps,copies:witness.proven_copies,group};
  const replay=replayContentEditMutation({sender_state_base64:input.state_base64,current_state_base64:input.state_base64,writer_client:actualWriter,operation:{...operation,copies:witness.proven_copies,group},footprint});
  return{update_base64:toBase64(update),state_base64:toBase64(Y.encodeStateAsUpdate(doc)),before_snapshot_base64,authored_document:witness.authored_document,text_items:witness.text_items,content_edit,proof:{...witness,...replay,requires_mutation_correspondence:false}};
 }finally{manager?.destroy();doc.destroy();}
}

function observedWriter(footprint,doc){const clocks=Y.decodeStateVector(Y.encodeStateVector(doc)),clients=new Set();for(const item of footprint.structs)if(item.item.clock+item.count>(clocks.get(item.item.client)||0))clients.add(item.item.client);if(clients.size>1)throw TypeError('Multiple actual command writers');return clients.size?[...clients][0]:null;}
function compareUpdate(current,originalFootprint,update){const state=Y.encodeStateAsUpdate(current),before=Y.decodeStateVector(Y.encodeStateVector(current)),known=new Map();for(const record of captureContentEditFootprint(current,state).structs){const list=known.get(record.item.client)||[];list.push(record);known.set(record.item.client,list);}const deleted=[];for(const[client,ranges]of Y.createDeleteSetFromStructStore(current.store).clients)for(const r of ranges)deleted.push({item:{client,clock:r.clock},count:r.len});applyRetainedUpdate(current,update);const footprint=captureContentEditFootprint(current,update);if(!same(normalized(originalFootprint,before,known,deleted),normalized(footprint,before,known,deleted)))throw TypeError('Original mutation differs from maintained owned history');return{footprint,retained_field_changes:fieldChanges(normalized(footprint,before,known,deleted))};}
function fieldChanges(footprint){const field=r=>r.key!==null||r.content.kind==='format';return{allocated:footprint.structs.filter(field),deleted:footprint.deleted_items.filter(field)};}
function redoneLinks(doc){const result=new Map();let remaining=1_000_000;for(const structs of doc.store.clients.values())for(const item of structs){if(--remaining<0)throw TypeError('Owned history observation budget exhausted');if(item instanceof Y.Item)result.set(item.id.client+':'+item.id.clock,item.redone?item.redone.client+':'+item.redone.clock:null)}return result;}
function restoredCopies(doc,prior,links){const copies=[],snapshot=captureContentEditSnapshot(doc.getXmlFragment('default')),visible=new Set();let remaining=1_000_000;function visit(node){if(node.kind==='text')visible.add(node.type.client+':'+node.type.clock);else for(const child of node.children)visit(child)}visit(snapshot);for(const structs of doc.store.clients.values())for(const source of structs){if(--remaining<0)throw TypeError('Restored copy observation budget exhausted');if(!(source instanceof Y.Item)||!(source.content instanceof Y.ContentString)||!source.redone||source.id.clock>=(prior.get(source.id.client)||0)||links.get(source.id.client+':'+source.id.clock)===source.redone.client+':'+source.redone.clock)continue;const destination=Y.getItem(doc.store,source.redone);if(!(destination instanceof Y.Item)||destination.id.clock>source.redone.clock||destination.id.clock+destination.length<source.redone.clock+source.length||!(destination.content instanceof Y.ContentString)||destination.content.str.slice(source.redone.clock-destination.id.clock,source.redone.clock-destination.id.clock+source.length)!==source.content.str||!(source.parent instanceof Y.XmlText)||!(destination.parent instanceof Y.XmlText)||!source.parent._item||!destination.parent._item)throw TypeError('Unavailable exact maintained restored copy');if(destination.deleted||source.redone.clock<(prior.get(destination.id.client)||0)||!visible.has(destination.parent._item.id.client+':'+destination.parent._item.id.clock))throw TypeError('Unreachable maintained restored copy');const selected=item=>({runs:[{type:{client:item.parent._item.id.client,clock:item.parent._item.id.clock},item:{client:item.id.client,clock:item.id.clock},count:item.length}]});const target=selected(destination);target.runs[0].item={client:source.redone.client,clock:source.redone.clock};target.runs[0].count=source.length;copies.push({source:selected(source),destination:target});}return copies;}
function ownedTextAccounting(doc,before,copies){const snapshot=captureContentEditSnapshot(doc.getXmlFragment('default')),fresh=[];function visit(node){if(node.kind==='text'){for(const run of node.runs){const start=Math.max(run.item.clock,before.get(run.item.client)||0),count=run.item.clock+run.count-start;if(count>0)fresh.push({type:node.type,item:{client:run.item.client,clock:start},count})}}else for(const child of node.children)visit(child)}visit(snapshot);const extent=ranges=>{let total=0;const groups=new Map();for(const run of ranges){if((total+=run.count)>131072||ranges.length>4096)throw TypeError('Owned inverse selection resource limit');const key=run.type.client+':'+run.type.clock+'/'+run.item.client,list=groups.get(key)||[];list.push([run.item.clock,run.item.clock+run.count]);groups.set(key,list)}return[...groups].sort(([a],[b])=>a.localeCompare(b)).map(([key,list])=>{list.sort((a,b)=>a[0]-b[0]);const merged=[];for(const[a,b]of list){const last=merged.at(-1);if(last&&a<last[1])throw TypeError('Duplicate restored destination');if(last&&a===last[1])last[1]=b;else merged.push([a,b])}return[key,merged]})};if(!same(extent(fresh),extent(copies.flatMap(copy=>copy.destination.runs))))throw TypeError('Unaccounted maintained inverse text allocation');return{fresh_items:{runs:fresh},text_items:{runs:[]},proven_copies:copies};}
const ownedObservations=new WeakMap();
/** Read-only immediate history observation, private to this same live owner.
 * It records no new authority and cannot be substituted with a transport object. */
export function captureOwnedHistoryObservation(doc){
 if(!(doc instanceof Y.Doc)||doc.gc!==false||doc.store.pendingStructs||doc.store.pendingDs)throw TypeError('Unavailable retained owned history observer');
 captureContentEditSnapshot(doc.getXmlFragment('default'));
 const token=Object.freeze({});ownedObservations.set(token,{doc,before:Y.decodeStateVector(Y.encodeStateVector(doc)),links:redoneLinks(doc)});return token;
}
/** Exact maintained redone edges and complete fresh inverse text accounting.
 * Accepted groups/receipts and mutation/tree proof remain independent gates. */
export function finishOwnedHistoryObservation(doc,observation){
 const before=ownedObservations.get(observation);if(!before||before.doc!==doc)throw TypeError('Unavailable same-owner history observation');
 const copies=restoredCopies(doc,before.before,before.links),accounting=ownedTextAccounting(doc,before.before,copies);ownedObservations.delete(observation);return accounting;
}
const historyKey='relaymark:operation_ids';
function historyID(value){fields(value,['client','clock']);if(!Number.isSafeInteger(value.client)||value.client<0||!Number.isInteger(value.clock)||value.clock<0||value.clock>0xffffffff)throw TypeError('Invalid retained history identity');return value;}
function historyRange(value){fields(value,['item','count']);historyID(value.item);if(!Number.isInteger(value.count)||value.count<1||value.item.clock+value.count>0x100000000)throw TypeError('Invalid retained history extent');return value;}
function historyIntervals(set){return [...set.clients].sort(([a],[b])=>a-b).map(([client,ranges])=>({client,ranges:ranges.map(({clock,len})=>({clock,len}))}));}
function historySet(value){if(!Array.isArray(value)||value.length>1_000_000)throw TypeError('Invalid retained stack set');const set=Y.createDeleteSet();let previous=-1,total=0;for(const row of value){fields(row,['client','ranges']);if(!Number.isSafeInteger(row.client)||row.client<=previous||!Array.isArray(row.ranges)||!row.ranges.length)throw TypeError('Noncanonical retained stack set');previous=row.client;let end=-1;const ranges=[];for(const range of row.ranges){fields(range,['clock','len']);if(!Number.isInteger(range.clock)||range.clock<=end||!Number.isInteger(range.len)||range.len<1||range.clock+range.len>0x100000000||++total>1_000_000)throw TypeError('Invalid retained stack extent');end=range.clock+range.len;ranges.push({...range});}set.clients.set(row.client,ranges);}return set;}
function stackWire(stack,ownerID){return stack.map(item=>{if(item.meta.size!==1||!item.meta.has(historyKey))throw TypeError('Unavailable canonical stack metadata');const group=validateOwnedCommandGroup(item.meta.get(historyKey));if(group.owner_id!==ownerID)throw TypeError('Conflicting owned checkpoint');return{insertions:historyIntervals(item.insertions),deletions:historyIntervals(item.deletions),group:clone(group)};});}
function stackItems(value,ownerID,stackLimit=4096){if(!Array.isArray(value)||value.length>stackLimit)throw TypeError('Oversized retained stack');return value.map(item=>{fields(item,['insertions','deletions','group']);const group=validateOwnedCommandGroup(item.group);if(group.owner_id!==ownerID)throw TypeError('Conflicting owned checkpoint');return{insertions:historySet(item.insertions),deletions:historySet(item.deletions),meta:new Map([[historyKey,clone(group)]])};});}
function checkpointItem(transaction,id,count){historyRange({item:id,count});const item=Y.getItemCleanStart(transaction,Y.createID(id.client,id.clock));Y.getItemCleanEnd(transaction,transaction.doc.store,Y.createID(id.client,id.clock+count-1));if(!(item instanceof Y.Item)||item.content instanceof Y.ContentDeleted)throw TypeError('Unavailable retained checkpoint item');return item;}
function sameRestoredContent(source,target){if(source.content.constructor!==target.content.constructor)return false;if(source.content instanceof Y.ContentFormat)return source.content.key===target.content.key&&same(source.content.value??null,target.content.value??null);if(source.content instanceof Y.ContentType){const a=source.content.type,b=target.content.type;return a.constructor===b.constructor&&(!(a instanceof Y.XmlElement)||a.nodeName===b.nodeName);}return same(source.content.getContent(),target.content.getContent());}
function installOwnedHistoryCheckpoint(doc,manager,checkpoint,ownerID,stackLimit=4096){
 fields(checkpoint,['owner_id','state_vector','undo_stack','redo_stack','redone','retained']);if(checkpoint.owner_id!==ownerID||JSON.stringify(checkpoint).length>32*1024*1024)throw TypeError('Conflicting or oversized owned checkpoint');
 if(!Array.isArray(checkpoint.state_vector)||!Array.isArray(checkpoint.redone)||!Array.isArray(checkpoint.retained)||checkpoint.redone.length+checkpoint.retained.length>1_000_000)throw TypeError('Invalid bounded owned checkpoint');
 const clocks=new Map();for(const entry of checkpoint.state_vector){fields(entry,['client','clock']);if(!Number.isSafeInteger(entry.client)||entry.client<0||!Number.isInteger(entry.clock)||entry.clock<0||entry.clock>0x100000000||clocks.has(entry.client))throw TypeError('Invalid checkpoint frontier');clocks.set(entry.client,entry.clock);}
 const undo=stackItems(checkpoint.undo_stack,ownerID,stackLimit),redo=stackItems(checkpoint.redo_stack,ownerID,stackLimit),seen=new Set();
 Y.transact(doc,transaction=>{
  for(const row of checkpoint.retained){historyRange(row);if(row.item.clock+row.count>(clocks.get(row.item.client)||0))throw TypeError('Retained item outside checkpoint frontier');let offset=0;while(offset<row.count){const item=checkpointItem(transaction,{client:row.item.client,clock:row.item.clock+offset},row.count-offset);offset+=item.length;let parent=item,depth=0;while(parent instanceof Y.Item){if(++depth>128)throw TypeError('Retained checkpoint parent limit');parent.keep=true;parent=parent.parent?._item;}}}
  for(const row of checkpoint.redone){fields(row,['item','count','target']);historyRange({item:row.item,count:row.count});historyID(row.target);if(row.item.clock+row.count>(clocks.get(row.item.client)||0)||row.target.clock+row.count>(clocks.get(row.target.client)||0)||seen.has(row.item.client+':'+row.item.clock))throw TypeError('Invalid checkpoint redone edge');seen.add(row.item.client+':'+row.item.clock);let offset=0;while(offset<row.count){let source=checkpointItem(transaction,{client:row.item.client,clock:row.item.clock+offset},row.count-offset),target=checkpointItem(transaction,{client:row.target.client,clock:row.target.clock+offset},row.count-offset);const count=Math.min(source.length,target.length,row.count-offset);source=checkpointItem(transaction,{client:row.item.client,clock:row.item.clock+offset},count);target=checkpointItem(transaction,{client:row.target.client,clock:row.target.clock+offset},count);if(source===target||!sameRestoredContent(source,target))throw TypeError('Mismatched checkpoint redone content');source.redone=Y.createID(target.id.client,target.id.clock);offset+=count;}}
  for(const item of [...undo,...redo])Y.iterateDeletedStructs(transaction,item.deletions,struct=>{if(!(struct instanceof Y.Item)||!struct.keep||struct.content instanceof Y.ContentDeleted)throw TypeError('Unretained owned stack deletion');});
 },'relaymark:checkpoint-restore');
 for(const structs of doc.store.clients.values())for(const item of structs){if(!(item instanceof Y.Item)||!item.redone)continue;const chain=new Set();let current=item;while(current.redone){const key=current.id.client+':'+current.id.clock;if(chain.has(key)||chain.size>1_000_000)throw TypeError('Cyclic checkpoint redone edge');chain.add(key);current=Y.getItem(doc.store,current.redone);if(!(current instanceof Y.Item))throw TypeError('Unavailable checkpoint redone target');}}
 if(typeof manager.restoreHistoryStacks!=='function')throw TypeError('Maintained stack initialization hook unavailable');manager.restoreHistoryStacks(undo,redo);
}
/** Data-only capture of this same settled maintained manager. Metadata remains
 * strict: browser selection keys are qualified and separated by its adapter. */
export function captureMaintainedHistoryCheckpoint(doc,manager,ownerID,stacksOverride=null){
 if(manager.doc!==doc||doc.gc!==false)throw TypeError('Unavailable retained history owner');
  if(typeof manager.exportHistoryStacks!=='function')throw TypeError('Maintained stack export hook unavailable');const stacks=stacksOverride??manager.exportHistoryStacks(),redone=[],kept=[];let budget=1_000_000;
  for(const structs of doc.store.clients.values())for(const item of structs){if(--budget<0)throw TypeError('Checkpoint retained-item budget exhausted');if(!(item instanceof Y.Item))continue;const range={item:{client:item.id.client,clock:item.id.clock},count:item.length};if(item.redone)redone.push({...range,target:{client:item.redone.client,clock:item.redone.clock}});if(item.keep)kept.push(range);}
  const result={owner_id:ownerID,state_vector:captureContentEditFootprint(doc,Uint8Array.of(0,0)).state_vector,undo_stack:stackWire(stacks.undo,ownerID),redo_stack:stackWire(stacks.redo,ownerID),redone,retained:kept};
  if(JSON.stringify(result).length>32*1024*1024)throw TypeError('Oversized owned checkpoint');return result;
}
/** Used only after independent scope/state/metadata validation by a local
 * persistence adapter. Server receipt replay continues its private admission. */
export function installMaintainedHistoryCheckpoint(doc,manager,checkpoint,ownerID){return installOwnedHistoryCheckpoint(doc,manager,checkpoint,ownerID,16384);}
export {exportOwnedHistoryState,restoreOwnedHistoryState} from './owned-history-persistence.js';
/** Trusted verified receipt cut -> data-only actual manager checkpoint. The host
 * persists scope, cut, digest and coverage with its existing checkpoint row. */
export function createOwnedHistoryCheckpoint(input){
 fields(input,['initial_state_base64','checkpoint','receipts','current_state_base64','owner_id'],['receipts','current_state_base64','owner_id']);
 const retained=checkpointOwner(input);
 try{return captureMaintainedHistoryCheckpoint(retained.doc,retained.manager,input.owner_id);}
 finally{retained.destroy();}
}
/** Fresh scoped host request -> exact maintained inverse command. Original
 * actor/receipt authentication remains outside this ephemeral producer. */
export function produceOwnedHistory(input){
 const common=['receipts','current_state_base64','owner_id','transaction_id','writer_client','history'];
 fields(input,[...common,'initial_state_base64','checkpoint'],common);
 canonicalOperationID(input.transaction_id);canonicalOperationID(input.owner_id);validateOwnedHistory(input.history);
 if(input.history.owner_id!==input.owner_id||input.receipts.some(receipt=>receipt.transaction_id===input.transaction_id)||input.history.operation_ids.includes(input.transaction_id))throw TypeError('Conflicting inverse identity');
 if(input.writer_client!==null&&(!Number.isSafeInteger(input.writer_client)||input.writer_client<0))throw TypeError('Invalid actual inverse writer');
 const retained=checkpointOwner(input);
 try{
  const beforeBytes=Y.encodeStateAsUpdate(retained.doc),before_snapshot_base64=toBase64(Y.encodeSnapshot(Y.snapshot(retained.doc))),before=owner(beforeBytes),frontier=Y.decodeStateVector(Y.encodeStateVector(before));
  try{
   const effect=retained.inverseEffect(input.history,input.writer_client),transform=planDocumentDifference(effect.before,effect.after);
   if(!transform.steps.length)throw TypeError('Actual maintained inverse is textually unchanged');
   const footprint=captureContentEditFootprint(retained.doc,effect.update),writer=observedWriter(footprint,before);
   if(writer!==null&&writer!==input.writer_client)throw TypeError('Supplied inverse writer differs from actual fresh allocation');
   const accounting=ownedTextAccounting(retained.doc,frontier,retained.restored());
   const operation={kind:'content_edit',steps:transform.steps.map(step=>step.toJSON()),copies:accounting.proven_copies,history:clone(input.history)};
   const basis=Object.hasOwn(input,'checkpoint')?{checkpoint:input.checkpoint}:{initial_state_base64:input.initial_state_base64};
   const replay=replayContentEditMutation({...basis,receipts:input.receipts,sender_state_base64:input.current_state_base64,current_state_base64:input.current_state_base64,writer_client:writer,operation,footprint});
   if(!same(replay.text_items,accounting.text_items)||!same(replay.proven_copies,accounting.proven_copies))throw TypeError('Inverse source accounting differs from independent replay');
   return {update_base64:toBase64(effect.update),state_base64:toBase64(Y.encodeStateAsUpdate(retained.doc)),before_snapshot_base64,authored_document:applyContentEdit(effect.before.toJSON(),operation).authored_document,text_items:accounting.text_items,content_edit:{before_snapshot_base64,steps:operation.steps,copies:operation.copies,history:operation.history},proof:{...replay,requires_mutation_correspondence:false}};
  }finally{before.destroy();}
 }finally{retained.destroy();}
}
/** Independently scoped dependency retirement only. This reconstructs every
 * supplied original receipt before changing the actual manager, never filters
 * serialized stacks or changes source facts. The host authenticates the cut,
 * complete groups and dependency closure before persisting this checkpoint. */
export function retireOwnedHistoryCheckpoint(input){
 fields(input,['initial_state_base64','checkpoint','receipts','current_state_base64','owner_id','groups'],['receipts','current_state_base64','owner_id','groups']);
 const retained=checkpointOwner(input);
 try{
  const before=Y.encodeStateAsUpdate(retained.doc),result=retireOwnedHistoryGroups(retained.manager,input.groups),after=Y.encodeStateAsUpdate(retained.doc);
  if(before.length!==after.length||before.some((byte,index)=>byte!==after[index]))throw TypeError('Retirement changed retained document state');
  return {checkpoint:captureMaintainedHistoryCheckpoint(retained.doc,retained.manager,input.owner_id),retired_groups:result.groups,undo:result.undo,redo:result.redo};
 }finally{retained.destroy();}
}
function checkpointOwner(input,observer=null,attributeCodec=canonicalAttributeCodec){
 canonicalOperationID(input.owner_id);
 if(Object.hasOwn(input,'initial_state_base64')===Object.hasOwn(input,'checkpoint'))throw TypeError('Exactly one trusted checkpoint basis is required');
 if(!Array.isArray(input.receipts))throw TypeError('Unavailable bounded accepted history');
 const baseline=input.checkpoint?(input.receipts[0]?.sender_state_base64??input.current_state_base64):input.initial_state_base64;
 const retained=retainedHistoryOwner(baseline,input.receipts,input.owner_id,input.checkpoint??null,observer,attributeCodec);
 try{
  applyRetainedUpdate(retained.doc,bytes(input.current_state_base64));const actual=owner(bytes(input.current_state_base64));
  try{if(!same(captureContentEditFootprint(retained.doc,Y.encodeStateAsUpdate(retained.doc)),captureContentEditFootprint(actual,Y.encodeStateAsUpdate(actual))))throw TypeError('Checkpoint does not reconstruct exact retained cut');}
  finally{actual.destroy();}
  return retained;
 }catch(error){retained.destroy();throw error;}
}

function retainedHistoryOwner(initial_state_base64,receipts,ownerID,checkpoint=null,observer=null,attributeCodec=canonicalAttributeCodec){
 canonicalOperationID(ownerID);
 if(!Array.isArray(receipts)||receipts.length>4096||(!checkpoint&&receipts.length<1))throw TypeError('Unavailable bounded accepted history');
 const doc=owner(bytes(initial_state_base64)),origin={},manager=new Y.UndoManager([doc.getXmlFragment('default'),doc.getMap('relaymark')],{trackedOrigins:new Set([origin]),captureTimeout:Infinity});protectOwnedHistoryBranches(manager);bindOwnedHistoryOwner(manager,ownerID);let activeID=null,popped=null,lastRestored=[];
 const event=e=>{if(!manager.undoing&&!manager.redoing&&activeID)bindOwnedCommandGroup(manager,e,activeID)};
 manager.on('stack-item-added',event);manager.on('stack-item-updated',event);manager.on('stack-item-popped',e=>{popped=e.stackItem;bindOwnedCommandHistory(manager,e);});
 const inverseEffect=(history,writer)=>{
  validateOwnedHistory(history);
  const stack=history.kind==='undo'?manager.undoStack:manager.redoStack,group=stack.at(-1)?.meta.get('relaymark:operation_ids');
  if(history.owner_id!==ownerID||!group||!same(group,{owner_id:history.owner_id,reference:history.reference,operation_ids:history.operation_ids}))throw TypeError('Owned history differs from actual accepted group');
  const prior=Y.decodeStateVector(Y.encodeStateVector(doc)),links=redoneLinks(doc),before=initProseMirrorDoc(doc.getXmlFragment('default'),schema,attributeCodec).doc,updates=[],capture=u=>updates.push(u);
  const replayClient=doc.clientID;doc.clientID=writer??0;popped=null;doc.on('update',capture);
  try{if(history.kind==='undo')manager.undo();else manager.redo();}finally{doc.off('update',capture);doc.clientID=replayClient}
  if(!popped||updates.length!==1)throw TypeError('Actual maintained inverse has no effective group');
  if(!same(popped.meta.get('relaymark:operation_ids'),{owner_id:history.owner_id,reference:history.reference,operation_ids:history.operation_ids}))throw TypeError('Actual maintained inverse consumed another group');
  const after=initProseMirrorDoc(doc.getXmlFragment('default'),schema,attributeCodec).doc;
  lastRestored=restoredCopies(doc,prior,links);
  return {update:updates[0],before,after};
 };
 const inverse=(operation,writer)=>{
  const effect=inverseEffect(operation.history,writer),expected=applyContentEdit(effect.before.toJSON(),operation);
  if(!same(effect.after.toJSON(),expected.document))throw TypeError('Actual maintained inverse disagrees with supplied steps');
  return effect.update;
 };
 try{if(checkpoint)installOwnedHistoryCheckpoint(doc,manager,checkpoint,ownerID);
  let total=bytes(initial_state_base64).length;const seen=new Set();
  for(const receipt of receipts){fields(receipt,['transaction_id','operation','update_base64','sender_state_base64']);if(seen.has(receipt.transaction_id))throw TypeError('Duplicate accepted command receipt');seen.add(receipt.transaction_id);const sender=bytes(receipt.sender_state_base64),update=bytes(receipt.update_base64);const receiptOwner=receipt.operation.history?validateOwnedHistory(receipt.operation.history).owner_id:validateOwnedCommandGroup(receipt.operation.group).owner_id;if(receiptOwner!==ownerID)throw TypeError('Mixed maintained history owner receipts');total+=sender.length+update.length;if(total>32*1024*1024)throw TypeError('Oversized accepted history replay');applyRetainedUpdate(doc,sender);if(doc.store.pendingStructs||doc.store.pendingDs)throw TypeError('Unsettled accepted sender frontier');const beforeBytes=Y.encodeStateAsUpdate(doc),candidate=owner(beforeBytes);try{applyRetainedUpdate(candidate,update);const footprint=captureContentEditFootprint(candidate,update),writer=observedWriter(footprint,doc);
   if(receipt.operation.history){const actual=inverse(receipt.operation,writer),locked=owner(beforeBytes);try{compareUpdate(locked,footprint,actual)}finally{locked.destroy()}}
   else{const group=validateOwnedCommandGroup(receipt.operation.group);if(group.operation_ids.at(-1)!==receipt.transaction_id)throw TypeError('Accepted group does not end in command receipt');replayMutation({sender_state_base64:receipt.sender_state_base64,current_state_base64:toBase64(beforeBytes),writer_client:writer,operation:receipt.operation,footprint},attributeCodec);if(group.reference===receipt.transaction_id)manager.stopCapturing();activeID=receipt.transaction_id;try{applyRetainedUpdate(doc,update,origin)}finally{activeID=null}const actualGroup=readOwnedCommandGroup(manager,receipt.transaction_id);if(!same(actualGroup,group))throw TypeError('Accepted prefix differs from maintained group');}
   if(observer){const before=owner(beforeBytes);try{
    observer({receipt,doc,candidate,footprint:effectiveFootprint(before,footprint)});
   }finally{before.destroy()}}
  }finally{candidate.destroy()}}
  return {doc,manager,inverse,inverseEffect,restored:()=>lastRestored,destroy:()=>{manager.destroy();doc.destroy();}};
 }catch(error){manager.destroy();doc.destroy();throw error;}
}
function replayOwnedHistory(evidence,attributeCodec=canonicalAttributeCodec){
 const common=['sender_state_base64','current_state_base64','writer_client','operation','footprint','receipts'];
 fields(evidence,[...common,'initial_state_base64','checkpoint'],common);validateOwnedHistory(evidence.operation.history);
 if(Object.hasOwn(evidence,'initial_state_base64')===Object.hasOwn(evidence,'checkpoint'))throw TypeError('Exactly one trusted owned-history basis is required');
 const baseline=evidence.checkpoint?(evidence.receipts[0]?.sender_state_base64??evidence.sender_state_base64):evidence.initial_state_base64;
 const retained=retainedHistoryOwner(baseline,evidence.receipts,evidence.operation.history.owner_id,evidence.checkpoint??null,null,attributeCodec);
 const {doc,inverse}=retained;
 try{
  applyRetainedUpdate(doc,bytes(evidence.sender_state_base64));const candidateFrontier=Y.decodeStateVector(Y.encodeStateVector(doc)),sender=owner(bytes(evidence.sender_state_base64));try{if(!same([...candidateFrontier].sort((a,b)=>a[0]-b[0]),[...Y.decodeStateVector(Y.encodeStateVector(sender))].sort((a,b)=>a[0]-b[0]))||!same(captureContentEditSnapshot(doc.getXmlFragment('default')),captureContentEditSnapshot(sender.getXmlFragment('default')))||!same(intervals(captureContentEditFootprint(doc,Y.encodeStateAsUpdate(doc)).declared_deletes),intervals(captureContentEditFootprint(sender,Y.encodeStateAsUpdate(sender)).declared_deletes))||!same(doc.share.has('relaymark')?doc.getMap('relaymark').toJSON():{},sender.share.has('relaymark')?sender.getMap('relaymark').toJSON():{}))throw TypeError('Accepted history does not reconstruct exact sender frontier');}finally{sender.destroy()}
  const current=owner(bytes(evidence.current_state_base64));try{if(observedWriter(evidence.footprint,current)!==evidence.writer_client)throw TypeError('History writer is not independently observed');const frontier=Y.decodeStateVector(Y.encodeStateVector(current)),update=inverse(evidence.operation,evidence.writer_client),proof=compareUpdate(current,evidence.footprint,update),accounting=ownedTextAccounting(current,frontier,retained.restored());return{...proof,...accounting,expected_update_base64:toBase64(update),complete_mutation_correspondence:true,owned_history_correspondence:true,restored_copies:retained.restored()};}finally{current.destroy()}
 }finally{retained.destroy();}
}

/** Read-only dependency plan over freshly authenticated complete manager cuts.
 * Actor/owner roster and imported allocation authority stay with the host. */
export function planReviewedRecoveryRetirement(input){
 return planRecoveryRetirement(input,{checkpointOwner,bytes,owner,schema});
}

/** Finite original-input verification only. The existing closed conversion owner
 * authenticates original receipts and scope, conversion bytes and destination.
 * This is not a live profile, writable command or issued conversion seal. */
function validateFiniteMaterial(mappings,slotInsertions){
 let materialBytes=0;for(const character of stableStringify([mappings,slotInsertions])){const point=character.codePointAt(0);materialBytes+=point<=0x7f?1:point<=0x7ff?2:point<=0xffff?3:4;if(materialBytes>MAX_BYTES)throw TypeError('Finite helper material byte limit');}
}
// Closed alternatives: verify exact supplied bytes, or derive them with one
// fresh writer. Neither shape selects a codec or authenticates source authority.
function finiteConversionFields(input,allowed,required){
 const derive=Object.hasOwn(input??{},'writer_client'),proof=['conversion_update_base64','destination_state_base64'];
 fields(input,derive?[...allowed.filter(key=>!proof.includes(key)),'writer_client']:allowed,derive?[...required.filter(key=>!proof.includes(key)),'writer_client']:required);
 return derive;
}
export function prepareAggregateSettingsHistoryCut(input){
 if(Object.hasOwn(input??{},'manager_contexts'))return prepareReviewedFiniteCohort(input);
 const derive=finiteConversionFields(input,['initial_state_base64','checkpoint','receipts','current_state_base64','owner_id','conversion_update_base64','destination_state_base64','video_mappings','slot_insertions'],['receipts','current_state_base64','owner_id','conversion_update_base64','destination_state_base64']);
 const mappings=Object.hasOwn(input,'video_mappings')?input.video_mappings:[],slotInsertions=Object.hasOwn(input,'slot_insertions')?input.slot_insertions:null;
 if(Object.hasOwn(input,'slot_insertions')&&slotInsertions===null)throw TypeError('Invalid finite Slot insertions');
 validateFiniteMaterial(mappings,slotInsertions);
 const source=owner(bytes(input.current_state_base64));let codec;
 try{codec=finiteSettingsInputCodec(source,mappings,slotInsertions);}finally{source.destroy();}
 // The closed host authenticates a prior whole sidecar and exact roster. A
 // supplied checkpoint remains only a mutation basis, never issued authority.
 const neutral=input.owner_id===null;let retained;
 if(neutral){
  if(Object.hasOwn(input,'checkpoint')||!Object.hasOwn(input,'initial_state_base64')||!Array.isArray(input.receipts)||input.receipts.length)throw TypeError('Invalid neutral original cut');
  const doc=owner(bytes(input.initial_state_base64)),current=owner(bytes(input.current_state_base64));
  try{if(!same(captureContentEditFootprint(doc,Y.encodeStateAsUpdate(doc)),captureContentEditFootprint(current,Y.encodeStateAsUpdate(current))))throw TypeError('Neutral basis does not reconstruct original state');}catch(error){doc.destroy();throw error;}finally{current.destroy();}
  retained={doc,manager:null,destroy:()=>doc.destroy()};
 }else retained=checkpointOwner(input,null,codec);
 let proof;
 try{proof=finiteConversionProof(retained.doc,input,codec,mappings,slotInsertions,derive);return {...(derive?{conversion_update_base64:toBase64(proof.conversion)}:{}),schema_hash:physicalAttributeSchemaHash(),authored_document:proseMirrorToRelayMark(proof.converted.toJSON()),...finishFiniteManagerCut({...retained,owner_id:input.owner_id},mappings,slotInsertions,proof),complete_supplied_receipt_mutation_correspondence:true,complete_conversion_mutation_correspondence:true,requires_original_inventory_authorization:true};}
 finally{proof?.destroy();retained.destroy();}
}

function finiteConversionProof(sourceDoc,input,codec,mappings,slotInsertions,derive){
 if(!derive)return verifyFiniteConversion(sourceDoc,input,codec,mappings,slotInsertions);
 const candidate=owner(Y.encodeStateAsUpdate(sourceDoc));let proof;
 try{
  const transform=prepareAggregateSettingsTransform(candidate,mappings,slotInsertions),writer=input.writer_client;
  if(transform.count){if(!Number.isInteger(writer)||writer<0||writer>0xffffffff||sourceDoc.store.clients.has(writer))throw TypeError('Finite writer must be a fresh uint32 identity');candidate.clientID=writer;}
  else if(writer!==null)throw TypeError('Neutral finite derivation requires null writer');
  const vector=Y.encodeStateVector(candidate),updates=[],capture=update=>updates.push(update);candidate.on('update',capture);
  try{candidate.transact(transform.apply,'relaymark:finite-settings-conversion');}finally{candidate.off('update',capture);}
  if(updates.length!==(transform.count?1:0))throw TypeError('Finite derivation must emit exactly one actual update');
  const material={conversion_update_base64:toBase64(Y.encodeStateAsUpdate(candidate,vector)),destination_state_base64:toBase64(Y.encodeStateAsUpdate(candidate))};
  // Output buffers obey the same byte bounds as every retained proof input.
  bytes(material.conversion_update_base64);bytes(material.destination_state_base64);
  proof=verifyFiniteConversion(sourceDoc,material,codec,mappings,slotInsertions);
  if(proof.writer!==writer)throw TypeError('Derived finite writer differs from observed allocation');
  return proof;
 }catch(error){proof?.destroy();throw error;}finally{candidate.destroy();}
}

function verifyFiniteConversion(sourceDoc,input,codec,mappings,slotInsertions){
 let destination,replay;
 try{
  const originalBytes=Y.encodeStateAsUpdate(sourceDoc),original=initProseMirrorDoc(sourceDoc.getXmlFragment('default'),schema,codec).doc;
  const expected=expectedFiniteSlotDocument(expectedFiniteVideoDocument(original.toJSON(),mappings),slotInsertions);
  destination=owner(bytes(input.destination_state_base64));replay=owner(originalBytes);
  const conversion=bytes(input.conversion_update_base64),candidate=owner(originalBytes);
  let originalFootprint,writer;
  try{applyRetainedUpdate(candidate,conversion);if(candidate.store.pendingStructs||candidate.store.pendingDs)throw TypeError('Unsettled physical conversion');originalFootprint=captureContentEditFootprint(candidate,conversion);writer=observedWriter(originalFootprint,sourceDoc);
   if(!same(captureContentEditFootprint(candidate,Y.encodeStateAsUpdate(candidate)),captureContentEditFootprint(destination,Y.encodeStateAsUpdate(destination))))throw TypeError('Conversion does not reconstruct exact destination');
  }finally{candidate.destroy();}
  const transform=prepareAggregateSettingsTransform(replay,mappings,slotInsertions);
  if((writer===null)!==(transform.count===0))throw TypeError('Physical conversion allocation mismatch');
  if(!transform.count&&!same(captureContentEditFootprint(replay,Y.encodeStateAsUpdate(replay)),captureContentEditFootprint(destination,Y.encodeStateAsUpdate(destination))))throw TypeError('Neutral conversion changes retained state');
  const updates=[],capture=update=>updates.push(update);if(writer!==null)replay.clientID=writer;replay.on('update',capture);
  try{replay.transact(transform.apply,'relaymark:finite-settings-conversion');}finally{replay.off('update',capture);}
  if(updates.length!==(transform.count?1:0))throw TypeError('Physical conversion must match exact finite register edits');
  const locked=owner(originalBytes);
  try{compareUpdate(locked,originalFootprint,transform.count?updates[0]:conversion);if(!same(captureContentEditFootprint(locked,Y.encodeStateAsUpdate(locked)),captureContentEditFootprint(destination,Y.encodeStateAsUpdate(destination))))throw TypeError('Physical conversion state disagrees');}finally{locked.destroy();}
  const converted=initProseMirrorDoc(destination.getXmlFragment('default'),schema,canonicalAttributeCodec).doc;
  if(!same(expected,converted.toJSON()))throw TypeError('Physical conversion changes authored content or metadata');
  return {destination,converted,conversion,writer,correspondence:transform.correspondence,footprint:effectiveFootprint(sourceDoc,originalFootprint),destroy(){destination.destroy();}};
 }catch(error){destination?.destroy();throw error;}finally{replay?.destroy();}
}

function finishFiniteManagerCut(retained,mappings,slotInsertions,proof){
 const neutral=retained.manager===null,{converted,conversion}=proof;
  const groups=neutral?[]:aggregateSettingsHistoryGroups(retained.doc,retained.manager,mappings,slotInsertions);
  applyRetainedUpdate(retained.doc,conversion,'relaymark:finite-settings-conversion');
  const before=Y.encodeStateAsUpdate(retained.doc),retirement=neutral?{groups:[]}:retireOwnedHistoryGroups(retained.manager,groups),after=Y.encodeStateAsUpdate(retained.doc);
  if(before.length!==after.length||before.some((byte,index)=>byte!==after[index]))throw TypeError('Finite retirement changes document state');
  const checkpoint=neutral?null:captureMaintainedHistoryCheckpoint(retained.doc,retained.manager,retained.owner_id);
  const cold=owner(after);let manager;
  try{
   if(!neutral){manager=new Y.UndoManager([cold.getXmlFragment('default'),cold.getMap('relaymark')]);bindOwnedHistoryOwner(manager,retained.owner_id);installOwnedHistoryCheckpoint(cold,manager,checkpoint,retained.owner_id);if(!same(readOwnedHistoryGroups(manager),readOwnedHistoryGroups(retained.manager)))throw TypeError('Finite cut loses cold owner membership');}
   if(!same(initProseMirrorDoc(cold.getXmlFragment('default'),schema,canonicalAttributeCodec).doc.toJSON(),converted.toJSON()))throw TypeError('Finite cut loses cold authored state');
  }finally{manager?.destroy();cold.destroy();}
  return {state_base64:toBase64(after),checkpoint,retired_groups:retirement.groups};
}


/** Finite original cohort. Its complete manager/association evidence
 * is supplied by the closed host; no list or summary authenticates itself. */
function prepareReviewedFiniteCohort(input){
 const required=['binding','current_state_base64','current_cut','expected_manager_scopes','manager_contexts','association_inventory','imports','conversion_update_base64','destination_state_base64','video_mappings'];
 const derive=finiteConversionFields(input,[...required,'dependency_checkpoint','checkpoint_state_base64','slot_insertions'],required);
 validateFiniteMaterial(input.video_mappings,input.slot_insertions??null);
 if(!Array.isArray(input.video_mappings))throw TypeError('Invalid finite cohort Video plan');
 if(Object.hasOwn(input,'slot_insertions')&&!Array.isArray(input.slot_insertions))throw TypeError('Invalid finite cohort Slot plan');
 const original=owner(bytes(input.current_state_base64));let codec;
 try{codec=finiteSettingsInputCodec(original,input.video_mappings,input.slot_insertions??null);}finally{original.destroy();}
 const {association_inventory,conversion_update_base64,destination_state_base64,writer_client,video_mappings,slot_insertions,...dependencyInput}=input;
 if(!Array.isArray(association_inventory))throw TypeError('Incomplete original reviewed association inventory');
 const decode=portable=>importAggregateSettingsSnapshot(portable).document;
 const finiteOwner={checkpointOwner:(basis,observer)=>checkpointOwner(basis,observer,codec),bytes,owner,schema,...(codec===finiteAggregateAttributeCodec?{identityLayout:snapshot=>contentEditIdentityLayout(snapshot,decode),buildWitness:evidence=>buildWitness(evidence,applyContentEdit,decode)}:{})};
 const cohort=restoreRecoveryDependencyCohort(dependencyInput,finiteOwner,association_inventory);let proof;
 try{
  proof=finiteConversionProof(cohort.current,input,codec,video_mappings,slot_insertions??null,derive);
  observeDependencyPredecessors(cohort,proof.footprint,finiteSettingsDependencyRelations(cohort.current,proof.destination,proof.footprint,proof.correspondence));
  const manager_results=cohort.retained.map(retained=>({actor_id:retained.actor_id,owner_id:retained.owner_id,...finishFiniteManagerCut(retained,video_mappings,slot_insertions??null,proof)}));
  const state_base64=manager_results[0].state_base64;if(manager_results.some(result=>result.state_base64!==state_base64))throw TypeError('Finite cohort destination state mismatch');
  const stateSHA=Array.from(digest(bytes(state_base64)),value=>value.toString(16).padStart(2,'0')).join('');
  const dependency=finalizeRecoveryDependencyCohort(cohort,proof.destination,{through_update_id:input.current_cut.through_update_id,state_sha256:stateSHA});
  return {...(derive?{conversion_update_base64:toBase64(proof.conversion)}:{}),schema_hash:physicalAttributeSchemaHash(),state_base64,authored_document:proseMirrorToRelayMark(proof.converted.toJSON()),manager_results:manager_results.map(({state_base64,...result})=>result),dependency_checkpoint:dependency.dependency_checkpoint,complete_supplied_receipt_mutation_correspondence:true,complete_conversion_mutation_correspondence:true,complete_dependency_correspondence:true,requires_original_inventory_authorization:true};
 }finally{proof?.destroy();cohort.destroy();}
}
