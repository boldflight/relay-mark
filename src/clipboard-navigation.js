/** Clipboard paste navigation plans: anchor names and heading/link repairs
 * for pasted content, as actual maintained ProseMirror steps. They grant no
 * source, donor or edit authority; the host admits the paste. */
import {snapshotToDocument,snapshotToDocumentWithProseMirror} from './document-snapshot.js';
import {Step,Transform} from 'prosemirror-transform';
import {Slice} from 'prosemirror-model';
import {relayMarkToProseMirror} from './document-adapter.js';
import {stableStringify,canonicalJSONSHA256,cloneCanonicalJSON} from './canonical-json.js';
import {paperDocumentDestinations} from './document-controls.js';
import {createCanonicalEditorSchema} from './editor-model.js';
const schema=createCanonicalEditorSchema();
const same=(a,b)=>stableStringify(a)===stableStringify(b);
function keys(value,allowed,required=allowed){if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!allowed.includes(k))||required.some(k=>!Object.hasOwn(value,k)))throw TypeError('Invalid causal evidence fields');}
function identity(value){keys(value,['client','clock']);if(!Number.isSafeInteger(value.client)||value.client<0||!Number.isSafeInteger(value.clock)||value.clock<0||value.clock>=2**32)throw TypeError('Invalid causal item identity');return value;}
function index(snapshot,decode=snapshotToDocument){
 const {portable,size,runs,nodes,positions}=snapshotProjection(snapshot);
 // Reuse only the paired result of this exact current decoder in this call.
 // Explicit finite/custom decoders retain their own full conversion path.
 const decoded=decode===snapshotToDocument?snapshotToDocumentWithProseMirror(portable):null;
 const document=decoded?decoded.document:decode(portable),json=decoded?decoded.prosemirror:relayMarkToProseMirror(document),pm=schema.nodeFromJSON(json);pm.check();if(pm.content.size!==size)throw TypeError('Causal snapshot size disagrees with maintained schema');
 return {runs,nodes,positions,document,pm:JSON.parse(JSON.stringify(pm.toJSON()))};
}
// Only an explicitly qualified original archive may choose finite semantic
// import. Its raw identity/run geometry remains the same maintained projection.
// A binding claim is not an authorization, receipt or human ancestry credential.
function navigationPlacement(input,issued=null){
 keys(input,issued?['before_document','block_indices','steps']:['archive_document','before_document','block_indices','steps']);
 const indices=input.block_indices,steps=input.steps;
 const source=schema.nodeFromJSON(issued?{type:'doc',content:steps?.[0]?.slice?.content}:input.archive_document),before=schema.nodeFromJSON(input.before_document);
 source.check();before.check();
 if(!Array.isArray(indices)||!indices.length||indices.length>4096||indices.some((n,i)=>!Number.isSafeInteger(n)||n<0||(!issued&&n>=source.childCount)||(i&&n<=indices[i-1]))||!Array.isArray(steps)||!steps.length||steps.length>512)throw TypeError('Invalid reviewed navigation input');
 const first=steps[0],append=first.stepType==='replace'&&first.from===before.content.size&&first.to===first.from,replacement=first.stepType==='replace'&&first.from===0&&first.to===before.content.size;
 if(!append&&!replacement||first.slice?.openStart||first.slice?.openEnd||first.slice?.content?.length!==indices.length)throw TypeError('Unavailable reviewed navigation placement');
 const strip=node=>{const out={...node};if(node.attrs){const {relaymarkId,...attrs}=node.attrs;out.attrs=attrs;}if(node.content)out.content=node.content.map(strip);return out;};
 const initial=Step.fromJSON(schema,first).apply(before);if(initial.failed)throw TypeError('Refused reviewed navigation Slice');
 for(let i=0;!issued&&i<indices.length;i++)if(!same(strip(source.child(indices[i]).toJSON()),strip(first.slice.content[i])))throw TypeError('Reviewed navigation changed original Slice');
 let current=before;for(const step of steps){const applied=Step.fromJSON(schema,step).apply(current);if(applied.failed)throw TypeError('Refused reviewed navigation Step');current=applied.doc;}
 if(current.content.size!==initial.doc.content.size)throw TypeError('Reviewed navigation changed import geometry');
 if(append)for(let i=0;i<before.childCount;i++)if(!before.child(i).eq(current.child(i)))throw TypeError('Reviewed navigation changed retained target');
 const lookup=path=>{let node=current,position=0;const actual=[(append?before.childCount:0)+indices.indexOf(path[0]),...path.slice(1)];for(let depth=0;depth<actual.length;depth++){const child=actual[depth];if(child<0||child>=node.childCount)throw TypeError('Unavailable reviewed navigation path');for(let i=0;i<child;i++)position+=node.child(i).nodeSize;if(depth)position++;node=node.child(child);}return {node,position};};
 return {source,before,indices,steps,append,current,lookup};
}


