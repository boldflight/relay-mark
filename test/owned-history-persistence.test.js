import {readFileSync} from 'node:fs';
import {createCanonicalEditorSchema} from '../src/editor-model.js';
import {prosemirrorToYXmlFragment} from './helpers/canonical-binding.js';
import test from 'node:test';import assert from 'node:assert/strict';import * as Y from 'yjs';
import * as Runtime from '../adapters/collaboration/content-edit-mutation.js';
import {bindOwnedHistoryOwner,bindOwnedCommandGroup,bindOwnedCommandHistory} from '../adapters/collaboration/owned-command-group.js';
const ownerID='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',scope={document_id:'11111111-1111-4111-8111-111111111111',incarnation:'one'},command='22222222-2222-4222-8222-222222222222';
function owner(update){const doc=new Y.Doc({gc:false}),root=doc.getXmlFragment('default');if(update)Y.applyUpdate(doc,update);else{const p=new Y.XmlElement('paragraph');p.setAttribute('relaymarkId','33333333333343338333333333333333');p.insert(0,[new Y.XmlText('Hello 🌍')]);root.insert(0,[p]);}const origin={},manager=new Y.UndoManager([root,doc.getMap('relaymark')],{trackedOrigins:new Set([origin])});bindOwnedHistoryOwner(manager,ownerID);return{doc,root,origin,manager,destroy(){manager.destroy();doc.destroy();}};}
test('cold actual manager restores original group and cursor before selective undo across a later peer',()=>{
 const a=owner(),key={},bkey={};let b,peer;
 try{a.manager.on('stack-item-added',e=>{if(!a.manager.undoing&&!a.manager.redoing)bindOwnedCommandGroup(a.manager,e,command);else bindOwnedCommandHistory(a.manager,e);});
 // A real editor bootstrap can retain older deleted paragraphs before input.
 const obsolete=new Y.XmlElement('paragraph');obsolete.setAttribute('relaymarkId','44444444444444448444444444444444');obsolete.insert(0,[new Y.XmlText('obsolete seed')]);a.doc.transact(()=>{a.root.insert(1,[obsolete]);a.root.delete(1,1);},'bootstrap');
 const text=a.root.get(0).get(0),anchor=Y.createRelativePositionFromTypeIndex(text,5);
 a.doc.transact(()=>text.insert(5,'!'),a.origin);a.manager.undoStack[0].meta.set(key,{type:'text',anchor,head:anchor,absAnchor:6,absHead:6,depth:undefined});
 const saved=Runtime.exportOwnedHistoryState(a.doc,a.manager,{...scope,selectionKey:key});const bytes=Y.encodeStateAsUpdate(a.doc);
 peer=owner(bytes);const vector=Y.encodeStateVector(peer.doc);peer.root.get(0).get(0).insert(0,'Peer ');b=owner(bytes);Y.applyUpdate(b.doc,Y.encodeStateAsUpdate(peer.doc,vector),'remote');
 Runtime.restoreOwnedHistoryState(b.doc,b.manager,saved,{...scope,selectionKey:bkey});
 assert.equal(b.manager.undoStack.length,1);assert.deepEqual(b.manager.undoStack[0].meta.get('relaymark:operation_ids'),a.manager.undoStack[0].meta.get('relaymark:operation_ids'));
 assert.deepEqual(Y.relativePositionToJSON(b.manager.undoStack[0].meta.get(bkey).anchor),Y.relativePositionToJSON(anchor));
 assert.ok(b.manager.undo());assert.equal(b.root.get(0).get(0).toString(),'Peer Hello 🌍');
 assert.ok(b.manager.redo());assert.equal(b.root.get(0).get(0).toString(),'Peer Hello! 🌍');
 assert.deepEqual(bytes,Y.encodeStateAsUpdate(a.doc));assert.equal(JSON.stringify(saved).includes('update_base64'),false);
 }finally{a.destroy();b?.destroy();peer?.destroy();}
});
test('foreign scope, unknown selection metadata or corrupt retained state cannot install history',()=>{
 const a=owner(),key={};try{a.manager.on('stack-item-added',e=>bindOwnedCommandGroup(a.manager,e,command));a.doc.transact(()=>a.root.get(0).get(0).insert(0,'!'),a.origin);
 const saved=Runtime.exportOwnedHistoryState(a.doc,a.manager,{...scope,selectionKey:key});
 for(const fault of [s=>({...s,scope:{...scope,incarnation:'foreign'}}),s=>({...s,state_sha256:'0'.repeat(64)}),s=>({...s,checkpoint:{...s.checkpoint,owner_id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'}})]){const b=owner(Y.encodeStateAsUpdate(a.doc));try{const before=Y.encodeStateAsUpdate(b.doc);assert.throws(()=>Runtime.restoreOwnedHistoryState(b.doc,b.manager,fault(saved),{...scope,selectionKey:{}}));assert.equal(b.manager.undoStack.length,0);assert.deepEqual(Y.encodeStateAsUpdate(b.doc),before);}finally{b.destroy();}}
 a.manager.undoStack[0].meta.set({},'unknown');assert.throws(()=>Runtime.exportOwnedHistoryState(a.doc,a.manager,{...scope,selectionKey:key}));
 }finally{a.destroy();}
});

// Real server codec fixture: object-key order changed, not the CRDT/history cut.
const serverCut=JSON.parse(readFileSync(new URL('./fixtures/owned-history-yex-link-cut.json',import.meta.url),'utf8'));
const serverBytes=()=>Uint8Array.from(Buffer.from(serverCut.update_base64,'base64'));
const plainText=doc=>doc.getXmlFragment('default').get(0).get(0).toDelta().map(part=>part.insert).join('');
test('a server-merged link restores the original archive and selective cold Undo/Redo',()=>{
 const b=owner(serverBytes()),archive=JSON.parse(serverCut.archive_json),key={};
 b.manager.on('stack-item-popped',event=>bindOwnedCommandHistory(b.manager,event));
 try{
  Runtime.restoreOwnedHistoryState(b.doc,b.manager,archive,{...archive.scope,selectionKey:key});
  assert.equal(JSON.stringify(archive),serverCut.archive_json);
  assert.equal(plainText(b.doc),serverCut.before);
  assert.ok(b.manager.undo());assert.equal(plainText(b.doc),serverCut.undo);
  assert.ok(b.manager.redo());assert.equal(plainText(b.doc),serverCut.redo);
  const attributes=b.doc.getXmlFragment('default').get(0).get(0).toDelta().find(part=>part.attributes?.link)?.attributes.link;
  assert.deepEqual({...attributes},{href:'https://example.org/docs',target:'_blank',rel:'noopener noreferrer nofollow',class:null,title:null});
 }finally{b.destroy();}
});
for(const fault of ['hash','value','unknown-attribute','nested-attribute','incomplete-attribute','identity'])test(`legacy encoding repair refuses ${fault} without installing history`,()=>{
 let b=owner(serverBytes());const archive=JSON.parse(serverCut.archive_json);
 try{
  if(fault==='hash')archive.state_sha256='0'.repeat(64);
  if(['value','unknown-attribute','nested-attribute','incomplete-attribute'].includes(fault))for(const rows of b.doc.store.clients.values())for(const item of rows){
   if(!(item.content instanceof Y.ContentFormat)||item.content.key!=='link'||!item.content.value)continue;
   const attrs={...item.content.value};
   if(fault==='value')attrs.href='https://invalid.example';
   if(fault==='unknown-attribute')attrs.unknown='extra';
   if(fault==='nested-attribute')attrs.href={nested:true};
   if(fault==='incomplete-attribute')delete attrs.title;
   item.content.value=attrs;
  }
  if(fault==='identity'){
   const document=Runtime.readContentEditDocument(Buffer.from(Y.encodeStateAsUpdate(b.doc)).toString('base64'));
   b.destroy();const doc=new Y.Doc({gc:false});doc.clientID=999999;
   prosemirrorToYXmlFragment(createCanonicalEditorSchema().nodeFromJSON(document),doc.getXmlFragment('default'));
   assert.deepEqual(Runtime.readContentEditDocument(Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64')),document);
   b={doc,manager:new Y.UndoManager([doc.getXmlFragment('default'),doc.getMap('relaymark')]),destroy(){this.manager.destroy();this.doc.destroy();}};bindOwnedHistoryOwner(b.manager,ownerID);
  }
  const before=Y.encodeStateAsUpdate(b.doc);
  assert.throws(()=>Runtime.restoreOwnedHistoryState(b.doc,b.manager,archive,{...archive.scope,selectionKey:{}}));
  assert.equal(b.manager.undoStack.length,0);assert.equal(b.manager.redoStack.length,0);
  assert.deepEqual(Y.encodeStateAsUpdate(b.doc),before);
 }finally{b.destroy();}
});
