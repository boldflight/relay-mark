import {currentOperationSeed} from './helpers/current-operation-seed.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import * as Y from 'yjs';
import {initProseMirrorDoc,prosemirrorToYXmlFragment} from './helpers/canonical-binding.js';
import * as Runtime from '../src/content-edit.js';
import {produceDocumentPatch} from '../src/document-patch.js';
import {parseDocument} from '../src/document-source.js';
import {captureContentEditSnapshot} from '../adapters/collaboration/content-edit-observer.js';
import {relayMarkToProseMirror,proseMirrorToRelayMark} from '../src/document-adapter.js';
const fixture=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-typing-mutation.json',import.meta.url)));
const metadata=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-metadata-history.json',import.meta.url))).normal;
const args=f=>({state_base64:currentOperationSeed(f.sender_state_base64),writer_client:818,transaction_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',owner_id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'});
function document(f){const d=new Y.Doc({gc:false});try{Y.applyUpdate(d,new Uint8Array(Buffer.from(currentOperationSeed(f.sender_state_base64),'base64')));return proseMirrorToRelayMark(initProseMirrorDoc(d.getXmlFragment('default'),Runtime.createCanonicalEditorSchema()).doc.toJSON());}finally{d.destroy();}}
test('headless reviewed append preserves existing rich widgets, identity and metadata with one actual command',()=>{
 const original=document(metadata),target=structuredClone(original);
 target.blocks.push({id:'b88888888888848888888888888888888',type:'paragraph',content:[{type:'strong',content:[{type:'text',text:'Reviewed 🌍'}]}]});
 target.frontmatter={title:'Reviewed title'};
 const result=produceDocumentPatch({...args(metadata),target_document:target});
 assert.deepEqual(result.authored_document,target);
 assert.deepEqual(result.authored_document.blocks.slice(0,-1),original.blocks);
 assert.equal(result.proof.complete_mutation_correspondence,true);
 assert.equal(result.content_edit.steps.filter(s=>s.stepType==='docAttr').length,1);
 assert.equal(result.text_items.runs.reduce((n,r)=>n+r.count,0),'Reviewed 🌍'.length);
 assert.deepEqual(document(metadata),original);
});
test('reviewed replacement and deletion keep unchanged block IDs and use maintained step execution',()=>{
 const original=document(fixture),target=structuredClone(original);
 target.blocks[0].content=[{type:'text',text:'Replacement 🚀'}];
 const result=produceDocumentPatch({...args(fixture),target_document:target});
 assert.deepEqual(result.authored_document,target);
 assert.equal(result.authored_document.blocks[0].id,original.blocks[0].id);
 const trimmed=structuredClone(target);trimmed.blocks[0].content=[];
 const deletion=produceDocumentPatch({...args(fixture),state_base64:result.state_base64,target_document:trimmed});
 assert.deepEqual(deletion.authored_document,trimmed);
 assert.equal(deletion.text_items.runs.length,0);
});
test('reviewed patch refuses no-op, unsupported or duplicate identity and unknown inputs',()=>{
 const target=document(fixture),input={...args(fixture),target_document:target};
 assert.throws(()=>produceDocumentPatch(input));
 assert.throws(()=>produceDocumentPatch({...input,target_document:{...target,blocks:[...target.blocks,...target.blocks]}}));
 assert.throws(()=>produceDocumentPatch({...input,target_document:{...target,unknown:'discard me'}}));
 assert.throws(()=>produceDocumentPatch({...input,actor_id:'untrusted'}));
 assert.deepEqual(document(fixture),target);
});

