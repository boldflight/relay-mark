/** Finite retained HTML import through maintained DOM + canonical PM grammar.
 * No browser, network, private draft, host permissions or HTML-to-Markdown path. */
import {DOMParser as HTMLDOMParser} from 'linkedom/worker';
import {DOMParser as PMDOMParser,Slice,Fragment} from 'prosemirror-model';
import {createCanonicalEditorSchema} from './editor-model.js';
import {inspectCanonicalHTML} from './document-html-rules.js';
import {parseForeignClipboard} from './document-html-foreign.js';
import {proseMirrorToSnapshot} from './document-snapshot.js';
import {importDocumentSnapshot,utf8Bytes} from './document-source.js';
import {stableStringify} from './canonical-json.js';
const schema=createCanonicalEditorSchema();
export function importDocumentHTML({html,namespace}){
 const originalHTML=html,dom=readHTML(html,namespace);
 if(html===null)html='';
 const {sourceNodes,sourceMarks,sourceText,normalizations}=inspectCanonicalHTML(dom.body);
 const document=PMDOMParser.fromSchema(schema).parse(dom.body,{preserveWhitespace:'full'});document.check();
 validateProjection(document,{sourceNodes,sourceMarks,sourceText,normalizations});
 const imported=importDocumentSnapshot(proseMirrorToSnapshot(document.toJSON()),{namespace});
 return {...imported,normalizations:[...(html===''?[{operation:'empty_retained_html',source_value:originalHTML}]:[]),...normalizations,...imported.normalizations,{operation:'import_retained_html',source:'description_html'}]};
}

function readHTML(html,namespace){
 if(html===null)html='';
 if(typeof html!=='string'||html.length>4194304||utf8Bytes(html).byteLength>4194304||typeof namespace!=='string'||!namespace)throw TypeError('Invalid retained HTML input');
 const dom=new HTMLDOMParser().parseFromString('<html><head></head><body>'+html+'</body></html>','text/html');
 if(dom.documentElement.children.length!==2||dom.head.childNodes.length||[...dom.documentElement.children].some(element=>!['head','body'].includes(element.localName)))throw TypeError('Invalid retained HTML envelope');
 return dom;
}
function validateProjection(document,{sourceNodes,sourceMarks,sourceText,normalizations}){
 const parsedNodes=[],parsedMarks=new Map();let parsedText='';
 document.descendants((node,position,parent)=>{
  if(!node.isText){parsedNodes.push({node,parent});return;}
  parsedText+=node.text;
  for(const mark of node.marks){const key=stableStringify([mark.type.name,mark.attrs]);parsedMarks.set(key,(parsedMarks.get(key)||'')+node.text);}
 });
 if(parsedText!==sourceText)throw TypeError('Retained HTML text was not preserved');
 const matched=new Map();let sourceIndex=0;
 for(const {node:parsed,parent}of parsedNodes){
  const original=sourceNodes[sourceIndex];
  if(parsed.type.name==='paragraph'&&original?.name!=='paragraph'&&
     (matched.get(parent)?.allowsImplicitParagraph&&parent.type.contentMatch.matchType(parsed.type)||
      sourceNodes.length===0&&!sourceText.trim())){
   normalizations.push({operation:'wrap_retained_inline',node:'paragraph',source_parent_index:matched.get(parent)?.sourceIndex??null});continue;
  }
  if(!original||parsed.type.name!==original.name||Object.entries(original.attributes).some(([key,value])=>stableStringify(parsed.attrs[key])!==stableStringify(value)))throw TypeError('Retained HTML structure or attributes were not preserved');
  matched.set(parsed,{...original,sourceIndex});sourceIndex++;
 }
 if(sourceIndex!==sourceNodes.length)throw TypeError('Retained HTML structure was not preserved');
 const expectedMarks=new Map();for(const mark of sourceMarks){const key=stableStringify([mark.name,mark.attributes]);expectedMarks.set(key,(expectedMarks.get(key)||'')+mark.text);}
 if(stableStringify([...expectedMarks].sort())!==stableStringify([...parsedMarks].sort()))throw TypeError('Retained HTML marks were not preserved');
}

/** Clipboard-only geometry. Recovery importDocumentHTML remains document-only.
 * Exported context is syntax, never a target/source authority or text lineage. */
