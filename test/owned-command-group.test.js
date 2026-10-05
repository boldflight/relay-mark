import test from 'node:test';import assert from 'node:assert/strict';import * as Y from 'yjs';
import {bindOwnedHistoryOwner,readOwnedHistoryOwner,bindOwnedCommandGroup,readOwnedCommandGroup,bindOwnedCommandHistory} from '../adapters/collaboration/owned-command-group.js';
const ownerID='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const first='11111111-1111-4111-8111-111111111111',second='22222222-2222-4222-8222-222222222222',third='33333333-3333-4333-8333-333333333333';
test('actual maintained typing group binds both command receipts without replacing selection metadata',()=>{
 const doc=new Y.Doc({gc:false}),text=doc.getText('text'),origin={},manager=new Y.UndoManager(text,{trackedOrigins:new Set([origin]),captureTimeout:Infinity});bindOwnedHistoryOwner(manager,ownerID);let id=first;
 const onEvent=e=>{if(manager.undoing||manager.redoing)return;e.stackItem.meta.set('selection','retained caret');bindOwnedCommandGroup(manager,e,id)};manager.on('stack-item-added',onEvent);manager.on('stack-item-updated',onEvent);
 doc.transact(()=>text.insert(0,'A'),origin);assert.deepEqual(readOwnedCommandGroup(manager,first),{owner_id:ownerID,reference:first,operation_ids:[first]});
 id=second;doc.transact(()=>text.insert(1,'🌍'),origin);assert.equal(manager.undoStack.length,1);assert.deepEqual(readOwnedCommandGroup(manager,second),{owner_id:ownerID,reference:first,operation_ids:[first,second]});assert.equal(manager.undoStack[0].meta.get('selection'),'retained caret');
 manager.stopCapturing();id=third;doc.transact(()=>text.insert(3,'!'),origin);assert.deepEqual(readOwnedCommandGroup(manager,third),{owner_id:ownerID,reference:third,operation_ids:[third]});
 assert.throws(()=>bindOwnedCommandGroup(manager,{type:'undo',stackItem:manager.undoStack[0]},first),/actual maintained/);
 assert.throws(()=>bindOwnedCommandGroup(manager,{type:'undo',stackItem:manager.undoStack[1]},first),/Duplicate/);assert.deepEqual(readOwnedCommandGroup(manager,third),{owner_id:ownerID,reference:third,operation_ids:[third]});let inverse;manager.on('stack-item-popped',e=>{inverse=bindOwnedCommandHistory(manager,e)});manager.undo();assert.deepEqual(inverse,{kind:'undo',owner_id:ownerID,reference:third,operation_ids:[third]});assert.equal(text.toString(),'A🌍');manager.undo();assert.deepEqual(inverse,{kind:'undo',owner_id:ownerID,reference:first,operation_ids:[first,second]});assert.equal(text.toString(),'');manager.redo();assert.deepEqual(inverse,{kind:'redo',owner_id:ownerID,reference:first,operation_ids:[first,second]});assert.equal(text.toString(),'A🌍');assert.throws(()=>bindOwnedCommandHistory(manager,{type:'undo',origin:manager,stackItem:manager.undoStack[0]}),/actual maintained inverse/);manager.destroy();doc.destroy();
});

test('continuous typing stays one group through 600 receipts and closes the resource boundary before command 4097',async()=>{
 const Group=await import('../adapters/collaboration/owned-command-group.js'),doc=new Y.Doc({gc:false}),text=doc.getText('text'),origin={},manager=new Y.UndoManager(text,{trackedOrigins:new Set([origin]),captureTimeout:Infinity});bindOwnedHistoryOwner(manager,ownerID);let id;
 const bind=e=>Group.bindOwnedCommandGroup(manager,e,id);manager.on('stack-item-added',bind);manager.on('stack-item-updated',bind);
 const uuid=n=>'00000000-0000-4000-8000-'+n.toString(16).padStart(12,'0');
 for(let n=1;n<=4097;n++){id=uuid(n);Group.prepareOwnedCommandGroup?.(manager,id);doc.transact(()=>text.insert(text.length,'x'),origin);if(n===600){assert.equal(manager.undoStack.length,1);assert.equal(Group.readOwnedCommandGroup(manager,id).operation_ids.length,600)}}
 assert.equal(text.length,4097);assert.equal(manager.undoStack.length,2);assert.deepEqual(Group.readOwnedCommandGroup(manager,id),{owner_id:ownerID,reference:uuid(4097),operation_ids:[uuid(4097)]});assert.equal(manager.undoStack[0].meta.get('relaymark:operation_ids').operation_ids.length,4096);assert.throws(()=>Group.prepareOwnedCommandGroup(manager,uuid(1)),/Duplicate/);manager.destroy();doc.destroy();
});


