/** Closed finite aggregate-settings input. Never a selectable live codec. */
import * as Y from 'yjs';
import {Step,Transform} from 'prosemirror-transform';
import {initProseMirrorDoc,updateYFragment} from '@tiptap/y-tiptap';
import {createCanonicalEditorSchema} from '../../src/editor-model.js';
import {createContentEditWrite} from '../../src/content-edit.js';
import {proseMirrorToRelayMark} from '../../src/document-adapter.js';
import {cloneCanonicalJSON as clone,stableStringify} from '../../src/canonical-json.js';
import {validateJSONValue} from '../../src/document-adapter.js';
import {canonicalAttributeCodec,settingsAttributeKey} from '../../src/document-attributes.js';
import {readOwnedHistoryGroups} from './owned-command-group.js';
import {canonicalOperationID} from '../../src/owned-command-group.js';
const nodes=new Set(['questionBlock','questionOption']),prefix='settings:';
const same=(a,b)=>stableStringify(a)===stableStringify(b);
function object(value){if(!value||typeof value!=='object'||Array.isArray(value)||![Object.prototype,null].includes(Object.getPrototypeOf(value)))throw TypeError('Invalid finite aggregate settings');}
function validate(name,attributes){
 object(attributes);if(Object.keys(attributes).some(key=>key.startsWith(prefix)))throw TypeError('Mixed finite settings encoding');
 if(nodes.has(name)){if(!Object.hasOwn(attributes,'settings'))throw TypeError('Missing finite aggregate settings');object(attributes.settings);validateJSONValue(attributes.settings);}
 else if(Object.hasOwn(attributes,'settings'))throw TypeError('Settings on unrelated finite node');
}
export const finiteAggregateAttributeCodec=Object.freeze({
 encode(name,attributes){validate(name,attributes);return Object.fromEntries(Object.entries(attributes).filter(([,value])=>value!==null).map(([key,value])=>[key,clone(value)]));},
 decode(name,attributes){validate(name,attributes);return clone(attributes);}
});
/** Closed finite Video mapping; captured facts never authorize the mapping. */
function videoPlan(mappings){
 if(!Array.isArray(mappings)||mappings.length>1_000_000)throw TypeError('Invalid finite Video mappings');
 const plan=new Map(),questions=new Set();
 for(const mapping of mappings){
  object(mapping);if(Object.keys(mapping).sort().join(',')!=='original_video,question_id,question_relaymark_id,video_id')throw TypeError('Invalid finite Video mapping fields');
  const {question_id:id,question_relaymark_id:anchor,original_video:video,video_id:uuid}=mapping;
  if(typeof id!=='string'||!id||typeof anchor!=='string'||!anchor||plan.has(anchor)||questions.has(id))throw TypeError('Duplicate or invalid finite Video anchor');
  canonicalOperationID(uuid);object(video);validateJSONValue(video);
  if(typeof video.mux_playback_id!=='string'||!video.mux_playback_id||!(video.video_id===undefined||video.video_id===null||video.video_id===uuid))throw TypeError('Invalid retained finite Video identity');
  plan.set(anchor,clone(mapping));questions.add(id);
 }
 return plan;
}
function mappedVideo(name,attributes,plan,used){
 const mapping=plan.get(attributes.relaymarkId);
 if(!mapping)return null;
 if(name!=='questionBlock'||attributes.type!=='video_question'||attributes.id!==mapping.question_id||!same(attributes.settings?.video,mapping.original_video)||used.has(attributes.relaymarkId))throw TypeError('Finite Video source anchor mismatch');
 used.add(attributes.relaymarkId);return {...clone(mapping.original_video),video_id:mapping.video_id};
}
function complete(plan,used){if(plan.size!==used.size)throw TypeError('Unused finite Video anchor');}
/** Exact existing host insert_option patches, not a supplied target tree. */
function slotPlan(patches){
 if(patches===null)return [];
 if(!Array.isArray(patches)||patches.length>1_000_000)throw TypeError('Invalid finite Slot insertions');
 for(const patch of patches){
  object(patch);if(Object.keys(patch).sort().join(',')!=='after_option_id,kind,label,option_id,option_relaymark_id,question_id,question_relaymark_id'||patch.kind!=='insert_option')throw TypeError('Invalid finite Slot insertion fields');
  for(const key of ['question_id','question_relaymark_id','option_relaymark_id','label'])if(typeof patch[key]!=='string'||!patch[key])throw TypeError('Invalid finite Slot insertion value');
  canonicalOperationID(patch.option_id);if(patch.after_option_id!==null)canonicalOperationID(patch.after_option_id);
 }
 return patches;
}
const schema=createCanonicalEditorSchema();
const slotNode=patch=>schema.nodes.questionOption.create({relaymarkId:patch.option_relaymark_id,id:patch.option_id},schema.text(patch.label));
function slotIndex(question,patch){
 const options=question.content||[];
 if(question.type!=='questionBlock'||question.attrs?.type!=='slot_picker'||question.attrs?.id!==patch.question_id||options[0]?.type!=='questionLabel')throw TypeError('Finite Slot question mismatch');
 if(options.length>4096)throw TypeError('Finite Slot choice limit');
 if(patch.after_option_id===null)return 1;
 const index=options.findIndex((node,i)=>i>0&&node.type==='questionOption'&&node.attrs?.id===patch.after_option_id);
 if(index<1)throw TypeError('Finite Slot predecessor mismatch');return index+1;
}
/** Complete expected PM result is independently derived from original + plan. */
export function expectedFiniteSlotDocument(original,patches=null){
 const result=clone(original),plan=slotPlan(patches);if(!plan.length)return result;
 const identities=new Set(),domainIDs=new Set(),questions=new Map();let remaining=1_000_000;
 function visit(node,depth){
  if(--remaining<0||depth>64)throw TypeError('Finite settings traversal limit');
  if(node.attrs?.relaymarkId)identities.add(node.attrs.relaymarkId);
  if(['questionBlock','questionOption'].includes(node.type)&&node.attrs?.id){if(domainIDs.has(node.attrs.id))throw TypeError('Duplicate finite form identity');domainIDs.add(node.attrs.id);}
  if(node.type==='questionBlock'){if(questions.has(node.attrs.relaymarkId))throw TypeError('Ambiguous finite Slot anchor');questions.set(node.attrs.relaymarkId,node);}
  for(const child of node.content||[])visit(child,depth+1);
 }
 visit(result,0);
 for(const patch of plan){
  const question=questions.get(patch.question_relaymark_id);if(!question)throw TypeError('Unused finite Slot anchor');
  if(identities.has(patch.option_relaymark_id)||domainIDs.has(patch.option_id))throw TypeError('Duplicate finite Slot option identity');
  const index=slotIndex(question,patch),node=slotNode(patch).toJSON();question.content.splice(index,0,node);identities.add(patch.option_relaymark_id);domainIDs.add(patch.option_id);
 }
 proseMirrorToRelayMark(result);return result;
}
function slotSteps(before,patches){
 const plan=slotPlan(patches),batches=[];let transform=new Transform(before),batchBefore=before;
 const flush=()=>{if(transform.steps.length){batches.push({before:batchBefore,after:transform.doc,steps:transform.steps.map(step=>step.toJSON())});batchBefore=transform.doc;transform=new Transform(batchBefore);}};
 for(let offset=0;offset<plan.length;){
  const patch=plan[offset],run=[patch];offset++;
  // Adjacent declared successors form one exact node-boundary insertion Slice.
  while(offset<plan.length&&plan[offset].question_relaymark_id===patch.question_relaymark_id&&plan[offset].question_id===patch.question_id&&plan[offset].after_option_id===run.at(-1).option_id)run.push(plan[offset++]);
  let selected;transform.doc.descendants((node,pos)=>{if(node.type.name==='questionBlock'&&node.attrs.relaymarkId===patch.question_relaymark_id){if(selected)throw TypeError('Ambiguous finite Slot anchor');selected={node,pos};}});
  if(!selected)throw TypeError('Unused finite Slot anchor');const index=slotIndex(selected.node.toJSON(),patch);let position=selected.pos+1;
  for(let i=0;i<index;i++)position+=selected.node.child(i).nodeSize;
  transform.replaceWith(position,position,run.map(slotNode));if(transform.steps.length===512)flush();
 }
 const document=transform.doc;flush();return {document,batches};
}
/** Actual representation is privately selected from the complete original state.
 * Mixed input is refused; nothing here is a selectable live editor codec. */
