// Times one job of the JavaScript reference runtime; the counterpart of
// `examples/bench.rs`. Run from the repository root:
//
//   node crates/relaymark-core/tools/bench.mjs <job> <input> <iterations>
import { readFileSync } from 'node:fs';
import {
  parseDocument, serializeDocument, projectDocumentMarkdown, renderDocument,
  documentToSnapshot, snapshotToDocument
} from '../../../src/document-source.js';
import { relayMarkToProseMirror, proseMirrorToRelayMark } from '../../../src/document-adapter.js';

const [job, input, count] = process.argv.slice(2);
const iterations = Number(count);
const text = readFileSync(input, 'utf8');
const value = ['parse', 'load'].includes(job) ? null : JSON.parse(text);
const jobs = {
  parse: () => parseDocument(text, { namespace: 'bench' }),
  load: () => parseDocument(text),
  serialize: () => serializeDocument(value),
  markdown: () => projectDocumentMarkdown(value),
  html: () => renderDocument(value),
  to_snapshot: () => documentToSnapshot(value),
  from_snapshot: () => snapshotToDocument(value),
  to_prosemirror: () => relayMarkToProseMirror(value),
  from_prosemirror: () => proseMirrorToRelayMark(value)
};
const times = [];
let sink;
for (let i = 0; i < iterations; i++) {
  const start = process.hrtime.bigint();
  sink = jobs[job]();
  times.push(Number(process.hrtime.bigint() - start) / 1e6);
}
const first = times[0] ?? 0;
times.sort((a, b) => a - b);
console.log(JSON.stringify({ engine: 'js', job, iterations, first_ms: +first.toFixed(3), median_ms: +(times[times.length >> 1] ?? 0).toFixed(3), sink: typeof sink }));
