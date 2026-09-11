import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'
import * as Y from 'yjs'
import { captureTextItems, resolveTextItems } from '../adapters/collaboration/text-items.js'

const bundle = readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js', import.meta.url), 'utf8')
function runtime(seed) {
  const context = { crypto: globalThis.crypto, TextEncoder, TextDecoder, console,
    setTimeout: () => 0, clearTimeout: () => {}, setInterval: () => 0, clearInterval: () => {} }
  runInNewContext(bundle, context)
  const call = (command, input = null) => JSON.parse(context.relayCollaborationCall(command, JSON.stringify(input)))
  call('apply', [...Y.encodeStateAsUpdate(seed)])
  return call
}
function seed() {
  const generated = new Y.Doc(), root = generated.getXmlFragment('default')
  const p = new Y.XmlElement('paragraph'), leaf = new Y.XmlText()
  p.insert(0, [leaf]); root.insert(0, [p]); leaf.insert(0, 'PREFIX 🌍 generated ', { bold: {} })
  const human = new Y.Doc(); Y.applyUpdate(human, Y.encodeStateAsUpdate(generated))
  human.getXmlFragment('default').get(0).get(0).insert(leaf.length, '人🌍人', { italic: {} })
  Y.applyUpdate(generated, Y.encodeStateAsUpdate(human)); human.destroy()
  return generated
}
function replay(seed, updates) {
  const doc = new Y.Doc(); Y.applyUpdate(doc, Y.encodeStateAsUpdate(seed))
  for (const update of [...updates, ...updates]) Y.applyUpdate(doc, Uint8Array.from(update))
  return doc
}
function selected(doc, selection) {
  const value = resolveTextItems(doc, doc.getXmlFragment('default'), selection)
  assert.deepEqual(value.unavailableRuns, []); assert.equal(value.collapsedUnits, 0)
  return value.segments.map(segment => segment.text).join('')
}
const decode = bytes => JSON.parse(new TextDecoder().decode(Uint8Array.from(bytes)))

test('middle split copies mixed-origin marked Unicode tail by identity, retains prefix and admits only typed text', () => {
  const original = seed(), call = runtime(original), root = original.getXmlFragment('default')
  const prefix = captureTextItems(root, { path: [0, 0], index: 0, length: 7 })
  const tail = captureTextItems(root, { path: [0, 0], index: 7, length: root.get(0).get(0).length - 7 })
  const result = call('replaceProseWithLineage', { start: 7, end: 7, text: 'typed\nnext ' })
  const doc = replay(original, result.updates)
  assert.equal(selected(doc, prefix), 'PREFIX ')
  assert.equal(selected(doc, decode(result.insertedTextItems)), 'typednext ')
  assert.equal(result.lineage.copies.length, 1)
  assert.deepEqual(result.lineage.copies[0].source, tail)
  assert.equal(selected(doc, result.lineage.copies[0].destination), '🌍 generated 人🌍人')
  assert.notDeepEqual(result.lineage.copies[0].source, result.lineage.copies[0].destination)
  const copied = doc.getXmlFragment('default').get(1).get(1)
  assert.deepEqual(copied.toDelta(), [{ insert: '🌍 generated ', attributes: { bold: {} } },
    { insert: '人🌍人', attributes: { italic: {} } }])
  assert.deepEqual(Object.keys(result.lineage.operation).sort(), ['end_anchor', 'inserted_attributes', 'inserted_text', 'kind', 'start_anchor'])
  doc.destroy(); original.destroy()
})

test('join preserves exact copied provenance and repeated operations keep one local client identity', () => {
  const original = seed(), call = runtime(original)
  const split = call('replaceProseWithLineage', { start: 7, end: 7, text: '\n' })
  const splitDoc = replay(original, split.updates), splitRoot = splitDoc.getXmlFragment('default')
  const before = captureTextItems(splitRoot, { path: [1, 0], index: 0, length: splitRoot.get(1).get(0).length })
  const firstVector = new Map(Y.decodeStateVector(Uint8Array.from(call('vector'))))
  const joined = call('replaceProseWithLineage', { start: 7, end: 8, text: '' })
  const joinedDoc = replay(splitDoc, joined.updates)
  assert.deepEqual(joined.lineage.copies[0].source, before)
  assert.equal(selected(joinedDoc, joined.lineage.copies[0].destination), '🌍 generated 人🌍人')
  assert.deepEqual(decode(joined.insertedTextItems), { version: 1, runs: [] })
  assert.deepEqual([...Y.decodeStateVector(Uint8Array.from(call('vector'))).keys()].sort(), [...firstVector.keys()].sort())
  assert.equal(joinedDoc.getXmlFragment('default').get(0).toArray().flatMap(text => text.toDelta()).map(run => run.insert).join(''),
    'PREFIX 🌍 generated 人🌍人')
  joinedDoc.destroy(); splitDoc.destroy(); original.destroy()
})

test('unsupported structural evidence and invalid scalar boundaries leave live bytes and history untouched', () => {
  const original = seed(), call = runtime(original), before = call('state')
  for (const input of [{ start: 8, end: 8, text: '' }, { start: 8, end: 8, text: '\n' }, { start: 7, end: 7, text: '\u2028' },
    { start: 7, end: 7, text: '\n', attributes: { bold: {} } }]) {
    assert.throws(() => call('replaceProseWithLineage', input))
    assert.deepEqual(call('state'), before)
  }
  assert.deepEqual(call('undo'), [])
  const nested = new Y.Doc(), quote = new Y.XmlElement('blockquote'), p = new Y.XmlElement('paragraph'), t = new Y.XmlText()
  t.insert(0, 'nested'); p.insert(0, [t]); quote.insert(0, [p]); nested.getXmlFragment('default').insert(0, [quote])
  const other = runtime(nested), old = other('state')
  assert.throws(() => other('replaceProseWithLineage', { start: 2, end: 2, text: '\n' }))
  assert.deepEqual(other('state'), old)
  nested.destroy(); original.destroy()
})
