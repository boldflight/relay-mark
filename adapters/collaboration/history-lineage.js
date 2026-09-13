import * as Y from 'yjs'
import { captureTextItems, resolveTextItems } from './text-items.js'
import yjsPackage from 'yjs/package.json' with { type: 'json' }

const maximumStructs = 65536, maximumStack = 4096
const equal = (a, b) => a.length === b.length && a.every((byte, i) => byte === b[i])
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value)
const id = value => value && Number.isSafeInteger(value.client) && value.client >= 0 &&
  Number.isSafeInteger(value.clock) && value.clock >= 0 && value.clock < 4294967296
const key = value => `${value.client}:${value.clock}`
function structs(doc) {
  if (!(doc.store?.clients instanceof Map)) throw Error('Unsupported Yjs history store')
  const result = []
  for (const [client, values] of doc.store.clients) {
    if (!Array.isArray(values) || values.length + result.length > maximumStructs) throw Error('Yjs history struct limit')
    for (const value of values) {
      if (!(value instanceof Y.Item || value instanceof Y.GC) || !id(value.id) || value.id.client !== client ||
          !Number.isSafeInteger(value.length) || value.length < 1 ||
          (value instanceof Y.Item && value.redone !== null && !id(value.redone))) throw Error('Unsupported Yjs history struct')
      result.push(value)
    }
  }
  return result
}
function cloneSet(value) {
  if (!(value?.clients instanceof Map)) throw Error('Unsupported Yjs history delete set')
  let count = 0
  for (const [client, ranges] of value.clients) {
    if (!Number.isSafeInteger(client) || client < 0 || !Array.isArray(ranges)) throw Error('Unsupported history client')
    for (const range of ranges) {
      if (++count > maximumStructs || !Number.isSafeInteger(range.clock) || range.clock < 0 ||
          !Number.isSafeInteger(range.len) || range.len <= 0 || range.clock + range.len > 4294967296) throw Error('Unsupported history interval')
    }
  }
  // mergeDeleteSets copies arrays, but normalizes shared DeleteItem.len fields.
  // Clone intervals too: even a refused scratch operation must not touch owner metadata.
  const copied = Y.createDeleteSet()
  for (const [client, ranges] of value.clients) copied.clients.set(client,
    ranges.map(range => ({ clock: range.clock, len: range.len })))
  return Y.mergeDeleteSets([copied])
}
function cloneStack(value) {
  if (!Array.isArray(value) || value.length > maximumStack) throw Error('Unsupported history stack')
  return value.map(item => {
    if (!(item?.meta instanceof Map)) throw Error('Unsupported history metadata')
    return { insertions: cloneSet(item.insertions), deletions: cloneSet(item.deletions), meta: new Map(item.meta) }
  })
}
function selection(item, destination) {
  if (!(item.parent instanceof Y.XmlText) || !(item.content instanceof Y.ContentString)) throw Error('Unsupported restored text')
  const type = Y.createRelativePositionFromTypeIndex(item.parent, 0, 0).type
  if (!id(type) || !id(destination)) throw Error('Missing restored text identity')
  return { version: 1, runs: [{ item: { client: destination.client, clock: destination.clock },
    type: { client: type.client, clock: type.clock }, count: item.length }] }
}
function identities(value) {
  const values = new Set()
  for (const run of value.runs) for (let i = 0; i < run.count; i++) {
    if (values.size >= 131072) throw Error('History text limit')
    const value = `${run.item.client}:${run.item.clock + i}`
    if (values.has(value)) throw Error('Overlapping history ancestry')
    values.add(value)
  }
  return values
}

// UndoManager deletes children before parents. Keep a container when surviving
// descendants remain after its own tracked children have been removed. This
// preserves peer text without implementing a different inverse operation.
export function preserveHistoryDescendants(item) {
  if (!(item instanceof Y.Item) || !(item.content instanceof Y.ContentType)) return true
  const type = item.content.type
  if (type instanceof Y.XmlText || type instanceof Y.XmlFragment) return type.length === 0
  return false
}

