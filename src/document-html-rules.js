/** Shared inert canonical rendered HTML admission. No host authorization or DOM runtime. */
import {documentDepthLimit} from './document-adapter.js';
import {canonicalEditorSchema} from './editor-schema.js';
import {canonicalDirectiveNodes} from './document-directives.js';
import {linkDefaults,validateLinkAttributes} from './document-links.js';
const nodeShapes=new Map(canonicalEditorSchema.nodes.map(shape=>[shape.name,shape]));
const attr=(element,name)=>element.getAttribute(name);
const number=(element,name,fallback=null)=>{const value=attr(element,name);if(value===null)return fallback;if(!/^-?\d+$/.test(value))throw TypeError('Invalid HTML integer '+name);const result=Number(value);if(!Number.isSafeInteger(result))throw TypeError('Invalid HTML integer '+name);return result;};
const boolean=(element,name,fallback=false)=>{const value=attr(element,name);if(value===null)return fallback;if(!['true','false'].includes(value))throw TypeError('Invalid HTML boolean '+name);return value==='true';};
function attributes(name,element,legacy){
 const shape=nodeShapes.get(name),encoded=attr(element,'data-authored');
 const value=encoded===null?legacy(element):JSON.parse(encoded);
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(key=>!Object.hasOwn(shape.attrs||{},key)||key==='relaymarkId'))throw TypeError('Invalid authored HTML attributes '+name);
 if(encoded!==null&&!canonicalDirectiveNodes.some(shape=>shape.name===name)){
  for(const[key,actual]of Object.entries(legacy(element))){if(name==='heading'&&key==='headingId')continue;if(Object.hasOwn(value,key)&&JSON.stringify(value[key])!==JSON.stringify(actual))throw TypeError('Conflicting authored HTML attribute '+key);}
 }
 const identity=attr(element,'data-relaymark-id');return {...value,...(identity===null?{}:{relaymarkId:identity})};
}
function taskHTMLType(element,expected){const type=attr(element,'data-type');if(type!==null&&type!==expected)throw TypeError('Conflicting task HTML type');}
function taskHTMLAttributes(element){
 taskHTMLType(element,'taskItem');
 const canonical=attr(element,'data-relay-task-item'),native=attr(element,'data-entity-id');
 if(canonical!==null&&native!==null&&canonical!==native)throw TypeError('Conflicting task HTML entity identity');
 const checked=attr(element,'data-checked');
 return {checked:checked===''&&attr(element,'data-type')==='taskItem'?true:boolean(element,'data-checked'),entityId:canonical??native};
}
function taskHTMLContent(element){
 const children=[...element.children];
 // The maintained TipTap node view wraps only its authored body in a div;
 // its sibling label/input is presentation, never authored task content.
 return attr(element,'data-type')==='taskItem'&&children.length===2&&children[0].localName==='label'&&children[1].localName==='div'?children[1]:element;
}
const defs=[];
function node(name,tag,allowed=[],legacy=()=>({}),options={}){defs.push({name,tag,allowed:['data-authored','data-relaymark-id',...allowed],getAttrs:element=>attributes(name,element,legacy),...options});}
node('paragraph','p:not([data-callout-title])');node('blockquote','blockquote');node('listItem','li:not([data-relay-task-item]):not([data-checked]):not([data-type="taskItem"])');
node('taskList','ul[data-relay-task-list],ul[data-type="taskList"]',['data-relay-task-list','data-type'],e=>{taskHTMLType(e,'taskList');return {};});node('bulletList','ul:not([data-relay-task-list]):not([data-type="taskList"])');
node('orderedList','ol',['start'],e=>({start:number(e,'start',1)}));
node('taskItem','li[data-checked],li[data-type="taskItem"]',['data-checked','data-relay-task-item','data-entity-id','data-type'],taskHTMLAttributes,{contentElement:taskHTMLContent});
for(let level=1;level<=6;level++)node('heading','h'+level,['id','data-relay-heading-id'],e=>({level,headingId:attr(e,'data-relay-heading-id')||attr(e,'id')}));
node('hardBreak','br');node('horizontalRule','hr');
node('codeBlock','pre',[],e=>({language:attr(e.firstElementChild,'data-language')}),{preserveWhitespace:'full',contentElement:'code'});
node('image','img',['src','alt','title','width','height'],e=>({src:attr(e,'src'),alt:attr(e,'alt'),title:attr(e,'title'),width:number(e,'width'),height:number(e,'height')}));
node('table','table',['style']);node('tableRow','tr');
for(const[name,tag]of [['tableCell','td'],['tableHeader','th']])node(name,tag,['colspan','rowspan','colwidth','data-align','style'],e=>({colspan:number(e,'colspan',1),rowspan:number(e,'rowspan',1),colwidth:attr(e,'colwidth')===null?null:attr(e,'colwidth').split(',').map(value=>{if(!/^\d+$/.test(value))throw TypeError('Invalid HTML column width');return Number(value);}),align:attr(e,'data-align')}));
node('callout','aside[data-relay-callout]',['data-relay-callout','data-emphasis'],e=>({tone:attr(e,'data-relay-callout'),emphasis:attr(e,'data-emphasis')||'soft'}));
node('calloutTitle','div[data-callout-title]',['data-callout-title']);
node('callout','section[data-relay-callout]',['data-relay-callout','data-tone','data-emphasis','class'],e=>{if(attr(e,'data-relay-callout')!=='')throw TypeError('Conflicting callout HTML representation');return {tone:attr(e,'data-tone')||'neutral',emphasis:attr(e,'data-emphasis')||'soft'};},{presentationClass:'relay-callout'});
node('calloutTitle','p[data-callout-title]',['data-callout-title','class'],()=>({}),{presentationClass:'relay-callout-title'});
node('questionBlock','fieldset[data-relay-question]',['data-relay-question','data-question-type','data-required'],e=>({id:attr(e,'data-relay-question'),type:attr(e,'data-question-type'),required:boolean(e,'data-required')}));
node('questionLabel','legend');
node('questionOption','div[data-relay-option]',['data-relay-option'],e=>({id:attr(e,'data-relay-option')}));
function questionSettings(element){const raw=attr(element,'data-settings'),value=raw===null?{}:JSON.parse(raw);if(!value||typeof value!=='object'||Array.isArray(value))throw TypeError('Invalid retained question settings');return value;}
function questionNumber(element,name){const raw=attr(element,name);if(raw===null)return null;if(!/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$/.test(raw)||!Number.isFinite(Number(raw)))throw TypeError('Invalid retained question number');return Number(raw);}
node('questionBlock','div[data-question-block]',['data-question-block','class','data-id','data-type','data-required','data-points','data-min','data-max','data-settings'],e=>({id:attr(e,'data-id'),type:attr(e,'data-type')||'short_text',required:boolean(e,'data-required'),points:questionNumber(e,'data-points'),min:questionNumber(e,'data-min'),max:questionNumber(e,'data-max'),settings:questionSettings(e)}),{presentationClass:'question-block-paper',completeAuthoredFields:true});
node('questionLabel','div[data-question-label]',['data-question-label','class'],()=>({}),{presentationClass:'question-block-content'});
node('questionOption','div[data-question-option]',['data-question-option','data-id','data-correct','data-points','data-settings'],e=>({id:attr(e,'data-id'),correct:boolean(e,'data-correct'),points:questionNumber(e,'data-points'),settings:questionSettings(e)}),{completeAuthoredFields:true});