export function finiteSettingsInputCodec(doc,mappings=[],slotInsertions=null){
 videoPlan(mappings);slotPlan(slotInsertions);if(!mappings.length&&slotInsertions===null)return finiteAggregateAttributeCodec;
 let encoding=null,remaining=1_000_000;
 function visit(node,depth){
  if(--remaining<0||depth>64)throw TypeError('Finite settings traversal limit');
  if(node instanceof Y.XmlText)return;
  if(!(node instanceof Y.XmlElement)&&!(node instanceof Y.XmlFragment))throw TypeError('Unknown finite editor node');
  if(node instanceof Y.XmlElement){const attributes=node.getAttributes();
   if(nodes.has(node.nodeName)){const current=attributes.settings===true?'canonical':'aggregate';if(encoding&&encoding!==current)throw TypeError('Mixed finite settings representation');encoding=current;(current==='canonical'?canonicalAttributeCodec:finiteAggregateAttributeCodec).decode(node.nodeName,attributes);}
   else canonicalAttributeCodec.decode(node.nodeName,attributes);
  }
  for(const child of node.toArray())visit(child,depth+1);
 }
 visit(doc.getXmlFragment('default'),0);if(!encoding)throw TypeError('Missing finite helper question');
 return encoding==='canonical'?canonicalAttributeCodec:finiteAggregateAttributeCodec;
}
/** Independently derives expected complete PM JSON; no supplied target AST. */
export function expectedFiniteVideoDocument(original,mappings=[]){
 const plan=videoPlan(mappings),used=new Set();let remaining=1_000_000;
 function visit(node,depth){
  if(--remaining<0||depth>64)throw TypeError('Finite settings traversal limit');
  const result=clone(node),video=mappedVideo(node.type,node.attrs||{},plan,used);
  if(video)result.attrs.settings.video=video;
  if(node.content)result.content=node.content.map(child=>visit(child,depth+1));
  return result;
 }
 const result=visit(original,0);complete(plan,used);return result;
}
/** XML traversal and field ordering exactly match DocumentXML's finite import.
 * Values, text, type identities and arbitrary other attributes are unchanged. */
