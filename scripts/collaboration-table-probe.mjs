// Experimental community-schema evidence, not a Relay authored-v1 extension.
// node scripts/collaboration-table-probe.mjs /absolute/path/to/web/assets [native-output.json]
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
if (!process.argv[2]) throw new Error('Provide the web assets directory containing the inspected community packages');
const versions = {'@tiptap/core':'3.30.2','@tiptap/extension-table':'3.30.2','@tiptap/y-tiptap':'3.0.9','yjs':'13.6.32'};
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
const path=new URL('../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/table-experimental.json',import.meta.url);
if (process.argv[3]) {
  const fixture=JSON.parse(readFileSync(path));const native=JSON.parse(readFileSync(process.argv[3]));
  for (const item of fixture.cases) { const doc=new Y.Doc();Y.applyUpdate(doc,Buffer.from(native[item.name],'base64'));assert.deepEqual(normalize(binding.yDocToProsemirrorJSON(doc,'default')),item.prosemirror); }
  console.log('Native Yrs re-encoded tables preserve actual community ProseMirror shape: 3 passed');
} else {
  writeFileSync(path,JSON.stringify({experimental:true,root:'default',source:'TipTap core/table 3.30.2; y-tiptap 3.0.9; Yjs 13.6.32',cases:fixtures},null,2)+'\n');
  console.log('Generated 3 experimental community table fixtures');
}
