import test from 'node:test'
import assert from 'node:assert/strict'
import {build} from 'esbuild'
import {runInNewContext} from 'node:vm'
import {historyHookPlugin} from '../scripts/yjs-history-hook.mjs'
const result=await build({stdin:{contents:`import * as Y from 'yjs'; import {Awareness} from 'y-protocols/awareness'; import {createCollaborationRuntime} from './adapters/collaboration/collaboration-runtime.js'; globalThis.api={Y,Awareness,createCollaborationRuntime}`,resolveDir:process.cwd()},plugins:[historyHookPlugin],bundle:true,write:false,format:'iife',platform:'browser',target:'es2020'})
function setup(){
 const context={crypto:globalThis.crypto,TextEncoder,TextDecoder,setInterval:()=>0,clearInterval:()=>{},setTimeout:()=>0,clearTimeout:()=>{}}
 runInNewContext(result.outputFiles[0].text,context)
 const {Y,Awareness,createCollaborationRuntime}=context.api
 const make=()=>{const doc=new Y.Doc(),root=doc.getXmlFragment('default'),localOrigin='host';const manager=new Y.UndoManager(root,{trackedOrigins:new Set([localOrigin]),captureTimeout:0});const awareness=new Awareness(doc);return {doc,root,manager,awareness,localOrigin}}
 return {Y,createCollaborationRuntime,make}
}
test('two supplied owners share exact commands without resource ownership or local peer capture',()=>{
 const {Y,createCollaborationRuntime,make}=setup(),a=make(),b=make()
 const seed=new Y.Doc(),p=new Y.XmlElement('paragraph'),t=new Y.XmlText();t.insert(0,'Hello');p.insert(0,[t]);seed.getXmlFragment('default').insert(0,[p])
 Y.applyUpdate(a.doc,Y.encodeStateAsUpdate(seed));Y.applyUpdate(b.doc,Y.encodeStateAsUpdate(seed))
 const ca=createCollaborationRuntime(a),cb=createCollaborationRuntime(b)
 const binding={document_id:'00000000-0000-4000-8000-000000000001',incarnation:'one'},scope_token='host'
 let replay=ca.call('createAttributionReplay',{binding,scope_token})
 const expected=()=>({binding,scope_token,replay_sha256:replay.replay_sha256,cut:replay.cut})
 function operation(command,args){const old=expected(),r=ca.call(command,{...args,replay_json:replay.replay_json,expected:old});const peer=cb.call('applyAttributionRecord',{record_json:r.record_json,replay_json:replay.replay_json,expected:old});assert.equal(peer.replay_json,r.replay_json);replay=r}
 operation('replaceProseWithAttribution',{operation:{start:2,end:2,text:'\n',operation_id:'00000000-0000-4000-8000-000000000002'}})
 operation('undoWithAttributedEvidence',{operation_id:'00000000-0000-4000-8000-000000000003'})
 operation('nativeFormattingWithAttribution',{operation:{kind:'formatText',path:[0,0],index:0,length:5,attributes:{bold:{}},operation_id:'00000000-0000-4000-8000-000000000004'}})
 assert.equal(b.manager.undoStack.length,0)
 const before=Y.encodeStateAsUpdate(b.doc);cb.dispose();cb.dispose()
 assert.equal(b.doc.isDestroyed,false);assert.equal(b.manager.doc,b.doc);assert.equal(b.awareness.doc,b.doc)
 assert.deepEqual(Y.encodeStateAsUpdate(b.doc),before)
 assert.throws(()=>cb.call('snapshot',null),/Disposed/)
 const replacement=createCollaborationRuntime(b);replacement.dispose();ca.dispose()
 for(const host of [a,b]){host.awareness.destroy();host.manager.destroy();host.doc.destroy()}seed.destroy()
})
test('unsupported manager is rejected without changing host policy or state',()=>{
 const {createCollaborationRuntime,make}=setup(),host=make(),filter=host.manager.deleteFilter
 host.manager.captureTimeout=100
 assert.throws(()=>createCollaborationRuntime(host),/pristine patched/)
 assert.equal(host.manager.deleteFilter,filter);assert.equal(host.manager.undoStack.length,0)
 host.awareness.destroy();host.manager.destroy();host.doc.destroy()
})
test('a second manager cannot install another runtime on the same active document',()=>{
 const {Y,createCollaborationRuntime,make}=setup(),host=make()
 const first=createCollaborationRuntime(host),filter=host.doc.gcFilter
 const other=new Y.UndoManager(host.root,{trackedOrigins:new Set([host.localOrigin]),captureTimeout:0})
 const otherFilter=other.deleteFilter
 assert.throws(()=>createCollaborationRuntime({...host,manager:other}),/pristine patched/)
 assert.equal(host.doc.gcFilter,filter);assert.equal(other.deleteFilter,otherFilter)
 assert.equal(host.doc.isDestroyed,false)
 first.dispose()
 const next=createCollaborationRuntime({...host,manager:other});next.dispose()
 other.destroy();host.manager.destroy();host.awareness.destroy();host.doc.destroy()
})
