import {placementUpdateHash} from './placement-lineage.js'

// Storage codec only: no document, author, or receipt authentication. The host
// binds the sidecar digest and operation ID to its qualified immutable update row.
// Full witness/placement semantics are checked during attributed replay.
const maximumBytes=64*1024*1024, maximumUpdateBytes=8*1024*1024
const uuid=x=>typeof x==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(x)
const hash=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x)
function keys(value,names){if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).sort().join(',')!==[...names].sort().join(','))throw Error('Invalid attribution record fields')}
function textBytes(value){
 if(typeof value!=='string'||!value.length||value.length>maximumBytes)throw Error('Attribution record size limit')
 const bytes=new TextEncoder().encode(value)
 if(bytes.length>maximumBytes)throw Error('Attribution record size limit')
 return bytes
}
function updateBytes(value){
 if(!(value instanceof Uint8Array)&&!Array.isArray(value))throw Error('Invalid attribution record update')
 if(!value.length||value.length>maximumUpdateBytes||value.some(n=>!Number.isInteger(n)||n<0||n>255))throw Error('Invalid attribution record update')
 return Uint8Array.from(value)
}
function header(record,updateHash){
 let value
 if(record?.kind==='format'){
  keys(record,['kind','update','event','operation']);value=record.event
  keys(value,['contract_version','kind','operation_id','update_sha256','mark','text_items','inserted_markers','deleted_markers','changes'])
  if(value.kind !== 'format_event'||!['bold','italic'].includes(value.mark))throw Error('Invalid attribution record mark')
  if(record.operation!==null){
   keys(record.operation,['kind','reference'])
   if(!['undo','redo'].includes(record.operation.kind)||!uuid(record.operation.reference)||record.operation.reference===value.operation_id)throw Error('Invalid attribution record inverse')
  }
 }else if(record?.kind==='placement'){
  keys(record,['kind','update','receipt','trust']);value=record.receipt
  keys(value,['contract_version','kind','document_id','incarnation','operation_id','update_sha256','operation','copies'])
  if(value.kind !== 'placement_receipt'||!['local','server'].includes(record.trust)||!uuid(value.document_id)||typeof value.incarnation!=='string'||!value.incarnation.length||new TextEncoder().encode(value.incarnation).length>256)throw Error('Invalid attribution record binding')
  keys(value.operation,['kind','reference'])
  const inverse=['undo','redo'].includes(value.operation.kind)
  if(!['replace_prose','format','undo','redo'].includes(value.operation.kind)||(inverse?!uuid(value.operation.reference):value.operation.reference!==null)||value.operation.reference===value.operation_id)throw Error('Invalid attribution record operation')
 }else throw Error('Unknown attribution record kind')
 if(value.contract_version!==1||!uuid(value.operation_id)||value.update_sha256!==updateHash)throw Error('Attribution record update binding mismatch')
 return value.operation_id
}

export function packAttributionRecord(recordJSON,update){
 const encoded=textBytes(recordJSON),bytes=updateBytes(update),record=JSON.parse(recordJSON)
 // Runtime records are compact JSON.stringify output. Reject noncanonical
 // whitespace/escapes/duplicate keys rather than silently changing receipt bytes.
 if(JSON.stringify(record)!==recordJSON)throw Error('Attribution record is not compact runtime JSON')
 const digest=placementUpdateHash(bytes),operationID=header(record,digest)
 if(!Array.isArray(record.update)||record.update.length!==bytes.length||record.update.some((n,i)=>n!==bytes[i]))throw Error('Attribution record bytes mismatch')
 const recordHash=placementUpdateHash(encoded)
 // Preserve the update property's position; reconstructing it yields the exact
 // original record serialization without storing its payload a second time.
 record.update=null
 const sidecarJSON=JSON.stringify({version:1,record_sha256:recordHash,update_sha256:digest,record})
 const sidecarBytes=textBytes(sidecarJSON)
 return {sidecar_json:sidecarJSON,sidecar_sha256:placementUpdateHash(sidecarBytes),record_sha256:recordHash,update_sha256:digest,operation_id:operationID}
}

export function unpackAttributionRecord(sidecarJSON,update,expected){
 keys(expected,['sidecar_sha256','operation_id'])
 if(!hash(expected.sidecar_sha256)||!uuid(expected.operation_id))throw Error('Invalid attribution sidecar expectation')
 const encoded=textBytes(sidecarJSON)
 if(placementUpdateHash(encoded)!==expected.sidecar_sha256)throw Error('Attribution sidecar digest mismatch')
 const sidecar=JSON.parse(sidecarJSON),bytes=updateBytes(update),digest=placementUpdateHash(bytes)
 keys(sidecar,['version','record_sha256','update_sha256','record'])
 if(sidecar.version!==1||!hash(sidecar.record_sha256)||sidecar.update_sha256!==digest||sidecar.record?.update!==null)throw Error('Invalid attribution sidecar update binding')
 sidecar.record.update=Array.from(bytes)
 if(header(sidecar.record,digest)!==expected.operation_id)throw Error('Attribution sidecar operation mismatch')
 const recordJSON=JSON.stringify(sidecar.record)
 if(placementUpdateHash(textBytes(recordJSON))!==sidecar.record_sha256)throw Error('Attribution record digest mismatch')
 return recordJSON
}


function metadataHeader(record) {
 keys(record,['kind','event','operation'])
 keys(record.event,['version','operation_id','mark'])
 keys(record.operation,['kind','reference'])
 const event=record.event,operation=record.operation
 if(record.kind!=='format_noop'||event.version!==1||!uuid(event.operation_id)||
    !['bold','italic'].includes(event.mark)||!['undo','redo'].includes(operation.kind)||
    !uuid(operation.reference)||operation.reference===event.operation_id)throw Error('Invalid attribution metadata record')
 return event.operation_id
}

// No-effect history has an operation identity and exact record bytes, but no
// Yjs update payload/hash. Keep its storage shape distinct from update sidecars.
export function packAttributionMetadata(recordJSON) {
 const encoded=textBytes(recordJSON),record=JSON.parse(recordJSON)
 if(JSON.stringify(record)!==recordJSON)throw Error('Attribution metadata is not compact runtime JSON')
 const operationID=metadataHeader(record),recordHash=placementUpdateHash(encoded)
 const sidecarJSON=JSON.stringify({version:1,record_sha256:recordHash,record})
 return {sidecar_json:sidecarJSON,sidecar_sha256:placementUpdateHash(textBytes(sidecarJSON)),
  record_sha256:recordHash,operation_id:operationID}
}

export function unpackAttributionMetadata(sidecarJSON,expected) {
 keys(expected,['sidecar_sha256','operation_id'])
 if(!hash(expected.sidecar_sha256)||!uuid(expected.operation_id))throw Error('Invalid attribution metadata expectation')
 const encoded=textBytes(sidecarJSON)
 if(placementUpdateHash(encoded)!==expected.sidecar_sha256)throw Error('Attribution metadata digest mismatch')
 const sidecar=JSON.parse(sidecarJSON)
 keys(sidecar,['version','record_sha256','record'])
 if(sidecar.version!==1||!hash(sidecar.record_sha256)||metadataHeader(sidecar.record)!==expected.operation_id)throw Error('Invalid attribution metadata binding')
 const recordJSON=JSON.stringify(sidecar.record)
 if(placementUpdateHash(textBytes(recordJSON))!==sidecar.record_sha256)throw Error('Attribution metadata record digest mismatch')
 return recordJSON
}
