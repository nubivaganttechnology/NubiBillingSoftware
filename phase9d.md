# Phase 9D — Public-config production-safety closure

**Result: PASS. Phase 9 is FULLY CLOSED.** This completes the missing public-config acceptance item alongside committed Phase 9C. Public-config remained byte-identical throughout a clean read-only observation, with no detected app, write handle or sidecar. The schema and full-row digests of every table match before and after.

Date: 2026-10-04. Scope: Phase 9D verification only. Awaiting review; Phase 10 has not begun.

## Preflight

| Check | Result |
| --- | --- |
| Branch | `fix/product-master-audit` — confirmed. |
| Phase 9C commit | `78d2179efdbf647544294df5828f85424b99a908` — `fix(product-master): complete Phase 9C stable 120s production safety verification`. HEAD was this commit. |
| Initial working tree | Clean. |
| Initial application check | Unrestricted read-only process lookup: no testflutter/NubiBill matches; exit 1, empty output, no error. |
| Initial public-config handle check | Unrestricted read-only `lsof`: no handles; exit 1, empty output, no error. |
| Script preflight guard | `pgrep -ifl 'testflutter|nubibill'` and `lsof -Fpcfatn` on the target again returned no matches/handles. No writer present. |

The process checks used approved system process visibility. No application was launched or terminated. Phase 9B's historical failed observation and Phase 9C's report were preserved unchanged.

## Target metadata and complete SHA-256

Absolute path: `/Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db`

| Field | Before | After | Comparison |
| --- | --- | --- | --- |
| Size (bytes) | 937984 | 937984 | Equal |
| mtime (UTC) | 2026-10-04T11:04:11.757294+00:00 | 2026-10-04T11:04:11.757294+00:00 | Equal |
| mtime (nanoseconds since epoch) | 1791111851757294196 | 1791111851757294196 | Equal |
| Inode | 52052551 | 52052551 | Equal |
| SHA-256 | `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012` | `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012` | **Equal** |

Before capture began: **2026-10-04T12:04:59.305322+00:00**. After capture completed: **2026-10-04T12:05:59.570221+00:00**. Times are UTC (Asia/Kolkata = UTC+05:30).

## Guarded observation

- Observation start: **2026-10-04T12:04:59.316160+00:00**.
- Observation end: **2026-10-04T12:05:59.419692+00:00**.
- Measured duration: **60.105047 seconds**, exceeding the required 60 seconds.
- **13 samples**, at scheduled five-second intervals including the start and 60-second endpoint.
- Every sample checked case-insensitive app-process matches, DB write/read-write handles, size, mtime, inode, full SHA-256 and WAL/SHM/journal existence.
- Every sample passed. The guard was also rerun immediately before and after the final read-only audit.

| Sample | UTC | Elapsed seconds | Result |
| --- | --- | --- | --- |
| 1 | 2026-10-04T12:04:59.446136+00:00 | 0.129987 | No app/handles; stable file; no sidecars |
| 2 | 2026-10-04T12:05:04.424398+00:00 | 5.108373 | No app/handles; stable file; no sidecars |
| 3 | 2026-10-04T12:05:09.425415+00:00 | 10.109517 | No app/handles; stable file; no sidecars |
| 4 | 2026-10-04T12:05:14.444305+00:00 | 15.128541 | No app/handles; stable file; no sidecars |
| 5 | 2026-10-04T12:05:19.426462+00:00 | 20.110816 | No app/handles; stable file; no sidecars |
| 6 | 2026-10-04T12:05:24.428671+00:00 | 25.113151 | No app/handles; stable file; no sidecars |
| 7 | 2026-10-04T12:05:29.432592+00:00 | 30.117201 | No app/handles; stable file; no sidecars |
| 8 | 2026-10-04T12:05:34.423418+00:00 | 35.108152 | No app/handles; stable file; no sidecars |
| 9 | 2026-10-04T12:05:39.425785+00:00 | 40.110647 | No app/handles; stable file; no sidecars |
| 10 | 2026-10-04T12:05:44.440279+00:00 | 45.125267 | No app/handles; stable file; no sidecars |
| 11 | 2026-10-04T12:05:49.425736+00:00 | 50.110848 | No app/handles; stable file; no sidecars |
| 12 | 2026-10-04T12:05:54.432104+00:00 | 55.117344 | No app/handles; stable file; no sidecars |
| 13 | 2026-10-04T12:05:59.417302+00:00 | 60.102669 | No app/handles; stable file; no sidecars |

Final `pgrep` and `lsof` results: both **exit 1 with empty output and no errors**. No application processes and no public-config handles were present. The script classified both writable (`w`) and read/write (`u`) descriptors as stop conditions; none appeared. It would also have stopped on any app match, metadata/hash change or sidecar.

## Read-only audit and schema comparison

Production was opened only with `sqlite3.connect('file:…?mode=ro', uri=True)`. The script set `PRAGMA query_only=ON`, verified it equals 1, and set connection-local `PRAGMA busy_timeout=5000`. Trace assertions allowed only SELECT/PRAGMA statements. No writable LocalDatabase initialization, bootstrap, migration, seed, import, repair, backup restoration or app run occurred.

