# Phase 10J — NubiBill Catalogue Release 4 Production Deployment Runbook

**Status: DEPLOYMENT CANDIDATE READY; PRODUCTION MIGRATION NOT EXECUTED.** O5 candidate `8e3658690ddb142717c7e9a75246a27fcb2bb877` passed the required sequential workspace suite (698 passed, 1 environment-gated legacy Phase 10I/10IB clone test skipped, exit 0). Production migration, another production DRY_RUN, `--execute`, database writes, Firestore, and network access remain prohibited in Phase 10O5.

## 0. Current go/no-go decision

**DEPLOYMENT CANDIDATE READY; PRODUCTION MIGRATION NOT EXECUTED.** `paired_backup_restore_rehearsed` is closed from isolated disposable copies. Candidate `8e3658690ddb142717c7e9a75246a27fcb2bb877` passed the sequential suite with 698 passed, 1 skipped, 0 failed, and exit code 0. The single skip is the legacy Phase 10I/10IB test gated on `PHASE10I_CLONE_DIR`; the required O5 command left all five `PHASE10I_*` variables unset. Current v4/R3 disposable-clone runner, CLI, and rollback cases passed in Phase 10M/N4 tests. Fresh read-only postflight at 2026-10-05T20:41:48Z matched both production DB hashes to their approved paired backups; all four integrity checks returned `ok`, with no sidecars or open handles. Phase 10F row-level migration and retirement approvals remain false; no historical remapping, cleanup, retirement, or backfill is authorized. No production migration or repeat production DRY_RUN is permitted in Phase 10O5.

1. Phase 10F/10L remains retention-only: row-level migration and retirement approvals remain false and no mappings are preapproved. The supplied O3 semantic approval is limited to conditional installation of the exact Release 4 catalogue under that policy; it grants no remapping, cleanup, retirement, or historical backfill. The 10 protected legacy queries remain unchanged.
2. Phase 10N4 records runner/clone validation and Phase 10N7 records a successful actual-production DRY_RUN (`GO`, exit 0) with query digest preservation. Phase 10O5 binds the reviewed implementation and test artifacts to its immutable candidate; it does not repeat the production DRY_RUN.
3. The supported `ProductionMigrationRunner` is present. The test-only `tool/refresh_system_catalogue_test.dart` remains prohibited against production. Phase 10O5 does not invoke either runner in execution mode and does not perform any production write.

This document supplies the gates and operator sequence for the controlled release. Any missing, stale, false, or unverified mandatory gate means STOP; conditional authorization does not bypass the checklist.

## 1. Authoritative evidence and immutable expectations

Evidence reviewed: Phase 10E Release 4 review/fixture; Phase 10F/F-B identity and migration plan; Phase 10H/H-B Product provenance contract; Phase 10G2 archive implementation; Phase 10I clone migration rehearsal; Phase 10IB new Product/Variant write closure; Phase 10IC full-suite verification.

| Item | Approved rehearsal expectation | Source/evidence |
| --- | --- | --- |
| Branch / Phase 10O5 candidate | `fix/product-master-audit` / `8e3658690ddb142717c7e9a75246a27fcb2bb877` (`release(product-master): bind Release 4 production candidate`) | Immutable candidate; full suite and artifact hashes are recorded in `phase10N6.md` |
| Account source path | `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db` | Phase 10I/10IC evidence; operator must independently identify production path |
| Public-config source path | `/Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db` | Phase 10I/10IC evidence; operator must independently identify production path |
| Account SHA-256 / bytes | `7751a6cc30a1f3765067bcec646beb16b0dc9dd094e1ccacd0d4d23e7e1515ef` / 9,744,384 | Phase 10I/10IC preimage; historical reference, not an assumed future preimage |
| Public-config SHA-256 / bytes | `a81b30213ada2f9fbb962eb4c55b5824545048cf0be534dcc12d591dc9c93693` / 937,984 | Phase 10I/10IC preimage; historical reference, not an assumed future preimage |
| Original schema / installed release | SQLite schema v3; active `PAINT_V1` data version 3 | Phase 10I clone preimage |
| Baseline businesses | 4 Products; 7 Variants; 195 sync-query rows; 10 protected legacy queries; 0 outbox rows | Phase 10I clone preimage. Counts are a reference only; exact current IDs/payloads must be captured and approved again |
| Phase 10F query digest | `311e4bd99435b5efb23d4f20192abc7677336169e6451787188f52e4e49fe303` | Phase 10F-B manifest. Reconfirm method and exact current baseline before using |
| Archive preimage | 3,903 eligible SYSTEM rows; legacy fingerprint `sha256:1557b7d098f0ae5f829853fb798c86152282af67776cbb525063e2055387e74b` | Phase 10I rehearsal. New production archive digest must be generated and approved from the exact fresh preimage/build; do not copy a run-specific digest from Phase 10IB |
| Release 4 | `PAINT_V1`; data version 4; schema revision 1; compiler revision 6; 137 canonical selectors; 137 READY forms | Phase 10E review/fixture and Phase 10I rehearsal |
| Expected full-snapshot fingerprint | `sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88` | Phase 10I/10IB clone evidence; must be independently revalidated against the exact approved artifact/build |

