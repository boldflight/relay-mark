import { createHash } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { dirname } from 'node:path'

// SHA-256 of dist/yjs.mjs in the Yjs build package.json installs:
// boldflight/yjs v13.6.33-relay.1 (Yjs 13.6.33 + the yjs/yjs#806 undo fix).
export const upstreamSHA256 = '105c7245ab478301529c7d034f59348e51e808f9144e3ea6614cea51b74af056'
export const historyStackMethods = "  /** Copy actual maintained stack intervals and metadata without closing capture. */\n  exportHistoryStacks () {\n    if (this.doc.gc || this.doc._transaction !== null || this.undoing || this.redoing || this.currStackItem !== null) throw new Error('History owner is not settled')\n    /** @param {DeleteSet} set */\n    const copySet = set => {\n      const result = new DeleteSet()\n      set.clients.forEach((ranges, client) => result.clients.set(client, ranges.map(({ clock, len }) => ({ clock, len }))))\n      return result\n    }\n    /** @param {Array<StackItem>} stack */\n    const copy = stack => stack.map(item => ({ insertions: copySet(item.insertions), deletions: copySet(item.deletions), meta: new Map(item.meta) }))\n    return { undo: copy(this.undoStack), redo: copy(this.redoStack) }\n  }\n\n  /** Initialize genuine StackItems on a pristine retained owner. Host metadata\n   * and document binding are validated by its scoped persistence adapter.\n   * @param {Array<{insertions:DeleteSet,deletions:DeleteSet,meta:Map<any,any>}>} undo\n   * @param {Array<{insertions:DeleteSet,deletions:DeleteSet,meta:Map<any,any>}>} redo\n   */\n  restoreHistoryStacks (undo, redo) {\n    if (this.doc.gc || this.doc._transaction !== null || this.doc.store.pendingStructs !== null || this.doc.store.pendingDs !== null || this.undoStack.length || this.redoStack.length || this.undoing || this.redoing || this.currStackItem !== null || !Array.isArray(undo) || !Array.isArray(redo) || undo.length + redo.length > 16384) throw new Error('History restore requires a pristine retained manager')\n    /** @param {DeleteSet} set */\n    const copySet = set => {\n      if (!(set instanceof DeleteSet)) throw new Error('Invalid history interval set')\n      const result = new DeleteSet()\n      set.clients.forEach((ranges, client) => {\n        if (!Number.isSafeInteger(client) || client < 0 || !Array.isArray(ranges)) throw new Error('Invalid history interval')\n        let end = 0\n        result.clients.set(client, ranges.map(({ clock, len }) => {\n          if (!Number.isInteger(clock) || clock < end || !Number.isInteger(len) || len < 1 || clock + len > getState(this.doc.store, client)) throw new Error('Unavailable history interval')\n          end = clock + len\n          return { clock, len }\n        }))\n      })\n      return result\n    }\n    /** @param {Array<{insertions:DeleteSet,deletions:DeleteSet,meta:Map<any,any>}>} stack */\n    const copy = stack => stack.map(source => {\n      if (!(source.meta instanceof Map)) throw new Error('Invalid history metadata')\n      const item = new StackItem(copySet(source.deletions), copySet(source.insertions))\n      item.meta = new Map(source.meta)\n      return item\n    })\n    const undoStack = copy(undo); const redoStack = copy(redo)\n    transact(this.doc, transaction => {\n      /** @type {Array<Item>} */\n      const retained = []\n      for (const item of [...undoStack, ...redoStack]) {\n        for (const intervals of [item.insertions, item.deletions]) {\n          iterateDeletedStructs(transaction, intervals, struct => {\n            if (!(struct instanceof Item) || struct.content instanceof ContentDeleted || !this.scope.some(type => type === this.doc || isParentOf(/** @type {AbstractType<any>} */ (type), struct))) throw new Error('Unavailable retained history content')\n            if (intervals === item.deletions) retained.push(struct)\n          })\n        }\n      }\n      retained.forEach(item => keepItem(item, true))\n    }, this)\n    this.undoStack = undoStack\n    this.redoStack = redoStack\n    // Explicit group metadata controls continuation; checkpointing itself is\n    // never a semantic capture boundary on the restored maintained manager.\n    this.lastChange = undoStack.length ? 1 : 0\n  }\n\n"
export function patchHistoryHook(source) {
  if (createHash('sha256').update(source).digest('hex') !== upstreamSHA256) throw Error('Pinned Yjs history hook source changed')
  const replacements = [
    ['      itemsToRedo.forEach(struct => {',
     '      Array.from(itemsToRedo).sort((a, b) => a.id.client - b.id.client || a.id.clock - b.id.clock).forEach(struct => {'],
    // Same focused modification as committed maintained Yjs canonical-undo:
    // exact actual popped item and materialized deletion candidates.
    ['      for (let i = itemsToDelete.length - 1; i >= 0; i--) {',
     '      const deleteContext = { transaction, stackItem, itemsToDelete, type: eventType };\n      for (let i = itemsToDelete.length - 1; i >= 0; i--) {'],
    ['undoManager.deleteFilter(item)', 'undoManager.deleteFilter(item, deleteContext)'],
    ['      undoManager.currStackItem = performedChange ? stackItem : null;\n    }\n    transaction.changed.forEach',
     '      if (!performedChange && undoManager.beforeHistoryItemSkip !== null) {\n        performedChange = undoManager.beforeHistoryItemSkip({ transaction, stackItem, type: eventType }) === true;\n      }\n      undoManager.currStackItem = performedChange ? stackItem : null;\n    }\n    if (undoManager.currStackItem !== null && undoManager.beforeHistoryTransactionCommit !== null) {\n      undoManager.beforeHistoryTransactionCommit({ transaction, stackItem: undoManager.currStackItem, type: eventType });\n    }\n    transaction.changed.forEach'],
    ['    captureTimeout = 500,', '    captureTimeout = 500,\n    beforeHistoryTransactionCommit = null,\n    beforeHistoryItemSkip = null,'],
    ['    this.deleteFilter = deleteFilter;', '    this.deleteFilter = deleteFilter;\n    this.supportsUndoDeleteContext = true;\n    this.beforeHistoryTransactionCommit = beforeHistoryTransactionCommit;\n    this.relayHistoryTransactionHookVersion = 1;\n    this.beforeHistoryItemSkip = beforeHistoryItemSkip;\n    this.relayHistoryItemSkipHookVersion = 1;']
  ]
  for (const [before, after] of replacements) {
    if (source.split(before).length !== 2) throw Error('Ambiguous Yjs history hook patch')
    source = source.replace(before, after)
  }
  const stackMarker = '  clear (clearUndoStack = true, clearRedoStack = true) {'
  if (source.split(stackMarker).length !== 2) throw Error('Ambiguous maintained stack hook patch')
  source = source.replace(stackMarker, historyStackMethods + stackMarker)
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