/** Clipboard placement is independent of reviewed-history admission. Exact
 * freshly copied structural IDs locate copied nodes after maintained Steps.
 * A fitted-away wrapper cannot be reconstructed by equal text. */
export function planClipboardAnchorAllocation(input){return planAnchorAllocation(input,null,clipboardNavigationPlacement);}
export function planClipboardHeadingNavigation(input){return planHeadingNavigation(input,null,clipboardNavigationPlacement);}
function clipboardNavigationPlacement(input){
 if(input.clipboard_items!=null)return clipboardBatchNavigationPlacement(input);
 keys(input,['clipboard_slice','before_document','steps','source_trace'],['clipboard_slice','before_document','steps']);
 const fragment=Slice.fromJSON(schema,input.clipboard_slice);
 const source=schema.topNodeType.create(null,fragment.content),before=schema.nodeFromJSON(input.before_document),steps=input.steps;
 before.check();
 const maximum=Slice.maxOpen(fragment.content);
 if(fragment.openStart<0||fragment.openEnd<0||fragment.openStart>maximum.openStart||fragment.openEnd>maximum.openEnd||fragment.size<=0)throw TypeError('Invalid clipboard fragment geometry');
 if(!source.childCount||source.childCount>4096||!Array.isArray(steps)||!steps.length||steps.length>512)throw TypeError('Invalid clipboard navigation input');
 const entries=doc=>{
  const ids=new Map(),paths=new Map();let budget=1_000_000;
  const visit=(node,path,position)=>{
   if(--budget<0||path.length>128)throw TypeError('Clipboard navigation inventory limit');
   paths.set(stableStringify(path),{node,position});
   const id=node.attrs.relaymarkId;
   if(typeof id==='string'){
    if(!/^b[0-9a-f]{32}$/.test(id)||ids.has(id))throw TypeError('Invalid clipboard structural identity');
    ids.set(id,{node,path,position});
   }
   let offset=position+(path.length?1:0);
   node.forEach((child,_,i)=>{visit(child,[...path,i],offset);offset+=child.nodeSize;});
  };
  visit(doc,[],0);return {ids,paths};
 };
 const copied=entries(source),original=entries(before);
 for(const id of copied.ids.keys())if(original.ids.has(id))throw TypeError('Clipboard identity was not freshly allocated');
 // Exact maintained identity-attribute Steps may identify a newly split
 // target heading wrapper. This is target placement classification only;
 // it confers no copied ancestry or issued history correspondence.
 const targetHeadingWrappers=new Map(),placementTransform=new Transform(before);
 let current=before;
 for(const json of steps){
  const prior=json.stepType==='attr'&&json.attr==='relaymarkId'?current.nodeAt(json.pos):null;
  const applied=Step.fromJSON(schema,json).apply(current);if(applied.failed)throw TypeError('Refused clipboard navigation Step');
  if(prior?.type.name==='heading'){
   const oldID=prior.attrs.relaymarkId,originalID=targetHeadingWrappers.get(oldID)??oldID,retained=original.ids.get(originalID);
   if(retained?.node.type.name==='heading'&&!copied.ids.has(oldID)&&typeof json.value==='string'&&!copied.ids.has(json.value)&&!original.ids.has(json.value)){
    const mappedOriginal=placementTransform.mapping.map(retained.position,1),originalNode=current.nodeAt(mappedOriginal);
    let duplicateCount=0;current.descendants(node=>{if(node.type.name==='heading'&&node.attrs.relaymarkId===oldID)duplicateCount++;});
    const provedWrapper=targetHeadingWrappers.has(oldID);
    const distinctGenerated=provedWrapper||duplicateCount>1&&same(prior.attrs,retained.node.attrs);
    const originalSurvives=originalNode?.type===retained.node.type&&same(originalNode.attrs,retained.node.attrs)&&mappedOriginal!==json.pos;
    const next=applied.doc.nodeAt(json.pos);
    if(distinctGenerated&&originalSurvives&&next?.type===prior.type&&next.attrs.relaymarkId===json.value&&next.attrs.headingId===prior.attrs.headingId)targetHeadingWrappers.set(json.value,originalID);
   }
  }
  placementTransform.step(Step.fromJSON(schema,json));
  current=placementTransform.doc;
 }
 const traced=input.source_trace==null?null:clipboardSourceTrace(input.source_trace,fragment,steps,current);
 const placed=entries(current),retainedNames=[];
 const originalNames=new Map(paperDocumentDestinations(before.toJSON()).map(entry=>{
  const value=original.paths.get(stableStringify(entry.source_path));return [value.node.attrs.relaymarkId,entry.name];
 }));
 for(const entry of paperDocumentDestinations(current.toJSON())){
  const actual=placed.paths.get(stableStringify(entry.source_path)),id=actual.node.attrs.relaymarkId;
  if(copied.ids.has(id))continue;
  const retained=original.ids.get(id),key=entry.kind==='heading'?'headingId':'name';
  if(retained){
   if(retained.node.type!==actual.node.type||retained.node.attrs[key]!==actual.node.attrs[key])throw TypeError('Clipboard navigation changed retained destination');
   retainedNames.push(originalNames.get(id));
  }else if(entry.kind==='heading'&&targetHeadingWrappers.has(id)){
   // Fresh suffix headings are normalized by the existing heading allocator;
   // original retained headings keep their names regardless of paste order.
   retainedNames.push(actual.node.attrs.headingId);
  }else throw TypeError('Clipboard navigation changed retained destination');
 }
 const comparable=node=>{
  // PM Node.toJSON retains the attrs object. Projection must never delete
  // fields on the immutable source/current Node while comparing them.
  const json=cloneCanonicalJSON(node.toJSON());
  if(json.attrs){if(node.type.name==='heading')delete json.attrs.headingId;if(node.type.name==='relayAnchor')delete json.attrs.name;}
  return json;
 };
 const lookup=path=>{
  const expected=copied.paths.get(stableStringify(path));if(!expected)throw TypeError('Unavailable clipboard source path');
  let prefix=path.length,ancestor;
  for(;prefix>0;prefix--){const item=copied.paths.get(stableStringify(path.slice(0,prefix)));if(typeof item?.node.attrs.relaymarkId==='string'){ancestor=item;break;}}
  // Inline source correspondence is positional even if fitting coalesced it
  // with copied or retained text. Never recover it by matching equal strings.
  if(expected.node.isText&&traced)return traced.lookup(path,expected.node);
  if(!ancestor)throw TypeError('Clipboard source path has no structural owner');
  const retained=placed.ids.get(ancestor.node.attrs.relaymarkId);
  if(!retained)throw TypeError('Clipboard fitting removed source destination');
  let {node,position}=retained;
  for(const child of path.slice(prefix)){
   if(child>=node.childCount)throw TypeError('Clipboard fitting changed source path');
   position++;for(let i=0;i<child;i++)position+=node.child(i).nodeSize;node=node.child(child);
  }
  if(!same(comparable(node),comparable(expected.node)))throw TypeError('Clipboard fitting changed source node');
  return {node,position};
 };
 const sourceDestinations=paperDocumentDestinations(source.toJSON()).filter(entry=>{
  const value=copied.paths.get(stableStringify(entry.source_path));
  // Context-only wrappers outside the actual Slice are not newly selected
  // destinations; their selected descendants remain exact copied material.
  return value.position>=fragment.openStart&&value.position<fragment.content.size-fragment.openEnd;
 });
 return {source,before,indices:Array.from({length:source.childCount},(_,i)=>i),steps,append:false,current,lookup,retainedNames,sourceDestinations};
}

