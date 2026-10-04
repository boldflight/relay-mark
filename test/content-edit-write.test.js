import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {applyContentEdit,prepareContentEditWrite,planContentEditTextWrite} from '../src/content-edit.js';
const f=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-identical-human-replacement.json',import.meta.url)));
const before=f.before_document,id=before.content[0].attrs.relaymarkId;
function plan(steps){const after=applyContentEdit(before,{kind:'content_edit',steps}).document;return planContentEditTextWrite(prepareContentEditWrite(before,steps,after),id,0,id,0)}
test('causal text delta chooses actual insertion positions before identical generated text',()=>{
 assert.deepEqual(plan([{stepType:'replace',from:2,to:2,slice:{content:[{type:'text',text:'🌍'}]}}]),[{retain:1},{insert:'🌍'},{retain:3}]);
 assert.deepEqual(plan(f.operation.steps),[{retain:1},{delete:2},{insert:'🌍'},{retain:1}]);
});
test('causal writer keeps marks and metadata out of text identity replacement and binds final append steps',()=>{
 const steps=[{stepType:'addMark',from:1,to:5,mark:{type:'bold'}},{stepType:'docAttr',attr:'relaymark',value:{meta:{source:'human'}}}];
 assert.deepEqual(plan(steps),[{retain:4}]);
 const after=applyContentEdit(before,{kind:'content_edit',steps:f.operation.steps}).document;
 assert.throws(()=>prepareContentEditWrite(before,f.operation.steps,{...after,attrs:{relaymark:{meta:{forged:true}}}}),/writer result/);
});

import {documentToSnapshot,parseDocument} from '../src/document-source.js';
test('canonical construction groups adjacent rich mark runs in one maintained text branch',()=>{
 const snapshot=documentToSnapshot(parseDocument('[A](https://one.example) [B](https://two.example)',{namespace:'marks'}));
 assert.equal(snapshot.children[0].children.length,1);
 assert.deepEqual(snapshot.children[0].children[0].delta.map(run=>run.insert),['A',' ','B']);
 assert.equal(snapshot.children[0].children[0].delta[0].attributes.link.href,'https://one.example');
 assert.equal(snapshot.children[0].children[0].delta[2].attributes.link.href,'https://two.example');
});
