# PHASE 10K REPORT: PRODUCTION MIGRATION RUNNER AND SYNC QUERY PRESERVATION

**Phase Identifier:** `PHASE_10K_PRODUCTION_MIGRATION_RUNNER_AND_SYNC_QUERY_PRESERVATION`
**Execution Timestamp:** `2026-10-05T16:43:00Z`
**Branch:** `fix/product-master-audit`
**Result Identifier:** `phase10K_A_1`
**Status:** `READY_FOR_AUTHORIZATION_REVIEW (TECHNICAL BLOCKERS RESOLVED ON DISPOSABLE CLONES; ZERO PRODUCTION WRITES PERFORMED)`

---

## 1. Root Cause of Sync-Query Mutation

During complete catalogue snapshot reconciliation, `SystemCatalogueSnapshot.import` previously performed an unconditional update on `sync_queries`:
- **Code Location:** `lib/data/catalogue/system_catalogue_snapshot.dart` (lines 185–214).
- **Failure Mechanism:** The importer looped over all compiled collections in the incoming snapshot and issued an `UPDATE` on `sync_queries` where `scopeType = 'SYSTEM'` and `collection = collection`.
- **Fields Mutated:**
  - `lastSyncedAt`: overwritten with `LocalDataSource.now()`.
  - `lastError`: reset to `null`.
  - `catalogueVersion`: set to the candidate's `releaseFingerprint`.
  - `cursor`: overwritten with `readTimes[entry.key]`.
- **Architectural Violation:** Existing registered sync query state is client-owned, durable synchronization state. It is **not** migration-owned. Overwriting these records during catalogue snapshot installation wiped out backoff states, corrupted readTime watermarks, and destroyed sync cursor tracking.

---

## 2. Importer Preservation Fix

- **Code Location:** `lib/data/catalogue/system_catalogue_snapshot.dart` and `lib/data/sync/sync_engine.dart`.
- **Implementation:**
  1. Added `bool preserveSyncQueries = true` parameter to `SystemCatalogueSnapshot.import` (defaulting to `true`).
  2. Guarded the `sync_queries` update block with `if (!preserveSyncQueries) { ... }`.
  3. Added `DatabaseExecutor? executor` parameter to `SystemCatalogueSnapshot.import` so it can execute inside caller-provided transactions without deadlocking or nesting SQLite transactions.
  4. Updated `SyncEngine` (`lib/data/sync/sync_engine.dart`) to explicitly supply `preserveSyncQueries: false` only during live remote Firestore pulls where read-time advancement is legitimate.
- **Invariants Preserved:**
  - Complete catalogue reconciliation across all collections is maintained.
  - Legitimate metadata inserts, updates, and deactivations remain active.
  - Legacy-reference query interlocks remain intact.
  - Zero display-name matching.
  - Zero Firestore or network calls introduced.

---

## 3. Runner Entry Point and Invocation Syntax

The production migration runner is implemented as a first-class repository tool:
- **Core Library:** `lib/data/migration/production_migration_runner.dart`
- **CLI Executable:** `bin/production_migration_runner.dart`
- **Tool Executable:** `tool/production_migration_runner.dart`

### Invocation Syntax

```bash
# Default Dry-Run Mode (Read-Only, Zero Writes)
dart run bin/production_migration_runner.dart \
  --database /path/to/account.db \
  --expected-account-sha 7751a6cc30a1f3765067bcec646beb16b0dc9dd094e1ccacd0d4d23e7e1515ef \
  --public-config /path/to/public-config.db \
  --expected-public-config-sha a81b30213ada2f9fbb962eb4c55b5824545048cf0be534dcc12d591dc9c93693 \
  --release-fingerprint sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88

# Gated Execute Mode (Write Mode - Requires Explicit Flags)
dart run bin/production_migration_runner.dart \
  --database /path/to/account.db \
  --expected-account-sha 7751a6cc30a1f3765067bcec646beb16b0dc9dd094e1ccacd0d4d23e7e1515ef \
  --public-config /path/to/public-config.db \
  --expected-public-config-sha a81b30213ada2f9fbb962eb4c55b5824545048cf0be534dcc12d591dc9c93693 \
  --backup /path/to/account.db.bak \
  --expected-backup-sha 853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651 \
  --release-fingerprint sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88 \
  --maintenance-ack \
  --execute \
  --json
```

---

## 4. Dry-Run Result on Production-Shaped Clone

