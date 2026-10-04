import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'
import * as Y from 'yjs'
import { placementUpdateHash } from '../adapters/collaboration/placement-lineage.js'
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
  assert.deepEqual(result.lineage.operation.start_anchor,JSON.parse(JSON.stringify(Y.relativePositionToJSON(Y.createRelativePositionFromTypeIndex(root.get(0).get(0),7,0)))))
  const doc = replay(original, result.updates)
  assert.equal(selected(doc, prefix), 'PREFIX ')
  assert.equal(selected(doc, decode(result.insertedTextItems)), 'typednext ')
  assert.equal(result.lineage.copies.length, 1)
  assert.deepEqual(result.lineage.copies[0].source, tail)
  assert.equal(selected(doc, result.lineage.copies[0].destination), '🌍 generated 人🌍人')
  assert.notDeepEqual(result.lineage.copies[0].source, result.lineage.copies[0].destination)
  const copied = doc.getXmlFragment('default').get(1).get(0)
  assert.deepEqual(copied.toDelta(), [{ insert: 'next ' }, { insert: '🌍 generated ', attributes: { bold: {} } },
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
  assert.deepEqual(decode(joined.insertedTextItems), { runs: [] })
  assert.deepEqual([...Y.decodeStateVector(Uint8Array.from(call('vector'))).keys()].sort(), [...firstVector.keys()].sort())
  assert.equal(joinedDoc.getXmlFragment('default').get(0).toArray().flatMap(text => text.toDelta()).map(run => run.insert).join(''),
    'PREFIX 🌍 generated 人🌍人')
  joinedDoc.destroy(); splitDoc.destroy(); original.destroy()
})

