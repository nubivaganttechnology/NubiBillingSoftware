# Phase 10IB — Product/Variant Write-Path Closure

**Outcome: disposable-clone Product/Variant write-path rehearsal passed. Production migration, Release 4 installation, and business writes remain unapproved.**

## Scope and safety boundary

Phase 10IB exercised only the post-upgrade business write path against two disposable child copies of the migrated Phase 10I account clone. One child received a successful Product/Variant create; the other was used for an injected rollback. Both were hash-checked against the upgraded clone before the attempt. The source account and public-config database files were not opened writable; their final byte sizes and SHA-256 hashes matched the preflight values.

The test exercised `ProductRepository.createStructuredProduct()` through the offline transaction path with instrumented remote adapters. The rehearsal observed **0 remote/Firestore calls**. Separately, the named original source database files were checked read-only for hashes after the rehearsal, matching the previously recorded Phase 10I preflight hashes; these file hash/size observations are not assertions performed by the Phase 10IB clone test. It did not install Release 4 or create any Product on the real production databases. No Phase 11 work was performed. This is clone-only evidence, not authorization for production activity.

## Successful write evidence

- The installed Release 4 contract selected a READY canonical subcategory with **137** selectors/forms available in the upgraded clone.
- The repository path created Product `PROD-72AB9C80FCF44503A2AF5EFAB9F9A3EB` and Variant `VAR-43AF9D4521F24CF38A2CEF49615E5D19` (SKU `SKU-0007`; unique barcode generated for this run). These IDs and values are observed run output, not fixed regression expectations.
- The Product’s `catalogueFingerprint` and its queued outbox Product payload carried the exact Release 4 fingerprint: `sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88`.
- `ProductValidator` accepted the payload. Local repository read-back returned the new Variant under the saved Product and retained the exact Product fingerprint.
- The Variant’s exact `productId` points to that Product; it carries no separate catalogue fingerprint. Provenance is therefore resolved through the parent Product rather than duplicated onto the Variant.
- SKU and barcode uniqueness were checked after the write. A duplicate-barcode attempt was rejected and left the complete local database state unchanged.
- Historical null-provenance Products remained fail-closed; no provenance was inferred for them.

## Preservation and rollback

The successful create left the pre-existing **4 Products**, **7 Variants**, and **195 sync-query definitions** unchanged. All **3,903** archived legacy rows were preserved with the same archive digest before and after the write (`0c079f234caca60ea3910189ea9448eeeca5953232d29cc88343ab69bd33e563`).

On the separate failure child, an injected exception occurred after Product creation had been staged and before Variant creation. The full captured SQLite state after failure exactly matched its pre-attempt state, demonstrating transactional rollback of the partial create.

## Verification

- Dedicated Phase 10I/10IB clone rehearsal: passed after the final canonical-unit fixture correction.
- Full sequential Flutter suite with the verified clone environment enabled: **passed — 664 passed, 0 failed, 0 skipped**. Phase 10IC records the final closure.
- `flutter analyze`: 48 workspace-wide infos/warnings, no errors. No diagnostics were reported for the Phase 10IB rehearsal test; the findings are outside this change. The analyzer exits non-zero because of those repository-wide findings.
- `git diff --check`: passed.
- Final original-source hashes and detailed machine-readable results: [docs/phase10ib-business-write-closure.json](docs/phase10ib-business-write-closure.json). See [phase10IC.md](phase10IC.md) for the final verification closure.

## Gate decision

Phase 10IB closes the tested new-business write path on disposable, production-shaped upgraded clones only. It does **not** authorize Release 4 installation, migration, Product/Variant creation, or any other write on production databases. The source files remain unchanged, Firestore was not accessed by the rehearsal, and Phase 11 remains out of scope.
