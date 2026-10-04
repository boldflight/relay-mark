/** Canonical source: maintained CommonMark + directives, exact relaymark-ast interchange. */
import MarkdownIt from 'markdown-it';
import {sha256} from '@noble/hashes/sha2.js';
import {bytesToHex} from '@noble/hashes/utils.js';
import {proseMirrorToRelayMark,relayMarkToProseMirror} from './document-adapter.js';
import {mapInline} from './document-inline.js';
import {parseAtomSource} from './document-atoms.js';
import {parseAttributes} from './attributes.js';
import {directiveNodeForName,directiveNodeForType} from './document-directives.js';
import {directiveForName,directiveForType} from './registry.js';
import {parsePaperControlSource} from './document-controls.js';
import {parseEntityReferenceSource} from './document-reference.js';
const md=new MarkdownIt({html:false,linkify:false,typographer:false});
const marksOrder=['link','bold','code','italic','strike','underline','highlight','superscript','subscript'];
function valid(ast){relayMarkToProseMirror(ast);return ast;}
function id(namespace,path){const hash=bytesToHex(sha256(new TextEncoder().encode(namespace+'\0'+path.join('.'))));return 'b'+hash.slice(0,12)+'4'+hash.slice(13,16)+'8'+hash.slice(17,32);}
function block(ns,path,type,content=[],props){return {id:id(ns,path),type,...(props?{props}:{}),content};}
function longestTicks(s){return Math.max(0,...Array.from(s.matchAll(/`+/g),m=>m[0].length));}
export function serializeDocument(ast){valid(ast);const json=JSON.stringify(ast),f='`'.repeat(Math.max(3,longestTicks(json)+1));return `${f}relaymark-ast\n${json}\n${f}\n`;}
export function parseDocument(source,{namespace}={}){
 if(typeof source!=='string')throw new TypeError('Invalid authored source');source=source.replace(/\r\n?/g,'\n');
 const exact=source.match(/^(`{3,})relaymark-ast\n([\s\S]*?)\n\1\s*$/);
 if(exact)return valid(JSON.parse(exact[2]));
 namespace??=source;if(typeof namespace!=='string')throw new TypeError('Invalid import namespace');
 let frontmatter;const fm=source.match(/^---\n([\s\S]*?)\n---(?:\n|$)/);if(fm){frontmatter={};for(const line of fm[1].split('\n')){const m=line.match(/^([^:]+):\s*(.*)$/);if(!m)throw new TypeError('Invalid frontmatter');try{frontmatter[m[1]]=JSON.parse(m[2]);}catch{frontmatter[m[1]]=m[2];}}source=source.slice(fm[0].length);}
 const blocks=sourceBlocks(source,namespace,[]);if(!blocks.length)blocks.push(block(namespace,[0],'paragraph'));
 return valid({type:'relaymark.document',...(frontmatter?{frontmatter}:{}),blocks});
}
function sourceBlocks(source,ns,prefix){
 const segments=[];let plain=[],directive=null,fence=null;
 const flush=()=>{if(plain.length){segments.push({kind:'markdown',source:plain.join('\n')});plain=[];}};
 const append=line=>directive?directive.body.push(line):plain.push(line);
 for(const line of source.split('\n')){const t=line.trim();
  if(fence){append(line);if(new RegExp('^'+fence[0]+'{'+fence.length+',}\\s*$').test(t))fence=null;continue;}
  const f=t.match(/^(`{3,}|~{3,})/);if(f){fence=f[0];append(line);continue;}
  const header=t.match(/^@([A-Z][A-Za-z0-9]*)(?:\((.*)\))?\s*\{\s*$/);
  if(directive?.historical){if(/^<!--\s*\/relay:question\s*-->$/.test(t)){segments.push({...directive,kind:'historical_question',source:directive.body.join('\n')});directive=null;}else directive.body.push(line);continue;}
  if(directive){if(t==='}'&&--directive.depth===0){segments.push({...directive,kind:'directive',source:directive.body.join('\n')});directive=null;}else{if(header)directive.depth++;directive.body.push(line);}continue;}
  if(/^<!--\s*relay:question\s+.*?\s*-->$/.test(t)){flush();directive={historical:true,header:t,body:[]};continue;}
  if(/^<!--\s*\/relay:question\s*-->$/.test(t))throw new TypeError('Unexpected historical question closing');
  if(header){flush();directive={name:header[1],attrs:parseAttributes(header[2]||''),header:t,body:[],depth:1};continue;}
  const control=parsePaperControlSource(t);if(control){flush();segments.push({kind:'control',control});continue;}
  if(t==='}')throw new TypeError('Unexpected directive closing');plain.push(line);
 }
 if(directive)throw new TypeError('Missing directive closing');flush();
 return segments.flatMap((s,index)=>{const path=[...prefix,index];if(s.kind==='markdown')return markdownBlocks(md.parse(s.source,{}),ns,path);if(s.kind==='historical_question')return [historicalQuestion(s.header,s.source,ns,path)];if(s.kind==='control')return [block(ns,path,'relay.paper_control',[],{control:s.control.control,...s.control.attrs,source:s.control.source})];
  const spec=directiveForName(s.name);if(!spec)throw new TypeError('Unknown directive');const props={...s.attrs};for(const [key,a]of Object.entries(spec.attributes||{}))if(props[key]===undefined&&Object.hasOwn(a,'default'))props[key]=a.default;
  let content=sourceBlocks(s.source,ns,[...path,0]);if(spec.ast_type==='relay.callout'&&props.title!==undefined){const title=String(props.title);delete props.title;content.unshift(block(ns,[...path,1],'relay.callout_title',inline(md.parseInline(title,{})[0]?.children||[])));}
  if(['relay.form_option','relay.agent_suggestion'].includes(spec.ast_type)){if(content.length>1||content[0]?.type!=='paragraph')throw new TypeError('Inline directive requires a paragraph');content=content[0]?.content||[];}
  if(spec.ast_type==='relay.entity_reference'){const source=s.header+'\n'+s.source+'\n}';const parsed=parseEntityReferenceSource(source);if(!parsed)throw new TypeError('Invalid entity reference source');props.source=source;content=[];}
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
 const labels=[],options=[],optionPattern=type==='checkboxes'?/^\s*-?\s*\[([xX ])\]\s*(.*)$/:/^\s*-?\s*\(([xX ])\)\s*(.*)$/;
 for(const rawLine of body.split('\n')){const line=rawLine.trim(),match=['multiple_choice','dropdown','checkboxes'].includes(type)?line.match(optionPattern):null;if(match)options.push({text:match[2].trim(),correct:match[1].toLowerCase()==='x'});else if(line)labels.push(line);}
 let choices=options;if(a.options){const explicit=JSON.parse(a.options);if(!Array.isArray(explicit)||(options.length&&options.length!==explicit.length))throw new TypeError('Invalid historical question options');choices=explicit.map((o,i)=>({...options[i],...o}));}
 const label=labels.join('\n')||a.label||'',content=[block(ns,[...path,0],'paragraph',inline(md.parseInline(label,{})[0]?.children||[]))];
 for(const[o,index]of choices.map((o,i)=>[o,i+1])){const text=o.label||o.text||'',slug=text.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'').slice(0,80),extra=Object.fromEntries(Object.entries(o).filter(([k])=>!['id','label','text','correct','points','settings'].includes(k)));
 content.push(block(ns,[...path,index],'relay.form_option',inline(md.parseInline(text,{})[0]?.children||[]),{id:o.id||slug||'option-'+index,correct:o.correct??false,points:o.points??null,settings:{...(o.settings||{}),...extra}}));}
 return block(ns,path,'relay.form_question',content,{id:a.id,type,required:a.required==='true',points:number('points'),min:number('min'),max:number('max'),settings});
}
function markdownBlocks(tokens,ns,prefix){let at=0;
 const sequence=(end,path)=>{const nodes=[];while(at<tokens.length&&tokens[at].type!==end){const t=tokens[at++],p=[...path,nodes.length];let n;
  switch(t.type){
   case 'paragraph_open':{const i=tokens[at++];if(i.type!=='inline')throw new TypeError('Paragraph shape');at++;if(i.children?.length===1&&i.children[0].type==='image'){const im=i.children[0];n=block(ns,p,'image',[],{src:im.attrGet('src'),alt:im.content,title:im.attrGet('title')||null});}else n=block(ns,p,'paragraph',inline(i.children||[]));break;}
   case 'heading_open':{const i=tokens[at++];at++;n=block(ns,p,'heading',inline(i.children||[]),{level:Number(t.tag.slice(1)),headingId:null});break;}
   case 'blockquote_open':n=block(ns,p,'quote',sequence('blockquote_close',p));break;
   case 'bullet_list_open':case 'ordered_list_open':{const children=sequence(t.type.replace('_open','_close'),p);let task=false;for(const item of children){const first=item.content[0]?.content[0];const m=first?.type==='text'?first.text.match(/^\[([ xX])\]\s+/):null;if(m){task=true;item.type='task_item';item.props={checked:m[1].toLowerCase()==='x',entityId:null};first.text=first.text.slice(m[0].length);if(!first.text)item.content[0].content.shift();}}
    if(task)for(const item of children){item.type='task_item';item.props??={checked:false,entityId:null};}
    n=block(ns,p,task?'task_list':'list',children,task?undefined:{kind:t.type==='ordered_list_open'?'ordered':'bullet',...(t.type==='ordered_list_open'?{start:Number(t.attrGet('start')||1)}:{})});break;}
   case 'list_item_open':n=block(ns,p,'list_item',sequence('list_item_close',p));break;
   case 'fence':case 'code_block':if(t.info.startsWith('relaymark-ast'))throw new TypeError('Mixed exact source');n=block(ns,p,'code',t.content?[{type:'text',text:t.content}]:[],{language:t.info||null});break;
   case 'hr':n=block(ns,p,'horizontal_rule');break;
   case 'table_open':{const rows=[];let header=false;while(at<tokens.length&&tokens[at].type!=='table_close'){const rowToken=tokens[at++];if(rowToken.type==='thead_open'){header=true;continue;}if(['thead_close','tbody_open','tbody_close'].includes(rowToken.type)){if(rowToken.type==='thead_close')header=false;continue;}if(rowToken.type!=='tr_open')throw new TypeError('Table row');const rp=[...p,rows.length],cells=[];while(tokens[at].type!=='tr_close'){const cell=tokens[at++],cp=[...rp,cells.length],run=tokens[at++];at++;const align=cell.attrGet('style')?.match(/text-align:(left|center|right)/)?.[1]||null;cells.push(block(ns,cp,'table_cell',[block(ns,[...cp,0],'paragraph',inline(run.children||[]))],{header,colspan:1,rowspan:1,colwidth:null,align}));}at++;rows.push(block(ns,rp,'table_row',cells));}at++;n=block(ns,p,'table',rows);break;}
   default:throw new TypeError('Unsupported CommonMark block '+t.type);
  }
  nodes.push(n);
 }if(end){if(tokens[at]?.type!==end)throw new TypeError('CommonMark nesting');at++;}return nodes;};return sequence(null,prefix);
}
function inline(tokens){const output=[],marks=[];for(const t of tokens){if(t.nesting){const types={strong:'bold',em:'italic',s:'strike',link:'link'};const key=t.type.replace(/_(open|close)$/,'');const mark=types[key];if(!mark)throw new TypeError('Unsupported inline '+t.type);if(t.nesting===1)marks.push(mark==='link'?{type:'link',attrs:{href:t.attrGet('href'),target:'_blank',rel:'noopener noreferrer nofollow',class:null,title:null}}:{type:mark});else marks.pop();continue;}
 if(t.type==='hardbreak'){if(marks.length)throw new TypeError('Marked hard break');output.push({type:'hard_break'});continue;}
 if(t.type==='code_inline'){output.push(mapInline({type:'text',text:t.content,marks:[{type:'code'}]}));continue;}
 if(!['text','softbreak'].includes(t.type))throw new TypeError('Unsupported CommonMark inline '+t.type);
 const text=t.type==='softbreak'?'\n':t.content;for(const piece of text.split(/(\[\[[^\]\r\n]+\]\])/).filter(Boolean)){if(piece.startsWith('[[')){const atom=parseAtomSource(piece);if(!atom||marks.length)throw new TypeError('Invalid or marked reference');output.push(atom);}else output.push(mapInline({type:'text',text:piece,...(marks.length?{marks:marks.toSorted((a,b)=>marksOrder.indexOf(a.type)-marksOrder.indexOf(b.type))}:{})}));}
 }return output;}
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const attrs=a=>Object.entries(a).filter(([,v])=>v!=null).map(([k,v])=>' '+k+'="'+esc(v)+'"').join('');
const tag=(n,a,body)=>'<'+n+attrs(a)+'>'+body+'</'+n+'>';
export function renderDocument(ast){const pm=relayMarkToProseMirror(ast);const render=n=>{const a=n.attrs||{},body=(n.content||[]).map(render).join('');if(n.type==='text'){let text=esc(n.text);for(const m of(n.marks||[]).toReversed()){const names={bold:'strong',code:'code',italic:'em',strike:'s',underline:'u',highlight:'mark',superscript:'sup',subscript:'sub'};text=m.type==='link'?tag('a',{href:m.attrs.href,target:'_blank',rel:'noopener noreferrer nofollow'},text):tag(names[m.type],{},text);}return text;}
 const generic=directiveNodeForName(n.type);if(generic){const{relaymarkId,...authored}=a;return tag('section',{'data-relay-directive':generic.type,'data-authored':JSON.stringify(authored)},body);}
 const names={paragraph:'p',blockquote:'blockquote',bulletList:'ul',orderedList:'ol',listItem:'li',taskList:'ul',taskItem:'li',table:'table',tableRow:'tr',tableCell:'td',tableHeader:'th',calloutTitle:'div',questionLabel:'legend'};
 if(n.type==='hardBreak')return '<br>';if(n.type==='horizontalRule')return '<hr>';if(n.type==='heading')return tag('h'+a.level,{id:a.headingId},body);if(n.type==='codeBlock')return tag('pre',{},tag('code',{'data-language':a.language},body));if(n.type==='image')return '<img'+attrs({src:a.src,alt:a.alt,title:a.title,width:a.width,height:a.height})+'>';
 if(n.type==='callout')return tag('aside',{'data-relay-callout':a.tone,'data-emphasis':a.emphasis},body);
 if(n.type==='questionBlock')return tag('fieldset',{'data-relay-question':a.id,'data-question-type':a.type,'data-required':a.required},body);
 if(n.type==='questionOption')return tag('div',{'data-relay-option':a.id},body);
 if(n.type==='relayReference')return tag('span',{'data-relay-reference':a.entityId,'data-source':a.source},esc(a.label));if(n.type==='relayTag')return tag('span',{'data-relay-tag':a.id,'data-source':a.source},esc(a.name));
 if(n.type==='relayEntityReference')return tag('div',{'data-relay-reference':a.entityRef,'data-projection':a.projection,'data-source':a.source},esc(a.label));
 if(n.type==='videoEmbed')return tag('div',{'data-relay-video':a.videoId},'');if(n.type==='agentSuggestion')return tag('aside',{'data-relay-suggestion':a.review,'data-kind':a.kind},esc(a.content));
 if(n.type==='relayDataView'){const{relaymarkId,...authored}=a;return tag('div',{'data-relay-data-view':a.source,'data-authored':JSON.stringify(authored)},esc(a.title||a.source));}
 if(n.type==='relayButton')return tag('button',{type:'button',disabled:true,'data-relay-kind':a.kind,'data-relay-target':a.target},esc(a.label));if(n.type==='relayAnchor')return tag('span',{'data-relay-anchor':a.name},'');if(n.type==='relayConnection')return tag('div',{'data-relay-connection':a.provider},esc(a.provider));
 const extra=n.type==='orderedList'?{start:a.start}:n.type==='taskList'?{'data-relay-task-list':true}:n.type==='taskItem'?{'data-checked':a.checked}:['tableCell','tableHeader'].includes(n.type)?{colspan:a.colspan,rowspan:a.rowspan,'data-align':a.align}:{};
 if(!names[n.type])throw new TypeError('Unsupported authored renderer');return tag(names[n.type],extra,body);};return pm.content.map(render).join('');}
export function projectDocumentMarkdown(ast){valid(ast);return ast.blocks.map(markdown).join('\n\n')+'\n';}
function inlineMarkdown(nodes){return nodes.map(n=>{if(n.type==='text')return n.text.replace(/([\\`*_[\]])/g,'\\$1');if(n.type==='hard_break')return '  \n';if(['relay.entity_ref','relay.tag_ref'].includes(n.type))return n.props.source;if(n.type==='link')return '['+inlineMarkdown(n.content)+']('+n.href+')';if(n.type==='code_span'){const text=n.content[0].text,f='`'.repeat(longestTicks(text)+1);return f+text+f;}const delimiter={strong:'**',emphasis:'*',strikethrough:'~~',underline:'<u>',highlight:'<mark>',superscript:'<sup>',subscript:'<sub>'}[n.type];if(!delimiter)throw new TypeError('Unsupported inline projection');return delimiter+inlineMarkdown(n.content)+(delimiter.startsWith('<')?delimiter.replace('<','</'):delimiter);}).join('');}
function markdown(n){const p=n.props||{};switch(n.type){case 'paragraph':case 'relay.callout_title':return inlineMarkdown(n.content);case 'heading':return '#'.repeat(p.level)+' '+inlineMarkdown(n.content);case 'quote':return n.content.map(markdown).join('\n\n').split('\n').map(x=>'> '+x).join('\n');case 'horizontal_rule':return '---';case 'code':{const text=n.content.map(x=>x.text||'').join(''),f='`'.repeat(Math.max(3,longestTicks(text)+1));return f+(p.language||'')+'\n'+text+(text.endsWith('\n')?'':'\n')+f;}
 case 'image':return '!['+(p.alt||'')+']('+p.src+')';case 'list':case 'task_list':return n.content.map((item,i)=>{const marker=n.type==='task_list'?(item.props.checked?'- [x] ':'- [ ] '):p.kind==='ordered'?(p.start+i)+'. ':'- ';const[first,...rest]=item.content.map(markdown).join('\n\n').split('\n');return marker+first+rest.map(x=>'\n'+' '.repeat(marker.length)+x).join('');}).join('\n');
 case 'table':{const rows=n.content.map(r=>'| '+r.content.map(c=>c.content.map(markdown).join(' ').replace(/\|/g,'\\|').replace(/\n/g,'<br>')).join(' | ')+' |');const separator='| '+n.content[0].content.map(c=>({left:':---',center:':---:',right:'---:'}[c.props.align]||'---')).join(' | ')+' |';return [rows[0],separator,...rows.slice(1)].join('\n');}
 case 'relay.form_option':return '- '+inlineMarkdown(n.content);case 'relay.paper_control':case 'relay.entity_reference':return p.source;
 default:{const generic=directiveNodeForType(n.type);if(generic)return '@'+directiveForType(generic.type).name+'('+Object.entries(p).map(([k,v])=>k+': '+JSON.stringify(v)).join(', ')+') {\n'+n.content.map(markdown).join('\n\n')+'\n}';const name={'relay.callout':'Callout','relay.form_question':'Question','relay.agent_suggestion':'AgentSuggestion','relay.data_view':'DataView','relay.video_embed':'Video'}[n.type];if(!name)throw new TypeError('Unsupported block projection');const body=n.type==='relay.agent_suggestion'?inlineMarkdown(n.content):n.content.map(markdown).join('\n\n');return '@'+name+'('+Object.entries(p).map(([k,v])=>k+': '+JSON.stringify(v)).join(', ')+') {\n'+body+'\n}';}
}}
