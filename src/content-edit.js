/** Pure maintained ProseMirror operation interpreter. The host supplies its
 * admitted pre-document and verifies CRDT anchors/copy authority independently.
 * No client pre-document, persistence, transport, or alternate editor lives here. */
import {Step} from 'prosemirror-transform';
import {createCanonicalEditorSchema} from './editor-model.js';
export {createCanonicalEditorSchema} from './editor-model.js';
import {proseMirrorToRelayMark,relayMarkToProseMirror,assertAuthoredMetadata} from './document-adapter.js';
import {stableStringify} from './canonical-json.js';
import {validateOwnedCommandGroup,validateOwnedHistory} from './owned-command-group.js';

import {EditorState,Selection} from 'prosemirror-state';
import {newlineInCode,createParagraphNear,liftEmptyBlock,splitBlockKeepMarks} from 'prosemirror-commands';
import {splitListItemKeepMarks,sinkListItem,liftListItem} from 'prosemirror-schema-list';
import * as tableCommands from 'prosemirror-tables';

const schema=createCanonicalEditorSchema();

/** Actual maintained command execution over the admitted canonical PM tree.
 * Native uses these exact steps with its existing PM/Yrs writer. No CRDT replica,
 * original-state replacement, identity allocation or transport authority lives here.
 * IDs created/copied by the command are repaired once by that same writer owner.
 */
export function createContentEditCommand(admittedDocument,request) {
 if(!request||Object.keys(request).some(key=>!['command','selection'].includes(key))||typeof request.command!=='string'||!request.selection||
    JSON.stringify(request).length>524288)throw TypeError('Invalid canonical editor command');
 proseMirrorToRelayMark(admittedDocument);
 const document=schema.nodeFromJSON(admittedDocument);document.check();
 const selection=Selection.fromJSON(document,request.selection);
 if(stableStringify(selection.toJSON())!==stableStringify(request.selection))throw TypeError('Noncanonical editor selection');
 const state=EditorState.create({schema,doc:document,selection});
 let transaction,kind='edit';const dispatch=tr=>{if(transaction)throw TypeError('Multiple command transactions');transaction=tr;};
 const cursor=selection.$from;
 const item=cursor.depth>=2?cursor.node(-1):null;
 const listItem=item&&['listItem','taskItem'].includes(item.type.name)?item.type:null;
 let accepted=false;
 if(request.command==='return'){
  if(listItem){
   // An authored linked-task relationship is domain truth. A whole-item lift
   // cannot silently discard it; nested lifting retains the same task item.
   if(cursor.parent.content.size===0&&item.childCount===1&&item.attrs.entityId&&
      (cursor.depth<4||cursor.node(-3).type!==listItem))throw TypeError('Canonical editor command refused: linked task lift');
   accepted=splitListItemKeepMarks(listItem,listItem.name==='taskItem'?{checked:false,entityId:null}:undefined)(state,dispatch);
   if(accepted)kind=cursor.parent.content.size===0?'exit':'split';
  }
  if(!accepted){
   for(const [command,resultKind] of [[newlineInCode,'split'],[createParagraphNear,'split'],[liftEmptyBlock,'exit'],[splitBlockKeepMarks,'split']]){
    if(command(state,dispatch)){accepted=true;kind=resultKind;break;}
   }
  }
 }else if(request.command==='sink_list_item'||request.command==='lift_list_item'){
  if(listItem){
   if(request.command==='lift_list_item'&&item.attrs.entityId&&
      (cursor.depth<4||cursor.node(-3).type!==listItem))throw TypeError('Canonical editor command refused: linked task lift');
   accepted=(request.command==='sink_list_item'?sinkListItem:liftListItem)(listItem)(state,dispatch);
  }
 }else{
  const allowed=new Set(['addRowBefore','addRowAfter','deleteRow','addColumnBefore','addColumnAfter','deleteColumn','mergeCells','splitCell','toggleHeaderRow','toggleHeaderColumn','toggleHeaderCell','deleteTable']);
  if(!allowed.has(request.command))throw TypeError('Unknown canonical editor command');
  const command=request.command==='toggleHeaderRow'?tableCommands.toggleHeader('row'):request.command==='toggleHeaderColumn'?tableCommands.toggleHeader('column'):tableCommands[request.command];
  accepted=command(state,dispatch);
 }
 if(!accepted||!transaction||!transaction.docChanged||transaction.steps.length>512)throw TypeError('Canonical editor command refused');
 if(request.command==='return'&&listItem?.name==='taskItem'&&kind==='split'){
  const selected=transaction.selection.$from;
  if(selected.depth>=2&&selected.node(-1).type===listItem){
   const pos=selected.before(selected.depth-1),original=cursor.before(cursor.depth-1);
   if(pos!==transaction.mapping.map(original,-1)){
    // TipTap task attributes have keepOnSplit:false. schema-list only uses
    // itemAttrs at the end of an item, so apply the same declared defaults to
    // the actual newly split item with maintained attribute steps in this command.
    for(const key of ['checked','entityId'])if(selected.node(-1).attrs[key]!==listItem.defaultAttrs[key])transaction.setNodeAttribute(pos,key,listItem.defaultAttrs[key]);
   }
  }
 }

 if(kind==='edit'&&request.command!=='sink_list_item'&&request.command!=='lift_list_item'){
  const initialFix=tableCommands.fixTables(state.apply(transaction),state);
  if(initialFix)for(const step of initialFix.steps)transaction.step(step);
  for(let pass=0;pass<256&&removeCoveredContentEditTableRow(transaction);pass++){if(pass===255)throw TypeError('Oversized covered-row normalization');}
  const finalFix=tableCommands.fixTables(state.apply(transaction),state);
  if(finalFix)for(const step of finalFix.steps)transaction.step(step);
 }
 transaction.doc.check();
 const retained_ids={};document.descendants((node,pos)=>{const id=node.attrs.relaymarkId;if(!id)return;const mapped=transaction.mapping.mapResult(pos);if(!mapped.deleted&&transaction.doc.nodeAt(mapped.pos)?.attrs.relaymarkId===id)retained_ids[id]=mapped.pos;});
 return {kind,retained_ids,steps:transaction.steps.map(step=>step.toJSON()),document:transaction.doc.toJSON(),selection:transaction.selection.toJSON(),
  stored_marks:transaction.storedMarks?.map(mark=>mark.toJSON())??null,
  stored_text_attributes:transaction.storedMarks?JSON.parse(JSON.stringify(Object.fromEntries(transaction.storedMarks.map(mark=>[mark.type.name,mark.attrs])))):null};
}