node('relayReference','span[data-relay-reference]',['data-relay-reference','data-source'],e=>({entityId:attr(e,'data-relay-reference'),source:attr(e,'data-source'),label:e.textContent}),{display:attrs=>attrs.label});
node('relayEntityReference','div[data-relay-reference]',['data-relay-reference','data-projection','data-source'],e=>({entityRef:attr(e,'data-relay-reference'),projection:attr(e,'data-projection'),source:attr(e,'data-source'),label:e.textContent}),{display:attrs=>attrs.label});
node('relayTag','span[data-relay-tag]',['data-relay-tag','data-source'],e=>({id:attr(e,'data-relay-tag'),source:attr(e,'data-source'),name:e.textContent}),{display:attrs=>attrs.name});
node('videoEmbed','div[data-relay-video]',['data-relay-video'],e=>({videoId:attr(e,'data-relay-video')}),{display:()=>''});
node('agentSuggestion','aside[data-relay-suggestion]',['data-relay-suggestion','data-kind'],e=>({review:attr(e,'data-relay-suggestion'),kind:attr(e,'data-kind'),content:e.textContent}),{display:attrs=>attrs.content});
node('relayDataView','div[data-relay-data-view]',['data-relay-data-view'],e=>({source:attr(e,'data-relay-data-view')}),{display:attrs=>attrs.title||attrs.source});
node('relayButton','button[data-relay-kind]',['type','disabled','data-relay-kind','data-relay-target'],e=>({kind:attr(e,'data-relay-kind'),target:attr(e,'data-relay-target'),label:e.textContent}),{display:attrs=>attrs.label});
node('relayAnchor','span[data-relay-anchor]',['data-relay-anchor'],e=>({name:attr(e,'data-relay-anchor')}),{display:()=>''});
node('relayConnection','div[data-relay-connection]',['data-relay-connection'],e=>({provider:attr(e,'data-relay-connection')}),{display:attrs=>attrs.provider});
for(const shape of canonicalDirectiveNodes)node(shape.name,`section[data-relay-directive="${shape.type}"]`,['data-relay-directive'],()=>{throw TypeError('Missing authored directive HTML attributes');});
const marks=[];
for(const[name,tag]of [['bold','strong'],['italic','em'],['strike','s'],['underline','u'],['highlight','mark'],['superscript','sup'],['subscript','sub'],['code','code']])marks.push({name,tag,allowed:[],getAttrs:()=>({})});
marks.push({name:'link',tag:'a',allowed:['href','target','rel','class','title'],getAttrs:element=>{const result={...linkDefaults,href:attr(element,'href')};for(const name of ['target','rel','class','title'])if(element.hasAttribute(name))result[name]=attr(element,name);validateLinkAttributes(result);return result;}});
export function canonicalHTMLNodeRules(name){return defs.filter(def=>def.name===name).map(({tag,getAttrs,contentElement,preserveWhitespace})=>({tag,getAttrs,priority:60,...(contentElement?{contentElement}:{}),...(preserveWhitespace?{preserveWhitespace}: {})}));}
export function canonicalHTMLMarkRules(name){return marks.filter(def=>def.name===name).map(({tag,getAttrs})=>({tag,getAttrs,priority:60}));}
/** Strict finite-source coverage. The parser may not silently erase source nodes/attrs. */
export function inspectCanonicalHTML(root){
 const sourceNodes=[],sourceMarks=[],normalizations=[];let sourceText='';
 function visit(element,depth=0){
  if(depth>documentDepthLimit()+canonicalEditorSchema.marks.length+2)throw TypeError('Oversized retained HTML');
  for(const child of element.childNodes){
   if(child.nodeType===3){sourceText+=child.textContent;continue;}
   if(child.nodeType!==1)throw TypeError('Unsupported retained HTML node');
   const parent=element.localName,name=child.localName;
   // Maintained HTML table serialization includes these purely structural wrappers.
   if((name==='tbody'&&parent==='table')||(name==='colgroup'&&parent==='table')||(name==='col'&&parent==='colgroup')){
    const allowed=name==='col'?['style']:[];checkAttributes(child,allowed);
    if(name==='col'&&child.hasAttribute('style')&&!tableSizeStyle(attr(child,'style')))throw TypeError('Invalid retained table width');
    if(name==='col'&&child.childNodes.length)throw TypeError('Invalid retained table column');
    visit(child,depth+1);continue;
   }
   if(name==='code'&&parent==='pre'){
    checkAttributes(child,['data-language']);if([...child.childNodes].some(node=>node.nodeType!==3))throw TypeError('Invalid retained code content');sourceText+=child.textContent;continue;
   }
   const definition=defs.find(def=>child.matches(def.tag));
   const mark=definition?null:marks.find(def=>child.matches(def.tag));
   if(!definition&&!mark)throw TypeError('Unsupported retained HTML element '+name);
   const rule=definition||mark;checkAttributes(child,rule.allowed);if(rule.presentationClass&&child.hasAttribute('class')&&attr(child,'class')!==rule.presentationClass)throw TypeError('Invalid retained presentation class');const attrs=rule.getAttrs(child);
   if(definition){
    sourceNodes.push({name:definition.name,attributes:attrs,allowsImplicitParagraph:[...child.childNodes].some(node=>node.nodeType===3&&node.textContent.trim()||node.nodeType===1&&marks.some(mark=>node.matches(mark.tag)))});
    const omitted={questionBlock:['points','min','max','settings'],questionOption:['correct','points','settings'],agentSuggestion:['confidence','evidence']}[definition.name];
    if(omitted&&!definition.completeAuthoredFields&&!child.hasAttribute('data-authored'))normalizations.push({operation:'historical_html_absent_fields',node:definition.name,source_node_index:sourceNodes.length-1,attributes:omitted,source:'retained_rendered_projection'});
    if(definition.name==='table')verifyTableColumns(child);
    if(definition.display){
     if([...child.childNodes].some(node=>node.nodeType!==3)||child.textContent!==definition.display(attrs))throw TypeError('Invalid retained atom display');
     continue;
    }
    if(['tableCell','tableHeader'].includes(definition.name)&&child.hasAttribute('style')&&attr(child,'style')!=='text-align: '+attrs.align)throw TypeError('Invalid retained cell style');
   }else sourceMarks.push({name:mark.name,attributes:attrs,text:child.textContent});
   visit(child,depth+1);
  }
 }
 visit(root);return {sourceNodes,sourceMarks,sourceText,normalizations};
}
function checkAttributes(element,allowed){for(const attribute of element.attributes)if(!allowed.includes(attribute.name))throw TypeError('Unsupported retained HTML attribute '+attribute.name);}

