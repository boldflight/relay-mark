import test from 'node:test';import assert from 'node:assert/strict';import * as Y from 'yjs';
import {Step} from 'prosemirror-transform';import {initProseMirrorDoc,updateYFragment} from './helpers/canonical-binding.js';
import {parseDocument,documentToSnapshot} from '../src/document-source.js';import {createCanonicalEditorSchema} from '../src/editor-model.js';
import {node} from '../adapters/collaboration/prose-operation.js';import {captureContentEditSnapshot} from '../adapters/collaboration/content-edit-observer.js';
import {cloneCanonicalJSON} from '../src/canonical-json.js';
test('live maintained formatting dictionaries preserve marks before wire re-decoding',()=>{
 const doc=new Y.Doc({gc:false});doc.clientID=51;const root=doc.getXmlFragment('default');root.insert(0,documentToSnapshot(parseDocument('A🌍Z',{namespace:'format-live'})).children.map(node));
 const schema=createCanonicalEditorSchema(),initialized=initProseMirrorDoc(root,schema),changed=Step.fromJSON(schema,{stepType:'addMark',from:1,to:2,mark:{type:'bold'}}).apply(initialized.doc);
 updateYFragment(doc,root,changed.doc,initialized.meta);
 const snapshot=captureContentEditSnapshot(root);assert.deepEqual(snapshot.children[0].children[0].runs.map(r=>[r.text,r.attributes]),[['A',{bold:{}}],['🌍Z',{}]]);
 assert.throws(()=>cloneCanonicalJSON(Object.assign(Object.create(null),{bold:undefined})),/Invalid authored JSON/);
 assert.throws(()=>cloneCanonicalJSON(new Date()),/Invalid authored JSON/);
});
