// bun scripts/collaboration-structured-fixtures.mjs /absolute/path/to/web/assets
// Actual Chromium editor + community schema/Yjs, with Relay's existing Heading extension.
import {createRequire} from 'node:module';
import {mkdtemp,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import assert from 'node:assert/strict';
const assets=resolve(process.argv[2]);
const require=createRequire(join(assets,'package.json'));
const {chromium}=await import(require.resolve('playwright'));
const temp=await mkdtemp(join(tmpdir(),'relay-structured-fixture-'));
const mod=name=>JSON.stringify(join(assets,'node_modules',name));
let browser,server;
try {
  const entry=join(temp,'entry.js');
  await writeFile(entry, `import {Editor} from ${mod('@tiptap/core/dist/index.js')};
import StarterKit from ${mod('@tiptap/starter-kit/dist/index.js')};
import {prosemirrorJSONToYDoc} from ${mod('@tiptap/y-tiptap/dist/y-tiptap.js')};
import * as Y from ${mod('yjs/dist/yjs.mjs')};
import {PaperHeading} from ${JSON.stringify(join(assets,'js/editors/extensions/paper-heading.js'))};
const paragraph=text=>({type:'paragraph',content:[{type:'text',text}]});
const list=(type,start,content)=>({type,...(start?{attrs:{start}}:{}),content});
const item=(text,nested)=>({type:'listItem',content:[paragraph(text),...(nested?[nested]:[])]});
const docs=[{name:'headings',content:[1,2,3,4,5,6].map(level=>({type:'heading',attrs:{level,headingId:'stable-'+level},content:[{type:'text',text:'Heading '+level+' 🌍'}]}))},
{name:'bullet-ordered',content:[list('bulletList',null,[item('Outer',list('orderedList',3,[item('Nested 🌍 text')])),item('Sibling')])]},
{name:'ordered-bullet',content:[list('orderedList',7,[item('Outer',list('bulletList',null,[item('Nested 🌍 text')])),item('Sibling')])]}];
const snapshot=node=>node instanceof Y.XmlText?{kind:'text',delta:node.toDelta()}:{kind:node instanceof Y.XmlElement?'element':'fragment',...(node instanceof Y.XmlElement?{name:node.nodeName,attributes:node.getAttributes()}:{}),children:node.toArray().map(snapshot)};
window.fixture={source:'Chromium TipTap3.30.2 Editor, Relay PaperHeading, y-tiptap3.0.9, Yjs13.6.32',cases:docs.map(({name,content})=>{
 const editor=new Editor({element:document.createElement('div'),extensions:[StarterKit.configure({heading:false}),PaperHeading],content:{type:'doc',content}});
 const json=editor.getJSON();const doc=prosemirrorJSONToYDoc(editor.schema,json,'default');
 const result={name,prosemirror:json,snapshot:snapshot(doc.getXmlFragment('default')),update:btoa(String.fromCharCode(...Y.encodeStateAsUpdate(doc)))};editor.destroy();return result;
})};`);
  const build=await Bun.build({entrypoints:[entry],target:'browser'});assert.ok(build.success,JSON.stringify(build.logs));
  const js=await build.outputs[0].text();
  server=Bun.serve({hostname:'127.0.0.1',port:0,fetch:r=>new Response(new URL(r.url).pathname==='/probe.js'?js:'<script type="module" src="/probe.js"></script>',{headers:{'content-type':new URL(r.url).pathname==='/probe.js'?'text/javascript':'text/html'}})});
  browser=await chromium.launch({headless:true});const page=await browser.newPage();
  page.on('pageerror',error=>console.error(error.message));await page.goto(server.url.href);await page.waitForFunction(()=>window.fixture);
  const fixture=await page.evaluate(()=>window.fixture);
  await writeFile(new URL('../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/structured-v1.json',import.meta.url),JSON.stringify(fixture,null,2)+'\n');
  console.log('Actual Chromium heading/nested-list fixtures: 3 generated');
} finally {await browser?.close();server?.stop(true);await rm(temp,{recursive:true,force:true})}
