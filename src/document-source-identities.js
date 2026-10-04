/** Stateless classification over host-authenticated current receipts. The host
 * authenticates original bytes, hashes, binding, actor and complete mutation
 * correspondence first. These helpers neither admit updates nor grant access. */
import {equalCanonicalJSON,cloneCanonicalJSON} from './canonical-json.js';
const maxUnits=131072,maxRuns=4096;
const fail=(message,code='source_reference_mismatch')=>{throw Object.assign(new TypeError(message),{code});};
const exact=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
const validID=id=>exact(id,['client','clock'])&&Number.isSafeInteger(id.client)&&id.client>=0&&Number.isInteger(id.clock)&&id.clock>=0&&id.clock<=0xffffffff;
const key=id=>`${id.client}:${id.clock}`;
function binding(value){if(!exact(value,['document_id','incarnation'])||Object.values(value).some(v=>typeof v!=='string'||!v||v.length>128))fail('Invalid source binding');}
export function decodeSourceSelector(selector){
 if(!exact(selector,['runs'])||!Array.isArray(selector.runs))fail('Invalid source selector');
 if(selector.runs.length>maxRuns)fail('Source selector budget','source_identity_limit');
 const identities=new Map();let units=0;
 for(const run of selector.runs){
  if(!exact(run,['item','type','count'])||!validID(run.item)||!validID(run.type)||!Number.isInteger(run.count)||run.count<1||run.item.clock+run.count>0x100000000)fail('Invalid source selector');
  if((units+=run.count)>maxUnits)fail('Source selector budget','source_identity_limit');
  for(let offset=0;offset<run.count;offset++){
   const item={client:run.item.client,clock:run.item.clock+offset},id=key(item);
   if(identities.has(id))fail('Overlapping source identities');
   identities.set(id,{item,type:{...run.type}});
  }
 }
 return identities;
}
export function encodeSourceIdentities(identities){
 if(!(identities instanceof Map))fail('Invalid source identities');
 if(identities.size>maxUnits)fail('Source identity budget','source_identity_limit');
 const runs=[];
 for(const [id,value] of [...identities].sort((a,b)=>a[1].item.client-b[1].item.client||a[1].item.clock-b[1].item.clock)){
  if(!value||!validID(value.item)||!validID(value.type)||id!==key(value.item))fail('Invalid source identities');
  const previous=runs.at(-1);
  if(previous&&previous.item.client===value.item.client&&previous.item.clock+previous.count===value.item.clock&&equalCanonicalJSON(previous.type,value.type))previous.count++;
  else runs.push({item:{...value.item},type:{...value.type},count:1});
 }
 const selector={runs};decodeSourceSelector(selector);return selector;
}
function copyPairs(copies){
 if(!Array.isArray(copies))fail('Invalid source copies');
 if(copies.length>maxRuns)fail('Source copy budget','source_identity_limit');
 let total=0;const seen=new Set(),pairs=[];
 for(const copy of copies){
  if(!exact(copy,['source','destination']))fail('Invalid source copy');
  const source=[...decodeSourceSelector(copy.source).values()],destination=[...decodeSourceSelector(copy.destination).values()];
  if(source.length!==destination.length)fail('Source copy correspondence');
  if((total+=source.length)>maxUnits)fail('Source copy budget','source_identity_limit');
  for(let i=0;i<source.length;i++){
   const id=key(destination[i].item);if(seen.has(id))fail('Overlapping copy destinations');seen.add(id);pairs.push([source[i],destination[i]]);
  }
 }
 return pairs;
}
export function classifyContentEditReference(documentBinding,transaction,proof,humanAncestry){
 binding(documentBinding);
 if(!transaction||typeof transaction.transaction_id!=='string'||!transaction.content_edit||!proof||proof.complete_mutation_correspondence!==true||!equalCanonicalJSON(proof.text_items,transaction.text_items)||!equalCanonicalJSON(proof.proven_copies,transaction.content_edit.copies))fail('Source reference mismatch');
 const typed=decodeSourceSelector(transaction.text_items),ancestry=decodeSourceSelector(humanAncestry),copies=transaction.content_edit.copies;
 if(transaction.content_edit.history&&(proof.owned_history_correspondence!==true||typed.size||!equalCanonicalJSON(proof.restored_copies,copies)))fail('Owned source history mismatch');
 const human=new Map(typed);
 for(const [source,destination] of copyPairs(copies)){
  if(typed.has(key(destination.item)))fail("Typed and copied destinations overlap");
  const known=ancestry.get(key(source.item));
  if(known){if(!equalCanonicalJSON(known.type,source.type))fail('Source identity type mismatch','source_identity_mismatch');human.set(key(destination.item),destination);}
 }
 return cloneCanonicalJSON({binding:documentBinding,transaction_id:transaction.transaction_id,text_items:transaction.text_items,proven_copies:copies,human_destinations:encodeSourceIdentities(human)});
}
/** Receipt references must already be authenticated against their original
 * transaction. Candidates bound memory; absent ancestry remains generated. */
export function foldSourceReferences(documentBinding,candidateSelector,references){
 binding(documentBinding);const candidates=decodeSourceSelector(candidateSelector),human=new Map();
 if(!Array.isArray(references))fail('Invalid source references');
 if(references.length>16384)fail('Source receipt budget','source_identity_limit');
 for(const reference of references){
  if(!exact(reference,['binding','transaction_id','text_items','proven_copies','human_destinations'])||!equalCanonicalJSON(reference.binding,documentBinding))fail('Source reference binding mismatch');
  const typed=decodeSourceSelector(reference.text_items),admitted=decodeSourceSelector(reference.human_destinations),destinations=new Map(copyPairs(reference.proven_copies).map(([,destination])=>[key(destination.item),destination]));
  for(const [id,value] of typed)if(!equalCanonicalJSON(admitted.get(id),value))fail('Missing typed human destination');
  for(const [id,value] of admitted){
   if(!equalCanonicalJSON(typed.get(id),value)&&!equalCanonicalJSON(destinations.get(id),value))fail('Unproven human destination');
   const candidate=candidates.get(id);if(candidate){if(!equalCanonicalJSON(candidate.type,value.type))fail('Source identity type mismatch','source_identity_mismatch');human.set(id,value);}
  }
 }
 return encodeSourceIdentities(human);
}
