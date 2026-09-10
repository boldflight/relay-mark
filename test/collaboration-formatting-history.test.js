import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'
import * as Y from 'yjs'

const bundle = readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js', import.meta.url), 'utf8')
function runtime() {
  const context = { crypto: globalThis.crypto, TextEncoder, TextDecoder, console,
    setTimeout: () => 0, clearTimeout: () => {}, setInterval: () => 0, clearInterval: () => {} }
  runInNewContext(bundle, context)
  return (command, input = null) => JSON.parse(context.relayCollaborationCall(command, JSON.stringify(input)))
}
function seed() {
  const doc = new Y.Doc()
  for (const value of ['Hello', 'World']) {
    const paragraph = new Y.XmlElement('paragraph'), text = new Y.XmlText()
    text.insert(0, value); paragraph.insert(0, [text]); doc.getXmlFragment('default').push([paragraph])
  }
  return doc
}
const bold = { kind: 'formatText', path: [0, 0], index: 0, length: 5, attributes: { bold: {} } }
test('only explicit isolated formatting follows the actual undo and redo items', () => {
  const call = runtime(), doc = seed()
  call('apply', [...Y.encodeStateAsUpdate(doc)])
  call('nativeFormatting', bold)
  const undo = call('undoWithFormattingEvidence'), redo = call('redoWithFormattingEvidence')
  assert.equal(undo.formattingMark, 'bold'); assert.ok(undo.updates.length)
  assert.equal(redo.formattingMark, 'bold'); assert.ok(redo.updates.length)
  // Legacy APIs preserve array results and do not discard inverse evidence.
  assert.ok(Array.isArray(call('undo')))
  assert.equal(call('redoWithFormattingEvidence').formattingMark, 'bold')
  const restored = runtime(); restored('apply', call('state'))
  assert.deepEqual(restored('undoWithFormattingEvidence'), { updates: [], formattingMark: null })
  doc.destroy()
})
test('generic and grouped formatting never acquire a native marker', () => {
  const call = runtime(), doc = seed()
  call('apply', [...Y.encodeStateAsUpdate(doc)])
  call('beginUndoGroup')
  call('edit', bold)
  call('edit', { ...bold, attributes: { italic: {} } })
  call('endUndoGroup')
  assert.equal(call('undoWithFormattingEvidence').formattingMark, null)
  assert.equal(call('redoWithFormattingEvidence').formattingMark, null)
  call('beginUndoGroup')
  assert.throws(() => call('nativeFormatting', bold), /isolated/)
  call('endUndoGroup')
  doc.destroy()
})
test('skipping a deleted formatting item never labels the older performed text operation', () => {
  const call = runtime(), peer = seed()
  call('apply', [...Y.encodeStateAsUpdate(peer)])
  call('edit', { kind: 'insertText', path: [1, 0], index: 5, text: '!' })
  call('nativeFormatting', bold)
  Y.applyUpdate(peer, Uint8Array.from(call('state')))
  peer.getXmlFragment('default').delete(0, 1)
  call('apply', [...Y.encodeStateAsUpdate(peer)])
  const result = call('undoWithFormattingEvidence')
  assert.equal(result.formattingMark, null)
  assert.ok(result.updates.length)
  const after = new Y.Doc(); Y.applyUpdate(after, Uint8Array.from(call('state')))
  assert.equal(after.getXmlFragment('default').get(0).get(0).toString(), 'World')
  peer.destroy(); after.destroy()
})
