# Phase 10H — Catalogue Provenance Contract and Backfill Feasibility

## Executive decision

**The minimum forward provenance token is one nullable Product field: `catalogueFingerprint`.** It must be a full-snapshot SHA-256, captured from the exact installed SYSTEM catalogue used by the resolved form. Release ID/data version/schema/compiler revision remain in the snapshot manifest for diagnostics; they are not duplicated in every Product. Variants inherit the owning Product token through `productId` and do not store a second token.

The read-only inventory found **no existing exact provenance field** in either model, Product payload, Variant payload, or the sole local release record. All 11 existing Product/Variant rows are **UNRESOLVED** for automatic backfill (0 EXACT, 0 AMBIGUOUS, 11 UNRESOLVED). No backfill is proposed. The current release descriptor is incomplete and cannot establish which catalogue snapshot each saved record used.

The provenance contract and per-record evidence are in [docs/phase10h-provenance-contract.json](docs/phase10h-provenance-contract.json) and [docs/phase10h-backfill-feasibility.json](docs/phase10h-backfill-feasibility.json). No app source, schema, Product, Variant, archive, release marker, or sync-query data has been changed. This phase does not implement the Phase 10G historical resolver.

## Preflight and production safety

- Active branch: `fix/product-master-audit`.
- Phase 10G report and manifest are committed in commit `2c09667010b4faaf17a6250353daf77298da2bbb`; working tree was clean at Phase 10H preflight.
- The complete Flutter suite is being run with an extended timeout because the guarded Phase 9C test intentionally observes for more than two minutes. Initial `runTests` invocation hit its fixed 30-second timeout. A clean full-suite terminal rerun reached and passed the Phase 9C guard (124-second observation; no process/checksum violation); the rerun's final suite totals are still pending.
- Account SQLite, account backup, and public-config SQLite were opened only with SQLite read-only mode for SELECT inventory. SHA-256 before and after the inventory matched:
  - Account DB: `7751a6cc30a1f3765067bcec646beb16b0dc9dd094e1ccacd0d4d23e7e1515ef`
  - Backup: `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651`
  - Public-config DB: `a81b30213ada2f9fbb962eb4c55b5824545048cf0be534dcc12d591dc9c93693`
- No Firestore requests/writes, production backfill, Release 4 installation, Product/Variant mutation, archive creation, or sync-query change occurred.

## Inventory findings

- `ProductModel` has category/subcategory IDs and attribute values but no catalogue release/fingerprint. `ProductVariantModel` likewise has no catalogue provenance.
- Product and Variant payload `version` is an entity mutation version, not a catalogue version. Neither payload has a usable `catalogueId`, data version, schema/compiler revision, or fingerprint.
- One local account release row exists: `PAINT_V1`, data version 3, published at `2026-10-03T08:17:12.255935Z`. Its schema revision, compiler revision, `contentFingerprint`, and proposed `catalogueFingerprint` are absent. The public-config database has zero catalogue release rows.
- Read-only inventory found 4 Product documents and 7 Variant documents (including soft-deleted/inactive rows and one orphan Variant). Local history counts were zero for inventory transactions, purchases, purchase bills, invoices, goods receipts, and purchase returns. No separate Product/Variant audit-snapshot model was found. No history rewrite is indicated by this evidence.
- The complete individual classification/value/unit references, record IDs, dates, parent IDs, state, and uncertainty classification are in the JSON feasibility artifact. Timestamps are reported as evidence only and were not used to assign provenance.

## Minimum contract and semantics

### Persisted key

`catalogueFingerprint` is nullable for backward compatibility and formatted `sha256:<64 lowercase hex characters>`. Its input is a canonical serialization of the **complete installed SYSTEM metadata snapshot** (all compiler input collections plus the release marker), ordered by collection and document ID with recursively ordered map keys. Semantic fields/statuses and identities are included; transport timestamps, local synchronization bookkeeping, and the `catalogueFingerprint` field itself on the release marker are excluded to avoid a self-referential hash. The value is a snapshot identity, not an authentication token.

The existing Release 4 `contentFingerprint` implementation is FNV-1a 64-bit and is explicitly documented in code as a change-detection hash, not authentication. It is not selected as the archive key. A future snapshot installer must persist the SHA-256 token in the installed release marker; Product creation must fail closed if that exact token is unavailable.

