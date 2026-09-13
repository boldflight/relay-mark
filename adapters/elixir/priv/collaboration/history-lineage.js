import * as Y from 'yjs'
import { placementUpdateHash } from './placement-lineage.js'
import { formatAttributionCut } from './format-attribution-cut.js'
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

// Metadata refers to text which a peer may delete outside this owner's tracked
// transactions. Compose with Yjs GC instead of taking ownership of its keep bits.
// A parent must survive too: ContentType.gc recursively collects its descendants.
const counterpartRetentions = new WeakMap()
function assertCounterpartRetention(doc) {
  for (const check of counterpartRetentions.get(doc) || []) if (!check()) throw Error('History counterpart retention limit or invalid metadata')
}
export function installHistoryCounterpartRetention(doc, owner, lineageKey, inFlight = () => []) {
  const previous = doc.gcFilter
  let index = null, disposed = false
  const invalidate = () => { index = null }
  function references() {
    const ranges = new Map(); let budget = 0
    const spend = () => { if (++budget > 131072) throw Error('History counterpart index limit') }
    const add = (identity, count) => {
      spend()
      if (!id(identity) || !Number.isSafeInteger(count) || count < 1 || identity.clock + count > 4294967296) throw Error('Invalid history counterpart')
      const values = ranges.get(identity.client) || []
      values.push([identity.clock, identity.clock + count]); ranges.set(identity.client, values)
    }
    const captures = inFlight()
    if (!Array.isArray(captures) || captures.length > maximumStack || owner.undoStack.length + owner.redoStack.length > maximumStack) throw Error('History counterpart stack limit')
    const metadata = [...owner.undoStack, ...owner.redoStack, ...(owner.currStackItem ? [owner.currStackItem] : [])]
      .map(entry => entry.meta.get(lineageKey)).concat(captures).filter(Boolean)
    for (const row of metadata) {
      spend()
      if (row.copies && (!Array.isArray(row.copies) || row.copies.length > 4096)) throw Error('History counterpart copy limit')
      const selections = [row.insertedTextItems, row.formattingTextItems,
        ...(row.copies || []).flatMap(pair => [pair.source, pair.destination])].filter(Boolean)
      for (const selection of selections) {
       if (!Array.isArray(selection.runs) || selection.runs.length > 4096) throw Error('History counterpart selection limit')
       for (const run of selection.runs) {
        if (!id(run.type)) throw Error('Invalid history counterpart type')
        add(run.item, run.count)
        if (run.type.clock >= Y.getState(doc.store, run.type.client)) continue
        let parent = Y.getItem(doc.store, run.type)
        const ancestors = new Set()
        while (parent instanceof Y.Item) {
          if (ancestors.size >= 128 || ancestors.has(parent)) throw Error('History counterpart ancestry limit')
          ancestors.add(parent); add(parent.id, parent.length); parent = parent.parent?._item
        }
       }
      }
    }
    // Merge intervals, not per-character identities. Index size is bounded by
    // retained stack selections and document ancestors; no second history store.
    for (const [client, values] of ranges) {
      values.sort((a,b) => a[0]-b[0]); const merged = []
      for (const value of values) {
        const last = merged[merged.length-1]
        if (last && value[0] <= last[1]) last[1] = Math.max(last[1], value[1])
        else merged.push([...value])
      }
      ranges.set(client, merged)
    }
    return ranges
  }
  const check = () => {
    if (index === null) {
      try { index = references() } catch { index = false }
    }
    return index !== false
  }
  const checks = counterpartRetentions.get(doc) || new Set()
  checks.add(check); counterpartRetentions.set(doc, checks)
  const filter = item => {
    if (disposed) return previous(item)
    if (!previous(item)) return false
    // GC occurs after mutation: an oversized/invalid index preserves content.
    // Subsequent checkpoint/preflight refuses until the host clears that history.
    if (!check()) return false
    const ranges = index.get(item.id.client) || []
    let low = 0, high = ranges.length
    while (low < high) { const mid = (low+high) >>> 1; if (ranges[mid][1] <= item.id.clock) low = mid+1; else high = mid }
    return low === ranges.length || ranges[low][0] >= item.id.clock + item.length
  }
  doc.gcFilter = filter
  const events = ['stack-item-added', 'stack-item-updated', 'stack-item-popped', 'stack-cleared']
  doc.on('beforeTransaction', invalidate)
  for (const event of events) owner.on(event, invalidate)
  return () => {
    disposed = true; checks.delete(check)
    doc.off('beforeTransaction', invalidate)
    for (const event of events) owner.off(event, invalidate)
    if (doc.gcFilter === filter) doc.gcFilter = previous
    index = null
  }
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
// Version-pinned effective marker observation. A removal marker has its own
// identity; absence of any marker is represented by null, not an invented ID.
export function captureHistoryMarkerState(doc) {
  if (yjsPackage.version !== '13.6.32') throw Error('Unsupported history marker runtime')
  const visible = visibleAttributes(doc), leaves = new Set([...visible.values()].map(row => row.leaf))
  const found = new Map(); let visited = 0
  for (const leaf of leaves) {
    let item = leaf._start
    const markers = {bold:{marker:null,enabled:false},italic:{marker:null,enabled:false}}
    while (item !== null) {
      if (++visited > maximumStructs || !(item instanceof Y.Item) || item.parent !== leaf) throw Error('Unsupported history marker structure')
      if (!item.deleted) {
        if (item.content instanceof Y.ContentFormat && ['bold','italic'].includes(item.content.key)) {
          const value=item.content.value
          if (value !== null && (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).length)) throw Error('Unsupported history marker value')
          markers[item.content.key]={marker:{client:item.id.client,clock:item.id.clock},enabled:value!==null}
        } else if (item.content instanceof Y.ContentString) {
          for (let offset=0;offset<item.length;offset++) {
            const identity=key({client:item.id.client,clock:item.id.clock+offset}), row=visible.get(identity)
            if (!row || row.leaf!==leaf) throw Error('Missing visible history marker unit')
            found.set(identity,{unit:row.unit,marks:JSON.parse(JSON.stringify(markers))})
          }
        }
      }
      item=item.right
    }
  }
  if (found.size!==visible.size) throw Error('Incomplete history marker observation')
  return [...found.values()]
}

