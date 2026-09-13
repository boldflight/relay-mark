import test from 'node:test'
import assert from 'node:assert/strict'
import {build} from 'esbuild'
import {runInNewContext} from 'node:vm'
import {historyHookPlugin} from '../scripts/yjs-history-hook.mjs'
const built=await build({entryPoints:['adapters/collaboration/runtime.js'],plugins:[historyHookPlugin],bundle:true,write:false,format:'iife',platform:'browser'})
test('typed multiline insertion survives actual undo and redo with exact snapshot',()=>{
 const c={crypto:globalThis.crypto,TextEncoder,TextDecoder,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}}
 runInNewContext(built.outputFiles[0].text,c)
 const call=(command,input=null)=>JSON.parse(c.relayCollaborationCall(command,JSON.stringify(input)))
 call('edit',{kind:'insertNodes',path:[],index:0,nodes:[{kind:'element',name:'paragraph',children:[{kind:'text',delta:[{insert:'Hello'}]}]}]})
 const initial=call('state'),fresh={...c};runInNewContext(built.outputFiles[0].text,fresh)
 const run=(command,input=null)=>JSON.parse(fresh.relayCollaborationCall(command,JSON.stringify(input)))
 run('apply',initial)
 const binding={document_id:'00000000-0000-4000-8000-000000000001',incarnation:'one'},scope_token='typed-redo'
 let r=run('createAttributionReplay',{binding,scope_token})
 const execute=(command,args)=>{r=run(command,{...args,replay_json:r.replay_json,expected:{binding,scope_token,replay_sha256:r.replay_sha256,cut:r.cut}});return r}
 execute('replaceProseWithAttribution',{operation:{start:2,end:2,text:'日本\n',operation_id:'00000000-0000-4000-8000-000000000002'}})
 const expected=run('snapshot')
 execute('undoWithAttributedEvidence',{operation_id:'00000000-0000-4000-8000-000000000003'})
 execute('redoWithAttributedEvidence',{operation_id:'00000000-0000-4000-8000-000000000004'})
 assert.deepEqual(run('snapshot'),expected)
})
function runtime(){
 const context={crypto:globalThis.crypto,TextEncoder,TextDecoder,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}}
 runInNewContext(built.outputFiles[0].text,context)
 return (command,input=null)=>JSON.parse(context.relayCollaborationCall(command,JSON.stringify(input)))
}
function owners(){
 const seed=runtime();seed('edit',{kind:'insertNodes',path:[],index:0,nodes:[{kind:'element',name:'paragraph',children:[{kind:'text',delta:[{insert:'Hello'}]}]}]})
 const a=runtime(),b=runtime();a('apply',seed('state'));b('apply',seed('state'))
 const binding={document_id:'00000000-0000-4000-8000-000000000011',incarnation:'one'},scope_token='retired-source'
 let replay=a('createAttributionReplay',{binding,scope_token}),n=20
 function perform(owner,peer,command,args={}){
  const operation_id=`00000000-0000-4000-8000-${String(n++).padStart(12,'0')}`, expected={binding,scope_token,replay_sha256:replay.replay_sha256,cut:replay.cut}
  const input=command==='replaceProseWithAttribution'||command==='nativeFormattingWithAttribution'?{operation:{...args,operation_id}}:{operation_id}
  const result=owner(command,{...input,replay_json:replay.replay_json,expected})
  const received=peer('applyAttributionRecord',{record_json:result.record_json,replay_json:replay.replay_json,expected})
  assert.equal(received.replay_json,result.replay_json);assert.equal(received.cut,result.cut);
  peer('validateAttributionReplay',{replay_json:received.replay_json,expected:{...expected,replay_sha256:received.replay_sha256,cut:received.cut}});
  assert.deepEqual(peer('snapshot'),owner('snapshot'));replay=result
 }
 return {a,b,perform}
}
test('selected baseline deletion undo restores exact retired identities through accepted copies',()=>{
 const {a,b,perform}=owners(),before=a('snapshot')
 perform(a,b,'replaceProseWithAttribution',{start:1,end:4,text:''})
 perform(a,b,'undoWithAttributedEvidence')
 assert.deepEqual(a('snapshot'),before)
})
test('peer formatting token on inserted text survives deletion and redo then selective peer undo',()=>{
 const {a,b,perform}=owners()
 perform(a,b,'replaceProseWithAttribution',{start:2,end:2,text:'日本\n'})
 const plain=a('snapshot')
 perform(b,a,'nativeFormattingWithAttribution',{kind:'formatText',path:[0,0],index:2,length:2,attributes:{bold:{}}})
 const marked=a('snapshot')
 perform(a,b,'undoWithAttributedEvidence')
 perform(a,b,'redoWithAttributedEvidence')
 assert.deepEqual(a('snapshot'),marked)
 perform(b,a,'undoWithAttributedEvidence')
 assert.deepEqual(a('snapshot'),plain)
})