- **Execution Mode:** `DRY_RUN`
- **Result:** `GO`
- **Success:** `true`
- **Preimage Integrity:** `PRAGMA integrity_check` -> `ok`
- **Preimage Verification:**
  - Account Preimage SHA: `7751a6cc30a1f3765067bcec646beb16b0dc9dd094e1ccacd0d4d23e7e1515ef` (Match)
  - Public Config SHA: `a81b30213ada2f9fbb962eb4c55b5824545048cf0be534dcc12d591dc9c93693` (Match)
  - Products: `4`
  - Variants: `7`
  - Sync queries: `195` (Digest: `d6b9e1b4c2b2d9e11327b96256e8198b545d9273bdf42d5eb2ad33f9ef927269`)
  - Protected queries: `10`
  - Legacy SYSTEM rows eligible for archive: `3903`
  - Legacy fingerprint: `sha256:1557b7d098f0ae5f829853fb798c86152282af67776cbb525063e2055387e74b`
- **Post-Inspection Check:** Database SHA-256 after dry run is **100% byte-identical** to preimage. Zero writes performed. Zero sidecars present.

---

## 5. Execute-Mode Clone Result

- **Execution Mode:** `EXECUTE` (on disposable temporary clone)
- **Result:** `SUCCESS`
- **Success:** `true`
- **Postimage Verification:**
  - Transaction committed successfully in 6 controlled stages.
  - Post-commit `PRAGMA integrity_check` -> `ok`.
  - Release 4 marker: `version = 4`, `catalogueId = 'PAINT_V1'`, `installed = 1`, `catalogueFingerprint = sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88`.
  - Selectors: `137/137` verified.
  - READY forms: `137/137` verified.
  - Archived legacy rows: `3903/3903` in `local_catalogue_archive` (Digest: `fcc17a60e9c84d78cdb2b2cfff055f3ea10be657ef959fdffd93f8c82bfc49f3`).
  - Historical null provenance fails closed.

---

## 6. 195/195 Query Preservation Result

- **Baseline Sync Queries:** `195` rows
- **Post-Migration Sync Queries:** `195` rows
- **Digest Before Migration:** `d6b9e1b4c2b2d9e11327b96256e8198b545d9273bdf42d5eb2ad33f9ef927269`
- **Digest After Migration:** `d6b9e1b4c2b2d9e11327b96256e8198b545d9273bdf42d5eb2ad33f9ef927269`
- **Field-by-Field Parity:** Exact match across `queryKey`, `collectionName`, `queryJson`, `active`, `cursor`, `lastSyncedAt`, `lastAttemptAt`, `lastError`, `catalogueVersion`.
- **Mutation Counts:** 0 inserted, 0 updated, 0 deleted, 0 reactivated.

---

## 7. 10/10 Protected-Query Preservation Result

All 10 protected legacy query keys are preserved byte-for-byte:
1. `product_subcategories` (BUS-6CB1F7443C2142159B8EBE3F9303839B / SYS_CATEGORY_ACCESSORIES / ACTIVE)
2. `product_subcategories` (BUS-6CB1F7443C2142159B8EBE3F9303839B / SYS_CATEGORY_EXTERIOR_WALL_PAINTS / ACTIVE)
3. `product_subcategories` (SYS_CATEGORY_ACCESSORIES / SYSTEM / ACTIVE)
4. `product_subcategories` (SYS_CATEGORY_EXTERIOR_WALL_PAINTS / SYSTEM / ACTIVE)
5. `subcategory_attribute_templates` (BUS-6CB1F7443C2142159B8EBE3F9303839B / BUSINESS / PM_SUBCATEGORY_ce0bf39843417fca)
6. `subcategory_attribute_templates` (BUS-6CB1F7443C2142159B8EBE3F9303839B / BUSINESS / SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH)
7. `subcategory_attribute_templates` (BUS-6CB1F7443C2142159B8EBE3F9303839B / BUSINESS / SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS)
8. `subcategory_attribute_templates` (SYSTEM / ACTIVE / PM_SUBCATEGORY_ce0bf39843417fca)
9. `subcategory_attribute_templates` (SYSTEM / ACTIVE / SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH)
10. `subcategory_attribute_templates` (SYSTEM / ACTIVE / SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS)

---

## 8. Product/Variant Preservation Result

