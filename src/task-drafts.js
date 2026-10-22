/** Draft Tasks: which unlinked checklist items a person started on purpose
 * ("armed"), when one is finished, and what each would create. Every RelayMark
 * editor decides this the same way; spec/relaymark/editor/task-drafts-v1.json
 * holds the cases, and crates/relaymark-core/src/task_drafts.rs is the engine
 * every native client calls.
 *
 * The armed set is the client's local state and never enters the document:
 * received, pasted and historical checklists never create Tasks on their own.
 * Callers pass the set in and get the next one back. The Yjs anchor for a
 * finished draft belongs to the platform, which owns the live binding. */
import {createCanonicalEditorSchema} from './editor-model.js';
const schema=createCanonicalEditorSchema();
const truthy=value=>Boolean(value);
const wellFormed=id=>typeof id==='string'&&/^b[0-9a-f]{32}$/.test(id);
/** The web's `taskOperationId`: the block identity as a lowercase UUID, the
 * server's idempotency key for the draft's creation. */
const operationId=id=>{const hex=id.slice(1);return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20,32)}`;};
function armedOption(options){
 const armed=options?.armed;
 if(armed==null)return new Set();
 if(!Array.isArray(armed)||armed.some(id=>typeof id!=='string'))throw new TypeError('Invalid armed task drafts');
 return new Set(armed);
}
function ids(event){
 if(!Array.isArray(event?.ids)||event.ids.some(id=>typeof id!=='string'))throw new TypeError('Invalid task draft event');
 return new Set(event.ids);
}
/** Every task item with a well-formed block identity, in document order. */
/** The task items of a document once block identity is assigned. An editor
 * that has not yet given a split's new half its own identity would leave that
 * half silently unarmed, so the duplicate is refused instead. */
function identified(document){
 const found=items(document),seen=new Set();
 for(const item of found){if(seen.has(item.blockId))throw new TypeError('Task items need distinct block identities');seen.add(item.blockId);}
 return found;
}
function items(document){
 const doc=schema.nodeFromJSON(document);doc.check();
 const found=[];
 const visit=(node,contentStart,path,ancestors)=>{
  let pos=contentStart;
  node.forEach((child,_,index)=>{
   path.push(index);
   const id=child.attrs.relaymarkId;
   if(child.type.name==='taskItem'&&wellFormed(id)){
    const first=child.firstChild;
    found.push({
     blockId:id,pos,path:[...path],linked:truthy(child.attrs.entityId),
     text:first?first.textContent:'',titleSize:first?first.nodeSize:0,
     done:truthy(child.attrs.checked),parentEntityId:parent(ancestors)
    });
   }
   if(!child.isTextblock&&!child.isLeaf){ancestors.push(child);visit(child,pos+1,path,ancestors);ancestors.pop();}
   path.pop();
   pos+=child.nodeSize;
  });
 };
 visit(doc,0,[],[]);
 return found;
}
/** The web's `taskParentId`: the nearest enclosing linked task item, or the
 * last Task reference in an enclosing list item's first paragraph. */
function parent(ancestors){
 const entity=value=>typeof value==='string'&&value!==''?value:null;
 for(let i=ancestors.length-1;i>=0;i--){
  const node=ancestors[i];
  if(node.type.name==='taskItem'&&entity(node.attrs.entityId))return entity(node.attrs.entityId);
  if(node.type.name==='taskItem'||node.type.name==='listItem'){
   let reference=null;
   node.firstChild?.descendants(child=>{
    if(child.type.name==='relayReference'&&typeof child.attrs.entityType==='string'&&child.attrs.entityType.toLowerCase()==='task')reference=entity(child.attrs.entityId);
    return true;
   });
   if(reference!=null)return reference;
  }
 }
 return null;
}
const title=item=>item.text.trim();
/** The web's `activeTaskDraft`: the caret is in the item's first paragraph. */
const holds=(item,caret)=>caret>item.pos&&caret<=item.pos+1+item.titleSize;
/** `taskDrafts`: every unlinked task item with a well-formed block identity. */
export function taskDrafts(document,options){
 const armed=armedOption(options);
 return items(document).filter(item=>!item.linked).map(item=>({
  block_id:item.blockId,operation_id:operationId(item.blockId),title:title(item),text:item.text,done:item.done,
  intent:armed.has(item.blockId)?'authored':'local',parent_entity_id:item.parentEntityId,path:item.path
 }));
}
/** The armed set after an editing event, from the documents before and after it. */
export function taskDraftArm(documents,options){
 if(!Array.isArray(documents)||documents.length!==2)throw new TypeError('Expected the documents before and after the event');
 const [before,after]=documents,armed=armedOption(options),event=options?.event??null;
 const afterItems=identified(after);
 // New items are those that were no task item before; the platform assigns
 // identity to new blocks, so a split or conversion gives each a fresh id.
 const fresh=()=>{const earlier=new Set(identified(before).map(item=>item.blockId));return afterItems.filter(item=>!item.linked&&!earlier.has(item.blockId));};
 switch(event?.kind){
  case 'input_rule':for(const item of fresh())armed.add(item.blockId);break;
  // Converting lines that already have text makes local checklist items.
  case 'command':for(const item of fresh())if(title(item)==='')armed.add(item.blockId);break;
  case 'split':{
   if(typeof event.from!=='string')throw new TypeError('Invalid task draft event');
   if(armed.has(event.from)&&afterItems.some(item=>item.blockId===event.from&&!item.linked))for(const item of fresh())armed.add(item.blockId);
   break;
  }
  case 'arm':for(const id of ids(event))armed.add(id);break;
  case 'disarm':for(const id of ids(event))armed.delete(id);break;
  // A remote change, paste or history step only prunes.
  case 'external':break;
  default:throw new TypeError('Invalid task draft event');
 }
 return {armed:afterItems.filter(item=>!item.linked&&armed.has(item.blockId)).map(item=>item.blockId)};
}
/** The armed drafts with a title that a key press, caret move or checkbox tap finishes. */
export function taskDraftBoundary(document,options){
 const armed=armedOption(options),drafts=items(document).filter(item=>!item.linked);
 const finished=item=>item!=null&&armed.has(item.blockId)&&title(item)!==''?item:null;
 const caret=key=>{
  const position=options?.[key];
  if(!Number.isSafeInteger(position)||position<0)throw new TypeError('Invalid task draft boundary');
  return drafts.find(item=>holds(item,position))??null;
 };
 // Return or a caret move while an input method is composing belongs to the
 // composition; a checkbox tap does not.
 const composing=truthy(options?.composing);
 let done;
 switch(options?.key){
  case 'return':done=composing?null:finished(caret('before'));break;
  case 'move':{if(composing){done=null;break;}const left=caret('before'),entered=caret('after');done=finished(left!=null&&(entered==null||entered.blockId!==left.blockId)?left:null);break;}
  case 'checkbox':{
   if(typeof options.block!=='string')throw new TypeError('Invalid task draft boundary');
   done=finished(drafts.find(item=>item.blockId===options.block));break;
  }
  default:throw new TypeError('Invalid task draft boundary');
 }
 return done?[done.blockId]:[];
}