Schema digest covers sorted `sqlite_master` records with object type, name, table name and SQL. Every table, including SQLite internal tables, was read completely. Deterministic row digests canonicalize each complete row in column order, encode BLOBs as explicit hex values, sort canonical row representations and SHA-256 the canonical resulting list. Rows are not filtered or limited to active records; duplicate rows and their multiplicity are retained. Column definitions are protected by schema equality.

| Audit field | Before | After | Comparison |
| --- | --- | --- | --- |
| Schema SHA-256 | `66052e9e59b4aa992fcbdba7bd4f6c5f5cc77b7753656008fa77c0e344009f5b` | `66052e9e59b4aa992fcbdba7bd4f6c5f5cc77b7753656008fa77c0e344009f5b` | **Equal** |
| Schema objects | 212 | 212 | Equal |
| Tables audited | 56 | 56 | Equal |
| Traced statements | 60 | 60 | SELECT/PRAGMA only |
| Write transactions | 0 | 0 | None |
| Full table/column/count/digest comparison | Complete | Identical | **PASS** |

Each full SHA-256 below is identical before and after; both row counts are shown explicitly.

| Table | Rows before | Rows after | Full-row SHA-256 before = after |
| --- | --- | --- | --- |
| `local_app_config` | 1 | 1 | `ec321729681401fc2bc043028bb6fff0f342c2a32aef1bd938dd4c4b65a490a2` |
| `local_brands` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_business_name_reservations` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_business_sub_types` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_business_types` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_businesses` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_customers` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_document_sequences` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_employees` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_godown_code_reservations` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_godowns` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_goods_receipt_items` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_goods_receipts` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_hsn_codes` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_inventory_transactions` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_invoices` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_outlets` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_pack_sizes` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_payment_allocations` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_permissions` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_product_attribute_options` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_product_attributes` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_product_catalogue_releases` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_product_categories` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_product_classification_options` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_product_subcategories` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_product_unique_keys` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_product_variants` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_products` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_purchase_bills` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_purchase_order_items` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_purchase_orders` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_purchase_returns` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_purchases` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_racks` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_roles` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_shades` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_shelves` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_stock_balances` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_storage_locations` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_subcategory_attribute_templates` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_supplier_balances` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_supplier_businesses` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_supplier_credits` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_supplier_ledger_entries` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_supplier_payments` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_supplier_products` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_suppliers` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_units` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `local_user` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `sqlite_sequence` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `sync_conflicts` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `sync_control` | 1 | 1 | `f63c843f18c7d7d19d3bf253e75c37ca472b6148c3d3c2a54369d483147cf7b9` |
| `sync_lease` | 1 | 1 | `c4127581130098d6541ac3d34db96a5f08966cdc678f300baed5e5d9908ed67a` |
| `sync_outbox` | 0 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `sync_queries` | 1 | 1 | `ced05f8bf7e4204ada5c3a464182dcd2fdc69e09217bee9afc60e3f7c6772115` |

## Sidecars and write safety

| Sidecar | Before | All 13 samples | After |
| --- | --- | --- | --- |
| `-wal` | Absent | Absent | Absent |
| `-shm` | Absent | Absent | Absent |
| `-journal` | Absent | Absent | Absent |

**Zero production SQLite writes by this verification.** Production connections enforced read-only/query-only, traced statements contained no mutation, no write transaction was opened, and the file bytes and monitored metadata remained identical.

**Zero live Firestore access and zero Firestore writes by this verification.** The script uses only local filesystem, process inspection and Python SQLite/hash libraries; no network or Firestore client was created or called.

## Strict acceptance and closure decision

| Criterion | Result |
| --- | --- |
| No app process appears | PASS — none in preflight, all samples and final guards. |
| No write/read-write DB handle appears | PASS — none. |
| Public-config SHA-256 before equals after | PASS — complete hashes above are identical. |
| Size and monitored metadata stable | PASS — size, mtime and inode identical throughout. |
| No WAL/SHM/journal appears | PASS — absent in every observation. |
| At least 60 seconds, five-second sampling | PASS — 60.105047 seconds, 13 samples. |
| Schema digest identical | PASS. |
| Every table row count/full-row digest identical | PASS — all 56 tables. |
| Zero production SQLite writes | PASS. |
| Zero live Firestore access/writes | PASS. |

**All Phase 9D conditions passed. With committed Phase 9C and this completed missing public-config check, Phase 9 is marked FULLY CLOSED.** This decision applies to the completed safety observations; earlier interrupted intervals remain preserved as historical evidence.

No architecture work or full-suite rerun was performed in Phase 9D. Test/analyzer results remain those recorded in committed Phase 9C; this task only supplied the missing public-config proof. No production catalogue changes, sync-query cleanup or Phase 8 migration was performed. No Phase 10 work began.

Workspace deliverable: **`phase9d.md` only**, uncommitted for review. Existing code and prior reports remain unchanged.

Local evidence: `/private/tmp/phase9d-evidence.json` (full before/after schema and table digests, all samples and guard outputs), `/private/tmp/phase9d-monitor.log`, `/private/tmp/phase9d_verify.py`. Required metadata, digests, process outcomes and decision are included in this report, so closure does not depend on retaining temporary files.