function clipboardBatchNavigationPlacement(input){
 keys(input,['clipboard_items','before_document','steps']);
 if(!Array.isArray(input.clipboard_items)||input.clipboard_items.length<2||input.clipboard_items.length>4096)throw TypeError('Invalid clipboard item roster');
 const before=schema.nodeFromJSON(input.before_document),steps=input.steps,transform=new Transform(before),children=[],items=[];
 before.check();
 if(!Array.isArray(steps)||!steps.length||steps.length>512)throw TypeError('Clipboard Step budget');
 for(const raw of steps)transform.step(Step.fromJSON(schema,raw));
 const current=transform.doc;
 let offset=0,prior=-1;
 for(const item of input.clipboard_items){
  keys(item,['clipboard_slice','source_trace','step_index']);
  const index=item.step_index;
  if(!Number.isSafeInteger(index)||index<=prior||index<0||index>=steps.length)throw TypeError('Invalid clipboard item Step order');
  prior=index;
  const fragment=Slice.fromJSON(schema,item.clipboard_slice),maximum=Slice.maxOpen(fragment.content);
  if(fragment.openStart<0||fragment.openEnd<0||fragment.openStart>maximum.openStart||fragment.openEnd>maximum.openEnd||fragment.size<=0)throw TypeError('Invalid clipboard fragment geometry');
  const trace=clipboardSourceTrace(item.source_trace,fragment,steps.slice(index),current,true);
  items.push({fragment,trace,offset});children.push(...fragment.content.content);offset+=fragment.content.childCount;
 }
 if(offset>4096)throw TypeError('Clipboard item node budget');
 // Reuse single placement's retained-target classification and structural lookup.
 // Text uses the original item trace, mapped through every later actual StepMap.
 const combined=new Slice(schema.topNodeType.create(null,children).content,0,0);
 const base=clipboardNavigationPlacement({clipboard_slice:combined.toJSON(),before_document:input.before_document,steps});
 const owner=path=>{const item=items.find(item=>path[0]>=item.offset&&path[0]<item.offset+item.fragment.content.childCount);if(!item)throw TypeError('Invalid clipboard item path');return {item,path:[path[0]-item.offset,...path.slice(1)]};};
 const lookup=path=>{const owned=owner(path);let node=schema.topNodeType.create(null,owned.item.fragment.content);for(const index of owned.path)node=node.child(index);return node.isText?owned.item.trace.lookup(owned.path,node):base.lookup(path);};
 const sourceDestinations=[];
 for(const item of items){
  const doc=schema.topNodeType.create(null,item.fragment.content),positions=new Map();
  const visit=(node,path,pos)=>{positions.set(stableStringify(path),pos);let offset=pos+(path.length?1:0);node.forEach((child,_,index)=>{visit(child,[...path,index],offset);offset+=child.nodeSize;});};visit(doc,[],0);
  for(const destination of paperDocumentDestinations(doc.toJSON())){
   const pos=positions.get(stableStringify(destination.source_path));
   if(pos>=item.fragment.openStart&&pos<item.fragment.content.size-item.fragment.openEnd)sourceDestinations.push({...destination,source_path:[destination.source_path[0]+item.offset,...destination.source_path.slice(1)]});
  }
 }
 return {...base,lookup,sourceDestinations,sourceScope:path=>items.indexOf(owner(path).item)};
}

