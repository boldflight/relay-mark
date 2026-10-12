// Current-operation tests bind the same physical attribute codec as production.
// This does not admit or convert historical aggregate-settings fixtures.
import * as binding from '@tiptap/y-tiptap';
import {canonicalAttributeCodec} from '../../src/document-attributes.js';
export * from '@tiptap/y-tiptap';
export const initProseMirrorDoc = (root, schema) => binding.initProseMirrorDoc(root, schema, canonicalAttributeCodec);
export class ProsemirrorBinding extends binding.ProsemirrorBinding {
  constructor(root, mapping = new Map()) { super(root, mapping, canonicalAttributeCodec); }
}
export function prosemirrorToYXmlFragment(document, root) {
  const initialized = initProseMirrorDoc(root, document.type.schema);
  binding.updateYFragment(root.doc, root, document, initialized.meta);
  return root;
}
export function updateYFragment(doc, root, document, meta) {
  return binding.updateYFragment(doc, root, document, {...meta, attributeCodec: canonicalAttributeCodec});
}
