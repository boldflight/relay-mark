import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import * as Y from 'yjs';
import {prosemirrorToYXmlFragment,initProseMirrorDoc,updateYFragment} from '@tiptap/y-tiptap';
import {Step} from 'prosemirror-transform';
import {parseDocument} from '../src/document-source.js';import {relayMarkToProseMirror} from '../src/document-adapter.js';
import {buildContentEditWitness,prepareContentEditWitness,createCanonicalEditorSchema,createContentEditWrite,replayContentEditMutation} from '../src/content-edit.js';
import {captureContentEditSnapshot,captureContentEditFootprint} from '../adapters/collaboration/content-edit-observer.js';
const schema=createCanonicalEditorSchema(),dir=new URL('../spec/relaymark/collaboration/fixtures/',import.meta.url);
for(const name of fs.readdirSync(dir).filter(name=>name.startsWith('content-edit-native-table-')&&!name.includes('-fault')))test(`actual ${name} copies original cell identities without human input`,()=>{
 const f=JSON.parse(fs.readFileSync(new URL(name,dir))),evidence=structuredClone(f.evidence);delete evidence.operation.copies;
 const result=buildContentEditWitness(evidence);
 assert.deepEqual(result.text_items,{runs:[]});assert.equal(result.proven_copies.reduce((n,c)=>n+c.destination.runs.reduce((n,r)=>n+r.count,0),0),f.expected_copied_units);
 assert.equal(replayContentEditMutation(Object.fromEntries(['sender_state_base64','current_state_base64','writer_client','operation','footprint'].map(key=>[key,f[key]]))).complete_mutation_correspondence,true);
 const wrong=structuredClone(f.evidence);wrong.operation.copies[0].source.runs[0].type.clock++;
 assert.throws(()=>prepareContentEditWitness({...wrong,text_items:{runs:[]}}),/wrongly typed/);
});
function replacement({freshID=false,alter=false,marks=false}={}){
 const doc=new Y.Doc({gc:false});doc.clientID=77;const root=doc.getXmlFragment('default');
 const ast=parseDocument('**A🌍Z**',{namespace:'complete-subtree-copy'}),pm=schema.nodeFromJSON(relayMarkToProseMirror(ast));prosemirrorToYXmlFragment(pm,root);
 const before=captureContentEditSnapshot(root),clocks=captureContentEditFootprint(doc,new Uint8Array([0,0])).state_vector;
 const paragraph=structuredClone(pm.toJSON().content[0]);if(freshID)paragraph.attrs.relaymarkId='b00000000000040008000000000000081';if(alter)paragraph.content[0].text='B🌍Z';if(marks)paragraph.content[0].marks=[{type:'italic'}];
 const steps=[{stepType:'replace',from:0,to:pm.content.size,slice:{content:[paragraph]}}],target=Step.fromJSON(schema,steps[0]).apply(pm).doc;
 const initialized=initProseMirrorDoc(root,schema),updates=[];doc.on('update',update=>updates.push(update));
 doc.transact(()=>updateYFragment(doc,root,target,{mapping:initialized.mapping,isOMark:initialized.meta.isOMark,contentEditWrite:createContentEditWrite(pm,steps,target)}));
 const after=captureContentEditSnapshot(root),footprint=captureContentEditFootprint(doc,updates[0]);
 const evidence={sender_before_snapshot:before,sender_after_snapshot:after,before_snapshot:before,after_snapshot:after,before_state_vector:clocks,operation:{kind:'content_edit',steps},footprint};
 const result=buildContentEditWitness(evidence);doc.destroy();return {result,evidence};
}
test('complete marked Unicode subtree identity proves a reconstructed copy; equal fresh identity does not',()=>{
 const copied=replacement().result;assert.deepEqual(copied.text_items,{runs:[]});assert.equal(copied.proven_copies[0].source.runs.reduce((n,r)=>n+r.count,0),4);
 const fresh=replacement({freshID:true}).result;assert.deepEqual(fresh.proven_copies,[]);assert.equal(fresh.text_items.runs.reduce((n,r)=>n+r.count,0),4);
});
test('altered same-ID text or marks cannot borrow original subtree ancestry',()=>{
 for(const opts of [{alter:true},{marks:true}]){const {result,evidence}=replacement(opts);assert.deepEqual(result.proven_copies,[]);assert.equal(result.text_items.runs.reduce((n,r)=>n+r.count,0),4);
  const original=evidence.sender_before_snapshot.children[0].children[0],destination=result.text_items;
  assert.throws(()=>prepareContentEditWitness({...evidence,operation:{...evidence.operation,copies:[{source:{runs:original.runs.map(run=>({type:original.type,item:run.item,count:run.count}))},destination}]},text_items:{runs:[]}}),/Unproven.*copy/);
 }
});
test('ambiguous source or duplicate final identified subtree cannot establish copy ancestry',()=>{
 const {evidence}=replacement();const duplicate=structuredClone(evidence);duplicate.sender_before_snapshot.children.push(structuredClone(duplicate.sender_before_snapshot.children[0]));assert.throws(()=>buildContentEditWitness(duplicate));
 const duplicateAfter=structuredClone(evidence);duplicateAfter.sender_after_snapshot.children.push(structuredClone(duplicateAfter.sender_after_snapshot.children[0]));assert.throws(()=>buildContentEditWitness(duplicateAfter));
});

for(const name of fs.readdirSync(dir).filter(name=>name.startsWith('content-edit-native-table-')&&name.includes('-fault')))test(`original ${name} retains its refused cross-engine allocation fault`,()=>{const f=JSON.parse(fs.readFileSync(new URL(name,dir)));assert.throws(()=>replayContentEditMutation(Object.fromEntries(['sender_state_base64','current_state_base64','writer_client','operation','footprint'].map(key=>[key,f[key]]))),/differs from executed/);});
