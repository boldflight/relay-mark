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
export function classifyContentEditReference(documentBinding,transaction,proof,humanAncestry,regionalContext){
 binding(documentBinding);
 if(!transaction||typeof transaction.transaction_id!=='string'||!transaction.content_edit||!proof||proof.complete_mutation_correspondence!==true||!equalCanonicalJSON(proof.text_items,transaction.text_items)||!equalCanonicalJSON(proof.proven_copies,transaction.content_edit.copies))fail('Source reference mismatch');
 const typed=decodeSourceSelector(transaction.text_items),ancestry=decodeSourceSelector(humanAncestry),copies=transaction.content_edit.copies;
 if(transaction.content_edit.history&&(proof.owned_history_correspondence!==true||typed.size||!equalCanonicalJSON(proof.restored_copies,copies)))fail('Owned source history mismatch');
 let regionalHuman;
 if(transaction.content_edit.reviewed_recovery){
  if(transaction.content_edit.history||typed.size||copies.length||proof.complete_recovery_correspondence!==true||!proof.operation||!equalCanonicalJSON(proof.operation.reviewed_recovery,transaction.content_edit.reviewed_recovery)||!equalCanonicalJSON(proof.operation.steps,transaction.content_edit.steps)||!equalCanonicalJSON(proof.recovery_regions,regionalContext?.recovery_regions))fail('Reviewed source correspondence mismatch');
  const regional=regionalContextRanges(regionalContext);
  if(!equalCanonicalJSON(encodeReferenceRanges(regional.destinations),encodeReferenceRanges(referenceRanges(proof.fresh_items).ordered)))fail('Incomplete reviewed allocation correspondence');
  regionalHuman=decodeSourceSelector(regionalContext.human_destinations);
 }else if(regionalContext!==undefined)fail('Unexpected reviewed source context');
 const human=new Map(regionalHuman||typed);
 for(const [source,destination] of copyPairs(copies)){
  if(typed.has(key(destination.item)))fail("Typed and copied destinations overlap");
  const known=ancestry.get(key(source.item));
  if(known){if(!equalCanonicalJSON(known.type,source.type))fail('Source identity type mismatch','source_identity_mismatch');human.set(key(destination.item),destination);}
 }
 return cloneCanonicalJSON({binding:documentBinding,transaction_id:transaction.transaction_id,text_items:transaction.text_items,proven_copies:copies,human_destinations:encodeSourceIdentities(human)});
}
/** Receipt references must already be authenticated against their original
 * transaction. Candidates bound memory; absent ancestry remains generated. */
