import test from 'node:test';import assert from 'node:assert/strict';import * as Y from 'yjs';
import {bindOwnedCommandGroup,readOwnedCommandGroup,bindOwnedCommandHistory} from '../adapters/collaboration/owned-command-group.js';
const first='11111111-1111-4111-8111-111111111111',second='22222222-2222-4222-8222-222222222222',third='33333333-3333-4333-8333-333333333333';
test('actual maintained typing group binds both command receipts without replacing selection metadata',()=>{
 const doc=new Y.Doc({gc:false}),text=doc.getText('text'),origin={},manager=new Y.UndoManager(text,{trackedOrigins:new Set([origin]),captureTimeout:Infinity});let id=first;
 const onEvent=e=>{if(manager.undoing||manager.redoing)return;e.stackItem.meta.set('selection','retained caret');bindOwnedCommandGroup(manager,e,id)};manager.on('stack-item-added',onEvent);manager.on('stack-item-updated',onEvent);
 doc.transact(()=>text.insert(0,'A'),origin);assert.deepEqual(readOwnedCommandGroup(manager,first),{reference:first,operation_ids:[first]});
 id=second;doc.transact(()=>text.insert(1,'🌍'),origin);assert.equal(manager.undoStack.length,1);assert.deepEqual(readOwnedCommandGroup(manager,second),{reference:first,operation_ids:[first,second]});assert.equal(manager.undoStack[0].meta.get('selection'),'retained caret');
 manager.stopCapturing();id=third;doc.transact(()=>text.insert(3,'!'),origin);assert.deepEqual(readOwnedCommandGroup(manager,third),{reference:third,operation_ids:[third]});
 assert.throws(()=>bindOwnedCommandGroup(manager,{type:'undo',stackItem:manager.undoStack[0]},first),/actual maintained/);
 assert.throws(()=>bindOwnedCommandGroup(manager,{type:'undo',stackItem:manager.undoStack[1]},first),/Duplicate/);assert.deepEqual(readOwnedCommandGroup(manager,third),{reference:third,operation_ids:[third]});let inverse;manager.on('stack-item-popped',e=>{inverse=bindOwnedCommandHistory(manager,e)});manager.undo();assert.deepEqual(inverse,{kind:'undo',reference:third,operation_ids:[third]});assert.equal(text.toString(),'A🌍');manager.undo();assert.deepEqual(inverse,{kind:'undo',reference:first,operation_ids:[first,second]});assert.equal(text.toString(),'');manager.redo();assert.deepEqual(inverse,{kind:'redo',reference:first,operation_ids:[first,second]});assert.equal(text.toString(),'A🌍');assert.throws(()=>bindOwnedCommandHistory(manager,{type:'undo',origin:manager,stackItem:manager.undoStack[0]}),/actual maintained inverse/);manager.destroy();doc.destroy();
});

test('continuous typing stays one group through 600 receipts and closes the resource boundary before command 4097',async()=>{
 const Group=await import('../adapters/collaboration/owned-command-group.js'),doc=new Y.Doc({gc:false}),text=doc.getText('text'),origin={},manager=new Y.UndoManager(text,{trackedOrigins:new Set([origin]),captureTimeout:Infinity});let id;
 const bind=e=>Group.bindOwnedCommandGroup(manager,e,id);manager.on('stack-item-added',bind);manager.on('stack-item-updated',bind);
 const uuid=n=>'00000000-0000-4000-8000-'+n.toString(16).padStart(12,'0');
 for(let n=1;n<=4097;n++){id=uuid(n);Group.prepareOwnedCommandGroup?.(manager,id);doc.transact(()=>text.insert(text.length,'x'),origin);if(n===600){assert.equal(manager.undoStack.length,1);assert.equal(Group.readOwnedCommandGroup(manager,id).operation_ids.length,600)}}
 assert.equal(text.length,4097);assert.equal(manager.undoStack.length,2);assert.deepEqual(Group.readOwnedCommandGroup(manager,id),{reference:uuid(4097),operation_ids:[uuid(4097)]});assert.equal(manager.undoStack[0].meta.get('relaymark:operation_ids').length,4096);assert.throws(()=>Group.prepareOwnedCommandGroup(manager,uuid(1)),/Duplicate/);manager.destroy();doc.destroy();
});
