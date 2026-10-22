# Phase 10L.1 — Phase 10K fixture regression closure

**Phase:** `PHASE_10L_FINAL_REGRESSION_CLOSURE`
**Scope:** Test fixture/setup correction only. No runner, migration, retention-policy, application architecture, or production data changes.

## Finding and correction

`test/phase10k_production_migration_runner_test.dart` `setUp` copies the database from the external source path `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db` into a per-test temporary directory, then uses that copy for all runner tests. The source had advanced to SQLite `user_version=4`, while the runner correctly requires a version-3 pre-migration source. The v4-only `local_catalogue_archive` table was empty in the copied preimage.

Added fixture setup helper `restoreVersion3Preimage` in the Phase 10K test file. Immediately after copying, it operates only on the temporary account clone: verifies any v4 archive table is empty, drops that v4-only table, sets `PRAGMA user_version=3`, and asserts both the version and absence of the archive table before computing fixture hashes. It fails closed for unexpected non-v3/non-v4 versions. The external source, backup, and public-config files are not opened for writes; runner execution tests use the temporary clone.

The production runner and its `schemaVersion != 3` rejection guard were not changed. No Release 4 migration semantics, retention policy, Phase 10L approval manifest, production application files, or sync-query definitions were changed for this correction. No Firestore access occurred.

## Verification

- Phase 10K test file: **16 passed, 0 failed, 0 skipped**. This includes dry-run, disposable-clone execution/idempotency, rollback, and negative safety tests.
- `flutter analyze test/phase10k_production_migration_runner_test.dart`: **No issues found**.
- `git diff --check`: **passed**.
- Runner source unchanged; the version-3 guard remains in place.
- Full workspace Flutter suite: **683 passed, 1 failed, 1 skipped**. The remaining failure is `test/phase10j_runbook_gate_test.dart`, whose test still expects the Phase 10F manifest status `BLOCKED_PENDING_EXPLICIT_REVIEW_AND_APPROVAL`; the existing manifest currently says `RETENTION_POLICY_APPROVED_EXECUTION_BLOCKED` following Phase 10L. This is unrelated to Phase 10K fixture drift. The one workspace skip is outside the Phase 10K file; Phase 10K had no skipped tests.

## Closure status

The seven Phase 10K fixture-drift regressions are fixed and all 16 Phase 10K tests pass. The requested whole-workspace zero-failure criterion is **not met** because of the stale Phase 10J manifest-status expectation. That test was not altered: updating it would exceed the requested fixture-only scope, and changing the Phase 10L manifest was expressly prohibited. A separate, explicitly scoped Phase 10J governance-test update is needed to make the full workspace suite green.

No production database writes, Release 4 production install, production migration, Product/Variant writes, sync-query changes, or Firestore operations were performed.
