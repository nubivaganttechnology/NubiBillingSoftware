# Phase 10K: Production Migration Runner Contract

## 1. Executive Summary & Purpose

This contract establishes the formal specification and operational requirements for the NubiBill Catalogue Release 4 production migration runner (`ProductionMigrationRunner`).

The runner addresses the second release blocker:
> **Blocker 2**: No supported, reviewed, strongly-gated production migration runner exists.

The runner is built as a first-class, repository-supported CLI and library tool designed to execute the Release 4 migration safely under maintenance-mode guarantees, with **default read-only dry-run mode**, **cryptographic preimage gates**, **verified backup preconditions**, **atomic transaction semantics**, and **strict post-commit invariant verification**.

---

## 2. Architecture & Entry Points

The runner is implemented in:
- `lib/data/migration/production_migration_runner.dart` (Core engine, options parser, and result models)
- `bin/production_migration_runner.dart` (Primary CLI executable entry point)
- `tool/production_migration_runner.dart` (Alternative development/release tooling entry point)

### Zero Remote / Zero Firestore Client Guarantee
The runner operates **strictly on local SQLite database files**:
- It **never** instantiates `FirebaseFirestore`, `FirestoreRestService`, `http.Client`, or `HttpClient`.
- Reads and catalogue resolutions are served through `MigrationReadOnlyCatalogueService`, an in-memory/local SQLite query adapter implementing `FirestoreDataService`.
- No credentials, tokens, or environment secrets are accepted, required, or embedded.

---

## 3. Invocation Syntax & Flags

```bash
dart run bin/production_migration_runner.dart [OPTIONS]
# or
dart run tool/production_migration_runner.dart [OPTIONS]
```

### Supported Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--database <path>` | String | **Required** | Absolute path to the account SQLite database. |
| `--expected-account-sha <sha256>` | String | **Required** | Expected SHA-256 hash of the target account database before any operation. |
| `--backup <path>` | String | Optional (Dry-run) / **Required (Execute)** | Path to a verified fresh backup database file. |
| `--expected-backup-sha <sha256>` | String | Optional | Expected SHA-256 hash of the backup file. |
| `--public-config <path>` | String | Optional | Path to public configuration database (`*-public-config.db`). |
| `--expected-public-config-sha <sha256>` | String | Optional | Expected SHA-256 hash of the public configuration database. |
| `--release-fingerprint <sha256>` | String | `sha256:cfc96...` | Expected release fingerprint of Release 4. |
| `--snapshot <path>` | String | `test/fixtures/system_catalogue_v4.json` | Path to canonical Release 4 snapshot JSON fixture. |
| `--dry-run` | Flag | **Default (True)** | Evaluates pre-conditions, derives plan, performs zero writes, and emits GO/NO-GO. |
| `--execute` | Flag | `false` | Explicitly enables destructive/write mode. |
| `--maintenance-ack` | Flag | `false` | Explicit acknowledgement that system is in maintenance mode with zero concurrent writers. |
| `--json` | Flag | `false` | Outputs machine-readable JSON result to stdout. |
| `--report-file <path>` | String | Optional | Writes machine-readable JSON execution report to the specified file. |

---

## 4. Safety Gates & Pre-conditions

Before any writable transaction is opened, the runner performs mandatory gate checks. Any check failure results in an **immediate abort with a non-zero exit code** and **zero bytes written**:

1. **Preimage Hash Gate**: Source database SHA-256 must match `--expected-account-sha` exactly.
2. **Active Sidecar Gate**: Rejects source or backup databases if SQLite `-wal`, `-shm`, or `-journal` files are present.
3. **Integrity Check Gate**: Read-only SQLite `PRAGMA integrity_check` must return `ok`.
4. **Catalogue Version Gate**: Database must currently have active version 3 catalogue installed (unless Release 4 is already installed, which returns idempotent `ALREADY_INSTALLED`).
5. **Preimage Entity Count Gates**:
   - Products must equal 4.
   - Variants must equal 7.
   - Sync queries must equal 195.
   - Protected legacy queries must equal 10.
   - Sync outbox must equal 0 (no pending sync operations).
   - Eligible legacy SYSTEM rows for archive must equal 3903.
6. **Release Artifact Fingerprint Gate**: Calculated fingerprint of Release 4 documents must match `--release-fingerprint`.
7. **Execute Flag Gate**: Refuses write operations unless `--execute` is explicitly passed.
8. **Maintenance Mode Acknowledgement Gate**: In execute mode, refuses to proceed without `--maintenance-ack`.
9. **Backup Verification Gate**: In execute mode, verified fresh backup file path must exist, be non-empty, pass `PRAGMA integrity_check`, and match `--expected-backup-sha` if provided.

---

## 5. In-Transaction Execution Order (Part 6)

In execute mode, operations are strictly sequenced inside a controlled single database transaction (`tx`):

