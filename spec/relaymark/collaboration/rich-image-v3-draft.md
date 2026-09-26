# Draft v3 image source mapping

This optional mapping extends the unregistered `relaymark-prosemirror-v3`
authored/default projection. It uses the existing TipTap block image node and
the community `@tiptap/y-tiptap` XML binding. It does not enable live v3
admission or change v1/v2 documents.

An image XML element needs a stable `relaymarkId`. Its normalized ProseMirror
attributes are `src`, nullable `alt`, nullable `title`, and null `width` and
`height`. The portable AST block is `image` with the same ID, no children, and
`props: {src, alt, title}`. Only durable `/m/ID` host media references or HTTPS
URLs are accepted. Temporary `blob:`/`data:` previews, insecure or credentialed
URLs, upload progress, playback/processing state, and dimensions do not enter
the portable source. The host still authorizes and resolves media access.

The [fixture](fixtures/rich-image-v3-draft.json) is an actual Yjs update from
TipTap 3.30.5 PaperImage, UniqueID, and `@tiptap/y-tiptap`, with a paragraph on
each side. The [test](../../../test/collaboration-rich-image-v3-draft.test.js)
checks the Yjs XML, normalized ProseMirror JSON, AST validation, exact inverse,
and rejection of temporary media or hidden content. The native YSwift/Yrs read
projector and Phoenix/Yex projector replay the same update to that exact AST.
This is a source-contract proof only; native image presentation/editing, browser
admission, device interaction, and mixed-client live recovery remain gated.
