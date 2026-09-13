import * as Y from 'yjs'
import {captureHistoryMarkerState, validateHistoryFormatEvent} from './history-lineage.js'
import {captureTextItems} from './text-items.js'
import {placementUpdateHash} from './placement-lineage.js'
import {formatAttributionCut} from './format-attribution-cut.js'

// Internal immutable candidates only: not a wire format, receipt validator, or
// authority store. The host pairs exact bytes with authorized, ordered receipts.
// State is ephemeral until host receipt replay/durable integration exists. The
// public shell cannot be JSON-hydrated into an authoritative WeakMap candidate.
// effectiveCopies MUST come from placementReceiptCopies for that exact update;
// semantic equality here is a consistency check, never proof of copy ancestry.
const states = new WeakMap(), maximumUnits = 131072, maximumEvents = 16384, maximumBytes = 8 * 1024 * 1024
const clone = x => JSON.parse(JSON.stringify(x))
const key = u => `${u.item.client}:${u.item.clock}@${u.type.client}:${u.type.clock}`
const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b)
const canonical = x => Array.isArray(x) ? x.map(canonical) : x && typeof x==='object' ? Object.fromEntries(Object.keys(x).sort().map(k=>[k,canonical(x[k])])) : x
const digest = formatAttributionCut
// Canonical internal authored identity, distinct from the host's exact JSON
// receipt hash. Derived effects may differ after reconciliation; intent may not.
const authoredIdentity = record => placementUpdateHash(new TextEncoder().encode(JSON.stringify(canonical(record))))

function observe(doc) {
 const markers=captureHistoryMarkerState(doc), result=new Map();let nodes=0
 function walk(type,path) {
  if(++nodes>65536 || path.length>128) throw Error('Attribution traversal limit')
  if(type instanceof Y.XmlText) {
   let offset=0
   for(const delta of type.toDelta()) {
    if(typeof delta.insert!=='string') throw Error('Unsupported attribution embed')
    const attributes=canonical(delta.attributes||{})
    if(['bold','italic'].some(n=>Object.hasOwn(attributes,n)&&!equal(attributes[n],{}))) throw Error('Unsupported attribution marks')
    const selected=captureTextItems(doc.getXmlFragment('default'),{path,index:offset,length:delta.insert.length});let n=0
    for(const run of selected.runs)for(let i=0;i<run.count;i++) {
     const unit={type:clone(run.type),item:{client:run.item.client,clock:run.item.clock+i}}
     if(result.size>=maximumUnits || result.has(key(unit))) throw Error('Attribution unit limit')
     result.set(key(unit),{unit,character:delta.insert[n++],attributes,bold:Object.hasOwn(attributes,'bold'),italic:Object.hasOwn(attributes,'italic')})
    }
    offset+=delta.insert.length
   }
  } else if(type instanceof Y.XmlFragment)type.toArray().forEach((child,i)=>walk(child,[...path,i]))
  else throw Error('Unsupported attribution type')
 }
 walk(doc.getXmlFragment('default'),[])
 if(markers.length!==result.size) throw Error('Incomplete attribution observation')
 return result
}
function publish(data) {const state=Object.freeze({version:1,fenced:data.fenced,cut:data.cut});states.set(state,data);return state}
function read(state) {const data=states.get(state);if(!data)throw Error('Unknown attribution candidate');return data}
export function createFormatAttribution(doc) {
 const cut=digest(doc),current=observe(doc),entries=new Map([...current].map(([k,row])=>[k,{...row,tokens:{bold:null,italic:null}}]))
 return publish({cut,fenced:false,entries,current,events:new Map(),dispositions:new Map(),consumedReferences:new Set(),retainedChanges:0})
}
export function fenceFormatAttribution(state) {return publish({...read(state),fenced:true})}
function prepare(state,beforeDoc,update,apply) {
 const old=read(state)
 if(old.fenced || digest(beforeDoc)!==old.cut)throw Error('Fenced or stale attribution cut')
 if(!(update instanceof Uint8Array)||!update.length||update.length>maximumBytes)throw Error('Invalid attribution update')
 const scratch=new Y.Doc({gc:false})
 try {
  Y.applyUpdate(scratch,Y.encodeStateAsUpdate(beforeDoc));Y.applyUpdate(scratch,update)
  const cut=digest(scratch),current=observe(scratch)
  const next={cut,fenced:false,entries:new Map(old.entries),current,events:new Map(old.events),dispositions:new Map(old.dispositions),consumedReferences:new Set(old.consumedReferences),retainedChanges:old.retainedChanges,updateSHA256:placementUpdateHash(update)}
  apply(old,next)
  if(next.entries.size>maximumUnits || next.events.size>maximumEvents)throw Error('Attribution retention limit')
  return publish(next)
 } finally {scratch.destroy()}
}
const uuid = value => typeof value==='string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value)
function inverseReference(old,operation,operationID) {
 if(!operation||Object.keys(operation).sort().join(',')!=='kind,reference'||
    !['undo','redo'].includes(operation.kind)||!uuid(operation.reference)||operation.reference===operationID)throw Error('Invalid inverse attribution reference')
 const reference=old.events.get(operation.reference)
 if(!reference||(operation.kind==='redo'&&reference.kind!=='undo')||(operation.kind==='undo'&&reference.kind==='undo'))throw Error('Invalid inverse attribution kind')
 if(old.dispositions.get(reference.disposition.contributionID)!==reference.disposition.afterActive||
    old.consumedReferences.has(operation.reference))throw Error('Consumed inverse attribution reference')
 return reference
}

