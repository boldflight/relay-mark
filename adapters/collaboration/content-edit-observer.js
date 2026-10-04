/** Read-only evidence from the pinned maintained Yjs owner. No authorship,
 * permission, editor command, or replica lifecycle is inferred by this observer. */
import * as Y from 'yjs';
import {cloneCanonicalJSON as cloneJSON} from '../../src/canonical-json.js';
const id=value=>({client:value.client,clock:value.clock});
const optionalID=value=>value?id(value):null;
function budget(maximumSteps){if(!Number.isSafeInteger(maximumSteps)||maximumSteps<1||maximumSteps>1_000_000)throw Error('Invalid observation budget');let remaining=maximumSteps;return()=>{if(--remaining<0)throw Error('Observation budget exhausted')};}
function settled(doc){if(!doc||doc.gc||doc.store.pendingStructs||doc.store.pendingDs)throw Error('Observation requires a settled retained owner');}
function parent(item){const branch=item.parent;if(!branch||typeof branch==='string'||branch instanceof Y.ID)throw Error('Unavailable retained parent');return branch._item?{type:id(branch._item.id)}:{root:Y.findRootTypeKey(branch)};}
function content(item,step){step();const value=item.content;
 if(value instanceof Y.ContentString)return {kind:'string',text:value.str};
 if(value instanceof Y.ContentFormat)return {kind:'format',key:value.key,value:cloneJSON(value.value)};
 if(value instanceof Y.ContentAny)return {kind:'any',values:cloneJSON(value.arr)};
 if(value instanceof Y.ContentEmbed)return {kind:'embed',value:cloneJSON(value.embed)};
 if(value instanceof Y.ContentJSON)return {kind:'json',values:value.arr.map(v=>JSON.stringify(cloneJSON(v)))};
 if(value instanceof Y.ContentBinary)return {kind:'binary',bytes:[...value.content]};
 if(value instanceof Y.ContentType){const branch=value.type;let type_kind,name=null;
  if(branch instanceof Y.XmlElement){type_kind='xml_element';name=branch.nodeName}
  else if(branch instanceof Y.XmlText)type_kind='xml_text';
  else if(branch instanceof Y.XmlFragment)type_kind='xml_fragment';
  else if(branch instanceof Y.Text)type_kind='text';
  else if(branch instanceof Y.Map)type_kind='map';
  else if(branch instanceof Y.Array)type_kind='array';
  else throw Error('Unsupported retained type');
  return {kind:'type',type_kind,name};
 }
 throw Error('Unsupported or pruned retained content');
}
/** Exact ordered rich XML identity tree; text runs preserve physical item splits. */
export function captureContentEditSnapshot(root,{maximumSteps=1_000_000}={}){
 settled(root.doc);const step=budget(maximumSteps);
 function visit(branch,depth){step();if(depth>128)throw Error('Observation depth exceeded');
  if(branch._item?.deleted)throw Error('Unavailable XML branch');
  if(branch instanceof Y.XmlText){if(Object.keys(branch.getAttributes()).length)throw Error('Unsupported XML text attributes');const attributes={},runs=[];
   for(let item=branch._start;item;item=item.right){step();if(item.deleted)continue;
    if(item.content instanceof Y.ContentFormat){if(item.content.value===null)delete attributes[item.content.key];else attributes[item.content.key]=cloneJSON(item.content.value);continue}
    if(!(item.content instanceof Y.ContentString))throw Error('Unsupported visible text content');
    runs.push({item:id(item.id),count:item.length,text:item.content.str,attributes:cloneJSON(attributes)});
   }
   if(!branch._item)throw Error('Unavailable XML text identity');return {kind:'text',type:id(branch._item.id),runs};
  }
  if(!(branch instanceof Y.XmlFragment))throw Error('Unsupported XML branch');const children=[];
  for(let item=branch._start;item;item=item.right){step();if(item.deleted)continue;if(!(item.content instanceof Y.ContentType))throw Error('Unsupported XML child');children.push(visit(item.content.type,depth+1))}
  if(branch instanceof Y.XmlElement){if(!branch._item)throw Error('Unavailable XML element identity');return {kind:'element',type:id(branch._item.id),name:branch.nodeName,attributes:cloneJSON(branch.getAttributes()),children}}
  return {kind:'fragment',root:Y.findRootTypeKey(branch),children};
 }
 const result=visit(root,0),metadata=root.doc.share.get('relaymark');
 if(metadata){if(!(metadata instanceof Y.Map))throw Error('Unsupported authored metadata root');const value=cloneJSON(metadata.toJSON());if(Object.keys(value).length)result.metadata=value;}
 return result;
}
/** Decode the exact original update with the maintained codec and inspect every
 * struct/delete range against its retained settled candidate, including hidden writes. */
export function captureContentEditFootprint(doc,bytes,{maximumSteps=1_000_000}={}){
 settled(doc);if(!(bytes instanceof Uint8Array)||bytes.length>8*1024*1024)throw Error('Invalid original update bytes');const step=budget(maximumSteps);let decoder;class CheckedDecoder extends Y.UpdateDecoderV1{constructor(value){super(value);decoder=this}}const decoded=Y.decodeUpdateV2(bytes,CheckedDecoder);if(decoder.restDecoder.pos!==bytes.length)throw Error('Trailing original update bytes');const current=Y.decodeStateVector(Y.encodeStateVector(doc));
 const structs=decoded.structs.map(item=>{step();if(!(item instanceof Y.Item)||!Number.isSafeInteger(item.id.clock+item.length)||item.id.clock+item.length>2**32||item.id.clock+item.length>(current.get(item.id.client)||0))throw Error('Unavailable original update item');
  const stored=Y.getItem(doc.store,item.id);if(!(stored instanceof Y.Item))throw Error('Unavailable retained item');
  return {item:id(item.id),count:item.length,parent:parent(stored),key:stored.parentSub??null,origin:optionalID(item.origin),right_origin:optionalID(item.rightOrigin),content:content(item,step),deleted:stored.deleted};
 }).sort((a,b)=>a.item.client-b.item.client||a.item.clock-b.item.clock);
 const declared_deletes=[],deleted_items=[];
 for(const [client,ranges]of [...decoded.ds.clients].sort((a,b)=>a[0]-b[0]))for(const range of ranges){step();const end=range.clock+range.len;if(!Number.isSafeInteger(end)||range.len<1||end>2**32)throw Error('Invalid declared delete');declared_deletes.push({item:{client,clock:range.clock},count:range.len});
  for(let clock=range.clock;clock<end;){step();const stored=Y.getItem(doc.store,Y.createID(client,clock));if(!(stored instanceof Y.Item)||!stored.deleted)throw Error('Unavailable declared deletion');const next=Math.min(end,stored.id.clock+stored.length);if(next<=clock)throw Error('Invalid retained deletion');deleted_items.push({item:{client,clock},count:next-clock,stored_item:id(stored.id),stored_count:stored.length,parent:parent(stored),key:stored.parentSub??null,content:content(stored,step)});clock=next;}
 }
 return {state_vector:[...current].sort((a,b)=>a[0]-b[0]).map(([client,clock])=>({client,clock})),structs,declared_deletes,deleted_items};
}
