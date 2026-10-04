/** Pure maintained ProseMirror operation interpreter. The host supplies its
 * admitted pre-document and verifies CRDT anchors/copy authority independently.
 * No client pre-document, persistence, transport, or alternate editor lives here. */
import {Schema} from 'prosemirror-model';
import {Step} from 'prosemirror-transform';
import {canonicalEditorSchema} from './editor-schema.js';
import {proseMirrorToRelayMark,relayMarkToProseMirror} from './document-adapter.js';
import {stableStringify} from './canonical-json.js';

export function createCanonicalEditorSchema() {
 const nodes=Object.fromEntries(canonicalEditorSchema.nodes.map(({name,markSet,...spec})=>[
  name,{...spec,...(markSet===null?{}:{marks:markSet.join(' ')})}
 ]));
 const marks=Object.fromEntries(canonicalEditorSchema.marks.map(({name,excludes,...spec})=>[
  name,{...spec,excludes:excludes.join(' ')}
 ]));
 return new Schema({topNode:canonicalEditorSchema.top,nodes,marks});
}
const schema=createCanonicalEditorSchema();

export function applyContentEdit(admittedDocument,operation,{maximumSteps=512}={}) {
 if(!operation||operation.kind!=='content_edit'||!Array.isArray(operation.steps)||
    !Number.isSafeInteger(maximumSteps)||maximumSteps<1||maximumSteps>4096||
    operation.steps.length<1||operation.steps.length>maximumSteps)
  throw new TypeError('Invalid or oversized canonical content edit');
 // Validate original attributes before maintained Node.fromJSON can fill defaults.
 proseMirrorToRelayMark(admittedDocument);
 let document=schema.nodeFromJSON(admittedDocument);document.check();
 const step_maps=[];
 for(const json of operation.steps){
  const step=Step.fromJSON(schema,json);
  // Never quietly drop unknown slice/mark/node/step attrs through upstream defaults.
  if(stableStringify(step.toJSON())!==stableStringify(json))throw new TypeError('Noncanonical content edit step');
  const result=step.apply(document);
  if(result.failed)throw new TypeError('Canonical content edit refused: '+result.failed);
  document=result.doc;
  const map=step.getMap();step_maps.push({ranges:[...map.ranges],inverted:map.inverted});
 }
 document.check();
 const json=JSON.parse(JSON.stringify(document.toJSON()));
 // Closed final ancestry/identities/media/forms use the one portable grammar.
 // Intermediate open Slices are validated in their actual maintained context.
 const authored_document=proseMirrorToRelayMark(json);
 return {document:json,authored_document,step_maps};
}

/** Same operation owner for a host-admitted portable AST. Authored envelope metadata
 * is retained by the one document owner; PM steps operate on its rich body. */
export function applyDocumentContentEdit(admittedDocument,operation,options) {
 const result=applyContentEdit(relayMarkToProseMirror(admittedDocument),operation,options);
 result.authored_document={...admittedDocument,blocks:result.authored_document.blocks};
 return result;
}
