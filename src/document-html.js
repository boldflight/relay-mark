/** Finite retained HTML import through maintained DOM + canonical PM grammar.
 * No browser, network, private draft, host permissions or HTML-to-Markdown path. */
import {DOMParser as HTMLDOMParser} from 'linkedom/worker';
import {DOMParser as PMDOMParser} from 'prosemirror-model';
import {createCanonicalEditorSchema} from './editor-model.js';
import {inspectCanonicalHTML} from './document-html-rules.js';
import {proseMirrorToSnapshot} from './document-snapshot.js';
import {importDocumentSnapshot,utf8Bytes} from './document-source.js';
import {stableStringify} from './canonical-json.js';
const schema=createCanonicalEditorSchema();
export function importDocumentHTML({html,namespace}){
 const originalHTML=html;
 if(html===null)html='';
 if(typeof html!=='string'||html.length>4194304||utf8Bytes(html).byteLength>4194304||typeof namespace!=='string'||!namespace)throw TypeError('Invalid retained HTML input');
 const dom=new HTMLDOMParser().parseFromString('<html><head></head><body>'+html+'</body></html>','text/html');
 if(dom.documentElement.children.length!==2||dom.head.childNodes.length||[...dom.documentElement.children].some(element=>!['head','body'].includes(element.localName)))throw TypeError('Invalid retained HTML envelope');
 const {sourceNodes,sourceMarks,sourceText,normalizations}=inspectCanonicalHTML(dom.body);
 const document=PMDOMParser.fromSchema(schema).parse(dom.body,{preserveWhitespace:'full'});document.check();
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
 const imported=importDocumentSnapshot(proseMirrorToSnapshot(document.toJSON()),{namespace});
 return {...imported,normalizations:[...(html===''?[{operation:'empty_retained_html',source_value:originalHTML}]:[]),...normalizations,...imported.normalizations,{operation:'import_retained_html',source:'description_html'}]};
}
