# Phase 10N — Schema-v4 / Release-3 runner compatibility

**Phase:** `PHASE_10M_B_SCHEMA4_RELEASE3_COMPATIBILITY`
**Scope:** Determine the exact LocalDatabase v3-to-v4 schema change, add fail-closed support for the verified current v4/R3 preimage, and rehearse only against disposable clones. Production was not migrated.

## Schema-drift forensic finding

`LocalDatabase.schemaVersion` is 4. Its `migrate(db, old, next)` has an `old < 4 && next >= 4` branch which calls only `CatalogueArchiveStore.createSchema(db)`. This is the legacy catalogue archive/provenance schema addition. The v3-to-v4 migration does not load or import a catalogue snapshot, does not set a catalogue marker, and does not enumerate/archive any catalogue rows. The table starts empty.

A disposable v3-schema clone was compared before and after invoking that exact migration branch. The object diff is:

| Object change | Result |
|---|---|
| Created table | `local_catalogue_archive` with columns `catalogueFingerprint`, `collection`, `documentId`, `payloadId`, `payloadJson`, `canonicalContent`, `archivedAt`; composite primary key `(catalogueFingerprint, collection, documentId)` |
| Created index | SQLite primary-key autoindex `sqlite_autoindex_local_catalogue_archive_1` |
| Dropped tables/indexes/triggers | None |
| Altered existing tables/columns/indexes/triggers | None |
| Schema metadata | `PRAGMA user_version` advances from 3 to 4 (normally performed by the SQLite open/upgrade wrapper after migration returns) |
| Existing table rows | All preserved exactly in the migration test |

The verified v3 and v4 full `sqlite_master` signatures are pinned in the runner (`ccd6c9a5…d492a` and `3996e1e7…bf18d18`, respectively). The v3-to-v4 change is therefore application-schema-only. It explains the observed user_version=4 while the active SYSTEM catalogue remains `PAINT_V1` Release 3. It does not install Release 4, archive rows automatically, or rewrite Products, Variants, sync queries, markers, or outbox. The observed v4/R3 state is an expected pre-Release-4 state, but migration is permitted only for the exact pinned preimage contract below.

## Exact schema-v4 / Release-3 acceptance contract

The runner accepts the current v4/R3 migration source only when all of the following match:

- Account SHA-256 `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` and public-config SHA-256 `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289`.
- Account and public-config integrity checks are exactly `ok`; both read-only connections enable and verify `query_only=1`.
- `user_version=4` and the complete `sqlite_master` schema signature matches the reviewed v4 signature.
- The archive table has the reviewed exact DDL; it exists and has zero rows in both databases.
- Exactly one active SYSTEM marker exists: `PAINT_V1`, catalogue version 3; no installed Release 4 marker exists.
- Account has exactly 4 Products, 7 Variants, 195 sync queries, 10 protected query keys, 0 outbox rows, and 3,903 eligible legacy SYSTEM catalogue rows with the approved legacy fingerprint.
- There are no account or public-config `-wal`, `-shm`, or `-journal` sidecars. Sidecars are checked before and after inspection.
- Runner expectation constants for Products/Variants/query/protected/outbox/archive row counts and legacy fingerprint equal the approved values.

Any byte hash mismatch, unknown schema object, unexpected archive DDL/row, marker/version mismatch, altered count/query state, failed integrity check, or sidecar causes an abort. A schema-v4 Release-4 database is not treated as a migration source. The existing matching Release 4 state can return `ALREADY_INSTALLED` only after its release marker, full v4 schema signature, archive row count, and business/sync counts are validated.

Immediately before applying writes, the transaction re-reads and compares the exact stable Product, Variant, sync-query, outbox, and active SYSTEM release-marker rows to the read-only preflight snapshots. Any difference aborts rather than relying on counts alone.

Schema v3 remains supported only with its explicit schema signature and Release 3 migration-source marker. The runner does not accept arbitrary v3/v4 structures based on `user_version` alone. For a verified v4/R3 source, execution validates the existing archive table and skips redundant `CREATE TABLE`; v3 execution creates the archive table transactionally and checks the resulting v4 schema signature before importing.

## Disposable-clone rehearsals

Byte copies were made from the current account/public-config/backup files. Before any writable SQLite use, clone account/public-config hashes matched the preflight hashes exactly. Dry-run ran on a fresh clone; execute ran only on a separate child clone with a disposable child backup.

- Clone dry-run: **GO**, exact v4/R3 preimage accepted, zero writes, source clone hash unchanged.
- Clone execute: **SUCCESS**; existing empty archive table retained, 3,903 Release 3 rows archived once, Release 4 installed with fingerprint `sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88`.
- Selectors/forms: **137/137 selectors** and **137/137 READY forms** verified.
- Products/Variants: **4/4 Products** and **7/7 Variants** unchanged.
- Sync state: **195/195 queries** and **10/10 protected queries** unchanged; outbox remained at 0 and unchanged.
- Archive: 3,903 rows with the approved legacy fingerprint; exactly one migration insert pass.
- Historical null provenance: all legacy Product records without a fingerprint remained fail-closed through the historical resolver checks.
- Idempotence: a second execute invocation returned **`ALREADY_INSTALLED`**, with unchanged database hash, archive rows, Products, Variants, queries, and outbox.
- Rollback: injected failures after archive insertion and after Release 4 marker staging both aborted the disposable transaction. All captured table rows, including Products, Variants, all sync queries, outbox, release marker, catalogue rows, and archive, matched the preimage; archive returned to 0, Release 3 remained installed, user_version remained 4, and integrity checks returned `ok`.

## Fail-closed tests

Disposable-clone negative tests cover schema-v4 with a non-empty archive, unexpected schema object, changed Product/Variant/query counts (which also invalidate the pinned hash), wrong account SHA, an active sidecar, a structurally corrupted database whose integrity check fails, and unknown `user_version=5`. All were rejected before migration. The Release-4 rerun test verifies the already-installed path is no-op only, not a migration source.

## Validation

- Phase 10K/10M runner test file, rerun after the exact transaction-preimage guard: **21 passed, 0 failed**.
- Phase 10M-only schema forensics and v4/R3 clone tests: **5 passed, 0 failed**.
- Changed-file analyzer (`flutter analyze lib/data/migration/production_migration_runner.dart test/phase10k_production_migration_runner_test.dart`): **No issues found**.
- Workspace analyzer: **48 repository-wide info/warning findings, 0 errors**; none are in the two changed files.
- Full sequential workspace test suite reached **689 passed, 1 skipped**, and printed **“All other tests passed!”**; however, its terminal ended abnormally before a normal command completion/exit code was captured. Treat this as incomplete full-suite validation, not a verified successful exit. No test failure was reported in the captured output.
- `git diff --check`: passed.

## Production and network safety

No production database was opened writable or changed. No new production backup, production dry-run, or production `--execute` was run. No Product/Variant production mutation occurred. No Firestore or remote service was accessed. Production hashes were rechecked after validation and remain equal to the Phase 10M preflight values (account `2a0474f4…b7122fa8`; public-config `9b9e4d0a…e0590289`); no production SQLite sidecars are present. Phase 11 was not started.

| Production source | Before this phase | After clone rehearsals | Size | Result |
|---|---|---|---:|---|
| Account DB | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | 9,748,480 bytes | Unchanged |
| Public-config DB | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | 946,176 bytes | Unchanged |

Account and public-config `-wal`, `-shm`, and `-journal` sidecars remained absent after validation.
