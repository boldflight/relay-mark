/** Causal identity preparation. This is deliberately not final admission: hosts
 * still prove complete non-text/deletion correspondence and accepted history scope. */
import {snapshotToDocument,snapshotToDocumentWithProseMirror,importAggregateSettingsSnapshot} from './document-snapshot.js';
import {canonicalContract} from './contract.js';
import {Step,Transform} from 'prosemirror-transform';
import {Slice} from 'prosemirror-model';
import {relayMarkToProseMirror} from './document-adapter.js';
import {stableStringify,canonicalJSONSHA256,cloneCanonicalJSON} from './canonical-json.js';
import {paperDocumentDestinations} from './document-controls.js';
import {validateTextAttributes} from './document-inline.js';
import {withLinkSyntaxScope} from './document-links.js';
import {createCanonicalEditorSchema} from './editor-model.js';
import {validateOwnedHistory,canonicalOperationID} from './owned-command-group.js';
const schema=createCanonicalEditorSchema(),MAX_UNITS=131072,MAX_SOURCE_UNITS=12_582_912;
const same=(a,b)=>stableStringify(a)===stableStringify(b);
function keys(value,allowed,required=allowed){if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!allowed.includes(k))||required.some(k=>!Object.hasOwn(value,k)))throw TypeError('Invalid causal evidence fields');}
function identity(value){keys(value,['client','clock']);if(!Number.isSafeInteger(value.client)||value.client<0||!Number.isSafeInteger(value.clock)||value.clock<0||value.clock>=2**32)throw TypeError('Invalid causal item identity');return value;}
const idKey=id=>id.client+':'+id.clock;
function unicode(text){for(let i=0;i<text.length;i++){const c=text.charCodeAt(i);if(c>=0xd800&&c<=0xdbff){const next=text.charCodeAt(++i);if(!(next>=0xdc00&&next<=0xdfff))throw TypeError('Causal range splits Unicode');}else if(c>=0xdc00&&c<=0xdfff)throw TypeError('Causal range splits Unicode');}}
function selection(value,maxUnits=MAX_UNITS,maxRuns=4096){keys(value,['runs']);if(!Array.isArray(value.runs)||value.runs.length>maxRuns)throw TypeError('Invalid causal selection');let count=0;const intervals=new Map();for(const run of value.runs){keys(run,['type','item','count']);identity(run.type);identity(run.item);if(!Number.isSafeInteger(run.count)||run.count<1||(count+=run.count)>maxUnits||run.item.clock+run.count>2**32)throw TypeError('Invalid causal run extent');const seen=intervals.get(run.item.client)||[];if(seen.some(([a,b])=>a<run.item.clock+run.count&&b>run.item.clock))throw TypeError('Overlapping causal selector');seen.push([run.item.clock,run.item.clock+run.count]);intervals.set(run.item.client,seen);}return value;}
function clocks(values){if(!Array.isArray(values))throw TypeError('Missing trusted state vector');const result=new Map();for(const entry of values){keys(entry,['client','clock']);if(!Number.isSafeInteger(entry.client)||entry.client<0||!Number.isSafeInteger(entry.clock)||entry.clock<0||entry.clock>2**32||result.has(entry.client))throw TypeError('Invalid trusted state vector');result.set(entry.client,entry.clock);}return result;}
function snapshotProjection(snapshot){const runs=[],nodes=new Map(),positions=[],seen=new Map();let budget=1_000_000;
 const step=()=>{if(--budget<0)throw TypeError('Causal snapshot budget exceeded');};
 function visit(node,position,depth,path=[]){step();if(depth>128)throw TypeError('Causal snapshot depth exceeded');
  if(node.kind==='text'){keys(node,['kind','type','runs']);identity(node.type);if(!Array.isArray(node.runs)||nodes.has(idKey(node.type)))throw TypeError('Invalid causal text branch');nodes.set(idKey(node.type),node);let size=0;
   for(const run of node.runs){step();keys(run,['item','count','text','attributes']);identity(run.item);if(typeof run.text!=='string'||!run.text||run.text.length!==run.count||run.item.clock+run.count>2**32)throw TypeError('Invalid causal string run');unicode(run.text);validateTextAttributes(run.attributes);const known=seen.get(run.item.client)||[];known.push([run.item.clock,run.item.clock+run.count]);seen.set(run.item.client,known);runs.push({...run,type:node.type,path,offset:size,position:position+size});size+=run.count;}
   positions.push({node,position,size,path});return {portable:{kind:'text',delta:node.runs.map(run=>({insert:run.text,attributes:run.attributes}))},size};
  }
  if(node.kind==='fragment'){keys(node,['kind','root','children','metadata'],['kind','root','children']);if(node.root!=='default'||!Array.isArray(node.children))throw TypeError('Invalid causal root');}
  else {keys(node,['kind','type','name','attributes','children']);identity(node.type);if(node.kind!=='element'||!schema.nodes[node.name]||nodes.has(idKey(node.type)))throw TypeError('Invalid causal element');nodes.set(idKey(node.type),node);}
  if(!Array.isArray(node.children))throw TypeError('Invalid causal children');const children=[];let size=0;const root=node.kind==='fragment';
  for(const [childIndex,child] of node.children.entries()){const result=visit(child,position+(root?0:1)+size,depth+1,[...path,childIndex]);children.push(result.portable);size+=result.size;}
  if(root)return {portable:{kind:'fragment',children,...(Object.hasOwn(node,'metadata')?{metadata:node.metadata}:{})},size};
  if(schema.nodes[node.name].isLeaf){if(size)throw TypeError('Causal atom contains children');size=1;}else size+=2;
  positions.push({node,position,size,path});return {portable:{kind:'element',name:node.name,attributes:node.attributes,children},size};
 }
 const projection=withLinkSyntaxScope(()=>visit(snapshot,0,0));
 // Visible item clocks are scoped to their actual client across all branches.
 // Validate the complete half-open intervals once; adjacent ranges are valid.
 for(const intervals of seen.values()){
  intervals.sort((a,b)=>a[0]-b[0]);
  for(let i=1;i<intervals.length;i++)if(intervals[i][0]<intervals[i-1][1])throw TypeError('Overlapping visible causal items');
 }
 return {...projection,runs,nodes,positions};
}
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
function archiveIndex(evidence){
 if(!Object.hasOwn(evidence,'archive_context'))return index(evidence.archive_identity_snapshot);
 const context=evidence.archive_context;keys(context,['binding']);const binding=context.binding;
 const extra=binding?.layer==='enhanced'?['draft_id','source_revision','source_hash']:[];
 keys(binding,['authority_id','account_id','organization_id','entity_id','document_id','incarnation','schema','root','source_contract','contract_version','access_epoch','cache_key','layer',...extra]);
 const uuid=value=>typeof value==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(value);
 if(binding.contract_version!==canonicalContract.contract_version||binding.schema!==canonicalContract.schema||binding.source_contract!==canonicalContract.source_contract||binding.root!=='default'||
  !['authored','enhanced'].includes(binding.layer)||!uuid(binding.document_id)||binding.document_id!==binding.incarnation||!/^[a-f0-9]{64}$/.test(binding.access_epoch)||
  ['authority_id','account_id','organization_id','entity_id'].some(name=>typeof binding[name]!=='string'||!binding[name])||
  binding.layer==='enhanced'&&(!uuid(binding.draft_id)||!/^sha256:[a-f0-9]{64}$/.test(binding.source_revision)||!/^[a-f0-9]{64}$/.test(binding.source_hash)))throw TypeError('Invalid original archive context');
 const lane=[binding.authority_id,binding.account_id,binding.organization_id,binding.layer==='enhanced'?binding.document_id:binding.entity_id,binding.incarnation,binding.access_epoch];
 if(binding.cache_key!==JSON.stringify(lane))throw TypeError('Invalid original archive lane');
 return index(evidence.archive_identity_snapshot,portable=>importAggregateSettingsSnapshot(portable).document);
}
function resolve(index,selected,read=false){selection(selected,read?MAX_SOURCE_UNITS:MAX_UNITS,4096);const out=[];for(const requested of selected.runs){let clock=requested.item.clock,end=clock+requested.count;const candidates=index.runs.filter(run=>run.item.client===requested.item.client&&same(run.type,requested.type)&&run.item.clock<end&&run.item.clock+run.count>clock).sort((a,b)=>a.item.clock-b.item.clock);
 for(const run of candidates){if(run.item.clock>clock)break;const from=Math.max(clock,run.item.clock),to=Math.min(end,run.item.clock+run.count);if(from<to){const text=run.text.slice(from-run.item.clock,to-run.item.clock);unicode(text);out.push({type:run.type,item:{client:run.item.client,clock:from},count:to-from,text,attributes:run.attributes,path:run.path,offset:run.offset+from-run.item.clock,position:run.position+from-run.item.clock});clock=to;}}
 if(clock!==end)throw TypeError('Causal selector has unavailable or wrongly typed items');
 }return out;
}
function plain(runs){return {runs:runs.map(({type,item,count})=>({type,item,count}))};}
function disjoint(runs){const seen=new Map();for(const run of runs){const list=seen.get(run.item.client)||[];if(list.some(([a,b])=>a<run.item.clock+run.count&&b>run.item.clock))throw TypeError('Duplicate destination/human allocation');list.push([run.item.clock,run.item.clock+run.count]);seen.set(run.item.client,list);}}
function cover(wanted,available){for(const run of wanted){let clock=run.item.clock,end=clock+run.count;for(const part of available.filter(v=>v.item.client===run.item.client&&same(v.type,run.type)).sort((a,b)=>a.item.clock-b.item.clock)){if(part.item.clock>clock)break;if(part.item.clock+part.count>clock)clock=Math.min(end,part.item.clock+part.count);}if(clock!==end)throw TypeError('Omitted or unproven fresh text allocation');}}
function equalContent(source,destination){let a=0,b=0,ao=0,bo=0;while(a<source.length&&b<destination.length){const s=source[a],d=destination[b],count=Math.min(s.count-ao,d.count-bo);if(s.text.slice(ao,ao+count)!==d.text.slice(bo,bo+count)||!same(s.attributes,d.attributes))throw TypeError('Causal contents or full attributes disagree');ao+=count;bo+=count;if(ao===s.count){a++;ao=0}if(bo===d.count){b++;bo=0}}if(a!==source.length||b!==destination.length)throw TypeError('Causal content length mismatch');}
function copyRange(source,destination,count,retained,inserted){let offset=0;while(offset<count){const sp=source+offset,dp=destination+offset,ends=[...retained.filter(r=>sp>=r.source_from&&sp<r.source_from+r.length&&dp===r.destination_from+sp-r.source_from).map(r=>r.source_from+r.length-sp),...inserted.filter(r=>dp>=r.destination_from&&dp<r.destination_from+r.length).map(r=>r.destination_from+r.length-dp)];if(!ends.length)return false;offset+=Math.min(count-offset,Math.max(...ends))}return true;}
function matchedCopy(source,destination,retained,inserted){let a=0,b=0,ao=0,bo=0;while(a<source.length&&b<destination.length){const s=source[a],d=destination[b],count=Math.min(s.count-ao,d.count-bo),sp=s.position+ao,dp=d.position+bo;if(s.text.slice(ao,ao+count)!==d.text.slice(bo,bo+count)||(!same(s.attributes,d.attributes)&&!copyRange(sp,dp,count,retained,[]))||!copyRange(sp,dp,count,retained,inserted))throw TypeError('Unproven content-edit causal copy');ao+=count;bo+=count;if(ao===s.count){a++;ao=0}if(bo===d.count){b++;bo=0}}if(a!==source.length||b!==destination.length||!source.length)throw TypeError('Causal copy length mismatch');}
function allocationCoverage(footprint,beforeClocks,afterClocks,after,fresh,operation){
 const allocationRuns=[];
 for(const record of footprint.structs){keys(record,['item','count','parent','key','origin','right_origin','content','deleted']);identity(record.item);if(!Number.isSafeInteger(record.count)||record.count<1||record.item.clock+record.count>2**32||record.item.clock+record.count>(afterClocks.get(record.item.client)||0))throw TypeError('Invalid original struct range');const start=Math.max(record.item.clock,beforeClocks.get(record.item.client)||0);if(start>=record.item.clock+record.count)continue;
  if(record.parent?.root==='relaymark'){if(!operation.steps.some(step=>step.stepType==='docAttr'&&step.attr==='relaymark'))throw TypeError('Content edit contains metadata allocation');continue;}
  if(record.content?.kind==='string'){if(record.deleted||typeof record.content.text!=='string'||record.content.text.length!==record.count||!record.parent?.type||record.key!==null)throw TypeError('Hidden or unprovable string mutation');const allocated={type:identity(record.parent.type),item:{client:record.item.client,clock:start},count:record.item.clock+record.count-start};const observed=resolve(after,{runs:[allocated]});if(observed.map(v=>v.text).join('')!==record.content.text.slice(start-record.item.clock))throw TypeError('Original allocation disagrees with retained content');allocationRuns.push(allocated);}
 }
 cover(allocationRuns,fresh);cover(fresh,allocationRuns);
}
// Maintained semantic insertion maps must not borrow an older source item.
// A value-only binding diff can otherwise move fresh input into a copied suffix.
function refuseReusedInsertedText(after,inserted,beforeClocks){
 let cursor=0;
 for(const run of after.runs){
  const start=run.position,end=start+run.count;
  while(cursor<inserted.length&&inserted[cursor].destination_from+inserted[cursor].length<=start)cursor++;
  for(let i=cursor;i<inserted.length&&inserted[i].destination_from<end;i++){
   const from=Math.max(start,inserted[i].destination_from),to=Math.min(end,inserted[i].destination_from+inserted[i].length);
   if(from<to&&run.item.clock+from-start<(beforeClocks.get(run.item.client)||0))throw TypeError('Semantic inserted text reused retained identity');
  }
 }
}
function freshRuns(after,beforeClocks){return after.runs.flatMap(run=>{const clock=Math.max(run.item.clock,beforeClocks.get(run.item.client)||0),count=run.item.clock+run.count-clock;return count>0?[{...run,item:{client:run.item.client,clock},count,text:run.text.slice(clock-run.item.clock),position:run.position+clock-run.item.clock}]:[]});}
export function prepareWitness(evidence,interpret){return prepareNormal(evidence,interpret,index);}
function prepareNormal(evidence,interpret,snapshotIndex){
 if(evidence.operation?.reviewed_recovery)throw TypeError('Reviewed recovery requires regional correspondence');
 return prepare(evidence,interpret,null,snapshotIndex);
}
function prepare(evidence,interpret,recoveryDestinations,snapshotIndex=index){
 keys(evidence,['sender_before_snapshot','sender_after_snapshot','before_snapshot','after_snapshot','before_state_vector','operation','text_items','footprint']);
 const {footprint,operation}=evidence;if(operation?.history)throw TypeError('Owned history accounting requires maintained accepted-receipt replay');keys(footprint,['state_vector','structs','declared_deletes','deleted_items']);if(!Array.isArray(footprint.structs)||!Array.isArray(footprint.declared_deletes)||!Array.isArray(footprint.deleted_items)||footprint.structs.length+footprint.deleted_items.length>1_000_000)throw TypeError('Invalid complete mutation footprint');
 const beforeClocks=clocks(evidence.before_state_vector),afterClocks=clocks(footprint.state_vector);for(const [client,clock]of beforeClocks)if(clock>(afterClocks.get(client)||0))throw TypeError('Mutation frontier is behind trusted prestate');
 keys(operation,['kind','steps','copies','history','group',...(recoveryDestinations?['reviewed_recovery']:[])],['kind','steps','copies']);if(!Array.isArray(operation.copies)||operation.copies.length>4096)throw TypeError('Invalid causal copies');
 const sender=snapshotIndex(evidence.sender_before_snapshot),senderAfter=snapshotIndex(evidence.sender_after_snapshot),before=snapshotIndex(evidence.before_snapshot),after=snapshotIndex(evidence.after_snapshot),expected=interpret(sender.pm,operation);
 if(!same(expected.document,senderAfter.pm))throw TypeError('Actual sender result disagrees with maintained steps');
 refuseReusedInsertedText(senderAfter,expected.inserted_ranges,beforeClocks);
 // Exact metadata consequences are part of the maintained doc attribute; full footprint correspondence remains required.
 const fresh=freshRuns(after,beforeClocks);
 const human=resolve(after,evidence.text_items),destinations=[],proven_copies=[];let copiedUnits=0;
 for(const copy of operation.copies){keys(copy,['source','destination']);const source=resolve(sender,copy.source),destination=resolve(senderAfter,copy.destination);matchedCopy(source,destination,expected.retained_ranges,expected.inserted_ranges);if((copiedUnits+=destination.reduce((n,r)=>n+r.count,0))>MAX_UNITS)throw TypeError('Copied destination limit exceeded');equalContent(destination,resolve(after,copy.destination));destinations.push(...destination);proven_copies.push(copy);}
 const accounted=[...human,...destinations,...(recoveryDestinations||[])];
 disjoint(accounted);cover(fresh,accounted);cover(accounted,fresh);
 // Original strings must all be visible and accounted for, including transient
 // allocations that disappear from the final authored result. Never infer this
 // from a state diff, AST equality or currently visible text alone.
 allocationCoverage(footprint,beforeClocks,afterClocks,after,fresh,operation);
 // This preparation result is not final admission. Non-string allocations and
 // complete old deletion/format/topology correspondence remain explicit evidence
 // for the final mutation proof, rather than being silently ignored.
 const unproven_mutations={structs:footprint.structs.filter(r=>r.content.kind!=='string'),declared_deletes:footprint.declared_deletes,deleted_items:footprint.deleted_items};
 return {document:expected.document,authored_document:expected.authored_document,retained_ranges:expected.retained_ranges,inserted_ranges:expected.inserted_ranges,proven_copies,fresh_items:plain(fresh),text_items:plain(human),unproven_mutations,requires_mutation_correspondence:true};
}

