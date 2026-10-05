/** Complete command mutation replay through the maintained editor/CRDT owners.
 * Inputs are trusted retained states and an independently observed footprint.
 * This proves correspondence against trusted receipts, never actor/source authority. */
import * as Y from 'yjs';
import {Step} from 'prosemirror-transform';
import {initProseMirrorDoc,updateYFragment} from '@tiptap/y-tiptap';
import atob from 'core-js-pure/actual/atob.js';
import btoa from 'core-js-pure/actual/btoa.js';
const toBase64=bytes=>btoa(Array.from(bytes,v=>String.fromCharCode(v)).join(''));
const fromBase64=value=>Uint8Array.from(atob(value),v=>v.charCodeAt(0));
import {createCanonicalEditorSchema} from '../../src/editor-model.js';
import {applyContentEdit,createContentEditWrite,buildContentEditWitness} from '../../src/content-edit.js';
import {stableStringify,cloneCanonicalJSON as clone} from '../../src/canonical-json.js';
import {bindOwnedHistoryOwner,readOwnedCommandGroup,bindOwnedCommandGroup,bindOwnedCommandHistory,validateOwnedCommandGroup,validateOwnedHistory} from './owned-command-group.js';
import {captureContentEditFootprint,captureContentEditSnapshot} from './content-edit-observer.js';
import {canonicalOperationID} from '../../src/owned-command-group.js';
import {protectOwnedHistoryBranches} from './owned-history-branches.js';
const schema=createCanonicalEditorSchema(),MAX_BYTES=8*1024*1024;
const same=(a,b)=>stableStringify(a)===stableStringify(b);
function fields(value,allowed,required=allowed){if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!allowed.includes(k))||required.some(k=>!Object.hasOwn(value,k)))throw TypeError('Invalid mutation replay evidence');}
function bytes(value){if(typeof value!=='string'||value.length>4*Math.ceil(MAX_BYTES/3))throw TypeError('Invalid retained replay bytes');const result=fromBase64(value,{lastChunkHandling:'strict'});if(result.length>MAX_BYTES||toBase64(result)!==value)throw TypeError('Noncanonical retained replay bytes');return result;}
function owner(state){const doc=new Y.Doc({gc:false,guid:'relaymark:ephemeral-command-proof'});Y.applyUpdate(doc,state);if(doc.store.pendingStructs||doc.store.pendingDs)throw TypeError('Unsettled retained replay state');for(const name of doc.share.keys())if(!['default','relaymark'].includes(name))throw TypeError('Unknown retained replay root');if(!doc.share.has('default'))throw TypeError('Missing retained editor root');const root=doc.getXmlFragment('default');if(root._map.size)throw TypeError('Hidden editor root attributes');if(doc.share.has('relaymark'))doc.getMap('relaymark');captureContentEditSnapshot(doc.getXmlFragment('default'));return doc;}
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
export function replayContentEditMutation(evidence){
 if(evidence.operation?.history)return replayOwnedHistory(evidence);
 fields(evidence,['sender_state_base64','current_state_base64','writer_client','operation','footprint']);const senderBytes=bytes(evidence.sender_state_base64),currentBytes=bytes(evidence.current_state_base64),sender=owner(senderBytes),current=owner(currentBytes);try{
  const before=Y.decodeStateVector(Y.encodeStateVector(current)),clients=new Set();for(const r of evidence.footprint.structs??[])if(r.item.clock+r.count>(before.get(r.item.client)||0))clients.add(r.item.client);
  if(clients.size>1||(clients.size===0?evidence.writer_client!==null:!clients.has(evidence.writer_client)||!Number.isSafeInteger(evidence.writer_client)||evidence.writer_client<0))throw TypeError('Replay writer must be independently observed from fresh structs');
  const initialized=initProseMirrorDoc(sender.getXmlFragment('default'),schema),expected=applyContentEdit(initialized.doc.toJSON(),evidence.operation);let result=initialized.doc;
  for(const json of evidence.operation.steps){const applied=Step.fromJSON(schema,json).apply(result);if(applied.failed)throw TypeError('Refused maintained command');result=applied.doc;}
  if(!same(result.toJSON(),expected.document))throw TypeError('Maintained command execution disagrees');
  sender.clientID=evidence.writer_client??0;const updates=[];sender.on('update',update=>updates.push(update));initialized.meta.contentEditWrite=createContentEditWrite(initialized.doc,evidence.operation.steps,result);updateYFragment(sender,sender.getXmlFragment('default'),result,initialized.meta);
  if(updates.length!==1)throw TypeError('Command must produce one maintained mutation transaction');const update=updates[0];
  const known=new Map();for(const record of captureContentEditFootprint(current,currentBytes).structs){const list=known.get(record.item.client)||[];list.push(record);known.set(record.item.client,list);}const ds=Y.createDeleteSetFromStructStore(current.store),deleted=[];for(const [client,ranges]of ds.clients)for(const r of ranges)deleted.push({item:{client,clock:r.clock},count:r.len});
  Y.applyUpdate(current,update);const footprint=captureContentEditFootprint(current,update),actual=normalized(evidence.footprint,before,known,deleted),replayed=normalized(footprint,before,known,deleted);
  if(!same(actual,replayed))throw TypeError('Original mutation differs from executed maintained command');
  return {footprint,expected_update_base64:toBase64(update),complete_mutation_correspondence:true,retained_field_changes:fieldChanges(replayed)};
 }finally{sender.destroy();current.destroy();}
}

