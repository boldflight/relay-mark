import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import {replayContentEditMutation} from '../adapters/collaboration/content-edit-mutation.js'
import {patchHistoryHook} from '../scripts/yjs-history-hook.mjs'
import {createRequire} from 'node:module'
const require=createRequire(import.meta.url)
test('original native random-order restored attributes remain refused rather than assigning source IDs to another parent',()=>{
 const evidence=JSON.parse(fs.readFileSync(new URL('../spec/relaymark/collaboration/fixtures/content-edit-native-inverse-original-order.json',import.meta.url)))
 assert.throws(()=>replayContentEditMutation(evidence),/Original mutation differs from maintained owned history/)
})
test('prepared maintained owner uses the same exact source identity comparator as the committed fork',()=>{
 const source=fs.readFileSync(new URL('./dist/yjs.mjs',new URL(require.resolve('yjs/package.json'),'file:')),'utf8')
 assert.equal(patchHistoryHook(source).split('Array.from(itemsToRedo).sort((a, b) => a.id.client - b.id.client || a.id.clock - b.id.clock).forEach(struct => {').length,2)
})