`docs/phase10f-migration-approval-manifest.json` remains unapproved for row-level migration, remapping, and retirement. The O3 approval supplies only the scoped conditional Release 4 installation decision; it does not alter Phase 10F action flags or target IDs. The Phase 10I/10IB results prove clone behavior, not individual historical mappings. The names/counts above are not substitutes for current logical preimage digests.

## 2. Roles, control window, and operational constraints

- **Release commander:** named human accountable for the window and GO/NO-GO decision.
- **Database operator:** freezes access, takes/validates paired backups, runs the approved local migration runner, and maintains the event log.
- **Independent verifier:** separately checks hashes, SQLite integrity, release/archive/business/query postconditions, and signs the evidence.
- **Business owner:** approves reference/retention decisions and any optional smoke Product/cleanup policy.
- **Application/sync owner:** confirms every client and background worker is stopped and remains stopped.

Use a maintenance window with a single account/public-config generation. Close the app on every client that can access these databases; stop and verify all background sync workers; disable automatic restart/update/open-on-login; prevent concurrent writable SQLite access. Keep maintenance mode active until the independent verifier signs every postcondition. Snapshot files must be staged and hash-verified before the window; do not fetch Firestore/HTTP data inside the migration transaction. This Phase 10J report itself made **zero Firestore requests and zero production writes**.

## 3. Part A — Predeployment GO gates (all required)

1. Confirm exact deployment branch/commit, signed build provenance, no unreviewed source/artifact change since the separately approved release decision, and complete tests green at that commit. Phase 10O5 evidence covers candidate `8e3658690ddb142717c7e9a75246a27fcb2bb877`; any later source or catalogue change requires a new candidate and a rerun.
2. Obtain signed approval for the complete migration action set. Resolve every Phase 10F/F-B blocker explicitly (identity mapping, retained historical metadata, query handling, template/attribute/option/unit references, Ceiling/Basement identities). No name similarity, “safe” label, zero cached refs, or test success constitutes approval.
3. Approve a precise source-to-target migration plan, exact artifact digests, executable reviewed migration runner, expected archive canonical digest, and rollback rehearsal. Confirm the runner's query behavior preserves all 195 full query rows exactly as required.
4. Confirm maintenance controls and operator/verifier/owner identities. Check no app clients or sync workers can reopen or write the DB.
5. Record source file sizes, mtimes, hashes, and sidecar state. Any `-wal`, `-shm`, or `-journal` file, open handle, unknown writer, or unexplained file state is **ABORT**; do not delete sidecars or checkpoint through ad hoc commands.
6. Run read-only `PRAGMA integrity_check` on both source databases and require exactly `ok`. Verify account schema `user_version=3`, active SYSTEM release marker `PAINT_V1`/version 3, Products=4, Variants=7, sync queries=195, protected queries=10, outbox=0 (or an explicitly approved refreshed preimage), plus approved canonical digests for Product/Variant rows, complete sync queries, and installed SYSTEM metadata.
7. Confirm source SHA-256 equals the newly approved preimage SHA-256. Historical Phase 10IC hashes in §1 are not a blanket approval for a changed production file.
8. Sign every section in `docs/phase10j-go-no-go-checklist.json`. Until then the result stays NO-GO.

