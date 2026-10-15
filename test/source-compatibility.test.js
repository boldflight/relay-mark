import test from 'node:test';
import assert from 'node:assert/strict';
import {importDocumentSource, documentToSnapshot, snapshotToDocument} from '../src/document-source.js';

test('CommonMark list items preserve nonparagraph first blocks behind an empty paragraph', () => {
  for (const [source, expected] of [
    ['- ', null],
    ['- # Heading\n\n  Body', 'heading'],
    ['- > Quoted', 'quote'],
    ['- - Nested', 'list'],
    ['- ```\n  code\n  ```', 'code'],
  ]) {
    const result = importDocumentSource(source, {namespace: 'historical-list'});
    const [item] = result.document.blocks[0].content;
    assert.equal(item.content[0].type, 'paragraph');
    assert.deepEqual(item.content[0].content, []);
    if (expected) assert.equal(item.content[1].type, expected); else assert.equal(item.content.length, 1);
    assert.deepEqual(importDocumentSource(source, {namespace: 'historical-list'}).document, result.document);
    assert.deepEqual(snapshotToDocument(documentToSnapshot(result.document)), result.document);
  }
});

test('a hard break inside strong text preserves the break and both marked runs', () => {
  const result = importDocumentSource('**Before  \nAfter**', {namespace: 'marked-break'});
  assert.deepEqual(result.document.blocks[0].content, [
    {type: 'strong', content: [{type: 'text', text: 'Before'}]},
    {type: 'hard_break'},
    {type: 'strong', content: [{type: 'text', text: 'After'}]},
  ]);
  assert.deepEqual(snapshotToDocument(documentToSnapshot(result.document)), result.document);
});

test('marked ordinary wiki text retains its literal source and emphasis', () => {
 const result = importDocumentSource('**[[Retained label]]**', {namespace: 'marked-wiki'});
 assert.deepEqual(result.document.blocks[0].content, [{type:'strong',content:[{type:'text',text:'[[Retained label]]'}]}]);
});

import {readFileSync} from 'node:fs';
test('source compatibility has one exact cross-runtime document and identity mapping', () => {
 const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/canonical-source-compatibility.json', import.meta.url)));
 assert.deepEqual(importDocumentSource(fixture.source,{namespace:fixture.namespace}).document,fixture.expected_ast);
});

test('marks around a canonical reference preserve its identity and neighboring text marks', () => {
 const source='**Before [[Note: 530dd8cb-3f36-47e1-925d-7969cd81aa67 | Kept note]] after**';
 const result=importDocumentSource(source,{namespace:'marked-reference'});
 const [before,reference,after]=result.document.blocks[0].content;
 assert.deepEqual(before,{type:'strong',content:[{type:'text',text:'Before '}]});
 assert.deepEqual(after,{type:'strong',content:[{type:'text',text:' after'}]});
 assert.equal(reference.type,'relay.entity_ref');
 assert.equal(reference.id,'530dd8cb-3f36-47e1-925d-7969cd81aa67');
 assert.equal(reference.label,'Kept note');
 assert.equal(reference.props.entityType,'Note');
 assert.equal(reference.props.source,'[[Note: 530dd8cb-3f36-47e1-925d-7969cd81aa67 | Kept note]]');
 assert.equal(Object.hasOwn(reference,'marks'),false);
 assert.deepEqual(snapshotToDocument(documentToSnapshot(result.document)), result.document);
});
