import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {runInNewContext} from 'node:vm'
import {build} from 'esbuild'
import {historyHookPlugin} from '../scripts/yjs-history-hook.mjs'
const id=n=>`81000000-0000-4000-8000-${String(n).padStart(12,'0')}`
const bundle=readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js',import.meta.url),'utf8')
function context(){return {crypto:globalThis.crypto,TextEncoder,TextDecoder,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}}}
function runtime(){const ctx=context();runInNewContext(bundle,ctx);return (name,input=null)=>JSON.parse(ctx.relayCollaborationCall(name,JSON.stringify(input)))}
function fixture(a=runtime(),b=runtime()){
 const seed=runtime();seed('edit',{kind:'insertNodes',path:[],index:0,nodes:[{kind:'element',name:'paragraph',children:[{kind:'text',delta:[{insert:'Hello'}]}]}]})
 const baseline=seed('state');a('apply',baseline);b('apply',baseline)
 const binding={document_id:id(99),incarnation:'one'},scope_token='qualified-no-effect-owner'
 let replay=a('createAttributionReplay',{binding,scope_token})
 const input=()=>({replay_json:replay.replay_json,expected:{scope_token,binding,replay_sha256:replay.replay_sha256,cut:replay.cut}})
 const accept=(result,peer)=>{const received=peer('applyAttributionRecord',{...input(),record_json:result.record_json});assert.equal(received.replay_json,result.replay_json);replay=result}
 const format=(owner,peer,n,value)=>{const result=owner('nativeFormattingWithAttribution',{...input(),operation:{kind:'formatText',path:[0,0],index:0,length:5,attributes:{bold:value},operation_id:id(n)}});accept(result,peer);return result}
 return {a,b,input,accept,format,scope_token,binding}
}
test('opt-in masked undo advances one owner without bytes, restores, and redo becomes effective after peer retirement',()=>{
 const h=fixture();h.format(h.a,h.b,1,{});h.format(h.b,h.a,2,null)
 const before=h.a('exportHistorySnapshot',{scope_token:h.scope_token}),bytes=h.a('state')
 for(const flags of [{},{allow_no_effect:false},{allow_no_effect:'true'},{allow_no_effect:true,reference_id:id(2)}]){
  assert.throws(()=>h.a('undoWithAttributedEvidence',{...h.input(),operation_id:id(3),...flags}))
  assert.deepEqual(h.a('exportHistorySnapshot',{scope_token:h.scope_token}),before)
 }
 const noop=h.a('undoWithAttributedEvidence',{...h.input(),operation_id:id(3),allow_no_effect:true})
 assert.deepEqual(noop.updates,[]);assert.equal(noop.kind,'formatting');assert.equal(noop.formattingMark,'bold');assert.equal(noop.cut,h.input().expected.cut)
 const record=JSON.parse(noop.record_json);assert.equal(record.kind,'format_noop');assert.equal(Object.hasOwn(record,'update'),false)
 assert.deepEqual(h.a('state'),bytes)
 const packed=h.a('packAttributionMetadata',{record_json:noop.record_json})
 assert.deepEqual(h.a('unpackAttributionMetadata',{sidecar_json:packed.sidecar_json,expected:{sidecar_sha256:packed.sidecar_sha256,operation_id:id(3)}}),{record_json:noop.record_json})
 h.accept(noop,h.b)
 const snapshot=h.a('exportHistorySnapshot',{scope_token:h.scope_token})
 assert.equal(snapshot.undo.length,0);assert.equal(snapshot.redo.length,1);assert.equal(snapshot.redo[0].operation_id,id(3));assert.deepEqual(snapshot.redo[0].insertions,[]);assert.deepEqual(snapshot.redo[0].deletions,[])
 const restored=runtime();restored('restoreHistorySnapshot',{snapshot,scope_token:h.scope_token,transaction_ids:[id(3)]})
 const peerNoop=h.b('undoWithAttributedEvidence',{...h.input(),operation_id:id(4),allow_no_effect:true});assert.deepEqual(peerNoop.updates,[]);h.accept(peerNoop,restored)
 const redo=restored('redoWithAttributedEvidence',{...h.input(),operation_id:id(5),allow_no_effect:true});assert.ok(redo.updates.length>0);h.accept(redo,h.b)
 assert.deepEqual(restored('snapshot'),h.b('snapshot'));assert.deepEqual(restored('snapshot').children[0].children[0].delta,[{insert:'Hello',attributes:{bold:{}}}])
 const fresh=runtime();fresh('restoreHistorySnapshot',{snapshot:restored('exportHistorySnapshot',{scope_token:h.scope_token}),scope_token:h.scope_token,transaction_ids:[id(5)]})
 fresh('validateAttributionReplay',h.input())
})
test('metadata-only redo and repeated undo preserve cut and distinct snapshot references',()=>{
 const h=fixture();h.format(h.a,h.b,10,{});h.format(h.b,h.a,11,null)
 const state=h.a('state')
 for(const [command,n] of [['undoWithAttributedEvidence',12],['redoWithAttributedEvidence',13],['undoWithAttributedEvidence',14]]){
  const result=h.a(command,{...h.input(),operation_id:id(n),allow_no_effect:true});assert.deepEqual(result.updates,[]);h.accept(result,h.b);assert.deepEqual(h.a('state'),state)
 }
 const saved=h.a('exportHistorySnapshot',{scope_token:h.scope_token});assert.equal(saved.redo.at(-1).operation_id,id(14))
 assert.throws(()=>h.a('redoWithAttributedEvidence',{...h.input(),operation_id:id(15),reference_id:id(12),allow_no_effect:true}))
 assert.deepEqual(h.a('exportHistorySnapshot',{scope_token:h.scope_token}),saved)
})
const notificationBuild=await build({stdin:{contents:`import * as Y from 'yjs';import {Awareness} from 'y-protocols/awareness';import {createCollaborationRuntime} from './adapters/collaboration/collaboration-runtime.js';
const doc=new Y.Doc(),root=doc.getXmlFragment('default'),origin={},manager=new Y.UndoManager(root,{trackedOrigins:new Set([origin]),captureTimeout:0}),awareness=new Awareness(doc);awareness.setLocalState(null);
const runtime=createCollaborationRuntime({doc,root,manager,localOrigin:origin,awareness});globalThis.call=runtime.call;globalThis.manager=manager;`,resolveDir:process.cwd()},plugins:[historyHookPlugin],bundle:true,write:false,format:'iife',platform:'browser',target:'es2020'})
test('throwing and reentrant observers cannot discard or partially advance a prepared no-effect result',()=>{
 const ctx=context();runInNewContext(notificationBuild.outputFiles[0].text,ctx)
 const a=(name,input=null)=>JSON.parse(JSON.stringify(ctx.call(name,input))),h=fixture(a)
 h.format(a,h.b,20,{});h.format(h.b,a,21,null)
 let nestedRefused=false,coherent=false
 ctx.manager.on('stack-item-added',()=>{
  coherent=ctx.manager.undoStack.length===0&&ctx.manager.redoStack.length===1
  try{a('undoWithAttributedEvidence',{...h.input(),operation_id:id(23),allow_no_effect:true})}catch{nestedRefused=true}
  throw Error('observer failed')
 })
 ctx.manager.on('stack-item-popped',()=>{throw Error('other observer failed')})
 const result=a('undoWithAttributedEvidence',{...h.input(),operation_id:id(22),allow_no_effect:true})
 assert.equal(result.notificationErrorCount,2);assert.equal(nestedRefused,true);assert.equal(coherent,true);assert.deepEqual(result.updates,[])
 h.accept(result,h.b)
 const saved=a('exportHistorySnapshot',{scope_token:h.scope_token});assert.equal(saved.redo.at(-1).operation_id,id(22))
})

test('masked formatting cannot discard structural counterpart metadata',()=>{
 const ctx=context();runInNewContext(notificationBuild.outputFiles[0].text,ctx)
 const a=(name,input=null)=>JSON.parse(JSON.stringify(ctx.call(name,input))),h=fixture(a)
 h.format(a,h.b,30,{});h.format(h.b,a,31,null)
 const selected=ctx.manager.undoStack.at(-1),metadata=[...selected.meta.values()].find(value=>value?.operationID===id(30))
 metadata.copies.push({source:{version:1,runs:[]},destination:{version:1,runs:[]}})
 const before=a('state'),undoCount=ctx.manager.undoStack.length
 assert.throws(()=>a('undoWithAttributedEvidence',{...h.input(),operation_id:id(32),allow_no_effect:true}),/owner reference mismatch/)
 assert.deepEqual(a('state'),before);assert.equal(ctx.manager.undoStack.length,undoCount);assert.equal(ctx.manager.undoStack.at(-1),selected);assert.equal(ctx.manager.redoStack.length,0)
})
