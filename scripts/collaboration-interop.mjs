import * as Y from 'yjs'
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
  writeFileSync(fixturePath, JSON.stringify({ schema: 'relaymark-prosemirror-v1', root: 'default', yjs: '13.6.32', seed, browserUpdate: Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64') }, null, 2) + '\n')
} else {
  const fixture = JSON.parse(readFileSync(fixturePath))
  const native = JSON.parse(readFileSync(process.argv[2]))
  const doc = new Y.Doc()
  Y.applyUpdate(doc, Buffer.from(fixture.browserUpdate, 'base64'))
  Y.applyUpdate(doc, Buffer.from(native.update, 'base64'))
  Y.applyUpdate(doc, Buffer.from(native.update, 'base64'))
  const expected = '<paragraph>Swift <bold><link href="relay:entity/123">Hello 🌍 browser</link></bold></paragraph>'
  if (snapshot(doc) !== expected) throw Error(snapshot(doc))
  console.log('Node Yjs → Swift JavaScriptCore → Node Yjs XML convergence passed')
}
