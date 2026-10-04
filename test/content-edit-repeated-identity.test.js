import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import * as Y from 'yjs';
import {Step} from 'prosemirror-transform';
import {initProseMirrorDoc,updateYFragment} from '@tiptap/y-tiptap';
import {createCanonicalEditorSchema,buildContentEditWitness,createContentEditWrite,resolveContentEditTextItems,replayContentEditMutation} from '../src/content-edit.js';
import {captureContentEditSnapshot,captureContentEditFootprint} from '../adapters/collaboration/content-edit-observer.js';
const enc=bytes=>Buffer.from(bytes).toString('base64');
test('actual repeated supplementary text insertion retains generated suffix identity and captures human input',()=>{
 const seed=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-typing-mutation.json',import.meta.url))),doc=new Y.Doc({gc:false});Y.applyUpdate(doc,new Uint8Array(Buffer.from(seed.sender_state_base64,'base64')));doc.clientID=101;
 const root=doc.getXmlFragment('default'),schema=createCanonicalEditorSchema(),initialized=initProseMirrorDoc(root,schema),before=captureContentEditSnapshot(root),clocks=captureContentEditFootprint(doc,new Uint8Array([0,0])).state_vector;
 const operation={kind:'content_edit',steps:[{stepType:'replace',from:2,to:2,slice:{content:[{type:'text',text:'🌍'}]}}]},applied=Step.fromJSON(schema,operation.steps[0]).apply(initialized.doc);assert.equal(applied.failed,null);
 const beforeState=enc(Y.encodeStateAsUpdate(doc)),beforeSnapshot=enc(Y.encodeSnapshot(Y.snapshot(doc))),updates=[];doc.on('update',update=>updates.push(update));initialized.meta.contentEditWrite=createContentEditWrite(initialized.doc,operation.steps,applied.doc);updateYFragment(doc,root,applied.doc,initialized.meta);assert.equal(updates.length,1);
 const evidence={sender_before_snapshot:before,sender_after_snapshot:captureContentEditSnapshot(root),before_snapshot:before,after_snapshot:captureContentEditSnapshot(root),before_state_vector:clocks,operation,footprint:captureContentEditFootprint(doc,updates[0])},proof=buildContentEditWitness(evidence);
 if(process.env.RELAYMARK_WRITE_REPEATED_FIXTURE)fs.writeFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-repeated-human-input.json',import.meta.url),JSON.stringify({description:'Actual maintained insertion of human 🌍 before generated 🌍 in A🌍Z: ambiguous string diff reuses inserted identity and reallocates suffix',sender_state_base64:beforeState,before_snapshot_base64:beforeSnapshot,update_base64:enc(updates[0]),evidence,observed:proof,expected:{human_units:2,original_suffix_selector:{runs:[{type:{client:101,clock:1},item:{client:101,clock:3},count:3}]}}},null,2)+'\n');
 assert.equal(root.get(0).get(0).toString(),'A🌍🌍Z');
 const retained=resolveContentEditTextItems(evidence.after_snapshot,{runs:[{type:{client:101,clock:1},item:{client:101,clock:3},count:3}]});
 assert.equal(retained.segments[0].offset,3);assert.equal(retained.segments.map(v=>v.text).join(''),'🌍Z');
 assert.equal(replayContentEditMutation({sender_state_base64:beforeState,current_state_base64:beforeState,writer_client:101,operation:{...proof.operation},footprint:evidence.footprint}).complete_mutation_correspondence,true);
 assert.equal(proof.text_items.runs.reduce((n,run)=>n+run.count,0),2,'human insertion cannot disappear into generated suffix attribution');doc.destroy();
});

