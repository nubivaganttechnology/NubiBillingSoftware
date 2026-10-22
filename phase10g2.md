# Phase 10G2 — Versioned Legacy Catalogue Archive and Resolution

## Outcome

Implemented local snapshot identity, immutable catalogue archive storage, transactional snapshot preservation, Release 4 creation provenance, and fail-closed historical resolution. All archive/upgrade verification used isolated SQLite FFI databases. This is implementation plus disposable-test validation only: production migration, production Release 4 installation, historical backfill, and Firestore access remain explicitly unapproved and were not performed.

## Contract and implementation

- Snapshot identity is `sha256:<64 lowercase hex>` over deterministic UTF-8 JSON. Collection/document IDs and map keys are sorted; arrays preserve order; semantic fields and identities participate; fingerprint self-reference and local synchronization bookkeeping are excluded. This is separate from the existing FNV `contentFingerprint`.
- The local archive uses composite key `(catalogueFingerprint, collection, documentId)` and retains both source document ID and decoded payload ID, original payload JSON, and canonical collision-comparison content. It contains the seven approved metadata collections only; Products and Variants are never archived in this table.
- Current non-deleted SYSTEM catalogue rows are archived before reconciliation and in the same SQLite transaction as the incoming release marker. Archive collision aborts; exact replay is idempotent. Failure checkpoints cover pre-archive, inserted archive rows, post-archive, and release-marker boundaries.
- A legacy installed marker lacking a token is fingerprinted from exact installed metadata; this derives snapshot identity only and never assigns provenance to old Product/Variant records. Matching same-version/same-content markers with a token are no-ops.
- New Product creation requires exactly one installed SYSTEM Release 4 marker with the expected schema/compiler revisions and a valid SHA-256. The token is carried on Product creation only; Variants inherit via `productId`. Normal edits retain the original Product token.
- Existing Products are read against their exact saved token using a local-only resolver. Invalid/null provenance returns explicit `provenanceMissing`; unknown archive token returns `archiveNotFound`. Neither path falls back to current selectors, display names, IDs alone, or timestamps. Product listing carries the resolution status while preserving saved Product fields.
- Ceiling keeps the historical payload identity distinct from the Release 4 payload under the overlapping document key, with fingerprint selecting the namespace. Basement legacy identity remains separate from Release 4 Liquid/Cementitious IDs; no mapping or retagging is introduced.

Contract artifact: [docs/phase10g2-legacy-archive-contract.json](docs/phase10g2-legacy-archive-contract.json).

## Disposable test evidence

New tests in [test/phase10g2_legacy_archive_test.dart](test/phase10g2_legacy_archive_test.dart) cover:

- v3-to-v4 snapshot archive, exact historical resolution, raw null-provenance behavior, Product/Variant payload preservation (4 Products and 7 Variants), and unchanged outbox/sync-query state;
- rollback when failure is injected before archival, after the first archived row, and after archival;
- same-key/different-payload collision rejection and idempotent Release 4 replay;
- Ceiling overlapping document identity and Basement split-identity no-remap cases.

The complete suite passed: **663 passed, 0 failed**, using `flutter test --timeout 5m --reporter expanded`; output is in `/tmp/phase10g2-full-tests.log`. Focused archive tests passed 7/7. Product creation tests in `offline_sync_test.dart` passed 2/2, and `system_catalogue_test.dart` passed 7/7.

`flutter analyze` still exits non-zero with **48 existing info/warning diagnostics** in unrelated files. No diagnostics remain in the changed implementation or new archive test files. `git diff --check` passed.

## Production safety verification

No production database was opened by the implementation/tests; only temporary FFI databases were used. No production schema migration was executed, no Release 4 snapshot was installed in production, no Product/Variant records were read or changed, no backfill was run, no sync query was changed, and no Firestore request was made. The local schema migration code is present for future execution when an account database is opened by the upgraded app.

Hash-only postflight of the identified account and public-config SQLite files matched the recorded Phase 10H baseline:

- Account: `7751a6cc30a1f3765067bcec646beb16b0dc9dd094e1ccacd0d4d23e7e1515ef`
- Public config: `a81b30213ada2f9fbb962eb4c55b5824545048cf0be534dcc12d591dc9c93693`
- Backup: the previously recorded hash-only baseline is `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651`; no backup file was present in the searched Documents location for a fresh postflight hash.

No Flutter app was connected to the Dart Tooling Daemon, so no hot reload/restart was possible; no app was launched.

## Changed paths

Implementation: [lib/data/catalogue/catalogue_fingerprint.dart](lib/data/catalogue/catalogue_fingerprint.dart), [lib/data/catalogue/system_catalogue_snapshot.dart](lib/data/catalogue/system_catalogue_snapshot.dart), [lib/data/local/catalogue_archive_store.dart](lib/data/local/catalogue_archive_store.dart), [lib/data/local/local_database.dart](lib/data/local/local_database.dart), [lib/data/models/product_model.dart](lib/data/models/product_model.dart), [lib/data/repositories/product_repository.dart](lib/data/repositories/product_repository.dart), [lib/data/services/historical_catalogue_resolver.dart](lib/data/services/historical_catalogue_resolver.dart), [lib/data/services/offline_firestore_service.dart](lib/data/services/offline_firestore_service.dart), [lib/core/constants/firebase_constants.dart](lib/core/constants/firebase_constants.dart), [pubspec.yaml](pubspec.yaml), [pubspec.lock](pubspec.lock).

Tests: [test/phase10g2_legacy_archive_test.dart](test/phase10g2_legacy_archive_test.dart), [test/offline_sync_test.dart](test/offline_sync_test.dart), [test/system_catalogue_test.dart](test/system_catalogue_test.dart).

No commit was created.
