import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import * as Y from 'yjs';
import * as ContentEdit from '../src/content-edit.js';
import {captureContentEditSnapshot,captureContentEditFootprint} from '../adapters/collaboration/content-edit-observer.js';
const fixture=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-native-reviewed-recovery.json',import.meta.url)));
const decode=value=>new Uint8Array(Buffer.from(value,'base64'));
const json=value=>JSON.parse(Buffer.from(value,'base64').toString());
function actualEvidence(){
 const donor=new Y.Doc({gc:false}),target=new Y.Doc({gc:false});
 Y.applyUpdate(donor,decode(fixture.original_document_base64));donor.getMap('relaymark');Y.applyUpdate(target,decode(fixture.target_before_base64));
 const before=captureContentEditSnapshot(target.getXmlFragment('default')),clocks=captureContentEditFootprint(target,Uint8Array.of(0,0)).state_vector;
 const transaction=json(fixture.native_transaction_base64),carrier=transaction.nativeContentEdit;
 Y.applyUpdate(target,decode(fixture.update_base64));const after=captureContentEditSnapshot(target.getXmlFragment('default'));
 const recovery={archive_sha256:'a'.repeat(64),reviewed_document_sha256:'b'.repeat(64),block_indices:[0,1],target_guard:{body_revision:'sha256:'+ 'c'.repeat(64)},donor_cut:null};
 const evidence={sender_before_snapshot:before,sender_after_snapshot:after,before_snapshot:before,after_snapshot:after,before_state_vector:clocks,operation:{kind:'content_edit',steps:json(carrier.steps),copies:[],reviewed_recovery:recovery},footprint:captureContentEditFootprint(target,decode(fixture.update_base64)),archive_identity_snapshot:captureContentEditSnapshot(donor.getXmlFragment('default')),reviewed_document:json(fixture.original_authored_ast_base64)};
 donor.destroy();target.destroy();return evidence;
}
const extent=runs=>runs.reduce((n,r)=>n+r.count,0);
test('actual native foreign generated recovery accounts18 imported units without declaring human input',()=>{
 const evidence=actualEvidence(),result=ContentEdit.prepareReviewedRecoveryWitness(evidence);
 assert.equal(result.complete_recovery_correspondence,true);assert.equal(result.requires_recovery_authorization,true);
 assert.deepEqual(result.text_items,{runs:[]});assert.deepEqual(result.proven_copies,[]);
 assert.equal(result.recovery_regions.reduce((n,r)=>n+r.count,0),18);
 assert.deepEqual(result.recovery_regions.map(r=>[r.archive_path,r.archive_offset,r.count]),[[[0,0],0,1],[[0,0],1,2],[[0,0],3,3],[[1,0,0],0,6],[[1,1,0],0,3],[[1,2,0],0,3]]);
 assert.equal(extent(result.fresh_items.runs),18);
 assert.equal(ContentEdit.replayContentEditMutation({sender_state_base64:fixture.target_before_base64,current_state_base64:fixture.target_before_base64,writer_client:result.fresh_items.runs[0].item.client,operation:evidence.operation,footprint:evidence.footprint}).complete_mutation_correspondence,true);
});