/** Canonical table rows require a physical cell. Maintained table commands
 * can cover an empty row entirely by earlier rowspans. The same authored
 * normalization shortens those spans and removes the covered row with actual
 * PM Steps. No received CRDT update is ever rewritten by this command helper.
 */
export function removeCoveredContentEditTableRow(transaction){
 let changed=false;transaction.doc.descendants((table,tablePos)=>{
  if(changed)return false;if(table.type.spec.tableRole!=='table')return true;
  const map=tableCommands.TableMap.get(table);let rowStart=0;
  for(let row=0;row<table.childCount;row++){
   const node=table.child(row);
   if(node.childCount===0&&row>0&&row<map.height){
    const covering=new Set();for(let col=0;col<map.width;col++)covering.add(map.map[row*map.width+col]);
    if([...covering].every(pos=>pos<rowStart)){
     for(const pos of covering){const cell=table.nodeAt(pos);transaction.setNodeMarkup(tablePos+1+pos,null,{...cell.attrs,rowspan:cell.attrs.rowspan-1});}
     transaction.delete(tablePos+1+rowStart,tablePos+1+rowStart+node.nodeSize);changed=true;return false;
    }
   }
   rowStart+=node.nodeSize;
  }
  return true;
 });return changed;
}

export function applyContentEdit(admittedDocument,operation,{maximumSteps=512}={}) {
 if(!operation||operation.kind!=='content_edit'||!Array.isArray(operation.steps)||
    !Number.isSafeInteger(maximumSteps)||maximumSteps<1||maximumSteps>4096||
    operation.steps.length<1||operation.steps.length>maximumSteps)
  throw new TypeError('Invalid or oversized canonical content edit');
 if(operation.group&&operation.history)throw TypeError('Command group and inverse history are exclusive');
 if(operation.group)validateOwnedCommandGroup(operation.group);if(operation.history)validateOwnedHistory(operation.history);
 // Validate original attributes before maintained Node.fromJSON can fill defaults.
 proseMirrorToRelayMark(admittedDocument);
 let document=schema.nodeFromJSON(admittedDocument);document.check();
 const step_maps=[];
 // Identity preparation uses only actual maintained maps. Equal replacement
 // text is not retained source; structural gap/suffix text maps through unchanged.
 const originalIdentities=new Map();document.descendants((node,position)=>{const id=node.attrs.relaymarkId;if(!id)return;if(originalIdentities.has(id))throw TypeError('Ambiguous retained subtree identity');originalIdentities.set(id,{node,position});});
 let copied_subtree_ranges=[];
 let retained_ranges=document.content.size?[{source_from:0,destination_from:0,length:document.content.size}]:[];
 for(const json of operation.steps){
  if(json.stepType==='docAttr'){if(json.attr!=='relaymark')throw TypeError('Unknown canonical document attribute');assertAuthoredMetadata(json.value);}
  const step=Step.fromJSON(schema,json);
  // Never quietly drop unknown slice/mark/node/step attrs through upstream defaults.
  if(stableStringify(step.toJSON())!==stableStringify(json))throw new TypeError('Noncanonical content edit step');
  const result=step.apply(document);
  if(result.failed)throw new TypeError('Canonical content edit refused: '+result.failed);
  document=result.doc;
  const map=step.getMap();step_maps.push({ranges:[...map.ranges],inverted:map.inverted});
  const changed=[];map.forEach((from,to)=>changed.push([from,to]));
  const mapRanges=ranges=>{const next=[];
  for(const range of ranges){
   const start=range.destination_from,end=start+range.length;
   const boundaries=[start,end,...changed.flatMap(([from,to])=>[from,to]).filter(p=>p>start&&p<end)].sort((a,b)=>a-b);
   for(let i=1;i<boundaries.length;i++){
    const from=boundaries[i-1],to=boundaries[i];if(from===to||changed.some(([a,b])=>a<b&&from>=a&&to<=b))continue;
    const destination=map.map(from,1),upper=map.map(to,-1);
    if(upper-destination!==to-from)throw new TypeError('Unprovable maintained map interval');
    const source=range.source_from+from-start,last=next.at(-1);
    if(last&&last.source_from+last.length===source&&last.destination_from+last.length===destination)last.length+=to-from;
    else next.push({source_from:source,destination_from:destination,length:to-from});
    if(next.length>65536)throw new TypeError('Content edit causal mapping budget exceeded');
   }
  }
  return next;};
  copied_subtree_ranges=mapRanges(copied_subtree_ranges);
  // A preserved authored identity is a source pointer only for its complete
  // exact original subtree. The actual Slice and applied destination must both
  // match. Equal text or partially matching content never establishes ancestry.
  const candidates=[];
  if(json.stepType==='replace'&&step.slice){
   step.slice.content.descendants((node,pos)=>{
    const id=node.attrs.relaymarkId,original=id&&originalIdentities.get(id);
    if(!original||!node.eq(original.node))return;
    const destination=step.from+pos-step.slice.openStart;
    if(destination<0||!document.nodeAt(destination)?.eq(node))return;
    if(candidates.some(range=>destination>=range.destination_from&&destination+node.nodeSize<=range.destination_from+range.length))return false;
    candidates.push({source_from:original.position,destination_from:destination,length:node.nodeSize});return false;
   });
  }
  copied_subtree_ranges.push(...candidates);
  if(copied_subtree_ranges.length>65536)throw TypeError('Copied subtree mapping budget exceeded');
  const next=mapRanges(retained_ranges);
  retained_ranges=next;
 }
 document.check();
 const json=JSON.parse(JSON.stringify(document.toJSON()));
 // Closed final ancestry/identities/media/forms use the one portable grammar.
 // Intermediate open Slices are validated in their actual maintained context.
 const authored_document=proseMirrorToRelayMark(json);
 const inserted_ranges=[];let cursor=0;
 for(const range of retained_ranges.slice().sort((a,b)=>a.destination_from-b.destination_from)){if(range.destination_from>cursor)inserted_ranges.push({destination_from:cursor,length:range.destination_from-cursor});cursor=Math.max(cursor,range.destination_from+range.length)}
 if(cursor<document.content.size)inserted_ranges.push({destination_from:cursor,length:document.content.size-cursor});
 return {document:json,authored_document,step_maps,retained_ranges,inserted_ranges,copied_subtree_ranges};
}

