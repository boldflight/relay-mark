import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {runInNewContext} from 'node:vm'
import * as Y from 'yjs'
import {packAttributionRecord,unpackAttributionRecord,packAttributionMetadata,unpackAttributionMetadata} from '../adapters/collaboration/attribution-record-codec.js'
import {placementUpdateHash} from '../adapters/collaboration/placement-lineage.js'
import {replayFormatAttribution} from '../adapters/collaboration/format-attribution-replay.js'
const fixture=JSON.parse(readFileSync(new URL('./fixtures/attributed-history-current.json',import.meta.url),'utf8'))
const recipe=JSON.parse(fixture.replay_json)
const expected=packed=>({sidecar_sha256:packed.sidecar_sha256,operation_id:packed.operation_id})
const clone=x=>JSON.parse(JSON.stringify(x))

test('all recorded placement and format steps reconstruct byte-exactly and retain complete replay meaning',()=>{
 const restored=clone(recipe)
 restored.steps=recipe.steps.map(step=>{
  const recordJSON=JSON.stringify(step),packed=packAttributionRecord(recordJSON,step.update),sidecar=JSON.parse(packed.sidecar_json)
  assert.equal(sidecar.record.update,null)
  assert.equal(packed.record_sha256,placementUpdateHash(new TextEncoder().encode(recordJSON)))
  const reopened=unpackAttributionRecord(packed.sidecar_json,step.update,expected(packed))
  assert.equal(reopened,recordJSON)
  return JSON.parse(reopened)
 })
 assert.equal(JSON.stringify(restored),fixture.replay_json)
 replayFormatAttribution(JSON.stringify(restored),fixture.expected)
})

test('wrong row bytes, operation identity, altered sidecar and unknown fields cannot reconstruct a record',()=>{
 const step=recipe.steps.find(s=>s.kind==='format'),packed=packAttributionRecord(JSON.stringify(step),step.update)
 const changed=[...step.update];changed[changed.length-1]^=1
 for(const [sidecar,bytes,expectation] of [
  [packed.sidecar_json,changed,expected(packed)],
  [packed.sidecar_json,step.update,{...expected(packed),operation_id:'00000000-0000-4000-8000-000000000000'}],
  [packed.sidecar_json+' ',step.update,expected(packed)]
 ])assert.throws(()=>unpackAttributionRecord(sidecar,bytes,expectation))
 for(const mutate of [s=>s.record.update=[],s=>s.version=2,s=>s.record_sha256='0'.repeat(64),s=>s.extra=true]){
  const altered=JSON.parse(packed.sidecar_json);mutate(altered);const json=JSON.stringify(altered)
  assert.throws(()=>unpackAttributionRecord(json,step.update,{...expected(packed),sidecar_sha256:placementUpdateHash(new TextEncoder().encode(json))}))
 }
 assert.equal(unpackAttributionRecord(packed.sidecar_json,step.update,expected(packed)),JSON.stringify(step))
})

test('codec refuses reserialization drift, malformed byte arrays and contradictory update hashes',()=>{
 const step=recipe.steps[0],json=JSON.stringify(step)
 for(const record of [JSON.stringify(step,null,2),json+' ',JSON.stringify({...step,extra:true}),JSON.stringify({...step,update:[0,0]})])assert.throws(()=>packAttributionRecord(record,step.update))
 for(const update of [[],[256],[-1],[0.5],new Uint8Array(8*1024*1024+1)])assert.throws(()=>packAttributionRecord(json,update))
 const changed=clone(step);changed.receipt.update_sha256='0'.repeat(64)
 assert.throws(()=>packAttributionRecord(JSON.stringify(changed),step.update))
})

test('large actual Yjs payload is absent from sidecar while Unicode and property order roundtrip exactly',()=>{
 const doc=new Y.Doc(),p=new Y.XmlElement('paragraph'),t=new Y.XmlText();p.insert(0,[t]);doc.getXmlFragment('default').insert(0,[p]);t.insert(0,'hello 🌍 '.repeat(10000))
 try{
  const update=[...Y.encodeStateAsUpdate(doc)]
  const receipt={contract_version:1,kind:'placement_receipt',document_id:'73000000-0000-4000-8000-000000000090',incarnation:'日本 🌍',operation_id:'73000000-0000-4000-8000-000000000001',update_sha256:placementUpdateHash(Uint8Array.from(update)),operation:{kind:'replace_prose',reference:null},copies:[]}
  const recordJSON=JSON.stringify({trust:'local',update,receipt,kind:'placement'})
  const packed=packAttributionRecord(recordJSON,update)
  assert.ok(packed.sidecar_json.length<recordJSON.length/100)
  assert.equal(unpackAttributionRecord(packed.sidecar_json,update,expected(packed)),recordJSON)
 }finally{doc.destroy()}
})

test('storage integrity is not a substitute for semantic witness validation',()=>{
 const step=clone(recipe.steps.find(s=>s.kind==='format'))
 step.event.changes[0].after.enabled=false
 const packed=packAttributionRecord(JSON.stringify(step),step.update)
 const record=JSON.parse(unpackAttributionRecord(packed.sidecar_json,step.update,expected(packed)))
 const changed=clone(recipe);changed.steps[1]=record
 const json=JSON.stringify(changed)
 assert.throws(()=>replayFormatAttribution(json,{...fixture.expected,replay_sha256:placementUpdateHash(new TextEncoder().encode(json))}))
})