For the Phase 10O5 workspace gate, run the complete suite at the exact candidate commit with all Phase 10I clone variables unset. The environment-gated Phase 10I/10IB test is expected to skip in this run; it pins an older schema-v3 clone preimage. Current v4/R3 clone migration, CLI, rollback, and failure-injection coverage ran through the Phase 10M/N4 tests against disposable databases. Never point clone variables or a test at original files.

```sh
env -u PHASE10I_CLONE_DIR -u PHASE10I_ACCOUNT_PROJECT -u PHASE10I_ACCOUNT_UID -u PHASE10I_CONFIG_PROJECT -u PHASE10I_CONFIG_UID flutter test --no-pub --timeout 5m --concurrency 1 --reporter compact
```

Require zero failures and exit code 0; record the expected environment-gated skip, `flutter analyze` severity counts, and `git diff --check`. O5 analysis found 0 errors, 5 warnings, and 42 informational findings; the warnings are in unchanged procurement UI files. The candidate runner/catalogue had no analyzer errors.

### Read-only preflight commands (macOS; review/substitute the approved paths)

These commands are documentation only and were **not run against production as part of Phase 10J**, apart from the read-only hash/metadata observation recorded in `phase10j.md`. They do not contact Firestore. They read only the main DB and abort if sidecars exist:

```sh
set -eu
ACCOUNT='/absolute/approved/path/account.db'
CONFIG='/absolute/approved/path/public-config.db'
for DB in "$ACCOUNT" "$CONFIG"; do
  test -f "$DB" || { echo "ABORT: missing $DB" >&2; exit 1; }
  for SUFFIX in -wal -shm -journal; do
    if test -e "$DB$SUFFIX"; then echo "ABORT: sidecar $DB$SUFFIX" >&2; exit 1; fi
  done
  stat -f '%z bytes | %Sm | %N' -t '%Y-%m-%d %H:%M:%S %z' "$DB"
  shasum -a 256 "$DB"
  sqlite3 -readonly "$DB" 'PRAGMA integrity_check;'
done
sqlite3 -readonly "$ACCOUNT" 'PRAGMA user_version;'
sqlite3 -readonly "$ACCOUNT" "SELECT COUNT(*) FROM local_products; SELECT COUNT(*) FROM local_product_variants; SELECT COUNT(*) FROM sync_queries; SELECT COUNT(*) FROM sync_outbox;"
sqlite3 -readonly "$ACCOUNT" "SELECT remoteId,payloadJson FROM local_product_catalogue_releases WHERE scopeType='SYSTEM' AND isDeleted=0 ORDER BY remoteId;"
sqlite3 -readonly "$ACCOUNT" "SELECT queryKey,collectionName,queryJson,active,cursor,lastSyncedAt,lastAttemptAt,lastError,catalogueVersion FROM sync_queries ORDER BY queryKey;"
```

Store stdout/stderr in the access-controlled deployment evidence directory; sanitize no source values before hashing. The exact preimage IDs/value digests must be exported by the approved read-only verifier, not inferred from counts. Use only `sqlite3 -readonly` for source reads.

## 4. Part B — Paired backup gate

After all writers are frozen and source checks pass, create one timestamped backup set on an approved encrypted volume with enough space and access controls. Do not put database files or backup material in the repository or general `/tmp`.

```sh
set -eu
ACCOUNT='/absolute/approved/path/account.db'
CONFIG='/absolute/approved/path/public-config.db'
BACKUP_ROOT='/absolute/approved/encrypted/backup/root'
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="$BACKUP_ROOT/phase10j-$STAMP"
mkdir -m 700 -p "$BACKUP_DIR"
cp -p "$ACCOUNT" "$BACKUP_DIR/account.db"
cp -p "$CONFIG" "$BACKUP_DIR/public-config.db"
chmod 600 "$BACKUP_DIR/account.db" "$BACKUP_DIR/public-config.db"
stat -f '%z bytes | %Sm | %N' -t '%Y-%m-%d %H:%M:%S %z' "$ACCOUNT" "$BACKUP_DIR/account.db" "$CONFIG" "$BACKUP_DIR/public-config.db"
shasum -a 256 "$ACCOUNT" "$BACKUP_DIR/account.db" "$CONFIG" "$BACKUP_DIR/public-config.db"
sqlite3 -readonly "$BACKUP_DIR/account.db" 'PRAGMA integrity_check;'
sqlite3 -readonly "$BACKUP_DIR/public-config.db" 'PRAGMA integrity_check;'
printf 'BACKUP_SET=%s\n' "$BACKUP_DIR"
```

