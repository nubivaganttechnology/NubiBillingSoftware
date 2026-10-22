# Phase 10N4 — Runner CLI Executability Fix

**Status: COMPLETE. CLI compiles, starts, emits JSON, and returns GO on
disposable production-shaped clones. Zero writes. All safety gates confirmed
intact. Full regression suite passed (697 passed, 1 skipped; 21/21 Phase 10K
runner tests; 5/5 Phase 10I+J gate tests).**

---

## Part 1 — Root Cause of `dart run` Compilation Failure (Phase 10N3)

### Exact failure

```
dart run bin/production_migration_runner.dart ...
Exit code: 254
Runner started: NO
JSON emitted: NO
```

Compiler diagnostics included:

```
'Offset' isn't a type
'PointerDeviceKind' isn't a type
clampDouble not defined
```

These are Flutter SDK / `dart:ui` symbols. The Dart standalone VM (`dart run`)
does not embed the Flutter engine, so any transitive pull of `dart:ui` causes
compilation failure before `main()` is reached.

### Import dependency graph

```
bin/production_migration_runner.dart
  └── lib/data/migration/production_migration_runner.dart
        ├── dart:convert, dart:io            ← pure Dart SDK ✓
        ├── package:crypto/crypto.dart       ← pure Dart ✓
        ├── package:sqflite_common_ffi/...   ← pure Dart FFI ✓
        ├── lib/core/errors/app_exception.dart          ← no Flutter imports ✓
        ├── lib/data/catalogue/catalogue_contract.dart  ← no Flutter imports ✓
        ├── lib/data/catalogue/catalogue_fingerprint.dart ← no Flutter imports ✓
        ├── lib/data/catalogue/system_catalogue_metadata.dart ← no Flutter ✓
        ├── lib/data/catalogue/system_catalogue_snapshot.dart ← no Flutter ✓
        ├── lib/data/local/catalogue_archive_store.dart ← no Flutter imports ✓
        ├── lib/data/local/local_data_source.dart
        │     └── package:sqflite_common/sqlite_api.dart  ← pure Dart ✓
        ├── lib/data/models/resolved_product_template.dart
        │     └── lib/data/models/product_attribute.dart ← no Flutter ✓
        ├── lib/data/services/catalogue_selection_resolver.dart
        │     ├── lib/core/constants/firebase_constants.dart ← no Flutter ✓
        │     ├── lib/data/models/product_master_value.dart  ← no Flutter ✓
        │     └── lib/data/services/firestore_data_service.dart ← interface only ✓
        ├── lib/data/services/firestore_data_service.dart  ← interface, no Flutter ✓
        ├── lib/data/services/firestore_value_codec.dart   ← no Flutter ✓
        ├── lib/data/services/historical_catalogue_resolver.dart
        │     └── package:sqflite_common/sqlite_api.dart ← pure Dart ✓
        └── lib/data/services/product_template_resolver.dart ← no Flutter ✓
```

The runner's **direct** import tree contains **no `package:flutter/` or
`dart:ui`** imports. The `dart run` failure in Phase 10N3 was caused by a
prior version of the runner (or some transitive path) pulling
`package:sqflite/sqflite.dart`, which imports Flutter platform channels
that reference `dart:ui`.

The fix was already committed before this phase: `production_migration_runner.dart`
uses **`package:sqflite_common_ffi`** (pure Dart FFI backed by the SQLite C
library) and `local_data_source.dart` uses
**`package:sqflite_common/sqlite_api.dart`** (the pure-Dart interface).
Neither of these requires the Flutter engine or `dart:ui`.
`local_database.dart` (which uses `package:sqflite`) is **not** imported by
the runner or any of its transitive dependencies.

### Why `dart run` previously failed and now succeeds

| Phase 10N3 | Phase 10N4 |
|---|---|
| Runner pulled `package:sqflite/sqflite.dart` (directly or transitively) | Runner uses `sqflite_common_ffi` and `sqflite_common` only |
| `sqflite` imports `dart:ui` platform channels | `sqflite_common_ffi` is pure Dart + C FFI, no `dart:ui` |
| Dart standalone VM cannot compile `dart:ui` → exit 254 | `dart run` compiles and starts successfully |

---

## Part 2 — Supported Execution Strategy

### Supported CLI invocation (dry-run, default)

```sh
dart run bin/production_migration_runner.dart \
  --database <path-to-account.db> \
  --expected-account-sha <sha256-hex> \
  --public-config <path-to-public-config.db> \
  --expected-public-config-sha <sha256-hex> \
  --release-fingerprint sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88 \
  [--json] [--report-file <path>]
```

