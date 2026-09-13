import { digest } from 'lib0/hash/sha256'

const maxReceipts = 16384, maxUnits = 131072, maxBytes = 64 * 1024 * 1024
const uuid = x => typeof x === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(x)
const json = x => JSON.stringify(x)
const clone = x => JSON.parse(json(x))
export const placementUpdateHash = bytes => Array.from(digest(bytes), b => b.toString(16).padStart(2, '0')).join('')
function keys(x, expected) {
  if (!x || typeof x !== 'object' || Array.isArray(x) || Object.keys(x).sort().join() !== expected.sort().join()) throw Error('Invalid placement fields')
}
function binding(x) {
  keys(x, ['document_id', 'incarnation'])
  if (!uuid(x.document_id) || typeof x.incarnation !== 'string' || !x.incarnation.length || new TextEncoder().encode(x.incarnation).length > 256) throw Error('Invalid placement binding')
  return { document_id: x.document_id, incarnation: x.incarnation }
}
function id(x) {
  keys(x, ['client', 'clock'])
  if (!Number.isSafeInteger(x.client) || x.client < 0 || x.client > Number.MAX_SAFE_INTEGER ||
      !Number.isSafeInteger(x.clock) || x.clock < 0 || x.clock > 4294967295) throw Error('Invalid placement identity')
  return { client: x.client, clock: x.clock }
}
const key = x => `${x.item.client}:${x.item.clock}@${x.type.client}:${x.type.clock}`
function selection(x) {
  keys(x, ['version', 'runs'])
  if (x.version !== 1 || !Array.isArray(x.runs) || x.runs.length > 4096) throw Error('Invalid placement selection')
  let count = 0
  const found = new Set()
  return x.runs.flatMap(run => {
    keys(run, ['item', 'type', 'count'])
    const item = id(run.item), type = id(run.type)
    if (!Number.isSafeInteger(run.count) || run.count < 1 || item.clock + run.count > 4294967296 || (count += run.count) > maxUnits) throw Error('Placement selection limit')
    return Array.from({ length: run.count }, (_, n) => {
      const unit = { item: { client: item.client, clock: item.clock + n }, type }
      const identity = `${unit.item.client}:${unit.item.clock}`
      if (found.has(identity)) throw Error('Overlapping placement selection')
      found.add(identity); return unit
    })
  })
}
function receipt(x, expected) {
  keys(x, ['version', 'document_id', 'incarnation', 'update_sha256', 'operation_id', 'operation', 'copies'])
  if (x.version !== 1 || x.document_id !== expected.document_id || x.incarnation !== expected.incarnation ||
      !uuid(x.operation_id) || typeof x.update_sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(x.update_sha256) ||
      !Array.isArray(x.copies) || x.copies.length > 4096) throw Error('Invalid placement receipt')
  keys(x.operation, ['kind', 'reference'])
  const inverse = ['undo', 'redo'].includes(x.operation.kind)
  if (!['replace_prose', 'format', 'undo', 'redo'].includes(x.operation.kind) ||
      (inverse ? !uuid(x.operation.reference) : x.operation.reference !== null) ||
      x.operation.reference === x.operation_id || (x.operation.kind === 'format' && x.copies.length)) throw Error('Invalid placement operation')
  let count = 0, sourceRuns = 0, destinationRuns = 0
  const sources = new Set(), destinations = new Set()
  const pairs = x.copies.flatMap(pair => {
    keys(pair, ['source', 'destination'])
    const a = selection(pair.source), b = selection(pair.destination)
    sourceRuns += pair.source.runs.length; destinationRuns += pair.destination.runs.length
    if (sourceRuns > 4096 || destinationRuns > 4096) throw Error('Placement aggregate run limit')
    if (!a.length || a.length !== b.length || (count += a.length) > maxUnits) throw Error('Invalid placement copy length')
    return a.map((source, n) => {
      const destination = b[n], sk = `${source.item.client}:${source.item.clock}`, dk = `${destination.item.client}:${destination.item.clock}`
      if (sources.has(sk) || destinations.has(dk) || sk === dk) throw Error('Ambiguous placement copies')
      sources.add(sk); destinations.add(dk); return { source, destination }
    })
  })
  if ([...sources].some(x => destinations.has(x))) throw Error('Overlapping placement copies')
  // Canonicalize every object field; duplicate replay is independent of JSON key order.
  const wireSelection = x => ({ version: 1, runs: x.runs.map(r => ({item:id(r.item), type:id(r.type), count:r.count})) })
  return { value: { version: 1, ...expected, update_sha256:x.update_sha256, operation_id:x.operation_id,
    operation:{kind:x.operation.kind,reference:x.operation.reference}, copies:x.copies.map(p=>({source:wireSelection(p.source),destination:wireSelection(p.destination)})) }, pairs }
}

