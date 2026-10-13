import test from 'node:test';import assert from 'node:assert/strict';
import * as Y from 'yjs';
import {parseDocument,documentToSnapshot} from '../src/document-source.js';
import {node} from '../adapters/collaboration/prose-operation.js';

test('real rich Enter proves relocated suffix by maintained maps and refuses hidden omitted text',async()=>{
 const {captureContentEditSnapshot,captureContentEditFootprint}=await import('../adapters/collaboration/content-edit-observer.js');
 const {prepareContentEditWitness}=await import('../src/content-edit.js');
 const doc=new Y.Doc({gc:false,clientID:7});doc.clientID=7;
 const root=doc.getXmlFragment('default');doc.getMap('relaymark');
 const ast=parseDocument('Hello world',{namespace:'browser-witness'});root.insert(0,documentToSnapshot(ast).children.map(node));
 const before=captureContentEditSnapshot(root),vector=Y.encodeStateVector(doc),beforeFootprint=captureContentEditFootprint(doc,new Uint8Array([0,0]));
 const old=root.get(0),text=old.get(0),nextID='b00000000000040008000000000000031';
 const source={runs:[{type:{client:7,clock:1},item:{client:7,clock:8},count:5}]};
 doc.transact(()=>{text.delete(6,5);const paragraph=new Y.XmlElement('paragraph');paragraph.setAttribute('relaymarkId',nextID);const suffix=new Y.XmlText();suffix.insert(0,'world');paragraph.insert(0,[suffix]);root.insert(1,[paragraph]);});
 const after=captureContentEditSnapshot(root),update=Y.encodeStateAsUpdate(doc,vector),footprint=captureContentEditFootprint(doc,update);
 const destination={runs:[{type:{client:7,clock:15},item:{client:7,clock:16},count:5}]};
 const operation={kind:'content_edit',steps:[
  {stepType:'replace',from:7,to:7,slice:{content:[{type:'paragraph',attrs:{relaymarkId:ast.blocks[0].id}},{type:'paragraph',attrs:{relaymarkId:ast.blocks[0].id}}],openStart:1,openEnd:1}},
  {stepType:'attr',pos:8,attr:'relaymarkId',value:nextID}
 ],copies:[{source,destination}]};
 const evidence={sender_before_snapshot:before,sender_after_snapshot:after,before_snapshot:before,after_snapshot:after,before_state_vector:beforeFootprint.state_vector,operation,text_items:{runs:[]},footprint};
 const result=prepareContentEditWitness(evidence);
 assert.equal(result.requires_mutation_correspondence,true);assert.ok(result.unproven_mutations.structs.length>0);
 assert.throws(()=>captureContentEditFootprint(doc,new Uint8Array([...update,0])));
 if(process.env.RELAYMARK_WRITE_WITNESS_FIXTURE){const {writeFileSync}=await import('node:fs');writeFileSync('spec/relaymark/collaboration/fixtures/content-edit-enter-witness.json',JSON.stringify({evidence,expected:{proven_copies:[{source,destination}],fresh_items:destination,text_items:{runs:[]},requires_mutation_correspondence:true}},null,2)+'\n');}
 assert.deepEqual(result.proven_copies,[{source,destination}]);assert.deepEqual(result.fresh_items,destination);
 assert.deepEqual(result.text_items,{runs:[]});
 assert.throws(()=>prepareContentEditWitness({...evidence,footprint:undefined}));
 assert.throws(()=>prepareContentEditWitness({...evidence,operation:{...operation,copies:[]}}));
 const forged=structuredClone(evidence);forged.operation.copies[0].source.runs[0].type.clock=0;
 assert.throws(()=>prepareContentEditWitness(forged));
 const badBefore=Y.encodeStateVector(doc);doc.transact(()=>{root.get(1).get(0).insert(0,'hidden');root.get(1).get(0).delete(0,6);});
 const hidden=captureContentEditFootprint(doc,Y.encodeStateAsUpdate(doc,badBefore));
 assert.throws(()=>prepareContentEditWitness({...evidence,footprint:{...footprint,structs:[...footprint.structs,...hidden.structs],deleted_items:[...footprint.deleted_items,...hidden.deleted_items],declared_deletes:[...footprint.declared_deletes,...hidden.declared_deletes]}}));
});

