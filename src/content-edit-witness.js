/** Causal identity preparation. This is deliberately not final admission: hosts
 * still prove complete non-text/deletion correspondence and accepted history scope. */
import {snapshotToDocument} from './document-snapshot.js';
import {relayMarkToProseMirror} from './document-adapter.js';
import {stableStringify} from './canonical-json.js';
import {validateTextAttributes} from './document-inline.js';
import {createCanonicalEditorSchema} from './editor-model.js';
import {validateOwnedHistory} from './owned-command-group.js';
const schema=createCanonicalEditorSchema(),MAX_UNITS=131072;
const same=(a,b)=>stableStringify(a)===stableStringify(b);
function keys(value,allowed,required=allowed){if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!allowed.includes(k))||required.some(k=>!Object.hasOwn(value,k)))throw TypeError('Invalid causal evidence fields');}
function identity(value){keys(value,['client','clock']);if(!Number.isSafeInteger(value.client)||value.client<0||!Number.isSafeInteger(value.clock)||value.clock<0||value.clock>=2**32)throw TypeError('Invalid causal item identity');return value;}
const idKey=id=>id.client+':'+id.clock;
function unicode(text){for(let i=0;i<text.length;i++){const c=text.charCodeAt(i);if(c>=0xd800&&c<=0xdbff){const next=text.charCodeAt(++i);if(!(next>=0xdc00&&next<=0xdfff))throw TypeError('Causal range splits Unicode');}else if(c>=0xdc00&&c<=0xdfff)throw TypeError('Causal range splits Unicode');}}
function selection(value){keys(value,['runs']);if(!Array.isArray(value.runs)||value.runs.length>4096)throw TypeError('Invalid causal selection');let count=0;const intervals=new Map();for(const run of value.runs){keys(run,['type','item','count']);identity(run.type);identity(run.item);if(!Number.isSafeInteger(run.count)||run.count<1||(count+=run.count)>MAX_UNITS||run.item.clock+run.count>2**32)throw TypeError('Invalid causal run extent');const seen=intervals.get(run.item.client)||[];if(seen.some(([a,b])=>a<run.item.clock+run.count&&b>run.item.clock))throw TypeError('Overlapping causal selector');seen.push([run.item.clock,run.item.clock+run.count]);intervals.set(run.item.client,seen);}return value;}
function clocks(values){if(!Array.isArray(values))throw TypeError('Missing trusted state vector');const result=new Map();for(const entry of values){keys(entry,['client','clock']);if(!Number.isSafeInteger(entry.client)||entry.client<0||!Number.isSafeInteger(entry.clock)||entry.clock<0||entry.clock>2**32||result.has(entry.client))throw TypeError('Invalid trusted state vector');result.set(entry.client,entry.clock);}return result;}
function index(snapshot){const runs=[],nodes=new Map(),seen=new Map();let budget=1_000_000;
 const step=()=>{if(--budget<0)throw TypeError('Causal snapshot budget exceeded');};
 function visit(node,position,depth){step();if(depth>128)throw TypeError('Causal snapshot depth exceeded');
  if(node.kind==='text'){keys(node,['kind','type','runs']);identity(node.type);if(!Array.isArray(node.runs)||nodes.has(idKey(node.type)))throw TypeError('Invalid causal text branch');nodes.set(idKey(node.type),node);let size=0;
   for(const run of node.runs){step();keys(run,['item','count','text','attributes']);identity(run.item);if(typeof run.text!=='string'||!run.text||run.text.length!==run.count||run.item.clock+run.count>2**32)throw TypeError('Invalid causal string run');unicode(run.text);validateTextAttributes(run.attributes);const known=seen.get(run.item.client)||[];if(known.some(([a,b])=>a<run.item.clock+run.count&&b>run.item.clock))throw TypeError('Overlapping visible causal items');known.push([run.item.clock,run.item.clock+run.count]);seen.set(run.item.client,known);runs.push({...run,type:node.type,position:position+size});size+=run.count;}
   return {portable:{kind:'text',delta:node.runs.map(run=>({insert:run.text,attributes:run.attributes}))},size};
  }
  if(node.kind==='fragment'){keys(node,['kind','root','children','metadata'],['kind','root','children']);if(node.root!=='default'||!Array.isArray(node.children))throw TypeError('Invalid causal root');}
  else {keys(node,['kind','type','name','attributes','children']);identity(node.type);if(node.kind!=='element'||!schema.nodes[node.name]||nodes.has(idKey(node.type)))throw TypeError('Invalid causal element');nodes.set(idKey(node.type),node);}
  if(!Array.isArray(node.children))throw TypeError('Invalid causal children');const children=[];let size=0;const root=node.kind==='fragment';
  for(const child of node.children){const result=visit(child,position+(root?0:1)+size,depth+1);children.push(result.portable);size+=result.size;}
  if(root)return {portable:{kind:'fragment',children,...(Object.hasOwn(node,'metadata')?{metadata:node.metadata}:{})},size};
  if(schema.nodes[node.name].isLeaf){if(size)throw TypeError('Causal atom contains children');size=1;}else size+=2;
  return {portable:{kind:'element',name:node.name,attributes:node.attributes,children},size};
 }
 const projected=visit(snapshot,0,0),document=snapshotToDocument(projected.portable),pm=schema.nodeFromJSON(relayMarkToProseMirror(document));pm.check();if(pm.content.size!==projected.size)throw TypeError('Causal snapshot size disagrees with maintained schema');
 return {runs,nodes,document,pm:JSON.parse(JSON.stringify(pm.toJSON()))};
}
function resolve(index,selected){selection(selected);const out=[];for(const requested of selected.runs){let clock=requested.item.clock,end=clock+requested.count;const candidates=index.runs.filter(run=>run.item.client===requested.item.client&&same(run.type,requested.type)&&run.item.clock<end&&run.item.clock+run.count>clock).sort((a,b)=>a.item.clock-b.item.clock);
 for(const run of candidates){if(run.item.clock>clock)break;const from=Math.max(clock,run.item.clock),to=Math.min(end,run.item.clock+run.count);if(from<to){const text=run.text.slice(from-run.item.clock,to-run.item.clock);unicode(text);out.push({type:run.type,item:{client:run.item.client,clock:from},count:to-from,text,attributes:run.attributes,position:run.position+from-run.item.clock});clock=to;}}
 if(clock!==end)throw TypeError('Causal selector has unavailable or wrongly typed items');
 }return out;
}
function plain(runs){return {runs:runs.map(({type,item,count})=>({type,item,count}))};}
function disjoint(runs){const seen=new Map();for(const run of runs){const list=seen.get(run.item.client)||[];if(list.some(([a,b])=>a<run.item.clock+run.count&&b>run.item.clock))throw TypeError('Duplicate destination/human allocation');list.push([run.item.clock,run.item.clock+run.count]);seen.set(run.item.client,list);}}
function cover(wanted,available){for(const run of wanted){let clock=run.item.clock,end=clock+run.count;for(const part of available.filter(v=>v.item.client===run.item.client&&same(v.type,run.type)).sort((a,b)=>a.item.clock-b.item.clock)){if(part.item.clock>clock)break;if(part.item.clock+part.count>clock)clock=Math.min(end,part.item.clock+part.count);}if(clock!==end)throw TypeError('Omitted or unproven fresh text allocation');}}
function equalContent(source,destination){let a=0,b=0,ao=0,bo=0;while(a<source.length&&b<destination.length){const s=source[a],d=destination[b],count=Math.min(s.count-ao,d.count-bo);if(s.text.slice(ao,ao+count)!==d.text.slice(bo,bo+count)||!same(s.attributes,d.attributes))throw TypeError('Causal contents or full attributes disagree');ao+=count;bo+=count;if(ao===s.count){a++;ao=0}if(bo===d.count){b++;bo=0}}if(a!==source.length||b!==destination.length)throw TypeError('Causal content length mismatch');}
function copyRange(source,destination,count,retained,inserted){let offset=0;while(offset<count){const sp=source+offset,dp=destination+offset,ends=[...retained.filter(r=>sp>=r.source_from&&sp<r.source_from+r.length&&dp===r.destination_from+sp-r.source_from).map(r=>r.source_from+r.length-sp),...inserted.filter(r=>dp>=r.destination_from&&dp<r.destination_from+r.length).map(r=>r.destination_from+r.length-dp)];if(!ends.length)return false;offset+=Math.min(count-offset,Math.max(...ends))}return true;}
function matchedCopy(source,destination,retained,inserted){let a=0,b=0,ao=0,bo=0;while(a<source.length&&b<destination.length){const s=source[a],d=destination[b],count=Math.min(s.count-ao,d.count-bo),sp=s.position+ao,dp=d.position+bo;if(s.text.slice(ao,ao+count)!==d.text.slice(bo,bo+count)||!same(s.attributes,d.attributes)||!copyRange(sp,dp,count,retained,inserted))throw TypeError('Unproven content-edit causal copy');ao+=count;bo+=count;if(ao===s.count){a++;ao=0}if(bo===d.count){b++;bo=0}}if(a!==source.length||b!==destination.length||!source.length)throw TypeError('Causal copy length mismatch');}
function allocationCoverage(footprint,beforeClocks,afterClocks,after,fresh){
 const allocationRuns=[];
 for(const record of footprint.structs){keys(record,['item','count','parent','key','origin','right_origin','content','deleted']);identity(record.item);if(!Number.isSafeInteger(record.count)||record.count<1||record.item.clock+record.count>2**32||record.item.clock+record.count>(afterClocks.get(record.item.client)||0))throw TypeError('Invalid original struct range');const start=Math.max(record.item.clock,beforeClocks.get(record.item.client)||0);if(start>=record.item.clock+record.count)continue;
  if(record.parent?.root==='relaymark')throw TypeError('Content edit contains metadata allocation');
  if(record.content?.kind==='string'){if(record.deleted||typeof record.content.text!=='string'||record.content.text.length!==record.count||!record.parent?.type||record.key!==null)throw TypeError('Hidden or unprovable string mutation');const allocated={type:identity(record.parent.type),item:{client:record.item.client,clock:start},count:record.item.clock+record.count-start};const observed=resolve(after,{runs:[allocated]});if(observed.map(v=>v.text).join('')!==record.content.text.slice(start-record.item.clock))throw TypeError('Original allocation disagrees with retained content');allocationRuns.push(allocated);}
 }
 cover(allocationRuns,fresh);cover(fresh,allocationRuns);
}
function freshRuns(after,beforeClocks){return after.runs.flatMap(run=>{const clock=Math.max(run.item.clock,beforeClocks.get(run.item.client)||0),count=run.item.clock+run.count-clock;return count>0?[{...run,item:{client:run.item.client,clock},count,text:run.text.slice(clock-run.item.clock),position:run.position+clock-run.item.clock}]:[]});}
export function prepareWitness(evidence,interpret){
 keys(evidence,['sender_before_snapshot','sender_after_snapshot','before_snapshot','after_snapshot','before_state_vector','operation','text_items','footprint']);
 const {footprint,operation}=evidence;if(operation?.history)throw TypeError('Owned history accounting requires maintained accepted-receipt replay');keys(footprint,['state_vector','structs','declared_deletes','deleted_items']);if(!Array.isArray(footprint.structs)||!Array.isArray(footprint.declared_deletes)||!Array.isArray(footprint.deleted_items)||footprint.structs.length+footprint.deleted_items.length>1_000_000)throw TypeError('Invalid complete mutation footprint');
 const beforeClocks=clocks(evidence.before_state_vector),afterClocks=clocks(footprint.state_vector);for(const [client,clock]of beforeClocks)if(clock>(afterClocks.get(client)||0))throw TypeError('Mutation frontier is behind trusted prestate');
 keys(operation,['kind','steps','copies','history','group'],['kind','steps','copies']);if(!Array.isArray(operation.copies)||operation.copies.length>4096)throw TypeError('Invalid causal copies');
 const sender=index(evidence.sender_before_snapshot),senderAfter=index(evidence.sender_after_snapshot),before=index(evidence.before_snapshot),after=index(evidence.after_snapshot),expected=interpret(sender.pm,operation);
 if(!same(expected.document,senderAfter.pm))throw TypeError('Actual sender result disagrees with maintained steps');
 if(!same(evidence.sender_after_snapshot.metadata??{},evidence.sender_before_snapshot.metadata??{})||!same(evidence.after_snapshot.metadata??{},evidence.before_snapshot.metadata??{}))throw TypeError('Content steps cannot mutate authored envelope');
 const fresh=freshRuns(after,beforeClocks);
 const human=resolve(after,evidence.text_items),destinations=[],proven_copies=[];let copiedUnits=0;
 for(const copy of operation.copies){keys(copy,['source','destination']);const source=resolve(sender,copy.source),destination=resolve(senderAfter,copy.destination);matchedCopy(source,destination,expected.retained_ranges,expected.inserted_ranges);if((copiedUnits+=destination.reduce((n,r)=>n+r.count,0))>MAX_UNITS)throw TypeError('Copied destination limit exceeded');equalContent(destination,resolve(after,copy.destination));destinations.push(...destination);proven_copies.push(copy);}
 disjoint([...human,...destinations]);cover(fresh,[...human,...destinations]);cover([...human,...destinations],fresh);
 // Original strings must all be visible and accounted for, including transient
 // allocations that disappear from the final authored result. Never infer this
 // from a state diff, AST equality or currently visible text alone.
 allocationCoverage(footprint,beforeClocks,afterClocks,after,fresh);
 // This preparation result is not final admission. Non-string allocations and
 // complete old deletion/format/topology correspondence remain explicit evidence
 // for the final mutation proof, rather than being silently ignored.
 const unproven_mutations={structs:footprint.structs.filter(r=>r.content.kind!=='string'),declared_deletes:footprint.declared_deletes,deleted_items:footprint.deleted_items};
 return {document:expected.document,authored_document:{...sender.document,blocks:expected.authored_document.blocks},retained_ranges:expected.retained_ranges,inserted_ranges:expected.inserted_ranges,proven_copies,fresh_items:plain(fresh),text_items:plain(human),unproven_mutations,requires_mutation_correspondence:true};
}

