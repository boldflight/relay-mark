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
