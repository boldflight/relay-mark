/** Bind receipt UUIDs onto the actual maintained UndoManager StackItem. The host
 * owns event subscription, command lifecycle, origin and accepted authorization. */
import {canonicalOperationID,validateOwnedCommandGroup} from '../../src/owned-command-group.js';
const key='relaymark:operation_ids';
export function bindOwnedCommandGroup(manager,event,operationID){
 canonicalOperationID(operationID);const item=event?.stackItem;
 if(!manager||manager.undoing||manager.redoing||event.type!=='undo'||manager.undoStack.at(-1)!==item||!item?.meta)throw TypeError('Unavailable actual maintained command item');
 const existing=item.meta.get(key);let ids=existing?validateOwnedCommandGroup({reference:existing[0],operation_ids:existing}).operation_ids.slice():[];
 // Rebinding a command within its one transaction is idempotent; moving an
 // already bound UUID into a different stack item is refused before metadata edit.
 for(const entry of [...manager.undoStack,...manager.redoStack])if(entry!==item&&entry.meta.get(key)?.includes(operationID))throw TypeError('Duplicate owned operation UUID');
 if(ids.at(-1)!==operationID){if(ids.includes(operationID))throw TypeError('Out-of-order owned operation UUID');ids.push(operationID)}
 const group=validateOwnedCommandGroup({reference:ids[0],operation_ids:ids});item.meta.set(key,Object.freeze(ids));return group;
}
export function readOwnedCommandGroup(manager,operationID){canonicalOperationID(operationID);const item=manager?.undoStack.at(-1),ids=item?.meta.get(key);if(!ids||ids.at(-1)!==operationID)throw TypeError('No actual owned command group');return validateOwnedCommandGroup({reference:ids[0],operation_ids:ids.slice()});}
export {validateOwnedCommandGroup,validateOwnedHistory} from '../../src/owned-command-group.js';
/** Transfer the same accepted group onto the actual inverse item created by the
 * maintained manager, preserving its separately owned selection metadata. */
export function bindOwnedCommandHistory(manager,event){
 const undo=event?.type==='undo',redo=event?.type==='redo';
 if(!manager||event.origin!==manager||!(undo&&manager.undoing||redo&&manager.redoing))throw TypeError('Unavailable actual maintained inverse');
 const ids=event.stackItem?.meta.get(key),inverse=(undo?manager.redoStack:manager.undoStack).at(-1);if(!ids||!inverse?.meta)throw TypeError('Unbound actual owned inverse');
 const group=validateOwnedCommandGroup({reference:ids[0],operation_ids:ids});inverse.meta.set(key,Object.freeze(ids.slice()));return{kind:event.type,...group};
}