export function captureSelectedFormattingStates(before, after, selected, mark) {
  if (!['bold','italic'].includes(mark)) throw Error('Invalid formatting attribution mark')
  const index=rows=>new Map(rows.map(row=>[key(row.unit.item),row]))
  const old=index(before), current=index(after)
  return expanded(selected).map(unit=>{
    const a=old.get(key(unit.item)),b=current.get(key(unit.item))
    if (!a || !b || key(a.unit.type)!==key(unit.type) || key(b.unit.type)!==key(unit.type)) throw Error('Unavailable formatting marker target')
    return {unit:JSON.parse(JSON.stringify(unit)),before:a.marks[mark],after:b.marks[mark]}
  })
}

// A format event is observed from an exact prestate and one transaction update.
// It retains real removed marker IDs even when poststate cleanup leaves null.
// No event is reconstructed from merged/GC bytes or final mark values alone.
export function captureHistoryFormatEvent(beforeDoc, update, input) {
  exactKeys(input,['operation_id','mark','text_items'])
  if (beforeDoc.store.pendingStructs !== null || beforeDoc.store.pendingDs !== null) throw Error('Incomplete format prestate')
  if (!uuid(input.operation_id) || !['bold','italic'].includes(input.mark) || !(update instanceof Uint8Array) ||
      !update.length || update.length>maximumStateBytes) throw Error('Invalid formatting event input')
  exactKeys(input.text_items,['version','runs'])
  if (input.text_items.version!==1 || !Array.isArray(input.text_items.runs) || !input.text_items.runs.length || input.text_items.runs.length>4096) throw Error('Invalid format target selection')
  for (const run of input.text_items.runs) {
    exactKeys(run,['item','type','count'])
    if (!id(run.item) || !id(run.type) || !Number.isSafeInteger(run.count) || run.count<1 || run.item.clock+run.count>4294967296) throw Error('Invalid format target identity')
  }
  const targets=expanded(input.text_items),targetIDs=new Set(targets.map(unit=>key(unit.item)))
  const before=captureHistoryMarkerState(beforeDoc),old=new Map(before.map(row=>[key(row.unit.item),row]))
  for (const unit of targets) if (key(old.get(key(unit.item))?.unit.type || {})!==key(unit.type)) throw Error('Unavailable format event target')
  const decoded=Y.decodeUpdate(update),inserted=[],deleted=[],newMarkers=new Map()
  for (const item of decoded.structs) {
    if (!(item instanceof Y.Item) || !(item.content instanceof Y.ContentFormat) || item.content.key!==input.mark ||
        item.length!==1 || !id(item.id)) throw Error('Unprovable or non-format event allocation')
    if (item.id.clock < Y.getState(beforeDoc.store,item.id.client)) throw Error('Format event already integrated')
    if (inserted.length>=4096) throw Error('Format event marker limit')
    const marker={client:item.id.client,clock:item.id.clock};inserted.push(marker);newMarkers.set(key(marker),item)
  }
  for (const [client,ranges] of decoded.ds.clients) for (const range of ranges) {
    if (range.len>4096 || deleted.length+range.len>4096) throw Error('Format event marker limit')
    for (let n=0;n<range.len;n++) {
      const marker={client,clock:range.clock+n}
      const item=newMarkers.get(key(marker)) || (marker.clock<Y.getState(beforeDoc.store,client) ? Y.getItem(beforeDoc.store,marker) : null)
      if (!(item instanceof Y.Item) || !(item.content instanceof Y.ContentFormat) || item.content.key!==input.mark || item.deleted || item.length!==1) throw Error('Unprovable format marker deletion')
      deleted.push(marker)
    }
  }
  if (!inserted.length && !deleted.length) throw Error('No formatting event')
  const scratch=new Y.Doc({gc:false})
  try {
    Y.applyUpdate(scratch,Y.encodeStateAsUpdate(beforeDoc));Y.applyUpdate(scratch,update)
    if (scratch.store.pendingStructs || scratch.store.pendingDs) throw Error('Incomplete format event')
    const after=captureHistoryMarkerState(scratch),current=new Map(after.map(row=>[key(row.unit.item),row]))
    if (current.size!==old.size) throw Error('Format event changed text identities')
    const changes=[]
    for (const [identity,previous] of old) {
      const next=current.get(identity)
      if (!next || key(next.unit.type)!==key(previous.unit.type)) throw Error('Format event changed text placement')
      for (const mark of ['bold','italic']) {
        if (previous.marks[mark].enabled!==next.marks[mark].enabled && (mark!==input.mark || !targetIDs.has(identity))) throw Error('Format event changed untargeted marks')
      }
      if (targetIDs.has(identity) && canonicalAttributes(previous.marks[input.mark])!==canonicalAttributes(next.marks[input.mark])) {
        const a=previous.marks[input.mark],b=next.marks[input.mark]
        if ((a.marker && !deleted.some(marker=>key(marker)===key(a.marker))) &&
            (b.marker && !newMarkers.has(key(b.marker)))) throw Error('Unproven format target transition')
        changes.push({unit:previous.unit,before:a,after:b})
      }
    }
    if (!changes.length) throw Error('Unprovable or ineffective formatting event')
    const sorted=values=>values.sort((a,b)=>a.client-b.client||a.clock-b.clock)
    return {version:1,operation_id:input.operation_id,update_sha256:placementUpdateHash(update),mark:input.mark,
      text_items:JSON.parse(JSON.stringify(input.text_items)),inserted_markers:sorted(inserted),deleted_markers:sorted(deleted),changes}
  } finally { scratch.destroy() }
}

