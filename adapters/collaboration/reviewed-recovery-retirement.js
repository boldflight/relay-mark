/** Dependency observation over the same maintained receipt/manager owner.
 * The host authenticates the complete actor+owner roster and imported intervals.
 * No source facts or persistent stack are rewritten by this read-only plan. */
import * as Y from 'yjs';
import {digest} from 'lib0/hash/sha256';
import {applyContentEdit,buildContentEditWitness} from '../../src/content-edit.js';
import {contentEditIdentityLayout} from '../../src/content-edit-witness.js';
import {captureContentEditSnapshot,captureContentEditFootprint} from './content-edit-observer.js';
import {stableStringify,cloneCanonicalJSON as clone} from '../../src/canonical-json.js';
import {canonicalOperationID} from '../../src/owned-command-group.js';
const MAX=1_000_000,key=id=>id.client+':'+id.clock,same=(a,b)=>stableStringify(a)===stableStringify(b);
const id=value=>({client:value.client,clock:value.clock});
function fields(value,allowed,required=allowed){if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!allowed.includes(k))||required.some(k=>!Object.hasOwn(value,k)))throw TypeError('Invalid recovery dependency evidence');}
function range(value){fields(value,['item','count']);fields(value.item,['client','clock']);if(!Number.isSafeInteger(value.item.client)||value.item.client<0||!Number.isSafeInteger(value.item.clock)||value.item.clock<0||!Number.isSafeInteger(value.count)||value.count<1||value.item.clock+value.count>2**32)throw TypeError('Invalid imported dependency interval');return value;}
function itemAt(doc,identity){const item=Y.getItem(doc.store,Y.createID(identity.client,identity.clock));if(!(item instanceof Y.Item)||item.content instanceof Y.ContentDeleted)throw TypeError('Unavailable retained dependency item');return item;}
function storedRanges(doc,selected){const result=[];for(const selectedRange of selected){range(selectedRange);let clock=selectedRange.item.clock,end=clock+selectedRange.count;while(clock<end){const item=itemAt(doc,{client:selectedRange.item.client,clock}),next=Math.min(end,item.id.clock+item.length);if(next<=clock)throw TypeError('Unavailable dependency extent');result.push({item:{client:selectedRange.item.client,clock},count:next-clock,stored:item});if(result.length>MAX)throw TypeError('Dependency item resource limit');clock=next;}}return result;}
function edge(source,destination,count,kind){return{source:id(source),destination:id(destination),count,kind};}
function copyPairs(copies){const edges=[];for(const copy of copies){let a=0,b=0,ao=0,bo=0;while(a<copy.source.runs.length&&b<copy.destination.runs.length){const source=copy.source.runs[a],destination=copy.destination.runs[b],n=Math.min(source.count-ao,destination.count-bo);edges.push(edge({client:source.item.client,clock:source.item.clock+ao},{client:destination.item.client,clock:destination.item.clock+bo},n,'copied_text'));ao+=n;bo+=n;if(ao===source.count){a++;ao=0}if(bo===destination.count){b++;bo=0}}if(a!==copy.source.runs.length||b!==copy.destination.runs.length)throw TypeError('Incomplete dependency copy');}return edges;}
function copyAllocations(sourceDoc,afterDoc,expected,fresh){
 const before=contentEditIdentityLayout(captureContentEditSnapshot(sourceDoc.getXmlFragment('default'))),after=contentEditIdentityLayout(captureContentEditSnapshot(afterDoc.getXmlFragment('default'))),edges=[];
 const allocated=new Map(fresh.map(record=>[key(record.item),record]));
 const freshItem=item=>allocated.has(key(item.id));
 for(const mapped of expected.copied_subtree_ranges){
  for(const original of before.positions){if(original.position<mapped.source_from||original.position+original.size>mapped.source_from+mapped.length)continue;
   const position=mapped.destination_from+original.position-mapped.source_from;
   const candidates=after.positions.filter(target=>target.position===position&&target.size===original.size&&target.node.kind===original.node.kind&&(original.node.kind==='text'||target.node.name===original.node.name));
   if(candidates.length>1)throw TypeError('Ambiguous copied branch allocation');if(!candidates.length)continue;
   const target=candidates[0],sourceType=itemAt(sourceDoc,original.node.type),targetType=itemAt(afterDoc,target.node.type);
   if(!freshItem(targetType))continue;
   if(!(sourceType.content instanceof Y.ContentType)||!(targetType.content instanceof Y.ContentType))throw TypeError('Unavailable copied type allocation');
   edges.push(edge(sourceType.id,targetType.id,1,'copied_type'));
   const source=sourceType.content.type,destination=targetType.content.type;
   if(original.node.kind==='element')for(const [field,sourceItem]of source._map){if(sourceItem.deleted||field==='relaymarkId')continue;const targetItem=destination._map.get(field);if(!targetItem||targetItem.deleted||!freshItem(targetItem)||!same(sourceItem.content.getContent(),targetItem.content.getContent()))throw TypeError('Incomplete copied field allocation');edges.push(edge(sourceItem.id,targetItem.id,1,'copied_field'));}
   if(original.node.kind==='text'){
    const formats=branch=>{const result=[];let offset=0;for(let item=branch._start;item;item=item.right){if(item.deleted)continue;if(item.content instanceof Y.ContentFormat)result.push({item,offset});else if(item.content instanceof Y.ContentString)offset+=item.length;else throw TypeError('Unavailable copied inline dependency');}return result;};
    const sourceFormats=formats(source),targetFormats=formats(destination);
    for(const targetFormat of targetFormats){if(!freshItem(targetFormat.item))continue;const matches=sourceFormats.filter(part=>part.offset===targetFormat.offset&&part.item.content.key===targetFormat.item.content.key&&same(part.item.content.value,targetFormat.item.content.value));if(matches.length>1)throw TypeError('Ambiguous copied format allocation');if(matches.length===1)edges.push(edge(matches[0].item.id,targetFormat.item.id,1,'copied_format'));}
   }
  }
 }
 return edges;
}
function merged(ranges){const result=[];for(const r of ranges.slice().sort((a,b)=>a.item.client-b.item.client||a.item.clock-b.item.clock)){const last=result.at(-1);if(last&&last.item.client===r.item.client&&r.item.clock<=last.item.clock+last.count)last.count=Math.max(last.item.clock+last.count,r.item.clock+r.count)-last.item.clock;else result.push({item:id(r.item),count:r.count});}return result;}
function intersects(ranges,item,count){return ranges.some(range=>range.item.client===item.client&&range.item.clock<item.clock+count&&item.clock<range.item.clock+range.count);}
function closure(seeds,edges){let ranges=merged(seeds),changed=true,budget=MAX;while(changed){if(--budget<0)throw TypeError('Dependency closure resource limit');const additions=[];for(const e of edges)for(const r of ranges){if(r.item.client!==e.source.client)continue;const from=Math.max(r.item.clock,e.source.clock),to=Math.min(r.item.clock+r.count,e.source.clock+e.count);if(from<to)additions.push({item:{client:e.destination.client,clock:e.destination.clock+from-e.source.clock},count:to-from});}const next=merged([...ranges,...additions]);changed=!same(ranges,next);ranges=next;if(ranges.length>MAX)throw TypeError('Dependency closure resource limit');}return ranges;}
function stackRanges(set){return[...set.clients].flatMap(([client,ranges])=>ranges.map(r=>({item:{client,clock:r.clock},count:r.len})));}
const hash=bytes=>Array.from(digest(bytes),value=>value.toString(16).padStart(2,'0')).join('');
function encodedBytes(value){let bytes=0;for(const character of JSON.stringify(value)){const point=character.codePointAt(0);bytes+=point<=0x7f?1:point<=0x7ff?2:point<=0xffff?3:4;if(bytes>32*1024*1024)throw TypeError('Dependency checkpoint byte resource limit');}return bytes;}
function scope(value){if(typeof value.actor_id!=='string'||!value.actor_id||value.actor_id.length>128)throw TypeError('Invalid actor dependency namespace');canonicalOperationID(value.owner_id);return value.actor_id+'/'+value.owner_id;}
function association(receipt,roster){fields(receipt,['transaction_id','transaction_sha256','update_sha256','issued_reference_sha256','actor_id','owner_id']);canonicalOperationID(receipt.transaction_id);if(!roster.has(scope(receipt)))throw TypeError('Foreign dependency association manager');for(const field of ['transaction_sha256','update_sha256','issued_reference_sha256'])if(typeof receipt[field]!=='string'||!/^[0-9a-f]{64}$/.test(receipt[field]))throw TypeError('Invalid dependency receipt digest');return clone(receipt);}
function cut(value){fields(value,['through_update_id','state_sha256']);if(!Number.isSafeInteger(value.through_update_id)||value.through_update_id<0||typeof value.state_sha256!=='string'||!/^[0-9a-f]{64}$/.test(value.state_sha256))throw TypeError('Invalid dependency checkpoint cut');}
function textRanges(doc,selection){fields(selection,['runs']);if(!Array.isArray(selection.runs))throw TypeError('Invalid dependency source intervals');for(const run of selection.runs){fields(run,['type','item','count']);fields(run.type,['client','clock']);range({item:run.type,count:1});for(const part of storedRanges(doc,[{item:run.item,count:run.count}]))if(!(part.stored.content instanceof Y.ContentString)||!(part.stored.parent instanceof Y.XmlText)||!part.stored.parent._item||!same(id(part.stored.parent._item.id),run.type))throw TypeError('Wrong dependency source item/type');}return selection.runs.map(({item,count})=>({item,count}));}
function subset(wanted,available){for(const r of wanted){let clock=r.item.clock,end=clock+r.count;for(const other of available.filter(p=>p.item.client===r.item.client).sort((a,b)=>a.item.clock-b.item.clock)){if(other.item.clock>clock)break;if(other.item.clock+other.count>clock)clock=Math.min(end,other.item.clock+other.count);}if(clock!==end)throw TypeError('Unaccounted dependency checkpoint interval');}}
export function planRecoveryRetirement(input,owner){
 fields(input,['binding','current_state_base64','current_cut','expected_manager_scopes','manager_contexts','imports','dependency_checkpoint','checkpoint_state_base64'],['binding','current_state_base64','current_cut','expected_manager_scopes','manager_contexts','imports']);fields(input.binding,['document_id','incarnation']);canonicalOperationID(input.binding.document_id);canonicalOperationID(input.binding.incarnation);cut(input.current_cut);encodedBytes(input);
 if(!Array.isArray(input.expected_manager_scopes)||!Array.isArray(input.manager_contexts)||!Array.isArray(input.imports))throw TypeError('Unavailable complete dependency roster');
 const roster=new Set();for(const value of input.expected_manager_scopes){fields(value,['actor_id','owner_id']);const identity=scope(value);if(roster.has(identity))throw TypeError('Duplicate dependency manager scope');roster.add(identity);}
 const contexts=new Set();for(const value of input.manager_contexts){fields(value,['actor_id','owner_id','initial_state_base64','checkpoint','receipts'],['actor_id','owner_id','receipts']);const identity=scope(value);if(contexts.has(identity)||!roster.has(identity))throw TypeError('Incomplete dependency manager scope');contexts.add(identity);}
 if(!same([...contexts].sort(),[...roster].sort())||!contexts.size||contexts.size>4096)throw TypeError('Incomplete dependency manager roster');
 if(Object.hasOwn(input,'dependency_checkpoint')!==Object.hasOwn(input,'checkpoint_state_base64'))throw TypeError('Unavailable dependency checkpoint state');
 if(!input.dependency_checkpoint&&input.manager_contexts.some(context=>context.checkpoint))throw TypeError('Checkpoint recovery dependencies require authenticated pre-cut summary');
 const currentBytes=owner.bytes(input.current_state_base64);if(hash(currentBytes)!==input.current_cut.state_sha256)throw TypeError('Dependency current state digest mismatch');
 const current=owner.owner(currentBytes),retained=[],edges=[],sourceEdges=[],associations=new Map();let material=0;
 const budget=ranges=>{if(!Array.isArray(ranges)||(material+=ranges.length)>MAX)throw TypeError('Aggregate dependency interval resource limit');return ranges;};
 try{
  if(input.dependency_checkpoint){
   const previous=input.dependency_checkpoint;fields(previous,['binding','through_update_id','state_sha256','manager_scopes','associations']);cut({through_update_id:previous.through_update_id,state_sha256:previous.state_sha256});
   const state=owner.bytes(input.checkpoint_state_base64);if(!same(previous.binding,input.binding)||previous.through_update_id>input.current_cut.through_update_id||hash(state)!==previous.state_sha256||(previous.through_update_id===input.current_cut.through_update_id&&previous.state_sha256!==input.current_cut.state_sha256))throw TypeError('Dependency checkpoint binding/cut/state mismatch');
   if(!Array.isArray(previous.manager_scopes)||!Array.isArray(previous.associations))throw TypeError('Unavailable dependency checkpoint roster');
   const oldRoster=new Set();for(const manager of previous.manager_scopes){fields(manager,['actor_id','owner_id']);const identity=scope(manager);if(oldRoster.has(identity)||!roster.has(identity))throw TypeError('Foreign dependency checkpoint roster');oldRoster.add(identity);}
   const checkpointScopes=input.manager_contexts.filter(context=>context.checkpoint).map(scope).sort();if(!same(checkpointScopes,[...oldRoster].sort()))throw TypeError('Dependency checkpoint manager roster mismatch');
   const prior=owner.owner(state);try{
    const frontier=captureContentEditFootprint(prior,Uint8Array.of(0,0)).state_vector;
    for(const context of input.manager_contexts)if(context.checkpoint&&!same(context.checkpoint.state_vector,frontier))throw TypeError('Dependency manager checkpoint frontier mismatch');
    for(const summary of previous.associations){fields(summary,['receipt','imported_items','capability_items','source_items']);const receipt=association(summary.receipt,oldRoster);if(associations.has(receipt.transaction_id))throw TypeError('Duplicate dependency association');
     storedRanges(prior,budget(summary.imported_items));storedRanges(prior,budget(summary.capability_items));budget(summary.source_items?.runs);const source=textRanges(prior,summary.source_items);
     subset(summary.imported_items,merged(summary.capability_items));subset(source,merged(summary.capability_items));
     associations.set(receipt.transaction_id,{receipt,imported_items:clone(summary.imported_items),capability_items:clone(summary.capability_items),source_items:clone(summary.source_items)});
    }
   }finally{prior.destroy()}
  }
  for(const added of input.imports){fields(added,['receipt','imported_items']);const receipt=association(added.receipt,roster);if(associations.has(receipt.transaction_id))throw TypeError('Duplicate or relabeled dependency association');
   const context=input.manager_contexts.find(context=>context.actor_id===receipt.actor_id&&context.owner_id===receipt.owner_id),original=context.receipts.find(command=>command.transaction_id===receipt.transaction_id);
   if(!original||hash(owner.bytes(original.update_base64))!==receipt.update_sha256)throw TypeError('Unavailable original dependency association receipt');
   const imports=storedRanges(current,budget(added.imported_items));if(!imports.length||merged(added.imported_items).reduce((n,r)=>n+r.count,0)!==added.imported_items.reduce((n,r)=>n+r.count,0))throw TypeError('Empty or overlapping imported dependencies');
   associations.set(receipt.transaction_id,{receipt,imported_items:clone(added.imported_items),capability_items:clone(added.imported_items),source_items:{runs:imports.filter(part=>part.stored.content instanceof Y.ContentString).map(part=>({type:id(part.stored.parent._item.id),item:part.item,count:part.count}))}});
  }
  if(!associations.size)throw TypeError('Unavailable reviewed dependency associations');
  for(const context of input.manager_contexts){
   const observe=({receipt,doc,footprint})=>{
    const imported=input.imports.find(association=>association.receipt.transaction_id===receipt.transaction_id&&association.receipt.actor_id===context.actor_id&&association.receipt.owner_id===context.owner_id);
    if(imported&&!same(merged(imported.imported_items),merged(footprint.structs.map(({item,count})=>({item,count})))))throw TypeError('Imported dependencies differ from exact original fresh allocation union');
    const sender=owner.owner(owner.bytes(receipt.sender_state_base64));try{
     const expected=applyContentEdit(contentEditIdentityLayout(captureContentEditSnapshot(sender.getXmlFragment('default'))).pm,receipt.operation);
     if(!receipt.operation.history&&!receipt.operation.reviewed_recovery){
      const senderAfter=owner.owner(owner.bytes(receipt.sender_state_base64));try{Y.applyUpdate(senderAfter,owner.bytes(receipt.update_base64));
       const proof=buildContentEditWitness({sender_before_snapshot:captureContentEditSnapshot(sender.getXmlFragment('default')),sender_after_snapshot:captureContentEditSnapshot(senderAfter.getXmlFragment('default')),before_snapshot:captureContentEditSnapshot(sender.getXmlFragment('default')),after_snapshot:captureContentEditSnapshot(senderAfter.getXmlFragment('default')),before_state_vector:captureContentEditFootprint(sender,Uint8Array.of(0,0)).state_vector,operation:{...receipt.operation,copies:[]},footprint:captureContentEditFootprint(senderAfter,owner.bytes(receipt.update_base64))});
       if(!same(proof.proven_copies,receipt.operation.copies))throw TypeError('Unavailable independently derived copy dependency');
       const text=copyPairs(proof.proven_copies);edges.push(...text);sourceEdges.push(...text);edges.push(...copyAllocations(sender,senderAfter,expected,footprint.structs));
      }finally{senderAfter.destroy()}
     }
     // Effective predecessor effects propagate capabilities, never independent
     // typing merely sharing a parent or origin/right-origin anchor.
     for(const previous of footprint.deleted_items){if(previous.key===null&&previous.content.kind!=='format')continue;for(const fresh of footprint.structs){if(!same(previous.parent,fresh.parent)||previous.key!==fresh.key||previous.content.kind!==fresh.content.kind||(previous.content.kind==='format'&&previous.content.key!==fresh.content.key))continue;edges.push(edge(previous.item,fresh.item,Math.min(previous.count,fresh.count),'field_predecessor'));}}
     if(edges.length>MAX)throw TypeError('Dependency edge resource limit');
    }finally{sender.destroy()}
   };
   const {actor_id,...basis}=context;const value=owner.checkpointOwner({...basis,current_state_base64:input.current_state_base64},observe);retained.push({...value,actor_id,owner_id:context.owner_id});
   for(const structs of value.doc.store.clients.values())for(const item of structs){if(!(item instanceof Y.Item)||!item.redone)continue;const target=itemAt(value.doc,id(item.redone));if(target.id.clock+target.length<item.redone.clock+item.length)throw TypeError('Unavailable dependency redone extent');const link=edge(item.id,item.redone,item.length,'redone');edges.push(link);if(item.content instanceof Y.ContentString)sourceEdges.push(link);if(edges.length>MAX)throw TypeError('Dependency edge resource limit');}
  }
  const planned=[],summaries=[];
  for(const previous of associations.values()){
   const capability=closure(previous.capability_items,edges),source=closure(textRanges(current,previous.source_items),sourceEdges),retirements=[];
   for(const manager of retained){const groups=[],seen=new Set();for(const item of [...manager.manager.undoStack,...manager.manager.redoStack]){
    if(![...stackRanges(item.insertions),...stackRanges(item.deletions)].some(r=>intersects(capability,r.item,r.count)))continue;
    const group=item.meta.get('relaymark:operation_ids');if(!group||group.owner_id!==manager.owner_id)throw TypeError('Unavailable actual dependency group');if(seen.has(group.reference))throw TypeError('Ambiguous actual dependency group');seen.add(group.reference);groups.push(clone(group));
   }if(groups.length)retirements.push({actor_id:manager.actor_id,owner_id:manager.owner_id,groups});}
   const source_dependencies={runs:storedRanges(current,source).map(part=>{const parent=part.stored.parent;if(!(parent instanceof Y.XmlText)||!parent._item)throw TypeError('Unavailable dependency text type');return{type:id(parent._item.id),item:part.item,count:part.count};})};
   budget(capability);budget(source_dependencies.runs);
   planned.push({receipt:clone(previous.receipt),retirements,source_dependencies});summaries.push({receipt:clone(previous.receipt),imported_items:previous.imported_items,capability_items:capability,source_items:source_dependencies});
  }
  const dependency_checkpoint={binding:clone(input.binding),...clone(input.current_cut),manager_scopes:clone(input.expected_manager_scopes),associations:summaries};
  const result={binding:clone(input.binding),associations:planned,dependency_checkpoint,dependency_edges:[...new Map(edges.map(e=>[stableStringify(e),e])).values()],complete_dependency_correspondence:true};encodedBytes(result);return result;
 }finally{for(const value of retained)value.destroy();current.destroy();}
}
