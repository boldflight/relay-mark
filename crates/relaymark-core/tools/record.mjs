// Records the JavaScript reference runtime as a differential oracle.
//
//   RELAYMARK_RECORD=/path/calls.jsonl node --import ./crates/relaymark-core/tools/record.mjs --test
//
// Every outermost call into an exported `src/*.js` function appends one JSON
// line: {fn, args, ok, value} or {fn, args, ok: false, error}. Arguments are
// cloned before the call, because callers mutate them afterwards. Values JSON
// cannot carry are tagged ({"$bytes": base64}, {"$undefined": true},
// {"$number": "Infinity"}) or make the call unrecordable ({"$unrecordable"}).
import { register } from 'node:module';
import { appendFileSync } from 'node:fs';

const out = process.env.RELAYMARK_RECORD;
let depth = 0;

function encode(value, seen = new Set()) {
  if (value === undefined) return { $undefined: true };
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return value;
  if (typeof value === 'number') {
    if (!Number.isFinite(value) || Object.is(value, -0)) return { $number: String(value) };
    return value;
  }
  if (typeof value === 'bigint' || typeof value === 'function' || typeof value === 'symbol') return { $unrecordable: typeof value };
  if (value instanceof Uint8Array) return { $bytes: Buffer.from(value).toString('base64') };
  if (seen.has(value)) return { $unrecordable: 'cycle' };
  seen.add(value);
  try {
    if (Array.isArray(value)) return value.map(item => encode(item, seen));
    const proto = Object.getPrototypeOf(value);
    if (proto !== Object.prototype && proto !== null) return { $unrecordable: proto?.constructor?.name ?? 'object' };
    const result = {};
    for (const [key, item] of Object.entries(value)) result[key] = encode(item, seen);
    return result;
  } finally { seen.delete(value); }
}

globalThis.__relaymarkRecord = (name, fn) => function (...args) {
  if (!out || depth > 0) return fn.apply(this, args);
  let input;
  try { input = encode(structuredClone(args)); } catch { input = { $unrecordable: 'clone' }; }
  depth++;
  try {
    const value = fn.apply(this, args);
    depth--;
    appendFileSync(out, JSON.stringify({ fn: name, args: input, ok: true, value: encode(value) }) + '\n');
    return value;
  } catch (error) {
    depth--;
    appendFileSync(out, JSON.stringify({ fn: name, args: input, ok: false, error: String(error?.message ?? error) }) + '\n');
    throw error;
  }
};

register('./record-hooks.mjs', import.meta.url);