/** Read the admitted retained owner through the same canonical PM binding.
 * Returned JSON is a projection, never a new writable replica or authority. */
export function readContentEditDocument(state_base64){
 const doc=owner(bytes(state_base64));
 try{return clone(initProseMirrorDoc(doc.getXmlFragment('default'),schema).doc.toJSON());}
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
  const initialized=initProseMirrorDoc(root,schema),operation={kind:'content_edit',steps:input.steps};
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
function compareUpdate(current,originalFootprint,update){const state=Y.encodeStateAsUpdate(current),before=Y.decodeStateVector(Y.encodeStateVector(current)),known=new Map();for(const record of captureContentEditFootprint(current,state).structs){const list=known.get(record.item.client)||[];list.push(record);known.set(record.item.client,list);}const deleted=[];for(const[client,ranges]of Y.createDeleteSetFromStructStore(current.store).clients)for(const r of ranges)deleted.push({item:{client,clock:r.clock},count:r.len});Y.applyUpdate(current,update);const footprint=captureContentEditFootprint(current,update);if(!same(normalized(originalFootprint,before,known,deleted),normalized(footprint,before,known,deleted)))throw TypeError('Original mutation differs from maintained owned history');return{footprint,retained_field_changes:fieldChanges(normalized(footprint,before,known,deleted))};}
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
function stackItems(value,ownerID){if(!Array.isArray(value)||value.length>4096)throw TypeError('Oversized retained stack');return value.map(item=>{fields(item,['insertions','deletions','group']);const group=validateOwnedCommandGroup(item.group);if(group.owner_id!==ownerID)throw TypeError('Conflicting owned checkpoint');return{insertions:historySet(item.insertions),deletions:historySet(item.deletions),meta:new Map([[historyKey,clone(group)]])};});}
function checkpointItem(transaction,id,count){historyRange({item:id,count});const item=Y.getItemCleanStart(transaction,Y.createID(id.client,id.clock));Y.getItemCleanEnd(transaction,transaction.doc.store,Y.createID(id.client,id.clock+count-1));if(!(item instanceof Y.Item)||item.content instanceof Y.ContentDeleted)throw TypeError('Unavailable retained checkpoint item');return item;}
function sameRestoredContent(source,target){if(source.content.constructor!==target.content.constructor)return false;if(source.content instanceof Y.ContentFormat)return source.content.key===target.content.key&&same(source.content.value??null,target.content.value??null);if(source.content instanceof Y.ContentType){const a=source.content.type,b=target.content.type;return a.constructor===b.constructor&&(!(a instanceof Y.XmlElement)||a.nodeName===b.nodeName);}return same(source.content.getContent(),target.content.getContent());}
function installOwnedHistoryCheckpoint(doc,manager,checkpoint,ownerID){
 fields(checkpoint,['owner_id','state_vector','undo_stack','redo_stack','redone','retained']);if(checkpoint.owner_id!==ownerID||JSON.stringify(checkpoint).length>32*1024*1024)throw TypeError('Conflicting or oversized owned checkpoint');
 if(!Array.isArray(checkpoint.state_vector)||!Array.isArray(checkpoint.redone)||!Array.isArray(checkpoint.retained)||checkpoint.redone.length+checkpoint.retained.length>1_000_000)throw TypeError('Invalid bounded owned checkpoint');
 const clocks=new Map();for(const entry of checkpoint.state_vector){fields(entry,['client','clock']);if(!Number.isSafeInteger(entry.client)||entry.client<0||!Number.isInteger(entry.clock)||entry.clock<0||entry.clock>0x100000000||clocks.has(entry.client))throw TypeError('Invalid checkpoint frontier');clocks.set(entry.client,entry.clock);}
 const undo=stackItems(checkpoint.undo_stack,ownerID),redo=stackItems(checkpoint.redo_stack,ownerID),seen=new Set();
 Y.transact(doc,transaction=>{
  for(const row of checkpoint.retained){historyRange(row);if(row.item.clock+row.count>(clocks.get(row.item.client)||0))throw TypeError('Retained item outside checkpoint frontier');let offset=0;while(offset<row.count){const item=checkpointItem(transaction,{client:row.item.client,clock:row.item.clock+offset},row.count-offset);offset+=item.length;let parent=item,depth=0;while(parent instanceof Y.Item){if(++depth>128)throw TypeError('Retained checkpoint parent limit');parent.keep=true;parent=parent.parent?._item;}}}
  for(const row of checkpoint.redone){fields(row,['item','count','target']);historyRange({item:row.item,count:row.count});historyID(row.target);if(row.item.clock+row.count>(clocks.get(row.item.client)||0)||row.target.clock+row.count>(clocks.get(row.target.client)||0)||seen.has(row.item.client+':'+row.item.clock))throw TypeError('Invalid checkpoint redone edge');seen.add(row.item.client+':'+row.item.clock);let offset=0;while(offset<row.count){let source=checkpointItem(transaction,{client:row.item.client,clock:row.item.clock+offset},row.count-offset),target=checkpointItem(transaction,{client:row.target.client,clock:row.target.clock+offset},row.count-offset);const count=Math.min(source.length,target.length,row.count-offset);source=checkpointItem(transaction,{client:row.item.client,clock:row.item.clock+offset},count);target=checkpointItem(transaction,{client:row.target.client,clock:row.target.clock+offset},count);if(source===target||!sameRestoredContent(source,target))throw TypeError('Mismatched checkpoint redone content');source.redone=Y.createID(target.id.client,target.id.clock);offset+=count;}}
  for(const item of [...undo,...redo])Y.iterateDeletedStructs(transaction,item.deletions,struct=>{if(!(struct instanceof Y.Item)||!struct.keep||struct.content instanceof Y.ContentDeleted)throw TypeError('Unretained owned stack deletion');});
 },'relaymark:checkpoint-restore');
 for(const structs of doc.store.clients.values())for(const item of structs){if(!(item instanceof Y.Item)||!item.redone)continue;const chain=new Set();let current=item;while(current.redone){const key=current.id.client+':'+current.id.clock;if(chain.has(key)||chain.size>1_000_000)throw TypeError('Cyclic checkpoint redone edge');chain.add(key);current=Y.getItem(doc.store,current.redone);if(!(current instanceof Y.Item))throw TypeError('Unavailable checkpoint redone target');}}
 if(typeof manager.restoreHistoryStacks!=='function')throw TypeError('Maintained stack initialization hook unavailable');manager.restoreHistoryStacks(undo,redo);
}
/** Trusted verified receipt cut -> data-only actual manager checkpoint. The host
 * persists scope, cut, digest and coverage with its existing checkpoint row. */
export function createOwnedHistoryCheckpoint(input){
 fields(input,['initial_state_base64','checkpoint','receipts','current_state_base64','owner_id'],['receipts','current_state_base64','owner_id']);canonicalOperationID(input.owner_id);
 if(Object.hasOwn(input,'initial_state_base64')===Object.hasOwn(input,'checkpoint'))throw TypeError('Exactly one trusted checkpoint basis is required');
 if(!Array.isArray(input.receipts))throw TypeError('Unavailable bounded accepted history');
 const baseline=input.checkpoint?(input.receipts[0]?.sender_state_base64??input.current_state_base64):input.initial_state_base64;
 const retained=retainedHistoryOwner(baseline,input.receipts,input.owner_id,input.checkpoint??null);
 try{Y.applyUpdate(retained.doc,bytes(input.current_state_base64));const actual=owner(bytes(input.current_state_base64));try{if(!same(captureContentEditFootprint(retained.doc,Y.encodeStateAsUpdate(retained.doc)),captureContentEditFootprint(actual,Y.encodeStateAsUpdate(actual))))throw TypeError('Checkpoint does not reconstruct exact retained cut');}finally{actual.destroy();}
  if(typeof retained.manager.exportHistoryStacks!=='function')throw TypeError('Maintained stack export hook unavailable');const stacks=retained.manager.exportHistoryStacks(),redone=[],kept=[];let budget=1_000_000;
  for(const structs of retained.doc.store.clients.values())for(const item of structs){if(--budget<0)throw TypeError('Checkpoint retained-item budget exhausted');if(!(item instanceof Y.Item))continue;const range={item:{client:item.id.client,clock:item.id.clock},count:item.length};if(item.redone)redone.push({...range,target:{client:item.redone.client,clock:item.redone.clock}});if(item.keep)kept.push(range);}
  const result={owner_id:input.owner_id,state_vector:captureContentEditFootprint(retained.doc,Uint8Array.of(0,0)).state_vector,undo_stack:stackWire(stacks.undo,input.owner_id),redo_stack:stackWire(stacks.redo,input.owner_id),redone,retained:kept};
  if(JSON.stringify(result).length>32*1024*1024)throw TypeError('Oversized owned checkpoint');return result;
 }finally{retained.destroy();}
}
function retainedHistoryOwner(initial_state_base64,receipts,ownerID,checkpoint=null){
 canonicalOperationID(ownerID);
 if(!Array.isArray(receipts)||receipts.length>4096||(!checkpoint&&receipts.length<1))throw TypeError('Unavailable bounded accepted history');
 const doc=owner(bytes(initial_state_base64)),origin={},manager=new Y.UndoManager([doc.getXmlFragment('default'),doc.getMap('relaymark')],{trackedOrigins:new Set([origin]),captureTimeout:Infinity});protectOwnedHistoryBranches(manager);bindOwnedHistoryOwner(manager,ownerID);let activeID=null,popped=null,lastRestored=[];
 const event=e=>{if(!manager.undoing&&!manager.redoing&&activeID)bindOwnedCommandGroup(manager,e,activeID)};
 manager.on('stack-item-added',event);manager.on('stack-item-updated',event);manager.on('stack-item-popped',e=>{popped=e.stackItem;bindOwnedCommandHistory(manager,e);});
 const inverse=(operation,writer)=>{validateOwnedHistory(operation.history);const stack=operation.history.kind==='undo'?manager.undoStack:manager.redoStack,group=stack.at(-1)?.meta.get('relaymark:operation_ids');if(operation.history.owner_id!==ownerID||!group||!same(group,{owner_id:operation.history.owner_id,reference:operation.history.reference,operation_ids:operation.history.operation_ids}))throw TypeError('Owned history differs from actual accepted group');
  const prior=Y.decodeStateVector(Y.encodeStateVector(doc)),links=redoneLinks(doc),initialized=initProseMirrorDoc(doc.getXmlFragment('default'),schema),expected=applyContentEdit(initialized.doc.toJSON(),operation),updates=[],capture=u=>updates.push(u);doc.clientID=writer??0;popped=null;doc.on('update',capture);try{if(operation.history.kind==='undo')manager.undo();else manager.redo();}finally{doc.off('update',capture)}
  if(!popped||updates.length!==1||!same(initProseMirrorDoc(doc.getXmlFragment('default'),schema).doc.toJSON(),expected.document))throw TypeError('Actual maintained inverse disagrees with supplied steps');lastRestored=restoredCopies(doc,prior,links);return updates[0];};
 try{if(checkpoint)installOwnedHistoryCheckpoint(doc,manager,checkpoint,ownerID);
  let total=bytes(initial_state_base64).length;const seen=new Set();
  for(const receipt of receipts){fields(receipt,['transaction_id','operation','update_base64','sender_state_base64']);if(seen.has(receipt.transaction_id))throw TypeError('Duplicate accepted command receipt');seen.add(receipt.transaction_id);const sender=bytes(receipt.sender_state_base64),update=bytes(receipt.update_base64);const receiptOwner=receipt.operation.history?validateOwnedHistory(receipt.operation.history).owner_id:validateOwnedCommandGroup(receipt.operation.group).owner_id;if(receiptOwner!==ownerID)throw TypeError('Mixed maintained history owner receipts');total+=sender.length+update.length;if(total>32*1024*1024)throw TypeError('Oversized accepted history replay');Y.applyUpdate(doc,sender);if(doc.store.pendingStructs||doc.store.pendingDs)throw TypeError('Unsettled accepted sender frontier');const beforeBytes=Y.encodeStateAsUpdate(doc),candidate=owner(beforeBytes);try{Y.applyUpdate(candidate,update);const footprint=captureContentEditFootprint(candidate,update),writer=observedWriter(footprint,doc);
   if(receipt.operation.history){const actual=inverse(receipt.operation,writer),locked=owner(beforeBytes);try{compareUpdate(locked,footprint,actual)}finally{locked.destroy()}}
   else{const group=validateOwnedCommandGroup(receipt.operation.group);if(group.operation_ids.at(-1)!==receipt.transaction_id)throw TypeError('Accepted group does not end in command receipt');replayContentEditMutation({sender_state_base64:receipt.sender_state_base64,current_state_base64:toBase64(beforeBytes),writer_client:writer,operation:receipt.operation,footprint});if(group.reference===receipt.transaction_id)manager.stopCapturing();activeID=receipt.transaction_id;try{Y.applyUpdate(doc,update,origin)}finally{activeID=null}const actualGroup=readOwnedCommandGroup(manager,receipt.transaction_id);if(!same(actualGroup,group))throw TypeError('Accepted prefix differs from maintained group');}
  }finally{candidate.destroy()}}
  return {doc,manager,inverse,restored:()=>lastRestored,destroy:()=>{manager.destroy();doc.destroy();}};
 }catch(error){manager.destroy();doc.destroy();throw error;}
}
function replayOwnedHistory(evidence){
 const common=['sender_state_base64','current_state_base64','writer_client','operation','footprint','receipts'];
 fields(evidence,[...common,'initial_state_base64','checkpoint'],common);validateOwnedHistory(evidence.operation.history);
 if(Object.hasOwn(evidence,'initial_state_base64')===Object.hasOwn(evidence,'checkpoint'))throw TypeError('Exactly one trusted owned-history basis is required');
 const baseline=evidence.checkpoint?(evidence.receipts[0]?.sender_state_base64??evidence.sender_state_base64):evidence.initial_state_base64;
 const retained=retainedHistoryOwner(baseline,evidence.receipts,evidence.operation.history.owner_id,evidence.checkpoint??null);
 const {doc,inverse}=retained;
 try{
  Y.applyUpdate(doc,bytes(evidence.sender_state_base64));const candidateFrontier=Y.decodeStateVector(Y.encodeStateVector(doc)),sender=owner(bytes(evidence.sender_state_base64));try{if(!same([...candidateFrontier].sort((a,b)=>a[0]-b[0]),[...Y.decodeStateVector(Y.encodeStateVector(sender))].sort((a,b)=>a[0]-b[0]))||!same(captureContentEditSnapshot(doc.getXmlFragment('default')),captureContentEditSnapshot(sender.getXmlFragment('default')))||!same(intervals(captureContentEditFootprint(doc,Y.encodeStateAsUpdate(doc)).declared_deletes),intervals(captureContentEditFootprint(sender,Y.encodeStateAsUpdate(sender)).declared_deletes))||!same(doc.share.has('relaymark')?doc.getMap('relaymark').toJSON():{},sender.share.has('relaymark')?sender.getMap('relaymark').toJSON():{}))throw TypeError('Accepted history does not reconstruct exact sender frontier');}finally{sender.destroy()}
  const current=owner(bytes(evidence.current_state_base64));try{if(observedWriter(evidence.footprint,current)!==evidence.writer_client)throw TypeError('History writer is not independently observed');const frontier=Y.decodeStateVector(Y.encodeStateVector(current)),update=inverse(evidence.operation,evidence.writer_client),proof=compareUpdate(current,evidence.footprint,update),accounting=ownedTextAccounting(current,frontier,retained.restored());return{...proof,...accounting,expected_update_base64:toBase64(update),complete_mutation_correspondence:true,owned_history_correspondence:true,restored_copies:retained.restored()};}finally{current.destroy()}
 }finally{retained.destroy();}
}
