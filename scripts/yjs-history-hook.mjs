import { createHash } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { dirname } from 'node:path'

// SHA-256 of dist/yjs.mjs in the Yjs build package.json installs:
// boldflight/yjs v13.6.33-relay.1 (Yjs 13.6.33 + the yjs/yjs#806 undo fix).
export const upstreamSHA256 = '105c7245ab478301529c7d034f59348e51e808f9144e3ea6614cea51b74af056'
export function patchHistoryHook(source) {
  if (createHash('sha256').update(source).digest('hex') !== upstreamSHA256) throw Error('Pinned Yjs history hook source changed')
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
