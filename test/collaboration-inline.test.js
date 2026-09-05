import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'
import * as Y from 'yjs'
import { fixtureURL, swiftFixtureURL, plain } from '../scripts/collaboration-inline-conformance.mjs'
const fixture=JSON.parse(readFileSync(fixtureURL))
const bundle=readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js',import.meta.url),'utf8')
function runtime() {
  const context={crypto:globalThis.crypto,TextEncoder,TextDecoder,console,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}}
  runInNewContext(bundle,context)
  return (command,input=null)=>JSON.parse(context.relayCollaborationCall(command,JSON.stringify(input)))
}
test('mixed inline fixtures and atomic edits preserve canonical prose',()=>{
  assert.equal(readFileSync(fixtureURL,'utf8'),readFileSync(swiftFixtureURL,'utf8'))
  for (const row of fixture.cases) {
    const call=runtime();call('apply',[...Buffer.from(fixture.seed,'base64')])
    const updates=call('replaceProse',row)
    const doc=new Y.Doc()
    // Native update before its seed and duplicate replay must converge.
    for (const update of [...updates,...updates]) Y.applyUpdate(doc,Uint8Array.from(update))
    Y.applyUpdate(doc,Buffer.from(fixture.seed,'base64'))
    assert.equal(plain(doc.getXmlFragment('default')),row.expected,row.id)
    doc.destroy()
  }
})
test('mixed inline edits retain untouched XML identity under concurrent reference typing',()=>{
  const call=runtime();call('apply',[...Buffer.from(fixture.seed,'base64')])
  const anchor=call('anchor',{path:[0,3],index:0})
  const native=call('replaceProse',{start:3,end:4,text:''})
  call('apply',[...Buffer.from(fixture.remote_update,'base64')])
  assert.deepEqual(call('resolve',anchor),{path:[0,2],index:0,association:0})
  const doc=new Y.Doc();Y.applyUpdate(doc,Buffer.from(fixture.seed,'base64'));Y.applyUpdate(doc,Buffer.from(fixture.remote_update,'base64'))
  for(const update of native.reverse()) Y.applyUpdate(doc,Uint8Array.from(update))
  assert.equal(plain(doc.getXmlFragment('default')),'A🌍BC!\n\uFFFC\nD\ne\u2028f\nlet x\n')
  assert.equal(doc.getXmlFragment('default').get(0).get(2).toDelta()[0].attributes.link.href,'relay:entity/person-1')
  doc.destroy()
})