Because the gate requires all writers stopped and no sidecars, each source/backup SHA-256 pair must match exactly. The account and public-config backups must share the same `$STAMP` directory and evidence record. Record backup path, hashes, sizes, mtimes, sidecar scan, integrity outputs, operator, verifier, and UTC time. Perform a restore-readability drill to a separate, non-production staging directory using copies of the backup files and `sqlite3 -readonly ... 'PRAGMA integrity_check;'`; verify the staging hashes against the backup hashes. Do not restore over production during this drill. No GO without both restore-readability results.

If an approved backup-generation process changes SQLite byte layout, it must not be silently substituted for `cp -p`; document its source consistency method, compare logical identity with the frozen source, and obtain fresh approval. Never mix account and public-config files from different timestamps.

## 5. Part C — Maintenance barrier and execution order (future, only after signed GO)

1. Announce maintenance mode. Stop all clients, scheduled jobs, sync workers and services. Confirm no open writable handles and no unknown process. Keep the barrier active through final sign-off.
2. Verify the exact approved source preimage and paired backup set again. Re-run read-only hashes, sizes/mtimes, sidecar scan and integrity checks. Require the release marker and all preimage digests still match the signed GO packet.
3. Stage and verify the approved Release 4 snapshot files and the separately approved migration plan/manifest. Require `PAINT_V1`, data version 4, schema revision 1, compiler revision 6, the reviewed 137-selector set, and the approved full-snapshot fingerprint. No network/Firestore calls are allowed in the local transaction.
4. **Runner available; execution remains gated:** `ProductionMigrationRunner` invokes the application-compatible database path and has clone/rollback validation recorded in Phase 10N4. This O5 candidate packet binds its exact source, fixture, and test hashes. Do not invoke `--execute` in Phase 10O5. Never use `tool/refresh_system_catalogue_test.dart` against production.
5. Under the approved runner only, open the account database through the real application migration path, apply the schema upgrade (v3→v4), retain legacy rows under the Phase 10L policy without automatic mapping/remap/cleanup/retirement/backfill, and install the approved Release 4 snapshot. Preserve exact source payload/document identities and all 195 sync-query rows. Keep the maintenance barrier active through the complete sequence and independent post-deployment verification.
6. Archive eligible exact current SYSTEM metadata using SHA-256 fingerprint and composite identity `(catalogueFingerprint, collection, documentId)`. Derive the exact old snapshot fingerprint from the installed preimage; archive document ID and decoded payload ID independently. Same-key/different-content is an immediate collision abort; no overwrite. Require 3,903 rows only if the freshly approved preimage has the Phase 10I row inventory; compare the archive canonical digest to the exact clone result produced for that signed preimage/build. Do not use a timestamp-bearing run digest from a different rehearsal as an expected constant.
7. Apply only explicitly approved and independently reviewed per-ID remaps/retention actions. Do not infer or backfill historical Product fingerprints. Preserve all historical Products with null provenance unless a separately approved semantic migration explicitly scopes otherwise.
8. Apply complete Release 4 snapshot reconciliation. Write the release marker/fingerprint last within the transaction. Commit only if every transaction invariant passes. Any thrown error or ambiguous commit result means hold maintenance, preserve the postimage, and establish transaction state before retry/rollback; never blindly rerun.
9. Do not execute an optional Product/Variant smoke test by default. It requires a separate written production-test approval, a unique controlled test identity, explicit outbox/network policy, and an approved cleanup or retention procedure. If not approved, create no test record.

### Migration command status

**Phase 10O5 execution prohibition.** A supported runner exists, but this phase must not invoke it with `--execute` or repeat the production dry-run. Any later production invocation requires a completed immutable GO packet, a fresh verified writer freeze, paired backups, all mandatory gates, the named operator, and independent post-deployment verification. Tests, dry-run evidence, and normal app launch are not interchangeable with that authorization.

## 6. Post-deployment acceptance checks (remain in maintenance mode)

Use the reviewed offline verifier bundled with the future approved build; raw SQL snippets below are read-only spot checks and do not replace canonical digest comparison. Every check must be captured by operator and independently repeated by verifier.

