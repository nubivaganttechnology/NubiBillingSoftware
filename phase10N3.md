# Phase 10N3 — Production Backup and Dry-Run Retry

**Status: BACKUP AND RESTORE-READABILITY GATES PASSED; DRY-RUN BLOCKED BEFORE RUNNER START. Overall result: NO-GO / INCOMPLETE.** A fresh paired backup was created and verified under the explicitly approved root. The supported CLI invocation failed while compiling Flutter SDK sources; the runner emitted no JSON and never reached its application logic. No migration was executed. Do not treat this as a successful dry-run or deployment GO.

## Authorization and maintenance

- Operator authorization: GO for the limited backup-and-dry-run phase, with execution expressly prohibited.
- Operator maintenance confirmation: **acknowledged** and treated as confirmation that NubiBill/Flutter app instances, background sync workers, and scheduled jobs were stopped.
- Approved encrypted backup root: `/Users/sksuman/StudioProjects/backup`.
- FileVault: **On** at preflight; backup root is on the FileVault-protected startup/data volume.
- Backup root permissions were set to `drwx------` (mode 700); backup files were set to mode 600.
- Preflight found no open handles for either exact production DB path and no `-wal`, `-shm`, or `-journal` sidecars.

## Sources and approved preimage

| Database | Production path | Source size | Source mtime | Approved / preflight SHA-256 |
| --- | --- | ---: | --- | --- |
| Account | `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db` | 9,748,480 bytes | 2026-10-05 17:20:34 +0530 | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` |
| Public-config | `/Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db` | 946,176 bytes | 2026-10-05 17:03:13 +0530 | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` |

Both preflight hashes matched the approved current preimage before copying. The operator confirmation was accepted as the maintenance freeze; independently, the exact-path handle and sidecar checks passed.

## Fresh paired backup set

Created at 2026-10-05T14:19:29Z:

- Set directory: `/Users/sksuman/StudioProjects/backup/nubibill-release4-20261005T141929Z`
- Account copy: `/Users/sksuman/StudioProjects/backup/nubibill-release4-20261005T141929Z/account-production.db`
- Public-config copy: `/Users/sksuman/StudioProjects/backup/nubibill-release4-20261005T141929Z/public-config-production.db`

| File | Size | SHA-256 | Source/copy comparison |
| --- | ---: | --- | --- |
| Account source | 9,748,480 bytes | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | — |
| Account backup | 9,748,480 bytes | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | Exact match |
| Public-config source | 946,176 bytes | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | — |
| Public-config backup | 946,176 bytes | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | Exact match |

Both backup files were fresh byte-for-byte copies; no prior set was overwritten.

## Backup integrity and preimage checks

Checks were performed against the fresh backup files using SQLite read-only connections and `PRAGMA query_only=ON` where queried. No backup file was modified.

| Check | Account backup | Public-config backup |
| --- | --- | --- |
| `PRAGMA integrity_check` | `ok` | `ok` |
| `PRAGMA user_version` | 4 | 4 |
| Catalogue archive rows | 0 | 0 |
| Active SYSTEM release rows | PAINT_V1, catalogueVersion 3 (Release 3) | 0 release rows (public-config contract) |
| Products | 4 | 0 (not applicable to config DB) |
| Variants | 7 | 0 (not applicable to config DB) |
| Sync queries | 195 | 1 (not applicable to account query-count gate) |
| Protected queries | 10 | Not applicable |
| Outbox | 0 | 0 |

The approved expectations for legacy eligible catalogue rows (3,903) and the target Release 4 fingerprint were supplied to the runner invocation, but the runner did not start. Those runner-derived checks therefore remain unverified in this phase.

## Restore-readability drill

Created isolated disposable copies at 2026-10-05T14:21:06Z:

- Drill directory: `/Users/sksuman/StudioProjects/backup/restore-readability-20261005T142106Z`
- Account disposable copy: `/Users/sksuman/StudioProjects/backup/restore-readability-20261005T142106Z/account-production.db`
- Public-config disposable copy: `/Users/sksuman/StudioProjects/backup/restore-readability-20261005T142106Z/public-config-production.db`

Before opening, both disposable SHA-256 values matched their corresponding fresh backups exactly. Each copy was then opened read-only with `PRAGMA query_only=ON`; query-only returned 1. Both returned integrity `ok` and schema version 4. The account copy returned archive 0, active PAINT_V1 catalogueVersion 3, Products 4, Variants 7, sync queries 195, protected queries 10, and outbox 0. The public-config copy returned archive 0 and release rows 0. The production source files were not used for this drill. The fresh backup hashes were rechecked afterward and remained unchanged.

## Production dry-run attempt

Exact runner command invoked (no `--execute` or destructive flag):

```sh
dart run bin/production_migration_runner.dart --database /Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db --expected-account-sha 2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8 --public-config /Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db --expected-public-config-sha 9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289 --release-fingerprint sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88 --json
```

- Shell exit code from `dart run`: **254**.
- JSON result: **none emitted**; compilation failed before runner startup, so there is no `mode`, `success`, or `result` JSON to report.
- Captured compiler diagnostics included Flutter SDK errors such as `'Offset' isn't a type`, `'PointerDeviceKind' isn't a type`, and `clampDouble` not being defined in Flutter gesture sources. Thus the production database preflight was not performed by the runner and no runner GO was obtained.
- Dry-run decision: **NO-GO / NOT COMPLETED**, not a runner-produced NO_GO classification.
- Per the strict stop conditions, the CLI was not retried after its nonzero exit.

## Postflight and write/network boundary

Postflight at 2026-10-05T14:22:27Z:

| Check | Result |
| --- | --- |
| Account source SHA-256 | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` — unchanged |
| Public-config source SHA-256 | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` — unchanged |
| Production SQLite sidecars | None observed |
| Exact production DB handles | None observed for either source path |
| Production writes / migration execution | Zero; `--execute` was not supplied, and the CLI failed before runner startup |
| Firestore / application network access | Zero; the runner did not start and no application database migration or Firestore operation ran |

## Final disposition

The paired backup and restore-readability evidence is complete and passed. The requested production dry-run did **not** complete because of the local CLI compilation failure. No production migration was executed. Stop here; do not rerun or execute the migration under this authorization. A future dry-run attempt requires resolving the Dart/Flutter compilation environment issue and obtaining renewed/continued operational authorization, followed by the same preflight and postflight gates.
