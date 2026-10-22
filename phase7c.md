# Phase 7C — Atomicity and Identity Proof

**Phase:** `PHASE_7C_ATOMICITY_AND_IDENTITY_PROOF`
**Date:** 2026-10-04
**Status:** Atomicity, identity, confirmation and integrity acceptance checks PASS. Full suite: **168/168 passed**. Analyzer: **51 pre-existing issues, zero new diagnostics**. Ready for review.

## Preflight

| Check | Result |
| --- | --- |
| Active branch | `fix/product-master-audit` |
| Phase 7B committed | HEAD `b18882a5c493ba48a4bc0623f4a1f92cd18429ec` — Phase 7B reclassification planning, UI confirmation and soft-delete sync contract |
| Initial working tree | Clean |
| Baseline full suite | `flutter test --reporter expanded`: **149/149 passed**, exit 0 |
| Baseline analyzer | `flutter analyze`: **51 issues** (5 warnings, 46 infos, 0 errors), exit 1 |
| Production SQLite safety | Files hashed before tests and after final verification; all hashes identical |

The production database's current checksum differs from the historical checksum printed in `phase7b.md`. Phase 7C captured the actual current checksum before work and verified it afterward. This proves no change during this closure; it does not establish when the earlier discrepancy arose.

## Transaction model and failure injection

The exercised production path is `ProductRepository.updateStructuredProduct()` → `OfflineFirestoreService.runAtomicOperation()` → `LocalTransactionContext` → `SyncOutboxRepository.enqueue()`.

The offline service opens **one SQLite transaction**. The repository first stages its writes in `LocalTransactionContext`; the service then passes that same transaction executor to every enqueue. Each enqueue performs the local document UPSERT and its `sync_outbox` INSERT inside that transaction. A thrown persistence/enqueue exception escapes the callback and rolls back the entire operation. Successful local notification occurs after commit. Remote delivery is deferred through the outbox; these tests perform no remote delivery.

The five failure tests use **temporary SQLite triggers with `RAISE(ABORT, 'phase7c forced failure')`**. Triggers execute after actual Product/Variant UPSERTs or an actual outbox INSERT, rather than throwing before persistence. Trigger predicates verify the expected preceding writes have already happened. Tests require a `DatabaseException` containing the injected marker, so an unrelated validation failure cannot falsely pass.

Every test gets a separate database directory created with `Directory.systemTemp.createTemp('nubibill-phase7c-')`, the production `LocalDatabase` schema, real FFI SQLite, the real offline service and repository, and seeded test-only catalogue records. All temporary connections are closed and directories removed at teardown. No failure hooks were added to production.

Every rollback compares the complete before/after snapshot of **all local document tables, `sync_outbox`, `sync_queries`, and `sqlite_sequence`**. This includes payloads, deletion flags, revisions, timestamps, unique keys and SKU sequence state, beyond the required Product/Variant checks.

| Forced failure | Result and direct assertions |
| --- | --- |
| After Product update, before Variant updates | **PASS.** Product payload and metadata restored; all 3 original variants unchanged; no retirement or insertion; outbox empty. |
| While updating a preserved Variant | **PASS.** Failure after updating V2, with V1 already changed and Product outbox already written. Product and all variants restored; no partial outbox survives. |
| While inserting a new Variant | **PASS.** Failure after the new row exists and preserved updates have occurred. New row removed; Product, existing variants and SKU sequence restored; outbox empty. |
| During retirement of a removed Variant | **PASS.** Failure after V3 changes to `DELETED`, with a new variant and prior preserved updates present. V3 restored to original `ACTIVE` state; all earlier mutations rolled back; no tombstone outbox remains. |
| During `sync_outbox` enqueue | **PASS.** Failure after the retirement outbox row itself is inserted, with all local mutations and preceding outbox rows present. Entire local transaction and every outbox row roll back. |

The outbox is transactionally atomic with local Product/Variant persistence. The architectural stop condition does not apply.

## Identity results

These are assertions against actual SQLite-backed repository edits, not assertions on hand-constructed identity maps.