export function importClipboardHTML({html,namespace}){
 // Clipboard HTML another application wrote is read as the web editor reads a
 // paste. Relay's own canonical HTML, and any ProseMirror slice, stay exact.
 try{return importCanonicalClipboardHTML({html,namespace});}
 catch(error){
  if(typeof html!=='string'||html.length>4194304||utf8Bytes(html).byteLength>4194304||typeof namespace!=='string'||!namespace)throw error;
  // Other applications write whole documents, with head, styles and metadata.
  const dom=new HTMLDOMParser().parseFromString(/<html[\s>]/i.test(html)?html:'<html><head></head><body>'+html+'</body></html>','text/html');
  // Editor-written HTML (a ProseMirror slice, Relay identities or authored
  // attributes) keeps its exact import and its refusals.
  if(!dom.body||[...dom.body.querySelectorAll('*')].some(element=>[...element.attributes].some(({name})=>
   /^data-(pm-slice|relaymark|authored|relay-)/.test(name))))throw error;
  return importForeignClipboardHTML(dom);
 }
}
function importForeignClipboardHTML(dom){
 let slice=Slice.fromJSON(schema,parseForeignClipboard(dom.body));
 if(!slice.content.size)throw TypeError('Empty clipboard Slice');
 schema.topNodeType.create(null,slice.content).check();
 const bounded=Slice.maxOpen(slice.content,false);
 slice=closeClipboardSlice(slice,bounded.openStart,bounded.openEnd);
 return {slice:{content:slice.content.toJSON(),openStart:slice.openStart,openEnd:slice.openEnd},
  normalizations:[{operation:'import_foreign_clipboard_html',source:'clipboard_html'}]};
}
function importCanonicalClipboardHTML({html,namespace}){
 const dom=readHTML(html,namespace),identityNormalizations=normalizeClipboardIdentities(dom.body),markers=[...dom.body.querySelectorAll('[data-pm-slice]')];
 if(markers.length>1)throw TypeError('Duplicate clipboard Slice metadata');
 let root=dom.body,declared=null,context=[];
 if(markers.length){
  const marker=markers[0],match=/^(\d+) (\d+)(?: -(\d+))? (.*)$/.exec(marker.getAttribute('data-pm-slice'));
  if(!match)throw TypeError('Invalid clipboard Slice metadata');
  declared=match.slice(1,3).map(Number);const wrappers=Number(match[3]||0);
  if([...declared,wrappers].some(n=>!Number.isSafeInteger(n)||n<0||n>128))throw TypeError('Clipboard Slice depth limit');
  context=JSON.parse(match[4]);if(!Array.isArray(context)||context.length%2||context.length>256)throw TypeError('Invalid clipboard context');
  marker.removeAttribute('data-pm-slice');
  for(let i=0;i<wrappers;i++){
   if(root.childNodes.length!==1||root.firstChild.nodeType!==1||!['table','tbody','tr'].includes(root.firstChild.localName))throw TypeError('Invalid clipboard table wrapper');
   if(root.firstChild.attributes.length)throw TypeError('Unexpected clipboard wrapper attributes');
   root=root.firstChild;
  }
 }
 const inventory=inspectCanonicalHTML(root),parser=PMDOMParser.fromSchema(schema);
 let slice=parser.parseSlice(root,{preserveWhitespace:'full'});
 if(!slice.content.size)throw TypeError('Empty clipboard Slice');
 // Validate exact original semantic nodes/marks before adding exported context.
 validateProjection(schema.topNodeType.create(null,slice.content),inventory);
 if(declared){
  if(declared[0]>slice.openStart||declared[1]>slice.openEnd)throw TypeError('Clipboard Slice depths exceed parsed content');
  slice=closeClipboardSlice(slice,...declared);
 }else{
  const bounded=Slice.maxOpen(slice.content,false);
  slice=closeClipboardSlice(slice,bounded.openStart,bounded.openEnd);
 }
 for(let i=context.length-2;i>=0;i-=2){
  const name=context[i],attrs=context[i+1],type=schema.nodes[name];
  if(typeof name!=='string'||!type||type===schema.topNodeType||type.isLeaf||type.hasRequiredAttrs()||
     attrs!==null&&(!attrs||typeof attrs!=='object'||Array.isArray(attrs)||Object.keys(attrs).some(k=>!Object.hasOwn(type.attrs,k))))throw TypeError('Unsupported clipboard context');
  slice=new Slice(Fragment.from(type.create(attrs,slice.content)),slice.openStart+1,slice.openEnd+1);
 }
 const maximum=Slice.maxOpen(slice.content);
 if(slice.openStart>maximum.openStart||slice.openEnd>maximum.openEnd||slice.size<=0)throw TypeError('Invalid restored clipboard Slice geometry');
 // No closed DocumentAST conversion here: open list/table fragments are legitimate.
 // Original fragment semantics remain exact input to the current host preflight.
 return {slice:{content:slice.content.toJSON(),openStart:slice.openStart,openEnd:slice.openEnd},
  normalizations:[...identityNormalizations,...inventory.normalizations,{operation:'import_clipboard_html',source:'clipboard_html'}]};
}
// Finite closeRange/closeSlice geometry from the installed maintained
// prosemirror-view/src/clipboard.ts (MIT); no target fitting or authority here.
function closeClipboardRange(fragment,side,from,to,depth,openEnd){
 const node=side<0?fragment.firstChild:fragment.lastChild;let inner=node.content;
 if(fragment.childCount>1)openEnd=0;
 if(depth<to-1)inner=closeClipboardRange(inner,side,from,to,depth+1,openEnd);
 if(depth>=from){
  const fill=side<0?node.contentMatchAt(0).fillBefore(inner,openEnd<=depth):node.contentMatchAt(node.childCount).fillBefore(Fragment.empty,true);
  if(!fill)throw TypeError('Unclosable clipboard Slice');inner=side<0?fill.append(inner):inner.append(fill);
 }
 return fragment.replaceChild(side<0?0:fragment.childCount-1,node.copy(inner));
}
function closeClipboardSlice(slice,openStart,openEnd){
 if(openStart<slice.openStart)slice=new Slice(closeClipboardRange(slice.content,-1,openStart,slice.openStart,0,slice.openEnd),openStart,slice.openEnd);
 if(openEnd<slice.openEnd)slice=new Slice(closeClipboardRange(slice.content,1,openEnd,slice.openEnd,0,0),slice.openStart,openEnd);
 return slice;
}

// Explicit recovery of the former maintained web clipboard export spelling.
// Live web writers emit only data-relaymark-id; document recovery stays strict.
function normalizeClipboardIdentities(root){
 let count=0;
 for(const element of root.querySelectorAll('[data-relaymarkid]')){
  const original=element.getAttribute('data-relaymarkid'),canonical=element.getAttribute('data-relaymark-id');
  if(canonical!==null&&canonical!==original)throw TypeError('Conflicting clipboard structural identity');
  element.setAttribute('data-relaymark-id',original);element.removeAttribute('data-relaymarkid');count++;
 }
 return count?[{operation:'normalize_clipboard_structural_identity',source:'data-relaymarkid',target:'data-relaymark-id',count}]:[];
}
