import test from 'node:test';
import assert from 'node:assert/strict';
import {createCanonicalEditorSchema,planClipboardAnchorAllocation,planClipboardHeadingNavigation,planReviewedHeadingNavigation} from '../src/content-edit.js';
import {parseDocument} from '../src/document-source.js';
import {relayMarkToProseMirror} from '../src/document-adapter.js';
import {Transform,Step} from 'prosemirror-transform';
import {Slice} from 'prosemirror-model';
const schema=createCanonicalEditorSchema();
const parse=(text,namespace)=>schema.nodeFromJSON(relayMarkToProseMirror(parseDocument(text,{namespace})));
function placement(){
 const before=parse('# Target\n\n@Anchor(name: "section")\n\nPrefix suffix','clipboard-target');
 const source=parse('# Copied\n\n@Anchor(name: "section")\n\n[Section](#section) [Chapter](#chapter)\n\n@Button(label: "Section", kind: "anchor", target: "section")\n\n> Last block','clipboard-source');
 const rename=(doc)=>{const tr=new Transform(doc);tr.setNodeAttribute(0,'headingId','chapter');return tr.doc;};
 const target=rename(before),copy=rename(source),tr=new Transform(target);
 const paragraph=target.child(0).nodeSize+target.child(1).nodeSize;
 tr.replaceRange(paragraph+1+7,paragraph+1+7,new Slice(copy.content,0,0));
 // Same structural-identity repair performed by the native commit before any
 // destination allocation. The split suffix cannot claim retained prefix ID.
 let serial=1;const seen=new Set();tr.doc.descendants((node,pos)=>{
  const id=node.attrs.relaymarkId;if(typeof id!=='string')return;
  if(seen.has(id))tr.setNodeAttribute(pos,'relaymarkId','b'+(serial++).toString(16).padStart(32,'0'));else seen.add(id);
 });
 return {clipboard_slice:{content:copy.toJSON().content,openStart:0,openEnd:0},before_document:target.toJSON(),steps:tr.steps.map(step=>step.toJSON())};
}
function repair(input){
 const originalJSON=JSON.stringify(input);
 const anchors=planClipboardAnchorAllocation(input),steps=[...input.steps,...anchors.steps];
 assert.equal(JSON.stringify(input),originalJSON,'Planner changed original clipboard input');
 const tr=new Transform(schema.nodeFromJSON(anchors.document));
 const copiedID=input.clipboard_slice.content[0].attrs.relaymarkId;
 tr.doc.descendants((node,pos)=>{if(node.attrs.relaymarkId===copiedID)tr.setNodeAttribute(pos,'headingId','h-copied');});
 steps.push(...tr.steps.map(step=>step.toJSON()));
 return planClipboardHeadingNavigation({...input,steps});
}
test('clipboard inside retained paragraph repairs copied Anchor/link/Button and heading links while preserving retained destinations',()=>{
 const input=placement(),result=repair(input),doc=schema.nodeFromJSON(result.document);
 const anchors=[],headings=[],links=[],buttons=[];
 doc.descendants(node=>{
  if(node.type.name==='relayAnchor')anchors.push(node.attrs.name);
  if(node.type.name==='heading')headings.push(node.attrs.headingId);
  for(const mark of node.marks)if(mark.type.name==='link')links.push(mark.attrs.href);
  if(node.type.name==='relayButton')buttons.push(node.attrs.target);
 });
 const copiedAnchor='a-'+input.clipboard_slice.content[1].attrs.relaymarkId;
 assert.deepEqual(anchors,['section',copiedAnchor]);
 assert.deepEqual(headings,['chapter','h-copied']);
 assert.deepEqual(links,['#'+copiedAnchor,'#h-copied']);
 assert.deepEqual(buttons,[copiedAnchor]);
 assert.equal(doc.child(0).eq(schema.nodeFromJSON(input.before_document).child(0)),true);
 assert.equal(doc.child(1).eq(schema.nodeFromJSON(input.before_document).child(1)),true);
 assert.match(doc.textContent,/Prefix /);assert.match(doc.textContent,/suffix/);
 assert.throws(()=>planReviewedHeadingNavigation({archive_document:{type:"doc",content:input.clipboard_slice.content},before_document:input.before_document,block_indices:input.clipboard_slice.content.map((_,i)=>i),steps:input.steps}),/Unavailable reviewed navigation placement/);
});
test('clipboard does not infer source correspondence from matching text or reused structural identity',()=>{
 const input=placement(),reused=structuredClone(input);
 reused.clipboard_slice.content[0].attrs.relaymarkId=input.before_document.content[0].attrs.relaymarkId;
 assert.throws(()=>planClipboardAnchorAllocation(reused),/not freshly allocated/);
 const bad=structuredClone(input),tr=new Transform(schema.nodeFromJSON(input.before_document));
 for(const json of input.steps)tr.step(Step.fromJSON(schema,json));
 const copyID=input.clipboard_slice.content[1].attrs.relaymarkId;
 tr.doc.descendants((node,pos)=>{if(node.attrs.relaymarkId===copyID)tr.setNodeAttribute(pos,'relaymarkId','b0000000000000000000000000000abcd');});
 bad.steps=tr.steps.map(step=>step.toJSON());
 assert.throws(()=>planClipboardAnchorAllocation(bad),/changed retained destination|removed source wrapper/);
});

test('clipboard before retained same-name heading reserves original target name rather than current suffix',()=>{
 const source=parse('# Copied\n\n[Jump](#chapter)','clipboard-before-source');
 const before=parse('# Target','clipboard-before-target');
 const named=doc=>{const t=new Transform(doc);t.setNodeAttribute(0,'headingId','chapter');return t.doc;};
 const copied=named(source),target=named(before),tr=new Transform(target);
 tr.replace(0,0,new Slice(copied.content,0,0));
 const input={clipboard_slice:{content:copied.toJSON().content,openStart:0,openEnd:0},before_document:target.toJSON(),steps:tr.steps.map(step=>step.toJSON())};
 const allocation=planClipboardAnchorAllocation(input);
 assert.deepEqual(allocation.retained_destination_names,['chapter']);
 tr.setNodeAttribute(0,'headingId','h-copied');
 const result=planClipboardHeadingNavigation({...input,steps:tr.steps.map(step=>step.toJSON())});
 assert.equal(result.document.content[0].attrs.headingId,'h-copied');
 assert.equal(result.document.content[1].content[0].marks[0].attrs.href,'#h-copied');
 assert.equal(result.document.content[2].attrs.headingId,'chapter');
});

test('clipboard cannot classify reidentification of a lone original heading as a generated suffix',()=>{
 const input=placement(),tr=new Transform(schema.nodeFromJSON(input.before_document));
 for(const json of input.steps)tr.step(Step.fromJSON(schema,json));
 tr.setNodeAttribute(0,'relaymarkId','b0000000000000000000000000000beef');
 tr.setNodeAttribute(0,'headingId','forged-retained-name');
 assert.throws(()=>planClipboardAnchorAllocation({...input,steps:tr.steps.map(step=>step.toJSON())}),/changed retained destination/);
});
