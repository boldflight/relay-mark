import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import * as Y from 'yjs';
import * as Runtime from '../adapters/collaboration/content-edit-mutation.js';
import {captureContentEditFootprint} from '../adapters/collaboration/content-edit-observer.js';
const fixture=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-enter-inverse-history.json',import.meta.url)));
const ownerID='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',enc=bytes=>Buffer.from(bytes).toString('base64'),dec=text=>new Uint8Array(Buffer.from(text,'base64'));
function knownOwner(evidence){const value=structuredClone(evidence);value.operation.history.owner_id=ownerID;for(const receipt of value.receipts){const metadata=receipt.operation.history??receipt.operation.group;metadata.owner_id=ownerID;}return value;}
test('cold checkpoint removes original update replay yet admits actual offline pre-cut Enter inverse across later peer state',()=>{
 const undo=knownOwner(fixture.undo),cut=new Y.Doc({gc:false});Y.applyUpdate(cut,dec(undo.current_state_base64));cut.getXmlFragment('default');
 const peer=new Y.Doc({gc:false});Y.applyUpdate(peer,Y.encodeStateAsUpdate(cut));peer.clientID=909;const paragraph=new Y.XmlElement('paragraph'),text=new Y.XmlText();paragraph.setAttribute('relaymarkId','b99999999999949998999999999999999');paragraph.insert(0,[text]);peer.getXmlFragment('default').insert(peer.getXmlFragment('default').length,[paragraph]);text.insert(0,'Later peer 🌍',{bold:{}});Y.applyUpdate(cut,Y.encodeStateAsUpdate(peer));peer.destroy();
 const checkpoint=Runtime.createOwnedHistoryCheckpoint({initial_state_base64:undo.initial_state_base64,receipts:undo.receipts,current_state_base64:enc(Y.encodeStateAsUpdate(cut)),owner_id:ownerID});
 assert.equal(checkpoint.owner_id,ownerID);assert.equal(checkpoint.undo_stack.length,1);assert.equal(checkpoint.redo_stack.length,0);
 assert.equal(JSON.stringify(checkpoint).includes('update_base64'),false,'checkpoint holds manager data, never an archive of original updates');
 const after=new Y.Doc({gc:false});Y.applyUpdate(after,Y.encodeStateAsUpdate(cut));after.getXmlFragment('default');Y.applyUpdate(after,dec(fixture.transport.undo.update_base64));
 const evidence={sender_state_base64:undo.sender_state_base64,current_state_base64:enc(Y.encodeStateAsUpdate(cut)),writer_client:undo.writer_client,operation:undo.operation,footprint:captureContentEditFootprint(after,dec(fixture.transport.undo.update_base64)),checkpoint:JSON.parse(JSON.stringify(checkpoint)),receipts:[]};
 const proof=Runtime.replayContentEditMutation(evidence);assert.equal(proof.owned_history_correspondence,true);assert.deepEqual(proof.text_items,{runs:[]});assert.equal(proof.proven_copies.flatMap(copy=>copy.destination.runs).reduce((sum,run)=>sum+run.count,0),16);
 assert.deepEqual(after.getXmlFragment('default').get(after.getXmlFragment('default').length-1).get(0).toDelta(),[{insert:'Later peer 🌍',attributes:{bold:{}}}]);
 for(const patch of [{owner_id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'},{undo_stack:[]},{retained:[]}])assert.throws(()=>Runtime.replayContentEditMutation({...evidence,checkpoint:{...checkpoint,...patch}}));
 after.destroy();cut.destroy();
});


test('checkpoint of real undo preserves redone edges through cold redo without archived payloads',()=>{
 const redo=knownOwner(fixture.redo),checkpoint=Runtime.createOwnedHistoryCheckpoint({initial_state_base64:redo.initial_state_base64,receipts:redo.receipts,current_state_base64:redo.current_state_base64,owner_id:ownerID});
 assert.equal(checkpoint.undo_stack.length,0);assert.equal(checkpoint.redo_stack.length,1);assert.ok(checkpoint.redone.length>0);
 // A second cut reconstructs from only the first maintained checkpoint and
 // its original post-cut undo receipt, never the already-pruned Enter update.
 const undo=knownOwner(fixture.undo),first=Runtime.createOwnedHistoryCheckpoint({initial_state_base64:undo.initial_state_base64,receipts:undo.receipts,current_state_base64:undo.current_state_base64,owner_id:ownerID});
 const second=Runtime.createOwnedHistoryCheckpoint({checkpoint:JSON.parse(JSON.stringify(first)),receipts:redo.receipts.slice(undo.receipts.length),current_state_base64:redo.current_state_base64,owner_id:ownerID});
 assert.deepEqual(second,checkpoint);
 const {initial_state_base64,receipts,...evidence}=redo;
 const proof=Runtime.replayContentEditMutation({...evidence,checkpoint:JSON.parse(JSON.stringify(checkpoint)),receipts:[]});
 assert.equal(proof.owned_history_correspondence,true);assert.deepEqual(proof.text_items,{runs:[]});assert.equal(proof.proven_copies.flatMap(copy=>copy.destination.runs).reduce((sum,run)=>sum+run.count,0),16);
 const cyclic=structuredClone(checkpoint);cyclic.redone[0].target=cyclic.redone[0].item;assert.throws(()=>Runtime.replayContentEditMutation({...evidence,checkpoint:cyclic,receipts:[]}));
});

test('typing capture continues across checkpoint and genuine marked group suffix while omitting later owned commands refuses',()=>{
 const f=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-owned-mark-history.json',import.meta.url))),undo=knownOwner(f.undo);
 const first=undo.receipts[0],cut=new Y.Doc({gc:false});Y.applyUpdate(cut,dec(first.sender_state_base64));cut.getXmlFragment('default');Y.applyUpdate(cut,dec(first.update_base64));
 const checkpoint=Runtime.createOwnedHistoryCheckpoint({initial_state_base64:undo.initial_state_base64,receipts:[first],current_state_base64:enc(Y.encodeStateAsUpdate(cut)),owner_id:ownerID});
 const {initial_state_base64,receipts,...evidence}=undo;
 const proof=Runtime.replayContentEditMutation({...evidence,checkpoint:JSON.parse(JSON.stringify(checkpoint)),receipts:receipts.slice(1)});
 assert.equal(proof.owned_history_correspondence,true);assert.deepEqual(proof.text_items,{runs:[]});
 // Later owned commands are already accepted at this cut. An older sender is
 // not allowed to install their stack data by pretending they were peer-only.
 const latest=Runtime.createOwnedHistoryCheckpoint({initial_state_base64:undo.initial_state_base64,receipts:undo.receipts,current_state_base64:undo.current_state_base64,owner_id:ownerID});
 assert.throws(()=>Runtime.replayContentEditMutation({...evidence,sender_state_base64:first.sender_state_base64,checkpoint:latest,receipts:[]}));
 cut.destroy();
});