// Candidate-bounded interval validation; command selector and authentication bounds remain unchanged.
function referenceRanges(selector,summary=false){
 if(!exact(selector,['runs'])||!Array.isArray(selector.runs))fail('Invalid source selector');
 if(selector.runs.length>(summary?1_000_000:maxRuns))fail('Source selector budget','source_identity_limit');
 let units=0;const ordered=[];
 const ranges=selector.runs.map(run=>{
  if(!exact(run,['item','type','count'])||!validID(run.item)||!validID(run.type)||!Number.isInteger(run.count)||run.count<1||run.item.clock+run.count>0x100000000)fail('Invalid source selector');
  units+=run.count;if(!summary&&units>maxUnits)fail('Source selector budget','source_identity_limit');
  const value={client:run.item.client,start:run.item.clock,end:run.item.clock+run.count,type:run.type};
  if(summary)return value;
  let low=0,high=ordered.length;while(low<high){const mid=(low+high)>>>1,other=ordered[mid];if(other.client<value.client||(other.client===value.client&&other.start<value.start))low=mid+1;else high=mid;}
  const previous=ordered[low-1],next=ordered[low];
  if((previous?.client===value.client&&previous.end>value.start)||(next?.client===value.client&&next.start<value.end))fail('Overlapping source identities');
  ordered.splice(low,0,value);return value;
 });
 if(summary){
  for(const value of ranges.sort((a,b)=>a.client-b.client||a.start-b.start))ordered.push(value);
  for(let i=1;i<ordered.length;i++)if(ordered[i-1].client===ordered[i].client&&ordered[i-1].end>ordered[i].start)fail('Overlapping source identities');
 }
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
/** Private regional contexts are supplied only after the host authenticates the
 * issued outer association and its original command/replayed allocation proof.
 * The normal five-field reference remains unchanged and is not a credential. */
export function foldSourceReferences(documentBinding,candidateSelector,references,regionalContexts){
 binding(documentBinding);const candidates=referenceRanges(candidateSelector).ordered;let human=[];
 if(!Array.isArray(references))fail('Invalid source references');
 if(references.length>16384)fail('Source receipt budget','source_identity_limit');
 if(regionalContexts!==undefined&&(!regionalContexts||typeof regionalContexts!=='object'||Array.isArray(regionalContexts)))fail('Invalid reviewed reference contexts');
 const contextKeys=regionalContexts===undefined?[]:Object.keys(regionalContexts),usedContexts=new Set();
 if(contextKeys.length>16384)fail('Source receipt budget','source_identity_limit');
 for(const reference of references){
  if(!exact(reference,['binding','transaction_id','text_items','proven_copies','human_destinations'])||!equalCanonicalJSON(reference.binding,documentBinding))fail('Source reference binding mismatch');
  const typed=referenceRanges(reference.text_items),admitted=referenceRanges(reference.human_destinations),destinations=referenceCopyDestinations(reference.proven_copies);
  for(const value of typed.ranges)if(uncoveredSourceClock(value,admitted.ordered)!==null)fail('Missing typed human destination');
  const context=regionalContexts&&Object.hasOwn(regionalContexts,reference.transaction_id)?regionalContexts[reference.transaction_id]:undefined;
  let regional=[];
  if(context!==undefined){
   if(usedContexts.has(reference.transaction_id)||typed.units||destinations.length)fail('Reviewed reference context mismatch');
   usedContexts.add(reference.transaction_id);
   const validated=regionalContextRanges(context);regional=validated.human.ordered;
   if(!equalCanonicalJSON(encodeReferenceRanges(regional),encodeReferenceRanges(admitted.ordered)))fail('Reviewed human reference mismatch');
  }
  const authorized=[...typed.ordered,...destinations,...regional].sort((a,b)=>a.client-b.client||a.start-b.start),intersections=[];
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
 if(contextKeys.some(key=>!usedContexts.has(key)))fail('Unmatched reviewed reference context');
 return encodeReferenceRanges(human);
}

/** Regional shapes are structural evidence, never donor/authorship authority.
 * Destination and archive intervals are bounded/disjoint before any partition. */
function regionalDestinationRanges(regions){
 if(!Array.isArray(regions))fail('Invalid reviewed regions');
 if(regions.length>maxRuns)fail('Source selector budget','source_identity_limit');
 const paths=new Map(),runs=[];let units=0;
 for(const region of regions){
  if(!exact(region,['archive_path','archive_offset','count','destination'])||!Array.isArray(region.archive_path)||region.archive_path.length>128||region.archive_path.some(n=>!Number.isSafeInteger(n)||n<0)||!Number.isSafeInteger(region.archive_offset)||region.archive_offset<0||!Number.isSafeInteger(region.count)||region.count<1||!Number.isSafeInteger(region.archive_offset+region.count))fail('Invalid reviewed region');
  if((units+=region.count)>maxUnits)fail('Source selector budget','source_identity_limit');
  const destination=referenceRanges(region.destination);if(destination.units!==region.count)fail('Reviewed destination extent mismatch');
  const path=JSON.stringify(region.archive_path),previous=paths.get(path)||[],end=region.archive_offset+region.count;
  if(previous.some(part=>part.start<end&&part.end>region.archive_offset))fail('Overlapping reviewed archive regions');
  previous.push({start:region.archive_offset,end});paths.set(path,previous);runs.push(...region.destination.runs);
 }
 return referenceRanges({runs}).ordered;
}
function requireRegionalSubset(selector,destinations){
 const subset=referenceRanges(selector);
 for(const part of subset.ranges){
  if(destinations.some(value=>value.client===part.client&&value.start<part.end&&value.end>part.start&&!sameSourceType(value.type,part.type)))fail('Source identity type mismatch','source_identity_mismatch');
  if(uncoveredSourceClock(part,destinations)!==null)fail('Unproven reviewed destination');
 }
 return subset;
}
function regionalContextRanges(context){
 if(!exact(context,['recovery_regions','human_destinations']))fail('Missing or invalid reviewed source context');
 const destinations=regionalDestinationRanges(context.recovery_regions),human=requireRegionalSubset(context.human_destinations,destinations);
 return {destinations,human};
}
/** The caller independently authenticates both supplied human and generated
 * facts. Everything else is explicitly unknown; absence is not generation. */
export function partitionReviewedRecoveryDestinations(input){
 if(!exact(input,['recovery_regions','human_destinations','generated_destinations']))fail('Invalid reviewed destination partition');
 const destinations=regionalDestinationRanges(input.recovery_regions),human=requireRegionalSubset(input.human_destinations,destinations),generated=requireRegionalSubset(input.generated_destinations,destinations);
 const known=referenceRanges({runs:[...input.human_destinations.runs,...input.generated_destinations.runs]}).ordered,unknown=[];
 unknown.push(...subtractReferenceRanges(destinations,known));
 return {human_destinations:encodeReferenceRanges(human.ordered),generated_destinations:encodeReferenceRanges(generated.ordered),unknown_destinations:encodeReferenceRanges(unknown)};
}


// Shared typed interval subtraction. Both callers validate their selectors first.
function subtractReferenceRanges(candidates,masks){
 const result=[];let first=0;
 for(const candidate of candidates){
  while(first<masks.length&&(masks[first].client<candidate.client||(masks[first].client===candidate.client&&masks[first].end<=candidate.start)))first++;
  let at=candidate.start;
  for(let i=first;i<masks.length;i++){
   const mask=masks[i];if(mask.client>candidate.client||mask.start>=candidate.end&&mask.client===candidate.client)break;
   if(mask.client!==candidate.client||mask.end<=at)continue;
   if(!sameSourceType(candidate.type,mask.type))fail('Source identity type mismatch','source_identity_mismatch');
   if(mask.start>at)result.push({...candidate,start:at,end:mask.start});
   at=Math.max(at,Math.min(candidate.end,mask.end));if(at===candidate.end)break;
  }
  if(at<candidate.end)result.push({...candidate,start:at});
 }
 return result;
}
/** Removes authenticated erasure source ranges from one bounded candidate window.
 * The host authenticates original checkpoint/receipt masks. This helper grants
 * no erasure, authorship or admission authority and never expands text units.
 * Summary input retains the existing 1M interval / 32MiB resource bounds;
 * command candidate and result bounds remain unchanged.
 */
export function subtractSourceSelectors(candidateSelector,excludedSelectors){
 const candidates=referenceRanges(candidateSelector).ordered;
 if(!Array.isArray(excludedSelectors))fail('Invalid source masks');
 if(excludedSelectors.length>1_000_000)fail('Source summary budget','source_identity_limit');
 let count=0;
 for(const selector of excludedSelectors){
  if(!exact(selector,['runs'])||!Array.isArray(selector.runs))fail('Invalid source selector');
  if((count+=selector.runs.length)>1_000_000)fail('Source summary budget','source_identity_limit');
 }
 let bytes=0;for(const character of JSON.stringify(excludedSelectors)){
  const point=character.codePointAt(0);bytes+=point<=0x7f?1:point<=0x7ff?2:point<=0xffff?3:4;
  if(bytes>33_554_432)fail('Source summary budget','source_identity_limit');
 }
 const ranges=[];for(const selector of excludedSelectors)for(const value of referenceRanges(selector,true).ordered)ranges.push(value);
 ranges.sort((a,b)=>a.client-b.client||a.start-b.start);
 const masks=[];
 for(const range of ranges){
  const previous=masks.at(-1);
  if(previous&&previous.client===range.client&&previous.end>range.start&&!sameSourceType(previous.type,range.type))fail('Source identity type mismatch','source_identity_mismatch');
  if(previous&&previous.client===range.client&&previous.end>=range.start&&sameSourceType(previous.type,range.type))previous.end=Math.max(previous.end,range.end);
  else masks.push({...range});
 }
 return encodeReferenceRanges(subtractReferenceRanges(candidates,masks));
}
