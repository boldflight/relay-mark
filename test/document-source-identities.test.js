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
 assert.throws(()=>decodeSourceSelector(select(0,131073)),{code:'source_identity_limit'});
 assert.throws(()=>decodeSourceSelector(select(0xffffffff,2)),/Invalid/);
});


test('source-only errors carry stable identity, reference and resource codes',()=>{
 assert.throws(()=>issue(select(11,16,999)),{code:'source_identity_mismatch'});
 const human=issue(select(11,16));assert.throws(()=>foldSourceReferences(binding,select(53,16,999),[human]),{code:'source_identity_mismatch'});
 human.human_destinations=select(200);assert.throws(()=>foldSourceReferences(binding,select(200),[human]),{code:'source_reference_mismatch'});
 assert.throws(()=>decodeSourceSelector(select(0,131073)),{code:'source_identity_limit'});
 assert.throws(()=>foldSourceReferences(binding,empty,new Array(16385)),{code:'source_identity_limit'});
});

function currentReference(typed,copies=[],ancestry=empty,history=false){
 const transaction={transaction_id:'33333333-3333-4333-8333-333333333333',text_items:typed,content_edit:{copies,...(history?{history:{}}:{})}};
 const proof={complete_mutation_correspondence:true,text_items:typed,proven_copies:copies,...(history?{owned_history_correspondence:true,restored_copies:copies}:{})};
 return classifyContentEditReference(binding,transaction,proof,ancestry);
}
test('read windows fold genuine bounded commands beyond the per-operation document unit limit',()=>{
 const first=currentReference(select(100,66002)),second=currentReference(select(100000,66002));
 const candidates={runs:[...first.text_items.runs,...second.text_items.runs]};
 // Each read window reuses the unchanged bounded classifier.
 const windows=candidates.runs.flatMap(run=>{const parts=[];for(let offset=0;offset<run.count;offset+=16384)parts.push({runs:[{...run,item:{...run.item,clock:run.item.clock+offset},count:Math.min(16384,run.count-offset)}]});return parts;});
 const folded=windows.flatMap(window=>foldSourceReferences(binding,window,[first,second]).runs);
 assert.equal(folded.reduce((n,r)=>n+r.count,0),132004);
 assert.deepEqual(folded[0],{...first.text_items.runs[0],count:16384});
 assert.throws(()=>foldSourceReferences(binding,candidates,[first,second]),{code:'source_identity_limit'});
 assert.throws(()=>classifyContentEditReference(binding,{transaction_id:'large',text_items:select(0,131073),content_edit:{copies:[]}},
  {complete_mutation_correspondence:true,text_items:select(0,131073),proven_copies:[]},empty),{code:'source_identity_limit'});
});
test('mixed-origin copies map exact intervals and can repeat the same source without duplicating destinations',()=>{
 const copies=[{source:select(11,16),destination:select(53,16)},
  {source:select(11,16),destination:select(100,16,3)}];
 const ancestry={runs:[...select(13,2).runs,...select(20,3).runs]};
 const expected={runs:[...select(55,2).runs,...select(62,3).runs,...select(102,2,3).runs,...select(109,3,3).runs]};
 const reference=currentReference(empty,copies,ancestry,true);
 assert.deepEqual(reference.human_destinations,expected);
 assert.deepEqual(foldSourceReferences(binding,{runs:[...select(53,16).runs,...select(100,16,3).runs]},[reference]),expected);
 assert.throws(()=>currentReference(empty,copies,select(20,3,999),true),{code:'source_identity_mismatch'});
 assert.throws(()=>currentReference(empty,[copies[0],copies[0]],ancestry,true));
 assert.throws(()=>currentReference(select(53),[copies[0]],ancestry));
});
test('copy packet run order pairs identities exactly across independent item and text types',()=>{
 const source={runs:[...select(20,2).runs,...select(11,3).runs]};
 const destination={runs:[...select(100,1,3).runs,...select(53,4).runs]};
 const reference=currentReference(empty,[{source,destination}],select(11,2),true);
 assert.deepEqual(reference.human_destinations,select(54,2));
 const forged=structuredClone(reference);forged.human_destinations=select(52,2);
 assert.throws(()=>foldSourceReferences(binding,select(52,2),[forged]),{code:'source_reference_mismatch'});
});
