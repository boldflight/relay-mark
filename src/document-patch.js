/** Reviewed AST targets execute through the canonical maintained command writer.
 * This plans editor Steps only; hosts retain authorization and conflict fencing. */
import {Transform,DocAttrStep,AttrStep} from 'prosemirror-transform';
import {Mark,Slice} from 'prosemirror-model';
import {createCanonicalEditorSchema} from './editor-model.js';
import {relayMarkToProseMirror,proseMirrorToRelayMark} from './document-adapter.js';
import {stableStringify} from './canonical-json.js';
import {readContentEditDocument,produceContentEdit} from '../adapters/collaboration/content-edit-mutation.js';
const schema=createCanonicalEditorSchema();
// Attribute-only edits have unchanged maintained node positions. Plan all
// changes before applying any Step; actual content/mark/topology changes use
// the existing Fragment diff below. No text-value matching establishes lineage.
function attributeSteps(before,target){
 const original=[],desired=[];
 before.descendants((node,pos)=>{original.push({node,pos});});
 target.descendants((node,pos)=>{desired.push({node,pos});});
 if(original.length!==desired.length)return null;
 const steps=[];
 for(let index=0;index<original.length;index++){
  const {node,pos}=original[index],next=desired[index];
  if(pos!==next.pos||node.type!==next.node.type||node.childCount!==next.node.childCount||node.text!==next.node.text||node.attrs.relaymarkId!==next.node.attrs.relaymarkId||!Mark.sameSet(node.marks,next.node.marks))return null;
  for(const attr of Object.keys(next.node.attrs))if(stableStringify(node.attrs[attr])!==stableStringify(next.node.attrs[attr]))steps.push(new AttrStep(pos,attr,next.node.attrs[attr]));
 }
 return steps;
}
/** Derives semantic Steps only after a maintained owner has selected exact
 * before/after PM trees. This does not create or establish mutation authority. */
export function planDocumentDifference(before,target){
 const transform=new Transform(before),attributes=attributeSteps(before,target);
 if(attributes!==null){for(const step of attributes)transform.step(step);}
 else{
 const start=before.content.findDiffStart(target.content);
 if(start!==null){
  const end=before.content.findDiffEnd(target.content);
  let fromEnd=end.a,toEnd=end.b;
  const overlap=start-Math.min(fromEnd,toEnd);
  if(overlap>0){fromEnd+=overlap;toEnd+=overlap;}
  transform.replace(start,fromEnd,target.slice(start,toEnd));
 }
 }
 if(stableStringify(before.attrs.relaymark)!==stableStringify(target.attrs.relaymark))transform.step(new DocAttrStep('relaymark',target.attrs.relaymark));
 if(!transform.doc.eq(target))throw TypeError('Reviewed target cannot be represented losslessly');
 return transform;
}
export function produceDocumentPatch(input){
 const keys=['state_base64','writer_client','transaction_id','owner_id','target_document'];
 if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!keys.includes(k))||keys.some(k=>!Object.hasOwn(input,k)))throw TypeError('Invalid reviewed document patch');
 const before=schema.nodeFromJSON(readContentEditDocument(input.state_base64));
 const target=schema.nodeFromJSON(relayMarkToProseMirror(input.target_document));
 target.check();
 const transform=planDocumentDifference(before,target);
 if(!transform.steps.length)throw TypeError('Reviewed document patch is unchanged');
 const {target_document,...command}=input;
 const result=produceContentEdit({...command,steps:transform.steps.map(step=>step.toJSON())});
 if(stableStringify(result.authored_document)!==stableStringify(target_document))throw TypeError('Maintained command differs from reviewed target');
 return result;
}

/** Exact authored-text review only. Marks are transparent, textblocks use one
 * newline boundary and atoms are opaque. Matching grants no source lineage. */
export function prepareDocumentTextReplacement(input){
 const keys=['document','target_text','replacement_document'];
 if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(key=>!keys.includes(key))||keys.some(key=>!Object.hasOwn(input,key)))throw TypeError('Invalid text replacement review');
 const target=input.target_text;
 if(typeof target!=='string'||!target.length||target.length>1000000)return {error:'invalid_patch'};
 const before=schema.nodeFromJSON(relayMarkToProseMirror(input.document));before.check();
 const replacement=schema.nodeFromJSON(relayMarkToProseMirror(input.replacement_document));replacement.check();
 // A segment never crosses an atomic node. Each run carries maintained UTF16
 // positions so surrogate pairs/mark boundaries need no host offset inference.
 const segments=[];let text='',runs=[],previousBlock=null;
 const flush=()=>{if(text)segments.push({text,runs});text='';runs=[];previousBlock=null;};
 before.descendants((node,pos)=>{
  if(node.isTextblock){
   if(previousBlock!==null){runs.push({from:text.length,to:text.length+1,pos:previousBlock,endPos:pos+1,separator:true});text+='\n';}
   node.forEach((child,offset)=>{
    if(child.isText){runs.push({from:text.length,to:text.length+child.text.length,pos:pos+1+offset});text+=child.text;}
    else{flush();}
   });
   previousBlock=pos+1+node.content.size;
   return false;
  }
  if(node.isAtom){flush();return false;}
  return true;
 });flush();
 let match;
 for(const segment of segments){
  let start=segment.text.indexOf(target);
  while(start>=0){
   if(match)return {error:'patch_target_ambiguous'};
   match={segment,start,end:start+target.length};
   start=segment.text.indexOf(target,start+1);
  }
 }
 if(!match)return {error:'patch_target_not_found'};
 const {segment,start,end}=match;
 const split=offset=>offset>0&&offset<segment.text.length&&/[\uD800-\uDBFF]/.test(segment.text[offset-1])&&/[\uDC00-\uDFFF]/.test(segment.text[offset]);
 if(split(start)||split(end))return {error:'invalid_patch'};
 const position=(offset,endPoint)=>{
  const run=segment.runs.find(run=>endPoint?offset>run.from&&offset<=run.to:offset>=run.from&&offset<run.to);
  if(run)return run.separator?(offset===run.from?run.pos:run.endPos):run.pos+offset-run.from;
  // A selected separator maps to the prior textblock end / next textblock start.
  const adjacent=endPoint?segment.runs.find(run=>run.from===offset):segment.runs.find(run=>run.to===offset);
  if(adjacent)return adjacent.pos+(endPoint?0:adjacent.to-adjacent.from);
  throw TypeError('Unavailable authored text boundary');
 };
 const fragment=replacement.content;
 const slice=new Slice(fragment,fragment.firstChild?.isTextblock?1:0,fragment.lastChild?.isTextblock?1:0);
 const transform=new Transform(before).replaceRange(position(start,false),position(end,true),slice);
 transform.doc.check();
 const target_document=proseMirrorToRelayMark(transform.doc.toJSON());
 return {target_document,steps:transform.steps.map(step=>step.toJSON())};
}