/** Same operation owner for a host-admitted portable AST. Authored envelope metadata
 * is retained by the one document owner; PM steps operate on its rich body. */
export function applyDocumentContentEdit(admittedDocument,operation,options) {
 const result=applyContentEdit(relayMarkToProseMirror(admittedDocument),operation,options);
 // The one doc attribute carries exact metadata, including removals.
 // Reapplying old envelope keys would silently undo a DocAttrStep.
 return result;
}

import {prepareWitness} from './content-edit-witness.js';
/** Prepare exact causal text/copy evidence; complete mutation/history admission is separately required. */
export function prepareContentEditWitness(evidence){return prepareWitness(evidence,applyContentEdit);}

import {buildWitness} from './content-edit-witness.js';
export function buildContentEditWitness(evidence){return buildWitness(evidence,applyContentEdit);}
export {replayContentEditMutation} from '../adapters/collaboration/content-edit-mutation.js';

import {buildOwnedHistoryWitness as buildObservedHistory} from './content-edit-witness.js';
/** Preliminary immediate inverse observation; authoritative owned receipt replay remains required. */
export function buildOwnedHistoryWitness(evidence){return buildObservedHistory(evidence,applyContentEdit);}

export {classifyContentEditReference,foldSourceReferences} from './document-source-identities.js';