// A verified history disposition, not a formatting event or a Yjs update. The
// ordered host journal supplies owner authorization; replay recomputes no effect.
export function prepareNoEffectFormatAttribution(state,{beforeDoc,event,operation,resolveSuccessor}) {
 const old=read(state)
 if(old.fenced||digest(beforeDoc)!==old.cut)throw Error('Fenced or stale attribution cut')
 if(!event||Object.keys(event).sort().join(',')!=='mark,operation_id,version'||event.version!==1||
    !uuid(event.operation_id)||!['bold','italic'].includes(event.mark)||typeof resolveSuccessor!=='function')throw Error('Invalid no-effect attribution event')
 if(old.events.has(event.operation_id))throw Error('Duplicate attribution event')
 const reference=inverseReference(old,operation,event.operation_id)
 const plan=queryFormatInverse(state,{operationID:operation.reference,resolveSuccessor})
 if(plan.kind!=='noop'||plan.mark!==event.mark)throw Error('Effective inverse cannot be a no-effect disposition')
 const disposition={contributionID:reference.disposition.contributionID,beforeActive:reference.disposition.afterActive,afterActive:reference.disposition.beforeActive}
 const retainedChanges=old.retainedChanges+plan.logicalScope.length
 if(old.events.size>=maximumEvents||retainedChanges>maximumUnits)throw Error('Attribution event unit limit')
 const next={...old,events:new Map(old.events),dispositions:new Map(old.dispositions),consumedReferences:new Set(old.consumedReferences),retainedChanges}
 next.consumedReferences.add(operation.reference)
 next.dispositions.set(disposition.contributionID,disposition.afterActive)
 next.events.set(event.operation_id,{authoredRecordSHA256:authoredIdentity({kind:"format_noop",event,operation}),disposition,kind:operation.kind,reference:operation.reference,mark:event.mark,changes:[],scopeChanges:clone(plan.logicalScope)})
 return publish(next)
}
export function prepareFormatAttribution(state,{beforeDoc,update,event,operation=null,resolveSuccessor}) {
 return prepare(state,beforeDoc,update,(old,next)=>{
  const verified=validateHistoryFormatEvent(beforeDoc,update,event)
  if(old.events.has(verified.operation_id))throw Error('Duplicate attribution event')
  let inverseTargets=null,logicalScope=null,disposition={contributionID:verified.operation_id,beforeActive:false,afterActive:true}
  if(operation!==null) {
   if(!operation||Object.keys(operation).sort().join(',')!=='kind,reference'||
      !['undo','redo'].includes(operation.kind)||typeof operation.reference!=='string'||
      operation.reference===verified.operation_id||typeof resolveSuccessor!=='function')throw Error('Invalid inverse attribution reference')
   const reference=inverseReference(old,operation,verified.operation_id)
   disposition={contributionID:reference.disposition.contributionID,beforeActive:reference.disposition.afterActive,afterActive:reference.disposition.beforeActive}
   const plan=queryFormatInverse(state,{operationID:operation.reference,resolveSuccessor})
   if(plan.kind!=='apply'||plan.mark!==verified.mark)throw Error('Ineffective inverse attribution')
   inverseTargets=new Map(plan.targets.map(target=>[key(target.unit),target]))
   logicalScope=plan.logicalScope
   if(inverseTargets.size!==verified.changes.length||verified.changes.some(change=>{
    const target=inverseTargets.get(key(change.unit));return !target||target.enabled!==change.after.enabled
   }))throw Error('Inverse attribution witness does not match effective targets')
  }
  const changes=[]
  for(const [k,row] of next.current) {
   const previous=old.entries.get(k)
   if(!old.current.has(k)||!previous||previous.character!==row.character)throw Error('Format changed attribution identities')
   const withoutMark=value=>Object.fromEntries(Object.entries(value).filter(([name])=>name!==verified.mark))
   if(!equal(withoutMark(previous.attributes),withoutMark(row.attributes)))throw Error('Unproven unrelated format attributes')
   next.entries.set(k,{...row,tokens:clone(previous.tokens)})
  }
  if(next.current.size!==old.current.size)throw Error('Format removed attribution identities')
  for(const change of verified.changes) {
   const k=key(change.unit),previous=old.entries.get(k),row=next.entries.get(k)
   if(!previous||!row)throw Error('Missing attribution target')
   const afterToken=inverseTargets?inverseTargets.get(k).restoreToken:verified.operation_id
   row.tokens[verified.mark]=afterToken
   changes.push({unit:clone(change.unit),beforeToken:previous.tokens[verified.mark],afterToken,beforeEnabled:change.before.enabled,afterEnabled:change.after.enabled})
  }
  const scopeChanges=logicalScope||changes
  if(next.retainedChanges+changes.length+scopeChanges.length>maximumUnits)throw Error('Attribution event unit limit')
  next.retainedChanges+=changes.length+scopeChanges.length
  if(operation!==null)next.consumedReferences.add(operation.reference)
  next.dispositions.set(disposition.contributionID,disposition.afterActive)
  next.events.set(verified.operation_id,{authoredRecordSHA256:authoredIdentity({kind:'format',update:Array.from(update),event:verified,operation}),disposition,kind:operation?.kind||'format',reference:operation?.reference||null,mark:verified.mark,changes,scopeChanges})
 })
}
export function prepareCopyAttribution(state,{beforeDoc,update,effectiveCopies}) {
 return prepare(state,beforeDoc,update,(old,next)=>{
  if(!Array.isArray(effectiveCopies)||effectiveCopies.length>maximumUnits)throw Error('Attribution copy limit')
  const destinations=new Set(),sources=new Set()
  for(const pair of effectiveCopies) {
   const sk=key(pair.source),dk=key(pair.destination),source=old.entries.get(sk),destination=next.current.get(dk)
   // A verified inverse may restore an exact retired identity (typed or baseline).
   // Retained entries preserve its tokens; never infer ancestry from matching text.
   if(!source||!destination||old.current.has(dk)||sources.has(sk)||destinations.has(dk))throw Error('Unavailable or duplicate attribution copy')
   if(source.character!==destination.character||!equal(source.attributes,destination.attributes))throw Error('Attribution copy semantics mismatch')
   sources.add(sk);destinations.add(dk)
   next.entries.set(dk,{...destination,tokens:clone(source.tokens)})
  }
  for(const [k,row] of next.current) {
   const previous=old.entries.get(k)
   if(old.current.has(k)) {
    if(previous.character!==row.character||!equal(previous.attributes,row.attributes))throw Error('Unproven surviving attribution change')
    next.entries.set(k,{...row,tokens:clone(previous.tokens)})
   } else if(!destinations.has(k)) {
    // Newly typed units have no formatting event authority. Previously retired
    // identities cannot silently return without explicit copy evidence.
    if(previous)throw Error('Unproven retired attribution restoration')
    next.entries.set(k,{...row,tokens:{bold:null,italic:null}})
   }
  }
 })
}
export function queryFormatInverse(state,{operationID,resolveSuccessor}) {
 const data=read(state)
 if(data.fenced)return {kind:'fenced',targets:[],protected:[]}
 const event=data.events.get(operationID)
 if(!event)throw Error('Unknown attribution event')
 const targets=[],protectedUnits=[],logicalScope=[],seen=new Set(),indices=new Map()
 let visited=0
 const prospectiveActive=token=>token===event.disposition.contributionID?event.disposition.beforeActive:data.dispositions.get(token)
 function predecessor(token,unit,enabled,prospective=true) {
  const traversed=new Set()
  while(token!==null) {
   if(++visited>maximumUnits||traversed.has(token))throw Error('Attribution predecessor traversal limit')
   traversed.add(token)
   const contribution=data.events.get(token)
   if(!contribution||contribution.kind!=='format')throw Error('Unknown attribution predecessor')
   if(!indices.has(token)) {
    const index=new Map()
    for(const change of contribution.scopeChanges) {
     if(++visited>maximumUnits)throw Error('Attribution predecessor traversal limit')
     const destination=resolveSuccessor(clone(change.unit))
     if(destination) {
      const k=key(destination)
      if(index.has(k))throw Error('Ambiguous attribution predecessor')
      index.set(k,change)
     }
    }
    indices.set(token,index)
   }
   const change=indices.get(token).get(key(unit))
   if(!change)throw Error('Unavailable attribution predecessor')
   if(prospective?prospectiveActive(token):data.dispositions.get(token))return {token,enabled:change.afterEnabled}
   token=change.beforeToken;enabled=change.beforeEnabled
  }
  return {token:null,enabled}
 }
 for(const change of event.scopeChanges) {
  const destination=resolveSuccessor(clone(change.unit)),k=destination&&key(destination),row=k&&data.entries.get(k)
  if(k&&seen.has(k))throw Error('Ambiguous attribution successor')
  if(k)seen.add(k)
  const restored=predecessor(change.beforeToken,destination||change.unit,change.beforeEnabled)
  logicalScope.push({unit:clone(change.unit),beforeToken:change.afterToken,beforeEnabled:change.afterEnabled,afterToken:restored.token,afterEnabled:restored.enabled})
  const currentToken=row&&data.current.has(k)?predecessor(row.tokens[event.mark],destination,row[event.mark],false).token:null
  if(!row||!data.current.has(k)||currentToken!==change.afterToken) {
   protectedUnits.push({unit:clone(change.unit),reason:'not-current-event'});continue
  }
  if(row[event.mark]===restored.enabled)continue
  targets.push({unit:clone(destination),mark:event.mark,enabled:restored.enabled,restoreToken:restored.token})
 }
 return {kind:targets.length?'apply':'noop',operationID,mark:event.mark,prestate_sha256:data.cut,targets,protected:protectedUnits,logicalScope}
}