export function prepareAggregateSettingsTransform(doc,mappings=[],slotInsertions=null){
 const codec=finiteSettingsInputCodec(doc,mappings,slotInsertions),plan=videoPlan(mappings),used=new Set();
 const edits=[],attributeRelations=[];let remaining=1_000_000;
 function visit(node,depth){
  if(--remaining<0||depth>64)throw TypeError('Finite settings traversal limit');
  if(node instanceof Y.XmlText)return;
  if(!(node instanceof Y.XmlElement)&&!(node instanceof Y.XmlFragment))throw TypeError('Unknown finite editor node');
  if(node instanceof Y.XmlElement){const attributes=node.getAttributes(),logical=codec.decode(node.nodeName,attributes),video=mappedVideo(node.nodeName,logical,plan,used);
   if(nodes.has(node.nodeName)){
    if(video)logical.settings.video=video;
    const next=canonicalAttributeCodec.encode(node.nodeName,logical);
    if(codec===finiteAggregateAttributeCodec){attributeRelations.push({node:{client:node._item.id.client,clock:node._item.id.clock},source:activeRegister(node,'settings',node.getAttribute('settings')),fields:Object.keys(next).filter(key=>key==='settings'||key.startsWith(prefix)).map(key=>({key,value:clone(next[key])}))});edits.push({node,key:'settings',value:true});for(const key of Object.keys(next).filter(key=>key.startsWith(prefix)).sort())edits.push({node,key,value:next[key]});}
    else if(video&&!same(attributes[settingsAttributeKey('video')],video))edits.push({node,key:settingsAttributeKey('video'),value:video});
   }
  }
  for(const child of node.toArray())visit(child,depth+1);
 }
 visit(doc.getXmlFragment('default'),0);complete(plan,used);
 const original=initProseMirrorDoc(doc.getXmlFragment('default'),schema,codec).doc,before=schema.nodeFromJSON(expectedFiniteVideoDocument(original.toJSON(),mappings)),expected=expectedFiniteSlotDocument(before.toJSON(),slotInsertions),structural=slotSteps(before,slotInsertions);
 if(!same(structural.document.toJSON(),expected))throw TypeError('Finite Slot maintained Steps disagree');
 return {correspondence:{attributes:attributeRelations,writes:edits.map(({node,key,value})=>({node:{client:node._item.id.client,clock:node._item.id.clock},key,value:clone(value)})),options:clone(slotPlan(slotInsertions))},count:edits.length+structural.batches.length,apply(){
  for(const {node,key,value}of edits)node.setAttribute(key,clone(value));
  for(const batch of structural.batches){
   const initialized=initProseMirrorDoc(doc.getXmlFragment('default'),schema,canonicalAttributeCodec);if(!same(initialized.doc.toJSON(),batch.before.toJSON()))throw TypeError('Finite Slot batch source differs');
   // The maintained binding's mapping belongs to these exact current PM nodes.
   // Replaying the declared Steps preserves that correspondence through a batch.
   let after=initialized.doc;for(const json of batch.steps){const result=Step.fromJSON(schema,json).apply(after);if(result.failed)throw TypeError('Finite Slot batch Steps refused');after=result.doc;}
   if(!same(after.toJSON(),batch.after.toJSON()))throw TypeError('Finite Slot batch result differs');
   initialized.meta.contentEditWrite=createContentEditWrite(initialized.doc,batch.steps,after);updateYFragment(doc,doc.getXmlFragment('default'),after,initialized.meta);
  }
 }};
}
/** Read actual whole manager sets, including deleted question registers.
 * A removed old question must not survive as an inverse restoring old encoding. */
