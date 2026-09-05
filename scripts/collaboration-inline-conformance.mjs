import * as Y from 'yjs'
import assert from 'node:assert/strict'
import { readFileSync, writeFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
export const fixtureURL = new URL('../spec/relaymark/collaboration/fixtures/inline-v1.json', import.meta.url)
export const swiftFixtureURL = new URL('../adapters/swift/Tests/RelayMarkCollaborationTests/Fixtures/inline-v1.json', import.meta.url)
export function tree(node) {
  if (node instanceof Y.XmlText) return {kind:'text',delta:node.toDelta()}
  if (node instanceof Y.XmlElement) return {kind:'element',name:node.nodeName,attributes:node.getAttributes(),children:node.toArray().map(tree)}
  return {kind:'fragment',children:node.toArray().map(tree)}
}
export function plain(node) {
  if (node instanceof Y.XmlText) return node.toDelta().map(x=>x.insert).join('')
  if (node.nodeName === 'hardBreak') return '\u2028'
  if (node.nodeName === 'horizontalRule') return '\uFFFC'
  return node.toArray().map(plain).join(['paragraph','heading','codeBlock'].includes(node.nodeName) ? '' : '\n')
}
function element(name, children=[], attributes={}) {
  const node = new Y.XmlElement(name)
  for (const [k,v] of Object.entries(attributes)) node.setAttribute(k,v)
  node.insert(0,children); return node
}
function text(value, attributes={}) { const node = new Y.XmlText(); node.insert(0,value,attributes); return node }
export function generate() {
  const doc = new Y.Doc(); doc.clientID=41001
  doc.getXmlFragment('default').insert(0,[
    element('heading',[text('A🌍'),element('hardBreak'),text('B'),text('C',{link:{href:'relay:entity/person-1'}})],{level:2}),
    element('horizontalRule'),element('paragraph',[text('D')]),
    element('blockquote',[element('paragraph',[text('e'),element('hardBreak'),text('f')])]),
    element('codeBlock',[text('let '),text('x\n')],{language:'swift'})
  ])
  const seed=Y.encodeStateAsUpdate(doc), remote=new Y.Doc(); remote.clientID=41002; Y.applyUpdate(remote,seed)
  const vector=Y.encodeStateVector(remote); remote.getXmlFragment('default').get(0).get(3).insert(1,'!')
  const result={fixture_version:1,schema:'relaymark-prosemirror-v1',root:'default',seed:Buffer.from(seed).toString('base64'),
    remote_update:Buffer.from(Y.encodeStateAsUpdate(remote,vector)).toString('base64'),
    initial_text:'A🌍\u2028BC\n\uFFFC\nD\ne\u2028f\nlet x\n',cases:[
      {id:'delete-inline-break',start:3,end:4,text:'',expected:'A🌍BC\n\uFFFC\nD\ne\u2028f\nlet x\n'},
      {id:'insert-after-break',start:4,end:4,text:'new',expected:'A🌍\u2028newBC\n\uFFFC\nD\ne\u2028f\nlet x\n'},
      {id:'delete-mixed-leaves',start:1,end:6,text:'X',expected:'AX\n\uFFFC\nD\ne\u2028f\nlet x\n'},
      {id:'delete-across-rule',start:5,end:10,text:'Z',expected:'A🌍\u2028BZ\ne\u2028f\nlet x\n'},
      {id:'insert-inline-break',start:5,end:5,text:'\u2028z',expected:'A🌍\u2028B\u2028zC\n\uFFFC\nD\ne\u2028f\nlet x\n'},
      {id:'delete-rule-atom',start:7,end:8,text:'',expected:'A🌍\u2028BC\n\nD\ne\u2028f\nlet x\n'},
      {id:'type-before-rule',start:7,end:7,text:'new',expected:'A🌍\u2028BC\nnew\n\uFFFC\nD\ne\u2028f\nlet x\n'},
      {id:'type-after-rule',start:8,end:8,text:'new',expected:'A🌍\u2028BC\n\uFFFC\nnew\nD\ne\u2028f\nlet x\n'}]}
  doc.destroy(); remote.destroy(); return result
}
if (process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  if (process.argv[2]==='--generate') {
    const data=JSON.stringify(generate(),null,2)+'\n';writeFileSync(fixtureURL,data);writeFileSync(swiftFixtureURL,data)
  } else {
    const fixture=JSON.parse(readFileSync(fixtureURL)), rows=JSON.parse(readFileSync(process.argv[2]))
    for (const row of rows) {
      const doc=new Y.Doc(); Y.applyUpdate(doc,Buffer.from(row.update,'base64'))
      const expected=row.id==='concurrent' ? 'A🌍BC!\n\uFFFC\nD\ne\u2028f\nlet x\n' : fixture.cases.find(x=>x.id===row.id).expected
      assert.equal(plain(doc.getXmlFragment('default')),expected)
      doc.destroy()
    }
    assert.equal(rows.length,fixture.cases.length+1)
    console.log('Verified actual Swift JavaScriptCore mixed-inline exports in upstream Yjs')
  }
}
