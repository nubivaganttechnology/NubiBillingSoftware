# Phase 10E — Basement split and isolated Catalogue Release 4

**Status: COMPLETE for release construction and isolated verification; production installation remains BLOCKED and unapproved.** The user-approved domain split replaces one ambiguous prospective Basement contract with two distinct contracts. Release 4 has 137 canonical, selector-visible READY forms. No production catalogue, Product/Variant, historical reference or sync-query mutation was performed.

## Preflight and scope

- Branch: `fix/product-master-audit`; initially clean working tree.
- Phase 10D committed at `bc672649c288709d9c97556ce51d761ae1862b11`.
- Complete pre-change baseline: **465/465 passed**.
- Account, backup and public-config hashes, size, mtime and sidecars captured before tests/inspection. Account/public-config SQL used `mode=ro` and `PRAGMA query_only=ON`; backup was hash-only.
- No Phase 8 migration, production import, retirement, selector-flag change, sync-query cleanup, live publication, Firestore access or Phase 11 work.

## Approved Basement contracts

New immutable IDs use explicit material keys rather than insertion order or mutable display labels:

- Liquid: `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_LIQUID`.
- Cementitious/Powder: `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_CEMENTITIOUS`.

| Contract | Liquid | Cementitious/Powder |
| --- | --- | --- |
| Family | WATERPROOFING_LIQUID | WATERPROOFING_CEMENTITIOUS |
| Measurement dimension | VOLUME | MASS |
| Allowed pack/base units | Litre, Millilitre | Kilogram, Gram |
| Default pack/base unit | Litre | Kilogram |
| Allowed selling units | Litre, Millilitre | Kilogram, Gram |
| Selling default | Unset; explicit user selection | Unset; explicit user selection |
| Conversion allowed/default | false / OFF | false / OFF |
| Explicit factor required if future contract enables conversion | true | true |
| Usage default | Interior & Exterior | Interior & Exterior |
| Surface default/options | Concrete, Wall, Floor | Concrete, Wall, Floor |

Both retain the verified optional technical fields: Coverage, Drying/Recoat Time, Mixing Ratio, Shelf Life, VOC and Warranty. Required variant fields are Pack Size, Pack Unit and Sold As. Technical numeric/chemistry defaults are not fabricated. No Bucket/Bag/Can presentation default, mixed MASS/VOLUME menu, paint finish/colour chemistry or container conversion is introduced. The minimally valid form tests explicitly supply the required selling choice; that choice is not a catalogue default.

The installed document ID `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING` and historical payload ID `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT` remain unresolved legacy identities. Each has **14 local template dependencies, zero Product dependencies and zero sync-query dependencies**. Neither is reused for a split form or automatically mapped to either material. Both retain `migrationApproved=false`, `retirementApproved=false` and `automaticReferenceMappingAllowed=false`.

## Release artifact and canonical accounting

- `PAINT_V1`: data version **4**, schema revision **1**, compiler revision **6**.
- Accounting: **136 − 1 ambiguous Basement + 2 split forms = 137**; **137 READY**, **zero blocked required contracts**.
- All other **135 Phase 10C candidate contracts remain exactly unchanged**, including the ten reviewed canonical duplicate decisions.
- Selector output equals the intended READY **ID set exactly**: **137**. The expected set is derived from metadata, not the historical 49/59/147 baseline.
- Miscellaneous, Hand Sanitizers, historical Paint/Interior Wall Paint, ten legacy duplicate members, old Ceiling payload templates and both old Basement identities remain noncanonical. BUSINESS rows are outside SYSTEM snapshot ownership.
- Historical Phase 10A/B/C/D evidence and archived v3 fixture are unchanged.

Runtime CatalogueContract fingerprint: `b29528b8ed70428c`.

Deterministic semantic SHA-256: `3f02fef8f5ce368757f28c0b64ab797f19585efbeb0dd5263a4b1a38cac285ef`.

Generation reconstructs the saved artifacts exactly through deterministic JSON serialization. Reordered candidates, attributes, options and audit rows produce identical release content/fingerprints. Label edits preserve IDs; default, option, unit-rule, requiredness and placement changes alter fingerprints. Non-semantic timestamps are excluded by the existing fingerprint contract.

