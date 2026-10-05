/** Reviewed AST targets execute through the canonical maintained command writer.
 * This plans editor Steps only; hosts retain authorization and conflict fencing. */
import {Transform,DocAttrStep,AttrStep} from 'prosemirror-transform';
import {Mark} from 'prosemirror-model';
import {createCanonicalEditorSchema} from './editor-model.js';
import {relayMarkToProseMirror} from './document-adapter.js';
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
export function produceDocumentPatch(input){
 const keys=['state_base64','writer_client','transaction_id','owner_id','target_document'];
 if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!keys.includes(k))||keys.some(k=>!Object.hasOwn(input,k)))throw TypeError('Invalid reviewed document patch');
 const before=schema.nodeFromJSON(readContentEditDocument(input.state_base64));
 const target=schema.nodeFromJSON(relayMarkToProseMirror(input.target_document));
 target.check();
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
 if(!transform.steps.length)throw TypeError('Reviewed document patch is unchanged');
 const {target_document,...command}=input;
 const result=produceContentEdit({...command,steps:transform.steps.map(step=>step.toJSON())});
 if(stableStringify(result.authored_document)!==stableStringify(target_document))throw TypeError('Maintained command differs from reviewed target');
 return result;
}
