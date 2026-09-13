# Peer formatting after structural undo regression

Run `node scripts/probe-peer-format-after-split-undo.mjs > /tmp/peer-format-split-undo.json` from the repository root. The standalone probe runs the actual committed collaboration bundle with two independent Yjs owners and writes exact seed/update bytes, installed Yjs version, bundle hash, marker observations, and expected/actual paragraph deltas. It is outside default test discovery while the known defect remains unresolved.

On September 14, 2026, at source `8bd520a705706b0045d5a5888ccfec96d378bc86`, the probe exits 1: A splits `Hello`, B bolds both paragraphs, A undoes the split, then B undoes its formatting. A's structural undo correctly leaves bold `Hello`. B's formatting undo leaves plain `He` and bold `llo`; the asserted correct result is entirely plain `Hello`. Replicas converge after each operation. Existing raw-gap and placement-candidate controls pass; they do not establish complete formatting undo.

`performHistoryWithMarks` permits reversal on original `formattingTextItems` identities. Restored tail identities are absent from B's original target set. Placement receipt preparation/commit retains copy evidence separately, but history preparation does not consume an authenticated marker-transition relationship through those copies. The marker capture APIs expose exact marker witnesses; matching the current boolean mark alone cannot authorize a reversal after peer same-mark ABA. That counterpart remains unproved here.

This is a live in-process regression, not server admission, disk restart, native host, or full interoperability acceptance. It introduces no runtime remapping or activation. The correct expected result must remain unchanged when the implementation is repaired.