export function canonicalHTMLElementAttributes(name,element){const rule=[...defs,...marks].find(def=>def.name===name&&element.matches(def.tag));return rule?rule.getAttrs(element):null;}

// The maintained table serializer emits one finite sizing declaration. It is
// presentation evidence; authored column widths remain the cell attributes.
function tableSizeStyle(value){const match=/^(width|min-width): ([1-9]\d*)px;?$/.exec(value||'');if(!match)return null;const size=Number(match[2]);return Number.isSafeInteger(size)?{kind:match[1],size}:null;}
function verifyTableColumns(table){
 const groups=[...table.children].filter(element=>element.localName==='colgroup');
 if(groups.length>1)throw TypeError('Duplicate retained table columns');
 if(!groups.length){if(table.hasAttribute('style'))throw TypeError('Missing retained table sizing evidence');return;}
 const row=table.querySelector('tr');if(!row)throw TypeError('Missing retained table row');
 const expected=[...row.children].flatMap(cell=>{
  if(!['td','th'].includes(cell.localName))throw TypeError('Invalid retained table row');
  const rule=defs.find(def=>def.name===(cell.localName==='td'?'tableCell':'tableHeader'));
  const attrs=rule.getAttrs(cell);
  return Array.from({length:attrs.colspan},(_,index)=>attrs.colwidth?.[index]||null);
 });
 const columns=[...groups[0].children];
 if(columns.length!==expected.length)throw TypeError('Retained table width evidence was not preserved');
 let total=0,fixed=true;const maintainedSizing=table.hasAttribute('style');
 for(let index=0;index<columns.length;index++){
  const column=columns[index],style=attr(column,'style'),size=tableSizeStyle(style),width=expected[index];
  if(column.localName!=='col'||(width!==null?(!size||size.kind!=='width'||size.size!==(maintainedSizing?Math.max(width,25):width)):style!==null&&(!maintainedSizing||!size||size.kind!=='min-width'||size.size!==25)))throw TypeError('Retained table width evidence was not preserved');
  if(width===null)fixed=false;
  total+=maintainedSizing?(width||25):(size?.size||0);
 }
 if(table.hasAttribute('style')){
  const style=tableSizeStyle(attr(table,'style'));
  if(!style||style.kind!==(fixed?'width':'min-width')||style.size!==total||columns.some(column=>!tableSizeStyle(attr(column,'style'))))throw TypeError('Retained table aggregate width evidence was not preserved');
 }
}