### Persistence and offline behavior

- Store the nullable token in Product JSON/payload, which is already the authoritative serialized SQLite and wire document. Do not add a mirrored SQL column.
- Capture the fingerprint alongside the resolved template. Product creation writes it in the same `runAtomicOperation` that writes the Product, Variants, unique keys/sequences, local rows, and outbox batch. The Product outbox payload carries the same field. Existing local transaction semantics ensure pending local values are not replaced by pulls.
- A normal edit preserves the saved token by not including it in mutable patch fields. A duplicate is a new Product and receives the token for its newly resolved form. A normal classification edit does not silently retag the record. Only a separately approved semantic migration may replace a fingerprint.
- Variant rows do not repeat the token. Historical Variant resolution first follows exact `productId` to the owning Product and uses its fingerprint; an orphan Variant fails closed.
- Older documents decode with `catalogueFingerprint == null`. Null/invalid provenance means raw-value/manual-review mode, never silent current-catalogue resolution.

### Archive key

The retained snapshot key is exactly `(catalogueFingerprint, collection, documentId)`. Store document ID and decoded payload identity independently and verbatim. Same-key, same-content repeats are idempotent; same-key, different-content is a hard collision and aborts. A future archive table and its source before-images/release marker must be written in the same transaction as snapshot reconciliation. No archive table is created in this phase.

## Ceiling and Basement proofs

- **Ceiling:** historical document ID `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` overlaps the Release 4 canonical document ID, while the historical payload `subcategoryId` is `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS`; the inventory records 22 installed-row references plus 21 references to the reference-only payload identity. ID-only lookup is ambiguous. The composite archive key distinguishes the rows only when the exact historical fingerprint is known. Existing records contain no such token, so none is assigned.
- **Basement:** old document identity `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING` and payload identity `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT` remain historical. Release 4 candidates `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_LIQUID` and `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_CEMENTITIOUS` are separate identities. No existing record is assigned either candidate's fingerprint and no automatic mapping is made.

These are contract-level identity proofs, not production resolution changes; the historical resolver is intentionally deferred.

## Backfill decision

| Kind | Rows | EXACT | AMBIGUOUS | UNRESOLVED | Automatic proposals |
|---|---:|---:|---:|---:|---:|
| Product | 4 | 0 | 0 | 4 | 0 |
| Variant | 7 | 0 | 0 | 7 | 0 |
| **Total** | **11** | **0** | **0** | **11** | **0** |

There is only one local release descriptor and it has no full-content fingerprint or compiler provenance. No immutable historical snapshot archive is available. Saved IDs/values demonstrate references, not which release was used. Consequently even a plausible candidate is not an exact backfill. Product dates are not used to infer a release. Orphan/inactive/tombstoned records remain unmodified and unresolved too.

## Migration and rollback design (not executed)

No SQL column is needed for the Product token because Product payload JSON already persists arbitrary wire fields. The future archive is separate and should use a composite primary key. Its table/index creation, exact preimage archive inserts, and release marker update must share a SQLite transaction under an app maintenance barrier. Inject failures after DDL and staged inserts; compare `sqlite_master`, schema version, release marker, source catalogue rows, sync queries, Products, Variants, and outbox to the exact preimage. Re-run identical input to prove idempotence; reject same-key/different-content.

No production schema migration or backfill was attempted. No Release 4 install was attempted.

## Changed files and validations

- New: [docs/phase10h-provenance-contract.json](docs/phase10h-provenance-contract.json)
- New: [docs/phase10h-backfill-feasibility.json](docs/phase10h-backfill-feasibility.json)
- New: [phase10h.md](phase10h.md)
- `flutter analyze` completed with exit code 1 and reported 49 lint/info/warning issues, all in untouched Dart files; no Phase 10H source files were added or changed. This phase did not attempt unrelated lint cleanup.
- No disposable-SQLite archive/rollback simulation or new provenance-specific test was run. Ceiling/Basement and backfill conclusions are evidence-based identity/inventory analysis; archive collision/idempotence and future migration rollback remain specified acceptance tests, not claimed as passed.
- No Dart/source/database changes. The complete-suite result and final filesystem/safety verification remain pending while the extended-timeout test command finishes.
