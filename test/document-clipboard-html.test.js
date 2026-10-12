import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {importClipboardHTML,importDocumentHTML} from '../src/content-edit.js';
const read=html=>importClipboardHTML({html,namespace:'clipboard-slice-independent'});
test('exported partial paragraph retains marks, exact reference and open sides',()=>{
 const result=read('<p data-pm-slice=\'1 1 []\'>left <a href="#chapter">Jump</a></p>');
 assert.equal(result.slice.openStart,1); assert.equal(result.slice.openEnd,1);
 const pm={content:result.slice.content};
 assert.equal(pm.content[0].type,'paragraph');
 assert.equal(pm.content[0].content.map(n=>n.text||'').join(''),'left Jump');
 assert.equal(pm.content[0].content[1].marks.find(m=>m.type==='link').attrs.href,'#chapter');
 assert.throws(()=>importDocumentHTML({html:'<p data-pm-slice="1 1 []">left</p>',namespace:'recovery'}),/Unsupported retained HTML attribute/);
});
test('exported list context reconstructs exact wrappers without inventing closed boundaries',()=>{
 const result=read('<p data-pm-slice=\'1 1 ["bulletList",null,"listItem",null]\'>partial</p>');
 assert.equal(result.slice.openStart,3); assert.equal(result.slice.openEnd,3);
 assert.equal(result.slice.content[0].type,'bulletList');
 assert.equal(result.slice.content[0].content[0].type,'listItem');
 assert.equal(result.slice.content[0].content[0].content[0].content[0].text,'partial');
});
test('bare inline fragment retains actual text and bold mark without a synthetic block',()=>{
 const result=read('<strong>literal</strong>');
 assert.deepEqual(result.slice,{content:[{type:'text',marks:[{type:'bold'}],text:'literal'}],openStart:0,openEnd:0});
 assert.equal(result.normalizations.some(n=>n.operation==='clipboard_native_inline_wrapper'),false);
});
test('declared closed slice remains closed; forged depth/context/envelope refuse',()=>{
 const closed=read('<p data-pm-slice="0 0 []">block</p>').slice;
 assert.equal(closed.openStart,0); assert.equal(closed.openEnd,0);
 assert.equal(closed.content[0].content[0].text,'block');
 for(const html of ['<p data-pm-slice="2 2 []">x</p>','<p data-pm-slice=\'1 1 ["doc",null]\'>x</p>',
  '<p data-pm-slice="1 1 []">x</p><p data-pm-slice="1 1 []">y</p>'])assert.throws(()=>read(html));
});

// Captured from actual getCoreExtensions + TextSelection.content + maintained
// EditorView.serializeForClipboard, not a hand-written HTML substitute.
const actualRich=JSON.parse(readFileSync(new URL('./fixtures/actual-web-rich-clipboard.json',import.meta.url),'utf8'))[0];
test('actual whole rich web clipboard preserves callout IDs, settings and exact open Slice',()=>{
 assert.equal(actualRich.text,'Selection begins\n\nInstructions\n\nOwn bold body\n\nColumn\n\nValue\n\nQuestion\n\nFirst choice\n\nSelection ends');
 const result=read(actualRich.html);
 assert.deepEqual(JSON.parse(JSON.stringify(result.slice)),actualRich.slice);
 assert.equal(result.slice.content[1].attrs.relaymarkId,'calloutOriginal');
 assert.equal(result.slice.content[1].content[0].attrs.relaymarkId,'titleOriginal');
 assert.deepEqual(result.slice.content[3].attrs.settings,{randomize:true,description:'日本語',optional:null});
});
test('actual rich clipboard rejects malformed authored settings and conflicting presentation evidence',()=>{
 for(const html of [
  actualRich.html.replace('data-required="true"','data-required="yes"'),
  actualRich.html.replace('data-settings="{&quot;randomize&quot;:true,&quot;description&quot;:&quot;日本語&quot;,&quot;optional&quot;:null}"','data-settings="[]"'),
  actualRich.html.replace('data-required="true"','data-required="true" data-points="NaN"'),
  actualRich.html.replace('class="relay-callout"','class="foreign-callout"'),
  actualRich.html.replace('min-width: 50px;','min-width: 51px;'),
  actualRich.html.replace(' style="min-width: 50px;"',''),
  actualRich.html.replace('min-width: 25px;','width: 25px;'),
 ]){assert.notEqual(html,actualRich.html);assert.throws(()=>read(html));}
});

test("actual web partial-callout retained export preserves exact original context/marks/IDs",()=>{
 const result=read("<p data-relaymarkid=\"paragraphOriginal\" data-pm-slice=\"1 1 [&quot;callout&quot;,{&quot;relaymarkId&quot;:&quot;calloutOriginal&quot;,&quot;tone&quot;:&quot;warning&quot;,&quot;emphasis&quot;:&quot;strong&quot;}]\"><strong>selected</strong></p>");
 assert.deepEqual(JSON.parse(JSON.stringify(result.slice)),{"content": [{"type": "callout", "attrs": {"relaymarkId": "calloutOriginal", "tone": "warning", "emphasis": "strong"}, "content": [{"type": "paragraph", "attrs": {"relaymarkId": "paragraphOriginal"}, "content": [{"type": "text", "marks": [{"type": "bold"}], "text": "selected"}]}]}], "openStart": 2, "openEnd": 2});
 assert.equal(result.normalizations.filter(n=>n.operation==='normalize_clipboard_structural_identity').length,1);
});

test("actual web partial-list retained export preserves exact original context/marks/IDs",()=>{
 const result=read("<p data-relaymarkid=\"listParagraphOriginal\" data-pm-slice=\"1 1 [&quot;bulletList&quot;,{&quot;relaymarkId&quot;:&quot;listOriginal&quot;},&quot;listItem&quot;,{&quot;relaymarkId&quot;:&quot;itemOriginal&quot;}]\"><em>selected</em></p>");
 assert.deepEqual(JSON.parse(JSON.stringify(result.slice)),{"content": [{"type": "bulletList", "attrs": {"relaymarkId": "listOriginal"}, "content": [{"type": "listItem", "attrs": {"relaymarkId": "itemOriginal"}, "content": [{"type": "paragraph", "attrs": {"relaymarkId": "listParagraphOriginal"}, "content": [{"type": "text", "marks": [{"type": "italic"}], "text": "selected"}]}]}]}], "openStart": 3, "openEnd": 3});
 assert.equal(result.normalizations.filter(n=>n.operation==='normalize_clipboard_structural_identity').length,1);
});

test('former clipboard identity spelling is explicit recovery only and conflicts refuse',()=>{
 const legacy='<p data-relaymarkid="retained">literal</p>';
 assert.throws(()=>importDocumentHTML({html:legacy,namespace:'strict-document'}),/Unsupported retained HTML attribute/);
 assert.throws(()=>read('<p data-relaymarkid="old" data-relaymark-id="new">literal</p>'),/Conflicting clipboard structural identity/);
 assert.equal(read('<p data-relaymark-id="canonical">literal</p>').normalizations.some(n=>n.operation==='normalize_clipboard_structural_identity'),false);
});
