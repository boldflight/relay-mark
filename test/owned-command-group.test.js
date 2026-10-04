import test from 'node:test';import assert from 'node:assert/strict';import * as Y from 'yjs';
import {bindOwnedCommandGroup,readOwnedCommandGroup} from '../adapters/collaboration/owned-command-group.js';
const first='11111111-1111-4111-8111-111111111111',second='22222222-2222-4222-8222-222222222222',third='33333333-3333-4333-8333-333333333333';
test('actual maintained typing group binds both command receipts without replacing selection metadata',()=>{
 const doc=new Y.Doc({gc:false}),text=doc.getText('text'),origin={},manager=new Y.UndoManager(text,{trackedOrigins:new Set([origin]),captureTimeout:Infinity});let id=first;
 const onEvent=e=>{e.stackItem.meta.set('selection','retained caret');bindOwnedCommandGroup(manager,e,id)};manager.on('stack-item-added',onEvent);manager.on('stack-item-updated',onEvent);
 doc.transact(()=>text.insert(0,'A'),origin);assert.deepEqual(readOwnedCommandGroup(manager,first),{reference:first,operation_ids:[first]});
 id=second;doc.transact(()=>text.insert(1,'🌍'),origin);assert.equal(manager.undoStack.length,1);assert.deepEqual(readOwnedCommandGroup(manager,second),{reference:first,operation_ids:[first,second]});assert.equal(manager.undoStack[0].meta.get('selection'),'retained caret');
 manager.stopCapturing();id=third;doc.transact(()=>text.insert(3,'!'),origin);assert.deepEqual(readOwnedCommandGroup(manager,third),{reference:third,operation_ids:[third]});
 assert.throws(()=>bindOwnedCommandGroup(manager,{type:'undo',stackItem:manager.undoStack[0]},first),/actual maintained/);
 assert.throws(()=>bindOwnedCommandGroup(manager,{type:'undo',stackItem:manager.undoStack[1]},first),/Duplicate/);assert.deepEqual(readOwnedCommandGroup(manager,third),{reference:third,operation_ids:[third]});manager.destroy();doc.destroy();
});