test('explicit identical generated selection replacement creates independently owned input identities',()=>{
 const seed=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-typing-mutation.json',import.meta.url))),doc=new Y.Doc({gc:false});Y.applyUpdate(doc,new Uint8Array(Buffer.from(seed.sender_state_base64,'base64')));doc.clientID=101;
 const root=doc.getXmlFragment('default'),schema=createCanonicalEditorSchema(),initialized=initProseMirrorDoc(root,schema),operation={kind:'content_edit',steps:[{stepType:'replace',from:2,to:4,slice:{content:[{type:'text',text:'🌍'}]}}]},applied=Step.fromJSON(schema,operation.steps[0]).apply(initialized.doc);
 assert.equal(applied.failed,null);const beforeState=enc(Y.encodeStateAsUpdate(doc)),beforeSnapshot=enc(Y.encodeSnapshot(Y.snapshot(doc))),updates=[];doc.on('update',update=>updates.push(update));initialized.meta.contentEditWrite=createContentEditWrite(initialized.doc,operation.steps,applied.doc);updateYFragment(doc,root,applied.doc,initialized.meta);
 if(process.env.RELAYMARK_WRITE_REPEATED_FIXTURE)fs.writeFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-identical-human-replacement.json',import.meta.url),JSON.stringify({description:'Explicit human replacement of generated selection with identical supplementary text must replace selected source identity; value-only diff emits no update',sender_state_base64:beforeState,before_snapshot_base64:beforeSnapshot,operation,updates_base64:updates.map(enc),before_document:initialized.doc.toJSON(),after_document:initProseMirrorDoc(root,schema).doc.toJSON(),expected:{human_units:2,one_original_update:true}},null,2)+'\n');
 assert.equal(updates.length,1,'actual explicit replacement cannot disappear as a value-only no-op');doc.destroy();
});

test('repeated human insertion beside identical peer text retains the peer branch item at its mapped position',()=>{
 const seed=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-typing-mutation.json',import.meta.url))),doc=new Y.Doc({gc:false}),peer=new Y.Doc({gc:false});Y.applyUpdate(doc,new Uint8Array(Buffer.from(seed.sender_state_base64,'base64')));Y.applyUpdate(peer,Y.encodeStateAsUpdate(doc));peer.clientID=303;peer.getXmlFragment('default').get(0).get(0).insert(3,'🌍');Y.applyUpdate(doc,Y.encodeStateAsUpdate(peer));doc.clientID=101;
 const root=doc.getXmlFragment('default'),schema=createCanonicalEditorSchema(),initialized=initProseMirrorDoc(root,schema),before=captureContentEditSnapshot(root),clocks=captureContentEditFootprint(doc,new Uint8Array([0,0])).state_vector,operation={kind:'content_edit',steps:[{stepType:'replace',from:2,to:2,slice:{content:[{type:'text',text:'🌍'}]}}]},applied=Step.fromJSON(schema,operation.steps[0]).apply(initialized.doc);
 assert.equal(applied.failed,null);const beforeState=enc(Y.encodeStateAsUpdate(doc)),beforeSnapshot=enc(Y.encodeSnapshot(Y.snapshot(doc))),updates=[];doc.on('update',update=>updates.push(update));initialized.meta.contentEditWrite=createContentEditWrite(initialized.doc,operation.steps,applied.doc);updateYFragment(doc,root,applied.doc,initialized.meta);assert.equal(updates.length,1);
 const evidence={sender_before_snapshot:before,sender_after_snapshot:captureContentEditSnapshot(root),before_snapshot:before,after_snapshot:captureContentEditSnapshot(root),before_state_vector:clocks,operation,footprint:captureContentEditFootprint(doc,updates[0])},proof=buildContentEditWitness(evidence);
 if(process.env.RELAYMARK_WRITE_REPEATED_FIXTURE)fs.writeFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-repeated-peer-input.json',import.meta.url),JSON.stringify({description:'Actual human insertion before generated and peer-identical supplementary text must not borrow the peer/generated item as input',sender_state_base64:beforeState,before_snapshot_base64:beforeSnapshot,update_base64:enc(updates[0]),evidence,observed:proof,expected:{human_units:2,peer_item:{client:303,clock:0},peer_position:6}},null,2)+'\n');
 const retainedPeer=resolveContentEditTextItems(evidence.after_snapshot,{runs:[{type:{client:101,clock:1},item:{client:303,clock:0},count:2}]});assert.equal(retainedPeer.segments[0].offset,5);
 assert.equal(proof.text_items.runs.reduce((n,run)=>n+run.count,0),2,'peer/source identity cannot substitute human input');doc.destroy();peer.destroy();
});
