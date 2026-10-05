import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import * as Y from 'yjs';
import {initProseMirrorDoc} from '@tiptap/y-tiptap';
import * as Runtime from '../src/content-edit.js';
import {produceDocumentPatch} from '../src/document-patch.js';
import {proseMirrorToRelayMark} from '../src/document-adapter.js';
const fixture=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-typing-mutation.json',import.meta.url)));
const metadata=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-metadata-history.json',import.meta.url))).normal;
const args=f=>({state_base64:f.sender_state_base64,writer_client:818,transaction_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',owner_id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'});
function document(f){const d=new Y.Doc({gc:false});try{Y.applyUpdate(d,new Uint8Array(Buffer.from(f.sender_state_base64,'base64')));return proseMirrorToRelayMark(initProseMirrorDoc(d.getXmlFragment('default'),Runtime.createCanonicalEditorSchema()).doc.toJSON());}finally{d.destroy();}}
test('headless reviewed append preserves existing rich widgets, identity and metadata with one actual command',()=>{
 const original=document(metadata),target=structuredClone(original);
 target.blocks.push({id:'b88888888888848888888888888888888',type:'paragraph',content:[{type:'strong',content:[{type:'text',text:'Reviewed 🌍'}]}]});
 target.frontmatter={title:'Reviewed title'};
 const result=produceDocumentPatch({...args(metadata),target_document:target});
 assert.deepEqual(result.authored_document,target);
 assert.deepEqual(result.authored_document.blocks.slice(0,-1),original.blocks);
 assert.equal(result.proof.complete_mutation_correspondence,true);
 assert.equal(result.content_edit.steps.filter(s=>s.stepType==='docAttr').length,1);
 assert.equal(result.text_items.runs.reduce((n,r)=>n+r.count,0),'Reviewed 🌍'.length);
 assert.deepEqual(document(metadata),original);
});
test('reviewed replacement and deletion keep unchanged block IDs and use maintained step execution',()=>{
 const original=document(fixture),target=structuredClone(original);
 target.blocks[0].content=[{type:'text',text:'Replacement 🚀'}];
 const result=produceDocumentPatch({...args(fixture),target_document:target});
 assert.deepEqual(result.authored_document,target);
 assert.equal(result.authored_document.blocks[0].id,original.blocks[0].id);
 const trimmed=structuredClone(target);trimmed.blocks[0].content=[];
 const deletion=produceDocumentPatch({...args(fixture),state_base64:result.state_base64,target_document:trimmed});
 assert.deepEqual(deletion.authored_document,trimmed);
 assert.equal(deletion.text_items.runs.length,0);
});
test('reviewed patch refuses no-op, unsupported or duplicate identity and unknown inputs',()=>{
 const target=document(fixture),input={...args(fixture),target_document:target};
 assert.throws(()=>produceDocumentPatch(input));
 assert.throws(()=>produceDocumentPatch({...input,target_document:{...target,blocks:[...target.blocks,...target.blocks]}}));
 assert.throws(()=>produceDocumentPatch({...input,target_document:{...target,unknown:'discard me'}}));
 assert.throws(()=>produceDocumentPatch({...input,actor_id:'untrusted'}));
 assert.deepEqual(document(fixture),target);
});
