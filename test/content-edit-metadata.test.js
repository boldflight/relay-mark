import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import * as Y from 'yjs';
import {Step} from 'prosemirror-transform';
import {EditorState} from 'prosemirror-state';
import {initProseMirrorDoc,updateYFragment,ProsemirrorBinding} from '@tiptap/y-tiptap';
import {createCanonicalEditorSchema,applyDocumentContentEdit,buildContentEditWitness,buildOwnedHistoryWitness} from '../src/content-edit.js';
import {proseMirrorToRelayMark} from '../src/document-adapter.js';
import {captureContentEditSnapshot,captureContentEditFootprint} from '../adapters/collaboration/content-edit-observer.js';
import {replayContentEditMutation,captureOwnedHistoryObservation,finishOwnedHistoryObservation} from '../adapters/collaboration/content-edit-mutation.js';
import {bindOwnedHistoryOwner,bindOwnedCommandGroup,readOwnedCommandGroup,bindOwnedCommandHistory} from '../adapters/collaboration/owned-command-group.js';
import {protectOwnedHistoryBranches} from '../adapters/collaboration/owned-history-branches.js';
const schema=createCanonicalEditorSchema(),ownerID='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',commandID='11111111-1111-4111-8111-111111111111';
const enc=b=>Buffer.from(b).toString('base64'),dec=b=>new Uint8Array(Buffer.from(b,'base64'));
const base=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-typing-mutation.json',import.meta.url))).sender_state_base64;
const metadata={frontmatter:{title:'Exact 🌍 recovery'},annotations:[],resources:[],meta:{retained:'original'}};
const steps=[{stepType:'replace',from:2,to:2,slice:{content:[{type:'text',text:'🚀',marks:[{type:'bold'}]}]}},{stepType:'docAttr',attr:'relaymark',value:metadata}];
function before(doc){return {state:enc(Y.encodeStateAsUpdate(doc)),snapshot:enc(Y.encodeSnapshot(Y.snapshot(doc))),identity:captureContentEditSnapshot(doc.getXmlFragment('default')),clocks:captureContentEditFootprint(doc,new Uint8Array([0,0])).state_vector};}
function update(doc,fn){const updates=[],on=u=>updates.push(u);doc.on('update',on);try{fn();}finally{doc.off('update',on);}assert.equal(updates.length,1,'body and envelope must have one actual update');return updates[0];}
function write(doc,command,origin){const initialized=initProseMirrorDoc(doc.getXmlFragment('default'),schema);let pm=initialized.doc;for(const json of command){const result=Step.fromJSON(schema,json).apply(pm);assert.equal(result.failed,null);pm=result.doc;}return update(doc,()=>doc.transact(()=>updateYFragment(doc,doc.getXmlFragment('default'),pm,initialized.meta),origin));}
function syncSteps(doc,pre){let state=EditorState.create({schema,doc:pre}),steps=[];const binding=new ProsemirrorBinding(doc.getXmlFragment('default'));binding.prosemirrorView={get state(){return state;},dispatch(tr){steps.push(...tr.steps.map(step=>step.toJSON()));state=state.apply(tr);}};binding._forceRerender();assert.deepEqual(state.doc.toJSON(),initProseMirrorDoc(doc.getXmlFragment('default'),schema).doc.toJSON());return steps;}
function seed(){const doc=new Y.Doc({gc:false});Y.applyUpdate(doc,dec(base));doc.clientID=404;doc.getMap('relaymark').set('meta',{obsolete:true});doc.clientID=101;return doc;}
function normal(doc,b,bytes){const after=captureContentEditSnapshot(doc.getXmlFragment('default')),footprint=captureContentEditFootprint(doc,bytes),operation={kind:'content_edit',steps,copies:[]};const proof=buildContentEditWitness({sender_before_snapshot:b.identity,sender_after_snapshot:after,before_snapshot:b.identity,after_snapshot:after,before_state_vector:b.clocks,operation,footprint});return {proof,evidence:{sender_state_base64:b.state,current_state_base64:b.state,writer_client:101,operation:{...operation,copies:proof.proven_copies},footprint}};}
test('DocAttrStep replaces exact authored metadata including explicit empty values and removes absent keys',()=>{
 const ast={type:'relaymark.document',blocks:[{id:'b11111111111141118111111111111111',type:'paragraph',content:[{type:'text',text:'Rich'}]}],frontmatter:{old:true},meta:{obsolete:true}};
 const result=applyDocumentContentEdit(ast,{kind:'content_edit',steps:[{stepType:'docAttr',attr:'relaymark',value:{annotations:[],resources:[],meta:{}}}]});
 assert.deepEqual(result.authored_document,{type:'relaymark.document',blocks:ast.blocks,annotations:[],resources:[],meta:{}});
 for(const value of [{unknown:true},{meta:{bad:undefined}},{resources:{}},null])assert.throws(()=>applyDocumentContentEdit(ast,{kind:'content_edit',steps:[{stepType:'docAttr',attr:'relaymark',value}]}));
 assert.throws(()=>applyDocumentContentEdit(ast,{kind:'content_edit',steps:[{stepType:'docAttr',attr:'domain',value:{}}]}));
 assert.throws(()=>proseMirrorToRelayMark({...result.document,attrs:{relaymark:null}}));
});
test('actual body and DocAttrStep emit one update with complete maintained mutation correspondence',()=>{
 const doc=seed(),b=before(doc),bytes=write(doc,steps),{proof,evidence}=normal(doc,b,bytes);
 assert.deepEqual(doc.getMap('relaymark').toJSON(),metadata);assert.deepEqual(Object.fromEntries(['frontmatter','annotations','resources','meta'].map(k=>[k,proof.authored_document[k]])),metadata);assert.deepEqual(proof.text_items.runs.map(r=>r.count),[2]);
 const replay=replayContentEditMutation(evidence);assert.equal(replay.complete_mutation_correspondence,true);assert.deepEqual(replay.footprint,evidence.footprint);
 assert.ok(replay.retained_field_changes.allocated.some(r=>r.parent?.root==='relaymark'&&r.key==='frontmatter'));doc.destroy();
});
test('hidden map writes cannot accompany an otherwise exact body and DocAttrStep',()=>{
 const doc=seed(),b=before(doc),bytes=write(doc,steps),hidden=update(doc,()=>doc.transact(()=>{doc.getMap('relaymark').set('meta',{hidden:true});doc.getMap('relaymark').set('meta',metadata.meta);}));
 const combined=Y.mergeUpdates([bytes,hidden]),{evidence}=normal(doc,b,combined);assert.deepEqual(doc.getMap('relaymark').toJSON(),metadata);
 assert.throws(()=>replayContentEditMutation(evidence),/differs from executed maintained/);doc.destroy();
});
test('same maintained manager undoes body and authored fields while retaining peer metadata and rich choice text',()=>{
 const doc=seed(),origin={},manager=new Y.UndoManager([doc.getXmlFragment('default'),doc.getMap('relaymark')],{trackedOrigins:new Set([origin]),captureTimeout:Infinity});protectOwnedHistoryBranches(manager);bindOwnedHistoryOwner(manager,ownerID);let popped;
 manager.on('stack-item-added',e=>{if(!manager.undoing&&!manager.redoing)bindOwnedCommandGroup(manager,e,commandID);});manager.on('stack-item-popped',e=>{popped=bindOwnedCommandHistory(manager,e);});
 const b=before(doc),bytes=write(doc,steps,origin),{evidence}=normal(doc,b,bytes),group=readOwnedCommandGroup(manager,commandID);evidence.operation.group=group;
 const receipts=[{transaction_id:commandID,sender_state_base64:b.state,update_base64:enc(bytes),operation:evidence.operation}],fixture={description:'Actual canonical body plus DocAttrStep metadata, independent peer map/choice change, same maintained owner undo/redo',initial_state_base64:b.state,normal:{...evidence,before_snapshot_base64:b.snapshot,update_base64:enc(bytes),text_items:normal(doc,b,bytes).proof.text_items},effects:[]};
 const peer=new Y.Doc({gc:false});Y.applyUpdate(peer,Y.encodeStateAsUpdate(doc));peer.getMap('relaymark');peer.clientID=303;const peerBefore=before(peer);let optionPosition;initProseMirrorDoc(peer.getXmlFragment('default'),schema).doc.descendants((node,pos)=>{if(node.isText&&node.text==='One')optionPosition=pos+node.nodeSize;});assert.ok(optionPosition);const peerSteps=[{stepType:'replace',from:optionPosition,to:optionPosition,slice:{content:[{type:'text',text:' peer',marks:[{type:'italic'}]}]}},{stepType:'docAttr',attr:'relaymark',value:{...metadata,frontmatter:{title:'Peer keeps 🌍 title'}}}],peerBytes=write(peer,peerSteps);fixture.peer={sender_state_base64:peerBefore.state,before_snapshot_base64:peerBefore.snapshot,steps:peerSteps,update_base64:enc(peerBytes)};Y.applyUpdate(doc,peerBytes);
 for(const[index,kind]of ['undo','redo'].entries()){
  const prior=before(doc),pre=initProseMirrorDoc(doc.getXmlFragment('default'),schema).doc,token=captureOwnedHistoryObservation(doc),inverseBytes=update(doc,()=>manager[kind]()),accounting=finishOwnedHistoryObservation(doc,token),actualSteps=syncSteps(doc,pre);
  assert.ok(actualSteps.some(step=>step.stepType==='docAttr'&&step.attr==='relaymark'));
  const operation={kind:'content_edit',steps:actualSteps,history:popped},footprint=captureContentEditFootprint(doc,inverseBytes),producer=buildOwnedHistoryWitness({before_snapshot:prior.identity,after_snapshot:captureContentEditSnapshot(doc.getXmlFragment('default')),before_state_vector:prior.clocks,operation,restored_copies:accounting.proven_copies,footprint});operation.copies=producer.proven_copies;
  const clocks=new Map(prior.clocks.map(r=>[r.client,r.clock])),writers=new Set(footprint.structs.filter(r=>r.item.clock+r.count>(clocks.get(r.item.client)||0)).map(r=>r.item.client));
  const replayEvidence={initial_state_base64:b.state,receipts:receipts.slice(),sender_state_base64:prior.state,current_state_base64:prior.state,writer_client:writers.size?[...writers][0]:null,operation,footprint},result=replayContentEditMutation(replayEvidence);fixture.effects.push({kind,before_snapshot_base64:prior.snapshot,update_base64:enc(inverseBytes),after_state_base64:enc(Y.encodeStateAsUpdate(doc)),evidence:replayEvidence,text_items:result.text_items,proven_copies:result.proven_copies});
  assert.equal(result.owned_history_correspondence,true);assert.deepEqual(result.text_items,{runs:[]});assert.deepEqual(doc.getMap('relaymark').get('frontmatter'),{title:'Peer keeps 🌍 title'});assert.equal(doc.getXmlFragment('default').get(1).get(1).get(0).toString(),'One<italic> peer</italic>');
  receipts.push({transaction_id:index?'33333333-3333-4333-8333-333333333333':'22222222-2222-4222-8222-222222222222',sender_state_base64:prior.state,update_base64:enc(inverseBytes),operation});
 }
 if(process.env.RELAYMARK_WRITE_METADATA_FIXTURE)fs.writeFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-metadata-history.json',import.meta.url),JSON.stringify(fixture,null,2)+'\n');manager.destroy();peer.destroy();doc.destroy();
});