const rawVideo=value=>value&&typeof value.mux_playback_id==='string'&&value.mux_playback_id&&value.video_id==null;
function validUUID(value){try{canonicalOperationID(value);return true;}catch{return false;}}
export function aggregateSettingsHistoryGroups(doc,manager,videoMappings=[],slotInsertions=null){
 const groups=readOwnedHistoryGroups(manager),registers=new Map(),videoParents=new Set(),slotParents=new Set(),typeItems=new Map(),unsupportedVideoParents=new Set(),plan=videoPlan(videoMappings);let remaining=1_000_000;
 const slotIDs=new Set(slotPlan(slotInsertions).map(patch=>patch.option_id));
 const retain=item=>{const ranges=registers.get(item.id.client)||[];ranges.push({clock:item.id.clock,end:item.id.clock+item.length});registers.set(item.id.client,ranges);};
 // Derive original question kind from actual retained type registers as well as
 // live nodes. Deleted original video questions need no fabricated live mapping.
 if(videoMappings.length||slotInsertions!==null)for(const structs of doc.store.clients.values())for(const item of structs){
  if(--remaining<0)throw TypeError('Finite settings retained-item limit');
  if(item instanceof Y.Item&&item.parent instanceof Y.XmlElement&&item.parent.nodeName==='questionBlock'&&item.parentSub==='type'){
   if(!(item.content instanceof Y.ContentAny)||item.content.arr.length!==item.length)throw TypeError('Unsupported retained question type register');
   const items=typeItems.get(item.parent)||[];items.push(item);typeItems.set(item.parent,items);
   if(item.content.arr.includes('video_question'))videoParents.add(item.parent);if(slotInsertions!==null&&item.content.arr.includes('slot_picker'))slotParents.add(item.parent);
  }
 }
 remaining=1_000_000;
 for(const structs of doc.store.clients.values())for(const item of structs){
  if(--remaining<0)throw TypeError('Finite settings retained-item limit');
  if(!(item instanceof Y.Item)||!(item.parent instanceof Y.XmlElement)||!nodes.has(item.parent.nodeName))continue;
  let relevant=false;
  if(slotIDs.size&&item.parentSub==='id'){
   if(!(item.content instanceof Y.ContentAny)||item.content.arr.length!==item.length)throw TypeError('Unsupported retained Slot identity register');
   if(item.content.arr.some(value=>slotIDs.has(value))){
    retain(item);let ancestor=item.parent;
    // A deleted ancestor can restore the old option even when the inverse
    // group's own selected range was its parent/container, not the option.
    while(ancestor instanceof Y.XmlElement&&ancestor._item?.deleted){retain(ancestor._item);ancestor=ancestor._item.parent;}
   }
  }
  if(item.parentSub==='settings'){
   if(!(item.content instanceof Y.ContentAny)||item.content.arr.length!==item.length)throw TypeError('Unsupported retained aggregate settings register');
   const sentinel=(videoMappings.length||slotInsertions!==null)&&item.content.arr.every(value=>value===true);
   if(!sentinel){for(const value of item.content.arr){object(value);validateJSONValue(value);if(videoParents.has(item.parent)&&rawVideo(value.video))unsupportedVideoParents.add(item.parent);}relevant=true;}
  }else if(videoMappings.length&&item.parentSub===settingsAttributeKey('video')&&videoParents.has(item.parent)){
   if(!(item.content instanceof Y.ContentAny)||item.content.arr.length!==item.length)throw TypeError('Unsupported retained Video register');
   for(const value of item.content.arr){validateJSONValue(value);if(value!=null&&(typeof value!=='object'||Array.isArray(value)))throw TypeError('Unsupported retained Video value');}
   relevant=item.content.arr.some(rawVideo);if(relevant)unsupportedVideoParents.add(item.parent);
  }
  if(relevant)retain(item);
 }
 // A type-only inverse can restore an unsupported original Video without
 // touching its video register. Keep mapped and already qualified identities.
 for(const parent of unsupportedVideoParents){
  if(plan.has(parent.getAttribute('relaymarkId')))continue;
  const settings=parent.getAttribute('settings'),video=settings===true?parent.getAttribute(settingsAttributeKey('video')):settings?.video;
  if(validUUID(video?.video_id))continue;
  for(const item of typeItems.get(parent)||[])retain(item);
 }
 // An unmapped row-only original has no independently certified option
 // definition to restore. Concrete current UUID options and mapped questions
 // retain their genuine type capabilities; domain rows still need host authority.
 const mappedSlotQuestions=new Set(slotPlan(slotInsertions).map(patch=>patch.question_relaymark_id));
 for(const parent of slotParents){
  if(mappedSlotQuestions.has(parent.getAttribute('relaymarkId')))continue;
  const options=parent.toArray().filter(node=>node instanceof Y.XmlElement&&node.nodeName==='questionOption');
  if(options.length&&options.every(option=>validUUID(option.getAttribute('id'))))continue;
  for(const item of typeItems.get(parent)||[])retain(item);
 }
 for(const ranges of registers.values())ranges.sort((a,b)=>a.clock-b.clock);
 let extents=0;
 const intersects=set=>{
  let found=false;for(const [client,ranges]of set.clients){const clocks=registers.get(client)||[];for(const range of ranges){if(++extents>1_000_000)throw TypeError('Finite settings stack extent limit');let left=0,right=clocks.length;while(left<right){const mid=(left+right)>>>1;if(clocks[mid].end<=range.clock)left=mid+1;else right=mid;}if(left<clocks.length&&clocks[left].clock<range.clock+range.len)found=true;}}
  return found;
 };
 const result=[];
 for(const [index,entry]of [...manager.undoStack,...manager.redoStack].entries()){
  const insertions=intersects(entry.insertions),deletions=intersects(entry.deletions);
  if(insertions||deletions)result.push(groups[index]);
 }
 return result;
}