test('headless task-link attribute patch retains original marked title items and relative anchors through the next receipt',()=>{
 const seed=new Y.Doc({gc:false});seed.clientID=800;
 const ast=parseDocument('- [ ] Rich **🌍** title\n\nAfter',{namespace:'reviewed-task-link'});
 prosemirrorToYXmlFragment(Runtime.createCanonicalEditorSchema().nodeFromJSON(relayMarkToProseMirror(ast)),seed.getXmlFragment('default'));
 const paragraph=seed.getXmlFragment('default').get(0).get(0).get(0),text=paragraph.get(0);
 const original=captureContentEditSnapshot(seed.getXmlFragment('default'));
 const anchor=Y.createRelativePositionFromTypeIndex(text,7);
 const target=structuredClone(ast);target.blocks[0].content[0].props.entityId='22222222-2222-4222-8222-222222222222';
 const input={state_base64:Buffer.from(Y.encodeStateAsUpdate(seed)).toString('base64'),writer_client:818,transaction_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',owner_id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',target_document:target};
 const linked=produceDocumentPatch(input);
 assert.deepEqual(linked.content_edit.steps,[{stepType:'attr',pos:1,attr:'entityId',value:target.blocks[0].content[0].props.entityId}]);
 assert.deepEqual(linked.text_items,{runs:[]});assert.deepEqual(linked.content_edit.copies,[]);
 const after=new Y.Doc({gc:false});Y.applyUpdate(after,Buffer.from(linked.state_base64,'base64'));
 const linkedSnapshot=captureContentEditSnapshot(after.getXmlFragment('default'));
 assert.deepEqual(linkedSnapshot.children[0].children[0].children[0],original.children[0].children[0].children[0]);
 const resolved=Y.createAbsolutePositionFromRelativePosition(anchor,after);
 assert.equal(resolved.index,7);assert.equal(resolved.type.toString(),'Rich <bold>🌍</bold> title');
 const checked=structuredClone(target);checked.blocks[0].content[0].props.checked=true;
 const next=produceDocumentPatch({...input,state_base64:linked.state_base64,transaction_id:'cccccccc-cccc-4ccc-8ccc-cccccccccccc',target_document:checked});
 assert.deepEqual(next.content_edit.steps,[{stepType:'attr',pos:1,attr:'checked',value:true}]);
 assert.equal(next.proof.complete_mutation_correspondence,true);assert.deepEqual(next.content_edit.copies,[]);
 const replay=Runtime.replayContentEditMutation({sender_state_base64:linked.state_base64,current_state_base64:linked.state_base64,writer_client:818,operation:{kind:'content_edit',steps:next.content_edit.steps,copies:next.content_edit.copies,group:next.content_edit.group},footprint:next.proof.footprint});
 assert.equal(replay.complete_mutation_correspondence,true);
 seed.destroy();after.destroy();
});

test('reference label and media dimension attributes retain surrounding and identified subtree identities',()=>{
 const seed=new Y.Doc({gc:false});seed.clientID=800;
 const source='Before [[Task: 22222222-2222-4222-8222-222222222222 | Old]] after\n\n![Keep](https://example.test/image.png)';
 const ast=parseDocument(source,{namespace:'reviewed-reference-attrs'});
 prosemirrorToYXmlFragment(Runtime.createCanonicalEditorSchema().nodeFromJSON(relayMarkToProseMirror(ast)),seed.getXmlFragment('default'));
 const before=captureContentEditSnapshot(seed.getXmlFragment('default'));
 const target=structuredClone(ast);
 target.blocks[0].content[1]=parseDocument('[[Task: 22222222-2222-4222-8222-222222222222 | New]]',{namespace:'new-reference-label'}).blocks[0].content[0];
 target.blocks[1].props.width=320;target.blocks[1].props.height=240;
 const result=produceDocumentPatch({state_base64:Buffer.from(Y.encodeStateAsUpdate(seed)).toString('base64'),writer_client:818,transaction_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',owner_id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',target_document:target});
 assert.equal(result.content_edit.steps.length,4);assert.ok(result.content_edit.steps.every(step=>step.stepType==='attr'));
 assert.deepEqual(result.text_items,{runs:[]});assert.deepEqual(result.content_edit.copies,[]);
 const afterDoc=new Y.Doc({gc:false});Y.applyUpdate(afterDoc,Buffer.from(result.state_base64,'base64'));
 const after=captureContentEditSnapshot(afterDoc.getXmlFragment('default'));
 assert.deepEqual(after.children[0].type,before.children[0].type);
 assert.deepEqual(after.children[0].children[0],before.children[0].children[0]);
 assert.deepEqual(after.children[0].children[2],before.children[0].children[2]);
 assert.deepEqual(after.children[0].children[1].type,before.children[0].children[1].type);
 assert.deepEqual(after.children[1].type,before.children[1].type);
 assert.deepEqual(result.authored_document,target);
 seed.destroy();afterDoc.destroy();
});

test('moving identified equal-text blocks remains a structural Slice command rather than relabeling their identities',()=>{
 const seed=new Y.Doc({gc:false});seed.clientID=800;
 const ast=parseDocument('Same 🌍\n\nSame 🌍',{namespace:'reviewed-equal-text-move'});
 prosemirrorToYXmlFragment(Runtime.createCanonicalEditorSchema().nodeFromJSON(relayMarkToProseMirror(ast)),seed.getXmlFragment('default'));
 const target={...ast,blocks:[...ast.blocks].reverse()};
 const result=produceDocumentPatch({state_base64:Buffer.from(Y.encodeStateAsUpdate(seed)).toString('base64'),writer_client:818,transaction_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',owner_id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',target_document:target});
 assert.deepEqual(result.authored_document,target);
 assert.deepEqual(result.content_edit.steps.map(step=>step.stepType),['replace']);
 assert.deepEqual(result.text_items,{runs:[]});
 assert.equal(result.content_edit.copies.flatMap(copy=>copy.destination.runs).reduce((sum,run)=>sum+run.count,0),14);
 seed.destroy();
});
