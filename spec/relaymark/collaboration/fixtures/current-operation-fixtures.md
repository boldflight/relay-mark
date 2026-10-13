# Current-operation fixtures

`current-content-edit-*` are separately emitted canonical physical fixtures.
The original files without `current-` remain unchanged historical evidence.
Only tests of current operations select these new files; the historical formats
are not admitted by live runtime guards.

- Mutation fixtures come from independent Yjs XML edits after the maintained
  finite seed conversion. The production content-edit producer is not their
  generator. Tests retain the declared command, exact footprint, human-unit,
  source-identity and hidden-write rejection expectations.
- Metadata, repeated-input and owned-mark fixtures come from the existing live
  operation tests, including fixed Unicode text, preserved peer fields and
  exact source identities. Their optional emission now writes only current files.
- Manager fixtures run fresh commands through maintained Yjs UndoManagers after
  seed conversion. Original command intents and independently expected final
  text remain fixed. Manager isolation and wrong-group refusals remain tested.
- Native reviewed recovery comes from a new maintained Swift append, starting
  from the original portable authored AST. Its test fixes the expected rich text,
  checks peer replay and undo, and exports the actual update and step carrier.
  The JavaScript tests retain their independent 18-unit recovery expectations.

Run the following from the repository root only when deliberately refreshing
these current fixtures, then review their diffs and run the affected consumers:

```sh
RELAYMARK_WRITE_CURRENT_MUTATIONS=1 node --import ./scripts/prepare-test-yjs.mjs test/helpers/generate-current-mutation-fixtures.mjs
RELAYMARK_WRITE_CURRENT_MANAGERS=1 node --import ./scripts/prepare-test-yjs.mjs test/helpers/generate-current-manager-fixtures.mjs
RELAYMARK_WRITE_REPEATED_FIXTURE=1 RELAYMARK_WRITE_METADATA_FIXTURE=1 RELAYMARK_WRITE_OWNED_FIXTURE=1 node --import ./scripts/prepare-test-yjs.mjs --test test/content-edit-repeated-identity.test.js test/content-edit-metadata.test.js test/content-edit-owned-history.test.js
RELAY_CURRENT_REVIEWED_FIXTURE_OUTPUT="$PWD/spec/relaymark/collaboration/fixtures/current-content-edit-native-reviewed-recovery.json" xcrun swift test --filter RelayMarkNativeRecoveryBlocksTests/testCurrentReviewedRecoveryFixturePreservesRichAuthoredMeaning
```

Ordinary test runs do not emit fixture files. The deliberate value-only binding
fault in the witness test is now reproduced on a current seed, so the identity
guard is exercised instead of being masked by obsolete settings rejection.