Subcategory IDs come from the reviewed immutable canonical keys. Template IDs use the immutable `(subcategoryId, attributeId)` tuple. Option identities reuse the explicit Phase 9 registry; otherwise a stable digest of `(attributeId, semanticCode)` is used. Semantic codes are distinct from display labels. Units use the existing immutable registry. Every document/payload identity agrees.

| Collection | Release 4 rows |
| --- | ---: |
| product_attribute_options | 167 |
| product_attributes | 44 |
| product_catalogue_releases | 1 |
| product_categories | 21 |
| product_subcategories | 137 |
| subcategory_attribute_templates | 2032 |
| units | 21 |

The [review manifest](docs/catalogue-release-v4-review.json) and [isolated fixture](test/fixtures/system_catalogue_v4.json) have `isolatedOnly=true` and all live execution/migration/Firestore-publication approvals false. The fixture release row has `published=true` solely to exercise the actual importer’s release contract in temporary SQLite; no release was published or installed live.

## Actual import, idempotence and rollback

`SystemCatalogueMetadata.compile` preserves the revision-6 explicit release without heuristic regeneration; `CatalogueContract` validates it. Fresh temporary SQLite imports through **SystemCatalogueSnapshot**, decodes through **LocalDataSource**, resolves through **ProductTemplateResolver/CatalogueSelectionResolver** and validates through **ProductValidator**. The installed temporary marker reports version 4/schema 1/compiler 6 with the expected fingerprint.

Identical second import is a **true no-op**: complete logical state of every SQLite table matches, including payloads, timestamps, internal sequences, installed marker, existing sync-query registrations/cursors and outbox. No extra rows/IDs/queries or changed fingerprint.

Controlled `failureProbe` callbacks throw inside the actual transaction at each stage. Each test starts from an imported v3 test release and nonempty business Product, Variant/SKU/barcode and outbox sentinel state. Full-table equality proves all prior state, cursors and release 3 survive:

| Injected failure | Result |
| --- | --- |
| After categories | PASS — complete rollback |
| After subcategories | PASS — complete rollback |
| After attributes | PASS — complete rollback |
| After options | PASS — complete rollback |
| After templates | PASS — complete rollback |
| Before release marker | PASS — complete rollback |
| After release marker, before commit | PASS — version 4 is observed inside the transaction, then complete rollback restores version 3 |

One genuine contract defect required a four-line production correction: `CatalogueContract.validate` applied option membership to valid TEXT defaults with `options=[]`. Membership now applies to SELECT/MULTI_SELECT; negative tests still reject out-of-set defaults for both enum types. Complete-snapshot validation, transaction boundaries, compiler revision and migration protections are unchanged. Runtime free-text master suggestions remain suggestions, not SELECT restrictions.

## Structural quality and form simulations

| Quality gate | Findings |
| --- | ---: |
| Document/payload mismatch | 0 |
| Same-parent normalized-name canonical duplicates | 0 |
| Duplicate active attribute-option identities | 0 |
| Missing attribute/option/parent references | 0 |
| Active orphan templates | 0 |
| Missing required templates | 0 |
| PRODUCT/VARIANT intersections | 0 |
| Invalid defaults | 0 |
| Invalid option defaults | 0 |
| Required fields under false visibility conditions | 0 |
| Unsupported conditions/missing condition targets | 0 |
| Invalid required unit contracts | 0 |
| Mixed MASS/VOLUME Basement contracts | 0 |
| Unexplained CRITICAL/HIGH findings | 0 |

- **137/137** candidate resolvers READY; **137/137** minimally constructible forms pass actual ProductValidator.
- **4,475 SELECT choices**, including **409 colour-mode cases**. Effective hidden fields are omitted and cease to be required; active colour identity is required only in its applicable mode.
- **238 conversion matrix cases**: 202 allowed measurement-base selections and 36 forbidden-conversion rejections; **339 invalid-conversion checks** cover cross-dimension bases, container bases, nonpositive factors and conversion-disabled families.
- Resolved defaults, requiredness, placement, constrained option sets and all unit sets/defaults equal authored content; no invalid default is silently discarded.
- Basement explicitly rejects the other form’s pack, selling and base units and rejects conversion in both forms.
- **Seven actual Create-form widget transitions pass**, saved state is checked and revalidated: Wall Putty → Interior Wall Primer; Interior Paint → Brush; Litre coating → Sandpaper; Sealant → Primer; Powder coating → Aerosol; Basement Liquid → Cementitious; Basement Cementitious → Liquid.
- Both Basement switches deliberately populate Millilitre/Gram state first. Target pack/base/selling dimension resets, selling remains unset until explicitly selected, conversion resets OFF, and stale dynamic identity values disappear.

