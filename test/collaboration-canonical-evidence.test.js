import test from 'node:test'
import assert from 'node:assert/strict'
import * as Y from 'yjs'
import {captureTextItems,resolveTextItems} from '../adapters/collaboration/text-items.js'
import {captureHistoryFormatEvent,validateHistoryFormatEvent} from '../adapters/collaboration/history-lineage.js'
import {createPlacementState,preparePlacementReceipt,placementUpdateHash} from '../adapters/collaboration/placement-lineage.js'
import {packAttributionRecord} from '../adapters/collaboration/attribution-record-codec.js'

test('rich question text evidence uses the shared contract and refuses retired inner counters',()=>{
 const author=new Y.Doc({gc:false}),root=author.getXmlFragment('default')
 const q=new Y.XmlElement('questionBlock'),option=new Y.XmlElement('questionOption'),text=new Y.XmlText()
 root.insert(0,[q]);q.insert(0,[option]);option.insert(0,[text]);text.insert(0,'Paris 🌍')
 const reader=new Y.Doc({gc:false});Y.applyUpdate(reader,Y.encodeStateAsUpdate(author))
 const selected=captureTextItems(reader.getXmlFragment('default'),{path:[0,0,0],index:0,length:5})
 assert.deepEqual(Object.keys(selected),['runs'])
 assert.throws(()=>resolveTextItems(reader,reader.getXmlFragment('default'),{version:1,...selected}))
 let update;author.on('update',bytes=>{update=bytes});text.format(0,5,{bold:{}})
 const operation_id='73000000-0000-4000-8000-000000000001'
 const event=captureHistoryFormatEvent(reader,update,{operation_id,mark:'bold',text_items:selected})
 assert.equal(event.contract_version,1);assert.equal(event.kind,'format_event');assert.equal('version' in event,false)
 assert.deepEqual(validateHistoryFormatEvent(reader,update,event),event)
 assert.throws(()=>validateHistoryFormatEvent(reader,update,{...event,text_items:{version:1,...selected}}))
 const record=JSON.stringify({kind:'format',update:[...update],event,operation:null})
 assert.equal(packAttributionRecord(record,update).operation_id,operation_id)
 const binding={document_id:'73000000-0000-4000-8000-000000000090',incarnation:'rich-question'}
 const receipt={contract_version:1,kind:'placement_receipt',...binding,update_sha256:placementUpdateHash(update),operation_id,operation:{kind:'format',reference:null},copies:[]}
 const state=preparePlacementReceipt(createPlacementState(binding),{expected_binding:binding,trust:'local',update:[...update],receipt})
 assert.deepEqual(state.receipts[0].receipt,receipt)
 reader.destroy();author.destroy()
})