/** Derive relocation witnesses from actual maintained StepMaps and fresh item
 * identities. Text equality never discovers a source. Clipboard/source authority
 * for inserted Slice content remains an independent host obligation. */
export function buildWitness(evidence,interpret,decode=snapshotToDocument){
 if(evidence.operation?.reviewed_recovery)throw TypeError('Reviewed recovery requires regional correspondence');
 keys(evidence,['sender_before_snapshot','sender_after_snapshot','before_snapshot','after_snapshot','before_state_vector','operation','footprint']);
 if(evidence.operation?.history)throw TypeError('Owned history accounting requires maintained accepted-receipt replay');
 keys(evidence.operation,['kind','steps','history','group','copies'],['kind','steps']);
 // The synchronous builder and final preparation share exact observer objects.
 // Reuse only within this call: distinct peer snapshots still validate in full,
 // and a later call must revalidate even a previously observed object.
 const indexes=new Map(),snapshotIndex=snapshot=>{if(!indexes.has(snapshot))indexes.set(snapshot,index(snapshot,decode));return indexes.get(snapshot);};
 const sender=snapshotIndex(evidence.sender_before_snapshot),after=snapshotIndex(evidence.sender_after_snapshot),frontier=clocks(evidence.before_state_vector),expected=interpret(sender.pm,{...evidence.operation,copies:[]});
 if(!same(after.pm,expected.document))throw TypeError('Actual sender disagrees with maintained command');
 refuseReusedInsertedText(after,expected.inserted_ranges,frontier);
 const supplied=evidence.operation.copies??[];if(!Array.isArray(supplied)||supplied.length>4096)throw TypeError('Invalid explicit Slice copies');const copies=[...supplied];let human=[];
 for(const run of after.runs){const start=Math.max(run.item.clock,frontier.get(run.item.client)||0),n=run.item.clock+run.count-start;if(n<=0)continue;let uncovered=[[run.position+start-run.item.clock,run.position+run.count]];
  for(const mapped of [...expected.retained_ranges,...expected.copied_subtree_ranges]){const from=Math.max(run.position+start-run.item.clock,mapped.destination_from),to=Math.min(run.position+run.count,mapped.destination_from+mapped.length);if(from>=to)continue;
   const sourceFrom=mapped.source_from+from-mapped.destination_from,sourceTo=sourceFrom+to-from;
   for(const original of sender.runs){const a=Math.max(original.position,sourceFrom),b=Math.min(original.position+original.count,sourceTo);if(a>=b)continue;const destination=from+a-sourceFrom,count=b-a;
    copies.push({source:{runs:[{type:original.type,item:{client:original.item.client,clock:original.item.clock+a-original.position},count}]},destination:{runs:[{type:run.type,item:{client:run.item.client,clock:run.item.clock+destination-run.position},count}]}});
    uncovered=uncovered.flatMap(([left,right])=>destination>=right||destination+count<=left?[[left,right]]:[...(left<destination?[[left,destination]]:[]),...(destination+count<right?[[destination+count,right]]:[])]);
   }
  }
  for(const [from,to]of uncovered)human.push({type:run.type,item:{client:run.item.client,clock:run.item.clock+from-run.position},count:to-from});
 }
 for(const copy of supplied){keys(copy,['source','destination']);for(const destination of resolve(after,copy.destination))human=human.flatMap(run=>{if(!same(run.type,destination.type)||run.item.client!==destination.item.client)return[run];const a=run.item.clock,b=a+run.count,c=destination.item.clock,d=c+destination.count;if(c>=b||d<=a)return[run];return[...(a<c?[{...run,count:c-a}]:[]),...(d<b?[{...run,item:{client:run.item.client,clock:d},count:b-d}]:[])];})}
 const operation={...evidence.operation,copies},text_items={runs:human},prepared=prepareNormal({...evidence,operation,text_items},interpret,snapshotIndex);
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
 // Inverse metadata authority is the independently replayed accepted manager.
 const fresh=freshRuns(after,beforeClocks),destinations=[];let units=0;
 for(const copy of restored_copies){keys(copy,['source','destination']);selection(copy.source);const destination=resolve(after,copy.destination),sourceCount=copy.source.runs.reduce((n,r)=>n+r.count,0),destinationCount=destination.reduce((n,r)=>n+r.count,0);
  if(!sourceCount||sourceCount!==destinationCount||(units+=destinationCount)>MAX_UNITS)throw TypeError('Invalid maintained restored extent');
  for(const run of copy.source.runs)if(run.item.clock+run.count>(beforeClocks.get(run.item.client)||0))throw TypeError('Restored source was not retained at prestate');
  destinations.push(...destination);
 }
 disjoint(destinations);cover(fresh,destinations);cover(destinations,fresh);
 allocationCoverage(footprint,beforeClocks,afterClocks,after,fresh,operation);
 return {document:expected.document,authored_document:expected.authored_document,fresh_items:plain(fresh),text_items:{runs:[]},proven_copies:restored_copies,restored_copies,
  operation:{...operation,copies:restored_copies},requires_mutation_correspondence:true,requires_owned_history_correspondence:true};
}