The unchanged **96 optional domain-review entries** remain narrowly documented in the candidate contracts, such as unset optional thinner/wood-finish colour defaults. None concerns a required identity/unit contract and none blocks readiness. No technical specification was invented to erase an optional review.

## Installed-v3 versus Release-4 interlock

The complete [row-level diff and dependency inventory](docs/phase10e-installed-v3-v4-diff.json) contains **4,958 row dispositions**, full before fields/digests, exact changed fields, proposed action, classification and all cached reference owners/paths/counts. It scans every account/public-config table for IDs, map keys, embedded IDs and attribute-scoped option-value dependencies. Ambiguous same-name option dependencies protect every matching legacy option. A row’s own identity and indexed mirrors are not counted as extra references. Backup SQL was not opened.

| Collection | Installed SYSTEM rows | Insert | Replace | Deactivate | Active omissions |
| --- | ---: | ---: | ---: | ---: | ---: |
| product_attribute_options | 220 | 131 | 36 | 184 | 161 |
| product_attributes | 50 | 0 | 44 | 6 | 5 |
| product_catalogue_releases | 1 | 0 | 1 | 0 | 0 |
| product_categories | 32 | 0 | 21 | 11 | 1 |
| product_subcategories | 197 | 2 | 135 | 62 | 13 |
| subcategory_attribute_templates | 3377 | 922 | 1110 | 2267 | 1237 |
| units | 26 | 0 | 21 | 5 | 5 |

**Totals: 1,055 inserts, 1,368 replacements, 2,535 deactivations; 1,422 active omissions.** Deactivations include already inactive rows the complete-query path would still touch. No hard deletion is proposed. These are actual importer effects proven by replaying the captured SYSTEM preimage into a separate temporary database, not effects executed in production.

| Disposition | Rows |
| --- | ---: |
| CANONICAL_KEEP | 1128 |
| LEGACY_RETAIN_REQUIRED | 242 |
| MIGRATION_REQUIRED | 2 |
| NEW_CANONICAL | 1055 |
| REVIEW_REQUIRED | 2506 |
| SAFE_UNREFERENCED_RETIREMENT_CANDIDATE | 25 |

**483 row identities have cached dependencies.** Every `LEGACY_RETAIN_REQUIRED`, `MIGRATION_REQUIRED` and `REVIEW_REQUIRED` entry is an unresolved live-installation blocker in the machine inventory. The 25 unreferenced retirement candidates are recommendations only and remain unapproved; absent templates are REVIEW_REQUIRED even when no cached template-ID reference exists. BUSINESS identities are preserved, not characterized as missing SYSTEM documents.

The two MIGRATION_REQUIRED SYSTEM rows are the omitted ambiguous Basement document and the canonical Ceiling document whose installed payload ID differs. The historical Ceiling payload identity additionally has **21 dependencies**; historical Basement payload identity has **14**. Both appear separately in `referenceOnlyIdentities`; old template groups are not grafted into Release 4.

The active omitted SYSTEM subcategories and reference counts are:

| Installed ID | Name | Dependencies |
| --- | --- | ---: |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | Tile Adhesives | 12 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_MISCELLANEOUS` | Miscellaneous | 6 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS` | Thinners | 6 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | Epoxy Flooring | 21 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS` | Hand Sanitizers | 22 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | Acrylic Putty | 19 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | Waterproof Wall Putty | 19 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | Acrylic Sealants | 14 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING` | Basement Waterproofing | 14 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING` | Bathroom & Kitchen Waterproofing | 14 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING` | Exterior Wall Waterproofing | 14 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT` | Interior Dampness Treatment | 14 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING` | Roof & Terrace Waterproofing | 14 |

