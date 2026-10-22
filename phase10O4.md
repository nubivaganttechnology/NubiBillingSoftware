# Phase 10O4 - Paired Database Rollback Procedure and Rehearsal

## Disposition

**ROLLBACK_GATE_CLOSED. Overall deployment remains STOP.** The paired restore utility and recovery procedure passed disposable rehearsal. `approved_branch_commit` and `full_tests_green_at_deployment_commit` remain NO; this phase did not create a candidate commit or run a post-commit full suite. Production migration, production DRY_RUN, and `--execute` remain prohibited.

## Restore Strategy and Utility

The named utility is [tool/paired_database_restore.py](tool/paired_database_restore.py). It uses a journaled pair operation with same-directory staged files and an individual atomic `os.replace` for each target. The pair is **not atomic**. A durable manifest records intents and results; recovery compares on-disk hashes with the recorded pre-restore hashes and exact approved backup hashes and never guesses.

The utility requires explicit backup paths and expected hashes for both members, explicit account/config target paths, a manifest path, a forensic directory, a non-empty maintenance acknowledgement, and a named rollback authority. It checks both backup hashes and SQLite integrity before staging; rejects symlink/non-regular/shared paths and targets not owned by the operator; checks exact target sidecars and `lsof` handles before replacement; requires an operator-owned mode-0700 forensic directory; writes staged and forensic files mode 0600; fsyncs staged files and directories where supported; and preserves separately hashed target postimages before mutation. It never deletes those forensic copies. The restored target files are owned by the operator and mode 0600; an independent verifier must confirm the application runtime uses that owner and can access both files before any app restart. O4 did not change production permissions.

The exact command and recovery-command shapes are documented in runbook §8.6 in [docs/phase10j-production-deployment-runbook.md](docs/phase10j-production-deployment-runbook.md).

## Manifest State Machine

Manifest schema version 1 records operation ID, both target/backup/staging/forensic paths, original target hashes, expected backup hashes, replacement progress, verification results, maintenance acknowledgement, rollback authority, timestamped events, errors, and final state. `pairAtomicityClaimed` is false.

- `PREPARED`: both backup stages and both forensic preimages are verified and durable; no target replacement has started.
- `ACCOUNT_REPLACED`: account target hash equals its approved backup hash.
- `CONFIG_REPLACED`: both target hashes equal their approved backup hashes.
- `VERIFIED`: both hashes and both SQLite integrity checks pass, with no target sidecars or exact-path handles.
- `COMPLETE`: written only after `VERIFIED`; app restart is still prohibited pending independent verification.
- `RECOVERY_REQUIRED`: any unknown target/stage hash, inconsistent manifest, sidecar, handle, or failed verification; stop and preserve evidence, do not resume automatically.

A crash before replacement resumes from `PREPARED`. After account replacement, recovery recognizes the account backup hash and replaces only config. After config replacement but before its state update, recovery recognizes both approved hashes and verifies the pair. An interruption during verification repeats both checks. Recovery uses the persisted manifest and target hashes; it never infers completion from a state label alone.

## Disposable Rehearsal

Root: `/tmp/nubibill-o4.Jfht00` (created mode 700; target, backup, forensic, and journal subdirectories mode 700). The targets were copies of both production-shaped databases; the approved backup files were separately copied into the isolated rehearsal root. A rehearsal-only marker was added to each disposable target to create valid failed-postimage clones. All restore writes occurred under this temporary root; no production target path was supplied to the utility.

- Operation ID: `92cbf0d057e24f3290c069ab39356af4`
- Manifest: `/tmp/nubibill-o4.Jfht00/journal/restore-manifest.json`
- Final manifest: `COMPLETE`
- Account target SHA-256: `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8`
- Public-config target SHA-256: `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289`
- Both rehearsal backup-copy hashes matched their approved values; both final target integrity checks returned `ok`.
- Manifest replacement progress: account `true`, public-config `true`; account/config/pair verification: `PASS`.
- Published file mode: `0600`; forensic directory mode: `0700`; both original disposable target postimages were preserved as mode-0600 files and match their manifest preimage hashes.
- No rehearsal target sidecars or exact-path open handles remained; no application was launched.

## Crash and Negative Tests

The focused restore suite passed **11/11**. Each required crash point used a child process terminated with exit 86, followed by the utility's `recover` CLI in a fresh process from the persisted manifest; all four recovered to `COMPLETE` with the approved pair:

- After `PREPARED`, before either replacement.
- After account rename, before its outcome state and before config replacement.
- After config rename, before its outcome state and final verification.
- During pair verification.

Negative tests fail closed for wrong account hash, wrong public-config hash, corrupt staged copy, SQLite sidecar, open exact-path handle, missing maintenance acknowledgement, insecure forensic-directory permissions, filesystem/manifest target-hash mismatch, missing backup member, and manifest missing a pair member. The `lsof` test also detected a real open exact-path descriptor. A filesystem/manifest mismatch records `RECOVERY_REQUIRED` and automatic recovery refuses to continue.

Governance/runbook tests passed **5/5**. They assert the paired gate is YES, the final deployment decision remains STOP, and production execution remains prohibited.

## Checklist and Runbook

Runbook §8.6 names the utility and documents explicit command forms, forensic preservation, non-atomic pair semantics, manifest fields, every state, crash reconciliation, fail-closed behavior, exact COMPLETE conditions, and independent approval before app restart.

The checklist now records `paired_backup_restore_rehearsed: YES` with the final operation ID, manifest, hashes, integrity, restrictive modes, forensic preservation, and crash/negative test evidence. `approved_branch_commit` and `full_tests_green_at_deployment_commit` remain NO. Overall checklist decision remains STOP; no production GO is implied by the rollback rehearsal.

## Read-Only Production and Backup Postflight

Checked at `2026-10-05T20:12:22Z` (2026-10-06 local):

| File | SHA-256 | Integrity |
| --- | --- | --- |
| Production account DB | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | `ok` |
| Production public-config DB | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | `ok` |
| Approved account backup | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | `ok` |
| Approved public-config backup | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | `ok` |

No production sidecars or exact-path handles were found. Source and backup hashes are unchanged and equal. Production databases were inspected read-only; no production file was written, copied over, renamed, replaced, moved, chmodded, or chowned. No Firestore or network service was accessed. No process was killed. No production migration DRY_RUN or `--execute` was run.

## Final Decision

**Rollback gate: CLOSED. Overall deployment: STOP.** The exact remaining blockers are candidate commit approval/binding and a green full test suite at that deployment commit. They are intentionally deferred to a later phase; no commit was created here.
