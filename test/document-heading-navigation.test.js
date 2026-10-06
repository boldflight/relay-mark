import test from 'node:test';
import assert from 'node:assert/strict';
import {paperDocumentDestinations,canonicalPaperControlSource} from '../src/document-controls.js';
const heading=(text,id=null)=>({type:'heading',attrs:{headingId:id},content:[{type:'text',text}]});
test('original heading destinations retain explicit Anchor precedence and duplicate source ordinals',()=>{
 const doc={type:'doc',content:[heading('Same 🌍','chapter'),heading('Same 🌍','chapter'),
  {type:'relayAnchor',attrs:{name:'chapter'}},heading('Café 🌍')]};
 assert.deepEqual(paperDocumentDestinations(doc),[
  {source_path:[2],kind:'anchor',name:'chapter'},
  {source_path:[0],kind:'heading',name:'chapter-2'},
  {source_path:[1],kind:'heading',name:'chapter-3'},
  {source_path:[3],kind:'heading',name:'cafe'},
 ]);
});

import {createCanonicalEditorSchema,planReviewedHeadingNavigation} from '../src/content-edit.js';
import {parseDocument} from '../src/document-source.js';
import {relayMarkToProseMirror} from '../src/document-adapter.js';
import {Transform} from 'prosemirror-transform';
import {Slice as ModelSlice} from 'prosemirror-model';
const schema=createCanonicalEditorSchema();
function actualTransform({selected=[0,1,2],href='#%63hapter',unchanged=false,duplicate=false}={}){
 const ast=parseDocument(`# Donor 🌍\n\n[Jump](${href})\n\n@Button(label: "Jump", kind: "anchor", target: "chapter")`,{namespace:'navigation-source'});
 ast.blocks[0].props.headingId='chapter';
 // Original authored AST can retain a malformed fragment without MarkdownIt
 // percent-escaping it on import; the reviewed planner must refuse it.
 ast.blocks[1].content[0].href=href;
 if(duplicate){ast.blocks.unshift(structuredClone(ast.blocks[0]));ast.blocks[0].id='b00000000000040008000000000000001';ast.blocks[3].props.target='chapter-2';ast.blocks[3].props.source=canonicalPaperControlSource('button',{label:'Jump',kind:'anchor',target:'chapter-2'});}
 const original=schema.nodeFromJSON(relayMarkToProseMirror(ast));
 const target=parseDocument('# Target',{namespace:'navigation-target'});target.blocks[0].props.headingId=unchanged?'target':'chapter';
 const before=schema.nodeFromJSON(relayMarkToProseMirror(target));
 const tr=new Transform(before);tr.replace(before.content.size,before.content.size,new ModelSlice(schema.nodeFromJSON({type:'doc',content:selected.map(i=>original.child(i).toJSON())}).content,0,0));
 const pos=before.content.size;
 if(!unchanged&&selected.some(i=>original.child(i).type.name==='heading'))tr.setNodeAttribute(pos,'headingId','h-44444444-4444-4444-8444-444444444444');
 return {archive_document:original.toJSON(),before_document:before.toJSON(),block_indices:selected,steps:tr.steps.map(step=>step.toJSON())};
}
test('selected original heading path repairs encoded link and Button through maintained Steps without changing target',()=>{
 const input=actualTransform(),planned=planReviewedHeadingNavigation(input);
 assert.deepEqual(planned.steps.map(step=>step.stepType),['removeMark','addMark','attr']);
 assert.deepEqual(planned.document.content[0],input.before_document.content[0]);
 const name=planned.document.content[1].attrs.headingId;
 assert.equal(planned.document.content[2].content[0].marks[0].attrs.href,'#'+name);
 assert.equal(planned.document.content[3].attrs.target,name);
 assert.deepEqual(planned.navigation_correspondence.destinations,[{source_path:[0],kind:'heading',source_name:'chapter',destination_name:name}]);
 assert.deepEqual(planned.navigation_correspondence.references.map(r=>[r.source_path,r.source_target,r.destination_target]),[
  [[1,0],'#%63hapter','#'+name],[[2],'chapter',name],
 ]);
 assert.match(planned.navigation_correspondence.source_inventory_sha256,/^[0-9a-f]{64}$/);
});
test('unchanged unique original destination preserves raw percent encoding and no repair Steps',()=>{
 const planned=planReviewedHeadingNavigation(actualTransform({unchanged:true}));
 assert.deepEqual(planned.steps,[]);
 assert.equal(planned.document.content[2].content[0].marks[0].attrs.href,'#%63hapter');
});
test('unselected original same-name destination and malformed fragments refuse before a writer',()=>{
 assert.throws(()=>planReviewedHeadingNavigation(actualTransform({selected:[1,2]})),/not selected/);
 assert.throws(()=>planReviewedHeadingNavigation(actualTransform({href:'#%ZZ'})),/Malformed original navigation/);
 assert.throws(()=>planReviewedHeadingNavigation(actualTransform({href:'#missing'})),/Unresolved or ambiguous/);
 const wrong=actualTransform();wrong.steps[0].slice.content[1].content[0].text='Changed';
 assert.throws(()=>planReviewedHeadingNavigation(wrong),/changed original Slice/);
 const altered=actualTransform();altered.steps.push({stepType:'attr',pos:0,attr:'headingId',value:'renamed-target'});
 assert.throws(()=>planReviewedHeadingNavigation(altered),/changed retained target/);
});

test('a later selected identical heading retains its full archive ordinal suffix without earlier private names',()=>{
 const input=actualTransform({duplicate:true,selected:[1,2,3],href:'#chapter-2'}),planned=planReviewedHeadingNavigation(input);
 assert.deepEqual(planned.navigation_correspondence.destinations,[{source_path:[1],kind:'heading',source_name:'chapter-2',destination_name:'h-44444444-4444-4444-8444-444444444444'}]);
 assert.deepEqual(planned.navigation_correspondence.references.map(r=>r.source_path),[[2,0],[3]]);
 assert.equal(planned.navigation_correspondence.references[0].destination_target,'#h-44444444-4444-4444-8444-444444444444');
 assert.equal(planned.navigation_correspondence.destinations.some(entry=>entry.source_path[0]===0),false);
});

test('a valid import requiring more than512 actual repair Steps refuses before a writer',()=>{
 const ast=parseDocument('# Chapter\n\n'+Array.from({length:256},(_,i)=>`[Jump ${i}](#chapter)`).join('\n\n'),{namespace:'navigation-limit'});
 ast.blocks[0].props.headingId='chapter';
 const source=schema.nodeFromJSON(relayMarkToProseMirror(ast)),before=schema.nodeFromJSON(actualTransform().before_document),tr=new Transform(before);
 tr.replace(before.content.size,before.content.size,new ModelSlice(source.content,0,0));
 tr.setNodeAttribute(before.content.size,'headingId','h-44444444-4444-4444-8444-444444444444');
 assert.throws(()=>planReviewedHeadingNavigation({archive_document:source.toJSON(),before_document:before.toJSON(),block_indices:ast.blocks.map((_,i)=>i),steps:tr.steps.map(s=>s.toJSON())}),/Step limit/);
});
