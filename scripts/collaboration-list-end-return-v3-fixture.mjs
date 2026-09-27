// bun scripts/collaboration-list-end-return-v3-fixture.mjs /absolute/web/assets --write|--check
// Executes TipTap's list split against the Relay v3 schema in Chromium/Yjs.
import { createRequire } from 'node:module';
import { mkdtemp, rm, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import assert from 'node:assert/strict';
import { proseMirrorV3ToRelayMark } from '../src/collaboration-table-v3.js';

const [assetsInput, mode] = process.argv.slice(2);
if (!assetsInput || !['--write', '--check'].includes(mode)) throw new Error('assets path and --write|--check required');
const assets = resolve(assetsInput);
const require = createRequire(join(assets, 'package.json'));
const { chromium } = await import(require.resolve('playwright'));
const temp = await mkdtemp(join(tmpdir(), 'relay-list-v3-'));
const mod = name => JSON.stringify(join(assets, 'node_modules', name));
let browser, server;
try {
  const entry = join(temp, 'entry.js');
  await writeFile(entry, `import {Editor} from ${mod('@tiptap/core/dist/index.js')};
import Collaboration from ${mod('@tiptap/extension-collaboration/dist/index.js')};
import {prosemirrorToYXmlFragment,yDocToProsemirrorJSON} from ${mod('@tiptap/y-tiptap/dist/y-tiptap.js')};
import * as Y from ${mod('yjs/dist/yjs.mjs')};
import {getCoreExtensions} from ${JSON.stringify(join(assets, 'js/editors/extensions/core.js'))};
const b=n=>'b0000000000004000800000000000'+n.toString(16).padStart(4,'0');
const p=(n,t)=>({type:'paragraph',attrs:{relaymarkId:b(n)},content:[{type:'text',text:t}]});
const item=(n,paragraph,nested)=>({type:'listItem',attrs:{relaymarkId:b(n)},content:[paragraph,...(nested?[nested]:[])]});
const scenarios=[
 {name:'flat_ordered',clientID:91516,raw:{type:'doc',content:[{type:'orderedList',attrs:{relaymarkId:b(1),start:7,type:null},content:[item(2,p(3,'Numbered Ω'))]}]},target:'Numbered Ω'},
 {name:'nested_ordered',clientID:91517,raw:{type:'doc',content:[{type:'bulletList',attrs:{relaymarkId:b(11)},content:[item(12,p(13,'Outer'),{type:'orderedList',attrs:{relaymarkId:b(14),start:3,type:null},content:[item(15,p(16,'Nested 🌍'))]}),item(17,p(18,'Sibling'))]}]},target:'Nested 🌍'},
];
const out={};
for(const scenario of scenarios){
 let next=100;
 const extensions=getCoreExtensions({collaborative:true,collaborationSchema:'relaymark-prosemirror-v3',hostCapabilities:[]}).map(e=>e.name==='uniqueID'?e.configure({generateID:()=>b(++next)}):e);
 const initial=new Editor({element:document.createElement('div'),extensions,content:scenario.raw});
 const normalized=initial.getJSON();
 const doc=new Y.Doc();doc.clientID=scenario.clientID;
 prosemirrorToYXmlFragment(initial.state.doc,doc.getXmlFragment('default'));initial.destroy();
 const seed=btoa(String.fromCharCode(...Y.encodeStateAsUpdate(doc)));
 const vector=Y.encodeStateVector(doc);
 const editor=new Editor({element:document.createElement('div'),extensions:[...extensions,Collaboration.configure({document:doc,field:'default'})]});
 let start;editor.state.doc.descendants((node,pos)=>{if(node.isText&&node.text===scenario.target)start=pos});
 if(start===undefined)throw Error('Missing target '+scenario.name);
 editor.commands.setTextSelection(start+scenario.target.length);
 if(!editor.commands.splitListItem('listItem'))throw Error('Split rejected '+scenario.name);
 const after=editor.getJSON();
 const update=btoa(String.fromCharCode(...Y.encodeStateAsUpdate(doc,vector)));
 const replay=new Y.Doc();Y.applyUpdate(replay,Uint8Array.from(atob(seed),c=>c.charCodeAt(0)));Y.applyUpdate(replay,Uint8Array.from(atob(update),c=>c.charCodeAt(0)));
 if(JSON.stringify(editor.schema.nodeFromJSON(yDocToProsemirrorJSON(replay,'default')).toJSON())!==JSON.stringify(after))throw Error('Yjs replay mismatch '+scenario.name);
 out[scenario.name]={source:'Relay v3 TipTap splitListItem + UniqueID + community y-tiptap/Yjs',normalized,after,seed,update};
 editor.destroy();doc.destroy();replay.destroy();
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
  for (const value of Object.values(cases)) value.expected_ast = proseMirrorV3ToRelayMark(value.after);
  const path = new URL('../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/list-end-return-v3.json', import.meta.url);
  const output = `${JSON.stringify(cases, null, 2)}\n`;
  if (mode === '--write') await writeFile(path, output);
  else assert.equal(await readFile(path, 'utf8'), output);
  console.log(`Community v3 list Return fixture ${mode === '--write' ? 'written' : 'matches'}`);
} finally {
  await browser?.close(); server?.stop(true); await rm(temp, { recursive: true, force: true });
}
