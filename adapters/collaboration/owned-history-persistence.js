/** Actual maintained browser manager archive. This is local scoped persistence,
 * never server receipt/attribution authority or a second command engine. */
import * as Y from 'yjs';
import {digest} from 'lib0/hash/sha256';
import {captureMaintainedHistoryCheckpoint,installMaintainedHistoryCheckpoint} from './content-edit-mutation.js';
import {readOwnedHistoryOwner,bindOwnedHistoryOwner} from './owned-command-group.js';
import {protectOwnedHistoryBranches} from './owned-history-branches.js';
const hash=bytes=>Array.from(digest(bytes),v=>v.toString(16).padStart(2,'0')).join('');
const encode=bytes=>{let text='';for(let i=0;i<bytes.length;i+=4096)text+=String.fromCharCode(...bytes.subarray(i,i+4096));return btoa(text);};
const decode=text=>{if(typeof text!=='string'||text.length>32*1024*1024)throw TypeError('Invalid owned snapshot');const bytes=Uint8Array.from(atob(text),v=>v.charCodeAt(0));if(encode(bytes)!==text)throw TypeError('Noncanonical owned snapshot');return bytes;};
function scope(options){if(!options||typeof options.document_id!=='string'||!options.document_id.length||options.document_id.length>512||typeof options.incarnation!=='string'||!options.incarnation.length||options.incarnation.length>512)throw TypeError('Invalid local history scope');return{document_id:options.document_id,incarnation:options.incarnation};}
function fields(value,keys){if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!keys.includes(k))||keys.some(k=>!Object.hasOwn(value,k)))throw TypeError('Invalid local history archive');}
function relative(value,doc){const json=Y.relativePositionToJSON(value);if(Object.keys(json).some(key=>!['type','tname','item','assoc'].includes(key)))throw TypeError('Invalid cursor identity');for(const key of ['type','item'])if(json[key]){const id=json[key];if(!Number.isSafeInteger(id.client)||id.client<0||!Number.isInteger(id.clock)||id.clock<0)throw TypeError('Invalid cursor identity');const item=Y.getItem(doc.store,Y.createID(id.client,id.clock));if(!(item instanceof Y.Item)||id.clock>=item.id.clock+item.length)throw TypeError('Unavailable cursor identity');}if(json.tname!==undefined&&!doc.share.has(json.tname))throw TypeError('Unavailable cursor root');if(!Number.isInteger(json.assoc))throw TypeError('Invalid cursor association');return json;}
function selection(value,doc){if(value===null||value===undefined)return null;const keys=['type','depth','anchor','head','absAnchor','absHead'];if(Object.keys(value).some(k=>!keys.includes(k))||!['text','node','all','cell','nodeRange'].includes(value.type)||!['absAnchor','absHead'].every(k=>Number.isInteger(value[k])&&value[k]>=0&&value[k]<=0x7fffffff)||value.depth!==undefined&&(!Number.isInteger(value.depth)||value.depth<0||value.depth>128))throw TypeError('Invalid maintained cursor metadata');return{type:value.type,anchor:relative(value.anchor,doc),head:relative(value.head,doc),absAnchor:value.absAnchor,absHead:value.absHead,...(value.depth===undefined?{}:{depth:value.depth})};}
function cursor(value,doc){if(value===null)return null;for(const pos of [value.anchor,value.head])if(!pos||Object.keys(pos).some(key=>!['type','tname','item','assoc'].includes(key)))throw TypeError('Invalid cursor identity');const decoded={...value,anchor:Y.createRelativePositionFromJSON(value.anchor),head:Y.createRelativePositionFromJSON(value.head)};selection(decoded,doc);return decoded;}
export function exportOwnedHistoryState(doc,manager,options){
 const qualified=scope(options),ownerID=readOwnedHistoryOwner(manager);
 if(manager.doc!==doc||doc.gc||doc.store.pendingStructs||doc.store.pendingDs||typeof manager.exportHistoryStacks!=='function')throw TypeError('Unavailable settled local history owner');
 const stacks=manager.exportHistoryStacks(),selections={undo:[],redo:[]};
 for(const name of ['undo','redo'])for(const item of stacks[name]){const known=options.selectionKey!==undefined&&item.meta.has(options.selectionKey);selections[name].push(known?selection(item.meta.get(options.selectionKey),doc):null);if(known)item.meta.delete(options.selectionKey);}
 const checkpoint=captureMaintainedHistoryCheckpoint(doc,manager,ownerID,stacks);
 const result={scope:qualified,state_sha256:hash(Y.encodeStateAsUpdate(doc)),snapshot_base64:encode(Y.encodeSnapshot(Y.snapshot(doc))),checkpoint,selections};
 if(JSON.stringify(result).length>32*1024*1024)throw TypeError('Oversized local history archive');return result;
}
export function restoreOwnedHistoryState(doc,manager,archive,options){
 fields(archive,['scope','state_sha256','snapshot_base64','checkpoint','selections']);fields(archive.scope,['document_id','incarnation']);fields(archive.selections,['undo','redo']);
 if(JSON.stringify(scope(options))!==JSON.stringify(archive.scope)||JSON.stringify(archive).length>32*1024*1024||manager.doc!==doc||doc.gc||manager.undoStack.length||manager.redoStack.length)throw TypeError('Conflicting local history archive');
 const ownerID=readOwnedHistoryOwner(manager);if(archive.checkpoint.owner_id!==ownerID)throw TypeError('Conflicting local history owner');
 const snapshot=Y.decodeSnapshot(decode(archive.snapshot_base64)),cut=Y.createDocFromSnapshot(doc,snapshot,new Y.Doc({gc:false}));
 // Community decode can merge adjacent deleted Items that the original
 // manager kept split for redone/retained boundaries. Restore that exact
 // checkpoint on the detached cut before checking the original byte hash.
 const cutManager=new Y.UndoManager([cut.getXmlFragment('default'),cut.getMap('relaymark')]);
 try{bindOwnedHistoryOwner(cutManager,ownerID);installMaintainedHistoryCheckpoint(cut,cutManager,archive.checkpoint,ownerID);if(hash(Y.encodeStateAsUpdate(cut))!==archive.state_sha256)throw TypeError('Local history retained state mismatch');}finally{cutManager.destroy();cut.destroy();}
 const selections={};for(const[name,wire]of [['undo',archive.checkpoint.undo_stack],['redo',archive.checkpoint.redo_stack]]){if(!Array.isArray(archive.selections[name])||archive.selections[name].length!==wire.length)throw TypeError('Local cursor stack mismatch');selections[name]=archive.selections[name].map(value=>cursor(value,doc));if(options.selectionKey===undefined&&selections[name].some(value=>value!==null))throw TypeError('Cursor binding is required');}
 // Admission failure must never partly install stacks/redone sidecars on the
 // live owner. Verify with a detached retained owner, then install exact data.
 const scratch=new Y.Doc({gc:false});Y.applyUpdate(scratch,Y.encodeStateAsUpdate(doc));const check=new Y.UndoManager([scratch.getXmlFragment('default'),scratch.getMap('relaymark')]);bindOwnedHistoryOwner(check,ownerID);
 try{installMaintainedHistoryCheckpoint(scratch,check,archive.checkpoint,ownerID);}finally{check.destroy();scratch.destroy();}
 protectOwnedHistoryBranches(manager);installMaintainedHistoryCheckpoint(doc,manager,archive.checkpoint,ownerID);
 for(const name of ['undo','redo'])manager[name+'Stack'].forEach((item,index)=>{if(options.selectionKey!==undefined)item.meta.set(options.selectionKey,selections[name][index]);});
 return{owner_id:ownerID,undo_count:manager.undoStack.length,redo_count:manager.redoStack.length};
}
