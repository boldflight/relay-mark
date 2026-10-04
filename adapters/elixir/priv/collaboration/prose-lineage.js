import { validateTextAttributes } from './document-inline.js'
import * as Y from 'yjs'
import { captureTextItems, resolveTextItems, captureVisibleTextItems } from './text-items.js'

// Uniform canonical marks supported by the existing native/browser formatting commands.
export function validProseAttributes(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.entries(value).every(([mark, attributes]) => ['bold', 'italic'].includes(mark) &&
      attributes !== null && typeof attributes === 'object' && !Array.isArray(attributes) && !Object.keys(attributes).length)
}

const empty = () => ({ runs: [] })
const equalBytes = (a, b) => a.length === b.length && a.every((value, i) => value === b[i])
function unicode(value) {
  for (let i = 0; i < value.length; i++) {
    const c = value.charCodeAt(i)
    if (c >= 0xD800 && c <= 0xDBFF) {
      const next = value.charCodeAt(++i)
      if (!(next >= 0xDC00 && next <= 0xDFFF)) throw Error('Invalid prose Unicode')
    } else if (c >= 0xDC00 && c <= 0xDFFF) throw Error('Invalid prose Unicode')
  }
}
function path(root, leaf) {
  for (let i = 0; i < root.length; i++) {
    const p = root.get(i)
    for (let j = 0; j < p.length; j++) if (p.get(j) === leaf) return [i, j]
  }
  throw Error('Unreachable prose evidence')
}
function capture(root, leaf, index, length) {
  return captureTextItems(root, { path: path(root, leaf), index, length })
}
function units(selection) { return selection.runs.reduce((sum, run) => sum + run.count, 0) }
function identities(selection) {
  const result = new Set()
  for (const run of selection.runs) for (let n = 0; n < run.count; n++) {
    const id = `${run.item.client}:${run.item.clock + n}`
    if (result.has(id)) throw Error('Duplicate prose evidence')
    result.add(id)
  }
  return result
}

// Shared structural admission, also used by the read-only host eligibility query.
function proseStructure(root) {
  const blocks = root.toArray()
  if (!blocks.length || blocks.length > 4096) throw Error('Prose lineage block limit')
  let total = blocks.length - 1, leaves = 0
  for (const p of blocks) {
    if (!(p instanceof Y.XmlElement) || p.nodeName !== 'paragraph' || Object.keys(p.getAttributes()).length) {
      throw Error('Prose lineage requires top-level paragraphs')
    }
    for (const leaf of p.toArray()) {
      if (!(leaf instanceof Y.XmlText) || ++leaves > 4096) throw Error('Unsupported prose lineage leaf')
      for (const run of leaf.toDelta()) {
        if (typeof run.insert !== 'string' || /[\n\r\u2028\u2029\ufffc]/u.test(run.insert)) throw Error('Unsupported prose lineage content')
        unicode(run.insert)
      }
      total += leaf.length
    }
  }
  if (total > 131072) throw Error('Prose lineage bounds')
  return { blocks, total }
}

// Conservative host routing policy; existing operation APIs preserve arbitrary
// existing marks, but ordinary native history supports only bold and italic.
export function supportsProseLineage(doc) {
  try {
    const { blocks } = proseStructure(doc.getXmlFragment('default'))
    return blocks.every(p => p.toArray().every(leaf => leaf.toDelta().every(run =>
      validProseAttributes(run.attributes || {}))))
  } catch { return false }
}

