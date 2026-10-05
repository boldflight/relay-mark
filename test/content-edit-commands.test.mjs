import test from 'node:test';
import assert from 'node:assert/strict';
import {parseDocument} from '../src/document-source.js';
import {relayMarkToProseMirror} from '../src/document-adapter.js';
import {createContentEditCommand,createCanonicalEditorSchema} from '../src/content-edit.js';
import {Step} from 'prosemirror-transform';

const schema=createCanonicalEditorSchema();
function run(source,command,selection){const before=relayMarkToProseMirror(typeof source==='string'?parseDocument(source,{namespace:'actual-command'}):source);
 const result=createContentEditCommand(before,{command,selection});let after=schema.nodeFromJSON(before);
 for(const json of result.steps){const applied=Step.fromJSON(schema,json).apply(after);assert.equal(applied.failed,null);after=applied.doc;}
 assert.deepEqual(after.toJSON(),result.document);return result;}

test('maintained Return splits marked Unicode within a callout with an actual open Slice',()=>{
 const result=run('@Callout(tone: "info", emphasis: "soft") {\n**A🌍Z**\n}','return',{type:'text',anchor:5,head:5});
 assert.equal(result.kind,'split');assert.equal(result.steps[0].stepType,'replace');
 assert.equal(result.steps[0].slice.openStart,1);
 const paragraphs=result.document.content[0].content;assert.equal(paragraphs.length,2);
 assert.equal(paragraphs[0].content[0].text,'A🌍');assert.equal(paragraphs[1].content[0].text,'Z');
 assert.equal(paragraphs[1].content[0].marks[0].type,'bold');
});

test('maintained Return deletes the selected rich range and lifts an empty secondary list paragraph',()=>{
 const replace=run('A🌍Z','return',{type:'text',anchor:2,head:4});
 assert.equal(replace.document.content.map(p=>p.content?.map(n=>n.text).join('')??'').join('|'),'A|Z');
 const empty=parseDocument('- First',{namespace:'empty-secondary'});empty.blocks[0].content[0].content.push({type:'paragraph',id:'b00000000000040008000000000000042',content:[]});
 const exit=run(empty,'return',{type:'text',anchor:10,head:10});
 assert.equal(exit.kind,'exit');assert.equal(exit.document.content[1].type,'paragraph');
});

test('maintained list indentation preserves marked text and refuses first-item sinking',()=>{
 const result=run('1. First\n2. **Second**','sink_list_item',{type:'text',anchor:12,head:12});
 assert.equal(result.steps[0].stepType,'replaceAround');
 assert.equal(result.document.content[0].content[0].content[1].type,'orderedList');
 assert.throws(()=>run('1. First','sink_list_item',{type:'text',anchor:3,head:3}),/refused/);
});