test('unsupported structural evidence and invalid scalar boundaries leave live bytes and history untouched', () => {
  const original = seed(), call = runtime(original), before = call('state')
  for (const input of [{ start: 8, end: 8, text: '' }, { start: 8, end: 8, text: '\n' }, { start: 7, end: 7, text: '\u2028' },
    { start: 7, end: 7, text: '\n', attributes: { strike: {} } }]) {
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
      assert.deepEqual(decode(result.insertedTextItems), { runs: [] })
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

test('ineffective tracked top item skips to the actual earlier operation with its exact reference', () => {
  const original = seed(), call = runtime(original)
  call('replaceProseWithLineage', { start: 0, end: 0, text: 'A', operation_id: operationID(30) })
  call('replaceProseWithLineage', { start: 0, end: 0, text: 'B', operation_id: operationID(31) })
  const peer = new Y.Doc(); Y.applyUpdate(peer, Uint8Array.from(call('state')))
  const vector = Y.encodeStateVector(peer)
  peer.getXmlFragment('default').get(0).get(0).delete(0, 1)
  call('apply', [...Y.encodeStateAsUpdate(peer, vector)])
  const result = call('undoWithLineage', { operation_id: operationID(32) })
  assert.equal(result.lineage.operation.transaction_id, operationID(30))
  assert.equal(result.updates.length, 1)
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
      assert.deepEqual(decode(result.insertedTextItems), { runs: [] })
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

test('qualified durable history survives pristine restart, peer updates and a second undo/redo restart', () => {
  const original = seed(), call = runtime(original)
  call('replaceProseWithLineage', { start: 7, end: 7, text: '\n', operation_id: operationID(80) })
  const peer = new Y.Doc(); Y.applyUpdate(peer, Uint8Array.from(call('state')))
  let vector = Y.encodeStateVector(peer)
  const copied = peer.getXmlFragment('default').get(1).get(0)
  copied.format(0, 2, { italic: {} }); copied.insert(2, 'PEER')
  call('apply', [...Y.encodeStateAsUpdate(peer, vector)])
  const first = call('exportHistorySnapshot', { scope_token: 'account/doc/incarnation|cut:80' })
  const pristine = new Y.Doc(), resumed = runtime(pristine)
  resumed('restoreHistorySnapshot', { snapshot: first, scope_token: first.scope_token, transaction_ids: [operationID(80)] })
  assert.deepEqual(resumed('state'), first.state_update)
  // A fresh peer update arrives after bootstrap, through the unchanged apply API.
  vector = Y.encodeStateVector(peer); peer.getXmlFragment('default').get(0).get(0).insert(0, 'PREFIX-PEER ')
  resumed('apply', [...Y.encodeStateAsUpdate(peer, vector)])
  const undone = resumed('undoWithLineage', { operation_id: operationID(81) })
  assert.equal(undone.lineage.operation.transaction_id, operationID(80))
  const undoneDoc = new Y.Doc(); Y.applyUpdate(undoneDoc, Uint8Array.from(resumed('state')))
  assert.deepEqual(undoneDoc.getXmlFragment('default').toArray().map(p => p.toArray().flatMap(t => t.toDelta()).map(run => run.insert).join('')),
    ['PREFIX-PEER PREFIX 🌍 generated 人🌍人', 'PEER'])
  assert.deepEqual(paragraphAttributes(undoneDoc, 0, 19), { bold: {}, italic: {} })
  const second = resumed('exportHistorySnapshot', { scope_token: 'account/doc/incarnation|cut:81' })
  assert.notEqual(second.client_id, first.client_id)
  const again = runtime(pristine)
  again('restoreHistorySnapshot', { snapshot: second, scope_token: second.scope_token, transaction_ids: [operationID(81)] })
  const redone = again('redoWithLineage', { operation_id: operationID(82) })
  assert.equal(redone.lineage.operation.transaction_id, operationID(81))
  const redoneDoc = new Y.Doc(); Y.applyUpdate(redoneDoc, Uint8Array.from(again('state')))
  assert.deepEqual(redoneDoc.getXmlFragment('default').toArray().map(p => p.toArray().flatMap(t => t.toDelta()).map(run => run.insert).join('')),
    ['PREFIX-PEER PREFIX ', '🌍PEER generated 人🌍人'])
  assert.deepEqual(paragraphAttributes(redoneDoc, 1, 0), { bold: {}, italic: {} })
  redoneDoc.destroy(); undoneDoc.destroy(); peer.destroy(); pristine.destroy(); original.destroy()
})

test('history snapshot refuses wrong scope, unknown receipts, corrupted metadata and nonpristine replacement atomically', () => {
  const original = seed(), call = runtime(original)
  call('replaceProseWithLineage', { start: 7, end: 20, text: 'NEW', operation_id: operationID(90) })
  call('undoWithLineage', { operation_id: operationID(91) })
  const snapshot = call('exportHistorySnapshot', { scope_token: 'qualified|cut:91' })
  const pristine = new Y.Doc(), target = runtime(pristine), before = target('state')
  const args = { snapshot, scope_token: snapshot.scope_token, transaction_ids: [operationID(91)] }
  const missing = structuredClone(snapshot); missing.retained[0].length = 4294967296
  const cycle = structuredClone(snapshot); assert.ok(cycle.redone.length); cycle.redone[0].target = cycle.redone[0].item
  for (const attempt of [{ ...args, scope_token: 'other-account|cut:91' }, { ...args, transaction_ids: [] },
    { ...args, snapshot: missing }, { ...args, snapshot: cycle }]) {
    assert.throws(() => target('restoreHistorySnapshot', attempt))
    assert.deepEqual(target('state'), before)
    assert.deepEqual(target('undo'), [])
  }
  target('restoreHistorySnapshot', args)
  const restored = target('state')
  assert.throws(() => target('restoreHistorySnapshot', args))
  assert.deepEqual(target('state'), restored)
  assert.ok(target('redoWithLineage', { operation_id: operationID(92) }).updates.length)
  pristine.destroy(); original.destroy()
})

test('deleted content lost by ordinary GC cannot be accepted as a restorable history checkpoint', () => {
  const original = seed(), call = runtime(original)
  call('replaceProseWithLineage', { start: 7, end: 20, text: '', operation_id: operationID(100) })
  const snapshot = call('exportHistorySnapshot', { scope_token: 'qualified|cut:100' })
  const lossy = new Y.Doc(); Y.applyUpdate(lossy, Uint8Array.from(snapshot.state_update))
  const corrupted = structuredClone(snapshot); corrupted.state_update = [...Y.encodeStateAsUpdate(lossy)]
  const pristine = new Y.Doc(), target = runtime(pristine), before = target('state')
  assert.throws(() => target('restoreHistorySnapshot', { snapshot: corrupted, scope_token: snapshot.scope_token, transaction_ids: [operationID(100)] }))
  assert.deepEqual(target('state'), before)
  target('restoreHistorySnapshot', { snapshot, scope_token: snapshot.scope_token, transaction_ids: [operationID(100)] })
  assert.ok(target('undoWithLineage', { operation_id: operationID(101) }).updates.length)
  lossy.destroy(); pristine.destroy(); original.destroy()
})

test('host-identified ordinary formatting survives restart with existing formatting evidence', () => {
  const original = seed(), call = runtime(original)
  const before = call('state')
  assert.throws(() => call('nativeFormatting', { kind: 'formatText', path: [0, 0], index: 0, length: 6,
    attributes: { bold: null }, operation_id: 'invented' }))
  assert.deepEqual(call('state'), before)
  call('nativeFormatting', { kind: 'formatText', path: [0, 0], index: 0, length: 6,
    attributes: { bold: null }, operation_id: operationID(110) })
  const snapshot = call('exportHistorySnapshot', { scope_token: 'format|cut:110' })
  assert.equal(snapshot.undo[0].formatting_mark, 'bold')
  assert.deepEqual(snapshot.undo[0].inserted_text_items, { runs: [] })
  const empty = new Y.Doc(), restored = runtime(empty)
  restored('restoreHistorySnapshot', { snapshot, scope_token: snapshot.scope_token, transaction_ids: [operationID(110)] })
  const state = restored('state')
  assert.throws(() => restored('undoWithLineage', { operation_id: operationID(111) }))
  assert.deepEqual(restored('state'), state)
  const result = restored('undoWithFormattingEvidence', { operation_id: operationID(111) })
  assert.equal(result.formattingMark, 'bold')
  const decoded = new Y.Doc(); Y.applyUpdate(decoded, Uint8Array.from(restored('state')))
  assert.deepEqual(paragraphAttributes(decoded, 0, 0), { bold: {} })
  const inverse = restored('exportHistorySnapshot', { scope_token: 'format|cut:111' })
  assert.equal(inverse.redo[0].operation_id, operationID(111))
  const again = runtime(empty)
  again('restoreHistorySnapshot', { snapshot: inverse, scope_token: inverse.scope_token, transaction_ids: [operationID(111)] })
  assert.equal(again('redoWithFormattingEvidence', { operation_id: operationID(113) }).formattingMark, 'bold')
  assert.equal(again('exportHistorySnapshot', { scope_token: 'format|cut:113' }).undo[0].operation_id, operationID(113))
  // The legacy inverse has no host-assigned ID; it must not invent one.
  again('undoWithFormattingEvidence')
  assert.throws(() => again('exportHistorySnapshot', { scope_token: 'format|cut:114' }))
  decoded.destroy(); empty.destroy(); original.destroy()
})

test('tracked inline replacement retains exact typed item evidence in its durable stack', () => {
  const original = seed(), call = runtime(original)
  const result = call('replaceProseWithLineage', { start: 0, end: 6, text: '日本🌍', operation_id: operationID(112) })
  const snapshot = call('exportHistorySnapshot', { scope_token: 'inline|cut:112' })
  const typed = JSON.parse(new TextDecoder().decode(Uint8Array.from(result.insertedTextItems)))
  assert.deepEqual(snapshot.undo[0].inserted_text_items, typed)
  const empty = new Y.Doc(), restored = runtime(empty)
  restored('restoreHistorySnapshot', { snapshot, scope_token: snapshot.scope_token, transaction_ids: [operationID(112)] })
  assert.deepEqual(restored('exportHistorySnapshot', { scope_token: snapshot.scope_token }).undo[0].inserted_text_items, typed)
  empty.destroy(); original.destroy()
})

test('unified history dispatch preserves actual prose and formatting evidence modes', () => {
  const original = seed(), call = runtime(original)
  call('replaceProseWithLineage', { start: 6, end: 6, text: '!', operation_id: operationID(120) })
  call('nativeFormatting', { kind: 'formatText', path: [0, 0], index: 0, length: 6,
    attributes: { bold: null }, operation_id: operationID(121) })
  const format = call('undoWithEvidence', { operation_id: operationID(122) })
  assert.equal(format.kind, 'formatting'); assert.equal(format.formattingMark, 'bold'); assert.equal(format.lineage, null)
  const prose = call('undoWithEvidence', { operation_id: operationID(123) })
  assert.equal(prose.kind, 'prose'); assert.equal(prose.formattingMark, null)
  assert.equal(prose.lineage.operation.transaction_id, operationID(120))
  assert.equal(call('redoWithEvidence', { operation_id: operationID(124) }).kind, 'prose')
  assert.equal(call('redoWithEvidence', { operation_id: operationID(125) }).kind, 'formatting')
  original.destroy()
})


test('unified history skips obsolete prose to formatting and leaves peer text untouched', () => {
  const original = seed(), call = runtime(original)
  call('nativeFormatting', { kind: 'formatText', path: [0, 0], index: 0, length: 6,
    attributes: { bold: null }, operation_id: operationID(130) })
  call('replaceProseWithLineage', { start: 0, end: 0, text: 'X', operation_id: operationID(131) })
  const peer = new Y.Doc(); Y.applyUpdate(peer, Uint8Array.from(call('state')))
  const vector = Y.encodeStateVector(peer), leaf = peer.getXmlFragment('default').get(0).get(0)
  leaf.delete(0, 1); leaf.insert(6, 'PEER', { italic: {} })
  call('apply', [...Y.encodeStateAsUpdate(peer, vector)])
  const result = call('undoWithEvidence', { operation_id: operationID(132) })
  assert.equal(result.kind, 'formatting'); assert.equal(result.formattingMark, 'bold')
  const value = new Y.Doc(); Y.applyUpdate(value, Uint8Array.from(call('state')))
  assert.equal(value.getXmlFragment('default').get(0).get(0).toDelta().map(run => run.insert).join(''), 'PREFIXPEER 🌍 generated 人🌍人')
  assert.deepEqual(paragraphAttributes(value, 0, 6), { italic: {} })
  const snapshot = call('exportHistorySnapshot', { scope_token: 'skip|132' })
  assert.equal(snapshot.redo[0].operation_id, operationID(132))
  assert.equal(call('redoWithEvidence', { operation_id: operationID(133) }).kind, 'formatting')
  value.destroy(); peer.destroy(); original.destroy()
})

test('skipping to an actionable untracked item refuses before changing live history', () => {
  const original = seed(), call = runtime(original)
  call('replaceProse', { start: 0, end: 0, text: 'A' })
  call('replaceProseWithLineage', { start: 0, end: 0, text: 'B', operation_id: operationID(140) })
  const peer = new Y.Doc(); Y.applyUpdate(peer, Uint8Array.from(call('state')))
  const vector = Y.encodeStateVector(peer)
  peer.getXmlFragment('default').get(0).get(0).delete(0, 1)
  call('apply', [...Y.encodeStateAsUpdate(peer, vector)])
  const before = call('state')
  assert.throws(() => call('undoWithEvidence', { operation_id: operationID(141) }))
  assert.deepEqual(call('state'), before)
  assert.ok(call('undo').length)
  peer.destroy(); original.destroy()
})

test('legacy formatting snapshots without exact target identities cannot authorize a broad mark reversal', () => {
  const original = seed(), call = runtime(original)
  call('nativeFormatting', { kind: 'formatText', path: [0, 0], index: 0, length: 6,
    attributes: { bold: null }, operation_id: operationID(150) })
  const snapshot = call('exportHistorySnapshot', { scope_token: 'format|150' })
  delete snapshot.undo[0].formatting_text_items
  const empty = new Y.Doc(), restored = runtime(empty), before = restored('state')
  assert.throws(() => restored('restoreHistorySnapshot', { snapshot, scope_token: snapshot.scope_token, transaction_ids: [operationID(150)] }))
  assert.deepEqual(restored('state'), before)
  empty.destroy(); original.destroy()
})


test('two pristine restores keep distinct session IDs and concurrent edits and selective undo converge', () => {
  const original = seed(), call = runtime(original)
  call('replaceProseWithLineage', { start: 0, end: 0, text: 'OLD', operation_id: operationID(160) })
  const snapshot = call('exportHistorySnapshot', { scope_token: 'owner|160' }), empty = new Y.Doc()
  const a = runtime(empty), b = runtime(empty)
  const canonical = owner => {
    const copy = new Y.Doc(); Y.applyUpdate(copy, Uint8Array.from(owner('state')))
    const bytes = [...Y.encodeStateAsUpdate(copy)]; copy.destroy(); return bytes
  }
  for (const owner of [a, b]) owner('restoreHistorySnapshot', { snapshot, scope_token: snapshot.scope_token, transaction_ids: [operationID(160)] })
  const aID = a('exportHistorySnapshot', { scope_token: 'a' }).client_id
  const bID = b('exportHistorySnapshot', { scope_token: 'b' }).client_id
  assert.notEqual(aID, bID); assert.notEqual(aID, snapshot.client_id); assert.notEqual(bID, snapshot.client_id)
  const left = a('replaceProseWithLineage', { start: 0, end: 0, text: 'A', operation_id: operationID(161) })
  const right = b('replaceProseWithLineage', { start: 0, end: 0, text: 'B', operation_id: operationID(162) })
  for (const update of left.updates) b('apply', update)
  for (const update of right.updates) a('apply', update)
  assert.deepEqual(canonical(a), canonical(b))
  const undoA = a('undoWithEvidence', { operation_id: operationID(163) })
  for (const update of undoA.updates) b('apply', update)
  assert.deepEqual(canonical(a), canonical(b))
  const undoB = b('undoWithEvidence', { operation_id: operationID(164) })
  for (const update of undoB.updates) a('apply', update)
  assert.deepEqual(canonical(a), canonical(b))
  const value = new Y.Doc(); Y.applyUpdate(value, Uint8Array.from(a('state')))
  assert.equal(value.getXmlFragment('default').get(0).get(0).toDelta().map(run => run.insert).join(''), 'OLDPREFIX 🌍 generated 人🌍人')
  // An old high awareness clock must not suppress the new session's first state.
  const receiver = runtime(empty)
  for (let i = 0; i < 20; i++) for (const data of call('presenceSet', { name: `Old ${i}` })) receiver('presenceApply', { data, origin: 'old' })
  for (const data of call('presenceSet', null)) receiver('presenceApply', { data, origin: 'old' })
  for (const data of a('presenceSet', { name: 'Restored' })) receiver('presenceApply', { data, origin: 'new' })
  assert.deepEqual(receiver('presenceStates').map(value => value.name), ['Restored'])
  value.destroy(); empty.destroy(); original.destroy()
})

test('multi-paragraph formatting is one tracked update and protects peer marks through undo', () => {
  const original = seed(), call = runtime(original)
  call('replaceProseWithLineage', { start: 7, end: 7, text: '\n', operation_id: operationID(170) })
  const before = call('state')
  assert.throws(() => call('nativeFormatting', { kind: 'formatText', ranges: [
    { path: [0, 0], index: 0, length: 6 }, { path: [99, 0], index: 0, length: 2 }
  ], attributes: { italic: {} }, operation_id: operationID(171) }))
  assert.deepEqual(call('state'), before)
  const updates = call('nativeFormatting', { kind: 'formatText', ranges: [
    { path: [0, 0], index: 0, length: 6 }, { path: [1, 0], index: 0, length: 2 }
  ], attributes: { italic: {} }, operation_id: operationID(171) })
  assert.equal(updates.length, 1)
  const snapshot = call('exportHistorySnapshot', { scope_token: 'multiple|171' })
  assert.equal(snapshot.undo.length, 2); assert.equal(snapshot.undo.at(-1).operation_id, operationID(171))
  const peer = new Y.Doc(); Y.applyUpdate(peer, Uint8Array.from(call('state')))
  const vector = Y.encodeStateVector(peer)
  peer.getXmlFragment('default').get(1).get(0).insert(2, 'P', { bold: {} })
  call('apply', [...Y.encodeStateAsUpdate(peer, vector)])
  assert.equal(call('undoWithEvidence', { operation_id: operationID(172) }).kind, 'formatting')
  const after = new Y.Doc(); Y.applyUpdate(after, Uint8Array.from(call('state')))
  assert.deepEqual(paragraphAttributes(after, 0, 0), { bold: {} })
  assert.deepEqual(paragraphAttributes(after, 1, 0), { bold: {} })
  assert.deepEqual(paragraphAttributes(after, 1, 2), { bold: {} })
  assert.equal(call('redoWithEvidence', { operation_id: operationID(173) }).kind, 'formatting')
  after.destroy(); peer.destroy(); original.destroy()
})


test('read-only host eligibility shares structure checks and conservatively restricts marks', () => {
  for (const [name, marks, expected] of [
    ['paragraph', {}, true], ['paragraph', {bold: {}, italic: {}}, true],
    ['paragraph', {link: {href: 'https://example.test'}}, false],
    ['heading', {}, false], ['bulletList', {}, false], ['codeBlock', {}, false], ['entity', {}, false]
  ]) {
    const doc = new Y.Doc(), block = new Y.XmlElement(name), text = new Y.XmlText()
    block.insert(0, [text]); doc.getXmlFragment('default').insert(0, [block]); text.insert(0, 'Unicode 🌍', marks)
    const call = runtime(doc), before = call('state')
    assert.equal(call('supportsProseLineage'), expected)
    assert.deepEqual(call('state'), before); assert.deepEqual(call('undo'), [])
    doc.destroy()
  }
  const empty = new Y.Doc(), call = runtime(empty)
  assert.equal(call('supportsProseLineage'), false)
  empty.getXmlFragment('default').insert(0, [new Y.XmlElement('paragraph')])
  const paragraph = runtime(empty)
  assert.equal(paragraph('supportsProseLineage'), true)
  empty.destroy()
})


test('raw peer split undo does not invent formatting ancestry for restored text', () => {
  const seed = new Y.Doc(), p = new Y.XmlElement('paragraph'), t = new Y.XmlText()
  p.insert(0, [t]); seed.getXmlFragment('default').insert(0, [p]); t.insert(0, 'Hello')
  let a = runtime(seed), b = runtime(seed)
  const split = a('replaceProseWithLineage', {start: 2, end: 2, text: '\n', operation_id: operationID(190)})
  for (const u of split.updates) b('apply', u)
  const append = b('replaceProseWithLineage', {start: 6, end: 6, text: ' B', operation_id: operationID(191)})
  for (const u of append.updates) a('apply', u)
  for (const u of b('nativeFormatting', {kind:'formatText', ranges:[{path:[0,0],index:0,length:2},{path:[1,0],index:0,length:5}],attributes:{bold:{}},operation_id:operationID(192)})) a('apply',u)
  for (const u of b('undoWithEvidence',{operation_id:operationID(193)}).updates) a('apply',u)
  for (const u of b('redoWithEvidence',{operation_id:operationID(194)}).updates) a('apply',u)
  const sa=a('exportHistorySnapshot',{scope_token:'a'}), sb=b('exportHistorySnapshot',{scope_token:'b'})
  const empty = new Y.Doc(); a=runtime(empty);b=runtime(empty)
  a('restoreHistorySnapshot',{snapshot:sa,scope_token:'a',transaction_ids:[operationID(190)]})
  b('restoreHistorySnapshot',{snapshot:sb,scope_token:'b',transaction_ids:[191,192,193,194].map(operationID)})
  const peer=new Y.Doc(); Y.applyUpdate(peer,Uint8Array.from(a('state'))); const vector=Y.encodeStateVector(peer)
  peer.getXmlFragment('default').get(0).get(0).insert(0,'Peer ')
  const remote=[...Y.encodeStateAsUpdate(peer,vector)];a('apply',remote);b('apply',remote)
  for(const u of a('undoWithEvidence',{operation_id:operationID(195)}).updates)b('apply',u)
  const undone=b('undoWithEvidence',{operation_id:operationID(196)})
  assert.equal(undone.kind,'formatting')
  for(const u of undone.updates)a('apply',u)
  const da=new Y.Doc(), db=new Y.Doc(); Y.applyUpdate(da,Uint8Array.from(a('state')));Y.applyUpdate(db,Uint8Array.from(b('state')))
  assert.deepEqual(Y.encodeStateAsUpdate(da),Y.encodeStateAsUpdate(db))
  // Raw Yjs delivery carries no source-to-copy lineage. Only surviving selected
  // IDs may change; this documents the live ancestry gap, not complete undo parity.
  assert.deepEqual(db.getXmlFragment('default').toArray().map(p=>p.toArray().map(t=>t.toDelta())),
    [[[{insert:'Peer He'},{insert:'llo',attributes:{bold:{}}}]],[[{insert:' B'}]]])
  da.destroy();db.destroy()
  seed.destroy();empty.destroy();peer.destroy()
})


test('local placement candidates pair exact emitted operations and persist before graph commit', () => {
  const original=seed(),call=runtime(original),op=operationID(210)
  const forward=call('replaceProseWithLineage',{start:7,end:7,text:'\n',operation_id:op})
  const update=Array.from(Y.mergeUpdates(forward.updates.map(u=>Uint8Array.from(u))))
  const binding={document_id:operationID(211),incarnation:'one'}
  const receipt={contract_version:1,kind:'placement_receipt',...binding,operation_id:op,update_sha256:placementUpdateHash(Uint8Array.from(update)),
    operation:{kind:'replace_prose',reference:null},copies:forward.lineage.copies}
  assert.throws(()=>call('preparePlacementReceipt',{expected_binding:binding,trust:'local',update,receipt:{...receipt,copies:[]}}))
  const candidate=call('preparePlacementReceipt',{expected_binding:binding,trust:'local',update,receipt})
  assert.equal(call('exportHistorySnapshot',{scope_token:'old'}).placement,undefined)
  const persisted=call('exportHistorySnapshot',{scope_token:'new',placement_candidate:candidate})
  assert.equal(persisted.placement.receipts.length,1)
  // A failed host save simply discards this candidate; graph is still behind it.
  assert.equal(call('exportHistorySnapshot',{scope_token:'old'}).placement,undefined)
  const sorted=JSON.parse(JSON.stringify(candidate,function(k,v){return v&&typeof v==='object'&&!Array.isArray(v)?Object.fromEntries(Object.keys(v).sort().map(n=>[n,v[n]])):v}))
  call('commitPlacementReceipt',sorted)
  assert.equal(call('exportHistorySnapshot',{scope_token:'new'}).placement.receipts.length,1)
  assert.throws(()=>call('commitPlacementReceipt',candidate))
  const pristine=new Y.Doc(), restored=runtime(pristine), before=restored('state')
  assert.throws(()=>restored('restoreHistorySnapshot',{snapshot:persisted,scope_token:'new',transaction_ids:[op]}))
  assert.deepEqual(restored('state'),before)
  restored('restoreHistorySnapshot',{snapshot:persisted,scope_token:'new',transaction_ids:[op],
    expected_placement_binding:binding,placement_receipt_ids:[op]})
  assert.deepEqual(restored('exportHistorySnapshot',{scope_token:'new'}).placement,persisted.placement)
  original.destroy();pristine.destroy()
})

import {captureProseOperation,validateProseWitness} from '../adapters/collaboration/prose-lineage.js';
import {captureVisibleTextItems} from '../adapters/collaboration/text-items.js';
test('rich anchored widget input validates full marks and refuses omitted fresh peer-option allocations',()=>{
 const before=new Y.Doc({gc:false});before.clientID=7;const root=before.getXmlFragment('default');
 const q=new Y.XmlElement('questionBlock'),label=new Y.XmlElement('questionLabel'),option=new Y.XmlElement('questionOption');
 const labelText=new Y.XmlText('A🌍Z'),optionText=new Y.XmlText('Choice');root.insert(0,[q]);q.insert(0,[label,option]);label.insert(0,[labelText]);option.insert(0,[optionText]);
 const attrs={underline:{},link:{href:'https://example.com',target:'_blank',rel:'noopener noreferrer nofollow',class:null,title:null}};
 const operation=captureProseOperation(before,root,{start:{path:[0,0,0],index:4},end:{path:[0,0,0],index:4},text:'!',attributes:attrs});
 assert.deepEqual(operation.start_anchor,{type:{client:7,clock:3},assoc:0});assert.deepEqual(operation.inserted_attributes,attrs);
 assert.throws(()=>captureProseOperation(before,root,{start:{path:[0,0,0],index:2},end:{path:[0,0,0],index:3},text:''}),/surrogate/);
 const after=new Y.Doc({gc:false});Y.applyUpdate(after,Y.encodeStateAsUpdate(before));after.clientID=7;const post=after.getXmlFragment('default');
 post.get(0).get(0).get(0).insert(4,'!',structuredClone(attrs));
 const inserted=captureVisibleTextItems(post,{since:Y.encodeStateVector(before)});
 assert.deepEqual(validateProseWitness(before,after,{operation,insertedTextItems:inserted,copies:[]}),{operation,copies:[]});
 const state=Y.encodeStateAsUpdate(after);assert.deepEqual(Y.encodeStateAsUpdate(after),state);
 post.get(0).get(1).get(0).insert(6,'unclaimed');
 assert.throws(()=>validateProseWitness(before,after,{operation,insertedTextItems:inserted,copies:[]}),/Unaccounted/);
 before.destroy();after.destroy();
});

test('rich command suffix copies retain exact link marks and reject mark loss or unaccounted source duplication',()=>{
 const before=new Y.Doc({gc:false}),root=before.getXmlFragment('default'),paragraph=new Y.XmlElement('paragraph'),text=new Y.XmlText();
 root.insert(0,[paragraph]);paragraph.insert(0,[text]);text.insert(0,'A🌍Z',{underline:{}});
 const operation=captureProseOperation(before,root,{start:{path:[0,0],index:1},end:{path:[0,0],index:1},text:'!'});
 const source=captureTextItems(root,{path:[0,0],index:1,length:3});
 const after=new Y.Doc({gc:false});Y.applyUpdate(after,Y.encodeStateAsUpdate(before));const post=after.getXmlFragment('default'),p=post.get(0),left=p.get(0);
 left.delete(1,3);left.insert(1,'!',{});const right=new Y.XmlText();p.insert(1,[right]);right.insert(0,'🌍Z',{underline:{}});
 const insertedTextItems=captureTextItems(post,{path:[0,0],index:1,length:1}),destination=captureTextItems(post,{path:[0,1],index:0,length:3});
 assert.deepEqual(validateProseWitness(before,after,{operation,insertedTextItems,copies:[{source,destination}]}),{operation,copies:[{source,destination}]});
 right.format(0,3,{underline:null});assert.throws(()=>validateProseWitness(before,after,{operation,insertedTextItems,copies:[{source,destination}]}),/attributes changed/);
 before.destroy();after.destroy();
});