// This is an evidence observer, not a second prose mutation implementation.
// The caller supplies the canonical replaceProse function for both executions.
// No user callbacks/await may occur between this preflight and live execution.
export function prepareProseLineage(live, input, replace) {
  if (!input || typeof input !== 'object' || Array.isArray(input) ||
      Object.keys(input).some(key => !['start', 'end', 'text', 'attributes', 'operation_id'].includes(key)) ||
      !Number.isSafeInteger(input.start) || !Number.isSafeInteger(input.end) ||
      input.start < 0 || input.end < input.start || typeof input.text !== 'string' ||
      input.text.length > 131072 || /[\r\u2028\u2029\ufffc]/u.test(input.text) ||
      (input.attributes !== undefined && !validProseAttributes(input.attributes))) throw Error('Unsupported prose lineage operation')
  if (input.operation_id !== undefined && (typeof input.operation_id !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(input.operation_id))) {
    throw Error('Invalid host operation identity')
  }
  unicode(input.text)
  const attributes = Object.fromEntries(Object.keys(input.attributes || {}).sort().map(mark => [mark, {}]))
  const operationInput = { start: input.start, end: input.end, text: input.text, attributes }
  const state = Y.encodeStateAsUpdate(live), vector = Y.encodeStateVector(live), clientID = live.clientID
  // Retain the exact historical structs encoded by the live undo owner.
  const staged = new Y.Doc({ gc: false })
  try {
    Y.applyUpdate(staged, state)
    staged.clientID = clientID
    const root = staged.getXmlFragment('default')
    const { blocks, total } = proseStructure(root)
    if (input.end > total || input.text.split('\n').length + blocks.length > 4096) throw Error('Prose lineage bounds')
    function anchor(offset) {
      for (const p of blocks) {
        const length = p.toArray().reduce((sum, leaf) => sum + leaf.length, 0)
        if (offset <= length) {
          if (!p.length) return Y.relativePositionToJSON(Y.createRelativePositionFromTypeIndex(p, 0, 0))
          for (const leaf of p.toArray()) {
            if (offset <= leaf.length) {
              // Empty item selections do not validate scalar boundaries. Reject
              // an anchor between a surrogate pair, including no-op edits.
              const plain = leaf.toDelta().map(run => run.insert).join('')
              const previous = plain.charCodeAt(offset - 1), next = plain.charCodeAt(offset)
              if (previous >= 0xD800 && previous <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) {
                throw Error('Prose anchor splits a surrogate pair')
              }
              capture(root, leaf, offset, 0)
              return Y.relativePositionToJSON(Y.createRelativePositionFromTypeIndex(leaf, offset, 0))
            }
            offset -= leaf.length
          }
        }
        offset -= length + 1
      }
      throw Error('Invalid prose lineage anchor')
    }
    const operation = { kind: 'replace_prose', start_anchor: anchor(input.start), end_anchor: anchor(input.end),
      inserted_text: input.text, inserted_attributes: attributes }
    const sources = [], copies = [], typed = empty()
    const expectedUpdates = []
    staged.on('update', update => expectedUpdates.push(update.slice()))
    replace(operationInput, staged, root, {
      tail(p, offset, copied) {
        if (!copied) return
        for (const leaf of p.toArray()) {
          if (offset >= leaf.length) { offset -= leaf.length; continue }
          sources.push(capture(root, leaf, offset, leaf.length - offset)); offset = 0
        }
      },
      inserted(leaf, index, length) { typed.runs.push(...capture(root, leaf, index, length).runs) },
      copied(nodes) {
        if (nodes.length !== sources.length) throw Error('Incomplete copied prose evidence')
        nodes.forEach((entry, index) => {
          const leaf = entry.leaf || entry
          const destination = capture(root, leaf, entry.index || 0, entry.length), source = sources[index]
          if (units(source) !== units(destination)) throw Error('Copied prose length changed')
          copies.push({ source, destination })
        })
      }
    })
    if (copies.length !== sources.length) throw Error('Missing copied prose evidence')
    const accounted = { runs: [...typed.runs, ...copies.flatMap(copy => copy.destination.runs)] }
    if (accounted.runs.length > 4096 || units(accounted) > 131072) throw Error('Prose lineage evidence limit')
    const expected = identities(accounted), actual = empty(), prior = Y.decodeStateVector(vector)
    for (const p of root.toArray()) for (const leaf of p.toArray()) {
      for (const run of capture(root, leaf, 0, leaf.length).runs) {
        const first = Math.max(run.item.clock, prior.get(run.item.client) || 0)
        if (first < run.item.clock + run.count) actual.runs.push({ ...run,
          item: { ...run.item, clock: first }, count: run.item.clock + run.count - first })
      }
    }
    const found = identities(actual)
    if (found.size !== expected.size || [...expected].some(id => !found.has(id))) throw Error('Unaccounted prose allocation')
    const resolved = resolveTextItems(staged, root, typed)
    if (resolved.unavailableRuns.length || resolved.collapsedUnits ||
        resolved.segments.map(segment => segment.text).join('') !== input.text.split('\n').join('')) throw Error('Unproven typed prose')
    if (live.clientID !== clientID || !equalBytes(state, Y.encodeStateAsUpdate(live))) throw Error('Prose prestate changed')
    return { input: operationInput, expectedUpdates, expectedState: Y.encodeStateAsUpdate(staged), insertedTextItems: Array.from(new TextEncoder().encode(JSON.stringify(typed))),
      lineage: { operation, copies } }
  } finally { staged.destroy() }
}