test('actual maintained Enter derives generated suffix copy IDs without a client claim',async()=>{
 const {readFileSync}=await import('node:fs'),{buildContentEditWitness}=await import('../src/content-edit.js');
 const {evidence,expected}=JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-enter-witness.json',import.meta.url)));
 const {text_items,...input}=evidence;input.operation={kind:'content_edit',steps:input.operation.steps};
 const result=buildContentEditWitness(input);assert.deepEqual(result.operation.copies,expected.proven_copies);assert.deepEqual(result.text_items,{runs:[]});
 const falseSource=structuredClone(input);falseSource.sender_before_snapshot.children[0].children[0].runs[0].attributes={bold:{}};
 assert.throws(()=>buildContentEditWitness(falseSource));
});

test('one retained rich source can be duplicated twice only onto exact fresh Slice allocations',async()=>{
 const {captureContentEditSnapshot,captureContentEditFootprint}=await import('../adapters/collaboration/content-edit-observer.js'),{prepareContentEditWitness}=await import('../src/content-edit.js');
 const {prosemirrorToYXmlFragment,initProseMirrorDoc,updateYFragment}=await import('./helpers/canonical-binding.js'),{Step}=await import('prosemirror-transform'),{createContentEditWrite,createCanonicalEditorSchema,replayContentEditMutation}=await import('../src/content-edit.js'),{relayMarkToProseMirror}=await import('../src/document-adapter.js');const schema=createCanonicalEditorSchema();
 const doc=new Y.Doc({gc:false});doc.clientID=71;const root=doc.getXmlFragment('default'),ast=parseDocument('Hello **world**',{namespace:'duplicate-slice'});prosemirrorToYXmlFragment(schema.nodeFromJSON(relayMarkToProseMirror(ast)),root);const initial=Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64');
 const before=captureContentEditSnapshot(root),vector=Y.encodeStateVector(doc),clocks=captureContentEditFootprint(doc,new Uint8Array([0,0])).state_vector,original=before.children[0].children[0].runs.find(run=>run.text==='world'),type=before.children[0].children[0].type;
 const steps=[{stepType:'replace',from:12,to:12,slice:{content:[{type:'text',text:'worldworld',marks:[{type:'bold'}]}]}}],initialized=initProseMirrorDoc(root,schema),target=Step.fromJSON(schema,steps[0]).apply(initialized.doc).doc;initialized.meta.contentEditWrite=createContentEditWrite(initialized.doc,steps,target);
 const updates=[];doc.on('update',u=>updates.push(u));updateYFragment(doc,root,target,initialized.meta);assert.equal(updates.length,1);const after=captureContentEditSnapshot(root),footprint=captureContentEditFootprint(doc,updates[0]),fresh=after.children[0].children[0].runs.find(run=>run.item.clock>=clocks[0].clock);
 const source={runs:[{type:{...type},item:{...original.item},count:5}]},destination=offset=>({runs:[{type:{...type},item:{client:fresh.item.client,clock:fresh.item.clock+offset},count:5}]}),copies=[{source,destination:destination(0)},{source,destination:destination(5)}];
 const operation={kind:'content_edit',steps,copies},evidence={sender_before_snapshot:before,sender_after_snapshot:after,before_snapshot:before,after_snapshot:after,before_state_vector:clocks,operation,text_items:{runs:[]},footprint};
 if(process.env.RELAYMARK_WRITE_DUPLICATE_FIXTURE){const {writeFileSync}=await import('node:fs');writeFileSync('spec/relaymark/collaboration/fixtures/content-edit-duplicated-slice-causal.json',JSON.stringify({evidence,expected:{proven_copies:copies,text_items:{runs:[]},inserted_ranges:[{destination_from:12,length:10}]},mutation:{sender_state_base64:initial,current_state_base64:initial,writer_client:71,operation,footprint}},null,2)+'\n')}const result=prepareContentEditWitness(evidence);assert.deepEqual(result.proven_copies,copies);assert.deepEqual(result.text_items,{runs:[]});const {buildContentEditWitness}=await import('../src/content-edit.js'),{text_items,...buildInput}=evidence;const built=buildContentEditWitness(buildInput);assert.deepEqual(built.operation.copies,copies);assert.deepEqual(built.text_items,{runs:[]});assert.deepEqual(built.inserted_ranges,[{destination_from:12,length:10}]);assert.equal(replayContentEditMutation({sender_state_base64:initial,current_state_base64:initial,writer_client:71,operation,footprint}).complete_mutation_correspondence,true);
 const forged=structuredClone(evidence);forged.operation.copies[1].destination=forged.operation.copies[0].destination;assert.throws(()=>prepareContentEditWitness(forged),/Duplicate destination/);const falseSource=structuredClone(evidence);falseSource.operation.copies[0].source.runs[0].type.clock=0;assert.throws(()=>prepareContentEditWitness(falseSource),/wrongly typed/);
 doc.destroy();
});