| Required scenario | Result |
| --- | --- |
| Classification change alone preserves `productId` | **PASS:** Product remains `P`; category/subcategory change; exactly one Product remains. |
| Classification change alone preserves surviving `variantId` | **PASS:** V1, V2 and V3 retain their IDs and parent Product. |
| Classification change alone preserves SKU | **PASS:** all original SKUs remain unchanged. |
| Classification change alone preserves barcode | **PASS:** all original barcodes remain unchanged. |
| Explicit SKU change updates the same `variantId` | **PASS:** V1 becomes `CUSTOM-01`; V1's ID and barcode, sibling identities and row count are unchanged. |
| Explicit barcode removal updates the same `variantId` | **PASS:** both empty-string and explicit-null removal are tested; V1 and its SKU survive. |
| New variant receives a new ID without altering existing IDs | **PASS:** all 3 existing IDs survive; exactly one additional ID appears, with generated SKU `SKU-0004`. |
| Retired ID never reassigned to unrelated new variant | **PASS:** V3 remains the same tombstone across later edits; new variants receive different IDs. An explicit attempt to reuse V3 is rejected with exact database rollback. |

Additional safety checks pass: explicit SKU collision with a preserved sibling whose SKU was omitted, generated SKU collision, and duplicate barcode input all reject without persistent side effects. Plan computation is read-only, reports the correct preserved/retired/new counts, and assigns no ID to the new input row.

## Confirmation and cancellation results

The widget tests open the real Product Management Edit page and select classifications through its actual selectors. To keep SQLite I/O outside Flutter's fake clock, the controller double serves a plan computed by the real repository before the interaction, verifies the UI's classification and surviving IDs against that plan, and spies on the save boundary. Successful UI payloads are then persisted through the real isolated repository. This tests the confirmation gate and cancellation separately from the transaction failure tests; it does not exercise a live authenticated `AppController` or remote sync.

| Required behavior | Result |
| --- | --- |
| Destructive `ReclassificationPlan` requires confirmation | **PASS:** actual dropped-attribute reclassification plan displays `Confirm Reclassification Impact`; save callback count remains 0. |
| Cancel causes zero Product writes | **PASS:** exact database snapshot unchanged; SQLite `total_changes()` delta is 0; save callback count remains 0. |
| Cancel causes zero Variant writes | **PASS:** all Variant payloads and metadata unchanged; same zero-change assertion. |
| Cancel causes zero `sync_outbox` writes | **PASS:** outbox remains empty; same zero-change assertion. |
| Non-destructive reclassification avoids unnecessary confirmation | **PASS:** tested for category change and subcategory-only change. No confirmation dialog; exactly one save callback. Persisting each captured UI payload preserves Product, Variant, SKU and barcode identities. |

## Orphan and duplicate integrity queries

The shared integrity helper runs after each representative success, rejected edit and forced rollback. It checks real SQL rows and the production local/product query APIs:

- **0 ACTIVE orphan variants:** SQL LEFT JOIN matches `local_product_variants.payloadJson`'s encoded `productId` to `local_products.remoteId`; no active, nondeleted row has a missing parent.
- **0 soft-retired variants in active/local Product queries:** IDs selected from rows with `status='DELETED' OR isDeleted=1` have an empty intersection with both the local variant query and `ProductRepository.getProducts()` results.
- **0 duplicate ACTIVE SKUs:** SQL groups active, nondeleted, nonblank values by tenant/business and trimmed, lowercase SKU; no group has `COUNT(*) > 1`.
- **0 duplicate ACTIVE barcodes:** the equivalent grouped query for barcode also returns no duplicate groups. Empty/null removed barcodes are excluded.

Retirement also directly verifies local `isDeleted=1` and an outbox `UPDATE` patch containing both `status='DELETED'` and `isDeleted=true`.

These results apply to the isolated representative edit fixtures. They are not a production catalogue cleanup or a claim that all historical production inventory has been audited.

## Production fixes required by failing tests

Tests-first closure exposed genuine defects; the authorized production-code exception was necessary:

