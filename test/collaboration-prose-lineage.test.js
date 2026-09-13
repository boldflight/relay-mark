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

test('optional canonical host identity preserves forward wire and ordinary undo compatibility', () => {
  const original = seed(), call = runtime(original), before = call('state')
  for (const operation_id of ['', 'NOT-A-UUID', 1, null]) {
    assert.throws(() => call('replaceProseWithLineage', { start: 7, end: 7, text: 'typed', operation_id }))
    assert.deepEqual(call('state'), before)
  }
  const result = call('replaceProseWithLineage', { start: 7, end: 7, text: 'typed',
    operation_id: '10000000-0000-4000-8000-000000000001' })
  assert.equal('operation_id' in result.lineage.operation, false)
  const undo = call('undo')
  assert.ok(undo.length > 0)
  const undone = replay(original, [...result.updates, ...undo])
  assert.equal(undone.getXmlFragment('default').get(0).toArray().flatMap(text => text.toDelta()).map(run => run.insert).join(''),
    'PREFIX 🌍 generated 人🌍人')
  undone.destroy(); original.destroy()
})

const operationID = n => `20000000-0000-4000-8000-${String(n).padStart(12, '0')}`
test('durable-reference undo restores deleted and replaced text, redo references actual inverse across cycles', () => {
  for (const text of ['', 'NEW🌍']) {
    const original = seed(), call = runtime(original)
    const forward = call('replaceProseWithLineage', { start: 7, end: 20, text, operation_id: operationID(1) })
    let all = [...forward.updates], reference = operationID(1)
    let clients = null
    for (let cycle = 0; cycle < 4; cycle++) {
      const redo = cycle % 2 === 1, next = operationID(cycle + 2)
      const result = call(redo ? 'redoWithLineage' : 'undoWithLineage', { operation_id: next })
      assert.equal(result.lineage.operation.transaction_id, reference)
      assert.equal(result.lineage.operation.kind, redo ? 'redo' : 'undo')
      assert.deepEqual(decode(result.insertedTextItems), { version: 1, runs: [] })
      all.push(...result.updates)
      const restored = replay(original, all)
      const plain = restored.getXmlFragment('default').get(0).toArray().flatMap(t => t.toDelta()).map(r => r.insert).join('')
      assert.equal(plain, redo ? 'PREFIX ' + text + '人🌍人' : 'PREFIX 🌍 generated 人🌍人')
      const copied = result.lineage.copies.map(copy => selected(restored, copy.destination)).join('')
      assert.equal(copied, redo ? text : '🌍 generated ')
      const currentClients = [...Y.decodeStateVector(Uint8Array.from(call('vector'))).keys()].sort()
      if (clients) assert.deepEqual(currentClients, clients)
      else clients = currentClients // A deletion-only forward first allocates on undo.
      restored.destroy(); reference = next
    }
    original.destroy()
  }
})

test('history split/join preserves mixed-origin tail through undo/redo and peer insertion', () => {
  const original = seed(), call = runtime(original)
  const forward = call('replaceProseWithLineage', { start: 7, end: 7, text: '\n', operation_id: operationID(10) })
  const peer = replay(original, forward.updates)
  const vector = Y.encodeStateVector(peer)
  peer.getXmlFragment('default').get(0).get(0).insert(0, 'peer ')
  const peerUpdate = [...Y.encodeStateAsUpdate(peer, vector)]
  call('apply', peerUpdate)
  const undone = call('undoWithLineage', { operation_id: operationID(11) })
  const combined = replay(original, [...forward.updates, peerUpdate, ...undone.updates])
  assert.equal(combined.getXmlFragment('default').get(0).toArray().flatMap(t => t.toDelta()).map(r => r.insert).join(''),
    'peer PREFIX 🌍 generated 人🌍人')
  assert.equal(undone.lineage.copies.map(copy => selected(combined, copy.destination)).join(''), '🌍 generated 人🌍人')
  const redone = call('redoWithLineage', { operation_id: operationID(12) })
  assert.equal(redone.lineage.operation.transaction_id, operationID(11))
  peer.destroy(); combined.destroy(); original.destroy()
})

