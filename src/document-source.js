/** Canonical source: maintained CommonMark + directives, exact relaymark-ast interchange. */
import MarkdownIt from 'markdown-it';
import {sha256} from '@noble/hashes/sha2.js';
import {bytesToHex} from '@noble/hashes/utils.js';
import {proseMirrorToRelayMark,relayMarkToProseMirror,identifiedDocumentNodeNames} from './document-adapter.js';
import {mapInline,textMarkNames} from './document-inline.js';
import {cloneCanonicalJSON as cloneJSON} from './canonical-json.js';
import {documentToSnapshot,snapshotToDocument,normalizeDocument} from './document-snapshot.js';
export {documentToSnapshot,snapshotToDocument,normalizeDocument,importAggregateSettingsSnapshot} from './document-snapshot.js';
export {validateTextAttributes} from './document-inline.js';
import {parseAtomSource,buildEntityReferenceSource} from './document-atoms.js';
export {buildEntityReferenceSource} from './document-atoms.js';
export {safeImageSource} from './document-links.js';
import {safeImageSource,safeLinkHref,renderedLinkAttributes,linkAttributes} from './document-links.js';
import {parseAttributes} from './attributes.js';
import {directiveNodeForName,directiveNodeForType,canonicalDirectiveNodes} from './document-directives.js';
import {directiveForName,directiveForType} from './registry.js';
import {isBlockNode} from './node-kind.js';
import {parsePaperControlSource,paperDocumentDestinations as authoredPMDestinations} from './document-controls.js';
import {parseEntityReferenceSource,buildBlockEntityReferenceSource} from './document-reference.js';
const md=new MarkdownIt({html:true,linkify:false,typographer:false});
// Maintained CommonMark's inline rule owns code/escape/mark boundaries. This rule
// interprets finite historic wiki source once and emits only canonical atom nodes.
md.inline.ruler.before('link','relaymark_reference',(state,silent)=>{
 if(state.src.slice(state.pos,state.pos+2)!=='[[')return false;
 const end=state.src.indexOf(']]',state.pos+2);if(end<0)return false;
 const atom=importAtomSource(state.src.slice(state.pos,end+2));
 if(!atom){if(!silent){const token=state.push('text','',0);token.content=state.src.slice(state.pos,end+2);}state.pos=end+2;return true;}
 if(!silent){const token=state.push('relay_atom','',0);token.meta=atom;}
 state.pos=end+2;return true;
});
function importAtomSource(source){
 const canonical=parseAtomSource(source);if(canonical)return canonical;
 const match=source.match(/^\[\[([A-Z][A-Za-z0-9]*(?: [A-Z][A-Za-z0-9]*)*):\s*([^| ]+)\s*(?:\|([\s\S]*))?\]\]$/u);if(!match)return null;
 const[type,id]=match.slice(1),label=match[3]===undefined?type:match[3].replace(/^ /u,'');
 try{const normalized=type==='Tag'?`[[Tag: ${id} | ${label}]]`:buildEntityReferenceSource({entityType:type,entityId:id,label});return parseAtomSource(normalized);}catch{return null;}
}
function bareLinkedTaskLine(line){return /^ {0,3}\[[ xX]\]\s+.*\[\[Task:/u.test(line)?line.replace(/^( {0,3})/u,'$1- '):line;}
function linkedTask(item){
 const paragraph=item.content[0],parts=paragraph?.type==='paragraph'?paragraph.content:null;if(!parts)return;
 const boundary=parts.findIndex(n=>n.type==='text'&&n.text.includes('\n')),index=(boundary<0?parts.length:boundary)-1,last=parts[index];
 if(last?.type!=='relay.entity_ref'||last.props.entityType!=='Task')return;
 item.props.entityId=last.id;parts.splice(index,1);
 const previous=parts[index-1];if(previous?.type==='text'&&previous.text.endsWith(' ')){previous.text=previous.text.slice(0,-1);if(!previous.text)parts.splice(index-1,1);}
}

const marksOrder=textMarkNames;
function valid(ast){return normalizeDocument(ast);}
/** Read-only authored destination inventory. Duplicate explicit Anchors remain
 * ambiguous; a host may activate only an exact unique selected target. */
export function paperDocumentDestinations(ast){return authoredPMDestinations(relayMarkToProseMirror(valid(ast)));}
function id(namespace,path){const hash=bytesToHex(sha256(utf8Bytes(namespace+'\0'+path.join('.'))));return 'b'+hash.slice(0,12)+'4'+hash.slice(13,16)+'8'+hash.slice(17,32);}
function block(ns,path,type,content=[],props){return {id:id(ns,path),type,...(props?{props}:{}),content};}
function longestTicks(s){return Math.max(0,...Array.from(s.matchAll(/`+/g),m=>m[0].length));}
export function serializeDocument(ast){ast=valid(ast);const json=JSON.stringify(ast),f='`'.repeat(Math.max(3,longestTicks(json)+1));return `${f}relaymark-ast\n${json}\n${f}\n`;}
export function parseDocument(source,{namespace}={}){
 if(typeof source!=='string')throw new TypeError('Invalid authored source');source=source.replace(/\r\n?/g,'\n');
 const exact=exactSourceAST(source);
 if(exact!==undefined)return valid(exact);
 namespace??=source;if(typeof namespace!=='string')throw new TypeError('Invalid import namespace');
 let frontmatter;const fm=source.match(/^---\n([\s\S]*?)\n---(?:\n|$)/);if(fm){frontmatter={};for(const line of fm[1].split('\n')){const m=line.match(/^([^:]+):\s*(.*)$/);if(!m)throw new TypeError('Invalid frontmatter');try{frontmatter[m[1]]=JSON.parse(m[2]);}catch{frontmatter[m[1]]=m[2];}}source=source.slice(fm[0].length);}
 const blocks=sourceBlocks(source,namespace,[]);if(!blocks.length)blocks.push(block(namespace,[0],'paragraph'));
 return valid({type:'relaymark.document',...(frontmatter?{frontmatter}:{}),blocks});
}
function exactSourceAST(source){const exact=source.match(/^(`{3,})relaymark-ast\n([\s\S]*?)\n\1\s*$/);return exact?JSON.parse(exact[2]):undefined;}
/** Finite historical source input; ordinary current editing uses parseDocument. */
export function importDocumentSource(source,{namespace}={}){
 if(typeof source!=='string'||typeof namespace!=='string'||!namespace)throw new TypeError('Migration requires source and retained namespace');
 source=source.replace(/\r\n?/g,'\n');
 const exact=exactSourceAST(source);
 return importDocument(exact===undefined?parseDocument(source,{namespace}):exact,{namespace});
}
// UTF-8 encoding is portable across JSCore and browser hosts without Web API globals.
export function utf8Bytes(string){const bytes=[];for(const char of string){let c=char.codePointAt(0);if(c>=0xd800&&c<=0xdfff)c=0xfffd;if(c<128)bytes.push(c);else if(c<2048)bytes.push(192|(c>>6),128|(c&63));else if(c<65536)bytes.push(224|(c>>12),128|((c>>6)&63),128|(c&63));else bytes.push(240|(c>>18),128|((c>>12)&63),128|((c>>6)&63),128|(c&63));}return new Uint8Array(bytes);}
export function editorDirectiveDefinitions(){return canonicalDirectiveNodes;}
/** Finite XML migration. Returns edits for the host's existing CRDT transaction;
 * never allocates a replica or rewrites text/items/history. Unknown schemas fail. */
export function importDocumentSnapshot(original,{namespace}={}){
 if(typeof namespace!=='string'||!namespace)throw new TypeError('Migration requires retained namespace');
 const snapshot=cloneJSON(original),changes=[],identity_mapping={retained:[],remapped:[],added:[]},seen=new Set();
 function visit(node,path,depth){
  if(depth>64||!node||typeof node!=='object')throw new TypeError('Invalid historical XML');
  if(node.kind==='text')return;
  if(node.kind!=='element'||!Array.isArray(node.children))throw new TypeError('Invalid historical XML element');
  if(identifiedDocumentNodeNames.includes(node.name)){
   if(!node.attributes||typeof node.attributes!=='object'||Array.isArray(node.attributes))throw new TypeError('Invalid historical XML attributes');
   const old=node.attributes.relaymarkId;
   if(old!==undefined&&(typeof old!=='string'||!old||seen.has(old)))throw new TypeError('Historical XML identity');
   if(old!==undefined)seen.add(old);
   if(typeof old==='string'&&/^b[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$/.test(old))identity_mapping.retained.push(old);
   else {
    const next=id(namespace,['migration','xml',...path]);
    node.attributes.relaymarkId=next;
    const change={path:[...path],operation:old===undefined?'add_attribute':'set_attribute',name:'relaymarkId',...(old===undefined?{}:{before:old}),value:next};changes.push(change);
    if(old===undefined)identity_mapping.added.push({id:next,path:[...path],attribute:'relaymarkId'});
    else identity_mapping.remapped.push({from:old,to:next,path:[...path]});
   }
  }
  if(node.name==='videoEmbed'){
   const defaults={playbackId:null,title:null,source:'mux',thumbnailUrl:null,status:'ready',youtubeId:null,uploadPercent:null};
   for(const[key,value]of Object.entries(defaults))if(Object.hasOwn(node.attributes,key)){if(node.attributes[key]!==value)throw new TypeError('Historical video requires retained domain presentation evidence');changes.push({path:[...path],operation:'remove_attribute',name:key,before:value});delete node.attributes[key];}
  }
  const obsoleteAtomAttrs=node.name==='relayReference'?['status','subtitle']:node.name==='relayTag'?['color']:[];
  for(const key of obsoleteAtomAttrs)if(Object.hasOwn(node.attributes,key)){
   if(node.attributes[key]!==null)throw new TypeError('Historical inline atom requires retained presentation evidence');
   changes.push({path:[...path],operation:'remove_attribute',name:key,before:null});delete node.attributes[key];
  }
  node.children.forEach((child,i)=>visit(child,[...path,i],depth+1));
 }
 if(snapshot.kind!=='fragment'||!Array.isArray(snapshot.children))throw new TypeError('Historical XML root');
 snapshot.children.forEach((child,i)=>visit(child,[i],0));
 const document=snapshotToDocument(snapshot);
 return {snapshot,document,identity_mapping,normalizations:changes,requires_reconstruction:false};
}

/** Finite historical AST conversion; never called by normal edits/current admission. */
export function importDocument(original,{namespace}={}){
 if(!original||typeof original!=='object'||Array.isArray(original)||typeof namespace!=='string'||!namespace)throw new TypeError('Migration requires document and retained namespace');
 const document=cloneJSON(original),identity_mapping={retained:[],remapped:[],added:[]},ids=new Map(),seen=new Set();
 if(Object.hasOwn(document,'version')){if(document.version!==1)throw new TypeError('Unknown historical document version');delete document.version;}
 const profiles={'relaymark.agent_answer.v1':'relaymark.agent_answer','relaymark.scripture_release.v1':'relaymark.scripture_release','relaymark.scripture_span.v1':'relaymark.scripture_span'};
 function profile(value){if(Array.isArray(value))return value.map(profile);if(value&&typeof value==='object'){for(const[key,child]of Object.entries(value))value[key]=key==='profile'&&profiles[child]?profiles[child]:profile(child);}return value;}
 profile(document);
 function visit(n,path){if(!n||typeof n!=='object'||!isBlockNode(n))throw new TypeError('Historical block shape');const old=n.id;if(typeof old!=='string'||!old||seen.has(old))throw new TypeError('Historical block identity');seen.add(old);
  if(/^b[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$/.test(old)){identity_mapping.retained.push(old);ids.set(old,old);}else{n.id=id(namespace,['migration','block',old]);identity_mapping.remapped.push({from:old,to:n.id});ids.set(old,n.id);}
  if(Object.hasOwn(n,'evidence_refs')){if(!Array.isArray(n.evidence_refs)||JSON.stringify(n.evidence_refs)!==JSON.stringify(n.props?.evidence))throw new TypeError('Ambiguous historical evidence');delete n.evidence_refs;}
  const children=n.content||[];if(!Array.isArray(children))throw new TypeError('Historical content');n.content=children.map((child,i)=>isBlockNode(child)?visit(child,[...path,i]):child);
  if(directiveNodeForType(n.type)){
   const normalized=[];let pending=[];const flush=()=>{if(pending.length){const index=normalized.length,wrapper=id(namespace,['migration',old,'inline',index]);identity_mapping.added.push({id:wrapper,parent:n.id,role:'inline_body',index});normalized.push({id:wrapper,type:'paragraph',content:pending});pending=[];}};
   for(const child of n.content){if(isBlockNode(child)){flush();normalized.push(child);}else pending.push(child);}flush();n.content=normalized;
  }
  return n;
 }
 if(!Array.isArray(document.blocks))throw new TypeError('Historical document blocks');document.blocks=document.blocks.map((n,i)=>visit(n,[i]));
 // Only known AST block references are remapped; host entity/resource identities stay exact.
 function references(value){if(Array.isArray(value))return value.map(references);if(value&&typeof value==='object'){for(const[key,child]of Object.entries(value)){if(['block_id','start_block_id','end_block_id'].includes(key)&&typeof child==='string'&&ids.has(child))value[key]=ids.get(child);else if(key==='evidence'&&Array.isArray(child))value[key]=child.map(v=>ids.get(v)||v);else references(child);}}return value;}
 references(document);document.blocks=valid(document).blocks;return {document,identity_mapping};
}
function sourceBlocks(source,ns,prefix){
 const segments=[];let plain=[],directive=null,fence=null;
 const flush=()=>{if(plain.length){segments.push({kind:'markdown',source:plain.join('\n')});plain=[];}};
 const append=line=>directive?directive.body.push(line):plain.push(line);
 for(const line of source.split('\n')){const t=line.trim();
  if(!fence&&!directive&&/^(?: {4}|\t)/u.test(line)){plain.push(line);continue;}
  if(fence){append(line);if(new RegExp('^'+fence[0]+'{'+fence.length+',}\\s*$').test(t))fence=null;continue;}
  const f=t.match(/^(`{3,}|~{3,})/);if(f){fence=f[0];append(line);continue;}
  const header=t.match(/^@([A-Z][A-Za-z0-9]*)(?:\((.*)\))?\s*\{\s*$/);
  if(directive?.historical){if(/^<!--\s*\/relay:question\s*-->$/.test(t)){segments.push({...directive,kind:'historical_question',source:directive.body.join('\n')});directive=null;}else directive.body.push(line);continue;}
  if(directive){if(t==='}'&&--directive.depth===0){segments.push({...directive,kind:'directive',source:directive.body.join('\n')});directive=null;}else{if(header)directive.depth++;directive.body.push(line);}continue;}
  if(/^<!--\s*relay:question\s+.*?\s*-->$/.test(t)){flush();directive={historical:true,header:t,body:[]};continue;}
  if(/^<!--\s*\/relay:question\s*-->$/.test(t))throw new TypeError('Unexpected historical question closing');
  if(header){flush();directive={name:header[1],attrs:parseAttributes(header[2]||''),header:t,body:[],depth:1};continue;}
  const bodylessDataView=t.match(/^@DataView\((.*)\)\s*$/);
  if(bodylessDataView){flush();segments.push({kind:'directive',name:'DataView',attrs:parseAttributes(bodylessDataView[1]),header:t,source:''});continue;}
  const control=parsePaperControlSource(t);if(control){flush();segments.push({kind:'control',control});continue;}
  if(t==='}')throw new TypeError('Unexpected directive closing');plain.push(bareLinkedTaskLine(line));
 }
 if(directive)throw new TypeError('Missing directive closing');flush();
 return segments.flatMap((s,index)=>{const path=[...prefix,index];if(s.kind==='markdown')return markdownBlocks(md.parse(s.source,{}),ns,path);if(s.kind==='historical_question')return [historicalQuestion(s.header,s.source,ns,path)];if(s.kind==='control')return [block(ns,path,'relay.paper_control',[],{control:s.control.control,...s.control.attrs,source:s.control.source})];
  const spec=directiveForName(s.name);if(!spec)throw new TypeError('Unknown directive');const props={...s.attrs};for(const [key,a]of Object.entries(spec.attributes||{}))if(props[key]===undefined&&Object.hasOwn(a,'default'))props[key]=a.default;
  let content=sourceBlocks(s.source,ns,[...path,0]);
  // Source can retain a callout immediately after insertion, before any body text.
  // Materialize the canonical empty body without relaxing AST/XML admission.
  if(spec.ast_type==='relay.callout'&&!content.length)content.push(block(ns,[...path,0,0],'paragraph'));
  if(spec.ast_type==='relay.callout'&&props.title!==undefined){const title=String(props.title);delete props.title;content.unshift(block(ns,[...path,1],'relay.callout_title',inline(md.parseInline(title,{})[0]?.children||[])));}
  if(['relay.form_option','relay.agent_suggestion'].includes(spec.ast_type)){if(content.length>1||content[0]?.type!=='paragraph')throw new TypeError('Inline directive requires a paragraph');content=content[0]?.content||[];}
  if(spec.ast_type==='relay.entity_reference'){const input={...s.attrs};if(typeof input.id==='string'&&!input.id.startsWith('entity:'))input.id='entity:'+input.id;const body=s.source.startsWith('  ')?s.source.slice(2):s.source;const source=buildBlockEntityReferenceSource(input,body),parsed=parseEntityReferenceSource(source);Object.assign(props,{id:parsed.id,label:parsed.label,projection:parsed.projection,source});content=[];}
  return [block(ns,path,spec.ast_type,content,props)];
 });
}
function historicalQuestion(header,body,ns,path){
 const raw=header.match(/^<!--\s*relay:question\s+(.*?)\s*-->$/)[1],pattern=/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*("(?:\\.|[^"\\])*"|'[^']*')/g;
 const matches=[...raw.matchAll(pattern)];if(raw.replace(pattern,'').trim())throw new TypeError('Invalid historical question attributes');
 const decode=s=>s.replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&');
 const a={};for(const[,key,value]of matches){if(Object.hasOwn(a,key))throw new TypeError('Duplicate historical question attribute');a[key]=decode(value.slice(1,-1));}
 const type=a.type||'short_text',number=k=>{if(a[k]===undefined)return null;const value=JSON.parse(a[k]);if(typeof value!=='number'||!Number.isFinite(value))throw new TypeError('Invalid historical question number');return value;};
 let settings=a.settings?JSON.parse(a.settings):{};if(!settings||typeof settings!=='object'||Array.isArray(settings))throw new TypeError('Invalid historical question settings');
 for(const[key,value]of Object.entries(a)){if(['id','type','required','points','min','max','settings','label','options'].includes(key))continue;if(Object.hasOwn(settings,key))throw new TypeError('Duplicate historical setting');try{settings[key]=JSON.parse(value);}catch{settings[key]=value;}}
 const labels=[],options=[],optionPattern=['checkboxes','multi_select'].includes(type)?/^\s*-?\s*\[([xX ])\]\s*(.*)$/:/^\s*-?\s*\(([xX ])\)\s*(.*)$/;
 for(const rawLine of body.split('\n')){const line=rawLine.trim(),match=['multiple_choice','dropdown','checkboxes','single_select','multi_select'].includes(type)?line.match(optionPattern):null;if(match)options.push({text:match[2].trim(),correct:match[1].toLowerCase()==='x'});else if(line)labels.push(line);}
 let choices=options;if(a.options){const explicit=JSON.parse(a.options);if(!Array.isArray(explicit)||(options.length&&options.length!==explicit.length))throw new TypeError('Invalid historical question options');choices=explicit.map((o,i)=>({...options[i],...o}));}
 const label=labels.join('\n')||a.label||'',content=[block(ns,[...path,0],'paragraph',inline(md.parseInline(label,{})[0]?.children||[]))];
 for(const[o,index]of choices.map((o,i)=>[o,i+1])){const text=o.label||o.text||'',slug=text.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'').slice(0,80),extra=Object.fromEntries(Object.entries(o).filter(([k])=>!['id','label','text','correct','points','settings'].includes(k)));
 content.push(block(ns,[...path,index],'relay.form_option',inline(md.parseInline(text,{})[0]?.children||[]),{id:o.id||slug||'option-'+index,correct:o.correct??false,points:o.points??null,settings:{...(o.settings||{}),...extra}}));}
 return block(ns,path,'relay.form_question',content,{id:a.id,type,required:a.required==='true',points:number('points'),min:number('min'),max:number('max'),settings});
}
// A trailing unmarked source marker is authored identity, never a host HTML rewrite.
function headingSource(inlineToken){
 const tokens=[...(inlineToken.children||[])],last=tokens.at(-1);
 const raw=inlineToken.content.match(/\s+\{#([A-Za-z0-9][A-Za-z0-9_-]{0,127})\}$/u);
 const marker=last?.type==='text'?last.content.match(/\s+\{#([A-Za-z0-9][A-Za-z0-9_-]{0,127})\}$/u):null;
 if(!raw||!marker||raw[1]!==marker[1])return {tokens,headingId:null};
 const content=last.content.slice(0,-marker[0].length);
 if(content)tokens[tokens.length-1]={...last,content};else tokens.pop();
 return {tokens,headingId:raw[1]};
}
function markdownBlocks(tokens,ns,prefix){let at=0;
 const sequence=(end,path)=>{const nodes=[];while(at<tokens.length&&tokens[at].type!==end){const t=tokens[at++],p=[...path,nodes.length];let n;
  switch(t.type){
   case 'paragraph_open':{const i=tokens[at++];if(i.type!=='inline')throw new TypeError('Paragraph shape');at++;n=inlineMediaBlocks(i.children||[],ns,p,'paragraph');break;}
   case 'heading_open':{const i=tokens[at++];at++;const {tokens:content,headingId}=headingSource(i);n=inlineMediaBlocks(content,ns,p,'heading',{level:Number(t.tag.slice(1)),headingId});break;}
   case 'blockquote_open':n=block(ns,p,'quote',sequence('blockquote_close',p));break;
   case 'bullet_list_open':case 'ordered_list_open':{const children=sequence(t.type.replace('_open','_close'),p);let task=false;for(const item of children){const first=item.content[0]?.content[0];const m=first?.type==='text'?first.text.match(/^\[([ xX])\]\s+/):null;if(m){task=true;item.type='task_item';item.props={checked:m[1].toLowerCase()==='x',entityId:null};first.text=first.text.slice(m[0].length);if(!first.text)item.content[0].content.shift();}}
    if(task)for(const item of children){item.type='task_item';item.props??={checked:false,entityId:null};linkedTask(item);}
    n=block(ns,p,task?'task_list':'list',children,task?undefined:{kind:t.type==='ordered_list_open'?'ordered':'bullet',...(t.type==='ordered_list_open'?{start:Number(t.attrGet('start')||1)}:{})});break;}
   case 'list_item_open':{const content=sequence('list_item_close',p);if(content[0]?.type!=='paragraph')content.unshift(block(ns,[...p,'leading-paragraph'],'paragraph'));n=block(ns,p,'list_item',content);break;}
   case 'fence':case 'code_block':if(t.info.startsWith('relaymark-ast'))throw new TypeError('Mixed exact source');n=block(ns,p,'code',t.content?[{type:'text',text:t.content}]:[],{language:t.info||null});break;
   case 'html_block':n=block(ns,p,'paragraph',[{type:'text',text:t.content}]);break;
   case 'hr':n=block(ns,p,'horizontal_rule');break;
   case 'table_open':{const rows=[];let header=false;while(at<tokens.length&&tokens[at].type!=='table_close'){const rowToken=tokens[at++];if(rowToken.type==='thead_open'){header=true;continue;}if(['thead_close','tbody_open','tbody_close'].includes(rowToken.type)){if(rowToken.type==='thead_close')header=false;continue;}if(rowToken.type!=='tr_open')throw new TypeError('Table row');const rp=[...p,rows.length],cells=[];while(tokens[at].type!=='tr_close'){const cell=tokens[at++],cp=[...rp,cells.length],run=tokens[at++];at++;const align=cell.attrGet('style')?.match(/text-align:(left|center|right)/)?.[1]||null;cells.push(block(ns,cp,'table_cell',inlineMediaBlocks(run.children||[],ns,[...cp,0],'paragraph'),{header,colspan:1,rowspan:1,colwidth:null,align}));}at++;rows.push(block(ns,rp,'table_row',cells));}at++;n=block(ns,p,'table',rows);break;}
   default:throw new TypeError('Unsupported CommonMark block '+t.type);
  }
  nodes.push(...(Array.isArray(n)?n:[n]).map(value=>value.type==='paragraph'?historicalMedia(value):value));
 }if(end){if(tokens[at]?.type!==end)throw new TypeError('CommonMark nesting');at++;}return nodes;};return sequence(null,prefix);
}
// One finite source boundary normalization. Existing canonical AST/Yjs is never
// reconstructed during edits; these IDs are allocated once from the import namespace.
function inlineMediaBlocks(tokens,ns,path,type,props){
 const safe=inertInlineTokens(tokens)
 if(!safe.some(token=>token.type==='image'))return [block(ns,path,type,inline(safe),props)]
 const output=[],pending=[];let depth=0
 const nextPath=()=>output.length?[...path,output.length]:path
 const flush=()=>{if(pending.length){output.push(block(ns,nextPath(),type,inline(pending),props));pending.length=0}}
 for(const token of safe){
  if(token.type==='image'){
   if(depth)throw new TypeError('Marked or linked inline image requires explicit authored media semantics')
   flush();output.push(block(ns,nextPath(),'image',[],{src:token.attrGet('src'),alt:token.content,title:token.attrGet('title')||null}))
  }else{depth+=token.nesting;pending.push(token)}
 }
 flush();return output
}
function historicalMedia(n){
 const [leaf]=n.content;if(n.content.length!==1)return n;
 if(leaf.type==='text'){
  const video=leaf.text.match(/^::video\[\/v\/([0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\]$/u);
  if(video)return{id:n.id,type:'relay.video_embed',props:{videoId:video[1]},content:[]};
 }
 const url=leaf.type==='text'?leaf.text:leaf.type==='link'&&leaf.content.length===1&&leaf.content[0].type==='text'&&leaf.content[0].text===leaf.href?leaf.href:null;
 if(url&&safeImageSource(url)&&/^https:\/\/[^?#]+\.gif(?:[?#]|$)/iu.test(url))return{id:n.id,type:'image',props:{src:url,alt:'',title:null},content:[]};return n;
}
function literalImage(token){return `![${token.content}](${token.attrGet('src')}${token.attrGet('title')?' '+JSON.stringify(token.attrGet('title')):''})`;}
function inertInlineTokens(tokens){const output=[];for(let i=0;i<tokens.length;i++){
 const t=tokens[i];if(t.type==='link_open'&&!safeLinkHref(t.attrGet('href'))){let end=i+1;while(end<tokens.length&&tokens[end].type!=='link_close')end++;if(end===tokens.length)throw new TypeError('Invalid CommonMark link nesting');const label=inlineMarkdown(inline(tokens.slice(i+1,end)));output.push({type:'text',nesting:0,content:`[${label}](${t.attrGet('href')})`});i=end;}
 else if(t.type==='image'&&!safeImageSource(t.attrGet('src')))output.push({type:'text',nesting:0,content:literalImage(t)});else output.push(t);
 }return output;}
function inline(tokens){const output=[],marks=[];for(const t of inertInlineTokens(tokens)){if(t.nesting){const types={strong:'bold',em:'italic',s:'strike',link:'link'};const key=t.type.replace(/_(open|close)$/,'');const mark=types[key];if(!mark)throw new TypeError('Unsupported inline '+t.type);if(t.nesting===1)marks.push(mark==='link'?{type:'link',attrs:linkAttributes(t.attrGet('href'),{title:t.attrGet('title')})}:{type:mark});else marks.pop();continue;}
 if(t.type==='html_inline'&&/^<!--relay-task-draft:[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}-->$/u.test(t.content)){const previous=output.at(-1);if(previous?.type==='text'&&previous.text.endsWith(' ')){previous.text=previous.text.slice(0,-1);if(!previous.text)output.pop();}continue;}
 if(t.type==='relay_atom'){output.push(t.meta);continue;}
 if(t.type==='hardbreak'){output.push({type:'hard_break'});continue;}
 if(t.type==='code_inline'){output.push(mapInline({type:'text',text:t.content,marks:[{type:'code'}]}));continue;}
 if(!['text','softbreak','html_inline'].includes(t.type))throw new TypeError('Unsupported CommonMark inline '+t.type);
 const text=(t.type==='softbreak'?'\n':t.content).replace(/ ?<!--relay-task-draft:[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}-->/gu,'');
 if(text)output.push(mapInline({type:'text',text,...(marks.length?{marks:marks.toSorted((a,b)=>marksOrder.indexOf(a.type)-marksOrder.indexOf(b.type))}:{})}));
 }return output;}
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const attrs=a=>Object.entries(a).filter(([,v])=>v!=null).map(([k,v])=>' '+k+'="'+esc(v)+'"').join('');
const tag=(n,a,body)=>'<'+n+attrs(a)+'>'+body+'</'+n+'>';
export function renderDocument(ast){const pm=relayMarkToProseMirror(ast);const headings=new Map(authoredPMDestinations(pm).filter(entry=>entry.kind==='heading').map(entry=>[entry.source_path.join('.'),entry.name]));const render=(n,path)=>{const a=n.attrs||{},body=(n.content||[]).map((child,index)=>render(child,[...path,index])).join(''),{relaymarkId,...authored}=a,hydration={'data-authored':JSON.stringify(authored)};if(n.type==='text'){let text=esc(n.text);for(const m of(n.marks||[]).toReversed()){const names={bold:'strong',code:'code',italic:'em',strike:'s',underline:'u',highlight:'mark',superscript:'sup',subscript:'sub'};text=m.type==='link'?tag('a',renderedLinkAttributes(m.attrs),text):tag(names[m.type],{},text);}return text;}
 const generic=directiveNodeForName(n.type);if(generic){const{relaymarkId,...authored}=a;return tag('section',{'data-relay-directive':generic.type,'data-authored':JSON.stringify(authored)},body);}
 const names={paragraph:'p',blockquote:'blockquote',bulletList:'ul',orderedList:'ol',listItem:'li',taskList:'ul',taskItem:'li',table:'table',tableRow:'tr',tableCell:'td',tableHeader:'th',calloutTitle:'div',questionLabel:'legend'};
 if(n.type==='hardBreak')return '<br>';if(n.type==='horizontalRule')return '<hr>';if(n.type==='heading'){const name=headings.get(path.join('.'));return tag('h'+a.level,{id:name,'data-relay-heading-id':name,...hydration},body)};if(n.type==='codeBlock')return tag('pre',{},tag('code',{'data-language':a.language},body));if(n.type==='image')return '<img'+attrs({src:a.src,alt:a.alt,title:a.title,width:a.width,height:a.height})+'>';
 // Match maintained table column projection: first-row spans define columns;
 // zero/null widths remain unspecified, without importing a host minimum width.
 if(n.type==='table'){const cols=n.content[0].content.flatMap(cell=>Array.from({length:cell.attrs.colspan},(_,index)=>{const width=cell.attrs.colwidth?.[index];return '<col'+attrs({style:width?'width: '+width+'px':null})+'>';})).join('');return tag('table',{},tag('colgroup',{},cols)+body);}
 if(n.type==='callout')return tag('aside',{'data-relay-callout':a.tone,'data-emphasis':a.emphasis,...hydration},body);
 if(n.type==='questionBlock')return tag('fieldset',{'data-relay-question':a.id,'data-question-type':a.type,'data-required':a.required},body);
 if(n.type==='questionOption')return tag('div',{'data-relay-option':a.id},body);
 if(n.type==='relayReference')return tag('span',{'data-relay-reference':a.entityId,'data-source':a.source,...hydration},esc(a.label));if(n.type==='relayTag')return tag('span',{'data-relay-tag':a.id,'data-source':a.source,...hydration},esc(a.name));
 if(n.type==='relayEntityReference')return tag('div',{'data-relay-reference':a.entityRef,'data-projection':a.projection,'data-source':a.source,...hydration},esc(a.label));
 if(n.type==='videoEmbed')return tag('div',{'data-relay-video':a.videoId,...hydration},'');if(n.type==='agentSuggestion')return tag('aside',{'data-relay-suggestion':a.review,'data-kind':a.kind},esc(a.content));
 if(n.type==='relayDataView'){const{relaymarkId,...authored}=a;return tag('div',{'data-relay-data-view':a.source,'data-authored':JSON.stringify(authored)},esc(a.title||a.source));}
 if(n.type==='relayButton')return tag('button',{type:'button',disabled:true,'data-relay-kind':a.kind,'data-relay-target':a.target,...hydration},esc(a.label));if(n.type==='relayAnchor')return tag('span',{'data-relay-anchor':a.name,...hydration},'');if(n.type==='relayConnection')return tag('div',{'data-relay-connection':a.provider,...hydration},esc(a.provider));
 const extra=n.type==='calloutTitle'?{'data-callout-title':true}:n.type==='orderedList'?{start:a.start}:n.type==='taskList'?{'data-relay-task-list':true}:n.type==='taskItem'?{'data-checked':a.checked,'data-relay-task-item':a.entityId,...hydration}:['tableCell','tableHeader'].includes(n.type)?{colspan:a.colspan,rowspan:a.rowspan,colwidth:a.colwidth?.join(','),'data-align':a.align,style:a.align?'text-align: '+a.align:null}:{};
 if(!names[n.type])throw new TypeError('Unsupported authored renderer');return tag(names[n.type],extra,body);};return pm.content.map((node,index)=>render(node,[index])).join('');}
export function projectDocumentMarkdown(ast){valid(ast);return ast.blocks.map(markdown).join('\n\n')+'\n';}
function inlineMarkdown(nodes){return nodes.map(n=>{if(n.type==='text')return n.text.replace(/([\\`*_[\]{}])/g,'\\$1');if(n.type==='hard_break')return '  \n';if(['relay.entity_ref','relay.tag_ref'].includes(n.type))return n.props.source;if(n.type==='link')return '['+inlineMarkdown(n.content)+']('+n.href+(n.props?.title!==undefined&&n.props.title!==null?' '+JSON.stringify(n.props.title):'')+')';if(n.type==='code_span'){const text=n.content[0].text,f='`'.repeat(longestTicks(text)+1);return f+text+f;}const delimiter={strong:'**',emphasis:'*',strikethrough:'~~',underline:'<u>',highlight:'<mark>',superscript:'<sup>',subscript:'<sub>'}[n.type];if(!delimiter)throw new TypeError('Unsupported inline projection');return delimiter+inlineMarkdown(n.content)+(delimiter.startsWith('<')?delimiter.replace('<','</'):delimiter);}).join('');}
function markdown(n){const p=n.props||{};switch(n.type){case 'paragraph':case 'relay.callout_title':return inlineMarkdown(n.content);case 'heading':return '#'.repeat(p.level)+' '+inlineMarkdown(n.content)+(p.headingId?' {#'+p.headingId+'}':'');case 'quote':return n.content.map(markdown).join('\n\n').split('\n').map(x=>'> '+x).join('\n');case 'horizontal_rule':return '---';case 'code':{const text=n.content.map(x=>x.text||'').join(''),f='`'.repeat(Math.max(3,longestTicks(text)+1));return f+(p.language||'')+'\n'+text+(text.endsWith('\n')?'':'\n')+f;}
 case 'image':return '!['+(p.alt||'')+']('+p.src+')';case 'list':case 'task_list':return n.content.map((item,i)=>{const marker=n.type==='task_list'?(item.props.checked?'- [x] ':'- [ ] '):p.kind==='ordered'?(p.start+i)+'. ':'- ';const[first,...rest]=item.content.map(markdown).join('\n\n').split('\n');return marker+first+rest.map(x=>'\n'+' '.repeat(marker.length)+x).join('');}).join('\n');
 case 'table':{const rows=n.content.map(r=>'| '+r.content.map(c=>c.content.map(markdown).join(' ').replace(/\|/g,'\\|').replace(/\n/g,'<br>')).join(' | ')+' |');const separator='| '+n.content[0].content.map(c=>({left:':---',center:':---:',right:'---:'}[c.props.align]||'---')).join(' | ')+' |';return [rows[0],separator,...rows.slice(1)].join('\n');}
 case 'relay.form_option':return '- '+inlineMarkdown(n.content);case 'relay.paper_control':case 'relay.entity_reference':return p.source;
 default:{const generic=directiveNodeForType(n.type);if(generic)return '@'+directiveForType(generic.type).name+'('+Object.entries(p).map(([k,v])=>k+': '+JSON.stringify(v)).join(', ')+') {\n'+n.content.map(markdown).join('\n\n')+'\n}';const name={'relay.callout':'Callout','relay.form_question':'Question','relay.agent_suggestion':'AgentSuggestion','relay.data_view':'DataView','relay.video_embed':'Video'}[n.type];if(!name)throw new TypeError('Unsupported block projection');const body=n.type==='relay.agent_suggestion'?inlineMarkdown(n.content):n.content.map(markdown).join('\n\n');return '@'+name+'('+Object.entries(p).map(([k,v])=>k+': '+JSON.stringify(v)).join(', ')+') {\n'+body+'\n}';}
}}

import {importPublication} from './form-publication-import.js';
/** Finite saved publication conversion. Optional source is only the same immutable release body. */
export function importFormPublication(publication,options){return importPublication(publication,options,{importSource:importDocumentSource,identity:id,normalize:normalizeDocument});}

export {classifyContentEditReference,foldSourceReferences,partitionReviewedRecoveryDestinations} from './document-source-identities.js';

export {resolveContentEditTextItems,sourceSelectorWindows,validateSourceReadSelector} from './content-edit-witness.js';
