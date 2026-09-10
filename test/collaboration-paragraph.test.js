import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'
import * as Y from 'yjs'
import { captureTextItems, resolveTextItems } from '../adapters/collaboration/text-items.js'

const bundle = readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js', import.meta.url), 'utf8')
function runtime() {
  const context = { crypto: globalThis.crypto, TextEncoder, TextDecoder, console,
    setTimeout: () => 0, clearTimeout: () => {}, setInterval: () => 0, clearInterval: () => {} }
  runInNewContext(bundle, context)
  return (command, input = null) => JSON.parse(context.relayCollaborationCall(command, JSON.stringify(input)))
}
function seed() {
  const doc = new Y.Doc(), root = doc.getXmlFragment('default')
  for (const value of ['Generated 😀 human', 'Other']) {
    const p = new Y.XmlElement('paragraph'), text = new Y.XmlText()
    text.insert(0, value, { bold: {} }); p.insert(0, [text]); root.push([p])
  }
  return doc
}
test('native paragraph Return preserves browser identities and formatting with exactly two new units', () => {
  const call = runtime(), peer = seed(), root = peer.getXmlFragment('default')
  const old = root.toArray(), delta = old.map(p => p.get(0).toDelta())
  const human = captureTextItems(root, { path: [0, 0], index: 13, length: 5 })
  const vector = Y.encodeStateVector(peer)
  call('apply', [...Y.encodeStateAsUpdate(peer)])
  const result = call('nativeParagraphAfter', { index: 0, endUTF16: 18 })
  assert.deepEqual(result.evidence, { paragraphIndex: 0, endUTF16: 18 })
  assert.equal(result.updates.length, 1)
  Y.applyUpdate(peer, Uint8Array.from(result.updates[0]))
  Y.applyUpdate(peer, Uint8Array.from(result.updates[0]))
  assert.equal(root.length, 3); assert.equal(root.get(0), old[0]); assert.equal(root.get(2), old[1])
  assert.deepEqual([root.get(0), root.get(2)].map(p => p.get(0).toDelta()), delta)
  assert.equal(root.get(1).length, 1); assert.ok(root.get(1).get(0) instanceof Y.XmlText)
  assert.equal(root.get(1).get(0).length, 0)
  assert.equal(resolveTextItems(peer, root, human).segments.map(s => s.text).join(''), 'human')
  const decoded = Y.decodeUpdate(Y.encodeStateAsUpdate(peer, vector))
  assert.equal(decoded.structs.reduce((count, item) => count + item.length, 0), 2)
  assert.equal(decoded.ds.clients.size, 0)
  // A browser peer can immediately type in the newly created native text type.
  root.get(1).get(0).insert(0, 'New 😀')
  call('apply', [...Y.encodeStateAsUpdate(peer)])
  assert.equal(call('snapshot').children[1].children[0].delta[0].insert, 'New 😀')
  peer.destroy()
})
test('stale endpoint, nested/unsupported target and grouped calls reject without mutation', () => {
  for (const input of [{ index: 0, endUTF16: 17 }, { index: -1, endUTF16: 18 },
    { index: 10, endUTF16: 18 }, { index: 0, endUTF16: 18, inserted: '\n' }]) {
    const call = runtime(), peer = seed(); call('apply', [...Y.encodeStateAsUpdate(peer)])
    const before = call('state')
    assert.throws(() => call('nativeParagraphAfter', input))
    assert.deepEqual(call('state'), before); peer.destroy()
  }
  for (const name of ['heading', 'blockquote']) {
    const peer = new Y.Doc(), p = new Y.XmlElement(name), text = new Y.XmlText()
    text.insert(0, 'hello'); p.insert(0, [text]); peer.getXmlFragment('default').push([p])
    const call = runtime(); call('apply', [...Y.encodeStateAsUpdate(peer)])
    const before = call('state')
    assert.throws(() => call('nativeParagraphAfter', { index: 0, endUTF16: 5 }))
    assert.deepEqual(call('state'), before); peer.destroy()
  }
  const call = runtime(), peer = seed(); call('apply', [...Y.encodeStateAsUpdate(peer)])
  call('beginUndoGroup'); const before = call('state')
  assert.throws(() => call('nativeParagraphAfter', { index: 0, endUTF16: 18 }), /isolated/)
  assert.deepEqual(call('state'), before); peer.destroy()
})
test('empty paragraph Return repeats, while history never receives formatting evidence', () => {
  const call = runtime(), peer = seed(); call('apply', [...Y.encodeStateAsUpdate(peer)])
  call('nativeParagraphAfter', { index: 0, endUTF16: 18 })
  const next = call('nativeParagraphAfter', { index: 1, endUTF16: 19 })
  assert.equal(next.updates.length, 1)
  assert.equal(call('snapshot').children[2].children[0].kind, 'text')
  assert.equal(call('undoWithFormattingEvidence').formattingMark, null)
  assert.equal(call('redoWithFormattingEvidence').formattingMark, null)
  peer.destroy()
})