test('untracked and mixed history refuse before mutation and leave the actual history usable', () => {
  const original = seed(), call = runtime(original)
  call('replaceProse', { start: 7, end: 7, text: 'untracked' })
  const before = call('state')
  assert.throws(() => call('undoWithLineage', { operation_id: operationID(20) }))
  assert.deepEqual(call('state'), before)
  assert.ok(call('undo').length)
  const forward = call('replaceProseWithLineage', { start: 7, end: 7, text: 'tracked', operation_id: operationID(21) })
  assert.ok(forward.updates.length)
  const state = call('state')
  assert.throws(() => call('undoWithLineage', { operation_id: operationID(21) }))
  assert.deepEqual(call('state'), state)
  assert.ok(call('undoWithLineage', { operation_id: operationID(22) }).updates.length)
  original.destroy()
})

test('ineffective tracked top item cannot silently consume an earlier operation during preflight', () => {
  const original = seed(), call = runtime(original)
  call('replaceProseWithLineage', { start: 0, end: 0, text: 'A', operation_id: operationID(30) })
  call('replaceProseWithLineage', { start: 0, end: 0, text: 'B', operation_id: operationID(31) })
  const peer = new Y.Doc(); Y.applyUpdate(peer, Uint8Array.from(call('state')))
  const vector = Y.encodeStateVector(peer)
  peer.getXmlFragment('default').get(0).get(0).delete(0, 1)
  call('apply', [...Y.encodeStateAsUpdate(peer, vector)])
  const before = call('state')
  assert.throws(() => call('undoWithLineage', { operation_id: operationID(32) }))
  assert.deepEqual(call('state'), before)
  // The ordinary API still sees both original stack entries and skips B to undo A.
  assert.ok(call('undo').length)
  const value = new Y.Doc(); Y.applyUpdate(value, Uint8Array.from(call('state')))
  assert.equal(value.getXmlFragment('default').get(0).toArray().flatMap(t => t.toDelta()).map(run => run.insert).join(''),
    'PREFIX 🌍 generated 人🌍人')
  value.destroy(); peer.destroy(); original.destroy()
})

test('split undo keeps remote descendants visible and redo converges without duplicating them', () => {
  for (const at of [0, 2]) {
    const original = seed(), call = runtime(original)
    const forward = call('replaceProseWithLineage', { start: 7, end: 7, text: '\n', operation_id: operationID(40) })
    const peer = replay(original, forward.updates), vector = Y.encodeStateVector(peer)
    peer.getXmlFragment('default').get(1).get(0).insert(at, 'PEER')
    const remote = [...Y.encodeStateAsUpdate(peer, vector)]
    call('apply', remote)
    const updates = [...forward.updates, remote]
    for (let n = 0; n < 4; n++) {
      const redo = n % 2 === 1
      const result = call(redo ? 'redoWithLineage' : 'undoWithLineage', { operation_id: operationID(41 + n) })
      updates.push(...result.updates)
      const doc = replay(original, updates), paragraphs = doc.getXmlFragment('default').toArray()
        .map(p => p.toArray().flatMap(t => t.toDelta()).map(run => run.insert).join(''))
      assert.equal(paragraphs.join('').split('PEER').length - 1, 1)
      if (!redo) assert.deepEqual(paragraphs, ['PREFIX 🌍 generated 人🌍人', 'PEER'])
      else assert.deepEqual(paragraphs, ['PREFIX ', at === 0 ? 'PEER🌍 generated 人🌍人' : '🌍PEER generated 人🌍人'])
      for (const bytes of result.updates) Y.applyUpdate(peer, Uint8Array.from(bytes))
      assert.deepEqual(peer.getXmlFragment('default').toArray().map(p => p.toArray().flatMap(t => t.toDelta()).map(run => run.insert).join('')), paragraphs)
      doc.destroy()
    }
    peer.destroy(); original.destroy()
  }
})

