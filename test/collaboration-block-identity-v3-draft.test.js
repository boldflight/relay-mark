import test from 'node:test'
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import * as Y from 'yjs'

const json = path => JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8'))
const fixture = json('../spec/relaymark/collaboration/fixtures/block-identity-v3-draft.json')
const astSchema = json('../spec/relaymark/schemas/relaymark-document.schema.json')
const liveSuite = json('../spec/relaymark/conformance/suite.json')
const v4BlockID = /^b[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$/

function xmlNode(shape) {
  if ('text' in shape) {
    const text = new Y.XmlText()
    text.insert(0, shape.text)
    return text
  }
  const element = new Y.XmlElement(shape.tag)
  element.setAttribute(fixture.attribute, shape.relaymarkId)
  if (shape.children?.length) element.insert(0, shape.children.map(xmlNode))
  return element
}

function collect(node, ids = []) {
  if (node instanceof Y.XmlElement) {
    ids.push(node.getAttribute(fixture.attribute))
    for (const child of node.toArray()) collect(child, ids)
  }
  return ids
}

test('draft v3 block IDs are AST-compatible and survive exact Yjs binary replay', () => {
  assert.equal(fixture.status, 'draft_not_live')
  assert.equal(fixture.schema, 'relaymark-prosemirror-v3')
  assert.equal(fixture.root, 'default')
  assert.equal(fixture.attribute, 'relaymarkId')
  assert.ok(!liveSuite.features.includes('collaboration.block_identity.v3'))
  const portablePattern = new RegExp(astSchema.$defs.id.pattern)
  const ids = fixture.expected_preorder_ids
  assert.equal(new Set(ids).size, ids.length)
  for (const id of ids) {
    assert.match(id, v4BlockID)
    assert.match(id, portablePattern)
  }
  for (let i = 0; i < 16; i++) {
    assert.match(`b${randomUUID().replaceAll('-', '')}`, v4BlockID)
  }

  const doc = new Y.Doc()
  doc.getXmlFragment(fixture.root).insert(0, [xmlNode(fixture.tree)])
  assert.deepEqual(collect(doc.getXmlFragment(fixture.root).get(0)), ids)
  const replica = new Y.Doc()
  Y.applyUpdate(replica, Y.encodeStateAsUpdate(doc))
  assert.deepEqual(collect(replica.getXmlFragment(fixture.root).get(0)), ids)
  assert.equal(replica.getXmlFragment(fixture.root).get(0).nodeName, 'table')
  assert.equal(replica.getXmlFragment(fixture.root).get(0).get(0).get(0).get(0).get(0).toString(), 'Name')
})
