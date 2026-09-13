import * as Y from 'yjs'
import { captureTextItems, resolveTextItems } from './text-items.js'
import { prepareProseLineage } from './prose-lineage.js'
import { prepareHistoryLineage, preserveHistoryDescendants, performHistoryWithMarks } from './history-lineage.js'
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
const undo = new Y.UndoManager(root, { trackedOrigins: new Set([localOrigin]), captureTimeout: 0, deleteFilter: preserveHistoryDescendants })
const formattingKey = Symbol('relay.native.formatting')
const lineageKey = Symbol('relay.native.lineage')
let lineageCapture = null
let formattingCapture = null
let historyCapture = null
undo.on('stack-item-added', ({ stackItem, origin }) => {
  if (historyCapture && origin === undo) historyCapture.inverse.push(stackItem)
  else if (lineageCapture && origin === localOrigin) stackItem.meta.set(lineageKey, lineageCapture)
  else if (formattingCapture && origin === localOrigin) stackItem.meta.set(formattingKey, formattingCapture)
})
undo.on('stack-item-updated', ({ stackItem }) => {
  // Even a text-equal replacement or a second mark operation makes a mixed item
  // ineligible. Only an isolated explicit formatting command carries evidence.
  stackItem.meta.delete(formattingKey)
  stackItem.meta.delete(lineageKey)
  if (historyCapture) historyCapture.mixed = true
})
undo.on('stack-item-popped', ({ stackItem }) => {
  if (historyCapture) historyCapture.performed.push(stackItem)
})
function history(redo, prepared = null) {
  if (historyCapture) throw Error('Nested history operation')
  const capture = { inverse: [], performed: [], mixed: false }
  historyCapture = capture
  localUpdates = []
  try {
    const execution = prepared ? performHistoryWithMarks(doc, undo, redo, lineageKey) : null
    const item = execution ? execution.item : (redo ? undo.redo() : undo.undo())
    const mark = item && item.meta.get(formattingKey)
    const proven = (mark === 'bold' || mark === 'italic') && !capture.mixed &&
      capture.performed.length === 1 && capture.performed[0] === item && capture.inverse.length === 1
    // Yjs creates the inverse item before reporting the actual popped item and
    // may skip ineffective stack entries. Never infer evidence from stack tops.
    for (const inverse of capture.inverse) {
      if (proven) inverse.meta.set(formattingKey, mark)
      else inverse.meta.delete(formattingKey)
    }
    if (prepared) {
      if (!item || item.meta.get(lineageKey)?.operationID !== prepared.reference || capture.mixed ||
          capture.performed.length !== 1 || capture.performed[0] !== item || capture.inverse.length !== 1) {
        throw Error('History execution diverged from preflight')
      }
      capture.inverse[0].meta.set(lineageKey, { operationID: prepared.operationID, copies: execution.inverseCopies })
      const actual = Y.encodeStateAsUpdate(doc)
      if (actual.length !== prepared.expectedState.length || actual.some((byte, i) => byte !== prepared.expectedState[i])) {
        throw Error('History state diverged from preflight')
      }
    }
    return { updates: localUpdates, formattingMark: proven ? mark : null }
  } finally { historyCapture = null }
}
function nativeFormatting(operation) {
  const keys = Object.keys(operation.attributes || {})
  if (operation.kind !== 'formatText' || keys.length !== 1 || !['bold', 'italic'].includes(keys[0]) ||
      undo.captureTimeout !== 0 || formattingCapture) throw Error('Expected isolated native bold or italic command')
  const value = operation.attributes[keys[0]]
  if (value !== null && (typeof value !== 'object' || Array.isArray(value) || Object.keys(value).length)) {
    throw Error('Invalid native formatting mark')
  }
  undo.stopCapturing()
  formattingCapture = keys[0]
  localUpdates = []
  try { edit(operation); return localUpdates }
  finally { formattingCapture = null; undo.stopCapturing() }
}
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
function proseBlocks(documentRoot = root) {
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
  walk(documentRoot)
  return blocks
}
function removeBlock(block, documentRoot = root) {
  let element = block.p
  while (element && element !== documentRoot) {
    const parent = element.parent
    parent.delete(parent.toArray().indexOf(element), 1)
    if (parent.length || parent === documentRoot) return
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
function insertInline(p, offset, content, attributes, inserted = null) {
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
  if (parts.length === 1) { target.insert(local, content, attributes); inserted?.(target, local, content.length); return }
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
function paragraph(content, attributes, tail = [], hooks = null) {
  const p = new Y.XmlElement('paragraph')
  // Populate after integration: insertInline relies on live Yjs lengths.
  return { p, populate: () => {
    insertInline(p, 0, content, attributes, hooks?.inserted)
    const copied = tail.map(node); p.insert(p.length, copied)
    if (copied.length) hooks?.copied(copied)
  } }
}
// Explicit paragraph-end Return only. Unlike generic splitting, this operation
// never moves/recreates existing content and always creates an empty XmlText.
function nativeParagraphAfter(input) {
  if (!input || Object.keys(input).sort().join(',') !== 'endUTF16,index' ||
      !Number.isSafeInteger(input.index) || input.index < 0 ||
      !Number.isSafeInteger(input.endUTF16) || input.endUTF16 < 0 ||
      undo.captureTimeout !== 0 || formattingCapture) throw Error('Expected isolated paragraph-end Return')
  const target = root.get(input.index)
  if (!(target instanceof Y.XmlElement) || target.nodeName !== 'paragraph' ||
      Object.keys(target.getAttributes()).length || target.length !== 1 ||
      !(target.get(0) instanceof Y.XmlText) || /[\n\r\u2028\u2029\ufffc]/u.test(target.get(0).toString())) {
    throw Error('Expected top-level paragraph with one text leaf')
  }
  let end = 0, found = false
  for (const block of proseBlocks()) {
    end += block.length
    if (block.p === target) { found = true; break }
    end++
  }
  if (!found || end !== input.endUTF16) throw Error('Paragraph-end position changed')
  const previous = root.toArray(), previousValue = JSON.stringify(previous.map(snapshot))
  const vector = Y.encodeStateVector(doc), clocks = Y.decodeStateVector(vector)
  const deletions = () => JSON.stringify([...Y.decodeUpdate(Y.encodeStateAsUpdate(doc, vector)).ds.clients]
    .sort(([a], [b]) => a - b).map(([client, ranges]) => [client, ranges.map(({ clock, len }) => [clock, len])]))
  const previousDeletes = deletions()
  const next = new Y.XmlElement('paragraph')
  next.insert(0, [new Y.XmlText()])
  localUpdates = []
  undo.stopCapturing()
  doc.transact(() => root.insert(input.index + 1, [next]), localOrigin)
  undo.stopCapturing()
  const retained = root.toArray().filter((_, index) => index !== input.index + 1)
  const paragraphID = Y.createRelativePositionFromTypeIndex(root, input.index + 1).item
  const textID = Y.createRelativePositionFromTypeIndex(next, 0).item
  const expected = new Map(clocks), after = Y.decodeStateVector(Y.encodeStateVector(doc))
  if (!paragraphID || !textID || paragraphID.client !== textID.client ||
      paragraphID.clock !== (clocks.get(paragraphID.client) || 0) || textID.clock !== paragraphID.clock + 1) {
    throw Error('Unproven paragraph allocation')
  }
  expected.set(paragraphID.client, paragraphID.clock + 2)
  // Exact allocations plus unchanged deletes prove no prior item identities
  // were replaced, including invisible mutations outside the rendered root.
  if (after.size !== expected.size || [...expected].some(([client, clock]) => after.get(client) !== clock) ||
      deletions() !== previousDeletes || retained.length !== previous.length ||
      retained.some((value, index) => value !== previous[index]) ||
      JSON.stringify(retained.map(snapshot)) !== previousValue || localUpdates.length !== 1 ||
      next.length !== 1 || !(next.get(0) instanceof Y.XmlText) || next.get(0).length !== 0) {
    throw Error('Unproven paragraph mutation')
  }
  return { updates: localUpdates, evidence: { paragraphIndex: input.index, endUTF16: end } }
}
function nativeParagraphPaste(input) {
  if (!input || Object.keys(input).sort().join(',') !== 'endUTF16,index,text' ||
      !Number.isSafeInteger(input.index) || input.index < 0 || !Number.isSafeInteger(input.endUTF16) || input.endUTF16 < 0 ||
      typeof input.text !== 'string' || input.text.length > 131072 || !input.text.includes('\n') ||
      /[\r\u2028\u2029\ufffc]/u.test(input.text) || undo.captureTimeout !== 0 || formattingCapture) {
    throw Error('Expected bounded isolated plain multiline paste')
  }
  for (let i = 0; i < input.text.length; i++) {
    const c = input.text.charCodeAt(i)
    if (c >= 0xD800 && c <= 0xDBFF) {
      const next = input.text.charCodeAt(++i)
      if (!(next >= 0xDC00 && next <= 0xDFFF)) throw Error('Invalid paste Unicode')
    } else if (c >= 0xDC00 && c <= 0xDFFF) throw Error('Invalid paste Unicode')
  }
  const lines = input.text.split('\n'), count = lines.length - 1
  if (count > 4096 || lines.filter(Boolean).length > 4096) throw Error('Paste paragraph limit exceeded')
  const queue = [root]; let nodes = 0
  while (queue.length) {
    const node = queue.pop()
    if (++nodes + count * 2 > 65536) throw Error('Paste document traversal limit exceeded')
    if (node instanceof Y.XmlFragment && !(node instanceof Y.XmlText)) {
      if (nodes + queue.length + node.length + count * 2 > 65536) throw Error('Paste document traversal limit exceeded')
      for (let i = 0; i < node.length; i++) queue.push(node.get(i))
    }
  }
  const target = root.get(input.index)
  if (!(target instanceof Y.XmlElement) || target.nodeName !== 'paragraph' || Object.keys(target.getAttributes()).length ||
      target.length !== 1 || !(target.get(0) instanceof Y.XmlText)) throw Error('Expected top-level paragraph with one text leaf')
  const leaf = target.get(0), oldLength = leaf.length, oldDelta = leaf.toDelta()
  if (oldDelta.some(part => typeof part.insert !== 'string' || /[\n\r\u2028\u2029\ufffc]/u.test(part.insert))) throw Error('Unsupported paste target')
  let end = 0, found = false
  for (const block of proseBlocks()) {
    end += block.length
    if (block.p === target) { found = true; break }
    end++
  }
  if (!found || end !== input.endUTF16) throw Error('Paragraph-end position changed')
  const previous = root.toArray(), oldOthers = JSON.stringify(previous.filter(p => p !== target).map(snapshot))
  const vector = Y.encodeStateVector(doc), clocks = Y.decodeStateVector(vector)
  const deletes = () => JSON.stringify([...Y.decodeUpdate(Y.encodeStateAsUpdate(doc, vector)).ds.clients]
    .sort(([a], [b]) => a - b).map(([client, ranges]) => [client, ranges.map(({ clock, len }) => [clock, len])]))
  const priorDeletes = deletes(), added = []
  localUpdates = []; undo.stopCapturing()
  doc.transact(() => {
    if (lines[0]) leaf.insert(oldLength, lines[0], {})
    for (let i = 1; i < lines.length; i++) {
      const p = new Y.XmlElement('paragraph'), text = new Y.XmlText()
      p.insert(0, [text]); root.insert(input.index + i, [p]); added.push(p)
      if (lines[i]) text.insert(0, lines[i], {})
    }
  }, localOrigin)
  undo.stopCapturing()
  const afterClocks = Y.decodeStateVector(Y.encodeStateVector(doc))
  const expectedUnits = lines.reduce((n, line) => n + line.length, count * 2)
  if (afterClocks.get(doc.clientID) !== (clocks.get(doc.clientID) || 0) + expectedUnits ||
      [...afterClocks].some(([client, clock]) => client !== doc.clientID && clocks.get(client) !== clock)) {
    throw Error('Unproven paste allocation')
  }
  const retained = root.toArray().filter(p => !added.includes(p))
  let remaining = oldLength
  const prefix = leaf.toDelta().flatMap(part => {
    const text = part.insert.slice(0, remaining); remaining -= text.length
    return text ? [{ ...part, insert: text }] : []
  })
  if (localUpdates.length !== 1 || deletes() !== priorDeletes ||
      retained.length !== previous.length || retained.some((p, i) => p !== previous[i]) ||
      target.length !== 1 || target.get(0) !== leaf || Object.keys(target.getAttributes()).length ||
      leaf.length !== oldLength + lines[0].length || JSON.stringify(prefix) !== JSON.stringify(oldDelta) ||
      JSON.stringify(retained.filter(p => p !== target).map(snapshot)) !== oldOthers) throw Error('Unproven paste mutation')
  const selection = { version: 1, runs: [] }
  for (let i = 0; i < lines.length; i++) {
    const p = root.get(input.index + i), text = p.get(0)
    if (i && (p !== added[i - 1] || p.nodeName !== 'paragraph' || Object.keys(p.getAttributes()).length || p.length !== 1 ||
        !(text instanceof Y.XmlText) || text.length !== lines[i].length)) throw Error('Unproven paste structure')
    const index = i ? 0 : oldLength
    let offset = 0
    for (const part of text.toDelta()) {
      offset += part.insert.length
      if (offset > index && Object.keys(part.attributes || {}).length) throw Error('Paste inserted marked text')
    }
    const captured = captureTextItems(root, { path: [input.index + i, 0], index, length: lines[i].length })
    if (captured.runs.some(run => run.item.clock < (clocks.get(run.item.client) || 0))) throw Error('Paste reused old text identity')
    selection.runs.push(...captured.runs)
  }
  const resolved = resolveTextItems(doc, root, selection)
  if (resolved.unavailableRuns.length || resolved.collapsedUnits || resolved.segments.map(s => s.text).join('') !== lines.join('')) {
    throw Error('Unproven paste selection')
  }
  return { updates: localUpdates, evidence: { paragraphIndex: input.index, endUTF16: end, paragraphCount: count },
    insertedTextItems: Array.from(new TextEncoder().encode(JSON.stringify(selection))) }
}
function replaceProse(input, targetDoc = doc, targetRoot = root, hooks = null) {
  const blocks = proseBlocks(targetRoot)
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
  hooks?.tail(blocks[last].p, end, first !== last || lines.length !== 1)
  targetDoc.transact(() => {
    if (first === last && !firstRule && lines.length === 1) {
      deleteInline(blocks[first].p, start, end)
      insertInline(blocks[first].p, start, input.text, input.attributes || {}, hooks?.inserted)
      return
    }
    let destination = blocks[first].p
    if (firstRule) {
      if (first === last && start === end && !input.text) return
      const parent = destination.parent, index = parent.toArray().indexOf(destination) + (start === 1 ? 1 : 0)
      const created = new Y.XmlElement('paragraph'); parent.insert(index, [created]); destination = created
      if (start === 0 && (first !== last || end === 1)) removeBlock(blocks[first], targetRoot)
    } else deleteInline(destination, start, inlineLength(destination))
    for (let i = last; i > first; i--) {
      if (i === last && lastRule && end === 0) continue
      removeBlock(blocks[i], targetRoot)
    }
    insertInline(destination, firstRule ? 0 : start, lines[0], input.attributes || {}, hooks?.inserted)
    if (lines.length === 1) {
      const copied = tail.map(node); destination.insert(destination.length, copied)
      if (copied.length) hooks?.copied(copied)
    }
    else {
      const additions = lines.slice(1).map((line, i) => paragraph(line, input.attributes || {}, i === lines.length - 2 ? tail : [], hooks))
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
    case 'captureTextItems': return captureTextItems(root, input)
    case 'resolveTextItems': return resolveTextItems(doc, root, input)
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
    // Yjs 13.6.32 retains unresolved structures and deletes independently.
    // Fail closed if the bundled store shape changes; a state vector alone does
    // not cover pending deletes. This is completeness, never source authority.
    case 'integrationStatus': {
      if (!Object.hasOwn(doc.store, 'pendingStructs') || !Object.hasOwn(doc.store, 'pendingDs')) {
        throw new Error('Unsupported integration status')
      }
      return { hasPendingStructs: doc.store.pendingStructs !== null, hasPendingDeletes: doc.store.pendingDs !== null }
    }
    case 'apply': Y.applyUpdate(doc, Uint8Array.from(input), 'relay.remote'); return null
    case 'state': return Array.from(Y.encodeStateAsUpdate(doc, input === null ? undefined : Uint8Array.from(input)))
    case 'mergeUpdates': return Array.from(Y.mergeUpdates(input.map(value => Uint8Array.from(value))))
    case 'vector': return Array.from(Y.encodeStateVector(doc))
    case 'snapshot': return snapshot(root)
    case 'replaceProse': localUpdates = []; replaceProse(input); return localUpdates
    case 'replaceProseWithLineage': {
      if (undo.captureTimeout !== 0 || formattingCapture || historyCapture || lineageCapture) throw Error('Expected isolated prose operation')
      const prepared = prepareProseLineage(doc, input, replaceProse)
      localUpdates = []; undo.stopCapturing()
      // No await or callback boundary between preflight and the same mutation.
      lineageCapture = input.operation_id ? { operationID: input.operation_id, copies: prepared.lineage.copies } : null
      try { replaceProse(prepared.input) } finally { lineageCapture = null; undo.stopCapturing() }
      const actual = Y.encodeStateAsUpdate(doc)
      if (actual.length !== prepared.expectedState.length || actual.some((byte, i) => byte !== prepared.expectedState[i])) {
        throw Error('Prose lineage execution diverged from preflight')
      }
      return { updates: localUpdates, insertedTextItems: prepared.insertedTextItems, lineage: prepared.lineage }
    }
    case 'edit': localUpdates = []; edit(input); return localUpdates
    case 'nativeFormatting': return nativeFormatting(input)
    case 'nativeParagraphAfter': return nativeParagraphAfter(input)
    case 'nativeParagraphPaste': return nativeParagraphPaste(input)
    case 'beginUndoGroup': undo.stopCapturing(); undo.captureTimeout = Number.MAX_SAFE_INTEGER; return null
    case 'endUndoGroup': undo.stopCapturing(); undo.captureTimeout = 0; return null
    case 'undoWithLineage':
    case 'redoWithLineage': {
      if (formattingCapture || historyCapture || lineageCapture) throw Error('Nested history evidence')
      const redo = command === 'redoWithLineage'
      const prepared = prepareHistoryLineage(doc, undo, redo, input, lineageKey)
      const result = history(redo, prepared)
      return { updates: result.updates, insertedTextItems: prepared.insertedTextItems, lineage: prepared.lineage }
    }
    case 'undo': return history(false).updates
    case 'redo': return history(true).updates
    case 'undoWithFormattingEvidence': return history(false)
    case 'redoWithFormattingEvidence': return history(true)
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
