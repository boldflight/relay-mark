import test from 'node:test'
import assert from 'node:assert/strict'
import * as Y from 'yjs'

// The pinned Yjs build carries the yjs/yjs#806 fix: undo must not delete a
// neighbour that merged with an item re-created by an earlier undo.
test('pinned Yjs undo keeps a merged neighbour of a redone item', () => {
  const doc = new Y.Doc()
  const fragment = doc.getXmlFragment('f')
  const p = new Y.XmlElement('p')
  p.insert(0, [new Y.XmlText('ab')])
  fragment.insert(0, [p])
  const undoManager = new Y.UndoManager(fragment, { trackedOrigins: new Set(['me']) })
  const step = f => { doc.transact(f, 'me'); undoManager.stopCapturing() }
  step(() => p.get(0).insert(0, 'x'))
  step(() => p.get(0).delete(1, 1))
  step(() => fragment.delete(0, 1))
  const states = []
  while (undoManager.canUndo()) {
    undoManager.undo()
    states.push(fragment.get(0).get(0).toString())
  }
  assert.deepEqual(states, ['xb', 'xab', 'ab'])
})
