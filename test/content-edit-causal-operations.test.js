import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import * as Y from 'yjs';
import {Step} from 'prosemirror-transform';import {initProseMirrorDoc,updateYFragment,ySyncPluginKey} from '@tiptap/y-tiptap';
import {createCanonicalEditorSchema,createContentEditWrite,buildContentEditWitness,replayContentEditMutation,prepareContentEditWitness} from '../src/content-edit.js';
import {captureContentEditSnapshot,captureContentEditFootprint} from '../adapters/collaboration/content-edit-observer.js';
import {bindOwnedHistoryOwner,bindOwnedCommandGroup,readOwnedCommandGroup} from '../adapters/collaboration/owned-command-group.js';
const enc=b=>Buffer.from(b).toString('base64');const schema=createCanonicalEditorSchema();
function seed(name,key='sender_state_base64'){const f=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/'+name+'.json',import.meta.url))),doc=new Y.Doc({gc:false});Y.applyUpdate(doc,Buffer.from(f[key],'base64'));doc.clientID=101;return doc;}
function write(doc,steps){const root=doc.getXmlFragment('default'),initialized=initProseMirrorDoc(root,schema),before=captureContentEditSnapshot(root),beforeState=enc(Y.encodeStateAsUpdate(doc)),beforeSnapshot=enc(Y.encodeSnapshot(Y.snapshot(doc))),clocks=captureContentEditFootprint(doc,new Uint8Array([0,0])).state_vector;let after=initialized.doc;for(const json of steps){const result=Step.fromJSON(schema,json).apply(after);assert.equal(result.failed,null);after=result.doc}const updates=[];const on=u=>updates.push(u);doc.on('update',on);initialized.meta.contentEditWrite=createContentEditWrite(initialized.doc,steps,after);updateYFragment(doc,root,after,initialized.meta);doc.off('update',on);assert.equal(updates.length,1);const operation={kind:'content_edit',steps},evidence={sender_before_snapshot:before,sender_after_snapshot:captureContentEditSnapshot(root),before_snapshot:before,after_snapshot:captureContentEditSnapshot(root),before_state_vector:clocks,operation,footprint:captureContentEditFootprint(doc,updates[0])};return {root,beforeState,beforeSnapshot,update:updates[0],operation,evidence,proof:buildContentEditWitness(evidence)};}
test('real two-rich-leaf human command refuses an omitted second selector while exact full mutation remains proven',()=>{
 const doc=seed('content-edit-typing-mutation'),root=doc.getXmlFragment('default'),before=initProseMirrorDoc(root,schema).doc;
 const first={stepType:'replace',from:2,to:2,slice:{content:[{type:'text',text:' Human🚀'}]}};
 const intermediate=Step.fromJSON(schema,first).apply(before).doc;let option;
 intermediate.descendants((node,pos)=>{if(node.type.name==='questionOption'&&option===undefined)option=pos+1+node.content.size});
 const second={stepType:'replace',from:option,to:option,slice:{content:[{type:'text',text:' Choice'}]}};
 const commandID='88888888-8888-4888-8888-888888888888',manager=new Y.UndoManager(root,{trackedOrigins:new Set([ySyncPluginKey])});bindOwnedHistoryOwner(manager,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');manager.on('stack-item-added',event=>{if(!manager.undoing&&!manager.redoing)bindOwnedCommandGroup(manager,event,commandID)});
 const result=write(doc,[first,second]),group=readOwnedCommandGroup(manager,commandID);result.operation={...result.proof.operation,group};
 assert.equal(result.proof.text_items.runs.reduce((n,r)=>n+r.count,0),15);
 assert.equal(new Set(result.proof.text_items.runs.map(r=>JSON.stringify(r.type))).size,2);
 const omitted=structuredClone(result.evidence);omitted.operation=result.operation;omitted.text_items={runs:[result.proof.text_items.runs[0]]};
 assert.throws(()=>prepareContentEditWitness(omitted),/Omitted or unproven fresh/);
 if(process.env.RELAYMARK_WRITE_CAUSAL_FIXTURE)fs.writeFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-two-rich-leaf-input.json',import.meta.url),JSON.stringify({description:'Actual one maintained command adds human Unicode prose in a paragraph and a separately rich form option',transaction_id:commandID,sender_state_base64:result.beforeState,before_snapshot_base64:result.beforeSnapshot,update_base64:enc(result.update),operation:result.operation,text_items:result.proof.text_items,evidence:{...result.evidence,operation:result.operation}},null,2)+'\n');
 assert.equal(replayContentEditMutation({sender_state_base64:result.beforeState,current_state_base64:result.beforeState,writer_client:101,operation:result.operation,footprint:result.evidence.footprint}).complete_mutation_correspondence,true);
 manager.destroy();doc.destroy();
});
test('mark-transformed retained branch copies bind only exact maintained retention, never literal inserted Slice guesses',()=>{
 const doc=seed('retained-marked-text-branches','state_base64');const before=initProseMirrorDoc(doc.getXmlFragment('default'),schema).doc;const steps=[];before.descendants((node,pos)=>{if(node.isText)for(const mark of node.marks)steps.push({stepType:'removeMark',from:pos,to:pos+node.nodeSize,mark:mark.toJSON()})});
 const result=write(doc,steps);assert.deepEqual(result.proof.text_items,{runs:[]});assert.equal(result.proof.proven_copies.reduce((n,c)=>n+c.destination.runs.reduce((m,r)=>m+r.count,0),0),2);
 assert.equal(replayContentEditMutation({sender_state_base64:result.beforeState,current_state_base64:result.beforeState,writer_client:101,operation:{...result.operation,copies:result.proof.proven_copies},footprint:result.evidence.footprint}).complete_mutation_correspondence,true);
 doc.destroy();
 const pasted=seed('retained-marked-text-branches','state_base64'),original=captureContentEditSnapshot(pasted.getXmlFragment('default')).children[0].children[2],copySource={runs:[{type:original.type,item:original.runs[0].item,count:1}]};
 const literal=write(pasted,[{stepType:'replace',from:3,to:4,slice:{content:[{type:'text',text:'B'}]}}]);
 assert.equal(literal.proof.text_items.runs.reduce((n,r)=>n+r.count,0),1);
 assert.throws(()=>prepareContentEditWitness({...literal.evidence,operation:{...literal.proof.operation,copies:[...literal.proof.proven_copies,{source:copySource,destination:literal.proof.text_items}]},text_items:{runs:[]}}),/Unproven content-edit causal copy/);
 pasted.destroy();
});