import {parseDocument} from '../src/document-source.js';
import {relayMarkToProseMirror,proseMirrorToRelayMark} from '../src/document-adapter.js';
import {prosemirrorToYXmlFragment,initProseMirrorDoc,updateYFragment} from '@tiptap/y-tiptap';
import {Step,Transform} from 'prosemirror-transform';
const schema=ContentEdit.createCanonicalEditorSchema();
const encode=bytes=>Buffer.from(bytes).toString('base64');
function duplicateEvidence({repairIDs=false,markupRepairs=false,afterRepairs=null,repairAttributes=null}={}){
 const donor=new Y.Doc({gc:false}),sender=new Y.Doc({gc:false}),current=new Y.Doc({gc:false});donor.clientID=21;sender.clientID=31;
 const ast=parseDocument('Same **🌍**\n\nSame **🌍**\n\n@Callout(tone: "info") {\nKept *🌍*\n}\n\n| A | B |\n| --- | --- |\n| C | D |\n\n![kept](https://example.com/kept.png)',{namespace:'regional-duplicate'});
 ast.frontmatter={title:'Archived title'};
 ast.blocks.push({id:'b00000000001040008000000000000000',type:'relay.video_embed',props:{videoId:'11111111-1111-4111-8111-111111111111'},content:[]});
 prosemirrorToYXmlFragment(schema.nodeFromJSON(relayMarkToProseMirror(ast)),donor.getXmlFragment('default'));
 const seed=parseDocument('Current **peer** prefix',{namespace:'regional-target'});seed.frontmatter={title:'Current title'};
 prosemirrorToYXmlFragment(schema.nodeFromJSON(relayMarkToProseMirror(seed)),sender.getXmlFragment('default'));
 const before=captureContentEditSnapshot(sender.getXmlFragment('default')),initial=Y.encodeStateAsUpdate(sender);
 Y.applyUpdate(current,initial);current.getMap('relaymark');current.clientID=41;
 current.getXmlFragment('default').get(0).get(0).insert(0,'Unseen peer ');
 const lockedBefore=captureContentEditSnapshot(current.getXmlFragment('default')),lockedState=encode(Y.encodeStateAsUpdate(current));
 const clocks=captureContentEditFootprint(current,Uint8Array.of(0,0)).state_vector;
 const archive=captureContentEditSnapshot(donor.getXmlFragment('default')),source=initProseMirrorDoc(donor.getXmlFragment('default'),schema).doc;
 let next=100;
 function rekey(node){const out=structuredClone(node);if(out.attrs&&Object.hasOwn(out.attrs,'relaymarkId'))out.attrs.relaymarkId='b'+(next++).toString(16).padStart(12,'0')+'40008'+'0'.repeat(15);if(out.content)out.content=out.content.map(rekey);return out;}
 const initialized=initProseMirrorDoc(sender.getXmlFragment('default'),schema),content=source.toJSON().content.map(rekey);
 const repairs=[];let pos=initialized.doc.content.size;
 function clear(node,position){if(node.attrs&&Object.hasOwn(node.attrs,'relaymarkId')){repairs.push([position,node.attrs.relaymarkId]);node.attrs.relaymarkId=null;}let child=position+1;for(const n of node.content||[]){clear(n,child);child+=schema.nodeFromJSON(n).nodeSize;}}
 if(repairIDs)for(const node of content){clear(node,pos);pos+=schema.nodeFromJSON(node).nodeSize;}
 const steps=[{stepType:'replace',from:initialized.doc.content.size,to:initialized.doc.content.size,slice:{content}}];
 let target=Step.fromJSON(schema,steps[0]).apply(initialized.doc).doc;
 if(repairIDs){const tr=new Transform(target);for(const [position,id]of repairs){const node=tr.doc.nodeAt(position);if(markupRepairs)tr.setNodeMarkup(position,null,repairAttributes?repairAttributes(node,{...node.attrs,relaymarkId:id}):{...node.attrs,relaymarkId:id},node.marks);else tr.setNodeAttribute(position,'relaymarkId',id);}if(afterRepairs)afterRepairs(tr);steps.push(...tr.steps.map(step=>step.toJSON()));target=tr.doc;}
 const updates=[];sender.on('update',update=>updates.push(update));
 initialized.meta.contentEditWrite=ContentEdit.createContentEditWrite(initialized.doc,steps,target);updateYFragment(sender,sender.getXmlFragment('default'),target,initialized.meta);
 assert.equal(updates.length,1);Y.applyUpdate(current,updates[0]);
 const after=captureContentEditSnapshot(current.getXmlFragment('default')),senderAfter=captureContentEditSnapshot(sender.getXmlFragment('default'));
 const indices=source.toJSON().content.map((_,i)=>i);
 const evidence={sender_before_snapshot:before,sender_after_snapshot:senderAfter,before_snapshot:lockedBefore,after_snapshot:after,before_state_vector:clocks,operation:{kind:'content_edit',steps,copies:[],reviewed_recovery:{...actualEvidence().operation.reviewed_recovery,block_indices:indices}},footprint:captureContentEditFootprint(current,updates[0]),archive_identity_snapshot:archive,reviewed_document:proseMirrorToRelayMark(source.toJSON())};
 const mutation={sender_state_base64:encode(initial),current_state_base64:lockedState,writer_client:31,operation:evidence.operation,footprint:evidence.footprint};
 donor.destroy();sender.destroy();current.destroy();return{evidence,mutation};
}
test('duplicate donor text keeps distinct archive paths through actual append with unseen peer prefix and rich fields',()=>{
 const {evidence,mutation}=duplicateEvidence(),proof=ContentEdit.prepareReviewedRecoveryWitness(evidence);
 assert.deepEqual(proof.text_items,{runs:[]});assert.equal(proof.recovery_regions.filter(r=>r.archive_path[0]===0).reduce((n,r)=>n+r.count,0),7);
 assert.equal(proof.recovery_regions.filter(r=>r.archive_path[0]===1).reduce((n,r)=>n+r.count,0),7);
 const first=proof.recovery_regions.find(r=>r.archive_path[0]===0),second=proof.recovery_regions.find(r=>r.archive_path[0]===1);
 assert.notDeepEqual(first.destination,second.destination);
 assert.deepEqual(proof.authored_document.frontmatter,{title:'Current title'});
 assert.equal(evidence.reviewed_document.blocks.at(-1).type,'relay.video_embed');
 assert.equal(ContentEdit.replayContentEditMutation(mutation).complete_mutation_correspondence,true);
});
test('different selected path, altered marked content/properties, target replacement and illegal allocator repair refuse',()=>{
 for(const mutate of [
  e=>{e.operation.reviewed_recovery.block_indices=[1];},
  e=>{e.reviewed_document.blocks[0].content[0].text='Wrong';},
  e=>{e.operation.steps[0].slice.content[0].content[1].marks=[{type:'italic'}];},
  e=>{e.operation.steps[0].slice.content[1].attrs.required=true;},
  e=>{e.operation.steps[0].to++;},
  e=>{e.operation.steps.push({stepType:'attr',pos:22,attr:'relaymarkId',value:'b00000000000040008000000000000001'});},
  e=>{e.operation.steps.push({stepType:'attr',pos:22,attr:'headingId',value:'replacement'});},
  e=>{e.operation.steps.push({stepType:'docAttr',attr:'relaymark',value:{}});}
 ]){const e=actualEvidence();mutate(e);assert.throws(()=>ContentEdit.prepareReviewedRecoveryWitness(e));}
 const e=actualEvidence();e.operation.steps[0].slice.content[1].content[1].attrs.id='wrong-option';assert.throws(()=>ContentEdit.prepareReviewedRecoveryWitness(e),/changed archive content or properties/);
});
test('a hidden transient extra string cannot disappear behind complete visible recovery coverage',()=>{
 const evidence=actualEvidence(),doc=new Y.Doc({gc:false});Y.applyUpdate(doc,decode(fixture.target_before_base64));Y.applyUpdate(doc,decode(fixture.update_base64));
 const updates=[decode(fixture.update_base64)];doc.on('update',u=>updates.push(u));
 const text=doc.getXmlFragment('default').get(0).get(0);
 doc.transact(()=>{text.insert(0,'Hidden');text.delete(0,6);});
 evidence.after_snapshot=captureContentEditSnapshot(doc.getXmlFragment('default'));
 evidence.footprint=captureContentEditFootprint(doc,Y.mergeUpdates(updates));
 assert.throws(()=>ContentEdit.prepareReviewedRecoveryWitness(evidence),/Hidden or unprovable string mutation/);doc.destroy();
});
test('regional evidence cannot enter the ordinary typed/copy classifier and ordinary external paste remains unchanged',()=>{
 const evidence=actualEvidence();const ordinary=Object.fromEntries(['sender_before_snapshot','sender_after_snapshot','before_snapshot','after_snapshot','before_state_vector','operation','footprint'].map(key=>[key,evidence[key]]));
 assert.throws(()=>ContentEdit.buildContentEditWitness(ordinary),/requires regional/);
 assert.throws(()=>ContentEdit.prepareContentEditWitness({...ordinary,text_items:{runs:[]}}),/requires regional/);
 delete ordinary.operation.reviewed_recovery;
 const pasted=ContentEdit.buildContentEditWitness(ordinary);assert.equal(extent(pasted.text_items.runs),18);assert.deepEqual(pasted.proven_copies,[]);
});