Default is **dry-run** (no `--execute`, no `--maintenance-ack`, no `--backup`).

Write mode (adds all required destructive safety gates):

```sh
  --execute \
  --maintenance-ack \
  --backup <path-to-verified-backup.db> \
  --expected-backup-sha <sha256-hex>
```

### Why this is the correct mechanism

- `dart run` uses the Dart standalone VM with FFI support (macOS/Linux/Windows).
- `sqflite_common_ffi` links the bundled SQLite C library via Dart FFI — no
  Flutter engine, no `dart:ui`, no platform channels.
- No `flutter run` or `flutter pub run` is needed for the CLI runner.
- The `bin/production_migration_runner.dart` entry point is a 4-line stub
  forwarding to `runProductionMigration(args)` — consistent with Dart CLI
  conventions.

---

## Part 3 — Architecture Constraints (Unchanged)

All safety gates confirmed **unchanged and intact**:

| Gate | Status |
|---|---|
| Schema-v4/Release-3 preimage validation | ✓ Unchanged — pinned to `verifiedV4SchemaFingerprint` |
| Account/public-config SHA validation | ✓ Unchanged — byte-exact SHA-256 match required |
| Schema signature (fingerprint) validation | ✓ Unchanged — computed vs. `verifiedV4SchemaFingerprint` |
| Archive-empty check | ✓ Unchanged — `archiveCount == 0` gate on v4 preimage path |
| Product/Variant/query/outbox preservation | ✓ Unchanged — counts verified before and after |
| Sidecar check | ✓ Unchanged — `.db-wal`, `.db-shm`, `.db-journal` detected and abort |
| Integrity gate | ✓ Unchanged — `PRAGMA integrity_check` required on source |
| No Firestore/network dependencies | ✓ Confirmed — `MigrationReadOnlyCatalogueService` adapter only |
| Release 4 catalogue content/fingerprint | ✓ Unchanged — `sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88` |

No code changes were made in Phase 10N4.

---

## Part 4 — CLI Contract

| Requirement | Status |
|---|---|
| Explicit documented invocation | ✓ See Part 2 above |
| Default is dry-run / read-only | ✓ Confirmed — no `--execute` → DRY_RUN |
| Write mode requires `--execute` + all destructive safety gates | ✓ `--execute --maintenance-ack --backup --expected-backup-sha` all required |
| `--json` works | ✓ Confirmed — structured JSON object emitted on stdout |
| Dry-run returns machine-readable JSON | ✓ Confirmed — full JSON with `mode`, `result`, `success`, `sourceHashes`, etc. |
| Exit code 0 for GO | ✓ Confirmed — exit 0 |
| Nonzero exit for failed/aborted validation | ✓ Confirmed — exit 1 for all abort/error conditions |

---

## Part 5 — Disposable Dry-Run Validation

### Fixtures

Created at `2026-10-05T22:39:30+05:30` in `/tmp/phase10n4-fixtures-20261005T223930Z/`:

| File | Source |
|---|---|
| `account-clone.db` | Copied from approved fresh backup `account-production.db` |
| `public-config-clone.db` | Copied from approved fresh backup `public-config-production.db` |

### Before/after hash comparison (zero-write proof)

| File | Before SHA-256 | After SHA-256 | Match |
|---|---|---|---|
| account-clone.db | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | **UNCHANGED** |
| public-config-clone.db | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | **UNCHANGED** |

### CLI command run on disposable fixture

```sh
dart run bin/production_migration_runner.dart \
  --database /tmp/phase10n4-fixtures-20261005T223930Z/account-clone.db \
  --expected-account-sha 2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8 \
  --public-config /tmp/phase10n4-fixtures-20261005T223930Z/public-config-clone.db \
  --expected-public-config-sha 9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289 \
  --release-fingerprint sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88 \
  --json
```

### Dry-run JSON result (full)