### Database, release, and selectors

- `PRAGMA integrity_check` returns exactly `ok`; schema `user_version` equals the app schema version 4.
- Exactly one active, non-deleted SYSTEM marker exists for `PAINT_V1`; data version=4, schema revision=1, compiler revision=6; `catalogueFingerprint` is valid `sha256:<64 lowercase hex>` and equals the approved Release 4 artifact fingerprint.
- All 137 approved canonical selector IDs match exactly as a set (no missing, extra, duplicate, legacy, BUSINESS, or retired identity is treated as a selector).
- Offline resolver reports 137/137 forms READY and validator accepts all forms using the exact Release 4 data.
- Archive contains exact before-images for the approved collections; for the Phase 10I preimage expected 3,903 rows, legacy fingerprint `sha256:1557b7d098f0ae5f829853fb798c86152282af67776cbb525063e2055387e74b`, and exact approved canonical-content digest. Document/payload IDs remain distinct where the source differs. No archive legacy row is exposed as a current selector.
- Import replay/no-op verification on an isolated clone is part of code readiness; do not replay a production import merely as a probe.

### Business data and historical provenance

- Product and Variant counts and full row digests match the approved preimage (rehearsal counts 4 and 7). Compare each original `remoteId`, `productId`, `variantId`, SKU, barcode, category/subcategory ID, attribute values, unit IDs and other payload fields; no changes or missing rows.
- Every pre-existing Product with unknown provenance remains `catalogueFingerprint=null`; its resolver status is `provenanceMissing`, never a Release 4 fallback. No Variant gets an independent token; Variant provenance remains via exact parent `productId`.
- Any difference in SKU/barcode uniqueness, soft-delete/inactive state, row payload, identity, or parent relation is an abort. No automatic repair.

### Sync and outbox

- Exactly 195 sync queries (or the signed, freshly measured baseline) remain. Compare the complete set and every `queryKey`, `queryJson`, `active`, `cursor`, `lastSyncedAt`, `lastAttemptAt`, `lastError`, and `catalogueVersion` to the frozen approved preimage. The 10 protected rows must match byte/logically exactly. No query reactivation and no surprise query registration/deletion.
- Outbox contents and digest equal the preimage (Phase 10I expected 0 rows). No migration/outbox write is expected.
- Important implementation gate: current snapshot importer updates some SYSTEM query tracking fields. If the approved implementation does not satisfy the no-change query invariant, abort; do not accept a matching row count as proof.

### Read-only SQL spot checks

```sh
sqlite3 -readonly "$ACCOUNT" 'PRAGMA integrity_check;'
sqlite3 -readonly "$ACCOUNT" 'PRAGMA user_version;'
sqlite3 -readonly "$ACCOUNT" "SELECT COUNT(*) FROM local_products; SELECT COUNT(*) FROM local_product_variants; SELECT COUNT(*) FROM sync_queries; SELECT COUNT(*) FROM sync_outbox;"
sqlite3 -readonly "$ACCOUNT" "SELECT remoteId,payloadJson FROM local_product_catalogue_releases WHERE scopeType='SYSTEM' AND isDeleted=0 ORDER BY remoteId;"
sqlite3 -readonly "$ACCOUNT" "SELECT queryKey,collectionName,queryJson,active,cursor,lastSyncedAt,lastAttemptAt,lastError,catalogueVersion FROM sync_queries ORDER BY queryKey;"
```

The full `payloadJson` exports contain business data; store them only in the approved encrypted evidence location with least-privilege access.

## 7. Abort conditions

Abort before mutation or stop immediately under maintenance if any of the following occurs:

- Any approval/checklist item is NO, blank, unsigned, stale, or lacks a named independent verifier.
- Phase 10F identity/reference blockers remain, an unapproved action appears in the candidate plan, or an unresolved mandatory reference remains.
- Branch/build/artifact digest differs from the approved packet; tests are not green for the exact deployment commit; code or catalogue content changed after review.
- Any source/preimage hash, size policy, schema version, marker, row count, Product/Variant/query/outbox/archive baseline digest mismatch.
- `integrity_check` is not exactly `ok`; sidecar exists unexpectedly; WAL/journal is non-empty/unexplained; unknown process, open writer, or application/sync process is detected.
- Snapshot incomplete, fingerprint malformed/mismatched, selector count/set differs from 137, any form is not READY/valid, any archive collision or identity mismatch exists.
- Any Product/Variant/protected-query/query/outbox value changes outside the signed plan; query reactivation occurs; any local transaction is partially committed or commit result cannot be proven.
- Any Firestore/network access is observed during this local migration; any attempt to fetch snapshot inside the transaction; any optional smoke write lacks separate approval.

