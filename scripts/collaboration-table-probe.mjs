// Experimental community-schema evidence, not a Relay authored-v1 extension.
// node scripts/collaboration-table-probe.mjs /absolute/path/to/web/assets [native-output.json]
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
if (!process.argv[2]) throw new Error('Provide the web assets directory containing the inspected community packages');
const versions = {'@tiptap/core':'3.30.2','@tiptap/extension-table':'3.30.2','@tiptap/y-tiptap':'3.0.9','yjs':'13.6.32','tiptap-markdown':'0.9.0','jsdom':'26.1.0'};
for (const [name, version] of Object.entries(versions)) {
  const installed=JSON.parse(readFileSync(resolve(process.argv[2], 'node_modules', name, 'package.json')));
  assert.equal(installed.version, version, `Re-review table probe semantics before changing ${name} version`);
}
const require = createRequire(resolve(process.argv[2], 'package.json'));
const load = name => import(pathToFileURL(require.resolve(name)).href);
const [{getSchema}, {StarterKit}, {TableKit}, binding, Y] = await Promise.all([
  load('@tiptap/core'), load('@tiptap/starter-kit'), load('@tiptap/extension-table'), load('@tiptap/y-tiptap'), load('yjs')]);
const schema = getSchema([StarterKit, TableKit]);
const normalize = value => JSON.parse(JSON.stringify(schema.nodeFromJSON(value).toJSON()));
const paragraph = text => ({type:'paragraph',content:[{type:'text',text}]});
const cell = (text, attrs={}, type='tableCell') => ({type,attrs,content:[paragraph(text)]});
const row = (...content) => ({type:'tableRow',content});
const cases = [
  ['rectangle', [row(cell('Name',{},'tableHeader'),cell('Value',{},'tableHeader')),row(cell('Hello 🌍'),cell('二'))]],
  ['colspan', [row(cell('Merged 🌍',{colspan:2,colwidth:[120,180]},'tableHeader')),row(cell('Left'),cell('Right'))]],
  ['rowspan', [row(cell('Tall',{rowspan:2,colwidth:[140]}),cell('Upper')),row(cell('Lower'))]],
];
const snapshot = node => node instanceof Y.XmlText ? {kind:'text',delta:node.toDelta()} :
  {kind:node instanceof Y.XmlElement?'element':'fragment',...(node instanceof Y.XmlElement?{name:node.nodeName,attributes:node.getAttributes()}:{}),children:node.toArray().map(snapshot)};
const fixtures = cases.map(([name,rows]) => {
  const input={type:'doc',content:[{type:'table',content:rows}]};
  // Construct through actual community ProseMirror schema and Yjs converter.
  const canonical=normalize(input);
  const doc=binding.prosemirrorJSONToYDoc(schema,canonical,'default');
  assert.deepEqual(normalize(binding.yDocToProsemirrorJSON(doc,'default')),canonical);
  return {name,prosemirror:canonical,update:Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64'),snapshot:snapshot(doc.getXmlFragment('default'))};
});
// Verify the narrow GFM subset with the installed community serializer, not a Relay table codec.
const esm = name => import(pathToFileURL(resolve(process.argv[2], `node_modules/${name}/dist/index.js`)).href);
const [{Editor}, {StarterKit: ESMStarterKit}, {TableKit: ESMTableKit}, {Markdown}, {JSDOM}] = await Promise.all([
  esm('@tiptap/core'), esm('@tiptap/starter-kit'), esm('@tiptap/extension-table'),
  import(pathToFileURL(resolve(process.argv[2], 'node_modules/tiptap-markdown/dist/tiptap-markdown.es.js')).href), load('jsdom'),
]);
const dom = new JSDOM('<html><body></body></html>');
Object.assign(globalThis, {
  window: dom.window, document: dom.window.document,
  HTMLElement: dom.window.HTMLElement, Node: dom.window.Node,
  MutationObserver: dom.window.MutationObserver,
  getSelection: dom.window.getSelection.bind(dom.window),
});
Object.defineProperty(globalThis, 'navigator', {configurable: true, value: dom.window.navigator});
const rectangle = fixtures.find(item => item.name === 'rectangle');
const editor = new Editor({
  extensions: [ESMStarterKit.configure({trailingNode: false}), ESMTableKit, Markdown],
  content: rectangle.prosemirror,
});
assert.deepEqual(JSON.parse(JSON.stringify(editor.getJSON())), rectangle.prosemirror);
rectangle.markdown = editor.storage.markdown.getMarkdown();
assert.equal(rectangle.markdown, '| Name | Value |\n| --- | --- |\n| Hello 🌍 | 二 |\n');
editor.commands.setContent(rectangle.markdown);
assert.deepEqual(JSON.parse(JSON.stringify(editor.getJSON())), rectangle.prosemirror);
editor.destroy();
const path=new URL('../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/table-experimental.json',import.meta.url);
if (process.argv[3] === '--source-only') {
  const fixture=JSON.parse(readFileSync(path));
  assert.equal(fixture.cases.find(item => item.name === 'rectangle').markdown, rectangle.markdown);
  console.log('Community Markdown serializer preserves unmerged 2x2 table: 1 passed');
} else if (process.argv[3]) {
  const fixture=JSON.parse(readFileSync(path));const native=JSON.parse(readFileSync(process.argv[3]));
  for (const item of fixture.cases) { const doc=new Y.Doc();Y.applyUpdate(doc,Buffer.from(native[item.name],'base64'));assert.deepEqual(normalize(binding.yDocToProsemirrorJSON(doc,'default')),item.prosemirror); }
  console.log('Native Yrs re-encoded tables preserve actual community ProseMirror shape: 3 passed');
} else {
  writeFileSync(path,JSON.stringify({experimental:true,root:'default',source:'TipTap core/table 3.30.2; y-tiptap 3.0.9; Yjs 13.6.32',cases:fixtures},null,2)+'\n');
  console.log('Generated 3 experimental community table fixtures');
}