/** Strict visible-only resolution. Missing items are never inferred tombstones.
 * Hosts fold authenticated ancestry against current visible candidates first. */
export function resolveContentEditTextItems(snapshot,selected){
 // Read-side selectors are bounded by the existing 16 MiB source frame,
 // independently of the unchanged 131072-unit authored-command proof guard.
 validateSourceReadSelector(selected);
 const resolved=resolve(index(snapshot),selected,true).sort((a,b)=>a.position-b.position);
 return {segments:resolved.map(({position,...segment})=>segment)};
}

/** Read-only current visible candidates, in bounded classifier windows. A
 * missing identity is never classified as a tombstone or granted authorship. */
export function sourceSelectorWindows(snapshot){return selectorWindows(index(snapshot));}
function selectorWindows(snapshotIndex){
 const windows=[];let runs=[],units=0;
 const flush=()=>{if(runs.length){windows.push({runs});runs=[];units=0;}};
 for(const run of snapshotIndex.runs){
  let offset=0;
  while(offset<run.count){
   if(units===16384||runs.length===4096)flush();
   let count=Math.min(run.count-offset,16384-units);
   const end=offset+count;
   if(end<run.count&&run.text.charCodeAt(end-1)>=0xd800&&run.text.charCodeAt(end-1)<=0xdbff)count--;
   if(!count){flush();continue;}
   runs.push({type:run.type,item:{client:run.item.client,clock:run.item.clock+offset},count});
   offset+=count;units+=count;
  }
 }
 flush();return {windows};
}