On abort: keep maintenance active, stop retries, preserve the failed postimage and logs separately, notify release commander and verifier, and choose the rollback procedure only after DB handles are closed and consistency state is known.

## 8. Rollback runbook

Rollback is a paired database restore, not a reverse Release 4 import. It is mandatory on any acceptance failure unless the incident commander and data owner approve a different forensic plan.

1. Keep every app client and sync worker frozen. Disable automatic restart. Record timestamp, operator, exact trigger, last acknowledged transaction stage, build/runner/snapshot hashes, logs and observed remote/network status.
2. Stop the runner and close all app, SQLite, sync and maintenance handles. Verify no writer remains. Do not delete WAL/SHM/journal files; preserve any sidecars with the failed postimage for forensic review.
3. Create a separate, access-controlled forensic copy of the failed account DB, public-config DB, and any sidecars; hash and inventory it. Never overwrite this evidence.
4. Verify the selected paired backup set has one timestamp/backup ID; source and backup hashes were recorded; both backup `integrity_check` results were `ok`; and the restore-readability drill passed. If either backup is missing, mismatched, unreadable, or from a different generation, **do not restore or resume**—escalate for forensic recovery.
5. Restore both account and public-config from that same verified backup set to staging first. Hash staging copies against backup hashes; run `PRAGMA integrity_check` on both; confirm schema/release marker, Product/Variant identities and payload digests, complete sync-query digest, and outbox digest equal the approved preimage. Ensure staging SQLite handles are closed.
6. With explicit rollback authorization recorded, use the journaled `tool/paired_database_restore.py` procedure in §8.6 while all writers remain frozen. The two-file pair is not atomic: each target is replaced separately by a same-directory atomic rename and a durable manifest makes interruption recovery deterministic. Never copy just one DB and resume.
7. Re-run read-only hashes, sizes/mtime, sidecar scan, integrity checks, release marker, Product/Variant/SKU/barcode digest, all 195 query rows/10 protected queries, and outbox checks on the restored pair. Require exact preimage logical identity—not merely expected counts—before resuming.
8. If any restored value differs or a sidecar/handle is unexplained, do not reopen the app. Preserve state and escalate.
9. Resume app writers only after release commander, database operator, independent verifier and business owner sign the rollback record. Record operator, reason, backup ID, source/restore hashes and verification outputs. Keep failed postimage for the retention period.

### 8.6. Paired restore utility contract and crash recovery

The named utility is `tool/paired_database_restore.py`, implemented with Python standard-library SQLite and filesystem APIs. It has no default production paths and accepts both backup paths, both expected SHA-256 hashes, both target paths, a manifest path, a forensic directory, a non-empty maintenance acknowledgement, and a named rollback authority. Use only the exact approved backup pair and an operation-specific manifest path on durable local storage.

Before writing `PREPARED`, the utility verifies both backup hashes and SQLite integrity; requires both targets to be regular, distinct files owned by the operator; checks zero target `-wal`, `-shm`, and `-journal` sidecars and zero exact-path handles with `lsof`; requires an operator-owned mode-0700 forensic directory; preserves separately hashed mode-0600 postimage forensic copies; stages both backups as mode-0600 files in their respective target directories; fsyncs staged files and directories where supported; and verifies both target preimage hashes remained stable. It atomically persists the manifest before any replacement. Original failed-postimage forensic files are never deleted by the utility.

Example command shape (substitute reviewed exact absolute paths and hashes; this is not authorization to run it against production):