/** Derive relocation witnesses from actual maintained StepMaps and fresh item
 * identities. Text equality never discovers a source. Clipboard/source authority
 * for inserted Slice content remains an independent host obligation. */
export function buildWitness(evidence,interpret){
 keys(evidence,['sender_before_snapshot','sender_after_snapshot','before_snapshot','after_snapshot','before_state_vector','operation','footprint']);
 if(evidence.operation?.history)throw TypeError('Owned history accounting requires maintained accepted-receipt replay');
 keys(evidence.operation,['kind','steps','history','group','copies'],['kind','steps']);
 const sender=index(evidence.sender_before_snapshot),after=index(evidence.sender_after_snapshot),frontier=clocks(evidence.before_state_vector),expected=interpret(sender.pm,{...evidence.operation,copies:[]});
 if(!same(after.pm,expected.document))throw TypeError('Actual sender disagrees with maintained command');
 const supplied=evidence.operation.copies??[];if(!Array.isArray(supplied)||supplied.length>4096)throw TypeError('Invalid explicit Slice copies');const copies=[...supplied];let human=[];
 for(const run of after.runs){const start=Math.max(run.item.clock,frontier.get(run.item.client)||0),n=run.item.clock+run.count-start;if(n<=0)continue;let uncovered=[[run.position+start-run.item.clock,run.position+run.count]];
  for(const mapped of expected.retained_ranges){const from=Math.max(run.position+start-run.item.clock,mapped.destination_from),to=Math.min(run.position+run.count,mapped.destination_from+mapped.length);if(from>=to)continue;
   const sourceFrom=mapped.source_from+from-mapped.destination_from,sourceTo=sourceFrom+to-from;
   for(const original of sender.runs){const a=Math.max(original.position,sourceFrom),b=Math.min(original.position+original.count,sourceTo);if(a>=b)continue;const destination=from+a-sourceFrom,count=b-a;
    copies.push({source:{runs:[{type:original.type,item:{client:original.item.client,clock:original.item.clock+a-original.position},count}]},destination:{runs:[{type:run.type,item:{client:run.item.client,clock:run.item.clock+destination-run.position},count}]}});
    uncovered=uncovered.flatMap(([left,right])=>destination>=right||destination+count<=left?[[left,right]]:[...(left<destination?[[left,destination]]:[]),...(destination+count<right?[[destination+count,right]]:[])]);
   }
  }
  for(const [from,to]of uncovered)human.push({type:run.type,item:{client:run.item.client,clock:run.item.clock+from-run.position},count:to-from});
 }
 for(const copy of supplied){keys(copy,['source','destination']);for(const destination of resolve(after,copy.destination))human=human.flatMap(run=>{if(!same(run.type,destination.type)||run.item.client!==destination.item.client)return[run];const a=run.item.clock,b=a+run.count,c=destination.item.clock,d=c+destination.count;if(c>=b||d<=a)return[run];return[...(a<c?[{...run,count:c-a}]:[]),...(d<b?[{...run,item:{client:run.item.client,clock:d},count:b-d}]:[])];})}
 const operation={...evidence.operation,copies},text_items={runs:human},prepared=prepareWitness({...evidence,operation,text_items},interpret);
 return {...prepared,operation,text_items};
}

