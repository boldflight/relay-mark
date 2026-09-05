import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'
import * as Y from 'yjs'
import { Awareness, encodeAwarenessUpdate } from 'y-protocols/awareness'
const bundle = readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js', import.meta.url), 'utf8')
function runtime() {
  let now = Date.now()
  const intervals = []
  const context = {crypto:globalThis.crypto,TextEncoder,TextDecoder,console,setTimeout:()=>0,clearTimeout:()=>{},
    Date: class extends Date { static now() { return now } }, setInterval: fn => intervals.push(fn),clearInterval:()=>{}}
  context.relayRunIntervals = () => intervals.forEach(fn => fn())
  runInNewContext(bundle, context)
  return {call:(command,input=null)=>JSON.parse(context.relayCollaborationCall(command,JSON.stringify(input))),
    advance:ms=>{ now+=ms; intervals.forEach(fn=>fn()) }}
}
function person(id, name) {
  const doc=new Y.Doc();doc.clientID=id;const awareness=new Awareness(doc);awareness.setLocalState({user:{name}})
  return {doc,awareness,bytes:()=>[...encodeAwarenessUpdate(awareness,[id])],destroy:()=>{awareness.destroy();doc.destroy()}}
}
test('snapshot immediately seeds remote presence and equal-clock import restores exact origin removal',()=>{
  const a=person(101,'A'),b=person(102,'B');try {
    const owner=runtime().call,child=runtime().call
    owner('presenceApply',{data:a.bytes(),origin:'socket-A'});owner('presenceApply',{data:b.bytes(),origin:'socket-B'})
    const snapshot=owner('presenceSnapshot'),before=child('state')
    // Already-received identical bytes emit no awareness update; snapshot still restores origin associations.
    child('presenceApply',{data:a.bytes(),origin:'earlier-path'})
    child('presenceApplySnapshot',snapshot);child('presenceApplySnapshot',snapshot)
    assert.deepEqual(child('presenceStates').map(x=>x.name).sort(),['A','B'])
    child('presenceRemoveOrigin','socket-A')
    assert.deepEqual(child('presenceStates').map(x=>x.name),['B'])
    assert.deepEqual(child('state'),before);assert.deepEqual(child('undo'),[])
    child('presenceRemoveOrigin','socket-B');assert.deepEqual(child('presenceStates'),[])
  } finally {a.destroy();b.destroy()}
})
test('snapshot rejects invalid membership without mutation and stale import cannot claim newer state',()=>{
  const a=person(201,'A');try {
    const owner=runtime().call,child=runtime().call
    owner('presenceApply',{data:a.bytes(),origin:'old'});const snapshot=owner('presenceSnapshot')
    assert.throws(()=>child('presenceApplySnapshot',{...snapshot,origins:{bad:[999]}}));assert.deepEqual(child('presenceStates'),[])
    assert.throws(()=>child('presenceApplySnapshot',{...snapshot,origins:{}}));assert.deepEqual(child('presenceStates'),[])
    child('presenceApplySnapshot',snapshot)
    a.awareness.setLocalState({user:{name:'New A'}})
    child('presenceApply',{data:a.bytes(),origin:'new'});child('presenceApplySnapshot',snapshot)
    child('presenceRemoveOrigin','old');assert.equal(child('presenceStates')[0].name,'New A')
    child('presenceRemoveOrigin','new');assert.deepEqual(child('presenceStates'),[])
  } finally {a.destroy()}
})
test('export excludes expired and cleared clients without exporting its local presence',()=>{
  const a=person(301,'A'),b=person(302,'B');try {
    const owner=runtime();owner.call('presenceSet',{name:'Local'})
    owner.call('presenceApply',{data:a.bytes(),origin:'A'});owner.advance(20000)
    owner.call('presenceApply',{data:b.bytes(),origin:'B'});owner.advance(15000)
    const snapshot=owner.call('presenceSnapshot');assert.deepEqual(snapshot.origins,{B:[302]})
    const child=runtime().call;child('presenceApplySnapshot',snapshot);assert.deepEqual(child('presenceStates').map(x=>x.name),['B'])
    owner.call('presenceClearRemote');assert.deepEqual(owner.call('presenceSnapshot').origins,{})
  } finally {a.destroy();b.destroy()}
})

test('equal-clock conflicting snapshot cannot claim the retained current state',()=>{
  const old=person(401,'Old'),current=person(401,'Current');try {
    const source=runtime().call,child=runtime().call
    source('presenceApply',{data:old.bytes(),origin:'old'})
    child('presenceApply',{data:current.bytes(),origin:'current'})
    child('presenceApplySnapshot',source('presenceSnapshot'))
    child('presenceRemoveOrigin','old');assert.equal(child('presenceStates')[0].name,'Current')
    child('presenceRemoveOrigin','current');assert.deepEqual(child('presenceStates'),[])
  } finally {old.destroy();current.destroy()}
})