```sh
python3 tool/paired_database_restore.py restore \\
  --account-backup "$BACKUP_DIR/account-production.db" \\
  --account-sha256 "$ACCOUNT_BACKUP_SHA256" \\
  --config-backup "$BACKUP_DIR/public-config-production.db" \\
  --config-sha256 "$CONFIG_BACKUP_SHA256" \\
  --account-target "$ACCOUNT_DB" \\
  --config-target "$PUBLIC_CONFIG_DB" \\
  --manifest "$RESTRICTED_EVIDENCE_DIR/paired-restore-manifest.json" \\
  --forensic-dir "$RESTRICTED_EVIDENCE_DIR/failed-postimages" \\
  --maintenance-ack "All clients/workers stopped; maintenance remains active through independent verification" \\
  --rollback-authority "ROLLBACK_AUTHORITY_NAME"
```

The manifest schema (version 1) records the operation ID; both target, backup, staging, and forensic paths; original target and expected backup hashes; replacement progress; per-database and pair verification; maintenance acknowledgement; rollback authority; published file mode (`0600`); timestamped events; error; and final status. `pairAtomicityClaimed` is false. Each target file is replaced by same-directory `os.replace`; the pair itself is never claimed atomic. The restored target inode is owned by the operator and mode `0600`; before any later app restart, the independent verifier must confirm the application database runtime uses that same owner and can access both files. The utility does not chmod or chown production targets.

State transitions are durable and monotonic: `PREPARED` means both stages and forensic copies are verified and durable; `ACCOUNT_REPLACED` means the account hash matches its approved backup; `CONFIG_REPLACED` means both target hashes match; `VERIFIED` means both exact hashes and both `PRAGMA integrity_check` results pass with no target sidecars/handles; `COMPLETE` is written only after `VERIFIED`. An unexpected target/stage hash, missing pair member, inconsistent manifest, sidecar, handle, or verification failure fails closed as `RECOVERY_REQUIRED` when the manifest can be safely written. An unreadable manifest also fails closed.

Persisted intent precedes each file replacement and the replacement outcome follows it. If the process stops before any replacement, recovery rechecks both target hashes and continues from `PREPARED`. If it stops after account replacement, recovery recognizes the exact account backup hash and replaces public-config only. If public-config was replaced before its outcome state was journaled, recovery recognizes both approved hashes and verifies the pair. If interrupted during verification, recovery repeats both hash and integrity checks. It never trusts a state label without comparing on-disk hashes. A hash matching neither the recorded pre-restore value nor the approved backup causes `RECOVERY_REQUIRED`; do not edit the manifest or replace either file manually. Resume only with maintenance active and the named authority supplied again:

```sh
python3 tool/paired_database_restore.py recover \\
  --manifest "$RESTRICTED_EVIDENCE_DIR/paired-restore-manifest.json" \\
  --maintenance-ack "Maintenance remains active through independent verification" \\
  --rollback-authority "ROLLBACK_AUTHORITY_NAME"
```

Rollback is `COMPLETE` only when account and public-config hashes exactly match the approved backup hashes, both integrity checks return exactly `ok`, both replacement progress flags are true, pair verification is PASS, and no target sidecars or exact-path handles exist. `COMPLETE` does not permit app restart by itself. Keep clients, workers, schedulers, and automatic restarts stopped until the independent verifier and named rollback/release authorities verify the operation ID, hashes, logical preimage identity, integrity outputs, file owner/mode, and application access and sign the rollback record. On `RECOVERY_REQUIRED` or any mismatch, preserve the manifest, current files, logs, and postimage forensics; maintain the freeze and escalate. Never delete forensic copies during recovery.

## 9. Optional production Product smoke test

Default: **NO SMOKE PRODUCT**. Do not create a production test record unless business owner and release commander have explicitly authorized it in writing before the window. Approval must specify exact tenant/business, identity fields, SKU/barcode strategy, local-only/network policy, outbox disposition, retention/cleanup owner and tested deletion procedure. If approved, execute only after all database checks and before leaving maintenance mode; verify Product fingerprint equals the approved Release 4 marker, outbox payload matches, Variant references exact Product, no independent Variant fingerprint exists, validator/read-back pass, and uniqueness holds. Do not invent cleanup after the fact. If cleanup semantics are not approved, do not create the smoke record.

## 10. Operator command boundary

Read-only source checks, integrity, metadata and paired `cp -p` backup commands are provided above. Phase 10O5 creates/verifies the candidate and runs its sequential workspace suite; it must not run a production migration or repeat the production dry-run. Never use a test command as a production migration command. Do not supply secrets in command arguments or logs.
