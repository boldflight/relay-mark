// bun scripts/collaboration-inline-v3-fixture.mjs /absolute/web/assets --write|--check|--write-offered|--check-offered
// Uses installed community TipTap StarterKit, y-tiptap and Yjs with stable block IDs.
import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
import { proseMirrorV3ToRelayMark, relayMarkV3ToProseMirror } from '../src/collaboration-table-v3.js';
import { validateDocument } from '../src/validator.js';
import { validateJSONSchema } from '../src/json-schema.js';

const [assetsInput, mode] = process.argv.slice(2);
if (!assetsInput || !['--write', '--check', '--write-offered', '--check-offered'].includes(mode)) {
  throw new Error('Usage: bun scripts/collaboration-inline-v3-fixture.mjs /absolute/web/assets --write|--check|--write-offered|--check-offered');
}
const offered = mode.endsWith('-offered');
const writing = mode.startsWith('--write');
const assets = resolve(assetsInput);
const esm = file => import(pathToFileURL(join(assets, 'node_modules', file)));
const { getSchema, Extension } = await esm('@tiptap/core/dist/index.js');
const { default: StarterKit } = await esm('@tiptap/starter-kit/dist/index.js');
const { prosemirrorToYXmlFragment, yDocToProsemirrorJSON } = await esm('@tiptap/y-tiptap/dist/y-tiptap.js');
const Y = await esm('yjs/dist/yjs.mjs');
const { default: Highlight } = await esm('@tiptap/extension-highlight/dist/index.js');
const { default: Superscript } = await esm('@tiptap/extension-superscript/dist/index.js');
const { default: Subscript } = await esm('@tiptap/extension-subscript/dist/index.js');
const { PaperHeading } = await import(pathToFileURL(join(assets, 'js/editors/extensions/paper-heading.js')));

const stableIDs = Extension.create({ name: 'fixtureStableIDs', addGlobalAttributes() {
  return [{ types: ['paragraph', 'heading', 'listItem', 'bulletList'],
    attributes: { relaymarkId: { default: null } } }];
} });
const schema = getSchema([StarterKit.configure({ trailingNode: false, heading: false }), PaperHeading,
  ...(offered ? [Highlight, Superscript, Subscript] : []), stableIDs]);
const id = number => `b0000000000004000800000000000${number.toString(16).padStart(4, '0')}`;
const text = (value, marks) => ({ type: 'text', text: value, ...(marks ? { marks } : {}) });
const base = { type: 'doc', content: [
  { type: 'paragraph', attrs: { relaymarkId: id(1) }, content: [
    text('Plain '), text('bold italic strike', [{ type: 'strike' }, { type: 'italic' }, { type: 'bold' }]),
    text(' then '), text('code `x`', [{ type: 'code' }]),
    { type: 'hardBreak' },
    text('web', [{ type: 'link', attrs: { href: 'https://example.org/path?q=relay#part' } }]),
    text(' and '), text('Relay entity', [{ type: 'link', attrs: { href: 'relay:entity/12345678-1234-4234-8234-123456789abc' } }, { type: 'bold' }]),
  ] },
  { type: 'heading', attrs: { relaymarkId: id(2), level: 2, headingId: 'marked-heading' },
    content: [text('Marked heading', [{ type: 'italic' }])] },
  { type: 'bulletList', attrs: { relaymarkId: id(3) }, content: [
    { type: 'listItem', attrs: { relaymarkId: id(4) }, content: [
      { type: 'paragraph', attrs: { relaymarkId: id(5) }, content: [text('List link', [{ type: 'link', attrs: { href: 'mailto:relay@example.org' } }])] }
    ] }
  ] }
] };
const offeredRaw = { type: 'doc', content: [
  { type: 'paragraph', attrs: { relaymarkId: id(21) }, content: [
    text('Underlined', [{ type: 'underline' }]), text(' '),
    text('Highlighted', [{ type: 'highlight' }]), text(' '),
    text('Superscript', [{ type: 'superscript' }]), text(' '),
    text('Subscript', [{ type: 'subscript' }]), text(' '),
    text('All offered', [{ type: 'subscript' }, { type: 'highlight' }, { type: 'underline' },
      { type: 'bold' }, { type: 'superscript' }]),
  ] },
  { type: 'heading', attrs: { relaymarkId: id(22), level: 2, headingId: 'offered-marks' },
    content: [text('Head highlight', [{ type: 'highlight' }, { type: 'italic' }])] },
  { type: 'paragraph', attrs: { relaymarkId: id(23) }, content: [
    text('Entity link', [{ type: 'link', attrs: { href: 'relay:entity/12345678-1234-4234-8234-123456789abc' } },
      { type: 'underline' }, { type: 'highlight' }])
  ] },
] };
const raw = offered ? offeredRaw : base;
const normalized = JSON.parse(JSON.stringify(schema.nodeFromJSON(raw).toJSON()));
const doc = new Y.Doc();
doc.clientID = offered ? 91_505 : 91_504;
prosemirrorToYXmlFragment(schema.nodeFromJSON(normalized), doc.getXmlFragment('default'));
const update = Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64');
const replay = new Y.Doc();
Y.applyUpdate(replay, Buffer.from(update, 'base64'));
assert.deepEqual(JSON.parse(JSON.stringify(schema.nodeFromJSON(yDocToProsemirrorJSON(replay, 'default')).toJSON())), normalized);
const expectedAST = proseMirrorV3ToRelayMark(normalized);
const astSchemaPath = new URL('../spec/relaymark/schemas/relaymark-document.schema.json', import.meta.url);
assert.deepEqual(validateDocument(expectedAST), []);
assert.deepEqual(validateJSONSchema(expectedAST, JSON.parse(await readFile(astSchemaPath, 'utf8')), astSchemaPath.pathname), []);
assert.deepEqual(relayMarkV3ToProseMirror(expectedAST), normalized);
const fixture = { fixture_version: 1, root: 'default', client_id: doc.clientID,
  source: `Community TipTap StarterKit/PaperHeading${offered ? '/Highlight/Superscript/Subscript' : ''} + stable relaymarkId attrs + y-tiptap + Yjs`, normalized,
  expected_ast: expectedAST, update };
const output = `${JSON.stringify(fixture, null, 2)}\n`;
const filename = offered ? 'inline-offered-marks-v3-draft.json' : 'inline-marks-v3-draft.json';
for (const path of [
  new URL(`../spec/relaymark/collaboration/fixtures/${filename}`, import.meta.url),
  new URL(`../adapters/swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/${filename}`, import.meta.url)
]) {
  if (writing) await writeFile(path, output);
  else assert.equal(await readFile(path, 'utf8'), output);
}
console.log(`Community v3 inline fixture ${writing ? 'written' : 'matches'}`);
doc.destroy();
replay.destroy();
