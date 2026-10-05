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
// REVIEW ONLY: bounded interval validation replacing fold's per-unit temporary maps.
// Command classifier/public Map APIs are unchanged. No caller-authentication owner moves.
function referenceRanges(selector){
 if(!exact(selector,['runs'])||!Array.isArray(selector.runs))fail('Invalid source selector');
 if(selector.runs.length>maxRuns)fail('Source selector budget','source_identity_limit');
 let units=0;const ordered=[];
 const ranges=selector.runs.map(run=>{
  if(!exact(run,['item','type','count'])||!validID(run.item)||!validID(run.type)||!Number.isInteger(run.count)||run.count<1||run.item.clock+run.count>0x100000000)fail('Invalid source selector');
  if((units+=run.count)>maxUnits)fail('Source selector budget','source_identity_limit');
  const value={client:run.item.client,start:run.item.clock,end:run.item.clock+run.count,type:run.type};
  let low=0,high=ordered.length;while(low<high){const mid=(low+high)>>>1,other=ordered[mid];if(other.client<value.client||(other.client===value.client&&other.start<value.start))low=mid+1;else high=mid;}
  const previous=ordered[low-1],next=ordered[low];
  if((previous?.client===value.client&&previous.end>value.start)||(next?.client===value.client&&next.start<value.end))fail('Overlapping source identities');
  ordered.splice(low,0,value);return value;
 });
 return {ranges,ordered,units};
}
function sameSourceType(left,right){return left.client===right.client&&left.clock===right.clock;}
function uncoveredSourceClock(range,available){
 let at=range.start;
 for(const candidate of available){
  if(candidate.client!==range.client||!sameSourceType(candidate.type,range.type)||candidate.end<=at)continue;
  if(candidate.start>at)return at;
  at=Math.max(at,candidate.end);if(at>=range.end)return null;
 }
 return at;
}
function referenceCopyDestinations(copies){
 if(!Array.isArray(copies))fail('Invalid source copies');
 if(copies.length>maxRuns)fail('Source copy budget','source_identity_limit');
 let total=0;const destinations=[];
 for(const copy of copies){
  if(!exact(copy,['source','destination']))fail('Invalid source copy');
  const source=referenceRanges(copy.source),destination=referenceRanges(copy.destination);
  if(source.units!==destination.units)fail('Source copy correspondence');
  if((total+=source.units)>maxUnits)fail('Source copy budget','source_identity_limit');
  for(const value of destination.ranges){
   let low=0,high=destinations.length;while(low<high){const mid=(low+high)>>>1,other=destinations[mid];if(other.client<value.client||(other.client===value.client&&other.start<value.start))low=mid+1;else high=mid;}
   const previous=destinations[low-1],next=destinations[low];
   if((previous?.client===value.client&&previous.end>value.start)||(next?.client===value.client&&next.start<value.end))fail('Overlapping copy destinations');
   destinations.splice(low,0,value);
  }
 }
 return destinations;
}
function mergeReferenceRanges(ranges){
 const merged=[];
 for(const range of ranges.sort((a,b)=>a.client-b.client||a.start-b.start)){
  const previous=merged.at(-1);
  if(previous&&previous.client===range.client&&previous.end>=range.start&&sameSourceType(previous.type,range.type))previous.end=Math.max(previous.end,range.end);
  else merged.push({...range});
 }
 return merged;
}
function encodeReferenceRanges(ranges){
 const selector={runs:mergeReferenceRanges(ranges).map(range=>({item:{client:range.client,clock:range.start},type:{...range.type},count:range.end-range.start}))};
 referenceRanges(selector);return selector;
}
export function foldSourceReferences(documentBinding,candidateSelector,references){
 binding(documentBinding);const candidates=referenceRanges(candidateSelector).ordered;let human=[];
 if(!Array.isArray(references))fail('Invalid source references');
 if(references.length>16384)fail('Source receipt budget','source_identity_limit');
 for(const reference of references){
  if(!exact(reference,['binding','transaction_id','text_items','proven_copies','human_destinations'])||!equalCanonicalJSON(reference.binding,documentBinding))fail('Source reference binding mismatch');
  const typed=referenceRanges(reference.text_items),admitted=referenceRanges(reference.human_destinations),destinations=referenceCopyDestinations(reference.proven_copies);
  for(const value of typed.ranges)if(uncoveredSourceClock(value,admitted.ordered)!==null)fail('Missing typed human destination');
  const authorized=[...typed.ordered,...destinations].sort((a,b)=>a.client-b.client||a.start-b.start),intersections=[];
  // Follow original packet order and preserve the first per-unit refusal code.
  for(const value of admitted.ranges){
   const gap=uncoveredSourceClock(value,authorized);let mismatch=null;
   for(const candidate of candidates){
    if(candidate.client<value.client)continue;
    if(candidate.client>value.client)break;
    if(candidate.end<=value.start)continue;
    if(candidate.start>=value.end)break;
    const start=Math.max(candidate.start,value.start),end=Math.min(candidate.end,value.end);
    if(!sameSourceType(candidate.type,value.type)){mismatch=start;break;}
    intersections.push({client:value.client,start,end,type:value.type});
   }
   if(mismatch!==null&&(gap===null||mismatch<gap))fail('Source identity type mismatch','source_identity_mismatch');
   if(gap!==null)fail('Unproven human destination');
   if(mismatch!==null)fail('Source identity type mismatch','source_identity_mismatch');
  }
  human=mergeReferenceRanges([...human,...intersections]);
 }
 return encodeReferenceRanges(human);
}