export {resolveContentEditTextItems} from './content-edit-witness.js';

import {contentEditTextGroups,planContentEditTextWrite} from './content-edit-write.js';
export {planContentEditTextWrite} from './content-edit-write.js';
/** In-process causal writer evidence, never a transport claim or authority. */
export function prepareContentEditWrite(before,steps,after){
 const expected=applyContentEdit(before,{kind:'content_edit',steps});
 if(stableStringify(expected.document)!==stableStringify(after))throw TypeError('Causal writer result disagrees with actual steps');
 const groups=document=>Object.fromEntries(contentEditTextGroups(schema.nodeFromJSON(document)).map(group=>[group.parent+':'+group.index,group]));
 const prepared={retained_ranges:expected.retained_ranges,before_groups:groups(before),after_groups:groups(after)};
 const causal_targets=[];
 for(const target of Object.values(prepared.after_groups)){
  const source=prepared.before_groups[target.parent+':'+target.index];
  let retained=false;
  if(source&&source.text.length===target.text.length){
   if(!source.text.length)retained=true;
   else{
    let lower=0,upper=prepared.retained_ranges.length;
    while(lower<upper){const middle=(lower+upper)>>>1,range=prepared.retained_ranges[middle];if(range.source_from+range.length<=source.position)lower=middle+1;else upper=middle;}
    const range=prepared.retained_ranges[lower];
    retained=!!range&&range.source_from<=source.position&&range.source_from+range.length>=source.position+source.text.length&&range.destination_from+source.position-range.source_from===target.position;
   }
  }
  if(!retained)causal_targets.push(target.parent);
 }
 return {...prepared,causal_targets:[...new Set(causal_targets)]};
}

/** Callback for the maintained binding, also used by exact headless replay. */
export function createContentEditWrite(before,steps,after){
 const prepared=prepareContentEditWrite(before.toJSON(),steps,after.toJSON());
 const targets=new Set(prepared.causal_targets),needed=new WeakMap();
 function visit(node){let changed=targets.has(node.attrs.relaymarkId);node.forEach(child=>{if(visit(child))changed=true});needed.set(node,changed);return changed}
 visit(after);
 return {requiresWrite:node=>needed.get(node)===true,planText:(sourceParent,sourceGroup,targetParent,targetGroup,sourceSpan)=>planContentEditTextWrite(prepared,sourceParent,sourceGroup,targetParent,targetGroup,sourceSpan)};
}
