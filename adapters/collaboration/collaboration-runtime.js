import {packAttributionRecord,unpackAttributionRecord} from './attribution-record-codec.js'
import { createPlacementState, preparePlacementReceipt, restorePlacementState, placementUpdateHash, createPlacementResolver } from './placement-lineage.js'
import * as Y from 'yjs'
import {replayFormatAttribution} from './format-attribution-replay.js'
import {createFormatAttribution, queryFormatInverse, prepareFormatAttribution} from './format-attribution.js'
import {formatAttributionCut} from './format-attribution-cut.js'
import { node, snapshot, range, proseBlocks as ownedProseBlocks, replaceProse as replaceOwnedProse } from './prose-operation.js'
import { captureTextItems, resolveTextItems } from './text-items.js'
import { prepareProseLineage, supportsProseLineage } from './prose-lineage.js'
import { currentAttributedCandidate, prepareHistoryEvidence, prepareHistoryLineage, preserveHistoryDescendants, installHistoryCounterpartRetention, captureHistoryFormatEvent, performHistoryWithMarks, exportHistorySnapshot, restoreHistorySnapshot } from './history-lineage.js'
import { Awareness, applyAwarenessUpdate, encodeAwarenessUpdate, removeAwarenessStates } from 'y-protocols/awareness'

const activeOwners = new WeakSet()
const activeDocuments = new WeakSet()