1. **Explicit SKU edits were silently discarded.** The update allowlist now accepts and trims an explicit nonempty SKU on the same Variant. Effective SKU uniqueness includes preserved sibling values omitted from the incoming payload and generated codes, rejecting collisions within the transaction. The SKU field in the UI remains read-only; the explicit-change test exercises the repository API.
2. **Soft-retired variants leaked through local queries.** Retirement now includes `isDeleted=true` in its deterministic UPDATE patch. Outbox enqueue derives the local deletion flag from DELETE operations or tombstone fields, keeping local query visibility consistent with the persisted/sync contract.
3. **The Edit classification selectors discarded surviving identities.** Category changes and temporarily clearing the subcategory reset existing rows to a new placeholder. Edit now retains those rows and Product values while the next template loads, allowing the existing reconciliation to preserve IDs and prune attributes. The widget tests failed with `[null]` in place of `[V1, V2, V3]` before this correction.

The pre-fix forced rollback tests already passed. Production transaction boundaries required no changes. The failing evidence included `CUSTOM-01` remaining `SKU-0001`, a retired V3 appearing in the local query, generated SKU collisions being accepted, and the UI losing existing Variant IDs.

No changes to `ProductTemplateResolver`, `CatalogueSelectionResolver`, colour architecture, unit engine, placement rules, catalogue master data, or production Product/Variant IDs. No migration was performed. Phase 8 was not started.

## Files changed

| File | Change |
| --- | --- |
| `test/product_edit_atomicity_test.dart` | New 19-test isolated SQLite and widget proof suite, failure triggers, full-state snapshots and integrity queries |
| `lib/data/repositories/product_repository.dart` | Explicit SKU persistence/collision protection and deterministic retirement flag |
| `lib/data/sync/sync_outbox_repository.dart` | Apply tombstone fields to the local deletion flag within the same transaction |
| `lib/presentation/products/product_pages.dart` | Retain existing Edit rows while classification selection changes |
| `phase7c.md` | This closure report |

Changes are left uncommitted for review. Phase 7B remains the committed HEAD.

## Final verification

| Command/check | Result |
| --- | --- |
| `flutter test --reporter expanded` | **168/168 passed**, 0 failures, exit 0: `00:17 +168: All tests passed!` |
| New Phase 7C tests within full suite | **19/19 passed** (baseline 149 + 19 = 168) |
| `flutter analyze` | **51 pre-existing issues**, 5 warnings, 46 infos, 0 errors; exit 1. Normalized diagnostic set matches baseline exactly; zero new issues and no diagnostics in the new test file. |
| `git diff --check` | Passed |
| Real Firestore writes | **0** |
| Production SQLite writes | **0** |

Test/analyzer logs were captured at `/private/tmp/phase7c-baseline-tests.log`, `/private/tmp/phase7c-baseline-analyze.log`, `/private/tmp/phase7c-final-tests.log`, and `/private/tmp/phase7c-final-analyze.log`.

Flutter/Dart commands needed sandbox escalation for SDK cache/telemetry metadata outside the workspace. That access was used for verification and formatting, not for database writes.

## Production SQLite checksums

SHA-256 was computed by reading file bytes, without opening a writable SQLite connection. All three files existed at preflight and remain byte-identical afterward. No database WAL/SHM sidecars were present in the preflight file listing.

| File | Before SHA-256 | After SHA-256 |
| --- | --- | --- |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db` | `02741485aa4c73a9dc1c0f363a4517d6009adcb1351792f510ba4ce53970e21c` | `02741485aa4c73a9dc1c0f363a4517d6009adcb1351792f510ba4ce53970e21c` |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db` | `c641b3c18a4dcd49f09960476298db9a993a5f6382bf52294441975c08aad957` | `c641b3c18a4dcd49f09960476298db9a993a5f6382bf52294441975c08aad957` |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak` | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` |

The two pre-existing catalogue audit tests in the full suite open the production database with `OpenMode.readOnly`; all Phase 7C mutation tests use only temporary databases.

## Firestore safety and closure

The new fixture uses a `FirestoreRestService` double with **no HTTP client**. Every remote invocation increments a counter and throws. Every teardown asserts that counter is **0**. Background sync scheduling is disabled by a test-only SyncEngine subclass, and connectivity is offline. Existing REST tests use mock HTTP clients; the application was not launched and no Firestore operation was run against a live service.

All five forced mid-transaction failures leave zero partial state; no outbox rows survive rollback; cancellation makes zero writes; surviving identity is preserved; integrity checks pass; all workspace tests pass; production SQLite is unchanged. The analyzer remains at its pre-existing nonzero baseline. Phase 7C is ready for review; no Phase 8 work has begun.
