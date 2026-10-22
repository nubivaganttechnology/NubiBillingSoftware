# Phase 10N7 — Actual Production Dry-Run

**Status: COMPLETE — GO.** The supported runner was invoked against the actual
production account and public-config databases in `DRY_RUN` mode only. It
returned `success: true`, `result: GO`, and shell exit code 0. No `--execute` or
destructive flag was supplied. The runner reported zero writes and zero
Firestore/network calls. Production execution remains unauthorized and was not
attempted.

## Preflight

Maintenance mode remains active per the operator's explicit authorization in
the N7 request (`maintenanceModeContinues: true`).

| Check | Result |
|---|---|
| Account DB open handles | None; `lsof` returned no rows |
| Public-config DB open handles | None; `lsof` returned no rows |
| SQLite `.db-wal`, `.db-shm`, `.db-journal` sidecars | None for either production DB |
| Account DB SHA-256 | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` — matches approval |
| Public-config DB SHA-256 | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` — matches approval |
| Approved account backup exists and hash | Yes — `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8`, matches account DB |
| Approved public-config backup exists and hash | Yes — `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289`, matches public-config DB |

## Production Dry-Run

Exact runner command:

```sh
dart run bin/production_migration_runner.dart --database /Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db --expected-account-sha 2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8 --public-config /Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db --expected-public-config-sha 9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289 --release-fingerprint sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88 --json
```

No `--execute`, maintenance acknowledgement, backup, or other destructive
flag was added. Actual shell exit code: **0**. Runner disposition: **GO**.

Full runner JSON output:

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
    "Database: /Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db",
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

The runner passed its source and public-config `PRAGMA integrity_check` gates;
non-`ok` results abort the runner. It accepted the exact schema-v4,
`PAINT_V1` catalogue-v3 preimage, including the empty archive (0 preimage
archive rows). The reported `archiveCount: 3903` and `expectedArchiveRows: 3903`
are planned Release 4 archive totals, not rows written by this dry-run.

| Observed preimage | Result |
|---|---:|
| Products | 4 |
| Variants | 7 |
| Sync queries | 195 |
| Protected queries | 10 |
| Outbox rows | 0 |
| Archive rows | 0 |
| Legacy catalogue rows eligible for archive | 3,903 |
| Target Release 4 fingerprint | `sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88` |
| Expected selectors / READY forms | 137 / 137 |

## Postflight

| Artifact | Preflight SHA-256 | Postflight SHA-256 | Match |
|---|---|---|---|
| Production account DB | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | **YES** |
| Production public-config DB | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | **YES** |
| Approved account backup | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | **YES** |
| Approved public-config backup | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | **YES** |

Postflight found no SQLite sidecars and no open handles for either production
DB. The runner's log confirms zero production writes and zero Firestore/network
calls; unchanged production hashes independently confirm the zero-write result.

## Disposition

Production dry-run: **GO**. Production migration execution: **NOT RUN** and
remains unauthorized. Maintenance mode remains active per the operator's
instruction. No retry was needed.