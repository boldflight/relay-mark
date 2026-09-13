import {readFileSync,writeFileSync} from 'node:fs'
import {runInNewContext} from 'node:vm'
import * as Y from 'yjs'
import {captureTextItems} from '../adapters/collaboration/text-items.js'
import {captureHistoryFormatEvent} from '../adapters/collaboration/history-lineage.js'
import {placementUpdateHash} from '../adapters/collaboration/placement-lineage.js'
import {formatAttributionCut} from '../adapters/collaboration/format-attribution-cut.js'
import {replayFormatAttribution} from '../adapters/collaboration/format-attribution-replay.js'
const output=process.argv[2]
if(!output)throw Error('Provide the explicit fixture output path')
const id=n=>`71000000-0000-4000-8000-${String(n).padStart(12,'0')}`
const source=readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js',import.meta.url),'utf8')
const doc=new Y.Doc({gc:false}),p=new Y.XmlElement('paragraph'),t=new Y.XmlText()
p.insert(0,[t]);doc.getXmlFragment('default').insert(0,[p]);t.insert(0,'Hello')
const baseline=[...Y.encodeStateAsUpdate(doc)],binding={document_id:id(90),incarnation:'native-fixture'},scope_token='qualified-native-owner',steps=[]
function client(){const context={crypto:globalThis.crypto,TextEncoder,TextDecoder,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}};runInNewContext(source,context)
 const call=(command,input=null)=>JSON.parse(context.relayCollaborationCall(command,JSON.stringify(input)));call('apply',baseline);return call}
const a=client(),b=client(),plain=a('snapshot')
function structural(command,input,kind,reference){
 const result=a(command,input),update=Y.mergeUpdates(result.updates.map(u=>Uint8Array.from(u)))
 steps.push({kind:'placement',update:[...update],trust:'local',receipt:{version:1,...binding,operation_id:input.operation_id,
  update_sha256:placementUpdateHash(update),operation:{kind,reference},copies:result.lineage.copies}})
 Y.applyUpdate(doc,update);b('apply',[...update])
}
structural('replaceProseWithLineage',{start:2,end:2,text:'\n',operation_id:id(1)},'replace_prose',null)
const ranges=[{path:[0,0],index:0,length:2},{path:[1,0],index:0,length:3}]
const selected={version:1,runs:ranges.flatMap(r=>captureTextItems(doc.getXmlFragment('default'),r).runs)}
const update=Y.mergeUpdates(b('nativeFormatting',{kind:'formatText',ranges,attributes:{bold:{}},operation_id:id(2)}).map(u=>Uint8Array.from(u)))
steps.push({kind:'format',update:[...update],event:captureHistoryFormatEvent(doc,update,{operation_id:id(2),mark:'bold',text_items:selected}),operation:null})
Y.applyUpdate(doc,update);a('apply',[...update])
structural('undoWithEvidence',{operation_id:id(3)},'undo',id(1))
const replay_json=JSON.stringify({version:1,scope_token,binding,baseline,steps})
const expected={scope_token,binding,replay_sha256:placementUpdateHash(new TextEncoder().encode(replay_json)),cut:formatAttributionCut(doc)}
replayFormatAttribution(replay_json,expected)
const fixture={version:1,replay_json,expected,owner_snapshot:b('exportHistorySnapshot',{scope_token}),transaction_ids:[id(2)],
 reference_id:id(2),undo_id:id(4),redo_id:id(5),plain_snapshot:plain,bold_snapshot:b('snapshot')}
// Verify the recorded live owner before saving the independent Swift fixture.
const inverse=b('undoWithAttributedEvidence',{operation_id:id(4),reference_id:id(2),replay_json,expected})
if(JSON.stringify(b('snapshot'))!==JSON.stringify(plain))throw Error('Fixture does not undo to plain text')
replayFormatAttribution(inverse.replay_json,{...expected,replay_sha256:inverse.replay_sha256,cut:inverse.cut})
writeFileSync(output,JSON.stringify(fixture,null,2)+'\n');doc.destroy()
