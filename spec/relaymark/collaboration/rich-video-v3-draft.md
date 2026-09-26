# Draft v3 video source mapping

This optional mapping extends the unregistered `relaymark-prosemirror-v3`
authored/default projection. It does not change live v1/v2 collaboration or
admit v3 editing.

The browser's `videoEmbed` node contains a durable `videoId` and hydrated
playback, title, source, thumbnail, status, YouTube ID, and upload-progress
fields. The portable AST stores only a stable block ID and canonical lowercase
UUID: `{id, type: "relay.video_embed", props: {videoId}, content: []}`. The
legacy Markdown directive remains `::video[/v/UUID]`. Media authorization and
playback metadata remain host-owned. The source projector accepts absent or
schema-default values for the hydrated fields, and rejects nondefault values,
unknown attributes, hidden children, or malformed IDs.

The [fixture](fixtures/rich-video-v3-draft.json) carries an actual Yjs update
produced with TipTap 3.30.5, a `videoEmbed` node matching the browser's
attribute schema, UniqueID using `relaymarkId`, and `@tiptap/y-tiptap` 3.0.9.
The [test](../../../test/collaboration-rich-video-v3-draft.test.js) checks the
XML, exact portable AST and inverse, schema validation, and rejection rules.
Swift and server read projectors consume the same update. Native playback and
live v3 admission remain separate work.
