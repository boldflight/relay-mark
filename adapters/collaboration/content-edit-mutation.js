/** Complete command mutation replay through the maintained editor/CRDT owners.
 * Inputs are trusted retained states and an independently observed footprint.
 * This proves correspondence, never actor/source authority or owned history. */
import * as Y from 'yjs';
import {Step} from 'prosemirror-transform';
import {initProseMirrorDoc,updateYFragment} from '@tiptap/y-tiptap';
import atob from 'core-js-pure/actual/atob.js';
import btoa from 'core-js-pure/actual/btoa.js';
const toBase64=bytes=>btoa(Array.from(bytes,v=>String.fromCharCode(v)).join(''));
const fromBase64=value=>Uint8Array.from(atob(value),v=>v.charCodeAt(0));
import {createCanonicalEditorSchema} from '../../src/editor-model.js';
import {applyContentEdit} from '../../src/content-edit.js';
import {stableStringify,cloneCanonicalJSON as clone} from '../../src/canonical-json.js';
import {captureContentEditFootprint,captureContentEditSnapshot} from './content-edit-observer.js';
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
 fields(evidence,['sender_state_base64','current_state_base64','writer_client','operation','footprint']);const senderBytes=bytes(evidence.sender_state_base64),currentBytes=bytes(evidence.current_state_base64),sender=owner(senderBytes),current=owner(currentBytes);try{
  const before=Y.decodeStateVector(Y.encodeStateVector(current)),clients=new Set();for(const r of evidence.footprint.structs??[])if(r.item.clock+r.count>(before.get(r.item.client)||0))clients.add(r.item.client);
  if(clients.size>1||(clients.size===0?evidence.writer_client!==null:!clients.has(evidence.writer_client)||!Number.isSafeInteger(evidence.writer_client)||evidence.writer_client<0))throw TypeError('Replay writer must be independently observed from fresh structs');
  if(evidence.operation.history)throw TypeError('Owned inverse requires maintained accepted-history replay');
  const initialized=initProseMirrorDoc(sender.getXmlFragment('default'),schema),expected=applyContentEdit(initialized.doc.toJSON(),evidence.operation);let result=initialized.doc;
  for(const json of evidence.operation.steps){const applied=Step.fromJSON(schema,json).apply(result);if(applied.failed)throw TypeError('Refused maintained command');result=applied.doc;}
  if(!same(result.toJSON(),expected.document))throw TypeError('Maintained command execution disagrees');
  sender.clientID=evidence.writer_client??0;const updates=[];sender.on('update',update=>updates.push(update));updateYFragment(sender,sender.getXmlFragment('default'),result,initialized.meta);
  if(updates.length!==1)throw TypeError('Command must produce one maintained mutation transaction');const update=updates[0];
  const known=new Map();for(const record of captureContentEditFootprint(current,currentBytes).structs){const list=known.get(record.item.client)||[];list.push(record);known.set(record.item.client,list);}const ds=Y.createDeleteSetFromStructStore(current.store),deleted=[];for(const [client,ranges]of ds.clients)for(const r of ranges)deleted.push({item:{client,clock:r.clock},count:r.len});
  Y.applyUpdate(current,update);const footprint=captureContentEditFootprint(current,update),actual=normalized(evidence.footprint,before,known,deleted),replayed=normalized(footprint,before,known,deleted);
  if(!same(actual,replayed))throw TypeError('Original mutation differs from executed maintained command');
  return {footprint,expected_update_base64:toBase64(update),complete_mutation_correspondence:true};
 }finally{sender.destroy();current.destroy();}
}
