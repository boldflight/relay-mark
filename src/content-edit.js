/** Native editing runtime: canonical HTML and clipboard import, the logical
 * and physical attribute codec, maintained ProseMirror commands, clipboard
 * navigation plans, and the causal ProseMirror-to-Yjs text write plan. The
 * host supplies its admitted pre-document; no persistence, transport or
 * authority lives here. */
export {importDocumentHTML,importClipboardHTML} from './document-html.js';
import {Step} from 'prosemirror-transform';
import {createCanonicalEditorSchema} from './editor-model.js';
import {canonicalAttributeCodec} from './document-attributes.js';
/** Stateless adapters for native PM/XML bridges; the canonical codec owns policy. */
export function encodeDocumentAttributes(name,attributes){return canonicalAttributeCodec.encode(name,attributes);}
export function decodeDocumentAttributes(name,attributes){return canonicalAttributeCodec.decode(name,attributes);}
import {proseMirrorToRelayMark,assertAuthoredMetadata} from './document-adapter.js';
import {stableStringify} from './canonical-json.js';

import {EditorState,Selection} from 'prosemirror-state';
import {newlineInCode,createParagraphNear,liftEmptyBlock,splitBlockKeepMarks} from 'prosemirror-commands';
import {splitListItemKeepMarks,sinkListItem,liftListItem} from 'prosemirror-schema-list';
import * as tableCommands from 'prosemirror-tables';
import {removeCoveredContentEditTableRow} from './editor-table.js';
import {contentEditWritePlan} from './content-edit-write.js';
export {planContentEditTextWrite} from './content-edit-write.js';
export {planClipboardAnchorAllocation,planClipboardHeadingNavigation} from './clipboard-navigation.js';

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


export function applyContentEdit(admittedDocument,operation,{maximumSteps=512}={}) {
 if(!operation||operation.kind!=='content_edit'||!Array.isArray(operation.steps)||
    !Number.isSafeInteger(maximumSteps)||maximumSteps<1||maximumSteps>4096||
    operation.steps.length<1||operation.steps.length>maximumSteps)
  throw new TypeError('Invalid or oversized canonical content edit');
 if('group' in operation||'history' in operation)throw TypeError('Unsupported content edit envelope');
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

/** The causal writer's plan: the steps' actual result must equal `after`. */
export function prepareContentEditWrite(before,steps,after){
 const expected=applyContentEdit(before,{kind:'content_edit',steps});
 if(stableStringify(expected.document)!==stableStringify(after))throw TypeError('Causal writer result disagrees with actual steps');
 return contentEditWritePlan(schema.nodeFromJSON(before),schema.nodeFromJSON(after),expected.retained_ranges);
}