- **Products Preimage:** 4 rows (`PRD-0199464E6EC27806A33ED60C969FF91B`, `PRD-0199465B203E709282362EE250EAE7A0`, `PRD-0199465DFEF77FFBAAFFA0BAEDC9B277`, `PRD-0199465FC804791E885B9E8398AE0A34`)
- **Products Postimage:** Exactly 4 rows unchanged.
- **Variants Preimage:** 7 rows (`VAR-0199464E6EC87756B13EE3D83D4BD0CD`, `VAR-0199465B2043743B8032737604F69B8F`, `VAR-0199465DFEFB7C609995BA5F809A7ED7`, `VAR-0199465FC80775B39688F80CF9CDD723`, `VAR-019946761A637207B5760DC8F1604B46`, `VAR-0199467817D57C5892556FE121A0C5BA`, `VAR-0199467A0061732599723AE93361E97C`)
- **Variants Postimage:** Exactly 7 rows unchanged.

---

## 9. Rollback and Negative-Test Results

All negative gate tests abort **before** any writable connection is opened:
- `wrong account SHA`: Aborts with `Preimage SHA-256 mismatch`. 0 bytes written.
- `missing maintenance ack`: Aborts with `Maintenance mode acknowledgement is required`. 0 bytes written.
- `missing backup`: Aborts with `Verified fresh backup path is required`. 0 bytes written.
- `wrong backup SHA`: Aborts with `Backup SHA-256 mismatch`. 0 bytes written.
- `wrong public-config SHA`: Aborts with `Public-config preimage SHA-256 mismatch`. 0 bytes written.
- `wrong target release fingerprint`: Aborts with `Release artifact fingerprint mismatch`. 0 bytes written.
- `active sidecar file present`: Aborts with `Active SQLite sidecars detected`. 0 bytes written.
- `missing/unknown snapshot file`: Aborts with `Release 4 snapshot file not found`. 0 bytes written.
- `already-installed Release 4`: Reports `ALREADY_INSTALLED` idempotent no-op with 0 writes.

---

## 10. Full Workspace Tests

- `test/phase10k_production_migration_runner_test.dart`: **14/14 tests passed**
- `test/system_catalogue_test.dart`: **7/7 tests passed**
- `test/catalogue_compiler_sync_test.dart`: **47/47 tests passed**
- **Total Tests Passed:** 68/68 passed (0 failures, 0 errors).

---

## 11. Flutter Analyze Result

Executed: `flutter analyze lib/data/catalogue/system_catalogue_snapshot.dart lib/data/sync/sync_engine.dart lib/data/migration/production_migration_runner.dart bin/production_migration_runner.dart tool/production_migration_runner.dart`
- **Result:** `No issues found! (ran in 0.5s)`

---

## 12. Production Hashes Before and After

| Database File | Size (Bytes) | SHA-256 Preflight | SHA-256 Postflight | Status |
|---|---|---|---|---|
| `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db` | 9,744,384 | `7751a6cc30a1f3765067bcec646beb16b0dc9dd094e1ccacd0d4d23e7e1515ef` | `7751a6cc30a1f3765067bcec646beb16b0dc9dd094e1ccacd0d4d23e7e1515ef` | **UNTOUCHED** |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak` | 9,728,000 | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | **UNTOUCHED** |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db` | 937,984 | `a81b30213ada2f9fbb962eb4c55b5824545048cf0be534dcc12d591dc9c93693` | `a81b30213ada2f9fbb962eb4c55b5824545048cf0be534dcc12d591dc9c93693` | **UNTOUCHED** |

---

## 13. Confirmation of Zero Firestore Access / Writes

- Zero remote HTTP/Firestore network clients are constructed or invoked by the runner or snapshot importer during catalogue migration.
- `MigrationReadOnlyCatalogueService` provides pure local SQLite querying.
- Production databases remain in exact read-only state.
- All migration approvals remain `false`.
- Phase 11 has **not** been started.

---

## 14. Deliverables Summary

1. **Supported Production Migration Runner:**
   - `lib/data/migration/production_migration_runner.dart`
   - `bin/production_migration_runner.dart`
   - `tool/production_migration_runner.dart`
2. **Runner Contract Document:**
   - `docs/phase10k-migration-runner-contract.md`
3. **Sync Query Preservation Audit & Proof JSON:**
   - `docs/phase10k-sync-query-preservation.json`
4. **Phase 10K Report:**
   - `phase10k.md`
5. **Phase 10K Test Suite:**
   - `test/phase10k_production_migration_runner_test.dart`
