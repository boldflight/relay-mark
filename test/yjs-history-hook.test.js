import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { patchHistoryHook } from '../scripts/yjs-history-hook.mjs'
const require = createRequire(import.meta.url)
test('pinned Yjs history hook transform is deterministic and refuses any upstream drift', () => {
  const source = readFileSync(new URL('./dist/yjs.mjs', new URL(require.resolve('yjs/package.json'), 'file:')), 'utf8')
  const first = patchHistoryHook(source)
  assert.equal(patchHistoryHook(source), first)
  assert.equal(first.split('undoManager.beforeHistoryTransactionCommit({ transaction, stackItem: undoManager.currStackItem, type: eventType });').length, 2)
  assert.ok(first.includes('beforeHistoryTransactionCommit = null'))
  assert.ok(first.includes('this.relayHistoryTransactionHookVersion = 1;'))
  assert.equal(first.split('undoManager.beforeHistoryItemSkip({ transaction, stackItem, type: eventType }) === true').length,2)
  assert.ok(first.includes('this.relayHistoryItemSkipHookVersion = 1;'))
  assert.ok(first.includes('beforeHistoryItemSkip = null'))
  assert.throws(() => patchHistoryHook(source + '\n'))
  assert.throws(() => patchHistoryHook(first))
})