// Supplied resources stay caller-owned. Importing this module allocates no replica.
export function createCollaborationRuntime(options) {
// One context owns one document. Transport, authorization and persistence belong to the host.
const supplied = options !== undefined
const doc = supplied ? options.doc : new Y.Doc()
const root = supplied ? options.root || doc?.getXmlFragment('default') : doc.getXmlFragment('default')
const localOrigin = supplied ? options.localOrigin : 'relay.local.editor'
const undo = supplied ? options.manager : new Y.UndoManager(root, { trackedOrigins: new Set([localOrigin]), captureTimeout: 0, deleteFilter: preserveHistoryDescendants })
if (typeof Y.relayCleanupContextlessFormattingGap !== 'function' || !(doc instanceof Y.Doc) || root !== doc.getXmlFragment('default') || undo?.doc !== doc ||
    undo.scope.length !== 1 || undo.scope[0] !== root || undo.captureTimeout !== 0 ||
    undo.undoStack.length || undo.redoStack.length || undo.currStackItem !== null || undo.undoing || undo.redoing ||
    undo.relayHistoryTransactionHookVersion !== 1 || undo.beforeHistoryTransactionCommit !== null || undo.beforeHistoryItemSkip != null ||
    undo.ignoreRemoteMapChanges !== false || localOrigin == null || !undo.trackedOrigins.has(localOrigin) || activeOwners.has(undo) || activeDocuments.has(doc) ||
    (supplied && options.awareness?.doc !== doc)) throw Error('Expected pristine patched collaboration owner')
const awareness = supplied ? options.awareness : new Awareness(doc)
if (!supplied) awareness.setLocalState(null)
const previousDeleteFilter = undo.deleteFilter
undo.deleteFilter = previousDeleteFilter === preserveHistoryDescendants ? previousDeleteFilter
  : item => preserveHistoryDescendants(item) && previousDeleteFilter(item)
activeOwners.add(undo)
activeDocuments.add(doc)
let disposed = false
const subscriptions = []
function listen(target, event, listener) { target.on(event, listener); subscriptions.push([target,event,listener]) }
let disposeRetention = () => {}
try {
let awarenessUpdates = []
const awarenessOrigins = new Map()
listen(awareness, 'update', ({ added, updated, removed }, origin) => {
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
const formattingKey = Symbol('relay.native.formatting')
const lineageKey = Symbol('relay.native.lineage')
// Host persists a candidate before commit; graph never advances on a failed save.
let placementState = null, placementCandidate = null, lastPlacementOperation = null
const placementJSON = value => JSON.stringify(value, function (key, item) {
  return item && typeof item === 'object' && !Array.isArray(item)
    ? Object.fromEntries(Object.keys(item).sort().map(name => [name,item[name]])) : item
})
const placementBase = () => placementUpdateHash(new TextEncoder().encode(placementJSON(placementState)))
function rememberPlacement(operationID, kind, reference, copies, updates) {
  if (!operationID || !updates.length) { lastPlacementOperation = null; return }
  lastPlacementOperation = JSON.parse(JSON.stringify({ operation_id: operationID, operation: {kind, reference}, copies,
    update_sha256: placementUpdateHash(Y.mergeUpdates(updates.map(u => Uint8Array.from(u)))) }))
}
function placementExport(input) {
  if (!input || Object.keys(input).some(k => !['scope_token','placement_candidate'].includes(k))) throw Error('Invalid placement export')
  const snapshot = exportHistorySnapshot(doc, undo, {scope_token:input.scope_token}, lineageKey)
  let state = placementState
  if (input.placement_candidate !== undefined) {
    if (!placementCandidate || placementJSON(input.placement_candidate) !== placementJSON(placementCandidate) || placementCandidate.base_sha256 !== placementBase()) throw Error('Stale placement candidate')
    state = placementCandidate.state
  }
  if (state) snapshot.placement = JSON.parse(JSON.stringify(state))
  if (new TextEncoder().encode(JSON.stringify(snapshot)).length > 64*1024*1024) throw Error('History snapshot limit')
  return snapshot
}
let lineageCapture = null
let formattingCapture = null
let historyCapture = null
disposeRetention = installHistoryCounterpartRetention(doc, undo, lineageKey, () => lineageCapture ? [lineageCapture] : [])
listen(undo, 'stack-item-added', ({ stackItem, origin }) => {
  if (historyCapture && origin === undo) historyCapture.inverse.push(stackItem)
  else if (lineageCapture && origin === localOrigin) stackItem.meta.set(lineageKey, lineageCapture)
  else if (formattingCapture && origin === localOrigin) stackItem.meta.set(formattingKey, formattingCapture)
})
listen(undo, 'stack-item-updated', ({ stackItem }) => {
  // Even a text-equal replacement or a second mark operation makes a mixed item
  // ineligible. Only an isolated explicit formatting command carries evidence.
  stackItem.meta.delete(formattingKey)
  stackItem.meta.delete(lineageKey)
  if (historyCapture) historyCapture.mixed = true
})
listen(undo, 'stack-item-popped', ({ stackItem }) => {
  if (historyCapture) historyCapture.performed.push(stackItem)
})
function history(redo, prepared = null) {
  if (historyCapture) throw Error('Nested history operation')
  const capture = { inverse: [], performed: [], mixed: false }
  historyCapture = capture
  localUpdates = []
  try {
    const execution = prepared ? performHistoryWithMarks(doc, undo, redo, lineageKey, prepared.formattingPlan) : null
    const item = execution ? execution.item : (redo ? undo.redo() : undo.undo())
    const mark = item && (item.meta.get(formattingKey) || item.meta.get(lineageKey)?.formattingMark)
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
      capture.inverse[0].meta.set(lineageKey, { operationID: prepared.operationID, copies: execution.inverseCopies, formattingMark: proven ? mark : null, formattingTextItems: execution.formattingTextItems || null })
      const actual = Y.encodeStateAsUpdate(doc)
      if (actual.length !== prepared.expectedState.length || actual.some((byte, i) => byte !== prepared.expectedState[i])) {
        throw Error('History state diverged from preflight')
      }
    }
    return { updates: localUpdates, formattingMark: proven ? mark : null }
  } finally { historyCapture = null }
}
// The host supplies an independently retained, qualified recipe expectation.
// Replay is deliberate here: keep one UndoManager and no second runtime history
// store until measured restoration cost warrants a validated checkpoint cache.
function checkedAttributionReplay(replayJSON, expected) {
  if (expected?.cut !== formatAttributionCut(doc)) throw Error('Stale attributed history cut')
  return replayFormatAttribution(replayJSON, expected)
}
function nextAttributionReplay(replayJSON, record, cut) {
  const recipe = JSON.parse(replayJSON)
  const operationID = record.kind === 'format' ? record.event.operation_id : record.receipt.operation_id
  if (recipe.steps.some(step => (step.kind === 'format' ? step.event.operation_id : step.receipt.operation_id) === operationID)) throw Error('Duplicate attribution replay operation')
  if (recipe.steps.length >= 16384) throw Error('Attribution replay step limit')
  recipe.steps.push(record)
  const json = JSON.stringify(recipe), encoded = new TextEncoder().encode(json)
  if (encoded.length > 64*1024*1024) throw Error('Attribution replay byte limit')
  return {replay_json:json, replay_sha256:placementUpdateHash(encoded), cut, record_json:JSON.stringify(record)}
}
function executePreparedProse(input, prepared) {
      localUpdates = []; undo.stopCapturing()
      // No await or callback boundary between preflight and the same mutation.
      lineageCapture = input.operation_id ? { operationID: input.operation_id, copies: prepared.lineage.copies, insertedTextItems: JSON.parse(new TextDecoder().decode(Uint8Array.from(prepared.insertedTextItems))) } : null
      try { replaceProse(prepared.input) } finally { lineageCapture = null; undo.stopCapturing() }
      const actual = Y.encodeStateAsUpdate(doc)
      if (actual.length !== prepared.expectedState.length || actual.some((byte, i) => byte !== prepared.expectedState[i])) {
        throw Error('Prose lineage execution diverged from preflight')
      }
      rememberPlacement(input.operation_id, 'replace_prose', null, prepared.lineage.copies, localUpdates)
      return { updates: localUpdates, insertedTextItems: prepared.insertedTextItems, lineage: prepared.lineage }
}
function attributedProse(input) {
  if (!input || Object.keys(input).sort().join(',') !== 'expected,operation,replay_json' ||
      !input.operation?.operation_id || undo.captureTimeout !== 0 || formattingCapture || historyCapture || lineageCapture) throw Error('Invalid attributed prose request')
  checkedAttributionReplay(input.replay_json, input.expected)
  const prepared = prepareProseLineage(doc, input.operation, replaceProse)
  if (!prepared.expectedUpdates.length) throw Error('No effective attributed prose operation')
  const update = Y.mergeUpdates(prepared.expectedUpdates)
  const record = {kind:'placement',update:Array.from(update),receipt:{version:1,
    document_id:input.expected.binding.document_id,incarnation:input.expected.binding.incarnation,
    operation_id:input.operation.operation_id,update_sha256:placementUpdateHash(update),
    operation:{kind:'replace_prose',reference:null},copies:prepared.lineage.copies},trust:'local'}
  const scratch = new Y.Doc({gc:false}); let successor
  try {
    Y.applyUpdate(scratch, prepared.expectedState)
    const cut = formatAttributionCut(scratch)
    successor = nextAttributionReplay(input.replay_json, record, cut)
    replayFormatAttribution(successor.replay_json,{...input.expected,replay_sha256:successor.replay_sha256,cut})
  } finally { scratch.destroy() }
  const result = executePreparedProse(input.operation, prepared)
  if (placementUpdateHash(Y.mergeUpdates(result.updates.map(u=>Uint8Array.from(u)))) !== placementUpdateHash(update)) throw Error('Attributed prose update diverged')
  return {...result,...successor}
}
function applyAttributionRecords(input) {
  if (!input || Object.keys(input).sort().join(',') !== 'expected,records_json,replay_json' ||
      formattingCapture || historyCapture || lineageCapture || !Array.isArray(input.records_json) ||
      !input.records_json.length || input.records_json.length > 16384) throw Error('Invalid attribution records application')
  let total = 0
  for (const json of input.records_json) {
    if (typeof json !== 'string' || json.length > 64*1024*1024) throw Error('Invalid attribution record size')
    total += new TextEncoder().encode(json).length
    if (total > 64*1024*1024) throw Error('Attribution batch size limit')
  }
  checkedAttributionReplay(input.replay_json, input.expected)
  const scratch = new Y.Doc({gc:false}), updates = []
  let successor = {replay_json:input.replay_json,replay_sha256:input.expected.replay_sha256,cut:input.expected.cut}
  try {
    Y.applyUpdate(scratch, Y.encodeStateAsUpdate(doc))
    for (const json of input.records_json) {
      const record = JSON.parse(json)
      packAttributionRecord(json, record.update)
      const update = Uint8Array.from(record.update)
      Y.applyUpdate(scratch, update, 'relay.remote')
      const cut = formatAttributionCut(scratch)
      successor = nextAttributionReplay(successor.replay_json, record, cut)
      replayFormatAttribution(successor.replay_json, {...input.expected,replay_sha256:successor.replay_sha256,cut})
      updates.push(update)
    }
  } finally { scratch.destroy() }
  // Every record has been checked before the first live update.
  for (const update of updates) Y.applyUpdate(doc, update, 'relay.remote')
  if (formatAttributionCut(doc) !== successor.cut) throw Error('Attributed records application diverged')
  return successor
}
function applyAttributionRecord(input) {
  if (!input || Object.keys(input).sort().join(',') !== 'expected,record_json,replay_json') throw Error('Invalid attribution record application')
  return applyAttributionRecords({expected:input.expected,replay_json:input.replay_json,records_json:[input.record_json]})
}
function initialAttributionReplay(input) {
  if (!input || Object.keys(input).sort().join(',') !== 'binding,scope_token' ||
      typeof input.scope_token !== 'string' || !input.scope_token.length || new TextEncoder().encode(input.scope_token).length > 2048 ||
      undo.undoStack.length || undo.redoStack.length || undo.currStackItem !== null || undo.captureTimeout !== 0 ||
      formattingCapture || historyCapture || lineageCapture) throw Error('Attribution baseline requires an isolated owner without history')
  const binding = createPlacementState(input.binding).binding, state = createFormatAttribution(doc)
  const replayJSON = JSON.stringify({version:1,scope_token:input.scope_token,binding,baseline:Array.from(Y.encodeStateAsUpdate(doc)),steps:[]})
  const encoded = new TextEncoder().encode(replayJSON)
  if (encoded.length > 64*1024*1024) throw Error('Attribution replay byte limit')
  return {replay_json:replayJSON,replay_sha256:placementUpdateHash(encoded),cut:state.cut}
}

function attributedProseHistory(redo, input, reference) {
  const prepared = prepareHistoryEvidence(doc, undo, redo, {operation_id:input.operation_id}, lineageKey)
  if (prepared.kind !== 'prose' || prepared.reference !== reference) throw Error('Attributed prose history candidate was skipped')
  const update = Y.mergeUpdates(prepared.expectedUpdates)
  const record = {kind:'placement',update:Array.from(update),receipt:{version:1,
    document_id:input.expected.binding.document_id,incarnation:input.expected.binding.incarnation,
    operation_id:input.operation_id,update_sha256:placementUpdateHash(update),
    operation:{kind:redo?'redo':'undo',reference},copies:prepared.lineage.copies},trust:'local'}
  const scratch = new Y.Doc({gc:false}); let successor
  try {
    Y.applyUpdate(scratch, prepared.expectedState)
    const cut = formatAttributionCut(scratch)
    successor = nextAttributionReplay(input.replay_json, record, cut)
    replayFormatAttribution(successor.replay_json,{...input.expected,replay_sha256:successor.replay_sha256,cut})
  } finally { scratch.destroy() }
  const result = history(redo, prepared)
  if (placementUpdateHash(Y.mergeUpdates(result.updates.map(u=>Uint8Array.from(u)))) !== placementUpdateHash(update)) throw Error('Attributed prose history update diverged')
  rememberPlacement(input.operation_id, redo?'redo':'undo', reference, prepared.lineage.copies, result.updates)
  return {kind:'prose',updates:result.updates,insertedTextItems:prepared.insertedTextItems,lineage:prepared.lineage,formattingMark:null,...successor}
}
function attributedHistory(redo, input) {
  if (!input || !['expected,operation_id,reference_id,replay_json','expected,operation_id,replay_json'].includes(Object.keys(input).sort().join(',')) ||
      formattingCapture || historyCapture || lineageCapture) throw Error('Invalid attributed history request')
  const restored = checkedAttributionReplay(input.replay_json, input.expected)
  const candidate = Object.hasOwn(input, 'reference_id') ? {reference:input.reference_id,kind:'formatting'} : currentAttributedCandidate(undo, redo, lineageKey)
  if (candidate.kind === 'prose') return attributedProseHistory(redo, input, candidate.reference)
  const referenceID = candidate.reference
  const resolver = createPlacementResolver(restored.placementState, input.expected.binding, restored.placementReceiptIDs)
  const plan = queryFormatInverse(restored.state, {operationID:referenceID, resolveSuccessor:resolver})
  const prepared = prepareHistoryEvidence(doc, undo, redo, {operation_id:input.operation_id}, lineageKey, plan)
  if (prepared.kind !== 'formatting' || prepared.reference !== referenceID) throw Error('Attributed history owner reference mismatch')
  const update = Y.mergeUpdates(prepared.expectedUpdates)
  const event = captureHistoryFormatEvent(doc, update, {operation_id:input.operation_id,
    mark:plan.mark, text_items:prepared.formattingTextItems})
  const operation = {kind:redo ? 'redo' : 'undo', reference:referenceID}
  const next = prepareFormatAttribution(restored.state, {beforeDoc:doc, update, event, operation, resolveSuccessor:resolver})
  if (next.cut !== prepared.expectedCut) throw Error('Attributed history cut diverged from preflight')
  const successor = nextAttributionReplay(input.replay_json, {kind:'format',update:Array.from(update),event,operation}, next.cut)
  const result = history(redo, prepared)
  if (placementUpdateHash(Y.mergeUpdates(result.updates.map(u=>Uint8Array.from(u)))) !== placementUpdateHash(update)) {
    throw Error('Attributed history update diverged from preflight')
  }
  rememberPlacement(input.operation_id, operation.kind, prepared.reference, prepared.lineage.copies, result.updates)
  return {kind:prepared.kind, updates:result.updates, insertedTextItems:prepared.insertedTextItems,
    lineage:null, formattingMark:result.formattingMark,
    ...successor}
}

function prepareNativeFormatting(operation) {
  const keys = Object.keys(operation.attributes || {})
  if (operation.kind !== 'formatText' || keys.length !== 1 || !['bold', 'italic'].includes(keys[0]) ||
      undo.captureTimeout !== 0 || formattingCapture) throw Error('Expected isolated native bold or italic command')
  const value = operation.attributes[keys[0]]
  if (value !== null && (typeof value !== 'object' || Array.isArray(value) || Object.keys(value).length)) {
    throw Error('Invalid native formatting mark')
  }
  if (operation.operation_id !== undefined && (typeof operation.operation_id !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(operation.operation_id))) throw Error('Invalid host operation identity')
  if (lineageCapture || historyCapture) throw Error('Nested formatting operation')
  const ranges = operation.ranges === undefined
    ? [{ path: operation.path, index: operation.index, length: operation.length }] : operation.ranges
  if (!Array.isArray(ranges) || !ranges.length || ranges.length > 4096 ||
      (operation.ranges !== undefined && ['path', 'index', 'length'].some(key => Object.hasOwn(operation, key)))) {
    throw Error('Invalid native formatting ranges')
  }
  const selected = { version: 1, runs: [] }, seen = new Set()
  const commands = ranges.map(range => {
    const captured = captureTextItems(root, range)
    selected.runs.push(...captured.runs)
    if (selected.runs.length > 4096) throw Error('Formatting selection limit')
    for (const run of captured.runs) for (let n = 0; n < run.count; n++) {
      const key = `${run.item.client}:${run.item.clock + n}`
      if (seen.has(key) || seen.size >= 131072) throw Error('Overlapping or oversized formatting selection')
      seen.add(key)
    }
    return { kind: 'formatText', path: range.path, index: range.index, length: range.length,
      attributes: { ...operation.attributes } }
  })
  return {commands, selected, mark:keys[0]}
}
function nativeFormatting(operation, prepared = prepareNativeFormatting(operation)) {
  const {commands, selected, mark} = prepared
  undo.stopCapturing()
  lineageCapture = operation.operation_id ? { operationID: operation.operation_id, copies: [], formattingMark: mark,
    formattingTextItems: selected } : null
  formattingCapture = mark
  localUpdates = []
  try {
    doc.transact(() => { for (const command of commands) edit(command) }, localOrigin)
    rememberPlacement(operation.operation_id, 'format', null, [], localUpdates)
    return localUpdates
  } finally { formattingCapture = null; lineageCapture = null; undo.stopCapturing() }
}
function attributedNativeFormatting(input) {
  if (!input || Object.keys(input).sort().join(',') !== 'expected,operation,replay_json' ||
      typeof input.operation?.operation_id !== 'string') throw Error('Invalid attributed formatting request')
  const restored = checkedAttributionReplay(input.replay_json, input.expected)
  const prepared = prepareNativeFormatting(input.operation)
  const scratch = new Y.Doc({gc:false}), updates = []
  let expectedState, update, successor
  try {
    Y.applyUpdate(scratch, Y.encodeStateAsUpdate(doc)); scratch.clientID = doc.clientID
    scratch.on('update', (bytes, origin) => { if (origin === localOrigin) updates.push(bytes.slice()) })
    scratch.transact(() => {
      for (const command of prepared.commands) {
        let type = scratch.getXmlFragment('default')
        for (const index of command.path) type = type.get(index)
        type.format(command.index, command.length, command.attributes)
      }
    }, localOrigin)
    if (!updates.length) throw Error('Attributed formatting made no effective change')
    update = Y.mergeUpdates(updates)
    const event = captureHistoryFormatEvent(doc, update, {operation_id:input.operation.operation_id,
      mark:prepared.mark, text_items:prepared.selected})
    const next = prepareFormatAttribution(restored.state, {beforeDoc:doc,update,event})
    if (next.cut !== formatAttributionCut(scratch)) throw Error('Attributed formatting cut diverged from preflight')
    successor = nextAttributionReplay(input.replay_json, {kind:'format',update:Array.from(update),event,operation:null}, next.cut)
    expectedState = Y.encodeStateAsUpdate(scratch)
  } finally { scratch.destroy() }
  const result = nativeFormatting(input.operation, prepared), actual = Y.encodeStateAsUpdate(doc)
  if (actual.length !== expectedState.length || actual.some((byte,i)=>byte !== expectedState[i]) ||
      placementUpdateHash(Y.mergeUpdates(result.map(u=>Uint8Array.from(u)))) !== placementUpdateHash(update)) throw Error('Attributed formatting diverged from preflight')
  return {updates:result,...successor}
}

let localUpdates = []
listen(doc, 'update', (update, origin) => {
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
function proseBlocks(documentRoot = root) { return ownedProseBlocks(documentRoot) }
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
  return replaceOwnedProse(input, targetDoc, targetRoot, localOrigin, hooks)
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
function call(command, input) {
  if (disposed) throw Error('Disposed collaboration context')
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
    case 'prepareLocalPlacementReceipt': {
      if (!input || Object.keys(input).sort().join() !== 'expected_binding,update' || !lastPlacementOperation) throw Error('Missing local placement operation')
      return call('preparePlacementReceipt',{expected_binding:input.expected_binding,trust:'local',update:input.update,
        receipt:{version:1,...input.expected_binding,...JSON.parse(JSON.stringify(lastPlacementOperation))}})
    }
    case 'preparePlacementReceipt': {
      if (input?.trust === 'local') {
        const r=input.receipt, proof=lastPlacementOperation
        if (!proof || r?.operation_id !== proof.operation_id || r?.update_sha256 !== proof.update_sha256 ||
            placementJSON(r?.operation) !== placementJSON(proof.operation) || placementJSON(r?.copies) !== placementJSON(proof.copies)) throw Error('Local placement receipt is not runtime-proven')
      }
      const state=preparePlacementReceipt(placementState || createPlacementState(input.expected_binding),input)
      placementCandidate={version:1,base_sha256:placementBase(),state,receipt:state.receipts.find(row=>row.receipt.operation_id===input.receipt.operation_id).receipt}
      return JSON.parse(JSON.stringify(placementCandidate))
    }
    case 'commitPlacementReceipt': {
      if (!placementCandidate || placementJSON(input)!==placementJSON(placementCandidate) || input.base_sha256!==placementBase()) throw Error('Stale placement candidate')
      placementState=JSON.parse(JSON.stringify(placementCandidate.state));placementCandidate=null;return null
    }
    case 'exportHistorySnapshot':
      if (formattingCapture || historyCapture || lineageCapture) throw Error('History operation is active')
      return placementExport(input)
    case 'restoreHistorySnapshot': {
      if (formattingCapture || historyCapture || lineageCapture || awareness.getStates().size ||
          awarenessOrigins.size || awarenessUpdates.length) throw Error('History restore requires an inactive host')
      let restoredPlacement=null
      if (input.snapshot?.placement !== undefined) {
        restoredPlacement=restorePlacementState(input.snapshot.placement,input.expected_placement_binding,input.placement_receipt_ids)
      } else if (input.expected_placement_binding !== undefined || input.placement_receipt_ids !== undefined) throw Error('Unexpected placement restore expectation')
      const {placement,...snapshot}=input.snapshot
      const allowed=['snapshot','scope_token','transaction_ids',...(placement ? ['expected_placement_binding','placement_receipt_ids'] : [])]
      if (Object.keys(input).some(k=>!allowed.includes(k))) throw Error('Invalid placement restore fields')
      restoreHistorySnapshot(doc, undo, {snapshot,scope_token:input.scope_token,transaction_ids:input.transaction_ids}, lineageKey)
      placementState=restoredPlacement;placementCandidate=null;lastPlacementOperation=null
      // Historical item IDs stay in the snapshot, but this owner keeps a fresh
      // session ID. Align awareness if Yjs rotated a colliding pristine ID.
      awareness.clientID = doc.clientID; awareness.meta.clear()
      awareness.setLocalState(null)
      return null
    }
    case 'apply': Y.applyUpdate(doc, Uint8Array.from(input), 'relay.remote'); return null
    case 'state': return Array.from(Y.encodeStateAsUpdate(doc, input === null ? undefined : Uint8Array.from(input)))
    case 'mergeUpdates': return Array.from(Y.mergeUpdates(input.map(value => Uint8Array.from(value))))
    case 'vector': return Array.from(Y.encodeStateVector(doc))
    case 'snapshot': return snapshot(root)
    case 'replaceProse': localUpdates = []; replaceProse(input); return localUpdates
    case 'supportsProseLineage': return supportsProseLineage(doc)
    case 'replaceProseWithLineage': {
      if (undo.captureTimeout !== 0 || formattingCapture || historyCapture || lineageCapture) throw Error('Expected isolated prose operation')
      const prepared = prepareProseLineage(doc, input, replaceProse)
      return executePreparedProse(input, prepared)
    }
    case 'edit': localUpdates = []; edit(input); return localUpdates
    case 'packAttributionRecord': {
      if (!input || Object.keys(input).sort().join(',') !== 'record_json,update') throw Error('Invalid attribution pack request')
      return packAttributionRecord(input.record_json,input.update)
    }
    case 'unpackAttributionRecord': {
      if (!input || Object.keys(input).sort().join(',') !== 'expected,sidecar_json,update') throw Error('Invalid attribution unpack request')
      return {record_json:unpackAttributionRecord(input.sidecar_json,input.update,input.expected)}
    }
    case 'validateAttributionReplay': {
      if (!input || Object.keys(input).sort().join(',') !== 'expected,replay_json') throw Error('Invalid attribution validation request')
      checkedAttributionReplay(input.replay_json, input.expected); return null
    }
    case 'replaceProseWithAttribution': return attributedProse(input)
    case 'applyAttributionRecords': return applyAttributionRecords(input)
    case 'applyAttributionRecord': return applyAttributionRecord(input)
    case 'createAttributionReplay': return initialAttributionReplay(input)
    case 'nativeFormattingWithAttribution': return attributedNativeFormatting(input)
    case 'nativeFormatting': return nativeFormatting(input)
    case 'nativeParagraphAfter': return nativeParagraphAfter(input)
    case 'nativeParagraphPaste': return nativeParagraphPaste(input)
    case 'beginUndoGroup': undo.stopCapturing(); undo.captureTimeout = Number.MAX_SAFE_INTEGER; return null
    case 'endUndoGroup': undo.stopCapturing(); undo.captureTimeout = 0; return null
    case 'undoWithAttributedEvidence': return attributedHistory(false, input)
    case 'redoWithAttributedEvidence': return attributedHistory(true, input)
    case 'undoWithEvidence':
    case 'redoWithEvidence': {
      if (formattingCapture || historyCapture || lineageCapture) throw Error('Nested history evidence')
      const redo = command === 'redoWithEvidence'
      const prepared = prepareHistoryEvidence(doc, undo, redo, input, lineageKey)
      const result = history(redo, prepared)
      rememberPlacement(input.operation_id, redo ? 'redo' : 'undo', prepared.reference, prepared.lineage.copies, result.updates)
      return { kind: prepared.kind, updates: result.updates, insertedTextItems: prepared.insertedTextItems,
        lineage: prepared.kind === 'prose' ? prepared.lineage : null, formattingMark: result.formattingMark }
    }
    case 'undoWithLineage':
    case 'redoWithLineage': {
      if (formattingCapture || historyCapture || lineageCapture) throw Error('Nested history evidence')
      const redo = command === 'redoWithLineage'
      const prepared = prepareHistoryLineage(doc, undo, redo, input, lineageKey)
      const result = history(redo, prepared)
      rememberPlacement(input.operation_id, redo ? 'redo' : 'undo', prepared.reference, prepared.lineage.copies, result.updates)
      return { updates: result.updates, insertedTextItems: prepared.insertedTextItems, lineage: prepared.lineage }
    }
    case 'undo': return history(false).updates
    case 'redo': return history(true).updates
    case 'undoWithFormattingEvidence':
    case 'redoWithFormattingEvidence': {
      const redo = command === 'redoWithFormattingEvidence'
      if (input === null) return history(redo)
      if (formattingCapture || historyCapture || lineageCapture) throw Error('Nested history evidence')
      const prepared = prepareHistoryLineage(doc, undo, redo, input, lineageKey, true)
      const result=history(redo,prepared)
      rememberPlacement(input.operation_id,redo ? 'redo' : 'undo',prepared.reference,prepared.lineage.copies,result.updates)
      return result
    }
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

function dispose() {
  if (disposed) return
  disposed = true
  for (const [target,event,listener] of subscriptions) target.off(event,listener)
  disposeRetention()
  undo.deleteFilter = previousDeleteFilter
  activeOwners.delete(undo)
  activeDocuments.delete(doc)
  if (!supplied) { awareness.destroy(); undo.destroy(); doc.destroy() }
}
return {call,dispose}
} catch (error) {
  for (const [target,event,listener] of subscriptions) target.off(event,listener)
  disposeRetention()
  undo.deleteFilter = previousDeleteFilter
  activeOwners.delete(undo); activeDocuments.delete(doc)
  if (!supplied) { awareness.destroy(); undo.destroy(); doc.destroy() }
  throw error
}
}
