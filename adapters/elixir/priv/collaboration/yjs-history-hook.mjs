import { createHash } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { dirname } from 'node:path'

export const upstreamSHA256 = '5d411d02f1467b947dbb8db7ae39fefc4ae1ff881679c97e9e86d4fc33cd160f'
export function patchHistoryHook(source) {
  if (createHash('sha256').update(source).digest('hex') !== upstreamSHA256) throw Error('Yjs 13.6.32 history hook source changed')
  const replacements = [
    ['      undoManager.currStackItem = performedChange ? stackItem : null;\n    }\n    transaction.changed.forEach',
     '      if (!performedChange && undoManager.beforeHistoryItemSkip !== null) {\n        performedChange = undoManager.beforeHistoryItemSkip({ transaction, stackItem, type: eventType }) === true;\n      }\n      undoManager.currStackItem = performedChange ? stackItem : null;\n    }\n    if (undoManager.currStackItem !== null && undoManager.beforeHistoryTransactionCommit !== null) {\n      undoManager.beforeHistoryTransactionCommit({ transaction, stackItem: undoManager.currStackItem, type: eventType });\n    }\n    transaction.changed.forEach'],
    ['    captureTimeout = 500,', '    captureTimeout = 500,\n    beforeHistoryTransactionCommit = null,\n    beforeHistoryItemSkip = null,'],
    ['    this.deleteFilter = deleteFilter;', '    this.deleteFilter = deleteFilter;\n    this.beforeHistoryTransactionCommit = beforeHistoryTransactionCommit;\n    this.relayHistoryTransactionHookVersion = 1;\n    this.beforeHistoryItemSkip = beforeHistoryItemSkip;\n    this.relayHistoryItemSkipHookVersion = 1;']
  ]
  for (const [before, after] of replacements) {
    if (source.split(before).length !== 2) throw Error('Ambiguous Yjs history hook patch')
    source = source.replace(before, after)
  }
  return source + '\nexport { cleanupContextlessFormattingGap as relayCleanupContextlessFormattingGap };\n'
}
export const historyHookPlugin = {
  name: 'relay-yjs-history-transaction-hook-v1',
  setup(build) {
    build.onLoad({ filter: /[/\\]yjs[/\\]dist[/\\]yjs\.mjs$/ }, async ({ path }) => ({
      contents: patchHistoryHook(await readFile(path, 'utf8')), loader: 'js', resolveDir: dirname(path)
    }))
  }
}
