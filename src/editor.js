/** Editor-only helpers for TipTap hosts using the stock Yjs binding: the
 * canonical schema and the authored table normalization. Hosts import this
 * small module instead of the content-edit proof runtime. */
export {createCanonicalEditorSchema} from './editor-model.js';
export {removeCoveredContentEditTableRow} from './editor-table.js';