export function validateHistoryFormatEvent(beforeDoc, update, event) {
  exactKeys(event,['version','operation_id','update_sha256','mark','text_items','inserted_markers','deleted_markers','changes'])
  const actual=captureHistoryFormatEvent(beforeDoc,update,{operation_id:event.operation_id,mark:event.mark,text_items:event.text_items})
  if (canonicalAttributes(event)!==canonicalAttributes(actual)) throw Error('Mismatched formatting event witness')
  return actual
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
// Optional internal plan comes from exact-cut verified attribution, not a client
// selection or final-value guess. The staged execution validates it before live use.
export function performHistoryWithMarks(doc, manager, redo, lineageKey, formattingPlan = null) {
  if (manager.relayHistoryTransactionHookVersion !== 1 || manager.beforeHistoryTransactionCommit !== null || manager.beforeHistoryItemSkip != null) {
    throw Error('History transaction hook unavailable')
  }
  let attributedTargets = null, attributedSelection = null
  if (formattingPlan !== null) {
    if (manager.relayHistoryItemSkipHookVersion !== 1 || manager.beforeHistoryItemSkip !== null) throw Error('Attributed history item hook unavailable')
    if (formattingPlan.kind !== 'apply' || !uuid(formattingPlan.operationID) ||
        !['bold','italic'].includes(formattingPlan.mark) ||
        formattingPlan.prestate_sha256 !== formatAttributionCut(doc) ||
        !Array.isArray(formattingPlan.targets) || !formattingPlan.targets.length || formattingPlan.targets.length > 131072) {
      throw Error('Unavailable or stale formatting attribution plan')
    }
    attributedTargets = new Map(); attributedSelection = {version:1,runs:[]}
    for (const target of formattingPlan.targets) {
      if (!id(target.unit?.item) || !id(target.unit?.type) || target.mark !== formattingPlan.mark ||
          typeof target.enabled !== 'boolean' || attributedTargets.has(key(target.unit.item))) throw Error('Invalid formatting attribution target')
      attributedTargets.set(key(target.unit.item),target)
      const last=attributedSelection.runs.at(-1), unit=target.unit
      if (last && last.item.client===unit.item.client && last.item.clock+last.count===unit.item.clock && key(last.type)===key(unit.type)) last.count++
      else {
        if (attributedSelection.runs.length>=4096) throw Error('Formatting attribution selection limit')
        attributedSelection.runs.push({item:{...unit.item},type:{...unit.type},count:1})
      }
    }
  }
  const current = visibleAttributes(doc)
  if (attributedTargets) for (const [identity,target] of attributedTargets) {
    if (key(current.get(identity)?.unit.type || {}) !== key(target.unit.type)) throw Error('Unavailable formatting attribution target')
  }
  const prior = Y.decodeStateVector(Y.encodeStateVector(doc))
  const links = new Map(structs(doc).filter(item => item instanceof Y.Item).map(item => [key(item.id), item.redone && key(item.redone)]))
  let execution = null, skipExecutedItem = null
  const applyHistoryMarks = ({ stackItem, transaction }) => {
    if (execution) throw Error('History hook performed multiple items')
    const metadata = stackItem.meta.get(lineageKey)
    if (!uuid(metadata?.operationID) || !Array.isArray(metadata.copies) || metadata.copies.length > 4096) {
      throw Error('Untracked history formatting counterpart')
    }
    if (formattingPlan && (metadata.operationID !== formattingPlan.operationID || metadata.formattingMark !== formattingPlan.mark)) {
      throw Error('Formatting attribution references a different history item')
    }
    let formattingTargets = null
    if (metadata.formattingMark) {
      if (!['bold', 'italic'].includes(metadata.formattingMark) || metadata.copies.length || !metadata.formattingTextItems) {
        throw Error('Unproven formatting history targets')
      }
      formattingTargets = identities(metadata.formattingTextItems)
    }
    const counterparts = new Map()
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
    const copies = restoredCopies(doc, prior, links), after = visibleAttributes(doc), inverseCopies = [], plans = []
    // Removing local formatting markers can otherwise change surviving peer
    // text even when its identity remains. Preserve its current attributes too.
    for (const [identity, target] of after) {
      const previous = current.get(identity)
      if (previous && key(previous.unit.type) === key(target.unit.type) &&
          (attributedTargets || canonicalAttributes(previous.attributes) !== canonicalAttributes(target.attributes))) {
        const desired = { ...previous.attributes }
        if (attributedTargets) {
          const attributed=attributedTargets.get(identity)
          if (attributed) {
            if (attributed.enabled) desired[formattingPlan.mark]={}
            else delete desired[formattingPlan.mark]
          }
        } else if (formattingTargets?.has(identity)) {
          if (Object.hasOwn(target.attributes, metadata.formattingMark)) desired[metadata.formattingMark] = target.attributes[metadata.formattingMark]
          else delete desired[metadata.formattingMark]
        }
        if (canonicalAttributes(desired)!==canonicalAttributes(target.attributes)) plans.push({ ...target, desired })
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
    const grouped = new Map(); let didFormat = false
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
            canonicalAttributes(row.attributes) !== canonicalAttributes(first.desired))) { leaf.format(first.offset, length, changes); didFormat = true }
      }
    }
    if (!metadata.formattingMark) {
      // Remote update integration cleans redundant YText markers. Do the same
      // canonical cleanup inside this existing structural history transaction,
      // before its bytes and inverse are emitted, including deleted source leaves.
      const affected = []
      Y.iterateDeletedStructs(transaction, transaction.deleteSet, item => {
        if (item instanceof Y.Item && item.parent instanceof Y.XmlText && item.parent._hasFormatting &&
            !(item.content instanceof Y.ContentFormat)) affected.push(item)
      })
      if (affected.length > 131072) throw Error('History formatting cleanup limit')
      for (const item of affected) Y.relayCleanupContextlessFormattingGap(transaction, item)
    }
    execution = { copies, inverseCopies, formattingTextItems: attributedSelection || metadata.formattingTextItems || null }
    return didFormat
  }
  manager.beforeHistoryTransactionCommit = input => {
    if (skipExecutedItem === input.stackItem) return
    applyHistoryMarks(input)
  }
  if (formattingPlan) manager.beforeHistoryItemSkip = input => {
    const metadata=input.stackItem.meta.get(lineageKey)
    if (metadata?.operationID !== formattingPlan.operationID || metadata.formattingMark !== formattingPlan.mark) return false
    const changed=applyHistoryMarks(input)
    if (!changed) throw Error('Attributed history made no effective formatting change')
    skipExecutedItem=input.stackItem
    return true
  }
  try {
    const item = redo ? manager.redo() : manager.undo()
    if (!execution) throw Error('History made no effective change')
    return { ...execution, item }
  } finally { manager.beforeHistoryTransactionCommit = null; if (formattingPlan) manager.beforeHistoryItemSkip = null }
}