/** A read selector is checked against the existing checkpoint material budget,
 * never used to admit an authored command. Its run/proof checks stay strict. */
export function validateSourceReadSelector(selected){
 if(JSON.stringify(selected).length>16_777_216)throw TypeError('Source selector transport budget exceeded');
 selection(selected,MAX_SOURCE_UNITS,4096);return true;
}

/** Complete-block recovery correspondence is allocation evidence only. The host
 * authenticates the exact archive/review hashes, donor cut and fresh target guard.
 * No source is discovered by equal values and no human ancestry is granted here.
 */
/** Pure source-ordinal navigation repair over an actual maintained import
 * transform. It is not receipt issuance or source-authority evidence. */
/** Same validated identity snapshot projection consumed by causal proof. */
/** Same identity/run validation and projection as the strict current reader.
 * This portable shape is input only: current or explicit finite grammar decoding
 * remains required, and no source, receipt or conversion authority is inferred. */
export function contentEditSnapshotToPortableSnapshot(snapshot){return cloneCanonicalJSON(snapshotProjection(snapshot).portable);}
export function readContentEditSnapshotDocument(snapshot){return index(snapshot).pm;}
export function readReviewedRecoveryArchiveDocument(evidence){keys(evidence,['archive_identity_snapshot','archive_context'],['archive_identity_snapshot']);return archiveIndex(evidence).pm;}
export function reviewedRecoveryArchiveSourceWindows(evidence){keys(evidence,['archive_identity_snapshot','archive_context'],['archive_identity_snapshot']);return selectorWindows(archiveIndex(evidence));}
export function planReviewedHeadingNavigation(input){return planHeadingNavigation(input);}
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

