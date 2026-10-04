/** Pure maintained ProseMirror operation interpreter. The host supplies its
 * admitted pre-document and verifies CRDT anchors/copy authority independently.
 * No client pre-document, persistence, transport, or alternate editor lives here. */
import {Step} from 'prosemirror-transform';
import {createCanonicalEditorSchema} from './editor-model.js';
export {createCanonicalEditorSchema} from './editor-model.js';
import {proseMirrorToRelayMark,relayMarkToProseMirror} from './document-adapter.js';
import {stableStringify} from './canonical-json.js';
import {validateOwnedCommandGroup,validateOwnedHistory} from './owned-command-group.js';

const schema=createCanonicalEditorSchema();

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
 let retained_ranges=document.content.size?[{source_from:0,destination_from:0,length:document.content.size}]:[];
 for(const json of operation.steps){
  const step=Step.fromJSON(schema,json);
  // Never quietly drop unknown slice/mark/node/step attrs through upstream defaults.
  if(stableStringify(step.toJSON())!==stableStringify(json))throw new TypeError('Noncanonical content edit step');
  const result=step.apply(document);
  if(result.failed)throw new TypeError('Canonical content edit refused: '+result.failed);
  document=result.doc;
  const map=step.getMap();step_maps.push({ranges:[...map.ranges],inverted:map.inverted});
  const changed=[];map.forEach((from,to)=>changed.push([from,to]));
  const next=[];
  for(const range of retained_ranges){
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
 return {document:json,authored_document,step_maps,retained_ranges,inserted_ranges};
}

/** Same operation owner for a host-admitted portable AST. Authored envelope metadata
 * is retained by the one document owner; PM steps operate on its rich body. */
export function applyDocumentContentEdit(admittedDocument,operation,options) {
 const result=applyContentEdit(relayMarkToProseMirror(admittedDocument),operation,options);
 result.authored_document={...admittedDocument,blocks:result.authored_document.blocks};
 return result;
}

import {prepareWitness} from './content-edit-witness.js';
/** Prepare exact causal text/copy evidence; complete mutation/history admission is separately required. */
export function prepareContentEditWitness(evidence){return prepareWitness(evidence,applyContentEdit);}

import {buildWitness} from './content-edit-witness.js';
export function buildContentEditWitness(evidence){return buildWitness(evidence,applyContentEdit);}
export {replayContentEditMutation} from '../adapters/collaboration/content-edit-mutation.js';