// This input is emitted internally by the same native fitter. Bind it to the
// actual original fragment/Step and validate its claimed positions; text is
// compared only AT those positions, never searched to infer correspondence.
function clipboardSourceTrace(trace,fragment,steps,current,allowStructuralSuffix=false){
 keys(trace,['source_nodes','placements','omitted_source_tokens','events','step']);
 const integer=n=>Number.isSafeInteger(n)&&n>=0&&n<=1_000_000;
 if(!same(trace.step,steps[0])||!allowStructuralSuffix&&steps.slice(1).some(s=>!['attr','docAttr','addMark','removeMark'].includes(s.stepType)))throw TypeError('Clipboard trace Step disagrees with placement');
 const suffix=steps.slice(1).map(raw=>Step.fromJSON(schema,raw).getMap());
 const mappedToken=position=>{
  let from=position,to=position+1;
  for(const map of suffix){from=map.map(from,1);to=map.map(to,-1);}
  if(to!==from+1)return null;
  return from;
 };
 if(!Array.isArray(trace.source_nodes)||trace.source_nodes.length>65536||!Array.isArray(trace.placements)||trace.placements.length>1_000_000||!Array.isArray(trace.events)||trace.events.length>65536||!Array.isArray(trace.omitted_source_tokens))throw TypeError('Clipboard trace resource bound');
 const tokens=doc=>{
  const out=[],nodes=[];
  const walk=(fragment,path,start)=>{let pos=start;fragment.forEach((node,_,i)=>{
   const child=path.concat(i),inner=node.isLeaf?pos:pos+1;
   nodes.push({source_path:child,from:pos,to:pos+node.nodeSize,content_from:inner,content_to:node.isLeaf?pos+node.nodeSize:pos+node.nodeSize-1,type:node.type.name});
   if(node.isText)for(let n=0;n<node.text.length;n++)out.push({kind:'text',unit:node.text.charCodeAt(n),marks:node.marks});
   else if(node.isLeaf)out.push({kind:'leaf',node});
   else{out.push({kind:'open',node});walk(node.content,child,pos+1);out.push({kind:'close',node});}
   pos+=node.nodeSize;
  });};
  walk(doc,[],0);return {out,nodes};
 };
 const original=tokens(fragment.content),target=tokens(current.content);
 if(original.out.length>1_000_000||!same(original.nodes,trace.source_nodes))throw TypeError('Clipboard trace original path inventory changed');
 const nodesByPath=new Map(original.nodes.map(node=>[stableStringify(node.source_path),node]));
 const opening=new Map(original.nodes.map(node=>[node.from,node])),closing=new Map(original.nodes.map(node=>[node.to-1,node]));
 const filtered=new Map();let eventBudget=1_000_000;
 for(const event of trace.events){
  if(event.kind==='open_wrapper'){
   keys(event,['kind','source_path']);if(!nodesByPath.has(stableStringify(event.source_path))||nodesByPath.get(stableStringify(event.source_path)).content_from===nodesByPath.get(stableStringify(event.source_path)).from)throw TypeError('Invalid clipboard opened wrapper');
  }else{
   keys(event,event.kind==='filtered_marks'?['kind','source_tokens','marks']:['kind','source_tokens']);
   if(!['drop_node','empty_open_node','filtered_marks'].includes(event.kind)||!Array.isArray(event.source_tokens)||event.source_tokens.some(n=>!integer(n)||n>=original.out.length)||(eventBudget-=event.source_tokens.length)<0)throw TypeError('Invalid clipboard source event');
   if(event.kind==='filtered_marks'){
    if(!Array.isArray(event.marks)||event.marks.length>64)throw TypeError('Invalid clipboard filtered marks');
    for(const raw of event.marks){const mark=schema.markFromJSON(raw);if(mark.type.name==='link')throw TypeError('Clipboard fitting discarded original link');}
    for(const n of event.source_tokens)filtered.set(n,event.marks);
   }
  }
 }
 const seen=new Set(),targets=new Set();let prior=-1;
 const comparable=node=>{const json={type:node.type.name,attrs:cloneCanonicalJSON(node.attrs),marks:node.marks.map(mark=>mark.toJSON())};if(node.type.name==='heading')delete json.attrs.headingId;if(node.type.name==='relayAnchor')delete json.attrs.name;return json;};
 for(const range of trace.placements){
  keys(range,['source_from','source_to','target_from','target_to']);
  if(Object.values(range).some(n=>!integer(n))||range.source_to<=range.source_from||range.source_to>original.out.length||range.target_to-range.target_from!==range.source_to-range.source_from||range.target_to>1_000_000||range.target_from<prior)throw TypeError('Invalid clipboard trace placement range');
  prior=range.target_to;
  for(let n=0;n<range.source_to-range.source_from;n++){
   const s=range.source_from+n,t=mappedToken(range.target_from+n);
   if(seen.has(s))throw TypeError('Clipboard trace duplicated source token');seen.add(s);
   const a=original.out[s];
   if(t==null){
    if(a.kind==='text'||a.kind==='leaf')throw TypeError('Later clipboard item discarded original semantic content');
    continue; // Maintained fitting can coalesce a context/container wrapper.
   }
   if(targets.has(t))throw TypeError('Clipboard trace duplicated target token');targets.add(t);
   const b=target.out[t];if(!b||a.kind!==b.kind)throw TypeError('Clipboard trace token kind changed');
   if(a.kind==='text'){
    const removed=filtered.get(s)??[],marks=a.marks.filter(mark=>!removed.some(raw=>same(mark.toJSON(),raw)));
    if(a.unit!==b.unit||!same(marks.map(mark=>mark.toJSON()),b.marks.map(mark=>mark.toJSON())))throw TypeError('Clipboard trace text/marks changed at issued position');
   }else{
    const wrapper=a.kind==='open'||a.kind==='close',bounds=wrapper?(a.kind==='open'?opening:closing).get(s):null;
    const context=bounds&&(bounds.from<fragment.openStart||bounds.to>fragment.content.size-fragment.openEnd);
    // An open context wrapper may join the retained target's wrapper. Its
    // selected descendants still require exact token/mark correspondence.
    if(!context&&!same(comparable(a.node),comparable(b.node)))throw TypeError('Clipboard trace node changed at issued position');
   }
  }
 }
 const omitted=Array.from({length:original.out.length},(_,i)=>i).filter(n=>!seen.has(n));
 if(!same(omitted,trace.omitted_source_tokens))throw TypeError('Clipboard trace incomplete omission roster');
 for(const token of omitted)if(token>=fragment.openStart&&token<fragment.content.size-fragment.openEnd&&['text','leaf'].includes(original.out[token].kind))throw TypeError('Clipboard fitting discarded original semantic content');
 return {lookup(path,node){
  const source=nodesByPath.get(stableStringify(path));if(!source||!node.isText)throw TypeError('Unavailable clipboard traced text path');
  const ranges=[];let count=0;
  for(const item of trace.placements){const from=Math.max(source.from,item.source_from),to=Math.min(source.to,item.source_to);if(to<=from)continue;
   for(let token=from;token<to;token++){
    const start=mappedToken(item.target_from+token-item.source_from);
    if(start==null)throw TypeError('Later clipboard item discarded original referenced text');
    const end=start+1;count++;
    const previous=ranges.at(-1);if(previous&&previous[1]===start)previous[1]=end;else ranges.push([start,end]);
   }
  }
  if(count!==node.nodeSize||!ranges.length)throw TypeError('Clipboard fitting discarded original referenced text');
  return {node,position:ranges[0][0],ranges};
 }};
}

