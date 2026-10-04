/** Canonical XML branch safety on the actual maintained UndoManager.
 * The popped StackItem still chooses every inverse. This filter only preserves
 * a valid structural skeleton when its deletion would hide surviving edits. */
import * as Y from 'yjs';
const installed=new WeakMap();
export function protectOwnedHistoryBranches(manager){
 if(installed.has(manager))return installed.get(manager);
 if(manager?.supportsUndoDeleteContext!==true)throw TypeError('Maintained UndoManager deletion context is unavailable');
 const previous=manager.deleteFilter,contexts=new WeakMap();
 manager.deleteFilter=(item,context)=>{let protectedItems=contexts.get(context);if(!protectedItems){protectedItems=protectedSkeleton(context.itemsToDelete);contexts.set(context,protectedItems)}return !protectedItems.has(item)&&previous(item,context)};
 const release=()=>{manager.deleteFilter=previous;installed.delete(manager)};
 installed.set(manager,release);return release;
}
function protectedSkeleton(items){
 const owned=new Set(items),protectedItems=new Set();
 const xml=item=>item.content instanceof Y.ContentType&&(item.content.type instanceof Y.XmlElement||item.content.type instanceof Y.XmlText);
 const roots=items.filter(item=>xml(item)&&!hasOwnedAncestor(item));
 function hasOwnedAncestor(item){let parent=item.parent;while(parent?._item){if(owned.has(parent._item)&&xml(parent._item))return true;parent=parent._item.parent}return false}
 for(const root of roots){const skeleton=new Set([root]),pending=[root.content.type];let survivor=false;
  while(pending.length){const branch=pending.pop();
   for(const item of branch._map.values()){if(item.deleted)continue;skeleton.add(item);if(!owned.has(item))survivor=true;}
   for(let item=branch._start;item;item=item.right){if(item.deleted)continue;if(!owned.has(item))survivor=true;if(xml(item)){skeleton.add(item);pending.push(item.content.type)}}
  }
  if(survivor)for(const item of skeleton)protectedItems.add(item);
 }
 return protectedItems;
}