function restoredCopies(doc, prior, links) {
  const root = doc.getXmlFragment('default'), copies = []
    for (const item of structs(doc)) {
      if (!(item instanceof Y.Item) || !(item.content instanceof Y.ContentString) || !item.redone ||
          item.id.clock >= (prior.get(item.id.client) || 0) || item.redone.clock < (prior.get(item.redone.client) || 0) ||
          links.get(key(item.id)) === key(item.redone)) continue
      const target = Y.getItem(doc.store, item.redone)
      if (!(target instanceof Y.Item) || !target.id || target.id.clock !== item.redone.clock || target.length !== item.length) {
        throw Error('Unsupported split restored ancestry')
      }
      const source = selection(item, item.id), destination = selection(target, target.id)
      const resolved = resolveTextItems(doc, root, destination)
      if (resolved.unavailableRuns.length || resolved.collapsedUnits) throw Error('Unreachable restored ancestry')
      copies.push({ source, destination })
    }
  return copies
}

function expanded(value) {
  identities(value)
  return value.runs.flatMap(run => Array.from({ length: run.count }, (_, n) => ({
    item: { client: run.item.client, clock: run.item.clock + n }, type: { ...run.type }
  })))
}
function visibleAttributes(doc) {
  const root = doc.getXmlFragment('default'), found = new Map()
  let nodes = 0
  function walk(type, path) {
    if (++nodes > maximumStructs || path.length > 128) throw Error('History formatting tree limit')
    if (type instanceof Y.XmlText) {
      let offset = 0
      for (const delta of type.toDelta()) {
        if (typeof delta.insert !== 'string') throw Error('Unsupported history formatting embed')
        const captured = captureTextItems(root, { path, index: offset, length: delta.insert.length })
        const attributes = JSON.parse(JSON.stringify(delta.attributes || {}))
        for (const unit of expanded(captured)) {
          if (found.size >= 131072) throw Error('History formatting unit limit')
          found.set(key(unit.item), { unit, leaf: type, path, offset: offset++, attributes })
        }
      }
    } else if (type instanceof Y.XmlFragment) type.toArray().forEach((child, i) => walk(child, [...path, i]))
    else throw Error('Unsupported history formatting type')
  }
  walk(root, [])
  return found
}
function appendPair(result, source, destination) {
  const last = result.at(-1), a = last?.source.runs[0], b = last?.destination.runs[0]
  const next = (run, unit) => run && run.item.client === unit.item.client &&
    run.item.clock + run.count === unit.item.clock && key(run.type) === key(unit.type)
  if (next(a, source) && next(b, destination)) { a.count++; b.count++ }
  else {
    if (result.length >= 4096) throw Error('History formatting counterpart limit')
    result.push({ source: { version: 1, runs: [{ ...source, count: 1 }] },
      destination: { version: 1, runs: [{ ...destination, count: 1 }] } })
  }
}
function canonicalAttributes(value) {
  const ordered = value => Array.isArray(value) ? value.map(ordered) :
    value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(name => [name, ordered(value[name])])) : value
  return JSON.stringify(ordered(value))
}