test('join undo preserves peer suffix in retained leaf through inverse cycles', () => {
  const original = seed(), call = runtime(original)
  const split = call('replaceProseWithLineage', { start: 7, end: 7, text: '\n', operation_id: operationID(50) })
  const join = call('replaceProseWithLineage', { start: 7, end: 8, text: '', operation_id: operationID(51) })
  const peer = replay(original, [...split.updates, ...join.updates]), vector = Y.encodeStateVector(peer)
  const p = peer.getXmlFragment('default').get(0), leaf = p.get(p.length - 1)
  leaf.insert(leaf.length, 'PEER')
  const remote = [...Y.encodeStateAsUpdate(peer, vector)]; call('apply', remote)
  const updates = [...split.updates, ...join.updates, remote]
  for (let n = 0; n < 4; n++) {
    const result = call(n % 2 ? 'redoWithLineage' : 'undoWithLineage', { operation_id: operationID(52 + n) })
    updates.push(...result.updates)
    const doc = replay(original, updates)
    const paragraphs = doc.getXmlFragment('default').toArray().map(p => p.toArray().flatMap(t => t.toDelta()).map(run => run.insert).join(''))
    assert.deepEqual(paragraphs, n % 2 ? ['PREFIX 🌍 generated 人🌍人PEER'] : ['PREFIX PEER', '🌍 generated 人🌍人'])
    doc.destroy()
  }
  peer.destroy(); original.destroy()
})

function paragraphAttributes(doc, paragraphIndex, offset) {
  for (const leaf of doc.getXmlFragment('default').get(paragraphIndex).toArray()) {
    for (const run of leaf.toDelta()) {
      if (offset < run.insert.length) return run.attributes || {}
      offset -= run.insert.length
    }
  }
  throw Error('Missing test text')
}

test('copied Unicode retains current peer mark additions/removals across inverse cycles in one receipt', () => {
  for (const attributes of [{ italic: {} }, { bold: null }]) {
    const original = seed(), call = runtime(original)
    call('replaceProseWithLineage', { start: 7, end: 7, text: '\n', operation_id: operationID(60) })
    let expected = attributes.bold === null ? {} : { bold: {}, italic: {} }
    function peerFormat(paragraph, offset, marks) {
      const peer = new Y.Doc({ gc: false }); Y.applyUpdate(peer, Uint8Array.from(call('state')))
      const vector = Y.encodeStateVector(peer), p = peer.getXmlFragment('default').get(paragraph)
      let index = offset
      for (const leaf of p.toArray()) {
        if (index < leaf.length) { leaf.format(index, 2, marks); break }
        index -= leaf.length
      }
      call('apply', [...Y.encodeStateAsUpdate(peer, vector)]); peer.destroy()
    }
    peerFormat(1, 0, attributes)
    for (let cycle = 0; cycle < 4; cycle++) {
      const redo = cycle % 2 === 1
      const before = call('state')
      const result = call(redo ? 'redoWithLineage' : 'undoWithLineage', { operation_id: operationID(61 + cycle) })
      assert.equal(result.updates.length, 1)
      const doc = new Y.Doc({ gc: false }); Y.applyUpdate(doc, Uint8Array.from(before))
      for (const bytes of [...result.updates, ...result.updates]) Y.applyUpdate(doc, Uint8Array.from(bytes))
      assert.deepEqual(paragraphAttributes(doc, redo ? 1 : 0, redo ? 0 : 7), expected)
      assert.equal(result.lineage.operation.transaction_id, operationID(60 + cycle))
      assert.deepEqual(decode(result.insertedTextItems), { version: 1, runs: [] })
      doc.destroy()
      if (cycle === 0) {
        // A peer changes the restored source before redo. Current marks must
        // flow back to the copied destination, not the old cached attributes.
        peerFormat(0, 7, { italic: null, strike: {} })
        const { italic, ...retained } = expected; expected = { ...retained, strike: {} }
      }
    }
    original.destroy()
  }
})

test('peer text surviving copied ancestor undo retains its current inherited marks', () => {
  const original = seed(), call = runtime(original)
  call('replaceProseWithLineage', { start: 7, end: 7, text: '\n', operation_id: operationID(70) })
  const peer = new Y.Doc(); Y.applyUpdate(peer, Uint8Array.from(call('state')))
  const vector = Y.encodeStateVector(peer)
  peer.getXmlFragment('default').get(1).get(0).insert(2, 'PEER')
  call('apply', [...Y.encodeStateAsUpdate(peer, vector)])
  const result = call('undoWithLineage', { operation_id: operationID(71) })
  assert.equal(result.updates.length, 1)
  const doc = new Y.Doc(); Y.applyUpdate(doc, Uint8Array.from(call('state')))
  assert.deepEqual(paragraphAttributes(doc, 1, 0), { bold: {} })
  peer.destroy(); doc.destroy(); original.destroy()
})
