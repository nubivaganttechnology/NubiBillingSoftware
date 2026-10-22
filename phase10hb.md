# Phase 10H-B — Provenance Contract Proof

## Scope and safety

Verification-only closure of the Phase 10H provenance contract. Added disposable/in-memory proof infrastructure under `test/` and a direct test dependency on `crypto` for SHA-256. No application model, production schema, historical resolver, protected sync query, Product/Variant production record, release marker, or production archive was changed. No Release 4 installation or Firestore access was performed. All SQLite tables added by this phase use the test-only name `phase10hb_catalogue_archive` and exist only inside FFI databases under system temporary directories.

Preflight confirmed branch `fix/product-master-audit`, Phase 10H artifacts present, and these tracked/untracked changes before proof work: the Phase 10H report and JSON files were untracked; the branch head was `2c09667010b4faaf17a6250353daf77298da2bbb`. Production hashes at preflight:

- Account SQLite: `7751a6cc30a1f3765067bcec646beb16b0dc9dd094e1ccacd0d4d23e7e1515ef`
- Backup (hash only; no SQL reads): `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651`
- Public-config SQLite: `a81b30213ada2f9fbb962eb4c55b5824545048cf0be534dcc12d591dc9c93693`

## Proof implementation

- Test-only snapshot fingerprints use SHA-256, represented as `sha256:<64 lowercase hex characters>`. Canonical input is UTF-8 JSON; collections sort lexically, document IDs sort lexically within each collection, map keys sort recursively, and array order is retained. Semantic fields, statuses, defaults, options, unit rules, document identity, and payload identity are hashed. Local sync bookkeeping and `catalogueFingerprint` are excluded to avoid self-reference.
- The disposable archive schema uses composite primary key `(catalogueFingerprint, collection, documentId)`, stores `documentId` and decoded `payloadId` independently, and preserves the original payload JSON plus canonical collision-comparison content. Identical replay is a no-op; same-key/different-content throws without overwriting.
- Product JSON round-trip preserves a valid nullable `catalogueFingerprint`; a legacy payload without it resolves to `PROVENANCE_MISSING`. Variants carry no duplicate fingerprint and inherit from their exact `productId` parent. Missing/orphan parent fails closed.
- Offline create proof reads a known fingerprint from a disposable installed release marker, then writes Product, Variant, and outbox rows through the existing `OfflineFirestoreService.runAtomicOperation`. Product payload/outbox fingerprint equality is asserted. An injected action failure proves Product, Variant, and outbox preimages are unchanged.
- Normal edit and classification patch use the existing offline document update path; both retain the saved fingerprint. Missing provenance never falls back by current document ID, name, or timestamp.
- Ceiling uses two fingerprints for the overlapping document ID and independently retains historical payload identity. The same document ID has two archive rows, while exact fingerprint selects the intended historical or canonical row. Null provenance returns `PROVENANCE_MISSING`.
- Basement legacy identity remains absent from the Release 4 Liquid/Cementitious identities. The Release 4 fingerprint resolves only those exact canonical IDs; legacy null provenance fails closed.
- Backfill evidence is re-read from the Phase 10H feasibility artifact. The proof asserts 0 EXACT, 0 AMBIGUOUS, 11 UNRESOLVED and zero automatic proposals; it does not reinterpret candidate IDs/dates/names.
- Disposable transaction tests inject failure after archive schema creation, after archive insert, and after release-marker staging/before commit. Each compares `sqlite_master`, archive-table existence/rows through schema state, release marker, Products, Variants, outbox, and sync queries against the preimage. Identical archive transaction replay is also asserted idempotent.

Proof code: [test/phase10hb_provenance_contract_test.dart](test/phase10hb_provenance_contract_test.dart) and [test/support/phase10hb_provenance_proof.dart](test/support/phase10hb_provenance_proof.dart).

## Validation status

- Focused provenance proof tests: 23 passed, 0 failed after the final strengthening to read fingerprint from a disposable release marker, use the existing atomic write path, inject a failure during outbox enqueue, and exercise actual offline edit semantics.
- Full workspace suite: `flutter test --timeout 5m --reporter expanded` completed successfully: 656 passed, 0 failed. Final output is captured in `/tmp/phase10hb-final-tests.log`.
- `flutter analyze`: completed with exit code 1 and 48 findings. The new proof files have no analyzer diagnostics. The remaining findings are in untouched files: existing style/info/warnings, one invalid annotation target, and two test dependency lint observations. No unrelated application lint cleanup was performed.
- Production postflight hashes match preflight exactly: account `7751a6cc30a1f3765067bcec646beb16b0dc9dd094e1ccacd0d4d23e7e1515ef`; backup `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651`; public-config `a81b30213ada2f9fbb962eb4c55b5824545048cf0be534dcc12d591dc9c93693`. Backup was hash-only; the production SQLite databases were not written.
- The test-only remote adapter throws on every Firestore/network method and records calls; all focused proof tests assert the count remains zero. No Firestore access/writes occurred.

## Final changed paths

- Modified dependency declaration/lock only to declare the SHA-256 helper dependency for test code: `pubspec.yaml`, `pubspec.lock`.
- New disposable proof suite and helper: [test/phase10hb_provenance_contract_test.dart](test/phase10hb_provenance_contract_test.dart), [test/support/phase10hb_provenance_proof.dart](test/support/phase10hb_provenance_proof.dart).
- New Phase 10H-B report: [phase10hb.md](phase10hb.md). Phase 10H inventory/contract artifacts remain as untracked prior-phase outputs.

This report will be finalized after those commands complete. Passing proof tests validate only disposable contract mechanics; they do not implement or approve production migration, Phase 10G historical resolution, Release 4 installation, or any historical backfill.