// Internal pure preparation only. The host independently authenticates the
// original observed basis and receipt order. No caller document/manager is
// mutated, and authored bytes are never rewritten into the correction.
export function prepareFormatInverseReconciliation(state,{beforeDoc,basis,recordJSON,resolveSuccessor}) {
 const old=read(state)
 if(old.fenced||digest(beforeDoc)!==old.cut||!basis||typeof basis.resolveSuccessor!=='function'||typeof resolveSuccessor!=='function')throw Error('Invalid reconciliation context')
 if(typeof recordJSON!=='string'||!recordJSON.length||new TextEncoder().encode(recordJSON).length>64*1024*1024)throw Error('Invalid reconciliation record')
 const record=JSON.parse(recordJSON)
 if(JSON.stringify(record)!==recordJSON)throw Error('Reconciliation requires exact compact record')
 const names=record.kind==='format_noop'?['event','kind','operation']:['event','kind','operation','update']
 if(!['format','format_noop'].includes(record.kind)||Object.keys(record).sort().join(',')!==names.sort().join(',')||!record.operation)throw Error('Invalid reconciliation inverse')
 const authored=record.kind==='format'?record.update:null
 if(authored&&(!Array.isArray(authored)||!authored.length||authored.length>maximumBytes||authored.some(n=>!Number.isInteger(n)||n<0||n>255)))throw Error('Invalid reconciliation authored bytes')
 const basisData=read(basis.state)
 // Existing strict admission proves exactly what the author observed and did.
 const validated=record.kind==='format_noop'
  ?prepareNoEffectFormatAttribution(basis.state,{beforeDoc:basis.doc,event:record.event,operation:record.operation,resolveSuccessor:basis.resolveSuccessor})
  :prepareFormatAttribution(basis.state,{beforeDoc:basis.doc,update:Uint8Array.from(authored),event:record.event,operation:record.operation,resolveSuccessor:basis.resolveSuccessor})
 const authoredRecordSHA256=read(validated).events.get(record.event.operation_id).authoredRecordSHA256
 for(const [id,event] of basisData.events) {
  const current=old.events.get(id)
  if(!current||current.authoredRecordSHA256!==event.authoredRecordSHA256||
    ['kind','reference','mark'].some(field=>current[field]!==event[field])||
    !equal(canonical(current.disposition),canonical(event.disposition))||
    (event.kind==='format'&&!equal(canonical(current.scopeChanges),canonical(event.scopeChanges))))throw Error('Incompatible reconciliation event basis')
 }
 if(old.events.has(record.event.operation_id))throw Error('Duplicate reconciliation operation')
 const reference=inverseReference(old,record.operation,record.event.operation_id)
 const plan=queryFormatInverse(state,{operationID:record.operation.reference,resolveSuccessor})
 if(!['apply','noop'].includes(plan.kind)||plan.mark!==record.event.mark)throw Error('Invalid reconciliation plan')
 const scratch=new Y.Doc({gc:false}),replica=new Y.Doc({gc:false})
 try {
  const before=Y.encodeStateAsUpdate(beforeDoc)
  Y.applyUpdate(scratch,before);Y.applyUpdate(scratch,Y.encodeStateAsUpdate(basis.doc))
  if(digest(scratch)!==old.cut)throw Error('Reconciliation basis is not observed by current document')
  if(authored)Y.applyUpdate(scratch,Uint8Array.from(authored))
  const integrated=observe(scratch),desired=new Map([...old.current].map(([k,row])=>[k,{...row,attributes:clone(row.attributes)}]))
  if(integrated.size!==old.current.size)throw Error('Reconciliation changed text identities')
  const mark=plan.mark
  for(const [k,row] of integrated) {
   const previous=old.current.get(k)
   if(!previous||previous.character!==row.character)throw Error('Reconciliation changed text identities')
   const other=attrs=>Object.fromEntries(Object.entries(attrs).filter(([name])=>name!==mark))
   if(!equal(other(previous.attributes),other(row.attributes)))throw Error('Reconciliation changed unrelated attributes')
  }
  for(const target of plan.targets) {
   const row=desired.get(key(target.unit))
   if(!row)throw Error('Unavailable reconciliation target')
   if(target.enabled)row.attributes[mark]={};else delete row.attributes[mark]
  }
  const updates=[];scratch.on('update',update=>updates.push(update.slice()))
  scratch.transact(()=>materializeReconciliation(scratch,desired,mark))
  const correction=updates.length?Y.mergeUpdates(updates):null
  if(correction&&correction.length>maximumBytes)throw Error('Reconciliation correction limit')
  const cut=digest(scratch),current=observe(scratch)
  for(const [k,row] of current)if(!equal(row.attributes,canonical(desired.get(k).attributes)))throw Error('Reconciliation projection mismatch')
  // The exact recorded pair must reproduce the full cut independently, including
  // remote Yjs formatting cleanup. Visible equality alone is insufficient.
  Y.applyUpdate(replica,before)
  if(authored)Y.applyUpdate(replica,Uint8Array.from(authored))
  if(correction)Y.applyUpdate(replica,correction)
  if(digest(replica)!==cut)throw Error('Reconciliation bytes are not independently replayable')
  const next={...old,cut,current,entries:new Map(old.entries),events:new Map(old.events),
   dispositions:new Map(old.dispositions),consumedReferences:new Set(old.consumedReferences)}
  for(const [k,row] of current)next.entries.set(k,{...row,tokens:clone(old.entries.get(k).tokens)})
  const changes=plan.targets.map(target=>{
   const k=key(target.unit),previous=old.entries.get(k)
   next.entries.get(k).tokens[mark]=target.restoreToken
   return {unit:clone(target.unit),beforeToken:previous.tokens[mark],afterToken:target.restoreToken,beforeEnabled:previous[mark],afterEnabled:target.enabled}
  })
  next.retainedChanges+=changes.length+plan.logicalScope.length
  if(next.retainedChanges>maximumUnits||next.events.size>=maximumEvents)throw Error('Reconciliation attribution limit')
  const disposition={contributionID:reference.disposition.contributionID,beforeActive:reference.disposition.afterActive,afterActive:reference.disposition.beforeActive}
  next.dispositions.set(disposition.contributionID,disposition.afterActive);next.consumedReferences.add(record.operation.reference)
  next.events.set(record.event.operation_id,{authoredRecordSHA256,disposition,kind:record.operation.kind,reference:record.operation.reference,mark,changes,scopeChanges:clone(plan.logicalScope)})
  return Object.freeze({recordJSON,authoredUpdate:authored?Object.freeze([...authored]):null,
   correctionUpdate:correction?Object.freeze([...correction]):null,cut,state:publish(next)})
 }finally{scratch.destroy();replica.destroy()}
}
function materializeReconciliation(doc,desired,mark) {
 function walk(type,path) {
  if(type instanceof Y.XmlText) {
   const selection=captureTextItems(doc.getXmlFragment('default'),{path,index:0,length:type.length})
   const units=selection.runs.flatMap(run=>Array.from({length:run.count},(_,i)=>({type:run.type,item:{client:run.item.client,clock:run.item.clock+i}})))
   const current=[]
   for(const delta of type.toDelta())for(let i=0;i<delta.insert.length;i++)current.push(Object.hasOwn(delta.attributes||{},mark))
   const ranges=[]
   for(let i=0;i<units.length;i++) {
    const enabled=Object.hasOwn(desired.get(key(units[i])).attributes,mark)
    if(enabled===current[i])continue
    const last=ranges.at(-1)
    if(last&&last.index+last.length===i&&last.enabled===enabled)last.length++
    else ranges.push({index:i,length:1,enabled})
   }
   for(const range of ranges)type.format(range.index,range.length,{[mark]:range.enabled?{}:null})
  }else type.toArray().forEach((child,i)=>walk(child,[...path,i]))
 }
 walk(doc.getXmlFragment('default'),[])
}