function planAnchorAllocation(input,issued=null,placement=navigationPlacement){
 const {source,before,indices,steps,append,current,lookup,retainedNames:clipboardRetained,sourceDestinations,sourceScope}=placement(input,issued);
 const inventory=issued?issued.destinations.filter(entry=>entry.kind==='anchor').map(entry=>({source_path:entry.source_path,name:entry.source_name})):(sourceDestinations??paperDocumentDestinations(source.toJSON())).filter(entry=>entry.kind==='anchor');
 const selected=new Set(indices),counts=new Map(),used=new Set(),reserved=new Set();
 const originalKey=entry=>sourceScope?sourceScope(entry.source_path)+':'+entry.name:entry.name;
 for(const entry of inventory)counts.set(originalKey(entry),(counts.get(originalKey(entry))||0)+1);
 const names=(doc,out)=>doc.descendants(node=>{const name=node.type.name==='relayAnchor'?node.attrs.name:node.type.name==='heading'?node.attrs.headingId:null;if(typeof name==='string')out.add(name);});
 const retainedNames=clipboardRetained??(append?paperDocumentDestinations(before.toJSON()).map(entry=>entry.name):[]);
 for(const name of retainedNames)used.add(name);names(current,reserved);
 for(const entry of paperDocumentDestinations(current.toJSON()))reserved.add(entry.name);
 const repair=new Transform(current);
 for(const entry of inventory)if(selected.has(entry.source_path[0])){
  if(counts.get(originalKey(entry))!==1)throw TypeError('Ambiguous original explicit Anchor');
  const {node,position}=lookup(entry.source_path);
  if(node.type.name!=='relayAnchor'||node.attrs.name!==entry.name)throw TypeError('Reviewed Anchor changed original source name');
  let name=entry.name;
  if(used.has(name)){
   const id=node.attrs.relaymarkId;
   if(typeof id!=='string'||!/^b[0-9a-f]{32}$/.test(id))throw TypeError('Reviewed Anchor requires allocated canonical identity');
   const base='a-'+id;name=base;let suffix=2;while(reserved.has(name))name=base+'-'+suffix++;
   if(name.length>128)throw TypeError('Reviewed Anchor name limit');
   repair.setNodeAttribute(position,'name',name);reserved.add(name);
  }
  used.add(name);
 }
 if(steps.length+repair.steps.length>512)throw TypeError('Reviewed navigation Step limit');
 return {steps:repair.steps.map(step=>step.toJSON()),document:repair.doc.toJSON(),retained_destination_names:retainedNames};
}

