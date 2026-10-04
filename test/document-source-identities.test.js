import test from 'node:test';
import assert from 'node:assert/strict';
import {classifyContentEditReference,foldSourceReferences,decodeSourceSelector,encodeSourceIdentities} from '../src/document-source-identities.js';
const binding={document_id:'doc',incarnation:'incarnation'};
const select=(clock,count=1,type=2)=>({runs:[{item:{client:101,clock},type:{client:101,clock:type},count}]});
const empty={runs:[]};
function issue(ancestry){const copies=[{source:select(11,16),destination:select(53,16)}],transaction={transaction_id:'22222222-2222-4222-8222-222222222222',text_items:empty,content_edit:{history:{},copies}},proof={complete_mutation_correspondence:true,owned_history_correspondence:true,text_items:empty,proven_copies:copies,restored_copies:copies};return classifyContentEditReference(binding,transaction,proof,ancestry);}
test('restored tombstoned human ancestry stays human while generated copies stay generated',()=>{
 const human=issue(select(11,16));assert.deepEqual(human.human_destinations,select(53,16));
 assert.deepEqual(issue(empty).human_destinations,empty);
 assert.deepEqual(foldSourceReferences(binding,select(53,16),[human]),select(53,16));
 assert.deepEqual(foldSourceReferences(binding,select(200),[human]),empty);
});
test('receipt copies cannot borrow another text type or document binding',()=>{
 assert.throws(()=>issue(select(11,16,999)),/type mismatch/);
 const human=issue(select(11,16));assert.throws(()=>foldSourceReferences({...binding,incarnation:'other'},select(53,16),[human]),/binding mismatch/);
 assert.throws(()=>foldSourceReferences(binding,select(53,16,999),[human]),/type mismatch/);
});
test('unproven human destinations never classify current candidates',()=>{
 const human=issue(empty);human.human_destinations=select(200);
 assert.throws(()=>foldSourceReferences(binding,select(200),[human]),/Unproven/);
});
test('canonical identity selectors reject overlap and bounded overflow',()=>{
 assert.deepEqual(encodeSourceIdentities(decodeSourceSelector(select(10,16))),select(10,16));
 assert.throws(()=>decodeSourceSelector({runs:[...select(10,2).runs,...select(11).runs]}),/Overlapping/);
 assert.throws(()=>decodeSourceSelector(select(0,131073)),/Invalid/);
 assert.throws(()=>decodeSourceSelector(select(0xffffffff,2)),/Invalid/);
});
