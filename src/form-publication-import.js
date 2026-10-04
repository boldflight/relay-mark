/** Finite prerelease publication decoding; never a live editor or respondent owner. */
import {cloneCanonicalJSON as clone,stableStringify} from './canonical-json.js';
import {validateQuestionProps} from './document-adapter.js';
import {isBlockNode} from './node-kind.js';
const same=(a,b)=>stableStringify(a)===stableStringify(b);
function object(value){if(!value||typeof value!=='object'||Array.isArray(value))throw TypeError('Invalid historical publication object');return value;}
function source(value){if(typeof value!=='string')throw TypeError('Historical label must retain source text');return value;}
function semantic(value){if(Array.isArray(value))return value.map(semantic);if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).filter(([key])=>key!=='id'||!isBlockNode(value)).map(([key,item])=>[key,semantic(item)]));return value;}
function settings(block,known){const value=clone(Object.hasOwn(block,'settings')?block.settings:{});object(value);for(const[key,item]of Object.entries(block)){if(known.includes(key)||key==='settings')continue;if(Object.hasOwn(value,key)&&!same(value[key],item))throw TypeError('Conflicting historical setting');value[key]=clone(item);}return value;}
function grading(question){const key=question.props.settings.answer_key;if(key==null)return;object(key);const points=question.props.points;if(key.points!=null&&points!=null&&key.points!==points)throw TypeError('Conflicting grading points');
 if(['multiple_choice','checkboxes'].includes(question.props.type)){const correct=question.content.slice(1).filter(n=>n.props.correct).map(n=>n.props.id),expected=question.props.type==='multiple_choice'?(correct.length===1?correct[0]:null):correct.slice().sort(),actual=Array.isArray(key.correct_answer)?key.correct_answer.slice().sort():key.correct_answer;if(!same(expected,actual))throw TypeError('Conflicting grading answer');}
}
function mergeSettings(saved,retained,path,normalizations){const result=clone(saved);for(const[key,value]of Object.entries(retained)){if(!Object.hasOwn(result,key)){result[key]=clone(value);normalizations.push({path:[...path,key],operation:'recover_retained_source_setting'});}else if(value&&typeof value==='object'&&!Array.isArray(value)&&result[key]&&typeof result[key]==='object'&&!Array.isArray(result[key]))result[key]=mergeSettings(result[key],value,[...path,key],normalizations);else if(!same(result[key],value))throw TypeError('Conflicting retained publication setting');}return result;}
export function importPublication(original,{namespace,source:retainedSource}={},adapter){
 object(original);if(typeof namespace!=='string'||!namespace||!Array.isArray(original.blocks))throw TypeError('Historical publication requires blocks and retained namespace');
 const normalizations=[],mapping={retained:[],remapped:[],added:[]},blocks=[];const questionIDs=new Set();
 function imported(text,role){const result=adapter.importSource(source(text),{namespace:namespace+':publication:'+role});if(Object.keys(result.document).some(k=>!['type','blocks'].includes(k)))throw TypeError('Publication fragment cannot silently drop source metadata');for(const key of Object.keys(mapping))mapping[key].push(...result.identity_mapping[key]);return result.document.blocks;}
 function inline(text,role){const nodes=imported(text,role);if(nodes.length!==1||nodes[0].type!=='paragraph')throw TypeError('Rich question/option label requires canonical inline content');return nodes[0];}
 for(const [position,raw]of original.blocks.entries()){const b=object(raw),path=['blocks',position];
  if(b.type==='paragraph'){if(Object.keys(b).some(k=>!['type','label'].includes(k)))throw TypeError('Unknown historical prose block fields');const parsed=imported(b.label,'prose:'+position);blocks.push(...parsed);normalizations.push({path,operation:'import_source',block_ids:parsed.map(n=>n.id)});continue;}
  if(typeof b.id!=='string'||!b.id||questionIDs.has(b.id))throw TypeError('Invalid historical question identity');questionIDs.add(b.id);
  const id=adapter.identity(namespace,['publication',position,'question']),label=inline(b.label??'',JSON.stringify(['label',b.id])),optionIDs=new Set();
  const props={id:b.id,type:b.type,required:b.required??false,points:b.points??null,min:b.min??null,max:b.max??null,settings:settings(b,['id','type','label','required','points','min','max','options'])};validateQuestionProps(props);
  if(b.options!==undefined&&!Array.isArray(b.options))throw TypeError('Historical options must retain their order');
  const options=(b.options??[]).map((o,index)=>{object(o);if(typeof o.id!=='string'||!o.id||optionIDs.has(o.id))throw TypeError('Invalid historical option identity');optionIDs.add(o.id);if(o.label!==undefined&&o.text!==undefined&&o.label!==o.text)throw TypeError('Ambiguous historical option label');const label=inline(o.label??o.text??'',JSON.stringify(['option',b.id,o.id])),id=adapter.identity(namespace,['publication',position,'option',index]),props={id:o.id,correct:o.correct??false,points:o.points??null,settings:settings(o,['id','label','text','correct','points'])};validateQuestionProps(props,true);mapping.added.push({id,parent:b.id,role:'option',option_id:o.id});return {id,type:'relay.form_option',props,content:label.content};});
  const question={id,type:'relay.form_question',props,content:[label,...options]};grading(question);blocks.push(question);mapping.added.push({id,role:'question',question_id:b.id});normalizations.push({path,operation:'form_question',block_id:id,label_id:label.id,option_ids:options.map(n=>n.id)});
 }
 let document=adapter.normalize({type:'relaymark.document',blocks:blocks.length?blocks:imported('','empty')});
 if(retainedSource!==undefined){
  const result=adapter.importSource(source(retainedSource),{namespace:namespace+':retained-publication-source'}),savedQuestions=document.blocks.filter(n=>n.type==='relay.form_question'),retainedQuestions=result.document.blocks.filter(n=>n.type==='relay.form_question');
  if(savedQuestions.length!==retainedQuestions.length||!same(semantic(document.blocks.filter(n=>n.type!=='relay.form_question')),semantic(result.document.blocks.filter(n=>n.type!=='relay.form_question'))))throw TypeError('Conflicting retained publication prose or question structure');
  retainedQuestions.forEach((q,i)=>{const saved=savedQuestions[i];if(saved.props.id!==q.props.id||saved.props.type!==q.props.type||saved.content.length!==q.content.length||!same(semantic(saved.content[0]),semantic(q.content[0])))throw TypeError('Conflicting retained publication question/option identity or labels');
   q.content.slice(1).forEach((option,index)=>{const old=saved.content[index+1];if(old.props.id!==option.props.id||old.props.correct!==option.props.correct||!same(old.content,option.content))throw TypeError('Conflicting retained option identity/label/correctness');if(old.props.points!=null&&old.props.points!==option.props.points)throw TypeError('Conflicting retained option points');option.props.settings=mergeSettings(old.props.settings,option.props.settings,['question',q.props.id,'option',option.props.id,'settings'],normalizations);});
   for(const key of ['required','points','min','max']){if(saved.props[key]==null&&q.props[key]!=null){normalizations.push({path:['question',q.props.id,key],operation:'recover_retained_source_setting'});}else if(!same(saved.props[key],q.props[key]))throw TypeError('Conflicting retained question setting');else q.props[key]=saved.props[key];}
   q.props.settings=mergeSettings(saved.props.settings,q.props.settings,['question',q.props.id,'settings'],normalizations);grading(q);
  });
  document=adapter.normalize(result.document);for(const key of Object.keys(mapping))mapping[key]=result.identity_mapping[key];normalizations.push({path:[],operation:'use_retained_publication_source'});
 }
 const used=new Set();function visit(node){if(isBlockNode(node))used.add(node.id);for(const child of node.content??[])visit(child)}document.blocks.forEach(visit);mapping.retained=mapping.retained.filter(v=>used.has(v));mapping.added=mapping.added.filter(v=>used.has(v.id));mapping.remapped=mapping.remapped.filter(v=>used.has(v.to));
 return {document,identity_mapping:mapping,normalizations};
}