// The scratch UndoManager performs its normal skipping. Select evidence from
// the actual actionable item, never from a top entry that a peer made obsolete.
// Candidate selection only. Callers must still prove the actual performed item on
// scratch with prepareHistoryEvidence; skipped/noop/untracked tops remain unsupported.
export function currentAttributedCandidate(owner, redo, lineageKey) {
  if (owner.undoing || owner.redoing || owner.currStackItem !== null || owner.captureTimeout !== 0) throw Error('History owner is not isolated')
  const stack = redo ? owner.redoStack : owner.undoStack
  if (!Array.isArray(stack) || !stack.length || stack.length > 16384) throw Error('No supported history candidate')
  const metadata = stack[stack.length - 1].meta.get(lineageKey)
  if (!uuid(metadata?.operationID) || !Array.isArray(metadata.copies) ||
      (metadata.formattingMark != null && !['bold','italic'].includes(metadata.formattingMark))) throw Error('Unsupported history candidate')
  return {reference:metadata.operationID,kind:metadata.formattingMark == null ? 'prose' : 'formatting'}
}
export function currentFormattingCandidate(owner, redo, lineageKey) {
  const candidate = currentAttributedCandidate(owner, redo, lineageKey)
  if (candidate.kind !== 'formatting') throw Error('Unsupported formatting candidate')
  return candidate.reference
}

