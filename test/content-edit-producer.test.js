import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import * as Y from 'yjs';
import * as Runtime from '../src/content-edit.js';
import {captureContentEditFootprint} from '../adapters/collaboration/content-edit-observer.js';
const directory=new URL('../spec/relaymark/collaboration/fixtures/',import.meta.url);
const id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',ownerID='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const fixture=name=>JSON.parse(fs.readFileSync(new URL(`content-edit-${name}-mutation.json`,directory)));
const input=f=>({state_base64:f.sender_state_base64,writer_client:f.writer_client,transaction_id:id,owner_id:ownerID,steps:f.operation.steps});
const bytes=s=>Uint8Array.from(Buffer.from(s,'base64'));
for(const name of ['typing','mark','widget','enter','delete'])test(`DOM-free ${name} produces actual canonical update and independently verified source evidence`,()=>{
 const f=fixture(name),before=new Y.Doc({gc:false});Y.applyUpdate(before,bytes(f.sender_state_base64));
 const saved=Y.encodeStateAsUpdate(before),result=Runtime.produceContentEdit(input(f));
 assert.deepEqual(Y.encodeStateAsUpdate(before),saved,'producer cannot mutate caller state');
 assert.deepEqual(result.content_edit.group,{owner_id:ownerID,reference:id,operation_ids:[id]});
 assert.deepEqual(result.content_edit.steps,f.operation.steps);
 assert.equal(result.proof.complete_mutation_correspondence,true);
 assert.equal(result.text_items.runs.reduce((sum,r)=>sum+r.count,0),name==='typing'?1:0);
 assert.equal(result.content_edit.copies.flatMap(copy=>copy.destination.runs).reduce((sum,r)=>sum+r.count,0),name==='enter'?16:0);
 assert.deepEqual(result.text_items,result.proof.text_items);
 assert.deepEqual(result.content_edit.copies,result.proof.proven_copies);
 const candidate=new Y.Doc({gc:false});Y.applyUpdate(candidate,saved);Y.applyUpdate(candidate,bytes(result.update_base64));
 assert.deepEqual(Y.encodeStateAsUpdate(candidate),bytes(result.state_base64));
 assert.deepEqual(captureContentEditFootprint(candidate,bytes(result.update_base64)),f.footprint,'actual original command footprint remains independently fixed');
 const replay=Runtime.replayContentEditMutation({sender_state_base64:f.sender_state_base64,current_state_base64:f.sender_state_base64,writer_client:f.writer_client,operation:{kind:'content_edit',steps:result.content_edit.steps,copies:result.content_edit.copies,group:result.content_edit.group},footprint:captureContentEditFootprint(candidate,bytes(result.update_base64))});
 assert.equal(replay.complete_mutation_correspondence,true);
 assert.deepEqual(result.before_snapshot_base64,result.content_edit.before_snapshot_base64);
 candidate.destroy();before.destroy();
});
test('producer refuses malformed writer, forged command owner, unknown steps and no-op without inventing receipts',()=>{
 const f=fixture('typing'),args=input(f);
 for(const patch of [{owner_id:'not-a-uuid'},{transaction_id:'not-a-uuid'},{writer_client:-1},{steps:[{stepType:'invisible-root-write'}]},{steps:[]}])assert.throws(()=>Runtime.produceContentEdit({...args,...patch}));
 assert.equal(f.sender_state_base64,args.state_base64);
});

test('reviewed full metadata and Unicode edit share one command and preserve exact authored envelope',()=>{
 const f=JSON.parse(fs.readFileSync(new URL('content-edit-metadata-history.json',directory))).normal;
 const result=Runtime.produceContentEdit(input(f));
 assert.deepEqual(result.authored_document.frontmatter,{title:'Exact 🌍 recovery'});
 assert.deepEqual(result.authored_document.annotations,[]);
 assert.deepEqual(result.authored_document.resources,[]);
 assert.deepEqual(result.authored_document.meta,{retained:'original'});
 assert.equal(result.text_items.runs.reduce((sum,r)=>sum+r.count,0),2);
 assert.equal(result.proof.complete_mutation_correspondence,true);
 const state=new Y.Doc({gc:false});Y.applyUpdate(state,bytes(f.sender_state_base64));let updates=0;state.on('update',()=>updates++);Y.applyUpdate(state,bytes(result.update_base64));assert.equal(updates,1);state.destroy();
});