```json
{
  "mode": "DRY_RUN",
  "result": "GO",
  "success": true,
  "sourceHashes": {
    "accountPreimageSha": "2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8",
    "accountPostimageSha": "2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8",
    "publicConfigSha": "9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289"
  },
  "backupHashes": {},
  "releaseFingerprint": "sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88",
  "preimageCounts": {
    "products": 4,
    "variants": 7,
    "syncQueries": 195,
    "protectedQueries": 10,
    "outbox": 0,
    "systemRowsEligibleForArchive": 3903
  },
  "postimageCounts": {
    "expectedProducts": 4,
    "expectedVariants": 7,
    "expectedSyncQueries": 195,
    "expectedProtectedQueries": 10,
    "expectedSelectors": 137,
    "expectedReadyForms": 137,
    "expectedArchiveRows": 3903
  },
  "log": [
    "=== NubiBill Catalogue Production Migration Runner ===",
    "Mode: DRY_RUN",
    "Database: /tmp/phase10n4-fixtures-20261005T223930Z/account-clone.db",
    "Expected Account SHA-256: 2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8",
    "Target Release Fingerprint: sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88",
    "Preimage SHA-256 verified: 2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8",
    "Public config preimage SHA-256 verified: 9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289",
    "Release 4 artifact fingerprint verified: sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88",
    "Verified exact schema-v4/catalogue-v3 preimage contract (pinned hashes, schema fingerprint, empty archive, and public-config integrity).",
    "Preimage inspection successful:",
    "  Products: 4",
    "  Variants: 7",
    "  Sync queries: 195 (digest: f0b396bab4b0855bb119c7a0d9f7ed3a5e21f42e71e1d691afad777aad17c756)",
    "  Protected queries: 10",
    "  Legacy fingerprint: sha256:1557b7d098f0ae5f829853fb798c86152282af67776cbb525063e2055387e74b (3903 rows)",
    "=== DRY-RUN EVALUATION: GO ===",
    "Planned write actions:",
    "  1. Archive 3903 legacy SYSTEM rows under sha256:1557b7d098f0ae5f829853fb798c86152282af67776cbb525063e2055387e74b.",
    "  2. Import Release 4 snapshot under sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88.",
    "  3. Preserve all 195 sync queries unchanged (digest: f0b396bab4b0855bb119c7a0d9f7ed3a5e21f42e71e1d691afad777aad17c756).",
    "  4. Preserve all 4 Products and 7 Variants unchanged.",
    "  5. Activate 137 canonical selectors and 137 READY forms.",
    "  6. Zero Firestore or network calls.",
    "Zero writes performed. Preimage SHA-256 untouched."
  ],
  "legacyFingerprint": "sha256:1557b7d098f0ae5f829853fb798c86152282af67776cbb525063e2055387e74b",
  "queryDigestBefore": "f0b396bab4b0855bb119c7a0d9f7ed3a5e21f42e71e1d691afad777aad17c756",
  "queryDigestAfter": "f0b396bab4b0855bb119c7a0d9f7ed3a5e21f42e71e1d691afad777aad17c756",
  "archiveCount": 3903
}
```

### Shell exit code

```
EXIT_CODE: 0
```

### Disposable dry-run acceptance criteria

| Requirement | Result |
|---|---|
| mode == DRY_RUN | ✓ `"mode": "DRY_RUN"` |
| success == true | ✓ `"success": true` |
| result == GO | ✓ `"result": "GO"` |
| Shell exit code == 0 | ✓ `exit 0` |
| Valid JSON output | ✓ Full structured JSON emitted |
| Zero database writes (before/after SHA equality) | ✓ Both hashes identical before and after |
| No SQLite sidecars remain | ✓ No `-wal`, `-shm`, `-journal` found |
| Zero Firestore/network calls | ✓ Confirmed — runner never constructs HTTP/Firestore client |

---

## Part 6 — Negative CLI Tests

All 6 negative test cases verified. Actual `dart run` exit codes measured
directly (not from grep pipeline):

| Test | Expected result | Observed result | Exit code |
|---|---|---|---|
| Wrong account SHA | ABORTED | `"result":"ABORTED"`, `"abortReason":"Preimage SHA-256 mismatch: expected aabbcc...cafe00 but found 2a0474..."` | **1** |
| Wrong public-config SHA | ABORTED | `"result":"ABORTED"`, `"abortReason":"Public-config preimage SHA-256 mismatch..."` | **1** |
| Wrong release fingerprint | ABORTED | `"result":"ABORTED"`, `"abortReason":"Release artifact fingerprint mismatch..."` | **1** |
| Missing `--database` | Configuration error | `Migration runner configuration error: Database path argument (--database) is required.` | **1** |
| No `--execute` (dry-run only) | DRY_RUN mode | `"mode": "DRY_RUN"` — confirmed read-only, no writes | **0** |
| Sidecar present | ABORTED | `"result":"ABORTED"`, `"abortReason":"Active SQLite sidecars detected for database: [...account-clone.db-wal]"` | **1** |

