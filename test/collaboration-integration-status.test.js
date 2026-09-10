import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'
import * as Y from 'yjs'

function replica() {
  const context = { crypto: globalThis.crypto, TextEncoder, TextDecoder, console,
    setTimeout: () => 0, clearTimeout: () => {}, setInterval: () => 0, clearInterval: () => {} }
  runInNewContext(readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js', import.meta.url), 'utf8'), context)
  return (command, input = null) => JSON.parse(context.relayCollaborationCall(command, JSON.stringify(input)))
}
const complete = { hasPendingStructs: false, hasPendingDeletes: false }
function source() {
  const doc = new Y.Doc(), leaf = new Y.XmlText()
  doc.getXmlFragment('default').insert(0, [leaf]); leaf.insert(0, 'human')
  const base = Y.encodeStateAsUpdate(doc), updates = []
  doc.on('update', update => updates.push([...update]))
  return { doc, leaf, base, updates }
}

test('missing struct dependencies remain visible across checkpoint restore until baseline arrives', () => {
  const s = source(), call = replica()
  s.leaf.insert(5, '!')
  assert.deepEqual(call('integrationStatus'), complete)
  call('apply', s.updates[0])
  assert.deepEqual(call('integrationStatus'), { hasPendingStructs: true, hasPendingDeletes: false })
  const restored = replica(); restored('apply', call('state'))
  assert.deepEqual(restored('integrationStatus'), call('integrationStatus'))
  for (const r of [call, restored]) {
    r('apply', [...s.base]); assert.deepEqual(r('integrationStatus'), complete)
    assert.equal(r('resolveTextItems', r('captureTextItems', { path: [0], index: 0, length: 6 })).segments[0].text, 'human!')
  }
  s.doc.destroy()
})

test('delete-only missing dependencies are incomplete even though the state vector is unchanged', () => {
  const s = source(), call = replica(), vector = call('vector')
  s.leaf.delete(0, 5)
  call('apply', s.updates[0]); call('apply', s.updates[0])
  assert.deepEqual(call('vector'), vector)
  assert.deepEqual(call('integrationStatus'), { hasPendingStructs: false, hasPendingDeletes: true })
  const restored = replica(); restored('apply', call('state'))
  assert.deepEqual(restored('integrationStatus'), call('integrationStatus'))
  for (const r of [call, restored]) {
    r('apply', [...s.base]); assert.deepEqual(r('integrationStatus'), complete)
    assert.deepEqual(r('captureTextItems', { path: [0], index: 0, length: 0 }), { version: 1, runs: [] })
    assert.throws(() => r('captureTextItems', { path: [0], index: 0, length: 1 }))
  }
  s.doc.destroy()
})

test('mixed out-of-order dependencies settle without changing ordinary replay behavior', () => {
  const s = source(), call = replica()
  s.leaf.insert(5, '!'); s.leaf.delete(0, 5)
  call('apply', s.updates[1]); call('apply', s.updates[0])
  assert.deepEqual(call('integrationStatus'), { hasPendingStructs: true, hasPendingDeletes: true })
  call('apply', [...s.base]); call('apply', s.updates[0]); call('apply', s.updates[1])
  assert.deepEqual(call('integrationStatus'), complete)
  assert.equal(call('resolveTextItems', call('captureTextItems', { path: [0], index: 0, length: 1 })).segments[0].text, '!')
  s.doc.destroy()
})
