# Phase 10M — Production GO preflight (read-only)

**Inspection date:** 2026-10-05
**Disposition:** **CASE_B — SCHEMA_DRIFT_REQUIRES_REVIEW. STOP.** This is not a precheck GO candidate. Do not create a new backup, run a migration dry-run, or execute the production runner until schema/preimage drift is independently resolved and approved. The business GO authorization is conditional; the preflight did not pass.

## Safety and method

Both production databases were opened using SQLite explicit read-only mode (`sqlite3 -readonly`); `PRAGMA query_only=1` was set and verified as `1` on each. Only filesystem metadata/hashes and SQLite read-only integrity, schema, metadata, and count queries were performed. `lsof` showed no open handles to either source database at inspection time. No Firestore or remote service was accessed. No database writes, backup creation, dry-run, migration, application startup, or production runner invocation occurred.

## Account database

Path: `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db`

| Check | Read-only observation |
|---|---|
| Size | 9,748,480 bytes |
| SHA-256 | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` |
| Modification time | 2026-10-05 17:20:34 +0530 |
| `PRAGMA query_only` | `1` |
| `PRAGMA integrity_check` | `ok` |
| `PRAGMA user_version` | `4` |
| Sidecars (`-wal`, `-shm`, `-journal`) | All absent before and after inspection |
| Open handles at check | None reported by `lsof` |
| `local_catalogue_archive` | Exists; 0 rows |
| Products (`local_products`) | 4 |
| Variants (`local_product_variants`) | 7 |
| Sync queries (`sync_queries`) | 195 |
| Protected legacy queries | 10 |
| Outbox (`sync_outbox`) | 0 |

Exactly one non-deleted active SYSTEM release row was observed: `PAINT_V1`, status `ACTIVE`, catalogue version 3, `published=true`. It is not a Release 4 marker. Schema revision, compiler revision, catalogue fingerprint, and `installed` are absent from this marker payload.

## Public-config database

Path: `/Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db`

| Check | Read-only observation |
|---|---|
| Size | 946,176 bytes |
| SHA-256 | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` |
| Modification time | 2026-10-05 17:03:13 +0530 |
| `PRAGMA query_only` | `1` |
| `PRAGMA integrity_check` | `ok` |
| `PRAGMA user_version` | `4` |
| Sidecars (`-wal`, `-shm`, `-journal`) | All absent before and after inspection |
| Open handles at check | None reported by `lsof` |
| `local_product_catalogue_releases` | 0 rows; no SYSTEM release marker present |
| `local_catalogue_archive` | Exists; 0 rows |
| Catalogue/release-named `local_app_config` records | None found |

## Existing backup (hash-only)

Path: `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak`

- Size: 9,728,000 bytes
- SHA-256: `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651`
- Modification time: 2026-10-04 10:55:36 +0530
- The backup was hashed and stat'ed only; it was not opened as a database or modified.

## Historical baseline comparison

| Baseline item | Historical approved value | Current observation | Result |
|---|---:|---:|---|
| Account SHA-256 | `7751a6cc30a1f3765067bcec646beb16b0dc9dd094e1ccacd0d4d23e7e1515ef` | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | Different |
| Public-config SHA-256 | `a81b30213ada2f9fbb962eb4c55b5824545048cf0be534dcc12d591dc9c93693` | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | Different |
| Account schema version | 3 | 4 | Different; known schema drift |
| Catalogue version | 3 | 3 (`PAINT_V1`, active SYSTEM marker) | Matches historical version, not Release 4 |
| Products | 4 | 4 | Matches |
| Variants | 7 | 7 | Matches |
| Sync queries | 195 | 195 | Matches |
| Protected legacy queries | 10 | 10 | Matches |
| Archive rows | Not specified in historical baseline | 0 | Empty |
| Outbox rows | Historical evidence indicates 0 | 0 | Matches |

Both database hashes differ from the historical values. The observed schema-v4 state is consistent with the previously reported drift, but these file-level hashes do not by themselves establish exact logical preimage equivalence. The account retains a Release 3 marker and has an empty archive, which meets the explicit CASE_B condition; the mismatched hashes must remain part of the review and must not be treated as approval to migrate.

## Classification and action

**CASE_B — `SCHEMA_DRIFT_REQUIRES_REVIEW`.** The account is schema v4, the active SYSTEM catalogue marker is still Release 3, and the archive is empty. The public-config DB is also schema v4 and has no local catalogue-release marker. The production runner currently rejects account schema versions other than 3. Consequently, this is not CASE_A and no production runner mode is authorized by this preflight. Stop here and resolve/reapprove the exact current preimage and schema compatibility before any subsequent backup or migration activity.

## No-write attestation

**Zero writes occurred. Zero Firestore or remote-service access occurred.** No backup was created, no dry-run was performed, and `ProductionMigrationRunner --execute` was not run. No tables, release markers, Products, Variants, sync queries, outbox rows, or application code were changed. File hashes, sizes, and mtimes were unchanged by the inspection; no WAL, SHM, or journal sidecars were present after it.
