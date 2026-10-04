/** The maintained canonical editor model, shared by all portable projections. */
import {Schema} from 'prosemirror-model';
import {canonicalEditorSchema} from './editor-schema.js';
export function createCanonicalEditorSchema() {
 const nodes=Object.fromEntries(canonicalEditorSchema.nodes.map(({name,markSet,...spec})=>[
  name,{...spec,...(markSet===null?{}:{marks:markSet.join(' ')})}
 ]));
 const marks=Object.fromEntries(canonicalEditorSchema.marks.map(({name,excludes,...spec})=>[
  name,{...spec,excludes:excludes.join(' ')}
 ]));
 return new Schema({topNode:canonicalEditorSchema.top,nodes,marks});
}
