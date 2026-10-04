// bun scripts/collaboration-list-v3-operations-probe.mjs /absolute/web/assets --write|--check
// Browser fixture for interior Return and empty-item exit, plus an indent/outdent probe.
import { createRequire } from 'node:module';
import { mkdtemp, rm, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import assert from 'node:assert/strict';
import { proseMirrorToRelayMark } from '../src/document-adapter.js';

const [assetsInput, mode] = process.argv.slice(2);
if (!assetsInput || !['--write', '--check'].includes(mode)) throw new Error('assets path and --write|--check required');
const assets = resolve(assetsInput);
const require = createRequire(join(assets, 'package.json'));
const { chromium } = await import(require.resolve('playwright'));
const temp = await mkdtemp(join(tmpdir(), 'relay-list-ops-v3-'));
const mod = name => JSON.stringify(join(assets, 'node_modules', name));
let browser, server;
try {
  const entry = join(temp, 'entry.js');
  await writeFile(entry, `import {Editor} from ${mod('@tiptap/core/dist/index.js')};
import Collaboration from ${mod('@tiptap/extension-collaboration/dist/index.js')};
import {prosemirrorToYXmlFragment} from ${mod('@tiptap/y-tiptap/dist/y-tiptap.js')};
import * as Y from ${mod('yjs/dist/yjs.mjs')};
import {getCoreExtensions} from ${JSON.stringify(join(assets, 'js/editors/extensions/core.js'))};
const b=n=>'b0000000000004000800000000000'+n.toString(16).padStart(4,'0');
const p=(n,t)=>({type:'paragraph',attrs:{relaymarkId:b(n)},...(t?{content:[{type:'text',text:t,...([5,16].includes(n)?{marks:[{type:'bold'}]}:{})}]}:{})});
const item=(n,paragraph,nested)=>({type:'listItem',attrs:{relaymarkId:b(n)},content:[paragraph,...(nested?[nested]:[])]});
const list=(kind,n,start,items)=>({type:kind,attrs:kind==='orderedList'?{relaymarkId:b(n),start,type:null}:{relaymarkId:b(n)},content:items});
const flat=(kind,empty=false)=>({type:'doc',content:[list(kind,1,7,[item(2,p(3,'First')),item(4,p(5,empty?'':'Second 🌍'))])]});
const nested=(kind,empty=false)=>({type:'doc',content:[list('bulletList',11,1,[item(12,p(13,'Outer'),list(kind,14,3,[item(15,p(16,empty?'':'Nested 🌍'))])),item(17,p(18,'Sibling'))])]});
const scenarios=[
 {name:'interior_flat_ordered',raw:flat('orderedList'),command:'splitListItem',target:'Second 🌍',offset:3},
 {name:'interior_nested_ordered',raw:nested('orderedList'),command:'splitListItem',target:'Nested 🌍',offset:3},
 {name:'exit_flat_ordered',raw:flat('orderedList',true),command:'keyboardShortcut',empty:true},
 {name:'exit_flat_bullet',raw:flat('bulletList',true),command:'keyboardShortcut',empty:true},
 {name:'exit_nested_ordered',raw:nested('orderedList',true),command:'keyboardShortcut',empty:true},
 {name:'exit_nested_bullet',raw:nested('bulletList',true),command:'keyboardShortcut',empty:true},
 {name:'indent_flat_ordered',raw:flat('orderedList'),command:'sinkListItem',target:'Second 🌍',offset:3},
 {name:'indent_flat_bullet',raw:flat('bulletList'),command:'sinkListItem',target:'Second 🌍',offset:3},
 {name:'outdent_nested_ordered',raw:nested('orderedList'),command:'liftListItem',target:'Nested 🌍',offset:3},
 {name:'outdent_nested_bullet',raw:nested('bulletList'),command:'liftListItem',target:'Nested 🌍',offset:3},
];
const snapshot=node=>node instanceof Y.XmlText?{kind:'text',delta:node.toDelta()}:{kind:node instanceof Y.XmlElement?'element':'fragment',...(node instanceof Y.XmlElement?{name:node.nodeName,attributes:node.getAttributes()}:{}),children:node.toArray().map(snapshot)};
const at=(root,path)=>path.reduce((node,index)=>node.toArray()[index],root);
const pathOf=(target,node,path=[])=>node===target?path:node instanceof Y.XmlText?null:node.toArray().reduce((found,child,index)=>found??pathOf(target,child,[...path,index]),null);
const out={};
for(const scenario of scenarios){
 let next=100;
 const extensions=getCoreExtensions({collaborative:true,collaborationSchema:'relaymark-prosemirror-v3',hostCapabilities:[]}).map(e=>e.name==='uniqueID'?e.configure({generateID:()=>b(++next)}):e);
 const initial=new Editor({element:document.createElement('div'),extensions,content:scenario.raw});
 const normalized=initial.getJSON();
 const doc=new Y.Doc();doc.clientID=91600+Object.keys(out).length;
 prosemirrorToYXmlFragment(initial.state.doc,doc.getXmlFragment('default'));initial.destroy();
 const root=doc.getXmlFragment('default');const before=snapshot(root),vector=Y.encodeStateVector(doc);
 const seed=btoa(String.fromCharCode(...Y.encodeStateAsUpdate(doc)));
 const leafPath=scenario.raw.content[0].content[0].content.length===2?[0,0,1,0,0,0]:[0,1,0,0];
 const leaf=at(root,leafPath);
 const anchors=leaf?[0,Math.min(3,leaf.length),leaf.length].map(index=>Y.encodeRelativePosition(Y.createRelativePositionFromTypeIndex(leaf,index,0))):[];
 const editor=new Editor({element:document.createElement('div'),extensions:[...extensions,Collaboration.configure({document:doc,field:'default'})]});
 let position;
 editor.state.doc.descendants((node,pos)=>{if(scenario.empty&&node.type.name==='paragraph'&&node.content.size===0)position=pos+1;if(!scenario.empty&&node.isText&&node.text===scenario.target)position=pos+scenario.offset});
 if(position===undefined)throw Error('Missing target '+scenario.name);
 editor.commands.setTextSelection(position);
 const accepted=editor.commands[scenario.command](scenario.command==='keyboardShortcut'?'Enter':'listItem');
 const after=snapshot(root);
 const resolved=anchors.map(bytes=>{const p=Y.createAbsolutePositionFromRelativePosition(Y.decodeRelativePosition(bytes),doc);return p?{path:pathOf(p.type,root),index:p.index}:null});
 const update=btoa(String.fromCharCode(...Y.encodeStateAsUpdate(doc,vector)));
 out[scenario.name]={accepted,normalized,before,after,prosemirror:editor.getJSON(),resolved,seed,update};
 editor.destroy();doc.destroy();
}
window.fixture=out;`);
  const build = await Bun.build({ entrypoints: [entry], target: 'browser' });
  assert.ok(build.success, JSON.stringify(build.logs));
  const js = await build.outputs[0].text();
  server = Bun.serve({ hostname: '127.0.0.1', port: 0, fetch: request => {
    const script = new URL(request.url).pathname === '/probe.js';
    return new Response(script ? js : '<script type="module" src="/probe.js"></script>',
      { headers: { 'content-type': script ? 'text/javascript' : 'text/html' } });
  } });
  browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  page.on('pageerror', error => console.error(error.message));
  await page.goto(server.url.href);
  await page.waitForFunction(() => window.fixture);
  const cases = await page.evaluate(() => window.fixture);
  const fixture = {};
  for (const [name, value] of Object.entries(cases)) {
    const summary = value.prosemirror.content.map(node => ({ type: node.type, id: node.attrs?.relaymarkId,
      content: node.content?.map(item => ({ type: item.type, id: item.attrs?.relaymarkId,
        content: item.content?.map(child => ({ type: child.type, id: child.attrs?.relaymarkId,
          content: child.content?.map(inner => ({ type: inner.type, id: inner.attrs?.relaymarkId })) })) })) }));
    console.log(JSON.stringify({ name, accepted: value.accepted, summary, anchors: value.resolved,
      updateLength: Buffer.from(value.update, 'base64').length }));
    if (!name.startsWith('indent_') && !name.startsWith('outdent_')) {
      fixture[name] = { source: 'Relay v3 TipTap/UniqueID Enter + community y-tiptap/Yjs',
        accepted: value.accepted, normalized: value.normalized, after: value.prosemirror,
        before_xml: value.before, after_xml: value.after, seed: value.seed, update: value.update,
        expected_ast: proseMirrorToRelayMark(value.prosemirror), anchors: value.resolved };
    }
  }
  const path = new URL('../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/list-operations-v3.json', import.meta.url);
  const output = `${JSON.stringify(fixture, null, 2)}\n`;
  if (mode === '--write') await writeFile(path, output);
  else assert.equal(await readFile(path, 'utf8'), output);
} finally { await browser?.close(); server?.stop(true); await rm(temp, { recursive: true, force: true }); }
