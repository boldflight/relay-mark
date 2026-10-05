import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import * as Replay from '../adapters/collaboration/content-edit-mutation.js';
const directory=new URL('../spec/relaymark/collaboration/fixtures/',import.meta.url);
for(const name of ['enter','peer','typing','mark','widget','delete','redundant'])test(`actual ${name} command replays every maintained mutation at its retained sender frontier`,()=>{
 const f=JSON.parse(fs.readFileSync(new URL(`content-edit-${name}-mutation.json`,directory)));
 const {description,...evidence}=f;const proof=Replay.replayContentEditMutation(evidence);
 if(name!=='redundant')assert.deepEqual(proof.footprint,f.footprint);assert.equal(proof.complete_mutation_correspondence,true);
});

for(const name of ['transient-format','transient-metadata'])test(`invisible ${name} writes cannot hide behind the same visible command`,()=>{
 const {description,...evidence}=JSON.parse(fs.readFileSync(new URL(`content-edit-${name}-mutation.json`,directory)));
 assert.throws(()=>Replay.replayContentEditMutation(evidence),/differs from executed/);
});

test('catch-up original cannot rewrite already retained text item contents',()=>{
 const {description,...evidence}=JSON.parse(fs.readFileSync(new URL('content-edit-redundant-mutation.json',directory)));
 const original=evidence.footprint.structs.find(r=>r.content.kind==='string'&&r.item.clock<10);original.content.text='B'+original.content.text.slice(1);
 assert.throws(()=>Replay.replayContentEditMutation(evidence),/rewrites retained item/);
});

// These original updates were emitted by the native maintained PM command
// bridge, not a JS fixture producer or a re-encoded state-equivalence stand-in.
for (const kind of ['media', 'control', 'atom']) test(`actual native ${kind} command matches every canonical CRDT mutation`, () => {
 const f=JSON.parse(fs.readFileSync(new URL(`content-edit-native-${kind}.json`,directory)));
 const evidence=Object.fromEntries(['sender_state_base64','current_state_base64','writer_client','operation','footprint'].map(key=>[key,f[key]]));
 assert.equal(Replay.replayContentEditMutation(evidence).complete_mutation_correspondence,true);
});
for (const kind of ['media', 'control']) test(`retained native ${kind} attribute-allocation fault is refused`, () => {
 const f=JSON.parse(fs.readFileSync(new URL(`content-edit-native-${kind}-attribute-order-fault.json`,directory)));
 const evidence=Object.fromEntries(['sender_state_base64','current_state_base64','writer_client','operation','footprint'].map(key=>[key,f[key]]));
 assert.throws(()=>Replay.replayContentEditMutation(evidence),/differs from executed/);
});
