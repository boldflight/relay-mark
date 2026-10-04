import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'
import * as Y from 'yjs'
import { captureTextItems, resolveTextItems, captureVisibleTextItems } from '../adapters/collaboration/text-items.js'
function seed(value = 'HUMAN') {
  const doc = new Y.Doc(), root = doc.getXmlFragment('default'), leaf = new Y.XmlText()
  root.insert(0, [leaf]); leaf.insert(0, value)
  return { doc, root, leaf }
}
const capture = (s, index = 0, length = s.leaf.length) => captureTextItems(s.root, { path: [0], index, length })
const resolve = (s, selection) => resolveTextItems(s.doc, s.root, selection)
const combined = result => result.segments.map(segment => segment.text).join('')
const copy = value => JSON.parse(JSON.stringify(value))
test('exact items exclude remote inserts and survive portable checkpoint restoration', () => {
  const a = seed(), selection = capture(a), b = new Y.Doc()
  Y.applyUpdate(b, Y.encodeStateAsUpdate(a.doc))
  const leaf = b.getXmlFragment('default').get(0)
  leaf.insert(2, 'remote'); leaf.insert(0, 'left'); leaf.insert(leaf.length, 'right')
  Y.applyUpdate(a.doc, Y.encodeStateAsUpdate(b))
  const result = resolve(a, selection)
  assert.equal(combined(result), 'HUMAN'); assert.equal(result.segments.length, 2)
  assert.deepEqual(result.unavailableRuns, [])
  const checkpoint = new Y.Doc(); Y.applyUpdate(checkpoint, Y.encodeStateAsUpdate(a.doc))
  assert.deepEqual(resolveTextItems(checkpoint, checkpoint.getXmlFragment('default'), selection), result)
  a.doc.destroy(); b.destroy(); checkpoint.destroy()
})
test('deletion is distinct from missing items and removed ancestors; no orphan paths', () => {
  const a = seed(), selection = capture(a)
  a.leaf.delete(1, 3); a.leaf.insert(1, 'new')
  assert.equal(combined(resolve(a, selection)), 'HN'); assert.equal(resolve(a, selection).collapsedUnits, 3)
  const unknown = copy(selection)
  unknown.runs[0].item.clock += 1000
  assert.deepEqual(resolve(a, unknown).unavailableRuns, [0])
  a.root.delete(0, 1); assert.deepEqual(resolve(a, selection), { segments: [], collapsedUnits: 0, unavailableRuns: [0] })
  const nested = seed(''), parent = new Y.XmlElement('paragraph'), leaf = new Y.XmlText()
  nested.root.insert(1, [parent]); parent.insert(0, [leaf]); leaf.insert(0, 'nested')
  const own = captureTextItems(nested.root, { path: [1, 0], index: 0, length: 6 })
  nested.root.delete(1, 1); assert.deepEqual(resolve(nested, own).unavailableRuns, [0])
  a.doc.destroy(); nested.doc.destroy()
})
test('output order is current document order across reversed runs and leaves', () => {
  const a = seed('abc'), second = new Y.XmlText(); a.root.insert(1, [second]); second.insert(0, 'def')
  const one = capture(a, 0, 1), three = capture(a, 2, 1)
  const two = captureTextItems(a.root, { path: [1], index: 0, length: 3 })
  const result = resolve(a, { runs: [...two.runs, ...three.runs, ...one.runs] })
  assert.equal(combined(result), 'acdef'); assert.deepEqual(result.segments.map(x => x.path), [[0], [0], [1]])
  a.doc.destroy()
})
test('UTF-16, formatting and undo do not invent ownership', () => {
  const a = seed('A😀éZ'), selection = capture(a), origin = {}
  a.leaf.format(0, a.leaf.length, { bold: true })
  assert.equal(combined(resolve(a, selection)), 'A😀éZ')
  const undo = new Y.UndoManager(a.leaf, { trackedOrigins: new Set([origin]) })
  a.doc.transact(() => a.leaf.delete(0, a.leaf.length), origin); undo.undo()
  assert.equal(combined(resolve(a, selection)), '')
  assert.equal(resolve(a, selection).collapsedUnits, 6)
  undo.destroy(); a.doc.destroy()
})
test('strict decoder rejects malformed, overflowing, duplicate and mismatched identities', () => {
  const a = seed(), valid = capture(a)
  const change = fn => { const value = copy(valid); fn(value); assert.throws(() => resolve(a, value)) }
  change(x => { x.extra = true }); change(x => { x.runs[0].extra = true }); change(x => { x.version = 2 })
  for (const count of [0, -1, 1.5, 131073, Number.MAX_SAFE_INTEGER]) change(x => { x.runs[0].count = count })
  change(x => { x.runs[0].item.extra = 0 }); change(x => { x.runs[0].type.extra = 0 })
  for (const field of ['item', 'type']) for (const invalid of [-1, 1.5, 2 ** 32]) change(x => { x.runs[0][field].clock = invalid })
  change(x => { x.runs[0].item.client = Number.MAX_SAFE_INTEGER + 1 })
  change(x => { x.runs[0].item.clock = 2 ** 32 - 1; x.runs[0].count = 2 })
  change(x => { x.runs.push(copy(x.runs[0])) }); change(x => { x.runs = Array(4097).fill(x.runs[0]) })
  change(x => { x.runs[0].assoc = -1 })
  const other = new Y.XmlText(); a.root.insert(1, [other]); other.insert(0, 'other')
  change(x => { x.runs[0].type = { ...Y.createRelativePositionFromTypeIndex(other, 0).type } })
  a.doc.destroy()
})
test('capture refuses unsupported or oversized selections without truncation', () => {
  const a = seed('x'.repeat(131073))
  assert.throws(() => capture(a)); assert.deepEqual(capture(a, 0, 0), { runs: [] })
  assert.throws(() => captureTextItems(a.root, { path: [0], index: 0, length: 1, extra: 0 }))
  a.leaf.insertEmbed(0, { atom: true }); assert.throws(() => capture(a, 0, 1), /atoms/)
  a.doc.destroy()
  const emoji = seed('😀')
  assert.throws(() => capture(emoji, 0, 1), /surrogate/)
  assert.throws(() => capture(emoji, 1, 1), /surrogate/)
  emoji.doc.destroy()
})
test('bounded maximum units resolves without argument expansion overflow', () => {
  const a = seed('x'.repeat(131072)), selected = capture(a)
  assert.equal(selected.runs.length, 1)
  assert.equal(resolve(a, selected).segments[0].length, 131072)
  a.doc.destroy()
})
test('fragmentation limit rejects capture and aggregate count is bounded across runs', () => {
  const a = seed('')
  for (let i = 0; i < 4097; i++) a.leaf.insert(a.leaf.length, 'x', { bold: i % 2 === 0 })
  assert.throws(() => capture(a), /Too many text item runs/)
  const selection = capture(a, 0, 1), second = copy(selection.runs[0])
  second.item.clock += 65537; second.count = 65536
  selection.runs[0].count = 65537; selection.runs.push(second)
  assert.throws(() => resolve(a, selection), /bounds/)
  a.doc.destroy()
})
test('committed Swift bundle exposes capture and resolve commands', () => {
  const context = { crypto: globalThis.crypto, TextEncoder, TextDecoder, console,
    setTimeout: () => 0, clearTimeout: () => {}, setInterval: () => 0, clearInterval: () => {} }
  runInNewContext(readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js', import.meta.url), 'utf8'), context)
  const call = (command, input) => JSON.parse(context.relayCollaborationCall(command, JSON.stringify(input)))
  const a = seed(); call('apply', [...Y.encodeStateAsUpdate(a.doc)])
  const selection = call('captureTextItems', { path: [0], index: 0, length: 5 })
  assert.deepEqual(selection, capture(a))
  a.leaf.insert(2, 'remote'); call('apply', [...Y.encodeStateAsUpdate(a.doc)])
  assert.deepEqual(call('resolveTextItems', selection), resolve(a, selection)); a.doc.destroy()
})
test('portable exact item fixtures resolve through production API', () => {
  const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/text-items-v1.json', import.meta.url), 'utf8'))
  for (const row of fixture.cases) {
    const doc = new Y.Doc(); Y.applyUpdate(doc, Buffer.from(row.update, 'base64'))
    assert.deepEqual(resolveTextItems(doc, doc.getXmlFragment('default'), {runs:row.selection.runs}), row.expected, row.name)
    doc.destroy()
  }
})
test('wide trees fail traversal before allocating a child array', () => {
  const a = seed()
  // A real public XML container with an over-limit child count. Spy only on
  // enumeration to prove the admission check precedes the potentially large copy.
  a.root.insert(1, Array.from({ length: 65536 }, () => new Y.XmlText()))
  a.root.toArray = () => { throw Error('enumeration occurred before admission') }
  assert.throws(() => resolve(a, { runs: [] }), /traversal limit exceeded/)
  a.doc.destroy()
})

test('whole rich XML observation accounts every fresh label and option run without a document character cap',()=>{
 const doc=new Y.Doc({gc:false});doc.clientID=7;const root=doc.getXmlFragment('default');
 const question=new Y.XmlElement('questionBlock'),labelNode=new Y.XmlElement('questionLabel'),optionNode=new Y.XmlElement('questionOption');
 const label=new Y.XmlText('A🌍Z'),option=new Y.XmlText('Choice');
 root.insert(0,[question]);question.insert(0,[labelNode,optionNode]);labelNode.insert(0,[label]);optionNode.insert(0,[option]);
 const vector=Y.encodeStateVector(doc),next=Y.decodeStateVector(vector).get(7);
 // Expected clocks fixed from these independent host allocations, not the observer.
 assert.equal(next,15);label.insert(4,'!');option.insert(6,'🌍');
 const state=Y.encodeStateAsUpdate(doc);
 assert.deepEqual(captureVisibleTextItems(root,{since:vector}),{runs:[
  {type:{client:7,clock:3},item:{client:7,clock:15},count:1},
  {type:{client:7,clock:8},item:{client:7,clock:16},count:2}
 ]});
 assert.deepEqual(Y.encodeStateAsUpdate(doc),state);
 assert.throws(()=>captureVisibleTextItems(root,{since:vector,maximumSteps:1}),/budget/);
 option.delete(6,2);assert.equal(captureVisibleTextItems(root,{since:vector}).runs.length,1);
 root.delete(0,1);assert.deepEqual(captureVisibleTextItems(root,{since:vector}),{runs:[]});
 const paragraph=new Y.XmlElement('paragraph'),long=new Y.XmlText('x'.repeat(250000));root.insert(0,[paragraph]);paragraph.insert(0,[long]);
 assert.equal(captureVisibleTextItems(root,{maximumSteps:8}).runs[0].count,250000);
 doc.destroy();
});
