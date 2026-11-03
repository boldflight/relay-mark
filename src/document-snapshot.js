/** Canonical portable XML projection. Source, native and causal proof consume this owner. */
import {relayMarkToProseMirror,proseMirrorToRelayMark} from './document-adapter.js';
import {cloneCanonicalJSON as cloneJSON} from './canonical-json.js';
import {textMarkNames as marksOrder} from './document-inline.js';
import {createCanonicalEditorSchema} from './editor-model.js';
import {linkDefaults} from './document-links.js';
import {canonicalAttributeCodec} from './document-attributes.js';
const schema=createCanonicalEditorSchema();
const metadataKeys=['frontmatter','annotations','resources','meta'];
// The empty document is valid although ProseMirror's `doc` wants a block: an empty fragment is exactly
// how y-prosemirror stores one, and the empty paragraph exists only in an editor's view. Every other
// node, and every non-empty doc, is checked against the schema as before (same rule as the Rust engine).
function checkedNode(pm){const node=schema.nodeFromJSON(pm);if(node.type.name!=='doc'||node.childCount)node.check();return node;}
export function documentToSnapshot(ast){ast=normalizeDocument(ast);return proseMirrorToSnapshot(relayMarkToProseMirror(ast),ast);}
/** The finite importer supplies an already schema-checked PM tree; identity repair
 * remains solely importDocumentSnapshot's responsibility. */
export function proseMirrorToSnapshot(pm,ast={}){
 function children(nodes){const result=[];for(const n of nodes){const next=node(n),last=result.at(-1);if(next.kind==='text'&&last?.kind==='text')last.delta.push(...next.delta);else result.push(next)}return result;}
 function node(n){if(n.type==='text')return {kind:'text',delta:[{insert:n.text,attributes:Object.fromEntries((n.marks||[]).map(m=>[m.type,m.attrs||{}]))}]};return {kind:'element',name:n.type,attributes:canonicalAttributeCodec.encode(n.type,Object.fromEntries(Object.entries(n.attrs||{}).filter(([key,value])=>key!=='relaymarkId'||value!==null))),children:children(n.content||[])};}
 const metadata=Object.fromEntries(metadataKeys.filter(k=>Object.hasOwn(ast,k)).map(k=>[k,cloneJSON(ast[k])]));return {kind:'fragment',children:pm.content.map(node),...(Object.keys(metadata).length?{metadata}: {})};
}
// The ordinary API remains document-only; the paired result is call-local to
// this same strict decoder and carries its final validated PM projection.
export function snapshotToDocument(snapshot){return snapshotToDocumentWithProseMirror(snapshot).document;}
export function snapshotToDocumentWithProseMirror(snapshot){
 const only=(value,keys)=>{if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!keys.includes(k)))throw new TypeError('Invalid portable snapshot shape');};
 only(snapshot,['kind','children','metadata']);if(snapshot.kind!=='fragment'||!Array.isArray(snapshot.children))throw new TypeError('Invalid portable fragment');
 function nodes(children,depth=0){if(depth>64||!Array.isArray(children))throw new TypeError('Invalid portable children');return children.flatMap(n=>{if(n.kind==='text'){only(n,['kind','delta']);if(!Array.isArray(n.delta))throw new TypeError('Invalid text delta');return n.delta.map(run=>{only(run,['insert','attributes']);if(typeof run.insert!=='string'||!run.insert)throw new TypeError('Invalid text insert');const attributes=run.attributes||{};only(attributes,['link','bold','code','italic','strike','underline','highlight','superscript','subscript','ai_authored']);const marks=Object.entries(attributes).map(([type,attrs])=>{only(attrs,type==='link'?['href','target','rel','class','title']:type==='ai_authored'?['run_id']:[]);return type==='link'?{type,attrs:{...linkDefaults,...attrs}}:type==='ai_authored'?{type,attrs}:{type};}).sort((a,b)=>marksOrder.indexOf(a.type)-marksOrder.indexOf(b.type));return {type:'text',text:run.insert,...(marks.length?{marks}: {})};});}
 only(n,['kind','name','attributes','children']);if(n.kind!=='element'||typeof n.name!=='string')throw new TypeError('Invalid portable element');only(n.attributes,Object.keys(n.attributes||{}));const content=nodes(n.children,depth+1),attributes={...({heading:{headingId:null},orderedList:{start:1,type:null},taskItem:{checked:false,entityId:null},codeBlock:{language:null},tableCell:{colspan:1,rowspan:1,colwidth:null,align:null},tableHeader:{colspan:1,rowspan:1,colwidth:null,align:null},image:{alt:null,title:null},callout:{tone:'neutral',emphasis:'soft'},agentSuggestion:{confidence:null},questionBlock:{required:false,points:null,min:null,max:null,settings:{}},questionOption:{correct:false,points:null,settings:{}}}[n.name]||{}),...canonicalAttributeCodec.decode(n.name,n.attributes)};return [{type:n.name,...(Object.keys(attributes).length?{attrs:attributes}:{}),...(content.length?{content}: {})}];});}
 const pm={type:'doc',content:nodes(snapshot.children)};proseMirrorToRelayMark(pm);
 const normalized=checkedNode(pm);const document=proseMirrorToRelayMark(JSON.parse(JSON.stringify(normalized.toJSON())));if(Object.hasOwn(snapshot,'metadata')){only(snapshot.metadata,metadataKeys);Object.assign(document,cloneJSON(snapshot.metadata));}return {document,prosemirror:relayMarkToProseMirror(document)};
}

/** Canonical semantic AST normalization: text segmentation has no authored ID.
 * Block/option identities, marks, atom boundaries and envelope values remain exact. */
export function normalizeDocument(document){
 const pm=relayMarkToProseMirror(document),normalized=checkedNode(pm);
 return {...document,blocks:proseMirrorToRelayMark(JSON.parse(JSON.stringify(normalized.toJSON()))).blocks};
}
