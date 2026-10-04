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
  keys(x, ['runs'])
  if (!Array.isArray(x.runs) || x.runs.length > 4096) throw Error('Invalid placement selection')
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
  keys(x, ['contract_version', 'kind', 'document_id', 'incarnation', 'update_sha256', 'operation_id', 'operation', 'copies'])
  if (x.contract_version !== 1 || x.kind !== 'placement_receipt' || x.document_id !== expected.document_id || x.incarnation !== expected.incarnation ||
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
  // Canonical ordered unit-pair coalescing ignores caller copy/run partition.
  // It never changes the original operation request/evidence bytes.
  const copies=[]
  for (const pair of pairs) {
    const last=copies.at(-1), a=last?.source.runs[0], b=last?.destination.runs[0]
    const follows=(run,unit)=>run && run.item.client===unit.item.client && run.item.clock+run.count===unit.item.clock &&
      run.type.client===unit.type.client && run.type.clock===unit.type.clock
    if (follows(a,pair.source) && follows(b,pair.destination)) { a.count++; b.count++ }
    else copies.push({source:{runs:[{...clone(pair.source),count:1}]},destination:{runs:[{...clone(pair.destination),count:1}]}})
  }
  return { value: { contract_version: 1, kind: 'placement_receipt', ...expected, update_sha256:x.update_sha256, operation_id:x.operation_id,
    operation:{kind:x.operation.kind,reference:x.operation.reference}, copies }, pairs }
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
  const types = new Map(), units = new Map(), components = new Map()
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
      types.set(item,type); units.set(key(unit),unit)
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
  return { state:{version:1,binding:expected,receipts:canonical}, known, edges, units, types }
}
function retainedProjection(snapshot, expectedBinding, receiptIDs) {
  const expected = binding(expectedBinding)
  if (!Array.isArray(receiptIDs) || receiptIDs.length > maxReceipts || receiptIDs.some(x=>!uuid(x)) || new Set(receiptIDs).size !== receiptIDs.length) throw Error('Invalid placement receipt whitelist')
  return rebuild(snapshot,expected,new Set(receiptIDs))
}
export function restorePlacementState(snapshot, expectedBinding, receiptIDs) {
  return retainedProjection(snapshot,expectedBinding,receiptIDs).state
}

// Read-only projections of the existing graph. The explicit host receipt
// whitelist is required; these helpers do not authenticate receipts or raw bytes.
export function placementReceiptCopies(state, expectedBinding, receiptIDs, operationID) {
  const projection=retainedProjection(state,expectedBinding,receiptIDs)
  if (!uuid(operationID) || !projection.known.has(operationID)) throw Error('Unknown placement operation')
  return clone(projection.known.get(operationID).effective)
}
export function createPlacementResolver(state, expectedBinding, receiptIDs) {
  const projection=retainedProjection(state,expectedBinding,receiptIDs)
  const terminal=new Map()
  function endpoint(start) {
    const path=[]; let current=start
    while (projection.edges.has(current) && !terminal.has(current)) {
      path.push(current); current=projection.edges.get(current)
    }
    const result=terminal.get(current) || current
    for (const unit of path) terminal.set(unit,result)
    return result
  }
  return input=>{
    const [source]=selection({runs:[{...input,count:1}]})
    const item=`${source.item.client}:${source.item.clock}`, type=`${source.type.client}:${source.type.clock}`
    if (projection.types.has(item) && projection.types.get(item)!==type) throw Error('Conflicting placement target type')
    const destination=projection.units.get(endpoint(key(source))) || source
    return clone(destination)
  }
}
export function resolvePlacementUnits(state, expectedBinding, receiptIDs, selected) {
  const resolve=createPlacementResolver(state,expectedBinding,receiptIDs)
  return selection(selected).map(source=>({source,destination:resolve(source)}))
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
