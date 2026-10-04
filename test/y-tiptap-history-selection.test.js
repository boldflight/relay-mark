import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {patchHistorySelection} from '../scripts/y-tiptap-history-selection.mjs';
const require=createRequire(import.meta.url);
test('one prepared maintained binding refuses upstream drift and uses its real ESM or CJS owner namespace',()=>{
 const base=new URL('./',new URL(require.resolve('@tiptap/y-tiptap'),'file:'));
 for(const suffix of ['js','cjs']){
  const source=readFileSync(new URL('y-tiptap.'+suffix,base),'utf8'),patched=patchHistorySelection(source);
  assert.equal(patchHistorySelection(source),patched);
  assert.ok(patched.includes('transaction.origin instanceof '+(suffix==='js'?'Y':'Y__namespace')+'.UndoManager;'));
  assert.ok(patched.includes('transaction.origin.currStackItem?.meta.get(this)'));
  assert.throws(()=>patchHistorySelection(source+'\n'),/source changed/);
  assert.throws(()=>patchHistorySelection(patched),/source changed/);
 }
});