// The local pinned hook runs after native inverse mutations but before cleanup.
// Both owners execute this function. No inverse algorithm or flag manipulation.
export function performHistoryWithMarks(doc, manager, redo, lineageKey) {
  if (manager.relayHistoryTransactionHookVersion !== 1 || manager.beforeHistoryTransactionCommit !== null) {
    throw Error('History transaction hook unavailable')
  }
  const top = (redo ? manager.redoStack : manager.undoStack).at(-1), metadata = top?.meta.get(lineageKey)
  if (!uuid(metadata?.operationID) || !Array.isArray(metadata.copies) || metadata.copies.length > 4096) {
    throw Error('Untracked history formatting counterpart')
  }
  const current = visibleAttributes(doc), counterparts = new Map()
  for (const pair of metadata.copies) {
    const source = expanded(pair.source), destination = expanded(pair.destination)
    if (source.length !== destination.length) throw Error('History counterpart length mismatch')
    source.forEach((unit, i) => {
      if (counterparts.size >= 131072 || counterparts.has(key(unit.item))) throw Error('Ambiguous history counterpart')
      const live = current.get(key(destination[i].item))
      if (live && key(live.unit.type) !== key(destination[i].type)) throw Error('History counterpart type mismatch')
      counterparts.set(key(unit.item), { source: unit, counterpart: destination[i], attributes: live?.attributes })
    })
  }
  const prior = Y.decodeStateVector(Y.encodeStateVector(doc))
  const links = new Map(structs(doc).filter(item => item instanceof Y.Item).map(item => [key(item.id), item.redone && key(item.redone)]))
  let execution = null
  manager.beforeHistoryTransactionCommit = ({ stackItem }) => {
    if (stackItem !== top || execution) throw Error('History hook selected a different item')
    const copies = restoredCopies(doc, prior, links), after = visibleAttributes(doc), inverseCopies = [], plans = []
    // Removing local formatting markers can otherwise change surviving peer
    // text even when its identity remains. Preserve its current attributes too.
    for (const [identity, target] of after) {
      const previous = current.get(identity)
      if (previous && key(previous.unit.type) === key(target.unit.type) &&
          canonicalAttributes(previous.attributes) !== canonicalAttributes(target.attributes)) {
        plans.push({ ...target, desired: previous.attributes })
      }
    }
    for (const copy of copies) {
      const source = expanded(copy.source), destination = expanded(copy.destination)
      source.forEach((unit, i) => {
        const mirror = counterparts.get(key(unit.item))
        if (!mirror) return
        if (key(mirror.source.type) !== key(unit.type)) throw Error('Restored counterpart type mismatch')
        appendPair(inverseCopies, mirror.counterpart, destination[i])
        if (mirror.attributes === undefined) return
        const target = after.get(key(destination[i].item))
        if (!target || key(target.unit.type) !== key(destination[i].type)) throw Error('Restored counterpart unavailable')
        plans.push({ ...target, desired: mirror.attributes })
      })
    }
    const grouped = new Map()
    for (const plan of plans) {
      const rows = grouped.get(plan.leaf) || []; rows.push(plan); grouped.set(plan.leaf, rows)
    }
    for (const [leaf, rows] of grouped) {
      rows.sort((a, b) => a.offset - b.offset)
      let position = 0
      while (position < rows.length) {
        const first = rows[position++]; let length = 1
        while (position < rows.length && rows[position].offset === first.offset + length &&
            canonicalAttributes(rows[position].desired) === canonicalAttributes(first.desired)) { position++; length++ }
        const changes = { ...first.desired }
        for (const row of rows.slice(position - length, position)) for (const name of Object.keys(row.attributes)) {
          if (!Object.hasOwn(first.desired, name)) changes[name] = null
        }
        // Validate whole scalar boundaries before format() can split a Yjs string.
        captureTextItems(doc.getXmlFragment('default'), { path: first.path, index: first.offset, length })
        if (rows.slice(position - length, position).some(row =>
            canonicalAttributes(row.attributes) !== canonicalAttributes(first.desired))) leaf.format(first.offset, length, changes)
      }
    }
    execution = { copies, inverseCopies }
  }
  try {
    const item = redo ? manager.redo() : manager.undo()
    if (!execution) throw Error('History made no effective change')
    return { ...execution, item }
  } finally { manager.beforeHistoryTransactionCommit = null }
}