export function planReviewedAnchorAllocation(input){return planAnchorAllocation(input);}
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

function retainedNavigation(context,input){
 keys(context,['source_inventory_sha256','destinations','references']);
 if(typeof context.source_inventory_sha256!=='string'||!(/^[0-9a-f]{64}$/).test(context.source_inventory_sha256))throw TypeError('Invalid navigation inventory digest');
 const seen=new Set();
 for(const [field,kinds]of [['destinations',['heading','anchor']],['references',['link','button']]]){
  const entries=context[field];if(!Array.isArray(entries)||entries.length>4096)throw TypeError('Invalid retained navigation entries');
  for(const entry of entries){
   keys(entry,field==='destinations'?['source_path','kind','source_name','destination_name']:['source_path','kind','source_target','destination_target']);
   const path=entry.source_path;
   if(!Array.isArray(path)||!path.length||path.length>128||path.some(n=>!Number.isSafeInteger(n)||n<0)||!input.block_indices.includes(path[0])||!kinds.includes(entry.kind))throw TypeError('Invalid retained navigation path');
   const key=entry.kind+':'+stableStringify(path);if(seen.has(key))throw TypeError('Duplicate retained navigation entry');seen.add(key);
   for(const value of field==='destinations'?[entry.source_name,entry.destination_name]:[entry.source_target,entry.destination_target])if(typeof value!=='string'||!value||value.length>16384)throw TypeError('Invalid retained navigation target');
  }
 }
 const first=input.steps[0],selected=schema.nodeFromJSON({type:'doc',content:first.slice.content}),actualDestinations=[];
 const visit=(node,path)=>{const mapped=[input.block_indices[path[0]],...path.slice(1)];if(node.type.name==='heading'||node.type.name==='relayAnchor')actualDestinations.push([mapped,node.type.name==='heading'?'heading':'anchor']);for(let i=0;i<node.childCount;i++)visit(node.child(i),[...path,i]);};
 for(let i=0;i<selected.childCount;i++)visit(selected.child(i),[i]);
 const claimed=context.destinations.map(entry=>[entry.source_path,entry.kind]);
 const order=entries=>entries.map(stableStringify).sort();
 if(!same(order(actualDestinations),order(claimed)))throw TypeError('Retained navigation destination inventory is incomplete');
 return planHeadingNavigation(input,context);
}

