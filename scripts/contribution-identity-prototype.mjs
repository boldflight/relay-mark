// Exploratory proof, not an accepted wire contract or authorship detector.
import assert from 'node:assert/strict'
import { performance } from 'node:perf_hooks'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import * as Y from 'yjs'

const docs = []
function document(text = '') {
  const doc = new Y.Doc(); docs.push(doc)
  const root = doc.getXmlFragment('default'), leaf = new Y.XmlText()
  root.insert(0, [leaf]); leaf.insert(0, text)
  return { doc, leaf }
}
function clone(doc) {
  const copy = new Y.Doc(); docs.push(copy); Y.applyUpdate(copy, Y.encodeStateAsUpdate(doc))
  return { doc: copy, leaf: copy.getXmlFragment('default').get(0) }
}
const encode = position => Array.from(Y.encodeRelativePosition(position))
const decode = bytes => Y.decodeRelativePosition(Uint8Array.from(bytes))
function plain(leaf) {
  return leaf.toDelta().map(part => {
    assert.equal(typeof part.insert, 'string', 'atoms require a separate supported mapping')
    return part.insert
  }).join('')
}
function capture(leaf, start, length) {
  // The caller has already established human intent for this exact selection.
  const oracle = [], runs = []
  for (let i = start; i < start + length; i++) {
    const left = Y.createRelativePositionFromTypeIndex(leaf, i, 0)
    const right = Y.createRelativePositionFromTypeIndex(leaf, i + 1, -1)
    assert.deepEqual(left.item, right.item)
    oracle.push([encode(left), encode(right)])
    const previous = runs.at(-1)
    if (previous && previous.client === left.item.client && previous.clock + previous.length === left.item.clock) {
      previous.length++
    } else runs.push({ type: left.type, tname: left.tname, client: left.item.client, clock: left.item.clock, length: 1 })
  }
  return { oracle, runs }
}
function expand(runs) {
  return runs.flatMap(run => Array.from({ length: run.length }, (_, offset) => [0, -1].map(assoc => encode(
    Y.createRelativePositionFromJSON({ type: run.type, tname: run.tname,
      item: { client: run.client, clock: run.clock + offset }, assoc })
  ))))
}
function resolve(doc, pairs) {
  return pairs.flatMap(([left, right]) => {
    // Disable following redone items: undo ownership requires saved host mapping.
    const a = Y.createAbsolutePositionFromRelativePosition(decode(left), doc, false)
    const b = Y.createAbsolutePositionFromRelativePosition(decode(right), doc, false)
    if (!a || !b) return []
    assert.equal(a.type, b.type)
    if (a.index === b.index) return []
    assert.equal(b.index, a.index + 1, 'exact item must resolve to precisely one UTF-16 unit')
    // Public round-trip identity check rejects positions that collapsed onto a replacement.
    const current = Y.createRelativePositionFromTypeIndex(a.type, a.index, 0)
    if (JSON.stringify(current.item) !== JSON.stringify(decode(left).item)) return []
    return [{ type: a.type, index: a.index, text: plain(a.type).slice(a.index, b.index) }]
  })
}
function check(state, ownership, expected) {
  const pairs = expand(ownership.runs)
  assert.deepEqual(pairs, ownership.oracle)
  const compact = resolve(state.doc, pairs), oracle = resolve(state.doc, ownership.oracle)
  assert.deepEqual(compact, oracle)
  assert.equal(compact.map(item => item.text).join(''), expected)
}
const results = []
function scenario(name, action) { action(); results.push({ name, passed: true }) }

