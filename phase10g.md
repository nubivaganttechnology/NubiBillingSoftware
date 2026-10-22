# Phase 10G — Legacy Metadata Retention and Historical Resolution

## Status: blocked before implementation

Phase 10G cannot safely deliver an automatic historical resolver under the current record contract. Discovery confirmed that saved `ProductModel` rows contain classification IDs and saved values, but no catalogue release fingerprint or other exact metadata-version discriminator. The Ceiling case is decisive: the historical Product payload identity differs from the installed document ID, but the document ID itself is also the Release 4 canonical subcategory ID. An ID-only resolver therefore cannot distinguish a pre-release Product from a Product created against Release 4 metadata.

The proposed artifact records the deterministic row selection and exact identity exceptions, but does **not** authorize or implement a database upgrade, import, retention write, migration, or resolver change: [docs/phase10g-legacy-retention-manifest.json](docs/phase10g-legacy-retention-manifest.json).

## Request constraints preserved

- No production account/public-config database was opened or modified for Phase 10G.
- No Firestore calls were made.
- No Release 4 install, Product/Variant/history/query rewrite, name matching, ID alias, option/unit substitution, or semantic rewrite was performed.
- The Phase 10F approval state remains false; Phase 10G adds no approval.

## Evidence and discovery

- Baseline branch: `fix/product-master-audit`; starting commit `f982133d6151c8ad807c8c09a91681057aa0403f`; working tree was clean at preflight.
- The complete Flutter test suite passed **633/633** before any Phase 10G artifact was added. The existing guarded observation reported unchanged account/backup hashes and no process/checksum violation.
- Phase 10E source inventory SHA-256 was independently rechecked against the Phase 10G manifest: `3af5a17dd23b8aae66385c75519ca01bd007e4b9e742138317d053f9b553b50f`.
- Deterministic retention projection resolves to **2,750 unique source rows**: 242 `LEGACY_RETAIN_REQUIRED`, 2,506 `REVIEW_REQUIRED`, and 2 `MIGRATION_REQUIRED`. These are references into the source inventory using `(collection, documentId)`; rows must not be merged by display or payload identity.
- The inventory contains 2,267 review-required historical template rows, six deactivated attribute rows, 163 referenced deactivated option rows, five deactivated unit rows (one referenced), and ten protected sync queries. All remain unapproved.
- The manifest independently checked the Ceiling and Basement installed document IDs and their distinct payload subcategory IDs/reference-only identities. No target candidates are approved as remaps.

## Relevant code behavior

- `SystemCatalogueSnapshot.import` validates the complete snapshot and reconciles metadata within one SQLite transaction. Its complete-query reconciliation can mark absent SYSTEM rows inactive or deleted; the release marker is written last.
- `ProductTemplateResolver` excludes inactive attributes/options/templates and resolves units from active unit rows. Retained rows alone therefore do not make historical forms resolve.
- The normal `CatalogueSelectionResolver` is the Create Product eligibility gate and must remain isolated from historical metadata.
- `ProductRepository.updateStructuredProduct` currently validates and resolves against active metadata. A legacy-only historical template cannot be substituted there without a discriminator and a separately scoped validation path.
- `ProductModel` has no catalogue release/version/fingerprint field. Creation time is not an exact metadata-version token; using it as one would be an unapproved heuristic and can select the wrong template for an offline-created or post-release Product.

## Proposed design, not applied

If an exact per-record version discriminator is approved and available, the bounded design is:

1. In the same SQLite transaction as a future approved snapshot reconciliation, append the exact preimage rows selected by the manifest to a local, append-only snapshot store keyed by `(sourceReleaseFingerprint, collection, documentId)`. Preserve decoded source fields and both document/payload identities. Do not touch Product, Variant, historical, or sync-query rows.
2. Keep normal Create Product selectors, template resolution, and validation canonical-only. Add an explicit historical-resolution API that requires the saved record's exact release/version token and reads only that retained version.
3. Fail closed when provenance is missing, the version is ambiguous, or a protected query/owner would need rewriting. Do not fall back to a display name, target candidate, nearest timestamp, or current canonical metadata.
4. Prove the archive/import transaction and resolver only in disposable SQLite fixtures, including rollback, idempotence, canonical selector isolation, and the Ceiling/Basement document-versus-payload identities.

This design is not implemented because the current persisted Product/history contract cannot supply step 2's exact version token. Adding/backfilling a provenance field would change existing records and is outside the requested no-migration boundary; selecting by date or ID would not meet the exact-version requirement.

## Required decision to resume

Provide either (a) an already-persisted, exact catalogue-version discriminator and its source for affected Product/history records, or (b) explicit authorization for a narrowly scoped provenance-field/backfill plan plus a migration/rollback approval. Until then, automatic historical resolution and snapshot installation remain blocked. No protected owner needs to be mutated and no Firestore dependency is proposed.

## Validation boundary

The 633-test result is the pre-Phase-10G source baseline, not a claim that an implementation was validated. The only new deliverables are this status report and its read-only manifest. The manifest source hash and row selection count were checked against the committed Phase 10E evidence. No Dart source changes were made, so no Flutter reload/restart was needed.
