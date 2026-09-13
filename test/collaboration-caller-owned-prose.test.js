import test from 'node:test'
import assert from 'node:assert/strict'
import * as Y from 'yjs'
import { readFileSync } from 'node:fs'
import { replaceProse } from '../adapters/collaboration/prose-operation.js'
import { prepareProseLineage } from '../adapters/collaboration/prose-lineage.js'
import { resolveTextItems } from '../adapters/collaboration/text-items.js'

function seed() {
  const doc = new Y.Doc({ gc: false }), root = doc.getXmlFragment('default')
  const p = new Y.XmlElement('paragraph'), text = new Y.XmlText()
  p.insert(0, [text]); root.insert(0, [p]); text.insert(0, 'Left 🌍 tail', { bold: {} })
  return { doc, root }
}
const plain = root => root.toArray().map(p => p.toArray().map(t => t.toDelta().map(run => run.insert).join('')).join(''))
const decode = bytes => JSON.parse(new TextDecoder().decode(Uint8Array.from(bytes)))

test('shared prose uses the caller document, origin and existing undo owner with exact staged evidence', () => {
  const { doc, root } = seed(), origin = { owner: 'existing-editor' }
  const manager = new Y.UndoManager(root, { trackedOrigins: new Set([origin]), captureTimeout: 0 })
  const clientID = doc.clientID, updates = [], untouched = seed()
  const untouchedState = Y.encodeStateAsUpdate(untouched.doc)
  doc.on('update', (bytes, observedOrigin) => updates.push({ bytes, origin: observedOrigin }))
  const replace = (input, targetDoc, targetRoot, hooks) => replaceProse(input, targetDoc, targetRoot, origin, hooks)
  try {
    const prepared = prepareProseLineage(doc, { start: 5, end: 5, text: 'human\nnext ' }, replace)
    assert.equal(updates.length, 0)
    assert.equal(manager.undoStack.length, 0)
    replace(prepared.input, doc, root)
    assert.equal(doc.clientID, clientID)
    assert.equal(doc.getXmlFragment('default'), root)
    assert.equal(updates.length, 1)
    assert.equal(updates[0].origin, origin)
    assert.equal(manager.undoStack.length, 1)
    assert.deepEqual(Y.encodeStateAsUpdate(doc), prepared.expectedState)
    assert.deepEqual(plain(root), ['Left human', 'next 🌍 tail'])
    const typed = resolveTextItems(doc, root, decode(prepared.insertedTextItems))
    assert.deepEqual(typed.unavailableRuns, [])
    assert.equal(typed.segments.map(part => part.text).join(''), 'humannext ')
    assert.equal(prepared.lineage.copies.length, 1)
    const copied = resolveTextItems(doc, root, prepared.lineage.copies[0].destination)
    assert.equal(copied.segments.map(part => part.text).join(''), '🌍 tail')
    assert.equal(root.get(1).length, 1)
    assert.deepEqual(root.get(1).get(0).toDelta(), [{ insert: 'next ' }, { insert: '🌍 tail', attributes: { bold: {} } }])
    manager.undo()
    assert.deepEqual(plain(root), ['Left 🌍 tail'])
    manager.redo()
    assert.deepEqual(plain(root), ['Left human', 'next 🌍 tail'])
    assert.deepEqual(Y.encodeStateAsUpdate(untouched.doc), untouchedState)
  } finally { manager.destroy(); doc.destroy(); untouched.doc.destroy() }
})

test('caller-owned preflight rejects a surrogate-splitting operation without touching its manager or document', () => {
  const { doc, root } = seed(), origin = Symbol('editor')
  const manager = new Y.UndoManager(root, { trackedOrigins: new Set([origin]), captureTimeout: 0 })
  const before = Y.encodeStateAsUpdate(doc)
  try {
    assert.throws(() => prepareProseLineage(doc, { start: 6, end: 6, text: 'bad' },
      (input, targetDoc, targetRoot, hooks) => replaceProse(input, targetDoc, targetRoot, origin, hooks)), /surrogate/)
    assert.deepEqual(Y.encodeStateAsUpdate(doc), before)
    assert.equal(manager.undoStack.length, 0)
  } finally { manager.destroy(); doc.destroy() }
})


test('Elixir distribution contains exact shared modules and the same host Yjs patch', () => {
  for (const name of ['text-items.js', 'prose-operation.js', 'prose-lineage.js', 'history-lineage.js']) {
    assert.deepEqual(readFileSync(new URL(`../adapters/elixir/priv/collaboration/${name}`, import.meta.url)),
      readFileSync(new URL(`../adapters/collaboration/${name}`, import.meta.url)))
  }
  assert.deepEqual(readFileSync(new URL('../adapters/elixir/priv/collaboration/yjs-history-hook.mjs', import.meta.url)),
    readFileSync(new URL('../scripts/yjs-history-hook.mjs', import.meta.url)))
})


test('uniform bold and italic typed marks are explicit evidence while copied tail marks stay unchanged', () => {
  for (const attributes of [{ bold: {} }, { italic: {} }, { bold: {}, italic: {} }]) {
    const { doc, root } = seed(), origin = Symbol('editor')
    const replace = (input, targetDoc, targetRoot, hooks) => replaceProse(input, targetDoc, targetRoot, origin, hooks)
    try {
      const prepared = prepareProseLineage(doc, { start: 5, end: 5, text: '日本\nnext ', attributes }, replace)
      assert.deepEqual(prepared.lineage.operation.inserted_attributes, attributes)
      replace(prepared.input, doc, root)
      assert.deepEqual(Y.encodeStateAsUpdate(doc), prepared.expectedState)
      assert.equal(root.get(1).length, 1)
      assert.deepEqual(root.get(1).get(0).toDelta(), Object.keys(attributes).length === 1 && attributes.bold
        ? [{ insert: 'next 🌍 tail', attributes }]
        : [{ insert: 'next ', attributes }, { insert: '🌍 tail', attributes: { bold: {} } }])
      assert.equal(resolveTextItems(doc, root, decode(prepared.insertedTextItems)).segments.map(p => p.text).join(''), '日本next ')
    } finally { doc.destroy() }
  }
})

test('unsupported or noncanonical inserted marks are rejected before caller mutation', () => {
  const { doc, root } = seed(), origin = Symbol('editor'), before = Y.encodeStateAsUpdate(doc)
  try {
    for (const attributes of [{ bold: true }, { bold: null }, { italic: [] }, { bold: { extra: true } }, { link: { href: 'https://example.com' } }]) {
      assert.throws(() => prepareProseLineage(doc, { start: 5, end: 5, text: 'bad', attributes },
        (input, targetDoc, targetRoot, hooks) => replaceProse(input, targetDoc, targetRoot, origin, hooks)), /Unsupported/)
      assert.deepEqual(Y.encodeStateAsUpdate(doc), before)
    }
  } finally { doc.destroy() }
})