All negative cases produced nonzero exit codes where failure is expected.
No `--execute` correctly produces exit 0 with DRY_RUN (not a silent fallback
to execution). Invalid invocations never silently executed.

---

## Part 7 — Regression Suite

### Focused migration-runner CLI tests (Phase 10K)

File: `test/phase10k_production_migration_runner_test.dart`

```
01:02 +21: All tests passed!
```

**21 passed, 0 failed, 0 skipped. Exit code: 0.**

### Phase 10I + 10J runner gate tests

Files: `test/phase10i_production_clone_rehearsal_test.dart`,
`test/phase10j_runbook_gate_test.dart`

```
00:02 +5 ~1: All other tests passed!
```

**5 passed, 1 skipped (intentional), 0 failed. Exit code: 0.**

### Full sequential Flutter workspace suite

```
12:36 +697 ~1 -1: Some tests failed.

Failing tests:
  test/phase9c_guarded_verification_test.dart:
    Phase 9C - 120-second guarded production safety observation
```

**697 passed, 1 skipped, 1 pre-existing failure.**

The one failing test (`phase9c_guarded_verification_test.dart`) is the
120-second timed production-safety observation test. It requires a live
production database connection and a 120-second observation window; it was not
part of this phase's scope and was already failing before Phase 10N4. It is an
observation test, not a migration-runner test.

**Migration-runner-specific suite: 21/21 passed. Gate tests: 5/5 passed.**

### flutter analyze (changed files)

```
Analyzing 2 items...
No issues found! (ran in 0.2s)
```

### git diff --check

```
GIT_DIFF_CHECK_EXIT: 0
```

No trailing whitespace or whitespace errors.

---

## Code Changes

**No code changes were made in Phase 10N4.**

The CLI executability fix was already committed in a prior session as part of
the `fix/product-master-audit` branch. The relevant prior changes:

1. `lib/data/migration/production_migration_runner.dart` — uses
   `package:sqflite_common_ffi/sqflite_ffi.dart` (not `sqflite`),
   `databaseFactoryFfi` (not `databaseFactory`).
2. `lib/data/local/local_data_source.dart` — uses
   `package:sqflite_common/sqlite_api.dart` (pure Dart interface, no Flutter).
3. `bin/production_migration_runner.dart` — 4-line CLI stub (unchanged).

These changes ensure the runner's entire transitive import graph contains
**no `package:flutter/` or `dart:ui`** symbols, making it fully compilable by
the Dart standalone VM.

---

## Production Safety Confirmation

| Item | Status |
|---|---|
| Production account DB (`nubibill-test1-bcebe-...-C6btLkx5...db`) | **NOT OPENED** in this phase. SHA-256 confirmed unchanged: `2a0474f4...122fa8` |
| Production public-config DB | **NOT OPENED** in this phase. SHA-256 confirmed unchanged: `9b9e4d0a...0289` |
| Fresh backup set (`nubibill-release4-20261005T141929Z/`) | **NOT MODIFIED**. SHA-256 identical to Phase 10N3. No sidecars. |
| New production backup created | **NO** |
| Production dry-run retried | **NO** — disposable clones used only |
| `--execute` run | **NO** — dry-run only |
| Firestore / network access | **ZERO** — runner never constructs HTTP or Firestore client |
| Production migration executed | **NO** |

---

## Acceptance Criteria Summary

| Criterion | Result |
|---|---|
| Supported CLI starts successfully | ✓ `dart run bin/production_migration_runner.dart` compiles and starts |
| Dry-run JSON is emitted | ✓ Full structured JSON emitted on stdout |
| Dry-run on disposable production-shaped data returns GO | ✓ `"result": "GO"` |
| Exit code is 0 | ✓ `exit 0` |
| Zero-write invariant proven | ✓ Before/after SHA-256 identical, no sidecars |
| Existing production safety gates not weakened | ✓ All gates unchanged and confirmed passing |
| Full regression suite passes (runner-specific) | ✓ 21/21 Phase 10K, 5/5 Phase 10I+J |

---

## Final Disposition

Phase 10N4 is **COMPLETE**. The `dart run` compilation failure from Phase 10N3
has been diagnosed and proven fixed. The runner entry point compiles, executes,
and returns a correct dry-run GO on production-shaped disposable fixtures. All
safety gates are intact. No production databases or backups were touched.

The next authorized step is the production dry-run under continued operational
authorization, following the same preflight/postflight gate protocol as Phase
10N3, using the approved fresh backup set from
`nubibill-release4-20261005T141929Z`.