test('production runtime reconstructs stored sidecars and undoes the original restored-tail fixture',()=>{
 const context={crypto:globalThis.crypto,TextEncoder,TextDecoder,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}}
 runInNewContext(readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js',import.meta.url),'utf8'),context)
 const call=(command,input=null)=>JSON.parse(context.relayCollaborationCall(command,JSON.stringify(input)))
 const rebuilt=clone(recipe)
 rebuilt.steps=recipe.steps.map(step=>{
  const packed=call('packAttributionRecord',{record_json:JSON.stringify(step),update:step.update})
  const decoded=call('unpackAttributionRecord',{sidecar_json:packed.sidecar_json,update:step.update,expected:expected(packed)})
  return JSON.parse(decoded.record_json)
 })
 assert.equal(JSON.stringify(rebuilt),fixture.replay_json)
 call('restoreHistorySnapshot',{snapshot:fixture.owner_snapshot,scope_token:fixture.expected.scope_token,transaction_ids:fixture.transaction_ids})
 const inverse=call('undoWithAttributedEvidence',{operation_id:fixture.undo_id,reference_id:fixture.reference_id,replay_json:JSON.stringify(rebuilt),expected:fixture.expected})
 assert.deepEqual(call('snapshot'),fixture.plain_snapshot)
 const packed=call('packAttributionRecord',{record_json:inverse.record_json,update:[...Y.mergeUpdates(inverse.updates.map(u=>Uint8Array.from(u)))]})
 assert.equal(packed.operation_id,fixture.undo_id)
})


test('metadata-only history roundtrips exact operation bytes without an update identity',()=>{
 const record={kind:'format_noop',event:{version:1,operation_id:'74000000-0000-4000-8000-000000000001',mark:'bold'},operation:{kind:'undo',reference:'74000000-0000-4000-8000-000000000002'}}
 const json=JSON.stringify(record),packed=packAttributionMetadata(json)
 assert.equal(unpackAttributionMetadata(packed.sidecar_json,expected(packed)),json)
 assert.equal(packed.record_sha256,placementUpdateHash(new TextEncoder().encode(json)))
 assert.equal(Object.hasOwn(packed,'update_sha256'),false)
 assert.equal(Object.hasOwn(JSON.parse(packed.sidecar_json),'update_sha256'),false)
 assert.equal(Object.hasOwn(JSON.parse(packed.sidecar_json).record,'update'),false)
 const next={...record,event:{...record.event,operation_id:'74000000-0000-4000-8000-000000000003'}}
 const second=packAttributionMetadata(JSON.stringify(next))
 assert.notEqual(second.record_sha256,packed.record_sha256)
 assert.notEqual(second.sidecar_sha256,packed.sidecar_sha256)
 assert.throws(()=>packAttributionRecord(json,[0,0]))
 assert.throws(()=>unpackAttributionRecord(packed.sidecar_json,[0,0],expected(packed)))
})

test('metadata storage rejects disguised updates, altered identity, byte drift and malformed inverse fields',()=>{
 const record={kind:'format_noop',event:{version:1,operation_id:'74000000-0000-4000-8000-000000000011',mark:'italic'},operation:{kind:'redo',reference:'74000000-0000-4000-8000-000000000010'}}
 const json=JSON.stringify(record),packed=packAttributionMetadata(json)
 for(const bad of [json+' ',JSON.stringify(record,null,2),JSON.stringify({...record,update:[]}),
  JSON.stringify({...record,event:{...record.event,update_sha256:'0'.repeat(64)}}),
  JSON.stringify({...record,event:{...record.event,version:2}}),
  JSON.stringify({...record,operation:{kind:'format',reference:record.operation.reference}}),
  JSON.stringify({...record,operation:{kind:'undo',reference:record.event.operation_id}})
 ])assert.throws(()=>packAttributionMetadata(bad))
 assert.throws(()=>unpackAttributionMetadata(packed.sidecar_json+' ',expected(packed)))
 assert.throws(()=>unpackAttributionMetadata(packed.sidecar_json,{...expected(packed),operation_id:record.operation.reference}))
 for(const mutate of [s=>s.update_sha256='0'.repeat(64),s=>s.record.update=null,s=>s.record_sha256='0'.repeat(64),s=>s.record.event.mark='bold']){
  const sidecar=JSON.parse(packed.sidecar_json);mutate(sidecar);const changed=JSON.stringify(sidecar)
  assert.throws(()=>unpackAttributionMetadata(changed,{...expected(packed),sidecar_sha256:placementUpdateHash(new TextEncoder().encode(changed))}))
 }
 const updateRecord=recipe.steps[0],ordinary=packAttributionRecord(JSON.stringify(updateRecord),updateRecord.update)
 assert.throws(()=>unpackAttributionMetadata(ordinary.sidecar_json,expected(ordinary)))
 assert.throws(()=>packAttributionMetadata(JSON.stringify(updateRecord)))
 assert.equal(unpackAttributionMetadata(packed.sidecar_json,expected(packed)),json)
})
