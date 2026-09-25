// bun scripts/collaboration-code-block-probe.mjs /absolute/path/to/web/assets
// Community existing code-block typing fixture; no live server or app state.
import {createRequire} from 'node:module';
import {mkdtemp,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import assert from 'node:assert/strict';
const assets=resolve(process.argv[2]);
const require=createRequire(join(assets,'package.json'));
const {chromium}=await import(require.resolve('playwright'));
const temp=await mkdtemp(join(tmpdir(),'relay-code-block-'));
const mod=name=>JSON.stringify(join(assets,'node_modules',name));
let browser,server;
try {
 const entry=join(temp,'entry.js');
 await writeFile(entry, `import {Editor} from ${mod('@tiptap/core/dist/index.js')};
import StarterKit from ${mod('@tiptap/starter-kit/dist/index.js')};
import Collaboration from ${mod('@tiptap/extension-collaboration/dist/index.js')};
import {prosemirrorJSONToYDoc} from ${mod('@tiptap/y-tiptap/dist/y-tiptap.js')};
import * as Y from ${mod('yjs/dist/yjs.mjs')};
const initial='let 🌍 = "'+String.fromCharCode(96).repeat(3)+'"\\nprint(🌍)\\n// tail';
const inserted='\\n// browser Ω';
const content={type:'doc',content:[{type:'codeBlock',attrs:{language:'swift'},content:[{type:'text',text:initial}]}]};
const seedEditor=new Editor({element:document.createElement('div'),extensions:[StarterKit.configure({trailingNode:false})],content});
const doc=prosemirrorJSONToYDoc(seedEditor.schema,seedEditor.getJSON(),'default');seedEditor.destroy();
const root=doc.getXmlFragment('default');
const at=path=>path.reduce((node,index)=>node.toArray()[index],root);
const pathOf=(target,node=root,path=[])=>node===target?path:node instanceof Y.XmlText?null:node.toArray().reduce((found,child,index)=>found??pathOf(target,child,[...path,index]),null);
const encode=bytes=>btoa(String.fromCharCode(...bytes));
const snapshot=node=>node instanceof Y.XmlText?{kind:'text',delta:node.toDelta()}:{kind:node instanceof Y.XmlElement?'element':'fragment',...(node instanceof Y.XmlElement?{name:node.nodeName,attributes:node.getAttributes()}:{}),children:node.toArray().map(snapshot)};
const specs=[{name:'prefix',path:[0,0],index:1},{name:'unicodeSuffix',path:[0,0],index:12}];
const anchors=specs.map(spec=>({...spec,anchor:encode(Y.encodeRelativePosition(Y.createRelativePositionFromTypeIndex(at(spec.path),spec.index,0)))}));
const seed=encode(Y.encodeStateAsUpdate(doc)),vector=Y.encodeStateVector(doc),before=snapshot(root);
const editor=new Editor({element:document.createElement('div'),extensions:[StarterKit.configure({undoRedo:false,trailingNode:false}),Collaboration.configure({document:doc,field:'default'})]});
let start;editor.state.doc.descendants((node,pos)=>{if(node.isText)start=pos});
if(start===undefined)throw Error('Missing code text');
editor.view.dispatch(editor.state.tr.insertText(inserted,start+initial.length));
const resolved=anchors.map(spec=>{const position=Y.createAbsolutePositionFromRelativePosition(Y.decodeRelativePosition(Uint8Array.from(atob(spec.anchor),c=>c.charCodeAt(0))),doc);return {...spec,resolved:position?{path:pathOf(position.type),index:position.index}:null}});
window.fixture={initial,inserted,index:initial.length,source:'Chromium TipTap3.30.2 + Collaboration, y-tiptap3.0.9, Yjs13.6.32',seed,update:encode(Y.encodeStateAsUpdate(doc,vector)),before,after:snapshot(root),anchors:resolved,prosemirror:editor.getJSON()};
editor.destroy();`);
 const build=await Bun.build({entrypoints:[entry],target:'browser'});assert.ok(build.success,JSON.stringify(build.logs));
 const js=await build.outputs[0].text();
 server=Bun.serve({hostname:'127.0.0.1',port:0,fetch:r=>new Response(new URL(r.url).pathname==='/probe.js'?js:'<script type="module" src="/probe.js"></script>',{headers:{'content-type':new URL(r.url).pathname==='/probe.js'?'text/javascript':'text/html'}})});
 browser=await chromium.launch({headless:true});const page=await browser.newPage();
 page.on('pageerror',e=>console.error(e.message));await page.goto(server.url.href);await page.waitForFunction(()=>window.fixture);
 const fixture=await page.evaluate(()=>window.fixture);
 await writeFile(new URL('../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/code-block-v1.json',import.meta.url),JSON.stringify(fixture,null,2)+'\n');
 console.log(JSON.stringify(fixture.anchors.map(({name,path,index,resolved})=>({name,before:{path,index},after:resolved})),null,2));
} finally {await browser?.close();server?.stop(true);await rm(temp,{recursive:true,force:true})}
