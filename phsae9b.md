# Phase 9B — Stable production-safety verification

Date: 2026-10-04. Requested output filename: `phsae9b.md`.

**Decision: STOP — Phase 9 is NOT fully closed.** Preflight initially passed, but NubiBill/testflutter started during the observation interval and opened the production account database for writing. The account and public-config file checksums changed. No production mutation or application launch was performed by the verification commands. The application was not killed automatically.

The complete workspace suite passed **247/247** tests, and the dedicated Phase 9 suite passed **47/47**. Analyzer results exactly match the pre-existing baseline: **51 diagnostics (5 warnings, 46 infos, zero errors), zero new diagnostics**. Passing tests do not override the failed production-safety criteria.

## Preflight

| Requirement | Result |
| --- | --- |
| Branch | `fix/product-master-audit` — confirmed. |
| Phase 9 committed | `22821f47cb2c1d9619bea637d1ab1e14f3a3dde3` — `fix(product-master): repair catalogue compiler import and sync`. |
| Working tree | Clean before verification; still clean before saving this report. |
| Application closed initially | Unrestricted read-only `pgrep -fl 'testflutter\|NubiBill\|nubibill'` returned exit 1 with no matches. |
| Account database handles initially | Unrestricted read-only `lsof` on the account database returned exit 1 with no handles. WAL/SHM paths did not exist. |
| Production metadata | Recorded before any test; complete before/after observations follow. |

The initial sandboxed process lookup could not access the process list. It was rerun with approved unrestricted read-only access; verification did not rely on the failed lookup.

## Observation and stop event

All times below are UTC; local timezone is Asia/Kolkata (UTC+05:30).

- Before capture: **2026-10-04T11:02:25.893691+00:00**.
- Monitor first sample: **2026-10-04T11:02:50.927329+00:00**.
- Last clean monitor sample: **2026-10-04T11:04:03.520986+00:00**, at 72.94 seconds.
- Stop sample: **2026-10-04T11:04:08.821922+00:00**, at 78.241 seconds.
- The planned 100-second monitored interval did not complete. The monitor sampled file hashes, sizes, modification times, sidecar existence, open handles and app processes every approximately five seconds. There were 16 samples, with the final sample detecting the application start.
- At the detecting sample the app existed but had not yet opened the account file. Follow-up `lsof` confirmed the writer:

```text
COMMAND     PID    USER     FD   TYPE   SIZE/OFF  NAME
testflutt 11795 sksuman    18u   REG    9744384   /Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db
```

Process path: `/Users/sksuman/StudioProjects/NubiBillingSoftware-main/build/macos/Build/Products/Debug/testflutter.app/Contents/MacOS/testflutter`.
Process start: **Sun Oct 4 16:34:08 2026 Asia/Kolkata** (11:04:08 UTC). The `18u` descriptor is read/write.

The monitor recorded STOP automatically. Its result reached the assistant after an already-issued verification batch; that batch captured the read-only post-event audit. Subsequent commands only retrieved existing test results and read-only incident evidence, then wrote this report. No new test run, production cleanup or live sync was started after detecting the stop event. The already-running dedicated isolated suite finished successfully.

The process was reported, not terminated. A new stable verification attempt requires the application to remain closed for the entire interval. This failed attempt is retained and must not be represented as a successful unchanged interval.

## Production file metadata and SHA-256

The after observations below are the captured post-event audit, not a successful stable endpoint. Both captures assert that file metadata remained consistent during each individual read-only capture.

### `nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db`

Path: `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db`

| Field | Before | After captured event |
| --- | --- | --- |
| Size (bytes) | 9728000 | 9744384 |
| Modification time (UTC) | 2026-10-04T10:59:25.457483+00:00 | 2026-10-04T11:04:12.161876+00:00 |
| Modification time (nanoseconds since epoch) | 1791111565457482534 | 1791111852161875909 |
| SHA-256 | `e333a15ce81017a6d927b82854659652e0a1c70e4f6f4e766824b66c81c63ba5` | `5145aa4d808fbcebfd57d0b43242a0bd9e5040bbfa6c3c044690bc7b553be2bb` |
| Byte/metadata equality | — | **FAIL** |

