// Standalone expected-success regression. Currently exits nonzero at the known
// restored-tail attribution gap; not included in the default test discovery.
// Run: node scripts/probe-peer-format-after-split-undo.mjs > /tmp/probe.json
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {createHash} from 'node:crypto'
import {createRequire} from 'node:module'
const yjsVersion = createRequire(import.meta.url)('yjs/package.json').version
import {runInNewContext} from 'node:vm'
import * as Y from 'yjs'
import {captureHistoryMarkerState} from '../adapters/collaboration/history-lineage.js'
const path = '../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js'
const bundle = readFileSync(new URL(path, import.meta.url), 'utf8')
const uuid = n => `30000000-0000-4000-8000-${String(n).padStart(12,'0')}`
const seed = new Y.Doc({gc:false}), p = new Y.XmlElement('paragraph'), t = new Y.XmlText()
p.insert(0,[t]);seed.getXmlFragment('default').insert(0,[p]);t.insert(0,'Hello')
function runtime() {
 const context={crypto:globalThis.crypto,TextEncoder,TextDecoder,console,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}}
 runInNewContext(bundle,context)
 const call=(command,input=null)=>JSON.parse(context.relayCollaborationCall(command,JSON.stringify(input)))
 call('apply',[...Y.encodeStateAsUpdate(seed)]);return call
}
function observation(call) {
 const doc=new Y.Doc({gc:false});Y.applyUpdate(doc,Uint8Array.from(call('state')))
 const result={paragraphs:doc.getXmlFragment('default').toArray().map(p=>p.toArray().flatMap(t=>t.toDelta())),markers:captureHistoryMarkerState(doc)}
 doc.destroy();return result
}
const a=runtime(),b=runtime(),steps=[]
function deliver(label,owner,peer,result) {
 const updates=Array.isArray(result)?result:result.updates
 for(const u of updates)peer('apply',u)
 const actual=observation(owner),replica=observation(peer)
 assert.deepEqual(actual.paragraphs,replica.paragraphs,'replicas must converge after each operation')
 steps.push({label,result,after:actual});return actual
}
deliver('A splits Hello',a,b,a('replaceProseWithLineage',{start:2,end:2,text:'\n',operation_id:uuid(1)}))
deliver('B bolds both paragraphs',b,a,b('nativeFormatting',{kind:'formatText',ranges:[{path:[0,0],index:0,length:2},{path:[1,0],index:0,length:3}],attributes:{bold:{}},operation_id:uuid(2)}))
const restored=deliver('A undoes split; B formatting survives',a,b,a('undoWithEvidence',{operation_id:uuid(3)}))
assert.deepEqual(restored.paragraphs,[[{insert:'Hello',attributes:{bold:{}}}]])
const final=deliver('B undoes own formatting after structural restoration',b,a,b('undoWithEvidence',{operation_id:uuid(4)}))
const expected=[[{insert:'Hello'}]]
console.log(JSON.stringify({fixture_kind:'real_yjs_expected_success_regression_not_server_authorization',yjs_version:yjsVersion,bundle_sha256:createHash('sha256').update(bundle).digest('hex'),initial_update_base64:Buffer.from(Y.encodeStateAsUpdate(seed)).toString('base64'),steps,expected_final_paragraphs:expected,actual_final_paragraphs:final.paragraphs},null,2))
seed.destroy()
assert.deepEqual(final.paragraphs,expected,'B formatting undo must remove its marks from the restored tail as well as retained prefix')