function reviewedSpliceGeometry(evidence,interpret,validateSlice=()=>{},navigation=null){
 const {operation}=evidence;
 keys(operation,['kind','steps','copies','group','reviewed_recovery'],['kind','steps','copies','reviewed_recovery']);
 const review=operation.reviewed_recovery;
 keys(review,['archive_sha256','reviewed_document_sha256','block_indices','target_guard','donor_cut']);
 for(const field of ['archive_sha256','reviewed_document_sha256'])if(typeof review[field]!=='string'||!/^[0-9a-f]{64}$/.test(review[field]))throw TypeError('Invalid reviewed archive digest');
 const indices=review.block_indices;
 if(!Array.isArray(indices)||!indices.length||indices.length>4096||indices.some((value,i)=>!Number.isSafeInteger(value)||value<0||(i&&value<=indices[i-1])))throw TypeError('Invalid reviewed block indices');
 const guard=review.target_guard;
 if(guard&&Object.hasOwn(guard,'body_revision')){keys(guard,['body_revision']);if(typeof guard.body_revision!=='string'||!/^sha256:[0-9a-f]{64}$/.test(guard.body_revision))throw TypeError('Invalid reviewed target guard');}
 else {keys(guard,['draft_revision']);if(!Number.isSafeInteger(guard.draft_revision)||guard.draft_revision<1)throw TypeError('Invalid reviewed target guard');}
 if(review.donor_cut!==null){keys(review.donor_cut,['document_id','incarnation','through_update_id']);canonicalOperationID(review.donor_cut.document_id);canonicalOperationID(review.donor_cut.incarnation);if(!Number.isSafeInteger(review.donor_cut.through_update_id)||review.donor_cut.through_update_id<0)throw TypeError('Invalid reviewed donor cut');}
 if(operation.copies.length)throw TypeError('Complete recovery append cannot claim ordinary copies');
 const sender=index(evidence.sender_before_snapshot),senderAfter=index(evidence.sender_after_snapshot),after=index(evidence.after_snapshot);
 const before=schema.nodeFromJSON(sender.pm);
 const first=operation.steps?.[0];
 keys(first,['stepType','from','to','slice']);
 const append=first.stepType==='replace'&&first.from===before.content.size&&first.to===first.from;
 const replacement=first.stepType==='replace'&&first.from===0&&first.to===before.content.size;
 if(!append&&!replacement)throw TypeError('Reviewed recovery requires root-end append or complete root replacement');
 keys(first.slice,['content','openStart','openEnd'],['content']);
 if((first.slice.openStart??0)!==0||(first.slice.openEnd??0)!==0||!Array.isArray(first.slice.content)||first.slice.content.length!==indices.length)throw TypeError('Reviewed recovery requires complete closed blocks');
 const targets=first.slice.content.map(node=>schema.nodeFromJSON(node));
 const sourceMetadata=validateSlice(targets,indices);
 const totalSize=targets.reduce((n,node)=>n+node.nodeSize,0),lower=first.from,upper=lower+totalSize;
 const firstApplied=Step.fromJSON(schema,first).apply(before);
 if(firstApplied.failed)throw TypeError('Refused maintained reviewed splice');
 let intermediate=firstApplied.doc.toJSON(),metadataSteps=0;
 const baseSteps=[first],navigationSteps=[];
 // Repairs are exact maintained allocator operations inside the imported Slice.
 // Structural IDs are replica identities. Heading anchors are retained authored
 // values unless the current PaperHeading rule requires a destination repair.
 for(const step of operation.steps.slice(1)){
  if(step.stepType==='removeMark'||step.stepType==='addMark'||step.stepType==='attr'&&step.attr==='target'){
   if(!navigation)throw TypeError('Reviewed navigation repair requires original correspondence');
   const applied=Step.fromJSON(schema,step).apply(schema.nodeFromJSON(intermediate));
   if(applied.failed)throw TypeError('Refused maintained navigation repair');
   intermediate=applied.doc.toJSON();navigationSteps.push(step);continue;
  }
  baseSteps.push(step);
  if(step.stepType==='docAttr'){
   keys(step,['stepType','attr','value']);
   if(!replacement||step.attr!=='relaymark'||++metadataSteps>1||sourceMetadata!==undefined&&!same(step.value,sourceMetadata))throw TypeError('Illegal reviewed metadata replacement');
   const applied=Step.fromJSON(schema,step).apply(schema.nodeFromJSON(intermediate));
   if(applied.failed)throw TypeError('Refused maintained reviewed metadata');intermediate=applied.doc.toJSON();continue;
  }
  const attributeStep=step.stepType==='attr';
  const position=attributeStep?step.pos:step.from;
  if(attributeStep)keys(step,['stepType','pos','attr','value']);
  else if(step.stepType!=='replaceAround'&&step.stepType!=='replace')throw TypeError('Illegal reviewed append repair');
  if(!Number.isSafeInteger(position)||position<lower||position>=upper)throw TypeError('Illegal reviewed append repair');
  const doc=schema.nodeFromJSON(intermediate),node=doc.nodeAt(position);
  if(!node||!Object.hasOwn(node.attrs,'relaymarkId')||position+node.nodeSize>upper)throw TypeError('Unavailable reviewed repair node');
  const attrs=step.slice?.content?.[0]?.attrs;
  const changed=attributeStep?[step.attr]:Object.keys({...node.attrs,...attrs}).filter(key=>!same(node.attrs[key],attrs?.[key]));
  if(changed.length!==1||!['relaymarkId','headingId','name','id'].includes(changed[0]))throw TypeError('Illegal reviewed append repair');
  const field=changed[0],value=attributeStep?step.value:attrs[field];
  let matches=0;
  if(field==='relaymarkId'){
   doc.descendants(n=>{if(n.attrs.relaymarkId===node.attrs.relaymarkId)matches++;});
   if(node.attrs.relaymarkId!==null&&matches<2)throw TypeError('Reviewed repair changed a unique authored identity');
   if(typeof value!=='string'||value===node.attrs.relaymarkId)throw TypeError('Invalid reviewed allocated identity');
  }else if(field==='id'){
   if(!['questionBlock','questionOption'].includes(node.type.name))throw TypeError('Unavailable reviewed form identity repair');
   let allocatedUsed=false;
   doc.descendants(n=>{if(['questionBlock','questionOption'].includes(n.type.name)&&n.attrs.id===node.attrs.id)matches++;if(n.attrs.id===value)allocatedUsed=true;});
   if(node.attrs.id!==null&&matches<2)throw TypeError('Reviewed repair changed a unique authored form identity');
   canonicalOperationID(value);
   if(value===node.attrs.id||allocatedUsed)throw TypeError('Invalid reviewed allocated form identity');
  }else if(field==='name'){
   if(!navigation||!attributeStep||node.type.name!=='relayAnchor'||typeof value!=='string'||!/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(value))throw TypeError('Illegal reviewed Anchor repair');
  }else{
   if(node.type.name!=='heading')throw TypeError('Unavailable reviewed heading repair');
   const anchor=node.attrs.headingId,valid=typeof anchor==='string'&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(anchor);
   let allocatedUsed=false,needsRepair=!valid;
   doc.descendants((n,pos)=>{
    const name=n.type.name==='heading'?n.attrs.headingId:n.type.name==='relayAnchor'?n.attrs.name:null;
    if(name===anchor&&(n.type.name==='relayAnchor'||n.type.name==='heading'&&pos<position))needsRepair=true;
    if(name===value)allocatedUsed=true;
   });
   if(!needsRepair)throw TypeError('Reviewed repair changed a unique authored heading anchor');
   // A repaired anchor cannot silently redirect an imported navigation target.
   // Preserve valid unchanged anchors; unsupported ambiguous/absent source
   // destinations require explicit review instead of an inferred link rewrite.
   let referenced=false;
   const checkTarget=target=>{if(typeof target==='string'&&(!valid||target===anchor))referenced=true;};
   const inspect=n=>{
    for(const mark of n.marks)if(mark.type.name==='link'&&typeof mark.attrs.href==='string'&&mark.attrs.href.startsWith('#')){
     let target=mark.attrs.href.slice(1);try{target=decodeURIComponent(target);}catch{}checkTarget(target);
    }
    if(n.type.name==='relayButton'&&n.attrs.kind==='anchor')checkTarget(n.attrs.target);
   };
   for(const target of targets){inspect(target);target.descendants(inspect);}
   if(referenced&&!navigation)throw TypeError('Reviewed heading repair would alter imported internal destination');
   if(typeof value!=='string'||!/^h-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value)||allocatedUsed)throw TypeError('Invalid reviewed allocated heading anchor');
  }
  // UniqueID and PaperHeading use setNodeMarkup; native emits AttrStep. The
  // exact maintained Step must change this one permitted identity field only.
  const repair=new Transform(doc);
  if(attributeStep)repair.setNodeAttribute(position,field,value);
  else repair.setNodeMarkup(position,null,{...node.attrs,[field]:value},node.marks);
  if(repair.steps.length!==1||!same(repair.steps[0].toJSON(),step))throw TypeError('Illegal reviewed append repair');
  const applied=Step.fromJSON(schema,step).apply(doc);if(applied.failed)throw TypeError('Refused maintained identity repair');intermediate=applied.doc.toJSON();
 }
 let navigationCorrespondence;
 if(navigation){
  const input={before_document:sender.pm,block_indices:indices,steps:baseSteps};
  const planned=navigation.archive_document?planHeadingNavigation({...input,archive_document:navigation.archive_document}):retainedNavigation(navigation.navigation_correspondence,input);
  if(!same(planned.steps,navigationSteps)||!same(planned.document,intermediate))throw TypeError('Reviewed navigation Steps disagree with original correspondence');
  navigationCorrespondence=planned.navigation_correspondence;
 }
 if(replacement&&sourceMetadata!==undefined&&!same(schema.nodeFromJSON(intermediate).attrs.relaymark,sourceMetadata))throw TypeError('Reviewed replacement metadata differs from original archive');
 const expected=interpret(sender.pm,operation);
 if(!same(expected.document,senderAfter.pm)||!same(intermediate,senderAfter.pm))throw TypeError('Reviewed append result disagrees with maintained steps');
 return {operation,review,indices,sender,senderAfter,after,before,targets,lower,upper,navigationCorrespondence};
}

