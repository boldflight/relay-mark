import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parseDocument} from '../src/document-source.js';
import {relayMarkToProseMirror} from '../src/document-adapter.js';

test('maintained rich content edit applies marked paste and steps in exact document context',async()=>{
 const {applyContentEdit}=await import('../src/content-edit.js');
 const before=relayMarkToProseMirror(parseDocument('Hello world',{namespace:'step-proof'}));
 const result=applyContentEdit(before,{kind:'content_edit',steps:[{stepType:'replace',from:7,to:12,slice:{content:[
  {type:'text',text:'peer',marks:[{type:'bold'}]},{type:'text',text:'!',marks:[{type:'italic'}]}
 ]}}]});
 assert.deepEqual(result.document.content[0].content,[{type:'text',text:'Hello '},{type:'text',marks:[{type:'bold'}],text:'peer'},{type:'text',marks:[{type:'italic'}],text:'!'}]);
 assert.deepEqual(result.step_maps,[{ranges:[7,5,5],inverted:false}]);
 assert.equal(result.authored_document.blocks[0].id,before.content[0].attrs.relaymarkId);
 assert.deepEqual(result.authored_document.blocks[0].content,[{type:'text',text:'Hello '},{type:'strong',content:[{type:'text',text:'peer'}]},{type:'emphasis',content:[{type:'text',text:'!'}]}]);
});

test('rich form paste and nested setting step use one maintained operation and refuse invalid final ancestry',async()=>{
 const {applyContentEdit}=await import('../src/content-edit.js');
 const before=relayMarkToProseMirror(parseDocument('Old',{namespace:'form-paste'}));
 const rich=JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/canonical-form.json',import.meta.url))).normalized;
 const question=rich.content.find(n=>n.type==='questionBlock');
 assert.ok(question);
 const result=applyContentEdit(before,{kind:'content_edit',steps:[
  {stepType:'replace',from:0,to:5,slice:{content:[question]}},
  {stepType:'attr',pos:0,attr:'required',value:true}
 ]});
 assert.equal(result.document.content[0].attrs.required,true);
 assert.deepEqual(result.document.content[0].content,question.content);
 assert.equal(result.authored_document.blocks[0].type,'relay.form_question');
 assert.throws(()=>applyContentEdit(before,{kind:'content_edit',steps:[{stepType:'replace',from:0,to:5,slice:{content:[question.content[1]]}}]}));
 assert.deepEqual(before.content[0].content,[{type:'text',text:'Old'}]);
});

test('actual maintained maps retain causal suffix through Enter and do not classify equal paste as copies',async()=>{
 const {applyContentEdit}=await import('../src/content-edit.js');
 const before=relayMarkToProseMirror(parseDocument('Hello world',{namespace:'causal-map'}));
 const id=before.content[0].attrs.relaymarkId,newID='b00000000000040008000000000000031';
 const result=applyContentEdit(before,{kind:'content_edit',steps:[
  {stepType:'replace',from:7,to:7,slice:{content:[{type:'paragraph',attrs:{relaymarkId:id}},{type:'paragraph',attrs:{relaymarkId:id}}],openStart:1,openEnd:1}},
  {stepType:'attr',pos:8,attr:'relaymarkId',value:newID}
 ]});
 assert.deepEqual(result.retained_ranges,[{source_from:0,destination_from:0,length:7},{source_from:7,destination_from:9,length:6}]);
 assert.equal(result.document.content[0].content[0].text,'Hello ');
 assert.equal(result.document.content[1].content[0].text,'world');
 const paste=applyContentEdit(before,{kind:'content_edit',steps:[{stepType:'replace',from:7,to:12,slice:{content:[{type:'text',text:'world'}]}}]});
 assert.deepEqual(paste.retained_ranges,[{source_from:0,destination_from:0,length:7},{source_from:12,destination_from:12,length:1}]);
});