/** Capture actual rich text intent before its host-owned editor command. This
 * observes upstream anchors, not numeric flattened prose or another mutation. */
export function captureProseOperation(doc, root, input) {
  if(root.doc!==doc||!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!['start','end','text','attributes'].includes(k))||typeof input.text!=='string'||input.text.length>131072)throw Error('Invalid rich prose operation')
  unicode(input.text);const attributes=structuredClone(input.attributes??{});validateTextAttributes(attributes)
  const positions=[input.start,input.end],paths=positions.map(position=>{
    if(!position||Object.keys(position).sort().join(',')!=='index,path'||!Array.isArray(position.path)||!position.path.length||position.path.length>128||position.path.some(n=>!Number.isSafeInteger(n)||n<0)||!Number.isSafeInteger(position.index)||position.index<0)throw Error('Invalid rich prose position')
    let leaf=root;for(const index of position.path){if(!(leaf instanceof Y.XmlFragment)||index>=leaf.length)throw Error('Invalid rich prose path');leaf=leaf.get(index)}
    if(!(leaf instanceof Y.XmlText)||position.index>leaf.length)throw Error('Expected rich text leaf')
    const text=plainLeaf(leaf),a=text.charCodeAt(position.index-1),b=text.charCodeAt(position.index)
    if(a>=0xD800&&a<=0xDBFF&&b>=0xDC00&&b<=0xDFFF)throw Error('Rich prose anchor splits a surrogate pair')
    return leaf
  })
  const compare=(a,b)=>{for(let n=0;n<Math.min(a.path.length,b.path.length);n++)if(a.path[n]!==b.path[n])return a.path[n]-b.path[n];return a.path.length-b.path.length||a.index-b.index}
  if(compare(...positions)>0)throw Error('Reversed rich prose operation')
  const anchor=(leaf,index)=>JSON.parse(JSON.stringify(Y.relativePositionToJSON(Y.createRelativePositionFromTypeIndex(leaf,index,0))))
  return {kind:'replace_prose',start_anchor:anchor(paths[0],input.start.index),end_anchor:anchor(paths[1],input.end.index),inserted_text:input.text,inserted_attributes:attributes}
}
function plainLeaf(leaf){return leaf.toDelta().map(run=>{if(typeof run.insert!=='string')throw Error('Unsupported rich text embed');return run.insert}).join('')}
function stable(value){if(Array.isArray(value))return value.map(stable);if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(k=>[k,stable(value[k])]));return value}
const equal=(a,b)=>JSON.stringify(stable(a))===JSON.stringify(stable(b))
function richSelection(doc,root,selection){
 const resolved=resolveTextItems(doc,root,selection)
 if(resolved.unavailableRuns.length||resolved.collapsedUnits)throw Error('Unprovable rich item selection')
 const runs=[]
 for(const segment of resolved.segments){let leaf=root;for(const index of segment.path)leaf=leaf.get(index)
  let offset=0;for(const part of leaf.toDelta()){
   if(typeof part.insert!=='string')throw Error('Unsupported rich text embed')
   const first=Math.max(offset,segment.index),last=Math.min(offset+part.insert.length,segment.index+segment.length)
   if(first<last){const attributes=structuredClone(part.attributes??{});validateTextAttributes(attributes);const text=part.insert.slice(first-offset,last-offset),previous=runs.at(-1)
    if(previous&&equal(previous.attributes,attributes))previous.text+=text;else runs.push({text,attributes})
   }offset+=part.insert.length
  }
 }
 return runs
}
function intervals(runs){
 const sorted=runs.map(run=>({client:run.item.client,start:run.item.clock,end:run.item.clock+run.count})).sort((a,b)=>a.client-b.client||a.start-b.start),result=[]
 for(const interval of sorted){const previous=result.at(-1);if(previous&&previous.client===interval.client){if(interval.start<previous.end)throw Error('Overlapping rich allocation evidence');if(interval.start===previous.end){previous.end=interval.end;continue}}result.push(interval)}
 return result
}
/** Validate read-only identity/accounting consequences of one exact host command.
 * The host must independently prove the PM command/StepMap/expected document and
 * authorize immutable receipts. Equal text alone never grants source ownership.
 * Undo copies use the maintained redone observer, not this live-source copier. */
