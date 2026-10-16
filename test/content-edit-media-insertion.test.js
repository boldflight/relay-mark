import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {validateMediaInsertion} from '../src/content-edit.js';

// Synthetic original produced by RelayMarkNativeDocument's actual owned FileRef
// insertion and buildContentEditWitness, via relay-swift's original-cleanup test.
// No user data. The producer deliberately returns derived ranges, not step_maps.
const fixture = JSON.parse(fs.readFileSync(new URL('./fixtures/native-file-insertion-witness.json', import.meta.url)));
for (const runtime of ['source', 'packaged']) test(`${runtime} validates the actual native FileRef witness and refuses changed command, ranges or file identity`, () => {
  const {before, steps, witness, kind, sources} = fixture;
  let invoke = args => validateMediaInsertion(...args);
  if (runtime === 'packaged') {
    const context = vm.createContext({});
    const swift = fs.readFileSync(new URL('../adapters/swift/Sources/RelayMarkSwift/Resources/content-edit-runtime.js', import.meta.url), 'utf8');
    assert.equal(swift, fs.readFileSync(new URL('../adapters/elixir/priv/collaboration/content-edit-runtime.js', import.meta.url), 'utf8'));
    vm.runInContext(swift, context);
    invoke = args => vm.runInContext(`RelayMarkContentEditRuntime.validateMediaInsertion(...${JSON.stringify(args)})`, context);
  }
  assert.equal(invoke([before, steps, witness, kind, sources]), true);
  assert.throws(() => invoke([before, steps, witness, kind, ['22222222-2222-4222-8222-222222222222']]), /original roster mismatch/);
  assert.throws(() => invoke([before, [], witness, kind, sources]), /command mismatch/);
  for (const field of ['document', 'inserted_ranges', 'retained_ranges']) {
    const changed = {...witness, [field]: field === 'document' ? {type: 'doc', content: []} : []};
    assert.throws(() => invoke([before, steps, changed, kind, sources]), /witness mismatch/);
  }
});