export function prepareReviewedRecoveryWitness(evidence,interpret){
 const fields=['sender_before_snapshot','sender_after_snapshot','before_snapshot','after_snapshot','before_state_vector','operation','footprint'];
 keys(evidence,[...fields,'archive_identity_snapshot','reviewed_document','archive_context'],[...fields,'archive_identity_snapshot','reviewed_document']);
 const archive=archiveIndex(evidence),original=schema.nodeFromJSON(archive.pm);let sourceBlocks;
 const {operation,indices,senderAfter,after,lower,navigationCorrespondence}=reviewedSpliceGeometry(evidence,interpret,(targets,indices)=>{
 if(indices.some(i=>i>=original.childCount))throw TypeError('Unavailable reviewed archive block');
 const reviewed={...archive.document,blocks:indices.map(i=>archive.document.blocks[i])};
 const reviewedPM=schema.nodeFromJSON(relayMarkToProseMirror(evidence.reviewed_document));
 if(!same(reviewed,evidence.reviewed_document))throw TypeError('Reviewed document differs from selected archive blocks');
 const stripID=node=>{const result={...node};if(node.attrs){const {relaymarkId,...attrs}=node.attrs;result.attrs=attrs;}if(node.content)result.content=node.content.map(stripID);return result;};
 sourceBlocks=indices.map(i=>original.child(i));
 // The exact Slice ordinal is the source pointer. IDs may be newly allocated by
 // the canonical writer, while every other field/mark/atom/child remains exact.
 for(let i=0;i<targets.length;i++)if(!same(stripID(sourceBlocks[i].toJSON()),stripID(targets[i].toJSON())))throw TypeError('Reviewed Slice changed archive content or properties');
 return reviewedPM.attrs.relaymark;
 },{archive_document:original.toJSON()});
 const navigationLinks=[];
 for(const reference of navigationCorrespondence.references.filter(r=>r.kind==='link'&&r.source_target!==r.destination_target)){
  let node=original,position=0;
  for(const [depth,child]of reference.source_path.entries()){for(let i=0;i<child;i++)position+=node.child(i).nodeSize;if(depth)position++;node=node.child(child);}
  navigationLinks.push({from:position,to:position+node.nodeSize,reference});
 }
 const frontier=clocks(evidence.before_state_vector),regions=[],destinations=[];let units=0,totalRuns=0;
 let destinationStart=lower;
 const originalStarts=[];let sourceStart=0;original.forEach(node=>{originalStarts.push(sourceStart);sourceStart+=node.nodeSize;});
 for(let selected=0;selected<indices.length;selected++){
  const blockIndex=indices[selected],sourceBlockStart=originalStarts[blockIndex];
  for(const run of archive.runs.filter(run=>run.path[0]===blockIndex)){
   const destinationPosition=destinationStart+run.position-sourceBlockStart,end=destinationPosition+run.count;
   const parts=senderAfter.runs.filter(part=>part.position<end&&part.position+part.count>destinationPosition).sort((a,b)=>a.position-b.position);
   let cursor=destinationPosition;const mapped=[];
   for(const part of parts){
    const from=Math.max(cursor,part.position),to=Math.min(end,part.position+part.count);if(from!==cursor||to<=from)throw TypeError('Unavailable reviewed destination interval');
    const itemClock=part.item.clock+from-part.position;
    if(itemClock<(frontier.get(part.item.client)||0))throw TypeError('Reviewed append borrowed retained target text');
    const text=part.text.slice(from-part.position,to-part.position),sourceText=run.text.slice(from-destinationPosition,to-destinationPosition);unicode(text);unicode(sourceText);
    const sourcePosition=run.position+from-destinationPosition,link=navigationLinks.find(link=>sourcePosition>=link.from&&sourcePosition+to-from<=link.to);
    const attributes=link?{...run.attributes,link:{...run.attributes.link,href:link.reference.destination_target}}:run.attributes;
    if(link&&run.attributes.link?.href!==link.reference.source_target||text!==sourceText||!same(part.attributes,attributes))throw TypeError('Reviewed regional text or full marks disagree');
    mapped.push({type:part.type,item:{client:part.item.client,clock:itemClock},count:to-from});cursor=to;
   }
   if(cursor!==end||(units+=run.count)>MAX_UNITS||regions.length>=4096)throw TypeError('Incomplete or oversized reviewed recovery regions');
   if((totalRuns+=mapped.length)>4096)throw TypeError('Reviewed destination run limit exceeded');
   const destination={runs:mapped},resolved=resolve(after,destination);equalContent(resolve(senderAfter,destination),resolved);
   destinations.push(...resolved);regions.push({archive_path:run.path,archive_offset:run.offset,count:run.count,destination});
  }
  destinationStart+=sourceBlocks[selected].nodeSize;
 }
 const prepared=prepare({...Object.fromEntries(fields.map(field=>[field,evidence[field]])),text_items:{runs:[]}},interpret,destinations);
 return {...prepared,operation,recovery_regions:regions,...(navigationCorrespondence?{navigation_correspondence:navigationCorrespondence}:{}),complete_recovery_correspondence:true,requires_recovery_authorization:true};
}

/** Target-only replay of an already issued reviewed association. The host must
 * authenticate its exact original annotation, regions, command/update hashes,
 * namespace and actor/owner. Paths and donor content are not rediscovered here.
 * Full maintained mutation replay remains an independent mandatory proof. */
