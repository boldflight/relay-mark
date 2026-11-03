// The empty document is valid everywhere: an empty fragment, an empty AST and an empty body agree.
// spec/relaymark/editor/empty-document-v1.json is shared with the Rust engine, the Elixir adapter and Swift.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {documentToSnapshot,snapshotToDocument,normalizeDocument,projectDocumentMarkdown,renderDocument,serializeDocument,parseDocument} from '../src/document-source.js';

const {cases}=JSON.parse(readFileSync(new URL('../spec/relaymark/editor/empty-document-v1.json',import.meta.url)));
const jobs={
 to_snapshot:documentToSnapshot,
 from_snapshot:snapshotToDocument,
 normalize:normalizeDocument,
 project:document=>({body:projectDocumentMarkdown(document),body_html:renderDocument(document)}),
};

test('the fixture has the cases this runtime runs',()=>{assert.equal(cases.length,4);});
for(const {name,job,input,expected} of cases)test(name,()=>{assert.deepEqual(jobs[job](structuredClone(input)),expected);});

// Keep: a Today paper whose body is empty must still serialize to its stored source and round trip.
test('the empty document serializes and parses back',()=>{
 assert.deepEqual(parseDocument(serializeDocument({type:'relaymark.document',blocks:[]})).blocks,[]);
});

// Keep: skipping the doc content check must not skip the envelope's metadata validation.
test('an empty document still refuses invalid metadata',()=>{
 assert.throws(()=>normalizeDocument({type:'relaymark.document',blocks:[],meta:'not an object'}));
 assert.throws(()=>normalizeDocument({type:'relaymark.document'}));
});