```
1. Verify In-Transaction Preimage
   ├── Count & compare Products (4)
   ├── Count & compare Variants (7)
   └── Count & compare Sync Queries (195)
2. Schema Migration & Preparation
   └── CREATE TABLE IF NOT EXISTS local_catalogue_archive (...)
3. Derive Legacy Catalogue Fingerprint & Archive
   ├── Derive legacy fingerprint: sha256:1557b7d098f0ae5f829853fb798c86152282af67776cbb525063e2055387e74b
   └── Archive all 3903 legacy SYSTEM rows across 7 catalogue tables into local_catalogue_archive
4. Apply Release 4 Snapshot (with Sync Query Preservation)
   ├── ID collision interlock check (protects BUSINESS/pending IDs)
   ├── Upsert Release 4 collections with completeQuery reconciliation
   ├── Preserve all 195 sync queries unchanged (preserveSyncQueries: true)
   └── Upsert Release 4 marker last with installed: true and catalogueFingerprint
5. Verify In-Transaction Invariants
   ├── Assert archive count in tx == 3903
   ├── Assert Product rows in tx byte-identical to preimage (4)
   ├── Assert Variant rows in tx byte-identical to preimage (7)
   ├── Assert Sync Query rows in tx byte-identical to preimage (195)
   ├── Assert Sync Outbox in tx is empty (0)
   └── Assert Release 4 marker in tx has version=4 and exact release fingerprint
6. Transaction Commit
   └── Atomic commit
```

---

## 6. Post-Commit Verification (Part 7)

Immediately after commit, a fresh read-only connection evaluates all post-commit invariants:

1. **SQLite PRAGMA integrity_check**: Must return `ok`.
2. **Release 4 Marker**: Must exist, be active, published, installed, version 4, and match Release 4 fingerprint.
3. **Canonical Selectors**: Exactly 137 subcategories exist, all eligible, valid, and resolvable.
4. **READY Forms**: Exactly 137 subcategories resolve to `ProductFormStatus.ready` with full form fields and valid default options.
5. **Product Row Invariance**: Exactly 4 original Products preserved with identical remoteIds, attributes, and barcodes.
6. **Variant Row Invariance**: Exactly 7 original Variants preserved with identical remoteIds and prices.
7. **Sync Query Parity**: Exactly 195 sync queries preserved; query digest before and after commit is identical (`d6b9e1b4c2b2d9e11327b96256e8198b545d9273bdf42d5eb2ad33f9ef927269`).
8. **Protected Query Parity**: All 10 protected queries preserved byte-for-byte.
9. **Legacy Archive Verification**: Exactly 3903 rows archived in `local_catalogue_archive` under `sha256:1557b7d098f0ae5f829853fb798c86152282af67776cbb525063e2055387e74b`.
10. **Historical Null Provenance**: Legacy historical references fail-closed as required by earlier phase contracts.

---

## 7. Failure & Rollback Behavior

- **Pre-transaction Abort**: Any gate check failure causes an immediate abort. The database file is never opened for write. Exit code `1`.
- **In-transaction Rollback**: If an exception or invariant check fails while the transaction is open, SQLite automatically rolls back all changes. The database reverts to its exact preimage state. Exit code `1`.
- **Post-commit Failure**: If a post-commit invariant check fails after commit, the runner logs a critical error, emits `status: ROLLBACK_REQUIRED`, preserves forensic logs, and exits with code `1`.
- **No Silent Self-Healing**: The runner never attempts heuristic repairs, partial commits, or silent recovery.

---

## 8. Idempotence

If the runner is executed against a database that already has Release 4 installed with a matching fingerprint:
- The runner safely detects the installed release.
- Emits `result: ALREADY_INSTALLED`, `success: true`.
- Performs **zero writes** and exits with code `0`.

---

## 9. Machine-Readable Output Specification

When invoked with `--json` or `--report-file`, the runner outputs structured JSON:

```json
{
  "mode": "EXECUTE",
  "result": "SUCCESS",
  "success": true,
  "sourceHashes": {
    "accountPreimageSha": "7751a6cc30a1f3765067bcec646beb16b0dc9dd094e1ccacd0d4d23e7e1515ef",
    "accountPostimageSha": "b1411fe88a82315430ebcb0199920d7acac9c7939b2ea650d040600cd5a8fb5c",
    "publicConfigSha": "a81b30213ada2f9fbb962eb4c55b5824545048cf0be534dcc12d591dc9c93693"
  },
  "backupHashes": {
    "backupPath": "/path/to/clone.db.bak",
    "backupSha": "853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651"
  },
  "releaseFingerprint": "sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88",
  "legacyFingerprint": "sha256:1557b7d098f0ae5f829853fb798c86152282af67776cbb525063e2055387e74b",
  "preimageCounts": {
    "products": 4,
    "variants": 7,
    "syncQueries": 195,
    "protectedQueries": 10,
    "outbox": 0,
    "systemRowsEligibleForArchive": 3903
  },
  "postimageCounts": {
    "products": 4,
    "variants": 7,
    "syncQueries": 195,
    "protectedQueries": 10,
    "selectors": 137,
    "readyForms": 137,
    "archivedRows": 3903
  },
  "queryDigestBefore": "d6b9e1b4c2b2d9e11327b96256e8198b545d9273bdf42d5eb2ad33f9ef927269",
  "queryDigestAfter": "d6b9e1b4c2b2d9e11327b96256e8198b545d9273bdf42d5eb2ad33f9ef927269",
  "archiveCount": 3903,
  "archiveDigest": "fcc17a60e9c84d78cdb2b2cfff055f3ea10be657ef959fdffd93f8c82bfc49f3",
  "abortReason": null
}
```
