/** The maintained canonical editor model, shared by all portable projections. */
import {canonicalHTMLNodeRules,canonicalHTMLMarkRules} from './document-html-rules.js';
import {Schema} from 'prosemirror-model';
import {canonicalEditorSchema} from './editor-schema.js';
import {xmlAttributeEncodingPolicy} from './document-attribute-policy.js';
export function createCanonicalEditorSchema() {
 const nodes=Object.fromEntries(canonicalEditorSchema.nodes.map(({name,markSet,...spec})=>[
  name,{...spec,parseDOM:canonicalHTMLNodeRules(name),...(markSet===null?{}:{marks:markSet.join(' ')})}
 ]));
 nodes[canonicalEditorSchema.top].attributeCodecRequired=xmlAttributeEncodingPolicy.attribute_codec_required;
 const marks=Object.fromEntries(canonicalEditorSchema.marks.map(({name,excludes,...spec})=>[
  name,{...spec,parseDOM:canonicalHTMLMarkRules(name),excludes:excludes.join(' ')}
 ]));
 return new Schema({topNode:canonicalEditorSchema.top,nodes,marks});
}