export function validateProseWitness(before, after, witness) {
 if(before===after||!witness||Object.keys(witness).sort().join(',')!=='copies,insertedTextItems,operation'||!Array.isArray(witness.copies))throw Error('Invalid rich prose witness')
 const operation=witness.operation
 if(!operation||Object.keys(operation).sort().join(',')!=='end_anchor,inserted_attributes,inserted_text,kind,start_anchor'||operation.kind!=='replace_prose'||typeof operation.inserted_text!=='string')throw Error('Invalid rich prose operation')
 validateTextAttributes(operation.inserted_attributes);unicode(operation.inserted_text)
 const preRoot=before.getXmlFragment('default'),postRoot=after.getXmlFragment('default'),vector=Y.encodeStateVector(before)
 const typed=richSelection(after,postRoot,witness.insertedTextItems)
 const start=Y.createAbsolutePositionFromRelativePosition(Y.createRelativePositionFromJSON(operation.start_anchor),before,false)
 const end=Y.createAbsolutePositionFromRelativePosition(Y.createRelativePositionFromJSON(operation.end_anchor),before,false)
 if(!start||!end||!(start.type instanceof Y.XmlText)||!(end.type instanceof Y.XmlText))throw Error('Unavailable rich command anchor')
 for(const [anchor,position] of [[operation.start_anchor,start],[operation.end_anchor,end]]){
  if(Object.keys(anchor).some(key=>!['type','item','assoc'].includes(key))||!anchor.type||!Number.isSafeInteger(anchor.assoc)||anchor.assoc<-(2**31)||anchor.assoc>=2**31||!equal(anchor.type,position.type._item?.id))throw Error('Rich anchor type binding mismatch')
  let ancestor=position.type;while(ancestor&&ancestor!==preRoot)ancestor=ancestor.parent
  if(ancestor!==preRoot)throw Error('Rich anchor outside authored scope')
 }
 const expectedText=start.type.parent?.nodeName==='codeBlock'?operation.inserted_text:operation.inserted_text.replace(/\n/g,'')
 if(typed.map(run=>run.text).join('')!==expectedText||typed.some(run=>!equal(run.attributes,operation.inserted_attributes)))throw Error('Unproven rich typed text or attributes')
 const claimed=[...witness.insertedTextItems.runs]
 for(const copy of witness.copies){
  if(!copy||Object.keys(copy).sort().join(',')!=='destination,source')throw Error('Invalid rich copy witness')
  const source=richSelection(before,preRoot,copy.source),destination=richSelection(after,postRoot,copy.destination)
  if(!source.length||!equal(source,destination))throw Error('Copied rich text or attributes changed')
  claimed.push(...copy.destination.runs)
 }
 if(claimed.length>4096||claimed.reduce((n,run)=>n+run.count,0)>131072)throw Error('Rich operation allocation evidence limit')
 const actual=captureVisibleTextItems(postRoot,{since:vector})
 if(!equal(intervals(claimed),intervals(actual.runs)))throw Error('Unaccounted rich allocation')
 return {operation:structuredClone(operation),copies:structuredClone(witness.copies)}
}
