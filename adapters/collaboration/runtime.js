import * as Y from 'yjs'

// One context owns one document. Transport, authorization and persistence belong to the host.
const doc = new Y.Doc()
const root = doc.getXmlFragment('default')
const localOrigin = 'relay.local.editor'
const undo = new Y.UndoManager(root, { trackedOrigins: new Set([localOrigin]), captureTimeout: 0 })
let localUpdates = []
doc.on('update', (update, origin) => {
  if (origin === localOrigin || origin === undo) localUpdates.push(Array.from(update))
})
function at(path) {
  let value = root
  for (const index of path) {
    if (!Number.isInteger(index) || index < 0 || index >= value.length) throw Error('Invalid XML path')
    value = value.get(index)
  }
  return value
}
function node(value) {
  if (value.kind === 'text') {
    const text = new Y.XmlText()
    text.applyDelta(value.delta || [])
    return text
  }
  if (value.kind !== 'element' || typeof value.name !== 'string') throw Error('Invalid XML node')
  const element = new Y.XmlElement(value.name)
  for (const [key, attribute] of Object.entries(value.attributes || {})) element.setAttribute(key, attribute)
  element.insert(0, (value.children || []).map(node))
  return element
}
function snapshot(value) {
  if (value instanceof Y.XmlText) return { kind: 'text', delta: value.toDelta() }
  if (value instanceof Y.XmlElement) return {
    kind: 'element', name: value.nodeName, attributes: value.getAttributes(), children: value.toArray().map(snapshot)
  }
  return { kind: 'fragment', children: value.toArray().map(snapshot) }
}
function range(target, index, length = 0) {
  if (!Number.isInteger(index) || !Number.isInteger(length) || index < 0 || length < 0 || index + length > target.length) throw Error('Invalid UTF-16 range')
}
function proseBlocks() {
  return root.toArray().map(p => {
    if (!(p instanceof Y.XmlElement) || p.nodeName !== 'paragraph' || Object.keys(p.getAttributes()).length || p.length > 1 || (p.length && !(p.get(0) instanceof Y.XmlText))) throw Error('Unsupported prose structure')
    return { p, text: p.length ? p.get(0) : null }
  })
}
function replaceProse(input) {
  const blocks = proseBlocks()
  if (!blocks.length) throw Error('Empty document must be enrolled with a paragraph')
  const total = blocks.reduce((n, b) => n + (b.text?.length || 0), blocks.length - 1)
  range({ length: total }, input.start, input.end - input.start)
  function locate(offset) {
    for (let i = 0; i < blocks.length; i++) {
      const length = blocks[i].text?.length || 0
      if (offset <= length) return [i, offset]
      offset -= length + 1
    }
    throw Error('Invalid prose offset')
  }
  const [first, start] = locate(input.start), [last, end] = locate(input.end)
  const lines = input.text.split('\n')
  const endText = blocks[last].text
  let skip = end
  const tail = []
  for (const run of endText?.toDelta() || []) {
    if (typeof run.insert !== 'string') throw Error('Unsupported text embed')
    if (skip >= run.insert.length) { skip -= run.insert.length; continue }
    tail.push({ ...run, insert: run.insert.slice(skip) }); skip = 0
  }
  doc.transact(() => {
    let text = blocks[first].text
    if (!text) { text = new Y.XmlText(); blocks[first].p.insert(0, [text]) }
    if (first === last && lines.length === 1) {
      text.delete(start, end - start)
      text.insert(start, input.text, input.attributes || {})
      return
    }
    text.delete(start, text.length - start)
    if (last > first) root.delete(first + 1, last - first)
    text.insert(start, lines[0], input.attributes || {})
    if (lines.length === 1) {
      text.applyDelta([{ retain: text.length }, ...tail])
    } else {
      const additions = lines.slice(1).map((line, i) => {
        const p = new Y.XmlElement('paragraph'), t = new Y.XmlText()
        t.applyDelta([{ insert: line, attributes: input.attributes || {} }, ...(i === lines.length - 2 ? tail : [])].filter(run => run.insert !== ''))
        p.insert(0, [t]); return p
      })
      root.insert(first + 1, additions)
    }
  }, localOrigin)
}
function edit(operation) {
  const target = at(operation.path || [])
  switch (operation.kind) {
    case 'insertNodes': {
      if (!(target instanceof Y.XmlFragment)) throw Error('Expected XML container')
      range(target, operation.index)
      const nodes = operation.nodes.map(node)
      doc.transact(() => target.insert(operation.index, nodes), localOrigin)
      break
    }
    case 'deleteNodes':
      if (!(target instanceof Y.XmlFragment)) throw Error('Expected XML container')
      range(target, operation.index, operation.length)
      doc.transact(() => target.delete(operation.index, operation.length), localOrigin)
      break
    case 'insertText':
      if (!(target instanceof Y.XmlText)) throw Error('Expected XML text')
      range(target, operation.index)
      doc.transact(() => target.insert(operation.index, operation.text, operation.attributes || {}), localOrigin)
      break
    case 'deleteText':
    case 'formatText':
      if (!(target instanceof Y.XmlText)) throw Error('Expected XML text')
      range(target, operation.index, operation.length)
      doc.transact(() => operation.kind === 'deleteText'
        ? target.delete(operation.index, operation.length)
        : target.format(operation.index, operation.length, operation.attributes), localOrigin)
      break
    default: throw Error('Unknown operation')
  }
}
export function call(command, input) {
  switch (command) {
    case 'apply': Y.applyUpdate(doc, Uint8Array.from(input), 'relay.remote'); return null
    case 'state': return Array.from(Y.encodeStateAsUpdate(doc, input === null ? undefined : Uint8Array.from(input)))
    case 'vector': return Array.from(Y.encodeStateVector(doc))
    case 'snapshot': return snapshot(root)
    case 'replaceProse': localUpdates = []; replaceProse(input); return localUpdates
    case 'edit': localUpdates = []; edit(input); return localUpdates
    case 'beginUndoGroup': undo.stopCapturing(); undo.captureTimeout = Number.MAX_SAFE_INTEGER; return null
    case 'endUndoGroup': undo.stopCapturing(); undo.captureTimeout = 0; return null
    case 'undo': localUpdates = []; undo.undo(); return localUpdates
    case 'redo': localUpdates = []; undo.redo(); return localUpdates
    case 'anchor': {
      const target = at(input.path)
      range(target, input.index)
      return Array.from(Y.encodeRelativePosition(Y.createRelativePositionFromTypeIndex(target, input.index, input.association || 0)))
    }
    case 'resolve': {
      const position = Y.createAbsolutePositionFromRelativePosition(Y.decodeRelativePosition(Uint8Array.from(input)), doc)
      if (!position) return null
      function find(container, path) {
        if (container === position.type) return path
        if (container instanceof Y.XmlText) return null
        for (let i = 0; i < container.length; i++) {
          const result = find(container.get(i), [...path, i])
          if (result) return result
        }
        return null
      }
      const path = find(root, [])
      return path === null ? null : { path, index: position.index, association: position.assoc }
    }
    default: throw Error('Unknown collaboration command')
  }
}
// JSON boundary avoids crossing JavaScriptCore object/thread lifetimes into Swift.
globalThis.relayCollaborationCall = (command, json) => JSON.stringify(call(command, JSON.parse(json)))
