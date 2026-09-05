import * as Y from 'yjs'
import { Awareness, applyAwarenessUpdate, encodeAwarenessUpdate, removeAwarenessStates } from 'y-protocols/awareness'

// One context owns one document. Transport, authorization and persistence belong to the host.
const doc = new Y.Doc()
const root = doc.getXmlFragment('default')
const awareness = new Awareness(doc)
awareness.setLocalState(null)
let awarenessUpdates = []
const awarenessOrigins = new Map()
awareness.on('update', ({ added, updated, removed }, origin) => {
  for (const [key, ids] of awarenessOrigins) {
    const retained = ids.filter(id => !removed.includes(id) && !updated.includes(id))
    if (retained.length) awarenessOrigins.set(key, retained); else awarenessOrigins.delete(key)
  }
  if (typeof origin === 'string' && origin !== 'local' && origin !== 'timeout') awarenessOrigins.set(origin, [...new Set([...(awarenessOrigins.get(origin) || []), ...added, ...updated])])
  if (origin === 'local') awarenessUpdates.push(Array.from(encodeAwarenessUpdate(awareness, [...added, ...updated, ...removed])))
})
// Snapshot bytes remain standard y-protocols data. Origin metadata is the existing
// ephemeral ownership index, not document state or a second awareness cache.
function presenceSnapshot() {
  const ids = [...awareness.getStates().keys()].filter(id => id !== awareness.clientID).sort((a,b) => a-b)
  const origins = Object.create(null), covered = new Set()
  for (const [origin, known] of awarenessOrigins) {
    const active = [...new Set(known.filter(id => ids.includes(id)))].sort((a,b) => a-b)
    if (active.length) { origins[origin] = active; active.forEach(id => covered.add(id)) }
  }
  if (ids.some(id => !covered.has(id))) throw Error('Presence origin is unavailable')
  return {version:1, update:Array.from(encodeAwarenessUpdate(awareness, ids)), origins}
}
function applyPresenceSnapshot(input) {
  if (!input || input.version !== 1 || !Array.isArray(input.update) ||
      input.update.some(byte => !Number.isInteger(byte) || byte < 0 || byte > 255) ||
      !input.origins || typeof input.origins !== 'object' || Array.isArray(input.origins)) throw Error('Invalid presence snapshot')
  const temporaryDoc = new Y.Doc()
  temporaryDoc.clientID = awareness.clientID
  const temporary = new Awareness(temporaryDoc)
  temporary.setLocalState(null)
  try {
    applyAwarenessUpdate(temporary, Uint8Array.from(input.update), null)
    const ids = [...temporary.getStates().keys()], covered = new Set()
    if (ids.includes(awareness.clientID)) throw Error('Presence snapshot includes local client')
    for (const [origin, members] of Object.entries(input.origins)) {
      if (!origin || origin === 'local' || origin === 'timeout' || !Array.isArray(members) ||
          !members.length || new Set(members).size !== members.length ||
          members.some(id => !Number.isSafeInteger(id) || id < 0 || !ids.includes(id))) throw Error('Invalid presence origins')
      members.forEach(id => covered.add(id))
    }
    if (ids.some(id => !covered.has(id))) throw Error('Incomplete presence origins')
    // Reject removed/tombstone states: bootstrap snapshots contain active remote presence only.
    if ([...temporary.meta.keys()].some(id => id !== temporary.clientID && !ids.includes(id))) throw Error('Inactive presence snapshot')
    applyAwarenessUpdate(awareness, Uint8Array.from(input.update), null)
    for (const [origin, members] of Object.entries(input.origins)) {
      const current = members.filter(id => awareness.getStates().has(id) &&
        awareness.meta.get(id)?.clock === temporary.meta.get(id)?.clock &&
        JSON.stringify(awareness.getStates().get(id)) === JSON.stringify(temporary.getStates().get(id)))
      if (current.length) awarenessOrigins.set(origin, [...new Set([...(awarenessOrigins.get(origin) || []), ...current])])
    }
  } finally { temporary.destroy(); temporaryDoc.destroy() }
}
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
// Portable anchors accept only canonical modern Yjs encodings, with bounded input.
function relativePosition(bytes) {
  if (!Array.isArray(bytes) || bytes.length < 1 || bytes.length > 256 || bytes.some(v => !Number.isInteger(v) || v < 0 || v > 255)) throw Error('Invalid relative position bytes')
  const position = Y.decodeRelativePosition(Uint8Array.from(bytes))
  if (!Number.isSafeInteger(position.assoc)) throw Error('Invalid relative association')
  for (const id of [position.type, position.item]) {
    if (id && (!Number.isSafeInteger(id.client) || id.client < 0 || !Number.isSafeInteger(id.clock) || id.clock < 0)) throw Error('Invalid relative identity')
  }
  if (position.tname !== null && position.tname !== 'default') throw Error('Unknown relative root')
  const canonical = Y.encodeRelativePosition(position)
  if (canonical.length !== bytes.length || canonical.some((byte, index) => byte !== bytes[index])) throw Error('Noncanonical relative position')
  return position
}
function absolutePosition(relative, portable) {
  const position = Y.createAbsolutePositionFromRelativePosition(relative, doc, !portable)
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
const hardBreakCharacter = '\u2028'
function inlineLength(p) {
  if (p.nodeName === 'horizontalRule') return 1
  return p.toArray().reduce((n, child) => n + (child instanceof Y.XmlText ? child.length : 1), 0)
}
function proseBlocks() {
  const blocks = []
  function walk(parent) {
    for (const p of parent.toArray()) {
      if (!(p instanceof Y.XmlElement)) throw Error('Unsupported prose structure')
      const attrs = p.getAttributes()
      if (['paragraph', 'heading', 'codeBlock', 'horizontalRule'].includes(p.nodeName)) {
        const allowed = p.nodeName === 'heading' ? ['level'] : p.nodeName === 'codeBlock' ? ['language'] : []
        if (Object.keys(attrs).some(key => !allowed.includes(key))) throw Error('Unsupported prose attributes')
        if (p.nodeName === 'horizontalRule' && p.length) throw Error('Unsupported rule content')
        for (const child of p.toArray()) {
          if (child instanceof Y.XmlText) continue
          if (p.nodeName !== 'codeBlock' && child instanceof Y.XmlElement && child.nodeName === 'hardBreak' && !child.length && !Object.keys(child.getAttributes()).length) continue
          throw Error('Unsupported prose inline content')
        }
        blocks.push({ p, length: inlineLength(p) })
      } else if (['blockquote', 'bulletList', 'orderedList', 'listItem'].includes(p.nodeName)) {
        if (Object.keys(attrs).some(key => p.nodeName !== 'orderedList' || key !== 'start')) throw Error('Unsupported prose container attributes')
        if (['bulletList', 'orderedList'].includes(p.nodeName) && p.toArray().some(n => n.nodeName !== 'listItem')) throw Error('Unsupported list children')
        walk(p)
      } else throw Error('Unsupported prose structure')
    }
  }
  walk(root)
  return blocks
}
function removeBlock(block) {
  let element = block.p
  while (element && element !== root) {
    const parent = element.parent
    parent.delete(parent.toArray().indexOf(element), 1)
    if (parent.length || parent === root) return
    element = parent
  }
}
function sliceInline(p, start) {
  const result = []
  for (const child of p.toArray()) {
    const length = child instanceof Y.XmlText ? child.length : 1
    if (start >= length) { start -= length; continue }
    if (child instanceof Y.XmlText) {
      const delta = []
      for (const run of child.toDelta()) {
        if (typeof run.insert !== 'string') throw Error('Unsupported text embed')
        if (start >= run.insert.length) { start -= run.insert.length; continue }
        delta.push({ ...run, insert: run.insert.slice(start) }); start = 0
      }
      result.push({ kind: 'text', delta })
    } else { result.push(snapshot(child)); start = 0 }
  }
  return result
}
function deleteInline(p, start, end) {
  let offset = 0
  const spans = p.toArray().map(child => {
    const length = child instanceof Y.XmlText ? child.length : 1
    const result = { child, start: offset, end: offset + length }; offset += length; return result
  })
  for (const span of spans.reverse()) {
    const from = Math.max(start, span.start), to = Math.min(end, span.end)
    if (to <= from) continue
    if (span.child instanceof Y.XmlText) span.child.delete(from - span.start, to - from)
    else p.delete(p.toArray().indexOf(span.child), 1)
  }
}
function insertInline(p, offset, content, attributes) {
  if (!content) return
  let index = 0, target = null, local = offset
  const children = p.toArray()
  for (; index < children.length; index++) {
    const child = children[index], length = child instanceof Y.XmlText ? child.length : 1
    if (child instanceof Y.XmlText && local <= length) { target = child; break }
    if (local === 0) break
    local -= length
  }
  if (!target) { target = new Y.XmlText(); p.insert(index, [target]); local = 0 }
  const parts = p.nodeName === 'codeBlock' ? [content] : content.split(hardBreakCharacter)
  if (parts.length === 1) { target.insert(local, content, attributes); return }
  // Splitting an inline text to insert a break moves only that text's suffix;
  // all other XmlText siblings and the block itself retain their Yjs identities.
  const tail = sliceInline({ toArray: () => [target] }, local)
  target.delete(local, target.length - local)
  target.insert(local, parts[0], attributes)
  const additions = []
  for (const part of parts.slice(1)) {
    additions.push(new Y.XmlElement('hardBreak'))
    const text = new Y.XmlText(); text.insert(0, part, attributes); additions.push(text)
  }
  for (const item of tail) additions.push(node(item))
  p.insert(p.toArray().indexOf(target) + 1, additions)
}
function paragraph(content, attributes, tail = []) {
  const p = new Y.XmlElement('paragraph')
  // Populate after integration: insertInline relies on live Yjs lengths.
  return { p, populate: () => { insertInline(p, 0, content, attributes); p.insert(p.length, tail.map(node)) } }
}
function replaceProse(input) {
  const blocks = proseBlocks()
  if (!blocks.length) throw Error('Empty document must be enrolled with a paragraph')
  const total = blocks.reduce((n, b) => n + b.length, blocks.length - 1)
  range({ length: total }, input.start, input.end - input.start)
  function locate(offset) {
    for (let i = 0; i < blocks.length; i++) {
      if (offset <= blocks[i].length) return [i, offset]
      offset -= blocks[i].length + 1
    }
    throw Error('Invalid prose offset')
  }
  const [first, start] = locate(input.start), [last, end] = locate(input.end)
  const firstRule = blocks[first].p.nodeName === 'horizontalRule'
  const lastRule = blocks[last].p.nodeName === 'horizontalRule'
  const lines = first === last && blocks[first].p.nodeName === 'codeBlock' ? [input.text] : input.text.split('\n')
  const tail = lastRule ? [] : sliceInline(blocks[last].p, end)
  // A cross-block merge must not smuggle inline marks/breaks into literal code.
  if (first !== last && blocks[first].p.nodeName === 'codeBlock' && tail.some(n => n.kind !== 'text' || n.delta.some(r => Object.keys(r.attributes || {}).length))) throw Error('Cannot merge marked prose into a code block')
  doc.transact(() => {
    if (first === last && !firstRule && lines.length === 1) {
      deleteInline(blocks[first].p, start, end)
      insertInline(blocks[first].p, start, input.text, input.attributes || {})
      return
    }
    let destination = blocks[first].p
    if (firstRule) {
      if (first === last && start === end && !input.text) return
      const parent = destination.parent, index = parent.toArray().indexOf(destination) + (start === 1 ? 1 : 0)
      const created = new Y.XmlElement('paragraph'); parent.insert(index, [created]); destination = created
      if (start === 0 && (first !== last || end === 1)) removeBlock(blocks[first])
    } else deleteInline(destination, start, inlineLength(destination))
    for (let i = last; i > first; i--) {
      if (i === last && lastRule && end === 0) continue
      removeBlock(blocks[i])
    }
    insertInline(destination, firstRule ? 0 : start, lines[0], input.attributes || {})
    if (lines.length === 1) destination.insert(destination.length, tail.map(node))
    else {
      const additions = lines.slice(1).map((line, i) => paragraph(line, input.attributes || {}, i === lines.length - 2 ? tail : []))
      const parent = destination.parent
      if (parent instanceof Y.XmlElement && parent.nodeName === 'listItem' && parent.length === 1) {
        const list = parent.parent
        const items = additions.map(({p}) => { const item = new Y.XmlElement('listItem'); item.insert(0, [p]); return item })
        list.insert(list.toArray().indexOf(parent) + 1, items)
      } else parent.insert(parent.toArray().indexOf(destination) + 1, additions.map(a => a.p))
      additions.forEach(a => a.populate())
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
function safeAnchor(value) {
  try { return Array.from(Y.encodeRelativePosition(Y.createRelativePositionFromJSON(value))) } catch { return null }
}
export function call(command, input) {
  switch (command) {
    case 'presenceSet': {
      awarenessUpdates = []
      const cursor = input?.anchor && input?.head ? {
        anchor: Y.relativePositionToJSON(Y.decodeRelativePosition(Uint8Array.from(input.anchor))),
        head: Y.relativePositionToJSON(Y.decodeRelativePosition(Uint8Array.from(input.head)))
      } : null
      awareness.setLocalState(input === null ? null : { user: { name: input.name, color: input.color }, cursor })
      return awarenessUpdates
    }
    case 'presenceSnapshot': return presenceSnapshot()
    case 'presenceApplySnapshot': applyPresenceSnapshot(input); return null
    case 'presenceApply': applyAwarenessUpdate(awareness, Uint8Array.from(input.data), input.origin); return null
    case 'presenceRemoveOrigin': removeAwarenessStates(awareness, awarenessOrigins.get(input) || [], 'remote'); awarenessOrigins.delete(input); return null
    case 'presenceTick': awarenessUpdates = []; globalThis.relayRunIntervals(); return awarenessUpdates
    case 'presenceClearRemote': removeAwarenessStates(awareness, [...awareness.getStates().keys()].filter(id => id !== awareness.clientID), 'remote'); return null
    case 'presenceStates': return [...awareness.getStates()].filter(([id]) => id !== awareness.clientID).map(([id, state]) => ({
      id, name: typeof state.user?.name === 'string' ? state.user.name.slice(0, 100) : 'Collaborator',
      color: typeof state.user?.color === 'string' ? state.user.color : '#666666',
      anchor: state.cursor?.anchor ? safeAnchor(state.cursor.anchor) : null,
      head: state.cursor?.head ? safeAnchor(state.cursor.head) : null
    }))
    case 'apply': Y.applyUpdate(doc, Uint8Array.from(input), 'relay.remote'); return null
    case 'state': return Array.from(Y.encodeStateAsUpdate(doc, input === null ? undefined : Uint8Array.from(input)))
    case 'mergeUpdates': return Array.from(Y.mergeUpdates(input.map(value => Uint8Array.from(value))))
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
      if (!Number.isSafeInteger(input.association ?? 0)) throw Error('Invalid relative association')
      return Array.from(Y.encodeRelativePosition(Y.createRelativePositionFromTypeIndex(target, input.index, input.association || 0)))
    }
    case 'resolve': return absolutePosition(Y.decodeRelativePosition(Uint8Array.from(input)), false)
    case 'resolveRange': {
      if (input.version !== 1) throw Error('Unsupported relative range version')
      const anchorPosition = relativePosition(input.anchor)
      const headPosition = relativePosition(input.head)
      const anchor = absolutePosition(anchorPosition, true)
      const head = absolutePosition(headPosition, true)
      return anchor && head ? { anchor, head } : null
    }
    default: throw Error('Unknown collaboration command')
  }
}
// JSON boundary avoids crossing JavaScriptCore object/thread lifetimes into Swift.
globalThis.relayCollaborationCall = (command, json) => JSON.stringify(call(command, JSON.parse(json)))