test('owned inverse preflight refuses unbound candidate below obsolete top before document mutation',async()=>{
 const Group=await import('../adapters/collaboration/owned-command-group.js');assert.equal(typeof Group.prepareOwnedHistory,'function');
 const doc=new Y.Doc({gc:false}),text=doc.getText('text'),origin={},manager=new Y.UndoManager(text,{trackedOrigins:new Set([origin]),captureTimeout:Infinity});
 doc.transact(()=>text.insert(0,'Original'),origin);manager.stopCapturing();doc.transact(()=>text.insert(8,'Temporary'),origin);bindOwnedHistoryOwner(manager,ownerID);manager.undoStack.at(-1).meta.set('relaymark:operation_ids',{owner_id:ownerID,reference:first,operation_ids:[first]});doc.transact(()=>text.delete(8,9),'peer');
 const before=Y.encodeStateAsUpdate(doc),stack=manager.undoStack.slice();assert.throws(()=>Group.prepareOwnedHistory(manager,'undo'),/Unbound/);assert.deepEqual(Y.encodeStateAsUpdate(doc),before);assert.deepEqual(manager.undoStack,stack);assert.equal(Group.prepareOwnedHistory(manager,'redo'),false);assert.throws(()=>Group.prepareOwnedHistory(manager,'unknown'),/Unavailable/);
 manager.undoStack[0].meta.set('relaymark:operation_ids',{owner_id:ownerID,reference:second,operation_ids:[second]});assert.equal(Group.prepareOwnedHistory(manager,'undo'),true);manager.destroy();doc.destroy();
});

 test('manager namespace survives reconnect but cannot be relabeled or inherited by a new manager',()=>{
 const doc=new Y.Doc({gc:false}),text=doc.getText('text'),origin={},manager=new Y.UndoManager(text,{trackedOrigins:new Set([origin])});
 bindOwnedHistoryOwner(manager,ownerID);assert.equal(readOwnedHistoryOwner(manager),ownerID);
 const event=e=>bindOwnedCommandGroup(manager,e,first);manager.on('stack-item-added',event);
 doc.transact(()=>text.insert(0,'owned'),origin);const before=Y.encodeStateAsUpdate(doc),metadata=manager.undoStack[0].meta.get('relaymark:operation_ids');
 assert.throws(()=>bindOwnedHistoryOwner(manager,second),/Conflicting/);assert.deepEqual(Y.encodeStateAsUpdate(doc),before);assert.equal(manager.undoStack[0].meta.get('relaymark:operation_ids'),metadata);
 assert.equal(bindOwnedHistoryOwner(manager,ownerID),ownerID);
 const reopened=new Y.UndoManager(text,{trackedOrigins:new Set([{}])});assert.notEqual(readOwnedHistoryOwner(reopened),ownerID);reopened.destroy();manager.destroy();doc.destroy();
 });


test('whole owned retirement validates exact namespace and membership before preserving shared-parent survivor undo',async()=>{
 const {retireOwnedHistoryGroups}=await import('../adapters/collaboration/owned-command-group.js');
 const doc=new Y.Doc({gc:false}),root=doc.getXmlFragment('default'),paragraph=new Y.XmlElement('paragraph'),text=new Y.XmlText();
 paragraph.setAttribute('relaymarkId','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');root.insert(0,[paragraph]);paragraph.insert(0,[text]);text.insert(0,'A🌍Z');
 const origin={},manager=new Y.UndoManager(root,{trackedOrigins:new Set([origin]),captureTimeout:Infinity});bindOwnedHistoryOwner(manager,ownerID);let id=first;
 const bind=e=>{if(!manager.undoing&&!manager.redoing){e.stackItem.meta.set('selection','retained caret');bindOwnedCommandGroup(manager,e,id)}};
 manager.on('stack-item-added',bind);manager.on('stack-item-updated',bind);manager.on('stack-item-popped',e=>bindOwnedCommandHistory(manager,e));
 doc.transact(()=>text.delete(0,1),origin);const old=readOwnedCommandGroup(manager,first);manager.stopCapturing();id=second;doc.transact(()=>text.delete(0,2),origin);manager.undo();manager.redo();manager.undoStack.at(-1).meta.set('selection','retained caret');
 manager.stopCapturing();id=third;doc.transact(()=>text.delete(0,1),origin);const thirdGroup=readOwnedCommandGroup(manager,third);manager.undo();
 const before=Y.encodeStateAsUpdate(doc),stacks={undo:manager.undoStack.slice(),redo:manager.redoStack.slice()};
 assert.throws(()=>retireOwnedHistoryGroups(manager,[old,{...thirdGroup,owner_id:third}]),/Conflicting/);
 assert.throws(()=>retireOwnedHistoryGroups(manager,[{...old,operation_ids:[first,third]}]),/actual whole group/);
 assert.deepEqual(Y.encodeStateAsUpdate(doc),before);assert.deepEqual(manager.undoStack,stacks.undo);assert.deepEqual(manager.redoStack,stacks.redo);
 const result=retireOwnedHistoryGroups(manager,[old,thirdGroup]);assert.equal(result.undo,1);assert.equal(result.redo,1);assert.deepEqual(Y.encodeStateAsUpdate(doc),before);
 assert.equal(manager.undoStack[0].meta.get('selection'),'retained caret');assert.equal(manager.undoStack[0].meta.get('relaymark:operation_ids').reference,second);
 manager.undo();assert.equal(text.toString(),'🌍Z');manager.redo();assert.equal(text.toString(),'Z');manager.undo();assert.equal(text.toString(),'🌍Z');assert.equal(manager.undo(),null);
 id='44444444-4444-4444-8444-444444444444';doc.transact(()=>text.insert(text.length,'Ω'),origin);assert.equal(readOwnedCommandGroup(manager,id).reference,id);manager.undo();assert.equal(text.toString(),'🌍Z');
 manager.destroy();doc.destroy();
});
