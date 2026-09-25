// Rebuild the optional mixed-document fixture from the real concurrent TipTap
// table update. No live collaboration profile uses this script.
// node scripts/collaboration-mixed-table-v3-fixture.mjs /absolute/web/assets --write
// node scripts/collaboration-mixed-table-v3-fixture.mjs /absolute/web/assets --check
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const assets = process.argv[2];
const mode = process.argv[3];
if (!assets || !['--write', '--check'].includes(mode)) {
  throw new Error('Usage: node scripts/collaboration-mixed-table-v3-fixture.mjs /absolute/web/assets --write|--check');
}
for (const [name, version] of Object.entries({
  '@tiptap/core': '3.30.5', '@tiptap/starter-kit': '3.30.5',
  '@tiptap/extension-table': '3.30.5', '@tiptap/extension-unique-id': '3.30.5',
  '@tiptap/y-tiptap': '3.0.9', yjs: '13.6.32',
})) {
  const installed = JSON.parse(readFileSync(resolve(assets, 'node_modules', name, 'package.json')));
  assert.equal(installed.version, version, `Re-review fixture against ${name}`);
}

const require = createRequire(resolve(assets, 'package.json'));
const load = name => import(pathToFileURL(require.resolve(name)).href);
const [{ getSchema }, { StarterKit }, { TableKit }, { UniqueID }, binding, Y] = await Promise.all([
  load('@tiptap/core'), load('@tiptap/starter-kit'), load('@tiptap/extension-table'),
  load('@tiptap/extension-unique-id'), load('@tiptap/y-tiptap'), load('yjs'),
]);
const basePath = new URL('../spec/relaymark/collaboration/fixtures/table-concurrent-v3-draft.json', import.meta.url);
const outputPath = new URL('../spec/relaymark/collaboration/fixtures/table-mixed-v3-draft.json', import.meta.url);
const base = JSON.parse(readFileSync(basePath, 'utf8'));
const baseUpdate = Buffer.from(base.update, 'base64');
const id = suffix => `b0000000000004000800000000000000${suffix}`;
const paragraph = (suffix, text) => {
  const node = new Y.XmlElement('paragraph');
  node.setAttribute('relaymarkId', id(suffix));
  if (text !== null) {
    const leaf = new Y.XmlText();
    leaf.insert(0, text);
    node.insert(0, [leaf]);
  }
  return node;
};
const doc = new Y.Doc();
doc.clientID = 2_000_000_001;
Y.applyUpdate(doc, baseUpdate);
const root = doc.getXmlFragment(base.root);
assert.equal(root.length, 1);
root.insert(0, [paragraph(1, 'Before 🌍 <table>')]);
root.insert(2, [paragraph(2, null), paragraph(3, 'After the shared table')]);

const schema = getSchema([
  StarterKit, TableKit,
  UniqueID.configure({ attributeName: 'relaymarkId',
    types: ['paragraph', 'table', 'tableRow', 'tableHeader', 'tableCell'] }),
]);
const raw = binding.yDocToProsemirrorJSON(doc, base.root);
const normalized = JSON.parse(JSON.stringify(schema.nodeFromJSON(raw).toJSON()));
assert.deepEqual(normalized.content[1], base.normalized.content[0]);
assert.deepEqual(normalized.content.map(node => node.type), ['paragraph', 'table', 'paragraph', 'paragraph']);
const update = Buffer.from(Y.encodeStateAsUpdate(doc));
const fixture = {
  fixture_version: 1,
  root: base.root,
  provenance: 'TipTap 3.30.5 schema; y-tiptap 3.0.9; Yjs 13.6.32; concurrent table update plus Yjs XmlElement paragraphs',
  base_table_update_sha256: createHash('sha256').update(baseUpdate).digest('hex'),
  update: update.toString('base64'),
  raw,
  normalized,
};
const encoded = `${JSON.stringify(fixture, null, 2)}\n`;
if (mode === '--write') writeFileSync(outputPath, encoded);
else assert.equal(readFileSync(outputPath, 'utf8'), encoded);
console.log(`Mixed Yjs table fixture ${mode === '--write' ? 'written' : 'verified'}`);
doc.destroy();