// Package-internal correspondence derived from the verified finite writer only.
function activeRegister(node,key,value){
 const item=node._map.get(key);if(!item||item.deleted||!(item.content instanceof Y.ContentAny)||item.content.arr.length!==item.length||!same(item.content.arr.at(-1),value))throw TypeError('Unavailable active finite register');
 return {item:{client:item.id.client,clock:item.id.clock+item.length-1},count:1};
}
export function finiteSettingsDependencyRelations(original,destination,footprint,correspondence){
 const relations=[],freshByClient=new Map();let budget=1_000_000;
 for(const {item,count}of footprint.structs){const ranges=freshByClient.get(item.client)||[],previous=ranges.at(-1);if(previous&&previous.clock+previous.count===item.clock)previous.count+=count;else ranges.push({clock:item.clock,count});freshByClient.set(item.client,ranges);}
 const covered=range=>{const ranges=freshByClient.get(range.item.client)||[];let left=0,right=ranges.length;while(left<right){const mid=(left+right)>>>1;if(ranges[mid].clock<=range.item.clock)left=mid+1;else right=mid;}const part=ranges[left-1];if(!part||part.clock+part.count<range.item.clock+range.count)throw TypeError('Finite dependency target was not actually born');};
 const coalesce=ranges=>{const result=[];for(const range of ranges.sort((a,b)=>a.item.client-b.item.client||a.item.clock-b.item.clock)){const previous=result.at(-1);if(previous&&previous.item.client===range.item.client&&previous.item.clock+previous.count>=range.item.clock)previous.count=Math.max(previous.item.clock+previous.count,range.item.clock+range.count)-previous.item.clock;else result.push(clone(range));}return result;};
 const type=(doc,id)=>{const item=Y.getItem(doc.store,Y.createID(id.client,id.clock));if(!(item instanceof Y.Item)||item.deleted||!(item.content instanceof Y.ContentType)||!same({client:item.id.client,clock:item.id.clock},id))throw TypeError('Unavailable exact finite type');return item.content.type;};
 for(const entry of correspondence.attributes){
  const before=type(original,entry.node),after=type(destination,entry.node);if(!same(activeRegister(before,'settings',before.getAttribute('settings')),entry.source))throw TypeError('Finite aggregate source identity differs');
  const targets=entry.fields.map(({key,value})=>{if(--budget<0)throw TypeError('Finite correspondence limit');const target=activeRegister(after,key,value);covered(target);return target;});relations.push({kind:'finite_attribute',sources:[entry.source],destinations:coalesce(targets)});
 }
 const written=correspondence.writes.map(entry=>{if(--budget<0)throw TypeError('Finite correspondence limit');type(original,entry.node);const node=type(destination,entry.node),target=activeRegister(node,entry.key,entry.value);covered(target);return target;});
 const declared=new Set(correspondence.options.map(patch=>patch.option_relaymark_id));
 const questions=new Map(),options=new Map();
 const visit=(node,question=null,depth=0)=>{if(--budget<0||depth>64)throw TypeError('Finite correspondence limit');if(node instanceof Y.XmlText)return;if(node instanceof Y.XmlElement){if(node.nodeName==='questionBlock'){question=node;if(questions.has(node.getAttribute('relaymarkId')))throw TypeError('Ambiguous finite question');questions.set(node.getAttribute('relaymarkId'),node);}if(node.nodeName==='questionOption'){const key=node.getAttribute('relaymarkId');if(options.has(key))throw TypeError('Ambiguous finite option');options.set(key,{node,question});}}for(const child of node.toArray())visit(child,question,depth+1);};visit(destination.getXmlFragment('default'));
 const originalQuestions=new Map();const originals=node=>{if(--budget<0)throw TypeError('Finite correspondence limit');if(node instanceof Y.XmlText)return;if(node instanceof Y.XmlElement&&node.nodeName==='questionBlock')originalQuestions.set(node.getAttribute('relaymarkId'),node);for(const child of node.toArray())originals(child);};originals(original.getXmlFragment('default'));
 const born=new Map([...options.entries()].filter(([key])=>declared.has(key)).map(([, {node}])=>[node,[]])),ancestry=new Map();
 const optionAncestor=branch=>{if(ancestry.has(branch))return ancestry.get(branch);if(--budget<0)throw TypeError('Finite correspondence limit');const result=born.has(branch)?branch:branch?._item?optionAncestor(branch._item.parent):null;ancestry.set(branch,result);return result;};
 const fieldIntervals=coalesce(written),fieldClients=new Map();for(const range of fieldIntervals){const values=fieldClients.get(range.item.client)||[];values.push(range);fieldClients.set(range.item.client,values);}
 const fieldCovered=record=>{const values=fieldClients.get(record.item.client)||[];let low=0,high=values.length;while(low<high){const mid=(low+high)>>>1;if(values[mid].item.clock<=record.item.clock)low=mid+1;else high=mid;}const value=values[low-1];return value&&value.item.clock+value.count>=record.item.clock+record.count;};
 for(const record of footprint.structs){
  if(--budget<0)throw TypeError('Finite correspondence limit');const item=Y.getItem(destination.store,Y.createID(record.item.client,record.item.clock));
  let clock=record.item.clock,text='',values=[];while(clock<record.item.clock+record.count){
   if(--budget<0)throw TypeError('Finite correspondence limit');const stored=Y.getItem(destination.store,Y.createID(record.item.client,clock)),offset=clock-stored.id.clock,n=Math.min(record.item.clock+record.count-clock,stored.length-offset),parent=stored.parent?._item?{type:{client:stored.parent._item.id.client,clock:stored.parent._item.id.clock}}:{root:Y.findRootTypeKey(stored.parent)};
   if(offset<0||n<1||!same(record.parent,parent)||record.key!==(stored.parentSub??null))throw TypeError('Finite allocation interval identity differs');
   if(stored.content instanceof Y.ContentString){if(record.content.kind!=='string')throw TypeError('Finite text allocation kind differs');text+=stored.content.str.slice(offset,offset+n);}
   else if(stored.content instanceof Y.ContentAny){if(record.content.kind!=='any'||stored.content.arr.length!==stored.length)throw TypeError('Finite field allocation kind differs');values.push(...stored.content.arr.slice(offset,offset+n));}
   else {if(offset||n!==1||record.count!==1)throw TypeError('Unavailable fragmented finite allocation');if(stored.content instanceof Y.ContentType){const type=stored.content.type,kind=type instanceof Y.XmlElement?'xml_element':type instanceof Y.XmlText?'xml_text':null;if(record.content.kind!=='type'||record.content.type_kind!==kind||record.content.name!==(type instanceof Y.XmlElement?type.nodeName:null))throw TypeError('Finite type allocation differs');}else if(!(stored.content instanceof Y.ContentFormat)||record.content.kind!=='format'||record.content.key!==stored.content.key||!same(record.content.value,stored.content.value))throw TypeError('Unsupported finite allocation content');}
   clock+=n;
  }
  if(record.content.kind==='string'&&record.content.text!==text||record.content.kind==='any'&&!same(record.content.values,values))throw TypeError('Finite allocation content extent differs');
  const root=item.content instanceof Y.ContentType&&born.has(item.content.type)?item.content.type:optionAncestor(item.parent),field=fieldCovered(record);
  if(root&&field)throw TypeError('Overlapping finite allocation correspondence');
  if(root)born.get(root).push({item:record.item,count:record.count});else if(!field)throw TypeError('Unaccounted finite structural allocation');
 }
 for(const patch of correspondence.options){
  const source=originalQuestions.get(patch.question_relaymark_id),question=questions.get(patch.question_relaymark_id),target=options.get(patch.option_relaymark_id);if(!source||source.getAttribute('id')!==patch.question_id||!question||!target||target.question!==question||target.node.getAttribute('id')!==patch.option_id||!same({client:source._item.id.client,clock:source._item.id.clock},{client:question._item.id.client,clock:question._item.id.clock}))throw TypeError('Finite option source/destination identity mismatch');
  const root=target.node,allocations=born.get(root);
  covered({item:{client:root._item.id.client,clock:root._item.id.clock},count:1});if(!allocations.length)throw TypeError('Missing born finite option subtree');relations.push({kind:'finite_option',sources:[{item:{client:source._item.id.client,clock:source._item.id.clock},count:1}],destinations:coalesce(allocations)});
 }
 return relations;
}
