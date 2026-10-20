# Native editing runtime

`src/content-edit.js` is the native editor's runtime, packaged for Swift as
`RelayMarkSwift/Resources/content-edit-runtime.js` and called through
`RelayMarkContentEditCodec`. It runs the maintained ProseMirror schema, model,
commands and transform over a document the host has already admitted. It holds
no persistence, transport, identity allocation or authority.

- `importDocumentHTML` and `importClipboardHTML` convert HTML through the shared
  DOM grammar into a canonical document or clipboard slice. The result grants no
  source, media or edit authority; the host fences the paste and authorizes its
  references. Clipboard HTML the editor wrote (a ProseMirror slice, or HTML
  carrying RelayMark identities or authored attributes) must import exactly or
  is refused. HTML other applications wrote is read with the web editor's own
  paste rules, the `parseHTML` rules of the TipTap 3.31 extensions it uses
  (`src/document-html-foreign.js`): `b`, `i`, `s`, `u`, `mark`, `sub`, `sup`,
  `code`, inline `font-weight`, `font-style`, `text-decoration` and
  `vertical-align`, headings, paragraphs, quotes, lists, task lists, code blocks,
  tables, rules, breaks, safe links and HTTPS or host media images. Unknown
  wrappers contribute their content, so Google Docs' `font-weight:normal`
  wrapper is not bold.
- `encodeDocumentAttributes` and `decodeDocumentAttributes` convert between
  logical ProseMirror attributes and physical XML fields
  (`spec/relaymark/xml-attribute-encoding.json`).
- `createContentEditCommand(document, {command, selection})` runs one maintained
  command (`return`, `sink_list_item`, `lift_list_item` or a table command) and
  returns its actual Steps, the resulting document and selection, and the
  identities it retained. Linked task items refuse a lift that would discard the
  linked task.
- `applyContentEdit(document, {kind: "content_edit", steps})` applies actual
  maintained Step JSON, refusing noncanonical or unknown Steps, and returns the
  result with the retained, inserted and copied-subtree ranges derived from the
  actual StepMaps.
- `prepareContentEditWrite(before, steps, after)` checks that the Steps produce
  `after` and plans the causal ProseMirror-to-Yjs write;
  `planContentEditTextWrite` then gives each changed text node its minimal
  retain/delete/insert delta, so text the edit kept keeps its Yjs items.
- `planClipboardAnchorAllocation` and `planClipboardHeadingNavigation` plan
  pasted content's Anchor names and heading/link repairs as maintained Steps.
  Original names never discover pasted nodes by text equality; malformed,
  unresolved or ambiguous destinations refuse before writing.

Commands and edits keep the 512-Step maximum. A refusal is recoverable; it never
falls back to another editor.
