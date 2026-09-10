import * as Y from 'yjs'
import { writeFileSync } from 'node:fs'
import { captureTextItems, resolveTextItems } from '../adapters/collaboration/text-items.js'

// Stable synthetic fixture for independent JS/Swift/Yex implementations.
const doc = new Y.Doc(); doc.clientID = 101
const root = doc.getXmlFragment('default'), paragraph = new Y.XmlElement('paragraph')
const prefix = new Y.XmlText(), leaf = new Y.XmlText()
root.insert(0, [paragraph]); paragraph.insert(0, [prefix, leaf])
prefix.insert(0, 'prefix😀'); leaf.insert(0, 'A😀HUMANZ')
const selection = captureTextItems(root, { path: [0, 1], index: 1, length: 7 })
const cases = []
function save(name) {
  cases.push({ name, update: Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64'), selection,
    expected: resolveTextItems(doc, root, selection) })
}
save('baseline-utf16-multiple-leaves')
const remote = new Y.Doc(); remote.clientID = 202
Y.applyUpdate(remote, Y.encodeStateAsUpdate(doc))
remote.getXmlFragment('default').get(0).get(1).insert(4, 'REMOTE')
Y.applyUpdate(doc, Y.encodeStateAsUpdate(remote)); remote.destroy()
save('interior-insertion-excluded')
leaf.delete(10, 2); save('partial-deletion')
root.delete(0, 1); save('deleted-ancestor-unavailable')
const fixture = { version: 1, yjs: '13.6.32', coordinateUnits: 'utf16', cases }
const output = new URL('../spec/relaymark/collaboration/fixtures/text-items-v1.json', import.meta.url)
writeFileSync(output, JSON.stringify(fixture, null, 2) + '\n')
doc.destroy()