test('actual appended null-ID allocation repairs remain inside imported node positions',()=>{
 const {evidence,mutation}=duplicateEvidence({repairIDs:true}),proof=ContentEdit.prepareReviewedRecoveryWitness(evidence);
 assert.deepEqual(proof.text_items,{runs:[]});assert.equal(proof.complete_recovery_correspondence,true);
 assert.equal(ContentEdit.replayContentEditMutation(mutation).complete_mutation_correspondence,true);
});


test('mounted setNodeMarkup allocator repairs keep exact rich imported regions and original steps',()=>{
 const {evidence,mutation}=duplicateEvidence({repairIDs:true,markupRepairs:true});
 assert.ok(evidence.operation.steps.some(step=>step.stepType==='replaceAround'));
 assert.ok(evidence.operation.steps.slice(1).some(step=>step.stepType==='replace')); // actual image/video leaf repairs
 const originalSteps=JSON.stringify(evidence.operation.steps),proof=ContentEdit.prepareReviewedRecoveryWitness(evidence);
 assert.equal(proof.complete_recovery_correspondence,true);assert.deepEqual(proof.text_items,{runs:[]});
 assert.deepEqual(proof.proven_copies,[]);assert.equal(JSON.stringify(evidence.operation.steps),originalSteps);
 assert.equal(ContentEdit.replayContentEditMutation(mutation).complete_mutation_correspondence,true);
 assert.deepEqual(proof.authored_document.frontmatter,{title:'Current title'});
});
test('mounted allocator repairs cannot change geometry, rich fields, content or existing target nodes',()=>{
 const {evidence}=duplicateEvidence({repairIDs:true,markupRepairs:true});
 const at=evidence.operation.steps.findIndex(step=>step.stepType==='replaceAround');
 const leaf=evidence.operation.steps.findIndex((step,i)=>i>0&&step.stepType==='replace');
 for(const mutate of [
  e=>{e.operation.steps[at].gapFrom++;},
  e=>{e.operation.steps[at].gapTo--;},
  e=>{e.operation.steps[at].insert=0;},
  e=>{e.operation.steps[at].structure=false;},
  e=>{e.operation.steps[at].slice.content[0].type='heading';},
  e=>{e.operation.steps[at].slice.content[0].marks=[{type:'bold'}];},
  e=>{e.operation.steps[at].slice.content[0].content=[{type:'text',text:'Extra'}];},
  e=>{e.operation.steps[at].slice.content[0].attrs.relaymarkId=null;},
  e=>{e.operation.steps[leaf].slice.content[0].attrs.width=999;},
  e=>{e.operation.steps[leaf].to++;},
  e=>{const tr=new Transform(schema.nodeFromJSON(relayMarkToProseMirror(parseDocument('Current **peer** prefix',{namespace:'regional-target'}))));tr.setNodeMarkup(0,null,{...tr.doc.nodeAt(0).attrs,relaymarkId:'b00000000000040008000000000000001'});e.operation.steps.push(tr.steps[0].toJSON());}
 ]){const altered=structuredClone(evidence);mutate(altered);assert.throws(()=>ContentEdit.prepareReviewedRecoveryWitness(altered));}
});