/** Immediate inverse producer over trusted maintained redone observations.
 * Historical source items can be tombstoned. This checks current destination
 * accounting and real synchronization Steps; it cannot authenticate source,
 * accepted groups, or the manager's complete original mutation footprint. */
export function buildOwnedHistoryWitness(evidence,interpret){
 keys(evidence,['before_snapshot','after_snapshot','before_state_vector','operation','restored_copies','footprint']);
 const {operation,footprint,restored_copies}=evidence;
 keys(operation,['kind','steps','history']);validateOwnedHistory(operation.history);
 keys(footprint,['state_vector','structs','declared_deletes','deleted_items']);
 if(!Array.isArray(footprint.structs)||!Array.isArray(footprint.deleted_items)||!Array.isArray(footprint.declared_deletes)||footprint.structs.length+footprint.deleted_items.length+footprint.declared_deletes.length>1_000_000)throw TypeError('Invalid observed inverse footprint');
 if(!Array.isArray(restored_copies)||restored_copies.length>4096)throw TypeError('Invalid maintained restored edges');
 const before=index(evidence.before_snapshot),after=index(evidence.after_snapshot),beforeClocks=clocks(evidence.before_state_vector),afterClocks=clocks(footprint.state_vector),expected=interpret(before.pm,operation);
 for(const[client,clock]of beforeClocks)if(clock>(afterClocks.get(client)||0))throw TypeError('Inverse frontier is behind prestate');
 if(!same(expected.document,after.pm))throw TypeError('Observed inverse disagrees with real synchronization Steps');
 if(!same(evidence.before_snapshot.metadata??{},evidence.after_snapshot.metadata??{}))throw TypeError('Inverse content steps cannot mutate authored envelope');
 const fresh=freshRuns(after,beforeClocks),destinations=[];let units=0;
 for(const copy of restored_copies){keys(copy,['source','destination']);selection(copy.source);const destination=resolve(after,copy.destination),sourceCount=copy.source.runs.reduce((n,r)=>n+r.count,0),destinationCount=destination.reduce((n,r)=>n+r.count,0);
  if(!sourceCount||sourceCount!==destinationCount||(units+=destinationCount)>MAX_UNITS)throw TypeError('Invalid maintained restored extent');
  for(const run of copy.source.runs)if(run.item.clock+run.count>(beforeClocks.get(run.item.client)||0))throw TypeError('Restored source was not retained at prestate');
  destinations.push(...destination);
 }
 disjoint(destinations);cover(fresh,destinations);cover(destinations,fresh);
 allocationCoverage(footprint,beforeClocks,afterClocks,after,fresh);
 return {document:expected.document,authored_document:{...before.document,blocks:expected.authored_document.blocks},fresh_items:plain(fresh),text_items:{runs:[]},proven_copies:restored_copies,restored_copies,
  operation:{...operation,copies:restored_copies},requires_mutation_correspondence:true,requires_owned_history_correspondence:true};
}
