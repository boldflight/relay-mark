// Re-emit current operations independently through Yjs XML. Never rewrite the
// retained historical binaries or use the producer under test as the oracle.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import * as Y from 'yjs';
import {currentOperationSeed} from './current-operation-seed.js';
import {captureContentEditFootprint} from '../../adapters/collaboration/content-edit-observer.js';
const directory=new URL('../../spec/relaymark/collaboration/fixtures/',import.meta.url);
const enc=bytes=>Buffer.from(bytes).toString('base64');
if(process.env.RELAYMARK_WRITE_CURRENT_MUTATIONS) for(const name of ['typing','mark','widget','delete','redundant','transient-format','transient-metadata']) {
 const old=JSON.parse(fs.readFileSync(new URL(`content-edit-${name}-mutation.json`,directory)));
 const state=currentOperationSeed(old.sender_state_base64),doc=new Y.Doc({gc:false});
 Y.applyUpdate(doc,Buffer.from(state,'base64'));doc.clientID=old.writer_client;
 const root=doc.getXmlFragment('default'),text=root.get(0).get(0),updates=[];
 doc.on('update',update=>updates.push(update));
 doc.transact(()=>{
  if(name==='mark')text.format(0,1,{bold:{}});
  else if(name==='widget')root.get(1).setAttribute('required',true);
  else if(name==='delete')text.delete(0,1);
  else text.insert(name==='redundant'?2:1,'X');
  if(name==='transient-format'){text.format(0,1,{bold:{}});text.format(0,1,{bold:null});}
  if(name==='transient-metadata'){doc.getMap('relaymark').set('meta',{hidden:'discarded'});doc.getMap('relaymark').delete('meta');}
 });
 assert.equal(updates.length,1);
 if(name==='typing')assert.equal(text.toString(),'AX🌍Z');
 if(name==='delete')assert.equal(text.toString(),'🌍Z');
 if(name==='widget')assert.equal(root.get(1).getAttribute('required'),true);
 const update=name==='redundant'?Y.encodeStateAsUpdate(doc):updates[0];
 const current={...old,description:'Current canonical physical seed; independently emitted Yjs XML '+name+' command',
  sender_state_base64:state,current_state_base64:state,footprint:captureContentEditFootprint(doc,update)};
 fs.writeFileSync(new URL(`current-content-edit-${name}-mutation.json`,directory),JSON.stringify(current,null,2)+'\n');
 doc.destroy();
}
