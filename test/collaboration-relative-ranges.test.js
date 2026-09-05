import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import * as Y from 'yjs'

test('canonical relative range fixtures match native resources and real Yjs positions', () => {
  const source = readFileSync(new URL('../spec/relaymark/collaboration/fixtures/relative-ranges-v1.json', import.meta.url), 'utf8')
  assert.equal(source, readFileSync(new URL('../adapters/swift/Tests/RelayMarkCollaborationTests/Fixtures/relative-ranges-v1.json', import.meta.url), 'utf8'))
  const fixture = JSON.parse(source), doc = new Y.Doc()
  Y.applyUpdate(doc, Buffer.from(fixture.seed, 'base64'))
  const root = doc.getXmlFragment('default')
  for (const entry of fixture.ranges) {
    for (const key of ['anchor', 'head']) {
      const bytes = Buffer.from(entry.range[key], 'base64')
      const relative = Y.decodeRelativePosition(bytes)
      assert.deepEqual(Buffer.from(Y.encodeRelativePosition(relative)), bytes)
      const absolute = Y.createAbsolutePositionFromRelativePosition(relative, doc, false)
      if (entry.expected === null) { assert.equal(absolute, null); continue }
      const expected = entry.expected[key]
      let type = root
      for (const index of expected.path) type = type.get(index)
      assert.equal(absolute.type, type)
      assert.equal(absolute.index, expected.index)
      assert.equal(absolute.assoc, expected.association)
    }
  }
  doc.destroy()
})
