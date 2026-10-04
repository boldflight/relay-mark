# Canonical authored video

The canonical `videoEmbed` XML/PM node has `relaymarkId` and `videoId` only;
portable AST is `relay.video_embed` with `props.videoId`. Playback provider,
processing status, progress, playback/YouTube IDs, title and thumbnail resolve
through the host's authorized media domain and view-only presentation storage.
They are not live document attributes. The shared emitter/validator and maintained
43-node editor schema agree on this shape.

The finite snapshot importer records `remove_attribute` for exact historic
presentation defaults (`source: "mux"`, `status: "ready"` and null playback/title/
thumbnail/YouTube/progress values). The original snapshot/update remains host
recovery evidence. Native `RelayMarkNativeSnapshotImport.prepare` returns exact
`originalState` and importer `result` without mutation; the host must preserve
both durably before `install`. Installation checks the same owner, exact original
state, vector and snapshot, then applies only the shared importer's recorded
attributes on the existing Yrs tree. It never rebuilds text/nodes or captures a
user undo command. Peer or hidden state changes refuse stale installation.

The original historical video fixture retains the same node/text anchors through
migration, then media-adjacent replacement uses actual maintained Steps and
converges with a peer. This is local library evidence, not deployed migration.

Nondefault historic media presentation attributes still require corpus/domain
classification. The importer currently refuses them with a domain-evidence
requirement rather than discarding potential meaning. The first-party web media
component documents these fields as server-hydrated presentation values; actual
stored exceptions, unresolved IDs and any truly authored metadata must be
verified by the host's media owner before broader finite normalization. Unknown
media remains an explicit migration gate, not completed conversion or a fallback.
