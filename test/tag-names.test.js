import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseAtomSource } from '../src/document-atoms.js';

// Relay's shared tag-name table, copied verbatim from relay-elixir.
const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/conformance/tag-names.json', import.meta.url)));
const id = '9712027d-18db-448e-8514-cea7c215d6f7';

// Bug caught: a normalized non-ASCII tag (`#仕事`) refused as an authored
// atom, so a document holding it cannot be saved or loaded.
test('every normalized Relay tag name is an authored tag atom', () => {
  for (const { tag } of fixture.cases.filter(row => row.tag !== null)) {
    const source = `[[Tag: ${id} | #${tag}]]`;
    assert.deepEqual(parseAtomSource(source)?.props, { name: tag, source }, tag);
  }
});

test('names that are not normalized stay text', () => {
  for (const name of ['Work', 'ΣΑΣ', 'two words', '-lead', 'a|b', '仕事 メモ', 'foo_bar', '\u0301a', '仕事。']) {
    assert.equal(parseAtomSource(`[[Tag: ${id} | #${name}]]`), null, name);
  }
});