test('actual semantic input cannot silently borrow generated or peer retained identities',async()=>{
 const {readFileSync}=await import('node:fs'),{buildContentEditWitness}=await import('../src/content-edit.js'),{captureContentEditSnapshot,captureContentEditFootprint}=await import('../adapters/collaboration/content-edit-observer.js');
 for(const name of ['repeated-human-input','repeated-peer-input']){
  const fixture=JSON.parse(readFileSync(new URL(`../spec/relaymark/collaboration/fixtures/current-content-edit-${name}.json`,import.meta.url)));
  const {initProseMirrorDoc,updateYFragment}=await import('./helpers/canonical-binding.js');
  const {createCanonicalEditorSchema}=await import('../src/editor-model.js'),{Step}=await import('prosemirror-transform');
  const doc=new Y.Doc({gc:false});Y.applyUpdate(doc,Buffer.from(fixture.sender_state_base64,'base64'));doc.clientID=101;
  const root=doc.getXmlFragment('default'),schema=createCanonicalEditorSchema(),initialized=initProseMirrorDoc(root,schema);
  const before=captureContentEditSnapshot(root),vector=Y.encodeStateVector(doc),clocks=captureContentEditFootprint(doc,Uint8Array.of(0,0)).state_vector;
  const operation=fixture.evidence.operation;let target=initialized.doc;
  for(const step of operation.steps)target=Step.fromJSON(schema,step).apply(target).doc;
  // Deliberately omit the explicit command write: the value-only community
  // binding reproduces the attribution fault against a current physical seed.
  updateYFragment(doc,root,target,initialized.meta);
  const after=captureContentEditSnapshot(root),footprint=captureContentEditFootprint(doc,Y.encodeStateAsUpdate(doc,vector));
  assert.throws(()=>buildContentEditWitness({sender_before_snapshot:before,sender_after_snapshot:after,before_snapshot:before,after_snapshot:after,before_state_vector:clocks,operation,footprint}),/inserted text reused retained identity/);
  doc.destroy();
 }
 const fixture=JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/current-content-edit-identical-human-replacement.json',import.meta.url))),doc=new Y.Doc({gc:false});Y.applyUpdate(doc,new Uint8Array(Buffer.from(fixture.sender_state_base64,'base64')));
 const snapshot=captureContentEditSnapshot(doc.getXmlFragment('default')),footprint=captureContentEditFootprint(doc,new Uint8Array([0,0]));
 assert.throws(()=>buildContentEditWitness({sender_before_snapshot:snapshot,sender_after_snapshot:snapshot,before_snapshot:snapshot,after_snapshot:snapshot,before_state_vector:footprint.state_vector,operation:fixture.operation,footprint}),/inserted text reused retained identity/);doc.destroy();
});