export function prepareHistoryEvidence(live, owner, redo, input, lineageKey, formattingPlan = null) {
  return prepareHistoryLineage(live, owner, redo, input, lineageKey, null, formattingPlan)
}

// Version-pinned access to nonserialized UndoManager/Item metadata lives ONLY
// here. No custom inverse algorithm: both preflight and live use Y.UndoManager.
export function prepareHistoryLineage(live, owner, redo, input, lineageKey, formatting = false, formattingPlan = null) {
  assertCounterpartRetention(live)
  if (typeof Y.relayCleanupContextlessFormattingGap !== 'function') throw Error('Missing pinned history cleanup hook')
  if (yjsPackage.version !== '13.6.32' || !input || Object.keys(input).join(',') !== 'operation_id' || !uuid(input.operation_id) ||
      owner.relayHistoryTransactionHookVersion !== 1 || owner.beforeHistoryTransactionCommit !== null || owner.beforeHistoryItemSkip != null ||
      owner.doc !== live || owner.captureTimeout !== 0 || owner.undoing || owner.redoing || owner.currStackItem !== null ||
      owner.scope.length !== 1 || owner.scope[0] !== live.getXmlFragment('default') || owner.ignoreRemoteMapChanges !== false) {
    throw Error('Unsupported isolated Yjs history owner')
  }
  const before = Y.encodeStateAsUpdate(live), clientID = live.clientID
  const prior = Y.decodeStateVector(Y.encodeStateVector(live)), oldStructs = structs(live)
  const undoStack = cloneStack(owner.undoStack), redoStack = cloneStack(owner.redoStack)
  if ([...undoStack, ...redoStack].some(item => item.meta.get(lineageKey)?.operationID === input.operation_id)) {
    throw Error('History requires distinct durable operation identities')
  }
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
    const inverse = [], popped = [], expectedUpdates = []; let mixed = false
    staged.on('update', (update, origin) => { if (origin === manager) expectedUpdates.push(update.slice()) })
    manager.on('stack-item-added', ({ stackItem, origin }) => { if (origin === manager) inverse.push(stackItem) })
    manager.on('stack-item-updated', () => { mixed = true })
    manager.on('stack-item-popped', ({ stackItem }) => popped.push(stackItem))
    const execution = performHistoryWithMarks(staged, manager, redo, lineageKey, formattingPlan)
    const performed = execution.item
    if (!performed || popped.length !== 1 || popped[0] !== performed || inverse.length !== 1 || mixed) throw Error('Unproven effective history item')
    const metadata = performed.meta.get(lineageKey), reference = metadata?.operationID
    const isFormatting = metadata?.formattingMark != null
    if (!uuid(reference) || (formatting !== null && formatting !== isFormatting)) throw Error('History evidence mode mismatch')
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
    return { kind: isFormatting ? 'formatting' : 'prose', reference, operationID: input.operation_id, formattingPlan, formattingTextItems: execution.formattingTextItems, expectedUpdates, expectedCut: formattingPlan ? formatAttributionCut(staged) : null, inverseCopies: execution.inverseCopies, expectedState: Y.encodeStateAsUpdate(staged),
      insertedTextItems: Array.from(new TextEncoder().encode('{"version":1,"runs":[]}')),
      lineage: { version: 1, operation: { kind: redo ? 'redo' : 'undo', transaction_id: reference }, copies } }
  } finally { manager?.destroy(); staged.destroy() }
}