// Version-pinned access to nonserialized UndoManager/Item metadata lives ONLY
// here. No custom inverse algorithm: both preflight and live use Y.UndoManager.
export function prepareHistoryLineage(live, owner, redo, input, lineageKey) {
  if (yjsPackage.version !== '13.6.32' || !input || Object.keys(input).join(',') !== 'operation_id' || !uuid(input.operation_id) ||
      owner.relayHistoryTransactionHookVersion !== 1 || owner.beforeHistoryTransactionCommit !== null ||
      owner.doc !== live || owner.captureTimeout !== 0 || owner.undoing || owner.redoing || owner.currStackItem !== null ||
      owner.scope.length !== 1 || owner.scope[0] !== live.getXmlFragment('default') || owner.ignoreRemoteMapChanges !== false) {
    throw Error('Unsupported isolated Yjs history owner')
  }
  const before = Y.encodeStateAsUpdate(live), clientID = live.clientID
  const prior = Y.decodeStateVector(Y.encodeStateVector(live)), oldStructs = structs(live)
  const undoStack = cloneStack(owner.undoStack), redoStack = cloneStack(owner.redoStack)
  const stack = redo ? redoStack : undoStack, top = stack.at(-1), reference = top?.meta.get(lineageKey)?.operationID
  if (!uuid(reference) || reference === input.operation_id) throw Error('History requires distinct durable operation identities')
  const staged = new Y.Doc({ gc: false }); let manager
  try {
    Y.applyUpdate(staged, before); staged.clientID = clientID
    // Encoding deliberately omits redone pointers and may merge split structs.
    // Restore exact boundaries with exported helpers before copying those links.
    Y.transact(staged, transaction => {
      for (const original of oldStructs) if (original instanceof Y.Item) {
        const copied = Y.getItemCleanStart(transaction, original.id)
        Y.getItemCleanEnd(transaction, staged.store, Y.createID(original.id.client, original.id.clock + original.length - 1))
        if (!(copied instanceof Y.Item) || copied.length !== original.length) throw Error('Cannot clone history item boundary')
        copied.redone = original.redone === null ? null : Y.createID(original.redone.client, original.redone.clock)
      }
    }, 'relay.history.preflight')
    manager = new Y.UndoManager(staged.getXmlFragment('default'), { trackedOrigins: new Set(['relay.local.editor']), captureTimeout: 0, deleteFilter: preserveHistoryDescendants })
    manager.undoStack = undoStack; manager.redoStack = redoStack
    const inverse = [], popped = []; let mixed = false
    manager.on('stack-item-added', ({ stackItem, origin }) => { if (origin === manager) inverse.push(stackItem) })
    manager.on('stack-item-updated', () => { mixed = true })
    manager.on('stack-item-popped', ({ stackItem }) => popped.push(stackItem))
    const execution = performHistoryWithMarks(staged, manager, redo, lineageKey)
    const performed = execution.item
    if (performed !== top || popped.length !== 1 || popped[0] !== top || inverse.length !== 1 || mixed) throw Error('Unproven effective history item')
    const root = staged.getXmlFragment('default'), copies = execution.copies
    if (copies.length > 4096) throw Error('History copy limit')
    const accounted = identities({ runs: copies.flatMap(copy => copy.destination.runs) }), actual = { runs: [] }
    function walk(type, path) {
      if (path.length > 128) throw Error('History tree limit')
      if (type instanceof Y.XmlText) {
        for (const run of captureTextItems(root, { path, index: 0, length: type.length }).runs) {
          const start = Math.max(run.item.clock, prior.get(run.item.client) || 0)
          if (start < run.item.clock + run.count) actual.runs.push({ ...run, item: { ...run.item, clock: start }, count: run.item.clock + run.count - start })
        }
      } else if (type instanceof Y.XmlFragment) type.toArray().forEach((child, i) => walk(child, [...path, i]))
      else throw Error('Unsupported restored tree')
    }
    walk(root, [])
    const found = identities(actual)
    if (found.size !== accounted.size || [...found].some(value => !accounted.has(value))) throw Error('Unaccounted restored text')
    if (live.clientID !== clientID || !equal(before, Y.encodeStateAsUpdate(live))) throw Error('History prestate changed')
    return { reference, operationID: input.operation_id, inverseCopies: execution.inverseCopies, expectedState: Y.encodeStateAsUpdate(staged),
      insertedTextItems: Array.from(new TextEncoder().encode('{"version":1,"runs":[]}')),
      lineage: { version: 1, operation: { kind: redo ? 'redo' : 'undo', transaction_id: reference }, copies } }
  } finally { manager?.destroy(); staged.destroy() }
}
