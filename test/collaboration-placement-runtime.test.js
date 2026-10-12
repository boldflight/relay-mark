import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {build} from 'esbuild'
import {fileURLToPath} from 'node:url'
import {runInNewContext} from 'node:vm'
import * as Y from 'yjs'
import {historyHookPlugin} from '../scripts/yjs-history-hook.mjs'
import {placementUpdateHash} from '../adapters/collaboration/placement-lineage.js'
// Expose only the existing internal dispatcher in this test build to exercise
// direct-JS object ownership without the production JSON serialization shield.
const directory=fileURLToPath(new URL('../',import.meta.url))
const source=readFileSync(new URL('../adapters/collaboration/runtime.js',import.meta.url),'utf8')
const built=await build({stdin:{contents:source+'\nglobalThis.directCall=call',resolveDir:directory+'adapters/collaboration',loader:'js'},
 bundle:true,write:false,format:'iife',platform:'browser',plugins:[historyHookPlugin]})
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`
test('direct JS cannot mutate retained local proof candidate or exported graph by alias',()=>{
 const context={crypto:globalThis.crypto,TextEncoder,TextDecoder,console,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}}
 runInNewContext(built.outputFiles[0].text,context)
 const call=context.directCall, original=new Y.Doc(),p=new Y.XmlElement('paragraph'),t=new Y.XmlText()
 p.insert(0,[t]);original.getXmlFragment('default').insert(0,[p]);t.insert(0,'Hello')
 call('apply',[...Y.encodeStateAsUpdate(original)])
 const result=call('replaceProseWithLineage',{start:2,end:2,text:'\n',operation_id:id(1)})
 const update=[...Y.mergeUpdates(result.updates.map(u=>Uint8Array.from(u)))], binding={document_id:id(2),incarnation:'one'}
 const receipt={contract_version:1,kind:'placement_receipt',...binding,operation_id:id(1),operation:{kind:'replace_prose',reference:null},
  update_sha256:placementUpdateHash(Uint8Array.from(update)),copies:JSON.parse(JSON.stringify(result.lineage.copies))}
 result.lineage.copies.length=0
 assert.throws(()=>call('preparePlacementReceipt',{expected_binding:binding,trust:'local',update,receipt:{...receipt,copies:[]}}),/runtime-proven/)
 const candidate=call('preparePlacementReceipt',{expected_binding:binding,trust:'local',update,receipt})
 const valid=JSON.parse(JSON.stringify(candidate));candidate.state.receipts[0].receipt.copies.length=0
 assert.throws(()=>call('commitPlacementReceipt',candidate),/Stale/)
 const exported=call('exportHistorySnapshot',{scope_token:'cut',placement_candidate:valid})
 exported.placement.receipts.length=0
 assert.equal(call('exportHistorySnapshot',{scope_token:'cut',placement_candidate:valid}).placement.receipts.length,1)
 call('commitPlacementReceipt',valid)
 valid.state.receipts.length=0
 const saved=call('exportHistorySnapshot',{scope_token:'cut'});saved.placement.receipts.length=0
 assert.equal(call('exportHistorySnapshot',{scope_token:'cut'}).placement.receipts.length,1)
 assert.equal(call('preparePlacementReceipt',{expected_binding:binding,trust:'local',update,receipt}).state.receipts.length,1)
 original.destroy()
})
