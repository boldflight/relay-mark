import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const json = path => JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8'));

test('rich table AST fixture remains gated until portable span, width and ID semantics are specified', () => {
  const pendingUrl = new URL('../spec/relaymark/collaboration/fixtures/rich-table-ast.pending.json', import.meta.url);
  const pending = JSON.parse(readFileSync(pendingUrl, 'utf8'));
  const community = JSON.parse(readFileSync(new URL(pending.input.fixture, pendingUrl), 'utf8'));
  const suite = json('../spec/relaymark/conformance/suite.json');
  const schema = json('../spec/relaymark/schemas/relaymark-document.schema.json');
  const input = community.cases.find(({ name }) => name === pending.input.case);
  const header = input.prosemirror.content[0].content[0].content[0];

  assert.equal(pending.enabled, false);
  assert.equal(pending.expected_ast, null);
  assert.equal(header.type, 'tableHeader');
  assert.deepEqual(header.attrs.colwidth, pending.must_preserve.colwidth);
  assert.equal(header.attrs.colspan, pending.must_preserve.colspan);
  assert.equal(header.attrs.rowspan, pending.must_preserve.rowspan);
  assert.deepEqual(input.prosemirror.content[0].content.flatMap(row => row.content.map(cell => cell.content[0].content[0].text)), pending.must_preserve.cell_text);
  assert.ok(!suite.features.includes('commonmark.table.rich'));
  assert.deepEqual(schema.$defs.block.properties.props.additionalProperties, { $ref: '#/$defs/jsonValue' });
});