const snapshotVersion = 1, maximumStateBytes = 8 * 1024 * 1024, maximumSnapshotBytes = 64 * 1024 * 1024
function exactKeys(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).sort().join(',') !== [...keys].sort().join(',')) throw Error('Invalid history snapshot fields')
}
function byteArray(value, maximum) {
  if (!Array.isArray(value) || !value.length || value.length > maximum ||
      value.some(byte => !Number.isInteger(byte) || byte < 0 || byte > 255)) throw Error('Invalid history snapshot bytes')
  return Uint8Array.from(value)
}
function scopeToken(value) {
  if (typeof value !== 'string' || !value.length || new TextEncoder().encode(value).length > 2048) throw Error('Invalid history scope token')
}
function intervalWire(value) {
  return [...cloneSet(value).clients].sort(([a], [b]) => a - b)
    .map(([client, ranges]) => ({ client, ranges: ranges.map(({ clock, len }) => ({ clock, len })) }))
}
function intervalSet(value) {
  if (!Array.isArray(value) || value.length > maximumStructs) throw Error('History interval limit')
  const result = Y.createDeleteSet()
  for (const row of value) {
    exactKeys(row, ['client', 'ranges'])
    if (result.clients.has(row.client)) throw Error('Duplicate history client')
    result.clients.set(row.client, row.ranges)
  }
  const copied = cloneSet(result)
  if (JSON.stringify(intervalWire(copied)) !== JSON.stringify(value)) throw Error('Noncanonical history intervals')
  return copied
}
function snapshotStack(stack, lineageKey) {
  return cloneStack(stack).map(item => {
    const metadata = item.meta.get(lineageKey)
    if (!uuid(metadata?.operationID) || !Array.isArray(metadata.copies)) throw Error('Untracked history cannot be persisted')
    return { insertions: intervalWire(item.insertions), deletions: intervalWire(item.deletions),
      operation_id: metadata.operationID, counterparts: JSON.parse(JSON.stringify(metadata.copies)),
      inserted_text_items: metadata.insertedTextItems || { version: 1, runs: [] }, formatting_mark: metadata.formattingMark || null,
      formatting_text_items: metadata.formattingTextItems || null }
  })
}
function restoreStack(value, lineageKey, references) {
  if (!Array.isArray(value) || value.length > maximumStack) throw Error('History stack limit')
  return value.map(row => {
    exactKeys(row, ['insertions', 'deletions', 'operation_id', 'counterparts', 'inserted_text_items', 'formatting_mark',
      ...(Object.hasOwn(row, 'formatting_text_items') ? ['formatting_text_items'] : [])])
    if (row.formatting_mark && !row.formatting_text_items) throw Error('Missing formatting history targets')
    if (row.formatting_mark !== null && !['bold', 'italic'].includes(row.formatting_mark)) throw Error('Invalid history formatting evidence')
    for (const selection of [row.inserted_text_items, ...(row.formatting_text_items ? [row.formatting_text_items] : [])]) {
    exactKeys(selection, ['version', 'runs'])
    if (selection.version !== 1 || !Array.isArray(selection.runs) || selection.runs.length > 4096) throw Error('Invalid history typed evidence')
    for (const run of selection.runs) {
      exactKeys(run, ['item', 'type', 'count']); exactKeys(run.item, ['client', 'clock']); exactKeys(run.type, ['client', 'clock'])
      if (!id(run.item) || !id(run.type) || !Number.isSafeInteger(run.count) || run.count < 1 || run.item.clock + run.count > 4294967296) throw Error('Invalid history typed run')
    }
    identities(selection)
    }
    if (!uuid(row.operation_id) || references.has(row.operation_id) || !Array.isArray(row.counterparts) || row.counterparts.length > 4096) {
      throw Error('Invalid history transaction reference')
    }
    references.add(row.operation_id)
    const source = [], destination = []
    for (const pair of row.counterparts) {
      exactKeys(pair, ['source', 'destination'])
      for (const selection of [pair.source, pair.destination]) {
        exactKeys(selection, ['version', 'runs'])
        if (selection.version !== 1 || !Array.isArray(selection.runs) || selection.runs.length > 4096) throw Error('Invalid history counterpart')
        for (const run of selection.runs) {
          exactKeys(run, ['item', 'type', 'count']); exactKeys(run.item, ['client', 'clock']); exactKeys(run.type, ['client', 'clock'])
          if (!id(run.item) || !id(run.type) || !Number.isSafeInteger(run.count) || run.count < 1 || run.item.clock + run.count > 4294967296) {
            throw Error('Invalid history counterpart run')
          }
        }
      }
      if (expanded(pair.source).length !== expanded(pair.destination).length) throw Error('History counterpart length mismatch')
      source.push(...pair.source.runs); destination.push(...pair.destination.runs)
    }
    identities({ runs: source }); identities({ runs: destination })
    return { insertions: intervalSet(row.insertions), deletions: intervalSet(row.deletions),
      meta: new Map([[lineageKey, { operationID: row.operation_id, copies: JSON.parse(JSON.stringify(row.counterparts)), insertedTextItems: JSON.parse(JSON.stringify(row.inserted_text_items)), formattingMark: row.formatting_mark, formattingTextItems: row.formatting_text_items || null }]]) }
  })
}
function cleanInterval(transaction, row) {
  if (!id(row.item) || !Number.isSafeInteger(row.length) || row.length < 1 || row.item.clock + row.length > 4294967296) {
    throw Error('Invalid retained history interval')
  }
  const item = Y.getItemCleanStart(transaction, Y.createID(row.item.client, row.item.clock))
  Y.getItemCleanEnd(transaction, transaction.doc.store, Y.createID(row.item.client, row.item.clock + row.length - 1))
  if (!(item instanceof Y.Item) || item.content instanceof Y.ContentDeleted) throw Error('History content unavailable')
  return item
}
function installSnapshotMetadata(doc, snapshot, undoStack, redoStack) {
  const seen = new Set()
  Y.transact(doc, transaction => {
    for (const row of snapshot.redone) {
      exactKeys(row, ['item', 'length', 'target'])
      if (!id(row.target) || seen.has(key(row.item))) throw Error('Invalid redone history identity')
      seen.add(key(row.item))
      let offset = 0
      while (offset < row.length) {
        const sourceID = { client: row.item.client, clock: row.item.clock + offset }
        const targetID = { client: row.target.client, clock: row.target.clock + offset }
        let item = cleanInterval(transaction, { item: sourceID, length: row.length - offset })
        let target = cleanInterval(transaction, { item: targetID, length: row.length - offset })
        const length = Math.min(item.length, target.length, row.length - offset)
        item = cleanInterval(transaction, { item: sourceID, length })
        target = cleanInterval(transaction, { item: targetID, length })
        if (item === target || item.content.constructor !== target.content.constructor ||
            (item.content instanceof Y.ContentType && (item.content.type.constructor !== target.content.type.constructor ||
              (item.content.type instanceof Y.XmlElement && item.content.type.nodeName !== target.content.type.nodeName))) ||
            (item.content instanceof Y.ContentString && item.content.str !== target.content.str)) throw Error('Mismatched restored history content')
        item.redone = Y.createID(targetID.client, targetID.clock)
        offset += length
      }
    }
    for (const row of snapshot.retained) {
      exactKeys(row, ['item', 'length'])
      let offset = 0
      while (offset < row.length) {
        let item = cleanInterval(transaction, { item: { client: row.item.client, clock: row.item.clock + offset }, length: row.length - offset })
        offset += item.length
        let depth = 0
        while (item instanceof Y.Item) {
          if (++depth > 128) throw Error('History parent limit')
          item.keep = true
          item = item.parent?._item
        }
      }
    }
    // Every stack interval must address integrated structs. Redone chains are
    // checked separately below; no pending dependency is accepted as a proof.
    for (const entry of [...undoStack, ...redoStack]) for (const set of [entry.insertions, entry.deletions]) {
      for (const [client, ranges] of set.clients) for (const row of ranges) {
        if (row.clock + row.len > Y.getState(doc.store, client)) throw Error('Unintegrated history interval')
        if (set === entry.deletions) {
          let clock = row.clock
          while (clock < row.clock + row.len) {
            const item = Y.getItem(doc.store, Y.createID(client, clock))
            if (!(item instanceof Y.Item) || item.content instanceof Y.ContentDeleted || !item.keep) throw Error('Unretained history content')
            clock = Math.min(item.id.clock + item.length, row.clock + row.len)
          }
        }
      }
    }
  }, 'relay.history.restore')
  for (const item of structs(doc)) if (item instanceof Y.Item && item.redone !== null) {
    const visited = new Set(); let current = item
    while (current.redone !== null) {
      if (visited.size >= maximumStructs || visited.has(key(current.id))) throw Error('Cyclic redone history')
      visited.add(key(current.id)); current = Y.getItem(doc.store, current.redone)
      if (!(current instanceof Y.Item)) throw Error('Missing redone history')
    }
  }
}
function pristineHistoryOwner(doc, owner) {
  return Y.decodeStateVector(Y.encodeStateVector(doc)).size === 0 && owner.undoStack.length === 0 && owner.redoStack.length === 0 &&
    owner.captureTimeout === 0 && !owner.undoing && !owner.redoing && owner.currStackItem === null &&
    owner.beforeHistoryTransactionCommit === null && owner.relayHistoryTransactionHookVersion === 1
}
export function exportHistorySnapshot(doc, owner, input, lineageKey) {
  assertCounterpartRetention(doc)
  exactKeys(input, ['scope_token']); scopeToken(input.scope_token)
  if (owner.captureTimeout !== 0 || owner.undoing || owner.redoing || owner.currStackItem !== null ||
      owner.beforeHistoryTransactionCommit !== null || owner.relayHistoryTransactionHookVersion !== 1 ||
      doc.store.pendingStructs !== null || doc.store.pendingDs !== null) throw Error('History owner is not settled')
  const values = structs(doc), state = Y.encodeStateAsUpdate(doc)
  if (state.length > maximumStateBytes) throw Error('History checkpoint limit')
  const snapshot = { version: snapshotVersion, yjs_version: '13.6.32', hook_version: 1, scope_token: input.scope_token,
    client_id: doc.clientID, state_update: Array.from(state), state_vector: Array.from(Y.encodeStateVector(doc)),
    undo: snapshotStack(owner.undoStack, lineageKey), redo: snapshotStack(owner.redoStack, lineageKey),
    redone: values.filter(item => item instanceof Y.Item && item.redone !== null).map(item => ({
      item: { client: item.id.client, clock: item.id.clock }, length: item.length, target: { client: item.redone.client, clock: item.redone.clock } })),
    retained: values.filter(item => item instanceof Y.Item && item.keep).map(item => ({
      item: { client: item.id.client, clock: item.id.clock }, length: item.length })) }
  if (new TextEncoder().encode(JSON.stringify(snapshot)).length > maximumSnapshotBytes) throw Error('History snapshot limit')
  return snapshot
}
export function restoreHistorySnapshot(doc, owner, input, lineageKey) {
  exactKeys(input, ['snapshot', 'scope_token', 'transaction_ids']); scopeToken(input.scope_token)
  if (!pristineHistoryOwner(doc, owner)) throw Error('History restore requires a pristine owner')
  const snapshot = input.snapshot
  if (new TextEncoder().encode(JSON.stringify(snapshot)).length > maximumSnapshotBytes) throw Error('History snapshot limit')
  exactKeys(snapshot, ['version', 'yjs_version', 'hook_version', 'scope_token', 'client_id', 'state_update', 'state_vector', 'undo', 'redo', 'redone', 'retained'])
  if (snapshot.version !== snapshotVersion || snapshot.yjs_version !== '13.6.32' || snapshot.hook_version !== 1 ||
      snapshot.scope_token !== input.scope_token || !Number.isSafeInteger(snapshot.client_id) || snapshot.client_id < 0 ||
      !Array.isArray(input.transaction_ids) || input.transaction_ids.length > 16384 ||
      input.transaction_ids.some(value => !uuid(value)) || new Set(input.transaction_ids).size !== input.transaction_ids.length ||
      !Array.isArray(snapshot.redone) || snapshot.redone.length > maximumStructs ||
      !Array.isArray(snapshot.retained) || snapshot.retained.length > maximumStructs) throw Error('Invalid history snapshot binding')
  const state = byteArray(snapshot.state_update, maximumStateBytes), vector = byteArray(snapshot.state_vector, maximumStateBytes)
  const references = new Set(), undoStack = restoreStack(snapshot.undo, lineageKey, references), redoStack = restoreStack(snapshot.redo, lineageKey, references)
  if ([...references].some(value => !input.transaction_ids.includes(value))) throw Error('History transaction is not retained by host')
  const scratch = new Y.Doc({ gc: false })
  try {
    Y.applyUpdate(scratch, state)
    if (scratch.store.pendingStructs !== null || scratch.store.pendingDs !== null ||
        !equal(vector, Y.encodeStateVector(scratch)) || !equal(state, Y.encodeStateAsUpdate(scratch))) throw Error('Incomplete history checkpoint')
    installSnapshotMetadata(scratch, snapshot, undoStack, redoStack)
    // Decode and validate the opaque counterpart identities even when their
    // original parent has been deleted; history receipts supply host authority.
    for (const entry of [...undoStack, ...redoStack]) {
      const metadata = entry.meta.get(lineageKey)
      for (const value of [metadata.insertedTextItems, ...(metadata.formattingTextItems ? [metadata.formattingTextItems] : []), ...metadata.copies.flatMap(pair => [pair.source, pair.destination])]) for (const run of value.runs) {
        const parent = Y.getItem(scratch.store, run.type)
        if (!(parent instanceof Y.Item) || !(parent.content instanceof Y.ContentType) ||
            !(parent.content.type instanceof Y.XmlText) || key(parent.id) !== key(run.type) ||
            run.item.clock + run.count > Y.getState(scratch.store, run.item.client)) throw Error('Unavailable history counterpart')
        let clock = run.item.clock
        while (clock < run.item.clock + run.count) {
          const item = Y.getItem(scratch.store, Y.createID(run.item.client, clock))
          if (!(item instanceof Y.Item) || !(item.content instanceof Y.ContentString) || item.parent !== parent.content.type) {
            throw Error('Mismatched history counterpart interval')
          }
          clock = Math.min(item.id.clock + item.length, run.item.clock + run.count)
        }
      }
    }
    if (!pristineHistoryOwner(doc, owner)) throw Error('History owner changed during restore')
    const gc = doc.gc
    try {
      doc.gc = false; Y.applyUpdate(doc, state, 'relay.history.restore')
      installSnapshotMetadata(doc, snapshot, undoStack, redoStack)
      owner.undoStack = undoStack; owner.redoStack = redoStack; owner.stopCapturing()
    } finally { doc.gc = gc }
    return null
  } finally { scratch.destroy() }
}
