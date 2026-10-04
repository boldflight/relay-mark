import test from 'node:test';
import assert from 'node:assert/strict';
import { proseMirrorToRelayMark, relayMarkToProseMirror } from '../src/document-adapter.js';
import { validateDocument } from '../src/validator.js';
const id = n => `b000000000000400080000000000000${String(n).padStart(2,'0')}`;
const label = {type:'questionLabel',attrs:{relaymarkId:id(2)},content:[{type:'text',text:'Choose ',marks:[{type:'bold'}]},{type:'text',text:'a plan'}]};
const question = {type:'questionBlock',attrs:{relaymarkId:id(1),id:'question-existing',type:'multiple_choice',required:true,points:3,min:null,max:null,settings:{randomize:false}},content:[label,
 {type:'questionOption',attrs:{relaymarkId:id(3),id:'option-existing-a',correct:true,points:null,settings:{}},content:[{type:'text',text:'Plan A'}]},
 {type:'questionOption',attrs:{relaymarkId:id(4),id:'option-existing-b',correct:false,points:null,settings:{}},content:[{type:'text',text:'Plan B'}]}]};

test('canonical form stores rich labels and independently identified option nodes', () => {
 const ast = proseMirrorToRelayMark({type:'doc',content:[question]});
 assert.deepEqual(ast,{type:'relaymark.document',blocks:[{id:id(1),type:'relay.form_question',props:{id:'question-existing',type:'multiple_choice',required:true,points:3,min:null,max:null,settings:{randomize:false}},content:[
 {id:id(2),type:'paragraph',content:[{type:'strong',content:[{type:'text',text:'Choose '}]},{type:'text',text:'a plan'}]},
 {id:id(3),type:'relay.form_option',props:{id:'option-existing-a',correct:true,points:null,settings:{}},content:[{type:'text',text:'Plan A'}]},
 {id:id(4),type:'relay.form_option',props:{id:'option-existing-b',correct:false,points:null,settings:{}},content:[{type:'text',text:'Plan B'}]}]}]});
 assert.deepEqual(validateDocument(ast),[]);
 assert.deepEqual(relayMarkToProseMirror(ast),{type:'doc',content:[question]});
 const invalid = structuredClone(ast); invalid.blocks[0].content[2].props.id='option-existing-a';
 assert.throws(()=>relayMarkToProseMirror(invalid),/option.*identity/i);
});

test('canonical data views preserve only the authored declaration', () => {
 const node={type:'relayDataView',attrs:{relaymarkId:id(5),source:'paper.related_tasks',projection:'table',columns:['title','status'],filter:{status:'open'},sort:['-due_date'],group:'status',limit:25,title:'Tasks'}};
 const ast=proseMirrorToRelayMark({type:'doc',content:[node]});
 assert.deepEqual(ast.blocks[0],{id:id(5),type:'relay.data_view',props:{source:'paper.related_tasks',projection:'table',columns:['title','status'],filter:{status:'open'},sort:['-due_date'],group:'status',limit:25,title:'Tasks'},content:[]});
 assert.deepEqual(validateDocument(ast),[]);
 assert.deepEqual(relayMarkToProseMirror(ast),{type:'doc',content:[node]});
 assert.throws(()=>proseMirrorToRelayMark({type:'doc',content:[{...node,attrs:{...node.attrs,records:[{private:'secret'}]}}]}),/Unsupported/);
});

test('authored image dimensions survive rich conversion without temporary media', () => {
 const node={type:'image',attrs:{relaymarkId:id(6),src:'/m/11111111-1111-4111-8111-111111111111',alt:'Diagram',title:null,width:640,height:480}};
 const ast=proseMirrorToRelayMark({type:'doc',content:[node]});
 assert.deepEqual(ast.blocks[0].props,{src:node.attrs.src,alt:'Diagram',title:null,width:640,height:480});
 assert.deepEqual(relayMarkToProseMirror(ast),{type:'doc',content:[node]});
 for(const width of [0,-1,Infinity,'640px']) assert.throws(()=>proseMirrorToRelayMark({type:'doc',content:[{...node,attrs:{...node.attrs,width}}]}),/dimension/i);
});
test('data view declarations reject nested predicate objects before host resolution',()=>{
 const node={type:'relayDataView',attrs:{relaymarkId:id(8),source:'paper.related_tasks',projection:'table',filter:{sql:{nested:'1'}}}};
 assert.throws(()=>proseMirrorToRelayMark({type:'doc',content:[node]}),/filter/);
});
