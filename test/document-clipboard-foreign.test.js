import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {importClipboardHTML} from '../src/content-edit.js';

// Clipboard HTML other applications write is read with the web editor's own
// TipTap paste rules; the result is the canonical slice the editor inserts.
const read=html=>importClipboardHTML({html,namespace:'foreign-clipboard'});
const [safari,appKit,googleDocs]=JSON.parse(readFileSync(new URL('./fixtures/foreign-clipboard-html.json',import.meta.url),'utf8'));
const blocks=slice=>slice.content.map(block=>block.type);
const runs=node=>(node.content??[]).flatMap(child=>child.type==='text'
 ?[[child.text,(child.marks??[]).map(mark=>mark.type).sort().join('+')]]:runs(child));

test('Safari: headings, b and i, inline code, links, lists and a styled paragraph',()=>{
 const {slice,normalizations}=read(safari.html);
 assert.deepEqual(blocks(slice),['heading','paragraph','bulletList','orderedList','blockquote']);
 assert.equal(slice.content[0].attrs.level,2);
 // The paragraph carries font-weight: 600 inline, so all of it is bold, as in the web
 // editor; WebKit writes the spaces between elements as non-breaking spaces.
 assert.deepEqual(runs(slice.content[1]),[['A\u00a0bold\u00a0start,\u00a0','bold'],['italic','bold+italic'],['\u00a0words,\u00a0','bold'],
  ['inline code','code'],['\u00a0and\u00a0','bold'],['a link','bold+link'],['.','bold']]);
 assert.equal(slice.content[1].content.find(node=>node.text==='a link').marks.find(mark=>mark.type==='link').attrs.href,'https://example.com/docs');
 assert.equal(slice.content[3].attrs.start,3);
 assert.deepEqual(normalizations,[{operation:'import_foreign_clipboard_html',source:'clipboard_html'}]);
});

test('Notes and Pages: AppKit HTML keeps b, i, links and list items; class styles are not read',()=>{
 const {slice}=read(appKit.html);
 assert.deepEqual(blocks(slice),['paragraph','paragraph','bulletList']);
 assert.deepEqual(runs(slice.content[1]),[['Plain, ',''],['bold','bold'],[', ',''],['italic','italic'],
  [', underlined and ',''],['a link','link'],['.','']]);
 assert.deepEqual(runs(slice.content[2]),[['First point',''],['Second point','']]);
});

test('Google Docs: the font-weight:normal b wrapper is not bold; styled spans are',()=>{
 const {slice}=read(googleDocs.html);
 assert.deepEqual(blocks(slice),['heading','paragraph','bulletList']);
 assert.deepEqual(runs(slice.content[0]),[['Agenda','']]);
 assert.deepEqual(runs(slice.content[1]),[['Bold','bold'],[' and ',''],['italic','italic'],[' text.','']]);
});

test('foreign links and images keep only destinations a paper may hold',()=>{
 const {slice}=read('<p><a href="javascript:alert(1)">script</a> <img src="data:image/png;base64,AAAA"><img src="https://example.com/a.png" alt="A"></p>');
 assert.deepEqual(runs(slice.content[0]),[['script','']]);
 assert.deepEqual(slice.content.filter(node=>node.type==='image').map(node=>node.attrs.src),['https://example.com/a.png']);
});

test('a ProseMirror slice the strict import refuses is still refused',()=>{
 assert.throws(()=>read('<p data-pm-slice="2 2 []">x</p>'));
});
