import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {importDocumentHTML} from '../src/document-html.js';
import {renderDocument} from '../src/document-source.js';
import {relayMarkToProseMirror} from '../src/document-adapter.js';
import {DOMParser as HTMLDOMParser} from 'linkedom/worker';
import {DOMParser as PMDOMParser} from 'prosemirror-model';
import {createCanonicalEditorSchema} from '../src/editor-model.js';
function authored(document,publicProjection=false){const pm=relayMarkToProseMirror(document);delete pm.attrs;function visit(node){if(node.attrs){delete node.attrs.relaymarkId;if(publicProjection&&node.type==='questionBlock')Object.assign(node.attrs,{points:null,min:null,max:null,settings:{}});if(publicProjection&&node.type==='questionOption')Object.assign(node.attrs,{correct:false,points:null,settings:{}});if(publicProjection&&node.type==='agentSuggestion')Object.assign(node.attrs,{confidence:null,evidence:[]});}for(const child of node.content||[])visit(child);}visit(pm);return pm;}
function fixture(name){const value=JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/'+name+'.json',import.meta.url)));return value.expected_ast||value.document||value;}
test('finite frozen HTML preserves independent rich fixture semantics and exact retry identity',()=>{
 for(const name of ['canonical-source','canonical-inline-media','canonical-directives','canonical-form','canonical-table-widths','rich-video-v3-draft','paper-controls-v3-draft','agent-suggestion-v3-draft','inline-atoms-v3-draft']){
  const original=fixture(name),html=renderDocument(original);
  const result=importDocumentHTML({html,namespace:'retained:'+name});
  if(name==='canonical-form'){assert.ok(!html.includes('data-authored'));assert.deepEqual(result.normalizations.filter(entry=>entry.operation==='historical_html_absent_fields').map(entry=>entry.attributes),[['points','min','max','settings'],['correct','points','settings'],['correct','points','settings']]);}
  assert.deepEqual(authored(result.document),authored(original,true),name);
  assert.deepEqual(importDocumentHTML({html,namespace:'retained:'+name}),result);
  assert.equal(renderDocument(original),html,'original HTML is immutable');
 }
});
test('historical HTML text and marks remain frozen independently of later private source',()=>{
 const html='<h2>Historical announcement</h2><p>Keep <strong>published meaning</strong> and <a href="https://example.test/retained">original source</a>.</p>';
 const result=importDocumentHTML({html,namespace:'original-publication'});
 assert.equal(result.document.blocks[0].type,'heading');
 assert.equal(result.document.blocks[0].props.level,2);
 assert.deepEqual(result.document.blocks[1].content[1],{type:'strong',content:[{type:'text',text:'published meaning'}]});
 assert.equal(result.document.blocks[1].content[3].href,'https://example.test/retained');
 assert.ok(result.identity_mapping.added.length>=2);
 assert.ok(!JSON.stringify(result).includes('Private'));
});
test('unknown nested source, hidden attributes and conflicting media evidence refuse before source erasure',()=>{
 for(const html of [
  '<p>Keep <details>unrepresented source</details></p>',
  '<p data-private-source="retained">Keep</p>',
  '<div data-relay-video="11111111-1111-4111-8111-111111111111" data-authored="{&quot;videoId&quot;:&quot;22222222-2222-4222-8222-222222222222&quot;}"></div>',
  '<p>Keep <script>original unsupported source</script></p>',
  '<aside data-relay-callout="neutral"><div data-callout-title="true">Title</div><p><strong>Keep</strong><iframe src="https://example.test/embed"></iframe></p></aside>',
 ])assert.throws(()=>importDocumentHTML({html,namespace:'retained-refusal'}));
});

test('genuine historical tight-list inline text uses maintained PM paragraph wrapping without loss',()=>{
 const result=importDocumentHTML({html:'<ul><li><strong>First</strong></li><li>Second</li></ul>',namespace:'retained-tight-list'});
 assert.equal(result.document.blocks[0].type,'list');
 assert.deepEqual(result.document.blocks[0].content[0].content[0].content,[{type:'strong',content:[{type:'text',text:'First'}]}]);
 assert.deepEqual(result.document.blocks[0].content[1].content[0].content,[{type:'text',text:'Second'}]);
 assert.equal(result.normalizations.filter(entry=>entry.operation==='wrap_retained_inline').length,2);
});

test('explicit retained nil and empty HTML use the same canonical empty grammar, never a later source',()=>{
 for(const html of [null,'']){
  const result=importDocumentHTML({html,namespace:'retained-empty:'+String(html)});
  assert.equal(result.document.blocks.length,1);
  assert.equal(result.document.blocks[0].type,'paragraph');
  assert.deepEqual(result.document.blocks[0].content,[]);
  assert.equal(result.identity_mapping.added.length,1);
  assert.ok(result.normalizations.some(entry=>entry.operation==='empty_retained_html'&&entry.source_value===html));
  assert.deepEqual(importDocumentHTML({html,namespace:'retained-empty:'+String(html)}),result);
  assert.ok(!JSON.stringify(result.document).includes('Private'));
 }
});


test('maintained task-list HTML preserves checked linked identity, rich text and nested tasks through canonical roundtrip',()=>{
 const id='11111111-1111-4111-8111-111111111111';
 const html=`<ul data-type="taskList"><li data-checked="true" data-entity-id="${id}"><p>Done Ω <strong>bold</strong> 😀</p><ul data-type="taskList"><li data-type="taskItem" data-checked="false"><p>Next</p></li></ul></li></ul>`;
 const result=importDocumentHTML({html,namespace:'maintained-task-dom'}),list=result.document.blocks[0],item=list.content[0];
 assert.equal(list.type,'task_list');assert.deepEqual(item.props,{checked:true,entityId:id});
 assert.deepEqual(item.content[0].content,[{type:'text',text:'Done Ω '},{type:'strong',content:[{type:'text',text:'bold'}]},{type:'text',text:' 😀'}]);
 assert.equal(item.content[1].type,'task_list');assert.deepEqual(item.content[1].content[0].props,{checked:false,entityId:null});
 const canonical=renderDocument(result.document);
 assert.match(canonical,/data-relay-task-list="true"/);assert.ok(canonical.includes(`data-relay-task-item="${id}"`));
 assert.deepEqual(authored(importDocumentHTML({html:canonical,namespace:'canonical-task-dom'}).document),authored(result.document));
 const ordinary=importDocumentHTML({html:'<ul><li><p>Ordinary bullet</p></li></ul>',namespace:'ordinary-bullet-dom'});
 assert.equal(ordinary.document.blocks[0].type,'list');assert.equal(ordinary.document.blocks[0].content[0].type,'list_item');
});

test('maintained interactive task DOM parses only authored body and refuses conflicting task evidence',()=>{
 const id='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222';
 // Exact upstream TaskItem.renderHTML label/input/span plus div body; the
 // shared model uses the same body boundary without a second DOM converter.
 const html=`<ul data-type="taskList"><li data-type="taskItem" data-checked="true" data-entity-id="${id}"><label><input type="checkbox" checked="checked"><span></span></label><div><p>Keep <strong>meaning</strong> 😀</p></div></li></ul>`;
 const dom=new HTMLDOMParser().parseFromString('<html><body>'+html+'</body></html>','text/html');
 const doc=PMDOMParser.fromSchema(createCanonicalEditorSchema()).parse(dom.body,{preserveWhitespace:'full'});doc.check();
 const item=doc.firstChild.firstChild;assert.equal(doc.firstChild.type.name,'taskList');
 assert.equal(item.type.name,'taskItem');assert.equal(item.attrs.entityId,id);assert.equal(item.attrs.checked,true);
 assert.equal(item.textContent,'Keep meaning 😀');assert.equal(item.firstChild.child(1).marks[0].type.name,'bold');
 for(const bad of [
  `<ul data-relay-task-list="true" data-type="bulletList"><li data-checked="true"><p>Keep</p></li></ul>`,
  `<ul data-type="taskList"><li data-type="listItem" data-checked="true"><p>Keep</p></li></ul>`,
  `<ul data-type="taskList"><li data-checked="true" data-relay-task-item="${id}" data-entity-id="${other}"><p>Keep</p></li></ul>`,
  `<ul data-type="taskList"><li data-checked="false" data-entity-id="${id}" data-authored='{ "checked":true,"entityId":"${id}" }'><p>Keep</p></li></ul>`,
  `<ul data-type="taskList"><li data-checked="maybe"><p>Keep</p></li></ul>`,
  `<ul data-type="taskList"><li data-checked="true" data-entity-id="not-a-uuid"><p>Keep</p></li></ul>`,
  `<ul data-type="taskList" onclick="steal()"><li data-checked="true"><p>Keep</p></li></ul>`,
  `<ul data-type="taskList"><li data-checked="true"><p>Keep<script>hidden</script></p></li></ul>`,
 ])assert.throws(()=>importDocumentHTML({html:bad,namespace:'conflicting-task-dom'}));
});