// Immutable candidates let the host save update + candidate snapshot before
// replacing its current graph. This module never mutates a Y.Doc or UndoManager.
export function createPlacementState(expectedBinding) {
  return { version: 1, binding: binding(expectedBinding), receipts: [] }
}
function rebuild(state, expected, allowed = null) {
  keys(state, ['version', 'binding', 'receipts'])
  if (state.version !== 1 || json(binding(state.binding)) !== json(expected) || !Array.isArray(state.receipts) || state.receipts.length > maxReceipts || new TextEncoder().encode(json(state)).length > maxBytes) throw Error('Invalid placement state')
  const known = new Map(), edges = new Map(), incoming = new Map(), canonical = []
  const types = new Map(), components = new Map()
  let retainedUnits = 0
  function component(node) {
    const path=[]; let root=node
    while (components.has(root)) { path.push(root); root=components.get(root) }
    for (const entry of path) components.set(entry,root)
    return root
  }
  for (const row of state.receipts) {
    keys(row, ['trust', 'receipt'])
    if (!['local', 'server'].includes(row.trust)) throw Error('Missing explicit placement trust')
    const {value, pairs} = receipt(row.receipt, expected)
    if (allowed && !allowed.has(value.operation_id)) throw Error('Placement receipt is not retained by host')
    if (known.has(value.operation_id)) throw Error('Duplicate retained placement receipt')
    retainedUnits += pairs.length
    if (retainedUnits > maxUnits) throw Error('Placement graph limit')
    for (const pair of pairs) for (const unit of [pair.source,pair.destination]) {
      const item=`${unit.item.client}:${unit.item.clock}`, type=`${unit.type.client}:${unit.type.clock}`
      if (types.has(item) && types.get(item)!==type) throw Error('Conflicting placement item type')
      types.set(item,type)
    }
    const reference = value.operation.reference && known.get(value.operation.reference)
    if (value.operation.reference && !reference) throw Error('Unknown placement reference')
    if (value.operation.kind === 'redo' && reference.value.operation.kind !== 'undo') throw Error('Invalid redo reference')
    if (value.operation.kind === 'undo' && reference.value.operation.kind === 'undo') throw Error('Invalid undo reference')
    const referenced = new Map((reference?.effective || []).map(p => [key(p.source), p.destination]))
    const effective = pairs.map(p => ({source:referenced.get(key(p.source)) || p.source, destination:p.destination}))
    for (const p of effective) {
      const a = key(p.source), b = key(p.destination)
      if (a === b || (edges.has(a) && edges.get(a) !== b) || (incoming.has(b) && incoming.get(b) !== a)) throw Error('Ambiguous placement successor')
      if (!edges.has(a)) {
        const left=component(a),right=component(b)
        if (left===right) throw Error('Cyclic placement succession')
        components.set(left,right)
      }
      edges.set(a,b); incoming.set(b,a)
      if (edges.size > maxUnits) throw Error('Placement graph limit')
    }
    known.set(value.operation_id,{value,effective}); canonical.push({trust:row.trust,receipt:value})
  }
  return { state:{version:1,binding:expected,receipts:canonical}, known, edges }
}
export function restorePlacementState(snapshot, expectedBinding, receiptIDs) {
  const expected = binding(expectedBinding)
  if (!Array.isArray(receiptIDs) || receiptIDs.length > maxReceipts || receiptIDs.some(x=>!uuid(x)) || new Set(receiptIDs).size !== receiptIDs.length) throw Error('Invalid placement receipt whitelist')
  return rebuild(snapshot,expected,new Set(receiptIDs)).state
}
export function preparePlacementReceipt(state, input) {
  keys(input,['expected_binding','trust','update','receipt'])
  const expected=binding(input.expected_binding), existing=rebuild(state,expected)
  if (!['local','server'].includes(input.trust) || !Array.isArray(input.update) || !input.update.length || input.update.length > 8*1024*1024 || input.update.some(b=>!Number.isInteger(b)||b<0||b>255)) throw Error('Invalid trusted placement update')
  const parsed=receipt(input.receipt,expected)
  if (placementUpdateHash(Uint8Array.from(input.update)) !== parsed.value.update_sha256) throw Error('Placement update hash mismatch')
  const previous=existing.known.get(parsed.value.operation_id)
  if (previous) {
    if (json(previous.value)!==json(parsed.value)) throw Error('Conflicting placement receipt')
    return clone(existing.state)
  }
  return rebuild({...existing.state,receipts:[...existing.state.receipts,{trust:input.trust,receipt:parsed.value}]},expected).state
}
