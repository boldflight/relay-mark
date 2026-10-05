import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {stableStringify} from '../src/canonical-json.js';

test('reviewed archive Unicode metadata has the same exact UTF-8 key bytes and digest on every runtime',()=>{
 const metadata={Z:1,a:2,'é':3,'Ω':4,'𐀀':5,'\uE000':6};
 const expected='{"Z":1,"a":2,"é":3,"Ω":4,"\uE000":6,"𐀀":5}';
 assert.equal(stableStringify(metadata),expected);
 assert.equal(createHash('sha256').update(stableStringify(metadata)).digest('hex'),createHash('sha256').update(expected).digest('hex'));
 const document={blocks:[],frontmatter:{nested:[metadata],title:'Raw 🌍'}};
 const reverse={frontmatter:{title:'Raw 🌍',nested:[Object.fromEntries(Object.entries(metadata).reverse())]},blocks:[]};
 assert.equal(stableStringify(document),stableStringify(reverse));
 assert.ok(stableStringify(document).includes(expected));
});
test('canonical key encoding preserves decomposed Unicode, numeric keys and normal original JSON bytes',()=>{
 assert.equal(stableStringify({'é':1,'e\u0301':2,'10':3,'2':4}),'{"10":3,"2":4,"é":2,"é":1}');
 assert.equal(stableStringify({content_edit:{kind:'content_edit',steps:[]},text_items:{runs:[]}}),'{"content_edit":{"kind":"content_edit","steps":[]},"text_items":{"runs":[]}}');
 assert.throws(()=>stableStringify({'\ud800':'invalid UTF-8 key'}),/Unicode/);
});
