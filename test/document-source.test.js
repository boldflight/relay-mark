import test from 'node:test';
import assert from 'node:assert/strict';
import {parseDocument,serializeDocument,projectDocumentMarkdown,renderDocument} from '../src/document-source.js';
test('canonical source imports CommonMark and directives; exact interchange retains metadata and identity',()=>{
 const source='# Title\n\n> **A** and [B](https://example.com)\n\n- [x] Task\n- [ ] Next\n\n| Name | Value |\n| --- | ---: |\n| A | B |\n\n@Callout(tone: "info", emphasis: "soft", title: "Read") {\n![Diagram](/m/asset)\n}\n';
 const ast=parseDocument(source,{namespace:'import-one'});
 assert.deepEqual(parseDocument(source,{namespace:'import-one'}),ast);
 assert.deepEqual(ast.blocks.map(x=>x.type),['heading','quote','task_list','table','relay.callout']);
 assert.equal(ast.blocks[1].content[0].content[0].type,'strong');
 ast.meta={import:'source'};
 assert.deepEqual(parseDocument(serializeDocument(ast)),ast);
 assert.match(projectDocumentMarkdown(ast),/\| Name \| Value \|/);
 assert.match(renderDocument(ast),/<strong>A<\/strong>/);
});

import {readFileSync} from 'node:fs';
test('browser CommonMark maps independent shared IDs and marked leaf expectations',()=>{const fixture=JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/canonical-source.json',import.meta.url)));assert.deepEqual(parseDocument(fixture.source,{namespace:fixture.namespace}),fixture.expected_ast);});

test('historical form comments import rich labels, original slug choices and settings into canonical nodes',()=>{
 const source='<!-- relay:question id="q1" type="multiple_choice" required="true" points="5" conditional="show-q0" -->\n**Capital?**\n- (x) Paris\n- ( ) London\n<!-- /relay:question -->\n\n<!-- relay:question id="q2" type="short_text" -->\n<!-- /relay:question -->\n';
 const [q1,q2]=parseDocument(source,{namespace:'historic-paper'}).blocks;
 assert.equal(q1.type,'relay.form_question');assert.deepEqual(q1.props,{id:'q1',type:'multiple_choice',required:true,points:5,min:null,max:null,settings:{conditional:'show-q0'}});
 assert.deepEqual(q1.content[0].content,[{type:'strong',content:[{type:'text',text:'Capital?'}]}]);assert.deepEqual(q1.content.slice(1).map(o=>[o.props.id,o.props.correct]),[['paris',true],['london',false]]);assert.equal(q2.props.id,'q2');assert.deepEqual(q2.content[0].content,[]);
});
test('authored renderer rejects executable link schemes instead of emitting clickable HTML',()=>{
 const ast=parseDocument('[Evidence](https://example.com)',{namespace:'safe-link'});
 for(const href of ['javascript:alert(1)','data:text/html,<script>','vbscript:msgbox(1)','//evil.example','https://u:p@example.com']){
  const unsafe=structuredClone(ast);unsafe.blocks[0].content[0].href=href;
  assert.throws(()=>renderDocument(unsafe),/link href/i);
 }
});

import {relayMarkToProseMirror,proseMirrorToRelayMark} from '../src/document-adapter.js';
test('generic authored claim evidence and comparison retain Unicode, IDs and table geometry',()=>{
 const ast=JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/canonical-directives.json',import.meta.url)));
 const pm=relayMarkToProseMirror(ast);assert.deepEqual(pm.content.map(n=>n.type),['relayEvidence','relayClaim','relayComparison']);
 assert.deepEqual(proseMirrorToRelayMark(pm),{type:ast.type,blocks:ast.blocks});
 assert.deepEqual(parseDocument(serializeDocument(ast)),ast);assert.match(renderDocument(ast),/<strong>Résumé 世界<\/strong>/);
 assert.match(projectDocumentMarkdown(ast),/@EvidenceRef\(/);assert.match(projectDocumentMarkdown(ast),/\| Subject \| Value \|/);
 const inline=structuredClone(ast);inline.blocks[1].content=inline.blocks[1].content[0].content;assert.throws(()=>relayMarkToProseMirror(inline));
});
