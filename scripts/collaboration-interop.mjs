import * as Y from 'yjs'
import { Awareness, encodeAwarenessUpdate, applyAwarenessUpdate } from 'y-protocols/awareness'
import { readFileSync, writeFileSync } from 'node:fs'
const fixturePath = 'adapters/swift/Tests/RelayMarkCollaborationTests/Fixtures/yjs-v13-xml.json'
function snapshot(doc) { return doc.getXmlFragment('default').toJSON() }
if (process.argv[2] === '--generate') {
  const doc = new Y.Doc(); doc.clientID = 100
  const paragraph = new Y.XmlElement('paragraph')
  const text = new Y.XmlText()
  doc.getXmlFragment('default').insert(0, [paragraph]); paragraph.insert(0, [text])
  text.insert(0, 'Hello 🌍', { bold: {}, link: { href: 'relay:entity/123' } })
  const seed = Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64')
  text.insert(8, ' browser')
  const awareness = new Awareness(doc)
  const anchor = Y.createRelativePositionFromTypeIndex(text, 6)
  awareness.setLocalState({ user: { name: 'Browser', color: '#2563eb' }, cursor: { anchor: Y.relativePositionToJSON(anchor), head: Y.relativePositionToJSON(anchor) } })
  const browserAwareness = Buffer.from(encodeAwarenessUpdate(awareness, [doc.clientID])).toString('base64')
  awareness.destroy()
  writeFileSync(fixturePath, JSON.stringify({ browserAwareness, schema: 'relaymark-prosemirror-v1', root: 'default', yjs: '13.6.32', seed, browserUpdate: Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64') }, null, 2) + '\n')
} else {
  const fixture = JSON.parse(readFileSync(fixturePath))
  const native = JSON.parse(readFileSync(process.argv[2]))
  const doc = new Y.Doc()
  Y.applyUpdate(doc, Buffer.from(fixture.browserUpdate, 'base64'))
  Y.applyUpdate(doc, Buffer.from(native.update, 'base64'))
  Y.applyUpdate(doc, Buffer.from(native.update, 'base64'))
  const expected = '<paragraph>Swift <bold><link href="relay:entity/123">Hello 🌍 browser</link></bold></paragraph>'
  if (snapshot(doc) !== expected) throw Error(snapshot(doc))
  if (native.awareness) {
    const awareness = new Awareness(doc)
    applyAwarenessUpdate(awareness, Buffer.from(native.awareness, 'base64'), 'native')
    if (![...awareness.getStates().values()].some(state => state.user?.name === 'Native' && Y.createAbsolutePositionFromRelativePosition(Y.createRelativePositionFromJSON(state.cursor.anchor), doc)?.index === 6)) throw Error('Native awareness failed')
    awareness.destroy()
  }
  console.log('Node Yjs → Swift → Node Yjs XML convergence passed')
}