export function prepareRetainedReviewedRecoveryWitness(evidence,interpret){
 const fields=['sender_before_snapshot','sender_after_snapshot','before_snapshot','after_snapshot','before_state_vector','operation','footprint'];
 keys(evidence,[...fields,'regional_context','navigation_correspondence'],[...fields,'regional_context']);
 const context=evidence.regional_context;keys(context,['recovery_regions','human_destinations']);
 const {operation,indices,senderAfter,after,targets,lower,navigationCorrespondence}=reviewedSpliceGeometry(evidence,interpret,()=>{},Object.hasOwn(evidence,'navigation_correspondence')?{navigation_correspondence:evidence.navigation_correspondence}:null);
 const regions=context.recovery_regions,frontier=clocks(evidence.before_state_vector),destinations=[],sources=new Map();
 if(!Array.isArray(regions)||regions.length>4096)throw TypeError('Invalid retained recovery regions');
 const blocks=new Map();let position=lower,units=0,totalRuns=0;
 for(let i=0;i<indices.length;i++){blocks.set(indices[i],[position,position+targets[i].nodeSize]);position+=targets[i].nodeSize;}
 for(const region of regions){
  keys(region,['archive_path','archive_offset','count','destination']);
  const path=region.archive_path,offset=region.archive_offset,count=region.count;
  if(!Array.isArray(path)||!path.length||path.length>128||path.some(n=>!Number.isSafeInteger(n)||n<0)||!blocks.has(path[0])||!Number.isSafeInteger(offset)||offset<0||!Number.isSafeInteger(count)||count<1||!Number.isSafeInteger(offset+count)||(units+=count)>MAX_UNITS)throw TypeError('Invalid retained archive extent');
  selection(region.destination);if(region.destination.runs.reduce((n,r)=>n+r.count,0)!==count||(totalRuns+=region.destination.runs.length)>4096)throw TypeError('Mismatched retained recovery extent');
  const observed=resolve(senderAfter,region.destination),locked=resolve(after,region.destination),[start,end]=blocks.get(path[0]);
  let cursor=observed[0]?.position;
  for(const part of observed){
   if(part.position!==cursor||part.position<start||part.position+part.count>end||part.item.clock<(frontier.get(part.item.client)||0))throw TypeError('Retained recovery destination is outside its fresh appended block');
   cursor+=part.count;
  }
  equalContent(observed,locked);
  const key=stableStringify(path),prior=sources.get(key)||[],base=observed[0].position-offset;
  if(prior.some(p=>p.offset<offset+count&&p.offset+p.count>offset)||prior.some(p=>p.base!==base))throw TypeError('Overlapping or displaced retained archive regions');
  prior.push({offset,count,base});sources.set(key,prior);destinations.push(...locked);
 }
 disjoint(destinations);
 const human=resolve(after,context.human_destinations);cover(human,destinations);
 // Original source-region authentication is external. Independently recheck
 // every current typed destination and the entire imported allocation union.
 const senderFresh=freshRuns(senderAfter,frontier);cover(senderFresh,destinations);cover(destinations,senderFresh);
 const prepared=prepare({...Object.fromEntries(fields.map(field=>[field,evidence[field]])),text_items:{runs:[]}},interpret,destinations);
 return {...prepared,operation,recovery_regions:regions,...(navigationCorrespondence?{navigation_correspondence:navigationCorrespondence}:{}),complete_recovery_correspondence:true,requires_recovery_authorization:true};
}



function evidenceForArchive(evidence){return {archive_identity_snapshot:evidence.archive_identity_snapshot,...(Object.hasOwn(evidence,'archive_context')?{archive_context:evidence.archive_context}:{})};}
function reviewedRegions(evidence){
 keys(evidence,['archive_identity_snapshot','recovery_regions','archive_context'],['archive_identity_snapshot','recovery_regions']);
 const archive=archiveIndex(evidence),regions=evidence.recovery_regions,byPath=new Map();
 for(const run of archive.runs){const key=stableStringify(run.path),list=byPath.get(key)||[];list.push(run);byPath.set(key,list);}
 for(const list of byPath.values())list.sort((a,b)=>a.offset-b.offset);
 if(!Array.isArray(regions)||regions.length>4096)throw TypeError('Invalid reviewed regional selection');
 const sources=[],destinations=[],validated=[];let units=0,runs=0;
 for(const region of regions){
  keys(region,['archive_path','archive_offset','count','destination']);
  if(!Array.isArray(region.archive_path)||region.archive_path.length>128||region.archive_path.some(value=>!Number.isSafeInteger(value)||value<0)||!Number.isSafeInteger(region.archive_offset)||region.archive_offset<0||!Number.isSafeInteger(region.count)||region.count<1||(units+=region.count)>MAX_UNITS)throw TypeError('Invalid reviewed archive extent');
  selection(region.destination);if(region.destination.runs.reduce((n,run)=>n+run.count,0)!==region.count||(runs+=region.destination.runs.length)>4096)throw TypeError('Mismatched reviewed destination extent');
  const start=region.archive_offset,end=start+region.count,parts=[];let cursor=start;
  for(const run of byPath.get(stableStringify(region.archive_path))||[]){
   const from=Math.max(start,run.offset),to=Math.min(end,run.offset+run.count);if(to<=from)continue;
   if(from!==cursor)throw TypeError('Unavailable reviewed archive interval');
   const text=run.text.slice(from-run.offset,to-run.offset);unicode(text);
   parts.push({...run,item:{client:run.item.client,clock:run.item.clock+from-run.offset},count:to-from,offset:from,text});cursor=to;
  }
  if(cursor!==end)throw TypeError('Unavailable reviewed archive interval');
  sources.push(...parts);destinations.push(...region.destination.runs);validated.push(region);
 }
 disjoint(sources);disjoint(destinations);selection(plain(sources));return {archive,regions:validated,sources};
}
/** Bounded candidate IDs only. No donor-human or recovery authority is issued. */
export function reviewedRecoverySourceSelection(evidence){return plain(reviewedRegions(evidence).sources);}
/** Caller-authenticated HUMAN archive candidates -> exact recomputed imported
 * destinations. Regions/offsets are structural pointers, never equal-text search
 * or same-namespace copy ancestry. This result grants no donor authority. */
export function mapReviewedRecoverySelection(evidence){
 keys(evidence,['archive_identity_snapshot','recovery_regions','source_selector','archive_context'],['archive_identity_snapshot','recovery_regions','source_selector']);
 const {archive,regions}=reviewedRegions({...evidenceForArchive(evidence),recovery_regions:evidence.recovery_regions});
 const human=resolve(archive,evidence.source_selector),mapped=[];
 for(const region of regions){
  for(const source of human){
   if(!same(source.path,region.archive_path))continue;
   const from=Math.max(source.offset,region.archive_offset),to=Math.min(source.offset+source.count,region.archive_offset+region.count);if(to<=from)continue;
   unicode(source.text.slice(from-source.offset,to-source.offset));
   let offset=0;
   for(const destination of region.destination.runs){
    const left=Math.max(from-region.archive_offset,offset),right=Math.min(to-region.archive_offset,offset+destination.count);
    if(left<right)mapped.push({type:destination.type,item:{client:destination.item.client,clock:destination.item.clock+left-offset},count:right-left});
    offset+=destination.count;
   }
  }
 }
 const result={runs:mapped};selection(result);return {destination:result};
}

/** Internal maintained replay layout. This reuses the witness's exact schema
 * projection; positions are not a caller-authenticated source credential. */
export function contentEditIdentityLayout(snapshot,decode=snapshotToDocument){return index(snapshot,decode);}
