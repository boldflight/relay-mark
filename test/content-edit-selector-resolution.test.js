import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {resolveContentEditTextItems} from '../src/content-edit.js';
const fixture=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-repeated-peer-input.json',import.meta.url)));
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