test('actual matching repair updates cannot alter imported properties or unique retained target identity',()=>{
 for(const repairAttributes of [
  (node,attrs)=>node.type.name==='image'?{...attrs,width:999}:attrs,
  (node,attrs)=>node.type.name==='callout'?{...attrs,tone:'warning'}:attrs
 ]){
  const {evidence}=duplicateEvidence({repairIDs:true,markupRepairs:true,repairAttributes});
  // Every changed field is in the actual Steps, update, snapshots and footprint.
  // Visible-result equality must not grant an unrelated repair permission.
  assert.throws(()=>ContentEdit.prepareReviewedRecoveryWitness(evidence),/Illegal reviewed append repair/);
 }
 const {evidence}=duplicateEvidence({repairIDs:true,markupRepairs:true,afterRepairs:tr=>{const node=tr.doc.nodeAt(0);tr.setNodeMarkup(0,null,{...node.attrs,relaymarkId:'b00000000000040008000000000000001'},node.marks);}});
 assert.throws(()=>ContentEdit.prepareReviewedRecoveryWitness(evidence),/Illegal reviewed append repair/);
});

test('regional human mapping follows exact original item/type and path despite duplicated text',()=>{
 const {evidence}=duplicateEvidence(),result=ContentEdit.prepareReviewedRecoveryWitness(evidence);
 const regional={archive_identity_snapshot:evidence.archive_identity_snapshot,recovery_regions:result.recovery_regions};
 const candidates=ContentEdit.reviewedRecoverySourceSelection(regional);
 assert.equal(extent(candidates.runs),result.recovery_regions.reduce((n,r)=>n+r.count,0));
 const segments=ContentEdit.resolveContentEditTextItems(evidence.archive_identity_snapshot,candidates).segments;
 const selected=segments.find(part=>part.path[0]===1&&part.text==='🌍');assert.ok(selected);
 const source_selector={runs:[{type:selected.type,item:selected.item,count:selected.count}]};
 const mapped=ContentEdit.mapReviewedRecoverySelection({...regional,source_selector});
 assert.equal(extent(mapped.destination.runs),2);
 const output=ContentEdit.resolveContentEditTextItems(evidence.after_snapshot,mapped.destination).segments;
 assert.equal(output.map(part=>part.text).join(''),'🌍');
 assert.equal(output[0].path[0],2); // retained target block then donor blocks0/1
 assert.deepEqual(ContentEdit.mapReviewedRecoverySelection({...regional,source_selector:{runs:[]}}),{destination:{runs:[]}});
 const forged=structuredClone(source_selector);forged.runs[0].type.clock++;
 assert.throws(()=>ContentEdit.mapReviewedRecoverySelection({...regional,source_selector:forged}),/wrongly typed|unavailable/);
 const half=structuredClone(source_selector);half.runs[0].count=1;
 assert.throws(()=>ContentEdit.mapReviewedRecoverySelection({...regional,source_selector:half}),/Unicode/);
 const duplicate=structuredClone(regional);duplicate.recovery_regions.push(duplicate.recovery_regions[0]);
 assert.throws(()=>ContentEdit.reviewedRecoverySourceSelection(duplicate),/Duplicate/);
});

