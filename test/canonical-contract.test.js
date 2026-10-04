import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { compileRelayMark } from '../src/runtime.js';
import { validateDocument } from '../src/validator.js';

test('new source is an unversioned AST and cannot masquerade as the old format numbered one', () => {
  const document = compileRelayMark('# Canonical paper\n\nPreserve this meaning.').document;
  assert.equal(Object.hasOwn(document, 'version'), false);
  assert.deepEqual(validateDocument(document), []);
  assert.ok(validateDocument({ ...document, version: 1 }).some(({code}) => code === 'relaymark.document.obsolete_version'));
});

test('all canonical descriptor bindings use the single portable contract', async () => {
  const expected = { contract_version: 1, schema: 'relaymark-prosemirror', source_contract: 'relaymark_ast' };
  const contract = JSON.parse(readFileSync(new URL('../spec/relaymark/contract.json', import.meta.url)));
  const { canonicalContract } = await import('../src/contract.js');
  assert.deepEqual(contract, expected);
  assert.deepEqual(canonicalContract, expected);
  assert.equal(Object.isFrozen(canonicalContract), true);
});
