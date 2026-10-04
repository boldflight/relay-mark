import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {dirname} from 'node:path';
// Exact maintained @tiptap/y-tiptap3.0.9 distribution. Reviewed source changes
// live in the registered canonical-undo fork; no node_modules mutation.
export const historySelectionBaseSHA256={
 esm:'b86b8382ce375b49f7e6e386bc4ef8639863c5379e296378f649216fe56f365e',
 cjs:'1aa28ac382711a72228b68c4769233c3b440e5d6da8617a0c0c54179b164054f'
};
export function patchHistorySelection(source){
 const digest=createHash('sha256').update(source).digest('hex');
 if(!Object.values(historySelectionBaseSHA256).includes(digest))throw Error('Pinned y-tiptap history selection source changed');
 const replacements=[
 ['      restoreRelativeSelection(tr, this.beforeTransactionSelection, this, oldDoc);',
  '      const isUndoRedoOperation = transaction.origin instanceof Y.UndoManager;\n      const relativeSelection = isUndoRedoOperation\n        ? transaction.origin.currStackItem?.meta.get(this) || this.beforeTransactionSelection\n        : this.beforeTransactionSelection;\n      restoreRelativeSelection(tr, relativeSelection, this, isUndoRedoOperation ? undefined : oldDoc);'],
 ['        stackItem.meta.set(binding, yUndoPluginKey.getState(view.state).prevSel);',
  '        const selection = undoManager.undoing || undoManager.redoing\n          ? binding.beforeTransactionSelection\n          : yUndoPluginKey.getState(view.state).prevSel;\n        stackItem.meta.set(binding, selection);'],
 ["    undoManager.on('stack-item-popped', ({ stackItem }) => {\n      const binding = ystate.binding;\n      if (binding) {\n        binding.beforeTransactionSelection = stackItem.meta.get(binding) || binding.beforeTransactionSelection;\n      }\n    });\n",'']
 ];
 for(const[before,after]of replacements){if(source.split(before).length!==2)throw Error('Ambiguous maintained selection patch');source=source.replace(before,after)}
 return digest===historySelectionBaseSHA256.cjs ? source.replace('const isUndoRedoOperation = transaction.origin instanceof Y.UndoManager;','const isUndoRedoOperation = transaction.origin instanceof Y__namespace.UndoManager;') : source;
}
export const historySelectionPlugin={name:'canonical-maintained-history-selection',setup(build){
 build.onLoad({filter:/[/\\]@tiptap[/\\]y-tiptap[/\\]dist[/\\]y-tiptap\.(?:js|cjs)$/},async({path})=>({contents:patchHistorySelection(await readFile(path,'utf8')),loader:'js',resolveDir:dirname(path)}));
}};