### `nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak`

Path: `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak`

| Field | Before | After captured event |
| --- | --- | --- |
| Size (bytes) | 9728000 | 9728000 |
| Modification time (UTC) | 2026-10-04T05:25:36.646308+00:00 | 2026-10-04T05:25:36.646308+00:00 |
| Modification time (nanoseconds since epoch) | 1791091536646307789 | 1791091536646307789 |
| SHA-256 | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` |
| Byte/metadata equality | — | PASS |

### `nubibill-test1-bcebe-public-config.db`

Path: `/Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db`

| Field | Before | After captured event |
| --- | --- | --- |
| Size (bytes) | 937984 | 937984 |
| Modification time (UTC) | 2026-10-04T09:26:42.938496+00:00 | 2026-10-04T11:04:11.757294+00:00 |
| Modification time (nanoseconds since epoch) | 1791106002938495731 | 1791111851757294196 |
| SHA-256 | `20cf0f320c9cbe6a62bcf8e6d1cc4e4a190bb13060522bbd8286d42e03be23e0` | `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012` |
| Byte/metadata equality | — | **FAIL** |

The account file grew by **16,384 bytes**. The public-config size did not change, but its modification time and checksum changed. Backup bytes, size and modification time remained identical. No restoration, VACUUM, repair, migration or compensating production write was attempted.

## Read-only row and query audit

Capture connections used `sqlite3.connect('file:…?mode=ro', uri=True)`, then `PRAGMA query_only=ON` and connection-local `PRAGMA busy_timeout=5000`. Trace validation allowed only **SELECT and PRAGMA** statements. No write transaction, bootstrap, migration or live LocalDatabase initialization was invoked on production by the audit script. Before/after schema digests and sorted full-row digests cover **all 56 tables in each of the three SQLite files**, not just active catalogue records.

At the captured post-event audit, schema and every table's row count and row digest matched their initial values. This proves logical equality at those two capture points; it does not negate the observed physical file changes or rule out activity between samples. The exact external operation that changed database pages was not traced and is not inferred from unchanged row digests.

| Audit finding | Before | Captured after | Result |
| --- | --- | --- | --- |
| Account `sync_queries` total | 195 | 195 | Unchanged |
| Active queries | 50 | 50 | Unchanged |
| Equivalent duplicate groups | 0 | 0 | Unchanged |
| Queries containing protected legacy IDs | 10 | 10 | Unchanged |
| Active protected-legacy queries | 0 | 0 | Unchanged |
| Query rows/specifications/cursors/attempts/lastSyncedAt | Full snapshot | Equal full snapshot | Zero changed rows |
| Catalogue rows | Full table digests | Equal | Zero observed logical changes |
| Product/Variant rows | Full table digests | Equal | Zero observed logical changes |
| All other tables and schemas | Full digests | Equal | Zero observed logical changes |

Equivalent query detection uses the committed registry's canonical map-key ordering and sorted/deduplicated AND-filter semantics. Protected IDs come from the committed Phase 9 audit guard set (64 IDs); inactive queries are included. Five distinct legacy IDs occur in the ten retained query specifications:

| Protected legacy ID | Referencing query count | Disposition |
| --- | --- | --- |
| `PM_SUBCATEGORY_ce0bf39843417fca` | 2 | All inactive; retained unchanged; BLOCK_MIGRATION pending Phase 8 review. |
| `SYS_CATEGORY_ACCESSORIES` | 2 | All inactive; retained unchanged; BLOCK_MIGRATION pending Phase 8 review. |
| `SYS_CATEGORY_EXTERIOR_WALL_PAINTS` | 2 | All inactive; retained unchanged; BLOCK_MIGRATION pending Phase 8 review. |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH` | 2 | All inactive; retained unchanged; BLOCK_MIGRATION pending Phase 8 review. |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS` | 2 | All inactive; retained unchanged; BLOCK_MIGRATION pending Phase 8 review. |

Full retained query specifications remain documented in [docs/phase9-query-audit.json](docs/phase9-query-audit.json). They were neither rewritten nor reactivated. No Phase 8 mapping approval was granted.

## Test and analyzer results

| Check | Result |
| --- | --- |
| `flutter test --reporter expanded` | **247 passed, zero failed**, exit 0; final line `00:31 +247: All tests passed!`. Includes the existing production read-only catalogue audits and isolated Phase 8/7C regression proofs. |
| `flutter test test/catalogue_compiler_sync_test.dart --reporter expanded` | **47 passed, zero failed**, exit 0; final line `00:20 +47: All tests passed!`. |
| `flutter analyze` | **51 existing issues**, exit 1: 5 warnings, 46 infos, zero errors. Normalized diagnostic set exactly equals the committed Phase 9 verification baseline; zero added or removed diagnostics. |

The dedicated suite reverified deterministic compiler IDs/payloads and order independence; same-release idempotence; explicit Metal & Wood Enamels/Satin profiles; document/payload identity agreement; unchanged-release zero full pulls; Product form zero catalogue reads; quota backoff; equivalent-query deduplication; and protected legacy detection with unchanged specifications. Atomic import rollback, BUSINESS preservation, cursor safety and Product/Variant/SKU/barcode/history preservation also passed.

All sync tests use `FakeRemote`/`CountingRemote` and temporary SQLite databases. REST protocol tests use `MockClient`. The two existing production catalogue tests explicitly open `OpenMode.readOnly`, set `query_only=ON`, and only query production. No live Firestore HTTP client was invoked. No app launch command was run by this work.

## WAL/SHM and write safety

- Before capture: no WAL, SHM or rollback-journal sidecars for the account, backup or public-config files.
- Monitor samples and captured after audit: no such sidecars observed. No WAL/SHM creation by verification commands was observed. Sampling does not establish that the external app could not create a transient file between samples.
- **Zero production SQLite write transactions by verification commands:** production connections were opened read-only/query-only; tests with write-capable bootstrap/import paths used their own temporary databases.
- **External production writer present:** PID 11795, confirmed read/write account handle. Thus zero production writes overall and byte-identical production files cannot be certified.
- **Zero Firestore writes by verification commands/tests.** The external application's network activity was not monitored, so zero global Firestore activity during the interrupted interval cannot be certified.
- No production catalogue import, sync-query maintenance, Phase 8 migration, live refresh, brush `--apply`, seed script, deactivation, Product identity rewrite or Phase 10 work was performed.

## Final closure decision

**Phase 9B failed its stable-production acceptance conditions; Phase 9 remains NOT fully closed.** Initial preflight and code/test checks passed. The application then started, held a production write handle and changed the account/public-config file bytes. Passing tests and unchanged captured row digests cannot substitute for the required checksum equality and absence of an external writer.

This report is the only workspace file created by Phase 9B. Phase 9 implementation code, original report and production data were not modified by verification. Do not continue closure verification until NubiBill/testflutter is fully closed; rerun the complete stable interval as a fresh attempt while preserving this failure record. Awaiting review.

Local evidence: `/private/tmp/phase9b-before.json`, `/private/tmp/phase9b-audit.json`, `/private/tmp/phase9b-monitor.json`, `/private/tmp/phase9b-monitor.log`, `/private/tmp/phase9b-full-tests.log`, `/private/tmp/phase9b-dedicated-tests.log`, `/private/tmp/phase9b-analyze.log`. The read-only capture/monitor script is `/private/tmp/phase9b_verify.py`. Temporary evidence is not a committed artifact; required hashes, metadata, process details and outcomes are included above.