test('fragmented imported archive candidates cannot bypass the existing command selector run bound',()=>{
 const runs=Array.from({length:4097},(_,index)=>({item:{client:3,clock:index+2},count:1,text:'x',attributes:{}}));
 const snapshot={kind:'fragment',root:'default',children:[{kind:'element',type:{client:3,clock:0},name:'paragraph',attributes:{relaymarkId:'b00000000000040008000000000000001'},children:[{kind:'text',type:{client:3,clock:1},runs}]}]};
 const recovery_regions=[{archive_path:[0,0],archive_offset:0,count:4097,destination:{runs:[{type:{client:4,clock:1},item:{client:4,clock:2},count:4097}]}}];
 assert.throws(()=>ContentEdit.reviewedRecoverySourceSelection({archive_identity_snapshot:snapshot,recovery_regions}),/Invalid causal selection/);
});

function classifiedRecovery(){
 const evidence=actualEvidence(),prepared=ContentEdit.prepareReviewedRecoveryWitness(evidence);
 const replay=ContentEdit.replayContentEditMutation({sender_state_base64:fixture.target_before_base64,current_state_base64:fixture.target_before_base64,writer_client:prepared.fresh_items.runs[0].item.client,operation:evidence.operation,footprint:evidence.footprint});
 const proof={...prepared,...replay};
 const region=prepared.recovery_regions.find(r=>r.count===2);
 const context={recovery_regions:prepared.recovery_regions,human_destinations:structuredClone(region.destination)};
 const binding={document_id:'target',incarnation:'target-incarnation'};
 const transaction={transaction_id:'22222222-2222-4222-8222-222222222222',text_items:prepared.text_items,content_edit:evidence.operation};
 return {binding,transaction,proof,context};
}
test('authenticated regional context preserves only2 donor human units in the actual18 unit native append',()=>{
 const {binding,transaction,proof,context}=classifiedRecovery();
 const reference=ContentEdit.classifyContentEditReference(binding,transaction,proof,{runs:[]},context);
 assert.deepEqual(Object.keys(reference).sort(),['binding','human_destinations','proven_copies','text_items','transaction_id']);
 assert.deepEqual(reference.human_destinations,context.human_destinations);
 const candidates={runs:context.recovery_regions.flatMap(r=>r.destination.runs)};
 assert.deepEqual(ContentEdit.foldSourceReferences(binding,candidates,[reference],{[transaction.transaction_id]:context}),context.human_destinations);
 const partition=ContentEdit.partitionReviewedRecoveryDestinations({...context,generated_destinations:{runs:[]}});
 assert.deepEqual(partition.human_destinations,context.human_destinations);
 assert.deepEqual(partition.generated_destinations,{runs:[]});assert.equal(extent(partition.unknown_destinations.runs),16);
 const generated=context.recovery_regions[0].destination;
 const known=ContentEdit.partitionReviewedRecoveryDestinations({...context,generated_destinations:generated});
 assert.equal(extent(known.generated_destinations.runs),1);assert.equal(extent(known.unknown_destinations.runs),15);
});
test('regional receipt classification refuses missing, forged, partial or cross-command private context',()=>{
 const {binding,transaction,proof,context}=classifiedRecovery();
 const classify=(tx=transaction,p=proof,c=context)=>ContentEdit.classifyContentEditReference(binding,tx,p,{runs:[]},c);
 assert.throws(()=>ContentEdit.classifyContentEditReference(binding,transaction,proof,{runs:[]}));
 for(const field of ['complete_recovery_correspondence','complete_mutation_correspondence']){const p=structuredClone(proof);delete p[field];assert.throws(()=>classify(transaction,p));}
 const partial=structuredClone(proof);partial.fresh_items.runs.pop();assert.throws(()=>classify(transaction,partial));
 const shifted=structuredClone(context);shifted.recovery_regions[0].archive_offset++;assert.throws(()=>classify(transaction,proof,shifted));
 const forged=structuredClone(context);forged.human_destinations.runs[0].type.clock++;assert.throws(()=>classify(transaction,proof,forged),{code:'source_identity_mismatch'});
 const outside=structuredClone(context);outside.human_destinations.runs[0].item.clock+=10000;assert.throws(()=>classify(transaction,proof,outside));
 const altered=structuredClone(transaction);altered.content_edit.reviewed_recovery.archive_sha256='d'.repeat(64);assert.throws(()=>classify(altered));
 const changedSteps=structuredClone(transaction);changedSteps.content_edit.steps[0].from++;assert.throws(()=>classify(changedSteps));
 const ordinary=structuredClone(transaction);delete ordinary.content_edit.reviewed_recovery;assert.throws(()=>classify(ordinary));
 const reference=classify(),candidates={runs:context.recovery_regions.flatMap(r=>r.destination.runs)};
 assert.throws(()=>ContentEdit.foldSourceReferences(binding,candidates,[reference]));
 assert.throws(()=>ContentEdit.foldSourceReferences(binding,candidates,[reference],{'33333333-3333-4333-8333-333333333333':context}));
 const relabeled={...reference,transaction_id:'33333333-3333-4333-8333-333333333333'};
 assert.throws(()=>ContentEdit.foldSourceReferences(binding,candidates,[relabeled],{[transaction.transaction_id]:context}));
 const wrong=structuredClone(reference);wrong.human_destinations={runs:[]};assert.throws(()=>ContentEdit.foldSourceReferences(binding,candidates,[wrong],{[transaction.transaction_id]:context}));
 assert.throws(()=>ContentEdit.foldSourceReferences(binding,candidates,[reference,reference],{[transaction.transaction_id]:context}));
});
test('regional partitions reject overlap, forged types, duplicate paths and unchanged command fragmentation limits',()=>{
 const {context}=classifiedRecovery();const partition=value=>ContentEdit.partitionReviewedRecoveryDestinations(value);
 assert.throws(()=>partition({...context,generated_destinations:context.human_destinations}));
 const forged=structuredClone(context.human_destinations);forged.runs[0].type.clock++;assert.throws(()=>partition({...context,generated_destinations:forged}),{code:'source_identity_mismatch'});
 const duplicate=structuredClone(context);duplicate.recovery_regions.push(duplicate.recovery_regions[0]);assert.throws(()=>partition({...duplicate,generated_destinations:{runs:[]}}));
 const fragmented={recovery_regions:Array.from({length:4097},(_,i)=>({archive_path:[0,0],archive_offset:i,count:1,destination:{runs:[{item:{client:4,clock:i*2},type:{client:4,clock:1},count:1}]}})),human_destinations:{runs:[]},generated_destinations:{runs:[]}};
 assert.throws(()=>partition(fragmented),{code:'source_identity_limit'});
 const oversized={...fragmented,recovery_regions:[{archive_path:[0],archive_offset:0,count:131073,destination:{runs:[{item:{client:4,clock:2},type:{client:4,clock:1},count:131073}]}}]};
 assert.throws(()=>partition(oversized),{code:'source_identity_limit'});
});

