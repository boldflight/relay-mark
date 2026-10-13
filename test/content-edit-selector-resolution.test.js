import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {resolveContentEditTextItems,sourceSelectorWindows,validateSourceReadSelector} from '../src/content-edit.js';
const fixture=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/current-content-edit-repeated-peer-input.json',import.meta.url)));
const snapshot=fixture.evidence.sender_before_snapshot;
const type={client:101,clock:1};
test('current rich source fragments follow document order and retain selected gaps, full attributes and UTF16 identities',()=>{
 const result=resolveContentEditTextItems(snapshot,{runs:[{type,item:{client:303,clock:0},count:2},{type,item:{client:101,clock:2},count:1},{type,item:{client:101,clock:5},count:1}]});
 assert.deepEqual(result.segments.map(({text,path,offset})=>({text,path,offset})),[{text:'A',path:[0,0],offset:0},{text:'🌍',path:[0,0],offset:3},{text:'Z',path:[0,0],offset:5}]);
 assert.deepEqual(result.segments.map(v=>v.attributes),[{},{},{}]);
 assert.throws(()=>resolveContentEditTextItems(snapshot,{runs:[{type:{client:999,clock:1},item:{client:101,clock:2},count:1}]}),/unavailable or wrongly typed/);
 assert.throws(()=>resolveContentEditTextItems(snapshot,{runs:[{type,item:{client:101,clock:999},count:1}]}),/unavailable or wrongly typed/);
 assert.throws(()=>resolveContentEditTextItems(snapshot,{runs:[{type,item:{client:101,clock:3},count:1}]}),/Unicode/);
});

test('large source export reads bounded causal windows without changing command selector limits',()=>{
 const large=structuredClone(snapshot),text='h'.repeat(16383)+'🌍'+'j'.repeat(132004-16385);
 large.children=[large.children[0]];large.children[0].children=[large.children[0].children[0]];
 large.children[0].children[0].runs=[{item:{client:101,clock:2},count:text.length,text,attributes:{}}];
 const {windows}=sourceSelectorWindows(large);
 assert.equal(windows.length,9);assert.equal(windows[0].runs[0].count,16383);
 assert.ok(windows.every(w=>w.runs.reduce((n,r)=>n+r.count,0)<=16384));
 const selector={runs:windows.flatMap(w=>w.runs)};
 assert.equal(validateSourceReadSelector(selector),true);
 assert.throws(()=>validateSourceReadSelector({runs:[{type,item:{client:101,clock:2},count:12_582_913}]}),/Invalid causal run extent/);
 assert.equal(resolveContentEditTextItems(large,selector).segments.map(s=>s.text).join(''),text);
 assert.throws(()=>resolveContentEditTextItems(large,{runs:[{...selector.runs[0],type:{client:999,clock:1}}]}),/unavailable or wrongly typed/);
 assert.throws(()=>resolveContentEditTextItems(large,{runs:[selector.runs[0],selector.runs[0]]}),/Overlapping/);
 assert.throws(()=>resolveContentEditTextItems(large,{runs:[{type,item:{client:101,clock:16385},count:1}]}),/Unicode/);
});
