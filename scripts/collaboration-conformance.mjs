import * as Y from 'yjs'
import yjsPackage from 'yjs/package.json' with { type: 'json' }
import assert from 'node:assert/strict'
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

export const fixtureURL = new URL('../spec/relaymark/collaboration/fixtures/convergence-v1.json', import.meta.url)
export const swiftFixtureURL = new URL('../adapters/swift/Tests/RelayMarkCollaborationTests/Fixtures/convergence-v1.json', import.meta.url)
const bytes = value => Buffer.from(value).toString('base64')
export function tree(node) {
  if (node instanceof Y.XmlText) return { kind: 'text', delta: node.toDelta() }
  if (node instanceof Y.XmlElement) return { kind: 'element', name: node.nodeName, attributes: node.getAttributes(), children: node.toArray().map(tree) }
  return { kind: 'fragment', children: node.toArray().map(tree) }
}
function seeded(text, clientID) {
  const doc = new Y.Doc(); doc.clientID = clientID
  const paragraph = new Y.XmlElement('paragraph'), leaf = new Y.XmlText()
  doc.getXmlFragment('default').insert(0, [paragraph]); paragraph.insert(0, [leaf]); leaf.insert(0, text)
  return doc
}
function replica(seed, clientID) { const doc = new Y.Doc(); doc.clientID = clientID; Y.applyUpdate(doc, seed); return doc }
const leaf = doc => doc.getXmlFragment('default').get(0).get(0)
function changed(doc, operation) { const vector = Y.encodeStateVector(doc); operation(leaf(doc)); return Y.encodeStateAsUpdate(doc, vector) }
function fixture(id, seedDoc, edits, orders, extra = {}) {
  const updates = [Y.encodeStateAsUpdate(seedDoc), ...edits]
  const merged = new Y.Doc(); updates.forEach(update => Y.applyUpdate(merged, update))
  return { id, updates: updates.map(bytes), orders, expected: tree(merged.getXmlFragment('default')), ...extra }
}
export function generate() {
  const unicode = seeded('A👩🏽‍💻e\u0301🇺🇳Z', 101), unicodeSeed = Y.encodeStateAsUpdate(unicode)
  const alice = replica(unicodeSeed, 102), bob = replica(unicodeSeed, 103)
  const before = bytes(Y.encodeStateVector(alice))
  const deletion = changed(alice, text => text.delete(1, '👩🏽‍💻'.length))
  const insertion = changed(bob, text => text.insert(text.length, ' 日本'))
  const marks = seeded('Meet Alex 🌍', 201), markSeed = Y.encodeStateAsUpdate(marks)
  const italic = replica(markSeed, 202), reference = replica(markSeed, 203), suffix = replica(markSeed, 204)
  const dependencies = seeded('Start', 301), dependent = replica(Y.encodeStateAsUpdate(dependencies), 302)
  const first = changed(dependent, text => text.insert(text.length, ' one'))
  const second = changed(dependent, text => text.insert(text.length, ' two'))
  return { fixture_version: 1, schema: 'relaymark-prosemirror-v1', root: 'default', update_encoding: 'yjs-v1', yjs: yjsPackage.version, cases: [
    fixture('unicode-delete-only', unicode, [deletion, insertion], [[0,1,2], [2,1,0,1,2], [1,0,2,0]],
      { deletion_update_index: 1, state_vector_before_delete: before, state_vector_after_delete: bytes(Y.encodeStateVector(alice)) }),
    fixture('concurrent-mark-entity-reference', marks, [
      changed(italic, text => text.format(5, 4, { italic: {} })),
      changed(reference, text => text.format(5, 4, { link: { href: 'relay:entity/11111111-1111-4111-8111-111111111111' } })),
      changed(suffix, text => text.insert(text.length, ' 👩🏽‍💻', { bold: {} }))
    ], [[0,1,2,3], [3,2,1,0,2,3], [2,0,3,1,1]]),
    fixture('dependent-update-before-parent', dependencies, [first, second], [[0,1,2], [2,1,0,2], [1,2,0,1]])
  ] }
}
export function verify(fixture) {
  for (const item of fixture.cases) {
    for (const order of item.orders) {
      const doc = new Y.Doc()
      for (const index of order) Y.applyUpdate(doc, Buffer.from(item.updates[index], 'base64'))
      assert.deepEqual(tree(doc.getXmlFragment('default')), item.expected, `${item.id}: ${order}`)
    }
    if (item.deletion_update_index !== undefined) {
      assert.equal(item.state_vector_before_delete, item.state_vector_after_delete)
      assert.notEqual(item.updates[item.deletion_update_index], bytes(Uint8Array.of(0, 0)))
    }
  }
}
export function verifyNative(fixture, native) {
  assert.deepEqual(native.cases.map(value => value.id).sort(), fixture.cases.map(value => value.id).sort())
  for (const item of fixture.cases) {
    const doc = new Y.Doc()
    item.updates.forEach(update => Y.applyUpdate(doc, Buffer.from(update, 'base64')))
    const before = leaf(doc).toString()
    const update = Buffer.from(native.cases.find(value => value.id === item.id).update, 'base64')
    Y.applyUpdate(doc, update); Y.applyUpdate(doc, update)
    assert.equal(leaf(doc).toString(), 'Swift✅ ' + before)
    // Adjacent unmarked runs coalesce; normalize through Yjs rather than compare segmentation.
    const delta = leaf(doc).toDelta()
    assert.deepEqual(delta.filter(run => run.attributes), item.expected.children[0].children[0].delta.filter(run => run.attributes))
  }
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv[2] === '--generate') {
    const result = generate(); verify(result)
    const json = JSON.stringify(result, null, 2) + '\n'
    writeFileSync(fixtureURL, json); writeFileSync(swiftFixtureURL, json)
  } else {
    const result = JSON.parse(readFileSync(fixtureURL)); verify(result)
    if (process.argv[2]) verifyNative(result, JSON.parse(readFileSync(process.argv[2])))
    console.log('Collaboration Unicode, delete-only, reordered, duplicate and concurrent mark/reference fixtures passed')
  }
}
