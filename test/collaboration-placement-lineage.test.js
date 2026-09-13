import test from 'node:test'
import assert from 'node:assert/strict'
import { digest } from 'lib0/hash/sha256'
import { createPlacementState, preparePlacementReceipt, restorePlacementState } from '../adapters/collaboration/placement-lineage.js'
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`
const binding={document_id:id(1),incarnation:'incarnation-1'}, update=[0,0]
const sha=Array.from(digest(Uint8Array.from(update)),b=>b.toString(16).padStart(2,'0')).join('')
const selection=(clock,count=1)=>({version:1,runs:[{item:{client:1,clock},type:{client:1,clock:0},count}]})
const pair=(a,b)=>({source:selection(a),destination:selection(b)})
const receipt=(n,copies=[],kind='replace_prose',reference=null)=>({version:1,...binding,update_sha256:sha,operation_id:id(n),operation:{kind,reference},copies})
const add=(state,r,trust='server')=>preparePlacementReceipt(state,{expected_binding:binding,trust,update,receipt:r})

test('immutable local and server receipt candidates retain directed inverse cycles across restart',()=>{
 const empty=createPlacementState(binding), forward=receipt(10,[pair(2,3)])
 const one=add(empty,forward,'local'); assert.equal(empty.receipts.length,0)
 const two=add(one,receipt(11,[pair(2,4)],'undo',id(10)))
 const three=add(two,receipt(12,[pair(3,5)],'redo',id(11)))
 assert.equal(one.receipts.length,1);assert.equal(three.receipts.length,3)
 // Undo derives 3->4, redo derives 4->5 through exact referenced pairs.
 assert.throws(()=>add(two,receipt(13,[pair(3,6)])),/Ambiguous/)
 assert.throws(()=>add(three,receipt(13,[pair(4,6)])),/Ambiguous/)
 assert.deepEqual(restorePlacementState(JSON.parse(JSON.stringify(three)),binding,[10,11,12].map(id)),three)
 assert.deepEqual(add(three,forward),three)
})

test('replay ignores object key order but refuses changed exact update hash',()=>{
 const one=add(createPlacementState(binding),receipt(10,[pair(2,3)]))
 const shuffled=Object.fromEntries(Object.entries(receipt(10,[pair(2,3)])).reverse())
 assert.deepEqual(add(one,shuffled),one)
 assert.throws(()=>add(one,{...shuffled,update_sha256:'a'.repeat(64)}),/hash mismatch/)
 assert.throws(()=>add(one,receipt(10,[pair(2,4)])),/Conflicting/)
 assert.equal(one.receipts.length,1)
})

test('binding trust reference and separate receipt whitelist are mandatory',()=>{
 const empty=createPlacementState(binding), r=receipt(10,[pair(2,3)])
 assert.throws(()=>preparePlacementReceipt(empty,{expected_binding:{...binding,incarnation:'other'},trust:'server',update,receipt:r}))
 assert.throws(()=>add(empty,receipt(11,[pair(2,4)],'undo',id(10))),/Unknown/)
 assert.throws(()=>add(empty,r,'implicit'))
 const one=add(empty,r)
 assert.throws(()=>restorePlacementState(one,binding,[]),/not retained/)
 assert.throws(()=>restorePlacementState(one,binding,[id(10),id(10)]))
})

test('cycles competing successors destination aliases and overlapping copies refuse atomically',()=>{
 const one=add(createPlacementState(binding),receipt(10,[pair(2,3)]))
 for(const pairs of [[pair(3,2)],[pair(2,4)],[pair(4,3)],[pair(4,5),pair(4,6)],[pair(4,5),pair(6,5)]]) {
  assert.throws(()=>add(one,receipt(11,pairs)))
 }
 assert.equal(one.receipts.length,1)
})

test('malformed identity selection and bounds refuse without truncating',()=>{
 const empty=createPlacementState(binding)
 for(const bad of [0,131073,NaN,-1]) {
  assert.throws(()=>add(empty,receipt(10,[{source:selection(2,bad),destination:selection(3,bad)}])))
 }
 assert.throws(()=>add(empty,receipt(10,Array.from({length:4097},()=>pair(2,3)))))
 assert.throws(()=>createPlacementState({...binding,incarnation:'x'.repeat(257)}))
})

test('live server admission cannot stand in for checkpoint-covered backfill without raw bytes',()=>{
 const empty=createPlacementState(binding)
 assert.throws(()=>preparePlacementReceipt(empty,{expected_binding:binding,trust:'server',update:[],receipt:receipt(10,[pair(2,3)])}),/Invalid trusted/)
 assert.equal(empty.receipts.length,0)
})


test('one item identity cannot acquire a conflicting parent type across receipts',()=>{
 const one=add(createPlacementState(binding),receipt(10,[pair(2,3)]))
 const forged=pair(3,4);forged.source.runs[0].type.clock=99
 assert.throws(()=>add(one,receipt(11,[forged])),/Conflicting placement item type/)
})


test('client identities accept the shared safe integer bound while clocks remain uint32',()=>{
 const p=pair(2,3);p.source.runs[0].item.client=Number.MAX_SAFE_INTEGER
 p.source.runs[0].type.client=Number.MAX_SAFE_INTEGER
 assert.equal(add(createPlacementState(binding),receipt(10,[p])).receipts.length,1)
 p.source.runs[0].item.client=Number.MAX_SAFE_INTEGER+1
 assert.throws(()=>add(createPlacementState(binding),receipt(10,[p])))
 p.source.runs[0].item.client=1;p.source.runs[0].item.clock=4294967296
 assert.throws(()=>add(createPlacementState(binding),receipt(10,[p])))
})

test('aggregate source and destination runs are each capped across copy pairs',()=>{
 const runs=(base,n)=>Array.from({length:n},(_,i)=>selection(base+i).runs[0])
 const make=n=>[{source:{version:1,runs:runs(10,2048)},destination:{version:1,runs:runs(10000,2048)}},
  {source:{version:1,runs:runs(3000,n)},destination:{version:1,runs:runs(14000,n)}}]
 assert.equal(add(createPlacementState(binding),receipt(10,make(2048))).receipts.length,1)
 assert.throws(()=>add(createPlacementState(binding),receipt(10,make(2049))),/aggregate run/)
})