function planHeadingNavigation(input,issued=null,placement=navigationPlacement){
 const {source,before,indices,steps,append,current,lookup,sourceDestinations,sourceScope}=placement(input,issued);
 const anchorSteps=steps.filter(step=>step.stepType==='attr'&&step.attr==='name');
 const allocation=planAnchorAllocation({...input,steps:steps.filter(step=>!anchorSteps.includes(step))},issued,placement);
 if(!same(allocation.steps,anchorSteps))throw TypeError('Reviewed Anchor name Steps disagree with original collision');
 const selected=new Set(indices),inventory=issued?issued.destinations.map(entry=>({source_path:entry.source_path,kind:entry.kind,name:entry.source_name})):(sourceDestinations??paperDocumentDestinations(source.toJSON())),destinations=[],references=[],allReferences=[];
 const walk=(node,path,visit)=>{visit(node,path);for(let i=0;i<node.childCount;i++)walk(node.child(i),[...path,i],visit);};

 const finalNames=new Set();current.descendants(node=>{const name=node.type.name==='heading'?node.attrs.headingId:node.type.name==='relayAnchor'?node.attrs.name:null;if(typeof name==='string'){if(finalNames.has(name))throw TypeError('Ambiguous reviewed destination');finalNames.add(name);}});
 for(const entry of inventory)if(selected.has(entry.source_path[0])){
  const {node}=lookup(entry.source_path),name=entry.kind==='heading'?node.attrs.headingId:node.attrs.name;
  if(typeof name!=='string'||!/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(name))throw TypeError('Unavailable reviewed destination');
  destinations.push({source_path:entry.source_path,kind:entry.kind,source_name:entry.name,destination_name:name});
 }
 walk(source,[],(node,path)=>{
  if(issued&&path.length)path=[indices[path[0]],...path.slice(1)];
  const href=node.marks.find(mark=>mark.type.name==='link')?.attrs.href;
  if(typeof href==='string'&&href.startsWith('#'))allReferences.push({source_path:path,kind:'link',source_target:href});
  if(node.type.name==='relayButton'&&node.attrs.kind==='anchor')allReferences.push({source_path:path,kind:'button',source_target:node.attrs.target});
 });
 const repair=new Transform(current);
 for(const reference of allReferences)if(selected.has(reference.source_path[0])){
  let name=reference.source_target;
  if(reference.kind==='link'){try{name=decodeURIComponent(name.slice(1));}catch{throw TypeError('Malformed original navigation fragment');}}
  const original=inventory.filter(entry=>entry.name===name&&(!sourceScope||sourceScope(entry.source_path)===sourceScope(reference.source_path)));
  if(original.length!==1)throw TypeError('Unresolved or ambiguous original navigation destination');
  const destination=destinations.find(entry=>same(entry.source_path,original[0].source_path)&&entry.kind===original[0].kind);
  if(!destination)throw TypeError('Original navigation destination was not selected');
  const target=destination.destination_name===destination.source_name?reference.source_target:(reference.kind==='link'?'#':'')+destination.destination_name;
  references.push({...reference,destination_target:target});
  const {node,position,ranges}=lookup(reference.source_path);
  if(reference.kind==='link'){
   const mark=node.marks.find(mark=>mark.type.name==='link');
   if(!node.isInline||mark?.attrs.href!==reference.source_target)throw TypeError('Reviewed navigation changed original link');
   if(target!==reference.source_target)for(const [from,to]of ranges??[[position,position+node.nodeSize]]){repair.removeMark(from,to,mark);repair.addMark(from,to,mark.type.create({...mark.attrs,href:target}));}
  }else{
   if(node.type.name!=='relayButton'||node.attrs.kind!=='anchor'||node.attrs.target!==reference.source_target)throw TypeError('Reviewed navigation changed original button');
   if(target!==reference.source_target)repair.setNodeAttribute(position,'target',target);
  }
 }
 if(steps.length+repair.steps.length>512)throw TypeError('Reviewed navigation Step limit');
 if(destinations.length>4096||references.length>4096)throw TypeError('Reviewed navigation correspondence limit');
 if(issued){if(!same(destinations,issued.destinations)||!same(references,issued.references))throw TypeError('Retained navigation correspondence disagrees with original Steps');}
 return {steps:repair.steps.map(step=>step.toJSON()),document:repair.doc.toJSON(),navigation_correspondence:{source_inventory_sha256:issued?issued.source_inventory_sha256:canonicalJSONSHA256({destinations:inventory,references:allReferences}),destinations,references}};
}