function retainedEvidence(evidence=actualEvidence()){
 const original=ContentEdit.prepareReviewedRecoveryWitness(evidence);
 const result=Object.fromEntries(['sender_before_snapshot','sender_after_snapshot','before_snapshot','after_snapshot','before_state_vector','operation','footprint'].map(key=>[key,evidence[key]]));
 result.regional_context={recovery_regions:original.recovery_regions,human_destinations:{runs:[]}};
 return result;
}
test('accepted native reviewed append replays target-only regional evidence without rereading donor bytes',()=>{
 const evidence=retainedEvidence(),original=JSON.stringify(evidence),proof=ContentEdit.prepareRetainedReviewedRecoveryWitness(evidence);
 assert.equal(proof.complete_recovery_correspondence,true);
 assert.equal(proof.requires_recovery_authorization,true);
 assert.equal(proof.requires_mutation_correspondence,true);
 assert.deepEqual(proof.text_items,{runs:[]});assert.deepEqual(proof.proven_copies,[]);
 assert.equal(extent(proof.fresh_items.runs),18);
 assert.deepEqual(proof.recovery_regions,evidence.regional_context.recovery_regions);
 assert.equal(JSON.stringify(evidence),original);
 assert.equal(ContentEdit.replayContentEditMutation({sender_state_base64:fixture.target_before_base64,current_state_base64:fixture.target_before_base64,writer_client:proof.fresh_items.runs[0].item.client,operation:evidence.operation,footprint:evidence.footprint}).complete_mutation_correspondence,true);
});
test('accepted rich append retains original allocator Steps and unseen target peer while human authority stays private',()=>{
 const {evidence,mutation}=duplicateEvidence({repairIDs:true,markupRepairs:true}),retained=retainedEvidence(evidence);
 const human=retained.regional_context.recovery_regions[0].destination;
 retained.regional_context.human_destinations=structuredClone(human);
 const proof=ContentEdit.prepareRetainedReviewedRecoveryWitness(retained);
 assert.deepEqual(proof.text_items,{runs:[]});assert.deepEqual(proof.proven_copies,[]);
 assert.deepEqual(proof.recovery_regions,retained.regional_context.recovery_regions);
 assert.deepEqual(proof.authored_document.frontmatter,{title:'Current title'});
 assert.equal(ContentEdit.replayContentEditMutation(mutation).complete_mutation_correspondence,true);
});
test('accepted regional replay refuses missing coverage, old/forged typed IDs, overlaps and modified append geometry',()=>{
 for(const mutate of [
  e=>{delete e.regional_context;},
  e=>{e.regional_context.recovery_regions.pop();},
  e=>{e.regional_context.recovery_regions[0].count++;},
  e=>{e.regional_context.recovery_regions.push(structuredClone(e.regional_context.recovery_regions[0]));},
  e=>{e.regional_context.recovery_regions[0].destination.runs[0].type.clock++;},
  e=>{e.regional_context.recovery_regions[0].archive_path[0]=99;},
  e=>{e.regional_context.recovery_regions[0].archive_offset=-1;},
  e=>{const n=e.before_snapshot.children[0].children[0],r=n.runs[0];e.regional_context.human_destinations={runs:[{type:n.type,item:r.item,count:r.count}]};},
  e=>{const r=e.regional_context.recovery_regions[0].destination.runs[0];e.regional_context.human_destinations={runs:[{...r,type:{...r.type,clock:r.type.clock+1}}]};},
  e=>{e.operation.steps[0].from--;e.operation.steps[0].to--;},
  e=>{e.operation.steps.push({stepType:'docAttr',attr:'relaymark',value:{}});},
  e=>{e.operation.reviewed_recovery.block_indices=[1];},
  e=>{e.regional_context.complete_recovery_correspondence=true;},
  e=>{e.regional_context.recovery_regions=Array.from({length:4097},()=>structuredClone(e.regional_context.recovery_regions[0]));},
  e=>{const r=e.regional_context.recovery_regions[0].destination.runs[0];e.regional_context.human_destinations={runs:[r,structuredClone(r)]};},
 ]){const e=retainedEvidence();mutate(e);assert.throws(()=>ContentEdit.prepareRetainedReviewedRecoveryWitness(e));}
});
test('accepted reviewed replay refuses hidden transient allocations despite complete issued visible regions',()=>{
 const evidence=retainedEvidence(),doc=new Y.Doc({gc:false});Y.applyUpdate(doc,decode(fixture.target_before_base64));Y.applyUpdate(doc,decode(fixture.update_base64));
 const updates=[decode(fixture.update_base64)];doc.on('update',u=>updates.push(u));
 doc.transact(()=>{const text=doc.getXmlFragment('default').get(0).get(0);text.insert(0,'Hidden');text.delete(0,6);});
 evidence.after_snapshot=captureContentEditSnapshot(doc.getXmlFragment('default'));evidence.footprint=captureContentEditFootprint(doc,Y.mergeUpdates(updates));
 assert.throws(()=>ContentEdit.prepareRetainedReviewedRecoveryWitness(evidence),/Hidden or unprovable string mutation/);doc.destroy();
});
