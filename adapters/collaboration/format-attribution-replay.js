import * as Y from 'yjs'
import {createFormatAttribution, prepareFormatAttribution, prepareCopyAttribution} from './format-attribution.js'
import {createPlacementState, preparePlacementReceipt, placementReceiptCopies, createPlacementResolver, placementUpdateHash} from './placement-lineage.js'
import {formatAttributionCut} from './format-attribution-cut.js'

// Internal trusted-host reconstruction, NOT receipt authentication. The expected
// digest/scope/cut must come from the host's atomic journal, independently of the
// recipe being read. A baseline must precede every retained contribution. Never
// turn an arbitrary after-state snapshot into a history baseline to fit a bound.
// Returned placementState is the structural projection used for replay, not a
// replacement for a host graph that also retains empty-copy format receipts.
const maximumBytes = 64 * 1024 * 1024, maximumUpdateBytes = 8 * 1024 * 1024, maximumSteps = 16384
const keys = (value, names) => {
 if (!value || typeof value !== 'object' || Array.isArray(value) ||
     Object.keys(value).sort().join(',') !== [...names].sort().join(',')) throw Error('Invalid attribution replay fields')
}
const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value)
function bytes(value) {
 if (!Array.isArray(value) || !value.length || value.length > maximumUpdateBytes ||
     value.some(n => !Number.isInteger(n) || n < 0 || n > 255)) throw Error('Invalid attribution replay update')
 return Uint8Array.from(value)
}

export function replayFormatAttribution(replayJSON, expected) {
 keys(expected, ['scope_token', 'binding', 'replay_sha256', 'cut'])
 if (typeof expected.scope_token !== 'string' || !expected.scope_token.length || new TextEncoder().encode(expected.scope_token).length > 2048 ||
     !hash(expected.replay_sha256) || !hash(expected.cut) || typeof replayJSON !== 'string' ||
     replayJSON.length > maximumBytes) throw Error('Invalid attribution replay expectation')
 const encoded = new TextEncoder().encode(replayJSON)
 if (encoded.length > maximumBytes || placementUpdateHash(encoded) !== expected.replay_sha256) throw Error('Attribution replay digest mismatch')
 const recipe = JSON.parse(replayJSON)
 keys(recipe, ['version', 'scope_token', 'binding', 'baseline', 'steps'])
 if (recipe.version !== 1 || recipe.scope_token !== expected.scope_token || !Array.isArray(recipe.steps) ||
     recipe.steps.length > maximumSteps) throw Error('Invalid attribution replay scope or steps')
 let graph = createPlacementState(expected.binding)
 const binding = createPlacementState(recipe.binding).binding
 if (binding.document_id !== graph.binding.document_id || binding.incarnation !== graph.binding.incarnation) throw Error('Attribution replay binding mismatch')
 // Check all envelope/update bounds before allocating a replay document. Exact
 // witness and placement validation remains in the existing reducers below.
 const baseline = bytes(recipe.baseline), seen = new Set(), ids = []
 let totalBytes = baseline.length
 const steps = recipe.steps.map(step => {
  if (step?.kind === 'format') keys(step, ['kind', 'update', 'event', 'operation'])
  else if (step?.kind === 'placement') keys(step, ['kind', 'update', 'receipt', 'trust'])
  else throw Error('Unknown attribution replay step')
  const update = bytes(step.update), operationID = step.kind === 'format' ? step.event?.operation_id : step.receipt?.operation_id
  if (typeof operationID !== 'string' || seen.has(operationID)) throw Error('Duplicate or missing attribution replay operation')
  seen.add(operationID); totalBytes += update.length
  if (totalBytes > maximumBytes) throw Error('Attribution replay byte limit')
  return {...step, update}
 })
 const doc = new Y.Doc({gc:false})
 try {
  Y.applyUpdate(doc, baseline)
  let state = createFormatAttribution(doc)
  for (const step of steps) {
   if (step.kind === 'format') {
    state = prepareFormatAttribution(state, {beforeDoc:doc, update:step.update, event:step.event,
     operation:step.operation, resolveSuccessor:createPlacementResolver(graph, binding, ids)})
   } else {
    graph = preparePlacementReceipt(graph, {expected_binding:binding, trust:step.trust, update:[...step.update], receipt:step.receipt})
    ids.push(step.receipt.operation_id)
    state = prepareCopyAttribution(state, {beforeDoc:doc, update:step.update,
     effectiveCopies:placementReceiptCopies(graph, binding, ids, step.receipt.operation_id)})
   }
   Y.applyUpdate(doc, step.update)
  }
  if (formatAttributionCut(doc) !== expected.cut) throw Error('Attribution replay final cut mismatch')
  return {state, placementState:graph, placementReceiptIDs:ids}
 } finally {doc.destroy()}
}