scenario('interior and both edge remote insertions stay excluded; broad interval absorbs interior', () => {
  const a = document('HUMAN'), own = capture(a.leaf, 0, 5), b = clone(a.doc)
  const broad = [own.oracle[0][0], own.oracle.at(-1)[1]]
  b.leaf.insert(2, 'REMOTE'); b.leaf.insert(0, 'L'); b.leaf.insert(b.leaf.length, 'R')
  Y.applyUpdate(a.doc, Y.encodeStateAsUpdate(b.doc)); check(a, own, 'HUMAN')
  const left = Y.createAbsolutePositionFromRelativePosition(decode(broad[0]), a.doc, false)
  const right = Y.createAbsolutePositionFromRelativePosition(decode(broad[1]), a.doc, false)
  assert.equal(a.leaf.toString().slice(left.index, right.index), 'HUREMOTEMAN')
})
scenario('remote partial deletion and insertion at deleted location', () => {
  const a = document('HUMAN'), own = capture(a.leaf, 0, 5), b = clone(a.doc)
  b.leaf.delete(1, 3); b.leaf.insert(1, 'new'); Y.applyUpdate(a.doc, Y.encodeStateAsUpdate(b.doc))
  check(a, own, 'HN'); check(clone(a.doc), own, 'HN')
})
scenario('fully deleted contribution does not adopt equal replacement text', () => {
  const a = document('same'), own = capture(a.leaf, 0, 4)
  a.leaf.delete(0, 4); a.leaf.insert(0, 'same'); check(a, own, '')
})
scenario('concurrent replicas converge with reordered and duplicated delivery', () => {
  const a = document('HUMAN'), own = capture(a.leaf, 0, 5), b = clone(a.doc), c = clone(a.doc)
  b.leaf.insert(2, 'B'); c.leaf.delete(3, 1); c.leaf.insert(3, 'C')
  const bu = Y.encodeStateAsUpdate(b.doc), cu = Y.encodeStateAsUpdate(c.doc)
  Y.applyUpdate(b.doc, cu); Y.applyUpdate(c.doc, bu)
  Y.applyUpdate(a.doc, cu); Y.applyUpdate(a.doc, bu); Y.applyUpdate(a.doc, cu)
  assert.equal(a.leaf.toString(), b.leaf.toString()); assert.equal(a.leaf.toString(), c.leaf.toString())
  for (const state of [a, b, c]) check(state, own, 'HUMN')
})
scenario('checkpoint clone preserves exact item identity', () => {
  const a = document('Human'), own = capture(a.leaf, 0, 5)
  check(clone(a.doc), own, 'Human')
})
scenario('formatting does not create or expand contribution text', () => {
  const a = document('Human'), own = capture(a.leaf, 0, 5)
  a.leaf.format(0, 5, { bold: true }); check(a, own, 'Human')
})
scenario('UTF-16 emoji round-trips without assuming one clock per grapheme', () => {
  const a = document('A😀éZ'), own = capture(a.leaf, 0, a.leaf.length)
  assert.equal(a.leaf.length, 6); check(clone(a.doc), own, 'A😀éZ')
  a.leaf.insert(3, 'remote'); check(a, own, 'A😀éZ')
})
scenario('deleted shared leaf becomes unresolvable', () => {
  const a = document('Human'), own = capture(a.leaf, 0, 5)
  a.doc.getXmlFragment('default').delete(0, 1); check(a, own, '')
})
scenario('multiple leaves and different client runs remain separate', () => {
  const a = document('one'), second = new Y.XmlText()
  a.doc.getXmlFragment('default').insert(1, [second]); second.insert(0, 'two')
  const first = capture(a.leaf, 0, 3), other = capture(second, 0, 3)
  check(a, { runs: [...first.runs, ...other.runs], oracle: [...first.oracle, ...other.oracle] }, 'onetwo')
  const b = clone(a.doc); b.leaf.insert(3, 'remote'); Y.applyUpdate(a.doc, Y.encodeStateAsUpdate(b.doc))
  assert.equal(capture(a.leaf, 0, a.leaf.length).runs.length, 2)
})
scenario('undo restoration gets fresh IDs and must consult saved intent mapping', () => {
  const a = document('generated'), generated = capture(a.leaf, 0, 9), origin = {}
  const undo = new Y.UndoManager(a.leaf, { trackedOrigins: new Set([origin]), captureTimeout: 0 })
  a.doc.transact(() => { a.leaf.delete(0, 9); a.leaf.insert(0, 'human') }, origin)
  const human = capture(a.leaf, 0, 5); undo.undo()
  assert.equal(a.leaf.toString(), 'generated'); check(a, generated, ''); check(a, human, '')
  assert.notDeepEqual(capture(a.leaf, 0, 9).runs, generated.runs)
  undo.redo(); assert.equal(a.leaf.toString(), 'human'); check(a, human, '')
  undo.destroy()
})
scenario('actual committed Swift bundle resolves the same canonical pairs', () => {
  const a = document('HUMAN'), own = capture(a.leaf, 0, 5)
  a.leaf.insert(2, 'remote')
  const context = vm.createContext({ console, TextEncoder, TextDecoder, setTimeout, clearTimeout,
    setInterval: () => 0, clearInterval: () => {}, crypto: globalThis.crypto })
  vm.runInContext(readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js', import.meta.url), 'utf8'), context)
  const call = (name, input) => JSON.parse(context.relayCollaborationCall(name, JSON.stringify(input)))
  call('apply', Array.from(Y.encodeStateAsUpdate(a.doc)))
  const text = expand(own.runs).map(([anchor, head]) => {
    const result = call('resolveRange', { version: 1, anchor, head })
    return a.leaf.toString().slice(result.anchor.index, result.head.index)
  }).join('')
  assert.equal(text, 'HUMAN')
})

const large = document('x'.repeat(100 * 1024)), start = performance.now()
const ownership = capture(large.leaf, 0, large.leaf.length), captured = performance.now()
check(large, ownership, large.leaf.toString())
const finished = performance.now()
results.push({ name: '100 KiB contiguous ASCII', passed: true, units: large.leaf.length,
  runs: ownership.runs.length, compactJSONBytes: Buffer.byteLength(JSON.stringify(ownership.runs)),
  oracleJSONBytes: Buffer.byteLength(JSON.stringify(ownership.oracle)),
  captureMs: Math.round(captured - start), expandAndCheckMs: Math.round(finished - captured) })
console.log(JSON.stringify({ prototypeVersion: 1, results }, null, 2))
docs.forEach(doc => doc.destroy())
