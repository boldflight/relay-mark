/** Clipboard HTML written by other applications (browsers, word processors,
 * notes apps), read with the web editor's own paste rules: the parseHTML rules
 * of the TipTap 3.31 extensions the web editor uses. Relay's own canonical
 * clipboard keeps its exact import in document-html.js. The parsed content is
 * canonical; nothing here grants source, media or edit authority. */
import {DOMParser as PMDOMParser,Schema} from 'prosemirror-model';
import {canonicalEditorSchema} from './editor-schema.js';
import {linkDefaults,safeImageSource,safeLinkHref} from './document-links.js';

const integer=(element,name,fallback)=>{const value=parseInt(element.getAttribute(name)??'',10);return Number.isSafeInteger(value)&&value>0?value:fallback;};
const orderedListTypes=new Set(['1','a','A','i','I']);
// @tiptap/extension-table parseColwidth: an explicit colwidth attribute.
const colwidth=element=>{const value=element.getAttribute('colwidth');if(!value)return null;const widths=value.split(',').map(width=>parseInt(width,10));return widths.every(width=>Number.isSafeInteger(width)&&width>0)?widths:null;};
const cell=element=>({colspan:integer(element,'colspan',1),rowspan:integer(element,'rowspan',1),colwidth:colwidth(element)});

const nodeRules={
 paragraph:[{tag:'p'}],
 blockquote:[{tag:'blockquote'}],
 heading:[1,2,3,4,5,6].map(level=>({tag:'h'+level,attrs:{level}})),
 bulletList:[{tag:'ul'}],
 orderedList:[{tag:'ol',getAttrs:element=>({start:element.hasAttribute('start')?integer(element,'start',1):1,
  type:orderedListTypes.has(element.getAttribute('type'))?element.getAttribute('type'):null})}],
 listItem:[{tag:'li'}],
 taskList:[{tag:'ul[data-type="taskList"]',priority:51}],
 taskItem:[{tag:'li[data-type="taskItem"]',priority:51,getAttrs:element=>{const checked=element.getAttribute('data-checked');return {checked:checked===''||checked==='true'};}}],
 codeBlock:[{tag:'pre',preserveWhitespace:'full',getAttrs:element=>{
  const language=[...(element.firstElementChild?.classList??[])].find(name=>name.startsWith('language-'));
  return {language:language?language.slice('language-'.length):null};
 }}],
 hardBreak:[{tag:'br'}],
 horizontalRule:[{tag:'hr'}],
 // Only sources a paper may keep: HTTPS or durable host media, never data: URIs.
 image:[{tag:'img[src]:not([src^="data:"])',getAttrs:element=>{
  const src=element.getAttribute('src');
  return safeImageSource(src)?{src,alt:element.getAttribute('alt'),title:element.getAttribute('title')}:false;
 }}],
 table:[{tag:'table'}],
 tableRow:[{tag:'tr'}],
 tableCell:[{tag:'td',getAttrs:cell}],
 tableHeader:[{tag:'th',getAttrs:cell}],
};
const markRules=name=>({
 bold:[{tag:'strong'},{tag:'b',getAttrs:element=>element.style.fontWeight!=='normal'&&null},
  {style:'font-weight=400',clearMark:mark=>mark.type.name===name},
  {style:'font-weight',getAttrs:value=>/^(bold(er)?|[5-9]\d{2,})$/.test(value)&&null}],
 italic:[{tag:'em'},{tag:'i',getAttrs:element=>element.style.fontStyle!=='normal'&&null},
  {style:'font-style=normal',clearMark:mark=>mark.type.name===name},{style:'font-style=italic'}],
 strike:[{tag:'s'},{tag:'del'},{tag:'strike'},
  {style:'text-decoration',consuming:false,getAttrs:value=>value.includes('line-through')?{}:false}],
 underline:[{tag:'u'},{style:'text-decoration',consuming:false,getAttrs:value=>value.includes('underline')?{}:false}],
 code:[{tag:'code'}],
 highlight:[{tag:'mark'}],
 superscript:[{tag:'sup'},{style:'vertical-align',getAttrs:value=>value==='super'?null:false}],
 subscript:[{tag:'sub'},{style:'vertical-align',getAttrs:value=>value==='sub'?null:false}],
 // Links keep the canonical attributes; unsafe destinations drop the mark, not the text.
 link:[{tag:'a[href]',getAttrs:element=>{const href=element.getAttribute('href');return safeLinkHref(href)?{...linkDefaults,href}:false;}}],
})[name]??[];

const nodes=Object.fromEntries(canonicalEditorSchema.nodes.map(({name,markSet,...spec})=>[
 name,{...spec,parseDOM:nodeRules[name]??[],...(markSet===null?{}:{marks:markSet.join(' ')})}
]));
const marks=Object.fromEntries(canonicalEditorSchema.marks.map(({name,excludes,...spec})=>[
 name,{...spec,parseDOM:markRules(name),excludes:excludes.join(' ')}
]));
const foreignParser=PMDOMParser.fromSchema(new Schema({topNode:canonicalEditorSchema.top,nodes,marks}));

/** The parsed slice as JSON, to be read into the canonical schema. */
export function parseForeignClipboard(body){
 return foreignParser.parseSlice(body).toJSON();
}