Other blockers include historical Accessories/Exterior Wall Paints category and Brush/Economy Exterior Paint classifications referenced by saved Products and queries; the dynamic hsnCode definition referenced by Products/Variants/templates; retained legacy option identities/default values; six omitted attribute definitions; five omitted units (one referenced); and 2,267 absent template rows. The inventory lists every exact ID and reference, including inactive records, profile/config/history tables and all replacement field differences. Existing broken Product/Variant references are not auto-attached or rewritten.

There are **10 protected legacy-reference sync queries**, all currently inactive. Their exact specifications, active flags, cursors and lastSyncedAt are captured unchanged. Their inactive status is not migration approval. The existing registry interlock still blocks unsafe registration/migration; no query was rewritten or removed.

**Required ordering:** resolve/approve per-ID reference and retention plans, address protected queries and historical compatibility, preserve historical values and audit mappings, then migrate/remap references before any dependent row retirement and complete-snapshot reconciliation. This must be a reviewed coordinated migration/install process. An ordinary Release 4 snapshot import before that work is unsafe and explicitly blocked. All duplicate, legacy, retirement and live execution approvals remain false.

## Verification results

- Dedicated Phase 10E: **168/168 passed** (four Dart test files, including ten Python evidence/generation proofs).
- Complete final workspace: **633/633 passed**, including historical Phase 7–10D safety/regression coverage and the new Release 4 tests.
- `flutter analyze --no-pub`: **49 existing diagnostics (0 errors, 6 warnings, 43 infos); zero new diagnostics**. The command exits 1 because the existing baseline is nonzero.
- `git diff --check`: passed.

Logs: `/private/tmp/phase10e-baseline-tests.log`, `/private/tmp/phase10e-dedicated-tests.log`, `/private/tmp/phase10e-full-tests.log`, `/private/tmp/phase10e-analyze.log`. Reproduction uses `flutter test --no-pub --timeout 5m --reporter expanded`; generation uses `python3 -B tool/catalogue_phase10e.py`. The optional `--audit-installed` is strictly read-only and only writes its dedicated repository diff artifact.

## Production byte stability

| File | Size before/after | mtimeNs before/after | SHA-256 before = after |
| --- | ---: | ---: | --- |
| Account | 9744384 | 1791112106494478057 | `76419c2ae88c03719f0965709d2e81f7cfbc65a6021278a79c93f9a14f83ee70` |
| Backup | 9728000 | 1791091536646307789 | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` |
| Public-config | 937984 | 1791111851757294196 | `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012` |

Absolute paths:

- `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db`.
- `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak`.
- `/Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db`.

All three files are byte-identical with unchanged size/mtime. No WAL/SHM/journal was present before or after. The full suite also passes its existing guarded production observation. The read-only interlock’s before/after metadata equals the phase-wide capture. Therefore no production catalogue/query/Product/Variant/history row changed. **Zero production SQLite writes; zero Firestore reads or writes.** All importer executions and failure probes used new temporary SQLite databases.

## Files changed

- [lib/data/catalogue/catalogue_contract.dart](lib/data/catalogue/catalogue_contract.dart).
- [tool/catalogue_phase10e.py](tool/catalogue_phase10e.py).
- [tool/catalogue_phase10e_interlock.py](tool/catalogue_phase10e_interlock.py).
- [tool/tests/test_catalogue_phase10e.py](tool/tests/test_catalogue_phase10e.py).
- [test/support/phase10e_release.dart](test/support/phase10e_release.dart).
- [test/catalogue_release4_import_test.dart](test/catalogue_release4_import_test.dart).
- [test/catalogue_release4_forms_test.dart](test/catalogue_release4_forms_test.dart).
- [test/catalogue_release4_safety_test.dart](test/catalogue_release4_safety_test.dart).
- [test/catalogue_release4_state_test.dart](test/catalogue_release4_state_test.dart).
- [test/fixtures/system_catalogue_v4.json](test/fixtures/system_catalogue_v4.json).
- [docs/catalogue-release-v4-review.json](docs/catalogue-release-v4-review.json).
- [docs/phase10e-installed-v3-v4-diff.json](docs/phase10e-installed-v3-v4-diff.json).
- [phase10e.md](phase10e.md).

**Review decision:** Phase 10E isolated release-build acceptance is satisfied. Release 4 is not authorized for production installation, migration or Firestore publication. No Phase 11 work was started. Changes and artifacts are left for review.
