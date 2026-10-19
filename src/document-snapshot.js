/** Canonical portable XML projection. Source, native and causal proof consume this owner. */
import {relayMarkToProseMirror,proseMirrorToRelayMark} from './document-adapter.js';
import {cloneCanonicalJSON as cloneJSON} from './canonical-json.js';
import {textMarkNames as marksOrder} from './document-inline.js';
import {createCanonicalEditorSchema} from './editor-model.js';
import {linkDefaults} from './document-links.js';
import {canonicalAttributeCodec} from './document-attributes.js';
import {xmlAttributeEncodingPolicy as policy} from './document-attribute-policy.js';
const schema=createCanonicalEditorSchema();
const metadataKeys=['frontmatter','annotations','resources','meta'];
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
 const normalized=schema.nodeFromJSON(pm);normalized.check();const document=proseMirrorToRelayMark(JSON.parse(JSON.stringify(normalized.toJSON())));if(Object.hasOwn(snapshot,'metadata')){only(snapshot.metadata,metadataKeys);Object.assign(document,cloneJSON(snapshot.metadata));}return {document,prosemirror:relayMarkToProseMirror(document)};
}

/** Detached finite original-input preview only. Original bytes, node identities
 * and source facts are never adopted into the current editor by this operation.
 * Missing-hash archives may already have canonical fieldwise settings; their
 * detached preview retains geometry and has no physical normalization.
 * The caller retains originals and independently qualifies any physical cut. */
export function importAggregateSettingsSnapshot(snapshot){
 const only=(value,keys)=>{if(!value||typeof value!=='object'||Array.isArray(value)||![Object.prototype,null].includes(Object.getPrototypeOf(value))||Object.keys(value).some(key=>!keys.includes(key)))throw TypeError('Invalid finite snapshot shape');};
 only(snapshot,['kind','children','metadata']);
 if(snapshot.kind!=='fragment')throw TypeError('Invalid finite fragment');
 const settingsNodes=new Set(policy.nodes),normalizations=[];let encoding=null;
 function nodes(children,path=[],depth=0){
  if(depth>64||!Array.isArray(children))throw TypeError('Invalid finite children');
  return children.map((node,index)=>{
   const currentPath=[...path,index];
   if(node?.kind==='text')return cloneJSON(node);
   only(node,['kind','name','attributes','children']);
   if(node.kind!=='element'||typeof node.name!=='string')throw TypeError('Invalid finite element');
   const original=node.attributes;
   if(!original||typeof original!=='object'||Array.isArray(original)||![Object.prototype,null].includes(Object.getPrototypeOf(original)))throw TypeError('Invalid finite attributes');
   let attributes;
   if(settingsNodes.has(node.name)){
    const current=original[policy.logical_attribute]===policy.presence;
    const kind=current?'canonical':'aggregate';
    if(encoding!==null&&encoding!==kind)throw TypeError('Mixed settings encoding');encoding=kind;
    if(current){canonicalAttributeCodec.decode(node.name,original);attributes=cloneJSON(original);}
    else {
     const aggregate=original[policy.logical_attribute];
     if(!Object.hasOwn(original,policy.logical_attribute)||!aggregate||typeof aggregate!=='object'||Array.isArray(aggregate))throw TypeError('Aggregate settings required');
     if(Object.keys(original).some(key=>key.startsWith(policy.field_prefix)))throw TypeError('Mixed settings encoding');
     attributes=canonicalAttributeCodec.encode(node.name,original);
     normalizations.push({path:currentPath,operation:'set_attribute',name:policy.logical_attribute,before:cloneJSON(aggregate),value:policy.presence});
     for(const name of Object.keys(attributes).filter(key=>key.startsWith(policy.field_prefix)).sort())normalizations.push({path:currentPath,operation:'add_attribute',name,value:cloneJSON(attributes[name])});
    }
   }else attributes=cloneJSON(original);
   return {...node,attributes,children:nodes(node.children,currentPath,depth+1)};
  });
 }
 const normalized={kind:'fragment',children:nodes(snapshot.children),...(Object.hasOwn(snapshot,'metadata')?{metadata:cloneJSON(snapshot.metadata)}:{})};
 return {snapshot:normalized,document:snapshotToDocument(normalized),normalizations,requires_physical_history_cut:normalizations.length!==0};
}

/** Canonical semantic AST normalization: text segmentation has no authored ID.
 * Block/option identities, marks, atom boundaries and envelope values remain exact. */
export function normalizeDocument(document){
 const pm=relayMarkToProseMirror(document),normalized=schema.nodeFromJSON(pm);normalized.check();
 return {...document,blocks:proseMirrorToRelayMark(JSON.parse(JSON.stringify(normalized.toJSON()))).blocks};
}
