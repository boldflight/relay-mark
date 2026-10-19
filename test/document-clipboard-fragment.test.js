import test from 'node:test';
import assert from 'node:assert/strict';
import {importClipboardHTML} from '../src/content-edit.js'
import {createCanonicalEditorSchema} from '../src/editor-model.js';
import {Slice} from 'prosemirror-model';
import {Transform} from 'prosemirror-transform';
const schema=createCanonicalEditorSchema();
const read=html=>importClipboardHTML({html,namespace:'actual-fragment'});
test('inline fragment remains actual inline Slice and fits inside retained paragraph',()=>{
 const result=read('<strong>typed</strong>');
 assert.deepEqual(Object.keys(result).sort(),['normalizations','slice']);
 assert.deepEqual([result.slice.openStart,result.slice.openEnd],[0,0]);
 assert.equal(result.slice.content[0].type,'text');
 assert.equal(result.slice.content[0].text,'typed');
 const target=schema.node('doc',null,[schema.node('paragraph',null,[schema.text('left right')])]);
 const tr=new Transform(target);tr.replaceRange(6,6,Slice.fromJSON(schema,result.slice));
 assert.equal(tr.doc.childCount,1);assert.equal(tr.doc.textContent,'left typedright');
 assert.equal(tr.doc.child(0).child(1).marks[0].type.name,'bold');
});
test('legitimate open list-item fragment is not forced into a closed DocumentAST',()=>{
 const result=read('<li data-pm-slice="2 2 []"><p>partial</p></li>');
 assert.equal(result.slice.content[0].type,'listItem');
 assert.deepEqual([result.slice.openStart,result.slice.openEnd],[2,2]);
 assert.equal(result.slice.content[0].content[0].content[0].text,'partial');
 assert.equal(Object.hasOwn(result,'document'),false);
});
