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
