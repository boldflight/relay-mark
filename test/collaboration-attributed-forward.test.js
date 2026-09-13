import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {runInNewContext} from 'node:vm'
import * as Y from 'yjs'
import {replayFormatAttribution} from '../adapters/collaboration/format-attribution-replay.js'
import {placementUpdateHash} from '../adapters/collaboration/placement-lineage.js'
const bundle=readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js',import.meta.url),'utf8')
const id=n=>`72000000-0000-4000-8000-${String(n).padStart(12,'0')}`
function setup(){
 const doc=new Y.Doc(),p=new Y.XmlElement('paragraph'),t=new Y.XmlText();p.insert(0,[t]);doc.getXmlFragment('default').insert(0,[p]);t.insert(0,'Hello')
 const baseline=[...Y.encodeStateAsUpdate(doc)];doc.destroy()
 const scope_token='host-qualified-journal',binding={document_id:id(90),incarnation:'forward'}
 function client(saved=null){const context={crypto:globalThis.crypto,TextEncoder,TextDecoder,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}};runInNewContext(bundle,context)
  const call=(command,input=null)=>JSON.parse(context.relayCollaborationCall(command,JSON.stringify(input)))
  if(saved)call('restoreHistorySnapshot',{snapshot:saved,scope_token,transaction_ids:[...saved.undo,...saved.redo].map(v=>v.operation_id)})
  else call('apply',baseline)
  return call
 }
 const a=client(),b=client();let replay=a('createAttributionReplay',{scope_token,binding})
 const input=()=>({replay_json:replay.replay_json,expected:{scope_token,binding,replay_sha256:replay.replay_sha256,cut:replay.cut}})
 function accept(result,peer){
  const record=JSON.parse(result.record_json),recipe=JSON.parse(result.replay_json)
  assert.deepEqual(recipe.steps.at(-1),record)
  assert.equal(record.event.update_sha256,placementUpdateHash(Y.mergeUpdates(result.updates.map(u=>Uint8Array.from(u)))))
  assert.deepEqual(record.update,[...Y.mergeUpdates(result.updates.map(u=>Uint8Array.from(u)))])
  replay=result;replayFormatAttribution(replay.replay_json,input().expected)
  for(const update of result.updates)peer('apply',update)
 }
 const format=(owner,peer,n,value,index=0,length=5)=>{const result=owner('nativeFormattingWithAttribution',{...input(),operation:{kind:'formatText',path:[0,0],index,length,attributes:{bold:value},operation_id:id(n)}});accept(result,peer);return result}
 return {a,b,client,input,format,accept,scope_token,binding,delta:owner=>owner('snapshot').children[0].children[0].delta}
}

test('native-generated baseline and forward record drive public undo/redo through owner restart',()=>{
 const h=setup(),initial=h.input(),before=h.a('state')
 assert.deepEqual(h.a('createAttributionReplay',{scope_token:h.scope_token,binding:h.binding}).replay_json,initial.replay_json)
 assert.deepEqual(h.a('state'),before)
 h.format(h.a,h.b,1,{})
 const saved=h.a('exportHistorySnapshot',{scope_token:h.scope_token}),restored=h.client(saved)
 const inverse=restored('undoWithAttributedEvidence',{...h.input(),operation_id:id(2),reference_id:id(1)});h.accept(inverse,h.b)
 assert.deepEqual(h.delta(restored),[{insert:'Hello'}])
 const again=h.client(restored('exportHistorySnapshot',{scope_token:h.scope_token}))
 const redo=again('redoWithAttributedEvidence',{...h.input(),operation_id:id(3),reference_id:id(2)});h.accept(redo,h.b)
 assert.deepEqual(h.delta(again),[{insert:'Hello',attributes:{bold:{}}}])
 assert.deepEqual(again('snapshot'),h.b('snapshot'))
})

test('two clients generate their own ordered witnesses and preserve a peer-owned middle island',()=>{
 const h=setup();h.format(h.a,h.b,10,{});h.format(h.b,h.a,11,null,2,1);h.format(h.b,h.a,12,{},2,1)
 const inverse=h.a('undoWithAttributedEvidence',{...h.input(),operation_id:id(13),reference_id:id(10)});h.accept(inverse,h.b)
 assert.deepEqual(h.delta(h.a),[{insert:'He'},{insert:'l',attributes:{bold:{}}},{insert:'lo'}])
 assert.deepEqual(h.a('snapshot'),h.b('snapshot'))
 const redo=h.a('redoWithAttributedEvidence',{...h.input(),operation_id:id(14),reference_id:id(13)});h.accept(redo,h.b)
 assert.deepEqual(h.delta(h.a),[{insert:'Hello',attributes:{bold:{}}}])
})

test('invalid forward requests, no-effects and duplicate identities refuse without changing owner history',()=>{
 const h=setup();h.format(h.a,h.b,20,{})
 const before=h.a('exportHistorySnapshot',{scope_token:h.scope_token}),saved=h.input()
 const operation={kind:'formatText',path:[0,0],index:0,length:5,attributes:{bold:null},operation_id:id(21)}
 for(const request of [
  {...saved,operation:{...operation,index:20}},
  {...saved,operation:{...operation,operation_id:id(20)}},
  {...saved,operation:{...operation,attributes:{bold:{}}}},
  {...saved,operation:{...operation,attributes:{bold:null,italic:{}}}},
  {...saved,operation,expected:{...saved.expected,cut:'0'.repeat(64)}}
 ]){
  assert.throws(()=>h.a('nativeFormattingWithAttribution',request))
  assert.deepEqual(h.a('exportHistorySnapshot',{scope_token:h.scope_token}),before)
  assert.deepEqual(h.input(),saved)
 }
 assert.throws(()=>h.a('createAttributionReplay',{scope_token:h.scope_token,binding:h.binding}),/without history/)
 assert.deepEqual(h.a('exportHistorySnapshot',{scope_token:h.scope_token}),before)
 h.format(h.a,h.b,22,null);assert.deepEqual(h.delta(h.a),[{insert:'Hello'}])
})
