import test from 'node:test';
import assert from 'node:assert/strict';
import * as Y from 'yjs';
import * as observation from '../adapters/collaboration/content-edit-observer.js';
import {parseDocument,documentToSnapshot} from '../src/document-source.js';
import {node} from '../adapters/collaboration/prose-operation.js';

const footprint=(structs=[],declared_deletes=[])=>({state_vector:[{client:999,clock:100000}],structs,declared_deletes,deleted_items:[]});
const interval=(client,clock,count)=>({item:{client,clock},count});
function seed(){const local=new Y.Doc({gc:false});local.clientID=71;const root=local.getXmlFragment('default');root.insert(0,documentToSnapshot(parseDocument('A🌍Z',{namespace:'ack-delete-reconnect'})).children.map(node));const server=new Y.Doc({gc:false});Y.applyUpdate(server,Y.encodeStateAsUpdate(local));return {local,server,text:root.get(0).get(0)};}
function coverage(local,server){const vector=Y.encodeStateVector(server),outgoing=Y.encodeStateAsUpdate(local,vector),delta=Y.encodeStateAsUpdate(server,Y.encodeStateVector(local));return {outgoing,result:observation.reconciliationCoverage(observation.captureContentEditFootprint(local,outgoing),observation.captureContentEditFootprint(local,delta),vector)};}

test('acknowledged Unicode deletion reconnect has no uncovered work despite a nonempty repeated DeleteSet',()=>{
 const {local,server,text}=seed();const before=Y.encodeStateVector(local);text.delete(1,2);Y.applyUpdate(server,Y.encodeStateAsUpdate(local,before));
 const state=Y.encodeStateAsUpdate(local),vector=Y.encodeStateVector(local),{outgoing,result}=coverage(local,server);
 assert.notDeepEqual([...outgoing],[0,0]);assert.equal(Y.decodeUpdate(outgoing).structs.length,0);assert.equal(Y.decodeUpdate(outgoing).ds.clients.get(71)[0].len,2);
 assert.deepEqual(result,{covered:true,uncovered_structs:[],uncovered_deletes:[]});
 assert.deepEqual(Y.encodeStateAsUpdate(local),state);assert.deepEqual(Y.encodeStateVector(local),vector);
});

test('local footprint clocks and tombstones cannot stand in for authoritative server coverage',()=>{
 const {local,server,text}=seed();const before=Y.encodeStateVector(local);text.delete(1,2);Y.applyUpdate(server,Y.encodeStateAsUpdate(local,before));
 const allocation=Y.decodeStateVector(Y.encodeStateVector(local)).get(71);text.insert(0,'N');
 assert.deepEqual(coverage(local,server).result,{covered:false,uncovered_structs:[interval(71,allocation,1)],uncovered_deletes:[]});
 const unacked=seed(),deleted=Y.createRelativePositionFromTypeIndex(unacked.text,1).item;unacked.text.delete(1,2);
 assert.deepEqual(coverage(unacked.local,unacked.server).result,{covered:false,uncovered_structs:[],uncovered_deletes:[interval(71,deleted.clock,2)]});
});

test('partial clock and deletion coverage reports exact gaps without expanding scalar clocks',()=>{
 const outgoing=footprint([interval(7,9,5)],[interval(42,9,8),interval(100,0,2)]),server=footprint([],[interval(42,14,2),interval(42,10,2)]);
 assert.deepEqual(observation.reconciliationCoverage(outgoing,server,Y.encodeStateVector(new Map([[7,11],[42,17],[100,2]]))),{
  covered:false,uncovered_structs:[interval(7,11,3)],uncovered_deletes:[interval(42,9,1),interval(42,12,2),interval(42,16,1),interval(100,0,2)]});
 const huge=footprint([interval(42,0,2**32)]);
 assert.deepEqual(observation.reconciliationCoverage(huge,footprint(),Y.encodeStateVector(new Map([[42,2**32]]))),{covered:true,uncovered_structs:[],uncovered_deletes:[]});
});

test('malformed ranges, vector trailers and duplicated clock entries refuse coverage',()=>{
 const vector=Y.encodeStateVector(new Map([[42,11]]));
 for(const malformed of [footprint([interval(42,2**32-1,2)]),footprint([],[interval(42,2,0)]),footprint([{item:{client:-1,clock:0},count:1}])])assert.throws(()=>observation.reconciliationCoverage(malformed,footprint(),vector));
 assert.throws(()=>observation.reconciliationCoverage(footprint(),footprint(),new Uint8Array([...vector,0])));
 assert.throws(()=>observation.reconciliationCoverage(footprint(),footprint(),new Uint8Array([2,42,11,42,11])));
 assert.throws(()=>observation.reconciliationCoverage(footprint(),footprint(),[256]));
});
