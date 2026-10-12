// Current records emitted by two maintained managers; historical fixture remains untouched.
import {readFileSync, writeFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {createHash} from 'node:crypto';
import * as Y from 'yjs';
const output=process.argv[2]; if(!output) throw Error('Provide explicit output path');
const bundle=readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js',import.meta.url),'utf8');
const id=n=>`91000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const doc=new Y.Doc({gc:false}),p=new Y.XmlElement('paragraph'),text=new Y.XmlText();
p.insert(0,[text]);doc.getXmlFragment('default').insert(0,[p]);text.insert(0,'Hello');
const baseline=[...Y.encodeStateAsUpdate(doc)],binding={document_id:id(99),incarnation:'concurrent-inverses'};
function owner(){
 const context={crypto:globalThis.crypto,TextEncoder,TextDecoder,setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{}};
 runInNewContext(bundle,context);
 const call=(command,input=null)=>JSON.parse(context.relayCollaborationCall(command,JSON.stringify(input)));
 call('apply',baseline);const scope_token='current-concurrent-fixture';let replay=call('createAttributionReplay',{scope_token,binding});
 const basis=()=>({replay_json:replay.replay_json,expected:{scope_token,binding,replay_sha256:replay.replay_sha256,cut:replay.cut}});
 return {format(value,n){replay=call('nativeFormattingWithAttribution',{...basis(),operation:{kind:'formatText',path:[0,0],index:0,length:5,attributes:{bold:value},operation_id:id(n)}});return JSON.parse(replay.record_json)},
 receive(record){replay=call('applyAttributionRecord',{...basis(),record_json:JSON.stringify(record)})},
 undo(n){replay=call('undoWithAttributedEvidence',{...basis(),operation_id:id(n),allow_no_effect:true});return JSON.parse(replay.record_json)}};
}
const a=owner(),b=owner(),add=a.format({},1);b.receive(add);const clear=b.format(null,2);a.receive(clear);
const aUndo=a.undo(3),bUndo=b.undo(4);
if(aUndo.kind!=='format_noop'||bUndo.kind!=='format')throw Error('Unexpected concurrent fixture operations');
writeFileSync(output,JSON.stringify({bundle_sha256:createHash('sha256').update(bundle).digest('hex'),binding,baseline,records:{add,clear,aUndo,bUndo}},null,2)+'\n');doc.destroy();
