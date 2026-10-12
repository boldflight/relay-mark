import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import * as Runtime from '../adapters/collaboration/content-edit-mutation.js';
import * as Y from 'yjs';
import {Transform} from 'prosemirror-transform';
import {initProseMirrorDoc,updateYFragment,prosemirrorToYXmlFragment} from './helpers/canonical-binding.js';
import {createCanonicalEditorSchema} from '../src/editor-model.js';
import {createContentEditWrite,buildContentEditWitness} from '../src/content-edit.js';
import {bindOwnedHistoryOwner,bindOwnedCommandGroup,readOwnedCommandGroup} from '../adapters/collaboration/owned-command-group.js';
import {protectOwnedHistoryBranches} from '../adapters/collaboration/owned-history-branches.js';
import {captureContentEditFootprint,captureContentEditSnapshot} from '../adapters/collaboration/content-edit-observer.js';
const schema=createCanonicalEditorSchema(),enc=b=>Buffer.from(b).toString('base64'),id=n=>'b'+String(n).padStart(12,'0')+'40008'+'0'.repeat(15);
const paragraph=(n,text)=>schema.node('paragraph',{relaymarkId:id(n)},schema.text(text));
const docJSON=e=>initProseMirrorDoc(e.root,schema).doc.toJSON();
function environment(client,ownerID,seed){const doc=new Y.Doc({gc:false});doc.clientID=client;Y.applyUpdate(doc,seed);const root=doc.getXmlFragment('default'),origin={},manager=new Y.UndoManager([root,doc.getMap('relaymark')],{trackedOrigins:new Set([origin]),captureTimeout:Infinity});protectOwnedHistoryBranches(manager);bindOwnedHistoryOwner(manager,ownerID);let active;for(const event of ['stack-item-added','stack-item-updated'])manager.on(event,e=>{if(!manager.undoing&&!manager.redoing)bindOwnedCommandGroup(manager,e,active)});return{doc,root,origin,manager,setActive:id=>active=id,destroy(){manager.destroy();doc.destroy()}};}
function command(e,uuid,plan,newGroup=true){const state=Y.encodeStateAsUpdate(e.doc),snapshot=captureContentEditSnapshot(e.root),clocks=captureContentEditFootprint(e.doc,Uint8Array.of(0,0)).state_vector,before=initProseMirrorDoc(e.root,schema),tr=new Transform(before.doc);plan(tr);const updates=[],capture=u=>updates.push(u);e.doc.on('update',capture);e.setActive(uuid);if(newGroup)e.manager.stopCapturing();try{e.doc.transact(()=>{before.meta.contentEditWrite=createContentEditWrite(before.doc,tr.steps.map(s=>s.toJSON()),tr.doc);updateYFragment(e.doc,e.root,tr.doc,before.meta)},e.origin)}finally{e.doc.off('update',capture)}assert.equal(updates.length,1);const update=updates[0],after=captureContentEditSnapshot(e.root),footprint=captureContentEditFootprint(e.doc,update),operation={kind:'content_edit',steps:tr.steps.map(s=>s.toJSON()),group:readOwnedCommandGroup(e.manager,uuid)};const proof=buildContentEditWitness({sender_before_snapshot:snapshot,sender_after_snapshot:after,before_snapshot:snapshot,after_snapshot:after,before_state_vector:clocks,operation,footprint});operation.copies=proof.proven_copies;return{transaction_id:uuid,operation,text_items:proof.text_items,sender_state_base64:enc(state),update_base64:enc(update),footprint};}
function effect(e,kind){const before=enc(Y.encodeStateAsUpdate(e.doc)),updates=[],capture=u=>updates.push(u);e.doc.on('update',capture);try{assert.ok(e.manager[kind]())}finally{e.doc.off('update',capture)}assert.equal(updates.length,1);return{kind,before_state_base64:before,update_base64:enc(updates[0]),after_state_base64:enc(Y.encodeStateAsUpdate(e.doc)),document:docJSON(e),footprint:captureContentEditFootprint(e.doc,updates[0])};}
function scenario(kind,peerOwner='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'){const seed=new Y.Doc({gc:false});seed.clientID=11;prosemirrorToYXmlFragment(schema.node('doc',null,[paragraph(1,'Base')]),seed.getXmlFragment('default'));const baseline=Y.encodeStateAsUpdate(seed);seed.destroy();const a=environment(101,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',baseline),b=environment(303,peerOwner,baseline);
try{const imported=command(a,'11111111-1111-4111-8111-111111111111',tr=>tr.insert(tr.doc.content.size,(kind==='field-resurrection'||kind==='copied-field-resurrection')?schema.node('questionBlock',{relaymarkId:id(2),id:'protected-question',type:'short_text',required:false},schema.node('questionLabel',{relaymarkId:id(3)},schema.text('Protected 🌍 question',[schema.mark('bold')]))):kind==='format-resurrection'?schema.node('paragraph',{relaymarkId:id(2)},schema.text('Protected 🌍',[schema.mark('bold')])):paragraph(2,'Protected 🌍')));Y.applyUpdate(b.doc,Buffer.from(imported.update_base64,'base64'));const rootID=a.root.get(1)._item.id;
if(kind==='copied-field-resurrection'){const copy=command(b,'77777777-7777-4777-8777-777777777777',tr=>{const end=tr.doc.content.size;tr.insert(end,tr.doc.child(1));tr.setNodeAttribute(end,'relaymarkId',id(4));tr.setNodeAttribute(end+1,'relaymarkId',id(5))});assert.deepEqual(copy.text_items,{runs:[]});assert.ok(copy.operation.copies.length);const beforePeer=Y.encodeStateAsUpdate(b.doc),c=environment(909,'cccccccc-cccc-4ccc-8ccc-cccccccccccc',beforePeer);try{const edit=command(c,'88888888-8888-4888-8888-888888888888',tr=>tr.setNodeAttribute(tr.doc.child(0).nodeSize+tr.doc.child(1).nodeSize,'required',true));assert.equal(c.root.get(2).getAttribute('required'),true);const undo=effect(c,'undo');assert.equal(c.root.get(2).getAttribute('required'),false);const redo=effect(c,'redo');assert.equal(c.root.get(2).getAttribute('required'),true);const beforeType=b.root.get(2)._item.id;assert.ok(edit.footprint.deleted_items.some(item=>item.parent.type.client===beforeType.client&&item.parent.type.clock===beforeType.clock&&item.key==='required'));assert.equal(edit.footprint.deleted_items.some(item=>item.item.client===101),false);return{baseline_state_base64:enc(baseline),imported,peer_copy:copy,peer_command:edit,effects:[undo,redo]};}finally{c.destroy()}}
if(kind==='mixed-parent'){const first=command(b,'45454545-4545-4545-8545-454545454545',tr=>tr.delete(tr.doc.child(0).nodeSize+1,tr.doc.child(0).nodeSize+2));const suffix=command(b,'56565656-5656-4656-8656-565656565656',tr=>tr.insert(1,schema.text('Independent Ω ')),false);assert.deepEqual(suffix.operation.group.operation_ids,[first.transaction_id,suffix.transaction_id]);return{baseline_state_base64:enc(baseline),imported,peer_command:first,peer_suffix:suffix};}
if(kind==='field-resurrection'){const update=command(b,'44444444-4444-4444-8444-444444444444',tr=>tr.setNodeAttribute(tr.doc.child(0).nodeSize,'required',true));assert.equal(b.root.get(1).getAttribute('required'),true);const undo=effect(b,'undo');assert.equal(b.root.get(1).getAttribute('required'),false);const redo=effect(b,'redo');assert.equal(b.root.get(1).getAttribute('required'),true);assert.ok(update.footprint.deleted_items.some(item=>item.parent.type.client===rootID.client&&item.parent.type.clock===rootID.clock&&item.key==='required'));return{baseline_state_base64:enc(baseline),imported,peer_command:update,effects:[undo,redo]};}
if(kind==='format-resurrection'){const update=command(b,'55555555-5555-4555-8555-555555555555',tr=>tr.removeMark(tr.doc.child(0).nodeSize+1,tr.doc.content.size-1,schema.marks.bold));assert.deepEqual(b.root.get(1).get(0).toDelta(),[{insert:'Protected 🌍'}]);const undo=effect(b,'undo');assert.deepEqual(JSON.parse(JSON.stringify(b.root.get(1).get(0).toDelta())),[{insert:'Protected 🌍',attributes:{bold:{}}}]);const redo=effect(b,'redo');assert.ok(update.footprint.deleted_items.some(item=>item.content.kind==='format'&&item.content.key==='bold'));return{baseline_state_base64:enc(baseline),imported,peer_command:update,effects:[undo,redo]};}
if(kind==='independent-parent'){const update=command(b,'66666666-6666-4666-8666-666666666666',tr=>tr.insert(tr.doc.child(0).nodeSize+1,schema.text('Independent Ω ')));const textAllocation=update.footprint.structs.find(item=>item.content.kind==='string');assert.equal(textAllocation.parent.type.client,101);Y.applyUpdate(a.doc,Buffer.from(update.update_base64,'base64'));const removeImport=effect(a,'undo');assert.equal(a.root.get(1).get(0).toString(),'Independent Ω ');Y.applyUpdate(b.doc,Buffer.from(removeImport.update_base64,'base64'));const undo=effect(b,'undo');assert.equal(b.root.get(1).get(0).toString(),'');const redo=effect(b,'redo');assert.equal(b.root.get(1).get(0).toString(),'Independent Ω ');assert.equal(b.root.toString().includes('Protected'),false);return{baseline_state_base64:enc(baseline),imported,peer_command:update,import_owner_undo:removeImport,effects:[undo,redo]};}
if(kind==='delete-resurrection'){const removal=command(b,'22222222-2222-4222-8222-222222222222',tr=>tr.delete(tr.doc.child(0).nodeSize,tr.doc.content.size));assert.equal(b.root.length,1);const undo=effect(b,'undo');assert.equal(b.root.get(1).get(0).toString(),'Protected 🌍');const redo=effect(b,'redo');assert.equal(b.root.length,1);return{baseline_state_base64:enc(baseline),imported_root:{client:rootID.client,clock:rootID.clock},imported,peer_command:removal,effects:[undo,redo]};}
const adjacent=command(b,'33333333-3333-4333-8333-333333333333',tr=>tr.insert(tr.doc.content.size,paragraph(3,'Independent Ω')));const rootAllocation=adjacent.footprint.structs.find(r=>r.content.kind==='type'&&r.content.type_kind==='xml_element');assert.deepEqual(rootAllocation.origin,{client:rootID.client,clock:rootID.clock});Y.applyUpdate(a.doc,Buffer.from(adjacent.update_base64,'base64'));const removeImport=effect(a,'undo');assert.equal(a.root.length,2);Y.applyUpdate(b.doc,Buffer.from(removeImport.update_base64,'base64'));const undo=effect(b,'undo');assert.equal(b.root.length,1);const redo=effect(b,'redo');assert.equal(b.root.length,2);assert.equal(b.root.get(1).get(0).toString(),'Independent Ω');assert.equal(b.root.toString().includes('Protected'),false);return{baseline_state_base64:enc(baseline),imported_root:{client:rootID.client,clock:rootID.clock},imported,peer_command:adjacent,import_owner_undo:removeImport,effects:[undo,redo]};
}finally{a.destroy();b.destroy()}}

function plannerInput(f){
 const receipts=[f.imported,...(f.peer_copy?[f.peer_copy]:[]),f.peer_command,...(f.peer_suffix?[f.peer_suffix]:[])];
 const scopes=[['actor-a',f.imported.operation.group.owner_id],['actor-b',(f.peer_copy??f.peer_command).operation.group.owner_id],...(f.peer_copy?[['actor-c',f.peer_command.operation.group.owner_id]]:[])];
 const actorByCommand=new Map([[f.imported.transaction_id,'actor-a'],[f.peer_command.transaction_id,f.peer_copy?'actor-c':'actor-b'],...(f.peer_copy?[[f.peer_copy.transaction_id,'actor-b']]:[]),...(f.peer_suffix?[[f.peer_suffix.transaction_id,'actor-b']]:[])]);
 const current=new Y.Doc({gc:false});Y.applyUpdate(current,Buffer.from(f.baseline_state_base64,'base64'));for(const receipt of receipts)Y.applyUpdate(current,Buffer.from(receipt.update_base64,'base64'));
 const state=enc(Y.encodeStateAsUpdate(current));current.destroy();
 const exact=receipt=>Object.fromEntries(['transaction_id','operation','sender_state_base64','update_base64'].map(key=>[key,receipt[key]]));
 const digest=value=>createHash('sha256').update(value).digest('hex');
 const association=receipt=>({transaction_id:receipt.transaction_id,transaction_sha256:digest(JSON.stringify(exact(receipt))),update_sha256:digest(Buffer.from(receipt.update_base64,'base64')),issued_reference_sha256:digest(JSON.stringify({issued_for:receipt.transaction_id})),actor_id:actorByCommand.get(receipt.transaction_id),owner_id:receipt.operation.group.owner_id});
 return {binding:{document_id:'22222222-2222-4222-8222-222222222222',incarnation:'33333333-3333-4333-8333-333333333333'},current_state_base64:state,current_cut:{through_update_id:receipts.length,state_sha256:digest(Buffer.from(state,'base64'))},
  imports:[{receipt:association(f.imported),imported_items:f.imported.footprint.structs.map(({item,count})=>({item,count}))}],
  expected_manager_scopes:scopes.map(([actor_id,owner_id])=>({actor_id,owner_id})),
  manager_contexts:scopes.map(([actor_id,owner_id])=>({actor_id,owner_id,initial_state_base64:f.baseline_state_base64,receipts:receipts.filter(r=>actorByCommand.get(r.transaction_id)===actor_id).map(exact)}))};
}
test('actual foreign text/property/format deletion groups retire, independent adjacent and shared-parent typing survives',()=>{
 for(const [kind,dependent]of [['delete-resurrection',true],['field-resurrection',true],['format-resurrection',true],['adjacent',false],['independent-parent',false]]){
  const f=scenario(kind),input=plannerInput(f),result=Runtime.planReviewedRecoveryRetirement(input);
  assert.equal(result.associations[0].source_dependencies.runs.some(run=>f.peer_command.text_items.runs.some(typed=>typed.item.client===run.item.client&&typed.item.clock<run.item.clock+run.count&&run.item.clock<typed.item.clock+typed.count)),false,'independent typed facts stay outside imported source closure');
  const selected=result.associations[0].retirements.flatMap(scope=>scope.groups.map(group=>group.reference));
  assert.ok(selected.includes(f.imported.transaction_id));assert.equal(selected.includes(f.peer_command.transaction_id),dependent,kind);
  assert.equal(result.complete_dependency_correspondence,true);assert.deepEqual(result.binding,input.binding);
 }
});
test('exact copied subtree field allocation protects a later third-manager property resurrection',()=>{
 const f=scenario('copied-field-resurrection'),result=Runtime.planReviewedRecoveryRetirement(plannerInput(f));
 assert.deepEqual(result.associations[0].retirements.flatMap(scope=>scope.groups.map(group=>group.reference)),[f.imported.transaction_id,f.peer_copy.transaction_id,f.peer_command.transaction_id]);
 assert.ok(result.dependency_edges.some(edge=>edge.kind==='copied_field'&&edge.source.client===101&&edge.destination.client===303));
 assert.ok(result.dependency_edges.some(edge=>edge.kind==='copied_format'&&edge.source.client===101&&edge.destination.client===303));
 assert.equal(f.peer_command.footprint.deleted_items.some(item=>item.item.client===101),false);
});
test('retirement planning rejects missing actor-owner roster, wrong imported ranges and altered original receipts',()=>{
 const input=plannerInput(scenario('delete-resurrection'));
 for(const change of [value=>value.manager_contexts.pop(),value=>value.expected_manager_scopes.pop(),value=>{value.manager_contexts[1].actor_id='actor-a'},value=>{value.imports[0].imported_items[0].count+=100000},value=>{value.imports[0].imported_items=[{item:{client:11,clock:0},count:1}]},value=>{value.manager_contexts[1].receipts[0].operation.steps[0].from=0},value=>{value.manager_contexts[0].checkpoint={}},value=>value.manager_contexts[0].receipts.push(value.manager_contexts[0].receipts[0])]){
  const altered=structuredClone(input);change(altered);assert.throws(()=>Runtime.planReviewedRecoveryRetirement(altered));
 }
});

function managerCut(input){return input.manager_contexts.map(context=>{const {actor_id,...basis}=context;return{actor_id,owner_id:context.owner_id,checkpoint:Runtime.createOwnedHistoryCheckpoint({...basis,current_state_base64:input.current_state_base64}),receipts:[]};});}
test('two real cold cuts retain copied field resurrection dependencies and independent suffix typing',()=>{
 const input=plannerInput(scenario('copied-field-resurrection')),original=Runtime.planReviewedRecoveryRetirement(input);
 const first={...input,imports:[],dependency_checkpoint:original.dependency_checkpoint,checkpoint_state_base64:input.current_state_base64,manager_contexts:managerCut(input)};
 const cold=Runtime.planReviewedRecoveryRetirement(first);assert.deepEqual(cold.associations,original.associations);
 const ownerID=first.manager_contexts[1].owner_id,writer=environment(707,ownerID,Buffer.from(first.current_state_base64,'base64'));
 try{
  Runtime.installMaintainedHistoryCheckpoint(writer.doc,writer.manager,first.manager_contexts[1].checkpoint,ownerID);
  const independent=command(writer,'99999999-9999-4999-8999-999999999999',tr=>tr.insert(1,schema.text('Independent Ω ')));
  const state=enc(Y.encodeStateAsUpdate(writer.doc)),next={...first,current_state_base64:state,current_cut:{through_update_id:first.current_cut.through_update_id+1,state_sha256:createHash('sha256').update(Buffer.from(state,'base64')).digest('hex')}};
  next.manager_contexts=structuredClone(first.manager_contexts);next.manager_contexts[1].receipts=[Object.fromEntries(['transaction_id','operation','sender_state_base64','update_base64'].map(key=>[key,independent[key]]))];
  const second=Runtime.planReviewedRecoveryRetirement(next);assert.deepEqual(second.associations[0].retirements,original.associations[0].retirements);
  assert.equal(second.associations[0].source_dependencies.runs.some(run=>independent.text_items.runs.some(typed=>typed.item.client===run.item.client&&typed.item.clock<run.item.clock+run.count&&run.item.clock<typed.item.clock+typed.count)),false);
  const third={...next,imports:[],dependency_checkpoint:second.dependency_checkpoint,checkpoint_state_base64:state,manager_contexts:managerCut(next)};
  assert.deepEqual(Runtime.planReviewedRecoveryRetirement(third).associations,second.associations);
 }finally{writer.destroy()}
});
test('separate imported allocation associations survive repeated cuts without joining unrelated source masks',()=>{
 const f=scenario('adjacent'),input=plannerInput(f),receipt={...input.imports[0].receipt,transaction_id:f.peer_command.transaction_id,actor_id:'actor-b',owner_id:f.peer_command.operation.group.owner_id,update_sha256:createHash('sha256').update(Buffer.from(f.peer_command.update_base64,'base64')).digest('hex')};
 input.imports.push({receipt,imported_items:f.peer_command.footprint.structs.map(({item,count})=>({item,count}))});
 const original=Runtime.planReviewedRecoveryRetirement(input);
 assert.deepEqual(original.associations[0].retirements.flatMap(scope=>scope.groups.map(group=>group.reference)),[f.imported.transaction_id]);
 assert.deepEqual(original.associations[1].retirements.flatMap(scope=>scope.groups.map(group=>group.reference)),[f.peer_command.transaction_id]);
 assert.equal(original.associations[0].source_dependencies.runs.some(run=>run.item.client===303),false);assert.equal(original.associations[1].source_dependencies.runs.some(run=>run.item.client===101),false);
 const cold={...input,imports:[],dependency_checkpoint:original.dependency_checkpoint,checkpoint_state_base64:input.current_state_base64,manager_contexts:managerCut(input)};
 assert.deepEqual(Runtime.planReviewedRecoveryRetirement(cold).associations,original.associations);
});
test('missing or tampered cold summary refuses cut, roster, association, type and aggregate budgets',()=>{
 const input=plannerInput(scenario('copied-field-resurrection')),proof=Runtime.planReviewedRecoveryRetirement(input),cold={...input,imports:[],dependency_checkpoint:proof.dependency_checkpoint,checkpoint_state_base64:input.current_state_base64,manager_contexts:managerCut(input)};
 for(const change of [
  value=>{delete value.dependency_checkpoint;delete value.checkpoint_state_base64;},
  value=>{value.dependency_checkpoint.state_sha256='0'.repeat(64);},
  value=>{value.dependency_checkpoint.through_update_id++;},
  value=>value.dependency_checkpoint.manager_scopes.pop(),
  value=>{value.dependency_checkpoint.associations[0].receipt.actor_id='foreign-actor';},
  value=>{value.dependency_checkpoint.associations[0].source_items.runs[0].type.clock++;},
  value=>{value.dependency_checkpoint.associations[0].capability_items=[];},
  value=>{value.dependency_checkpoint.associations[0].imported_items[0].count+=100000;},
  value=>value.dependency_checkpoint.associations.push(value.dependency_checkpoint.associations[0]),
  value=>{value.current_cut.state_sha256='f'.repeat(64);}
 ]){const altered=structuredClone(cold);change(altered);assert.throws(()=>Runtime.planReviewedRecoveryRetirement(altered));}
 const tooLarge=structuredClone(cold);tooLarge.dependency_checkpoint.associations[0].receipt.transaction_sha256='a'.repeat(33_554_433);assert.throws(()=>Runtime.planReviewedRecoveryRetirement(tooLarge),/byte resource limit/);
});

test('planned A retirement leaves exact current state and unrelated B cold undo-redo/new command working',()=>{
 const f=scenario('adjacent'),input=plannerInput(f),proof=Runtime.planReviewedRecoveryRetirement(input),contexts=managerCut(input),selected=proof.associations[0].retirements[0];
 const {actor_id,...basis}=contexts[0];const retired=Runtime.retireOwnedHistoryCheckpoint({...basis,current_state_base64:input.current_state_base64,groups:selected.groups});
 const a=environment(707,contexts[0].owner_id,Buffer.from(input.current_state_base64,'base64'));
 const b=environment(808,contexts[1].owner_id,Buffer.from(input.current_state_base64,'base64'));
 try{
  Runtime.installMaintainedHistoryCheckpoint(a.doc,a.manager,retired.checkpoint,contexts[0].owner_id);
  assert.equal(a.manager.undo(),null,'retired imported group cannot pop');assert.equal(enc(Y.encodeStateAsUpdate(a.doc)),input.current_state_base64);
  Runtime.installMaintainedHistoryCheckpoint(b.doc,b.manager,contexts[1].checkpoint,contexts[1].owner_id);
  const original=docJSON(b);effect(b,'undo');assert.equal(b.root.length,2);assert.equal(b.root.get(1).get(0).toString(),'Protected 🌍');
  effect(b,'redo');assert.deepEqual(docJSON(b),original);
  const independent=command(a,'abababab-abab-4bab-8bab-abababababab',tr=>tr.insert(1,schema.text('New Ω ')));
  assert.equal(independent.text_items.runs.reduce((count,run)=>count+run.count,0),6);
  effect(a,'undo');assert.equal(a.root.get(0).get(0).toString(),'Base');effect(a,'redo');assert.equal(a.root.get(0).get(0).toString(),'New Ω Base');
 }finally{a.destroy();b.destroy()}
});

test('whole mixed-group retirement never masks its independently typed human item facts',()=>{
 const f=scenario('mixed-parent'),input=plannerInput(f),proof=Runtime.planReviewedRecoveryRetirement(input);
 const peer=proof.associations[0].retirements.find(manager=>manager.owner_id===f.peer_command.operation.group.owner_id);
 assert.deepEqual(peer.groups,[f.peer_suffix.operation.group]);
 const human=f.peer_suffix.text_items.runs;assert.equal(human.reduce((n,run)=>n+run.count,0),14);
 assert.equal(proof.associations[0].source_dependencies.runs.some(run=>human.some(typed=>typed.item.client===run.item.client&&typed.item.clock<run.item.clock+run.count&&run.item.clock<typed.item.clock+typed.count)),false);
 const cold={...input,imports:[],dependency_checkpoint:proof.dependency_checkpoint,checkpoint_state_base64:input.current_state_base64,manager_contexts:managerCut(input)};
 assert.deepEqual(Runtime.planReviewedRecoveryRetirement(cold).associations,proof.associations);
});


test('shipped headless planner preserves the same complete cut and cold association summary',()=>{
 const input=plannerInput(scenario('copied-field-resurrection'));
 const global={btoa:value=>Buffer.from(value,'binary').toString('base64'),atob:value=>Buffer.from(value,'base64').toString('binary')};
 runInNewContext(readFileSync(new URL('../adapters/elixir/priv/collaboration/content-edit-runtime.js',import.meta.url),'utf8'),global);
 const invoke=value=>{global.inputJSON=JSON.stringify(value);return JSON.parse(runInNewContext('JSON.stringify(RelayMarkContentEditRuntime.planReviewedRecoveryRetirement(JSON.parse(inputJSON)))',global));};
 const actual=invoke(input);assert.deepEqual(actual,Runtime.planReviewedRecoveryRetirement(input));
 const cold={...input,imports:[],dependency_checkpoint:actual.dependency_checkpoint,checkpoint_state_base64:input.current_state_base64,manager_contexts:managerCut(input)};
 assert.deepEqual(invoke(cold).associations,actual.associations);
 const forged=structuredClone(cold);forged.dependency_checkpoint.associations[0].receipt.actor_id='other-account';assert.throws(()=>invoke(forged));
});


test('identical owner UUIDs under different authenticated actors remain distinct managers through cold cuts',()=>{
 const f=scenario('adjacent','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),input=plannerInput(f),original=Runtime.planReviewedRecoveryRetirement(input);
 assert.deepEqual(original.associations[0].retirements.map(manager=>manager.actor_id),['actor-a']);
 assert.equal(input.expected_manager_scopes[0].owner_id,input.expected_manager_scopes[1].owner_id);
 const cold={...input,imports:[],dependency_checkpoint:original.dependency_checkpoint,checkpoint_state_base64:input.current_state_base64,manager_contexts:managerCut(input)};
 assert.deepEqual(Runtime.planReviewedRecoveryRetirement(cold).associations,original.associations);
 const wrong=structuredClone(cold);wrong.manager_contexts[1].actor_id='actor-a';assert.throws(()=>Runtime.planReviewedRecoveryRetirement(wrong));
});
