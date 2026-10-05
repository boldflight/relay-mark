/** Receipt ownership is bound to the actual maintained manager, never actor,
 * tab, join or document identity. Hosts pass the persisted UUID only when they
 * genuinely restore this same manager's archive. */
import { uuidv4 } from 'lib0/random';
import {canonicalOperationID,validateOwnedCommandGroup} from '../../src/owned-command-group.js';
const key='relaymark:operation_ids',ownerKey=Symbol.for('relaymark:history_owner');
export function bindOwnedHistoryOwner(manager,ownerID){
 canonicalOperationID(ownerID);if(!manager||!Array.isArray(manager.undoStack)||!Array.isArray(manager.redoStack))throw TypeError('Unavailable actual history owner');
 const existing=manager?.[ownerKey];if(existing&&existing!==ownerID)throw TypeError('Conflicting maintained history owner');
 for(const item of [...manager.undoStack,...manager.redoStack]){const group=item.meta?.get(key);if(group&&validateOwnedCommandGroup(group).owner_id!==ownerID)throw TypeError('Conflicting maintained history owner');}
 if(!existing)Object.defineProperty(manager,ownerKey,{value:ownerID});return ownerID;
}
export function readOwnedHistoryOwner(manager){return manager?.[ownerKey]??bindOwnedHistoryOwner(manager,uuidv4());}
function ownedGroup(manager,item){const group=validateOwnedCommandGroup(item?.meta?.get(key));if(group.owner_id!==readOwnedHistoryOwner(manager))throw TypeError('Conflicting maintained history owner');return group;}
function freeze(group){return Object.freeze({...group,operation_ids:Object.freeze(group.operation_ids.slice())});}
export function bindOwnedCommandGroup(manager,event,operationID){
 canonicalOperationID(operationID);const item=event?.stackItem;
 if(!manager||manager.undoing||manager.redoing||event.type!=='undo'||manager.undoStack.at(-1)!==item||!item?.meta)throw TypeError('Unavailable actual maintained command item');
 const ownerID=readOwnedHistoryOwner(manager),existing=item.meta.get(key),ids=existing?ownedGroup(manager,item).operation_ids.slice():[];
 for(const entry of [...manager.undoStack,...manager.redoStack])if(entry!==item&&entry.meta.get(key)&&ownedGroup(manager,entry).operation_ids.includes(operationID))throw TypeError('Duplicate owned operation UUID');
 if(ids.at(-1)!==operationID){if(ids.includes(operationID))throw TypeError('Out-of-order owned operation UUID');ids.push(operationID)}
 const group=validateOwnedCommandGroup({owner_id:ownerID,reference:ids[0],operation_ids:ids});item.meta.set(key,freeze(group));return group;
}
export function readOwnedCommandGroup(manager,operationID){canonicalOperationID(operationID);const item=manager?.undoStack.at(-1);if(!item?.meta.get(key))throw TypeError('No actual owned command group');const group=ownedGroup(manager,item);if(group.operation_ids.at(-1)!==operationID)throw TypeError('No actual owned command group');return {...group,operation_ids:group.operation_ids.slice()};}
export {validateOwnedCommandGroup,validateOwnedHistory} from '../../src/owned-command-group.js';
export function bindOwnedCommandHistory(manager,event){
 const undo=event?.type==='undo',redo=event?.type==='redo';
 if(!manager||event.origin!==manager||!(undo&&manager.undoing||redo&&manager.redoing))throw TypeError('Unavailable actual maintained inverse');
 const inverse=(undo?manager.redoStack:manager.undoStack).at(-1);if(!event.stackItem?.meta.get(key)||!inverse?.meta)throw TypeError('Unbound actual owned inverse');
 const group=ownedGroup(manager,event.stackItem);inverse.meta.set(key,freeze(group));return{kind:event.type,...group,operation_ids:group.operation_ids.slice()};
}
/** Checkpoints do not split typing groups; only a real semantic/resource boundary does. */
export function prepareOwnedCommandGroup(manager,operationID){
 canonicalOperationID(operationID);if(!manager||manager.undoing||manager.redoing)throw TypeError('Unavailable actual command owner');readOwnedHistoryOwner(manager);
 for(const item of [...manager.undoStack,...manager.redoStack])if(item.meta.get(key)&&ownedGroup(manager,item).operation_ids.includes(operationID))throw TypeError('Duplicate owned operation UUID');
 const top=manager.undoStack.at(-1),group=top?.meta.get(key)?ownedGroup(manager,top):null;
 if(top&&(!group||group.operation_ids.length===4096))manager.stopCapturing();
}
/** Check every candidate: the maintained manager may skip obsolete StackItems. */
export function prepareOwnedHistory(manager,kind){
 if(!manager||manager.undoing||manager.redoing||!['undo','redo'].includes(kind))throw TypeError('Unavailable actual inverse owner');readOwnedHistoryOwner(manager);
 const stack=kind==='undo'?manager.undoStack:manager.redoStack;if(!Array.isArray(stack))throw TypeError('Unavailable actual inverse stack');
 for(const item of stack){if(!item?.meta?.get(key))throw TypeError('Unbound actual inverse candidate');ownedGroup(manager,item);}
 return stack.length>0;
}
