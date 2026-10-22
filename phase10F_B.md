# Phase 10F-B — Identity and manifest consistency closure

**Status: forensic verification completed; plan-only.** This addendum corrects Phase 10F identity/reporting errors and records exact read-only evidence. It does not authorize or execute migration, Release 4 installation, retirement, sync-query rewrite, Firestore access, catalogue redesign, or Phase 11 work. Approval fields remain false.

## Preflight and safety boundary

- Branch: `fix/product-master-audit`.
- Phase 10E commit: `6bce76dd7f7009edcdb96753c2d41ec64eede875` (`feat(product-master): build and verify isolated catalogue release 4`).
- At preflight, the only pending files were the three Phase 10F planning artifacts: `phase10f.md`, `docs/phase10f-migration-approval-manifest.json`, and `tool/tests/test_catalogue_phase10f.py`.
- Before verification SHA-256: account database `76419c2ae88c03719f0965709d2e81f7cfbc65a6021278a79c93f9a14f83ee70`; backup `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651`; public-config database `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012`.
- Account and public-config SQLite files were opened through the repository read-only connection and asserted `PRAGMA query_only=1`. The production query inventory returned 195 rows. The backup was hashed only. No Phase 10E evidence artifact was regenerated or overwritten. No Firestore access occurred.

## Ceiling: exact identity chain and typo verdict

Decoded production evidence establishes these distinct, exact values:

| Role | Exact ID | Evidence |
| --- | --- | --- |
| Installed Ceiling document ID | `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` | Production row; ACTIVE, not deleted. |
| Installed payload `subcategoryId` | `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` | Production payload, parent `SYS_CATEGORY_INTERIOR_WALL_COATINGS`. |
| Release 4 canonical document/payload ID | `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` | Release 4 review and fixture. |
| Installed document dependency census | 22 | All 22 reference records are `local_subcategory_attribute_templates`. |
| Historical payload identity dependency census | 21 | Explicit Phase 10E `referenceOnlyIdentities` entry; all 21 are `local_subcategory_attribute_templates`. |

The exact payload ID with `COATINGS` is a real stored historical identity, not a typo. The prior `phase10f.md` text omitted `COATINGS` and was incorrect. It is corrected to the production value. The document and payload IDs are not interchangeable: the 22 document-ID references and 21 payload-ID references are preserved independently. Phase 8 inventory, Phase 10A evidence, Phase 10E ledger, Release 4 review/fixture, the revised Phase 10F report, and the concrete manifest decisions were cross-checked character-for-character. Old template groups retain the exact parent IDs they store; no name-derived ID was substituted.

Exact old Ceiling template-group parents: the 22 installed legacy template rows use `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS`; the 21 V3 historical template rows use `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS`. Both parent IDs remain independently resolvable.

## Basement: document/payload split

| Role | Exact ID | Evidence |
| --- | --- | --- |
| Installed Basement document | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING` | Production row; parent `SYS_CATEGORY_WATERPROOFING`; ACTIVE, not deleted; 14 template references. |
| Historical Basement payload | `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT` | Separate Phase 10E reference-only identity; 14 template references. |
| Prospective Release 4 choices | `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_LIQUID`; `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_CEMENTITIOUS` | Both exist in the Release 4 fixture/review; neither is approved as a historical remap. |

Both old identities remain `MIGRATION_REQUIRED`; there is no automatic Liquid/Cementitious selection and no target is set in the manifest.

Exact old Basement template-group parents: 14 installed template rows use `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING`; 14 V3 historical template rows use `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT`.

## Ten duplicate pairs: exact parent, counts, owner scope

The Phase 8 duplicate-pair inventory, Phase 8 mappings, Phase 10E row ledger, Release 4 fixture/review, and manifest identity review actions agree on each row below. Each legacy ID has only template-owner dependencies in the Phase 10E ledger; every corresponding approval remains false.

| Legacy ID | Prospective canonical ID (not an approved target) | Parent category ID | References |
| --- | --- | --- | ---: |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | `SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | `SYS_CATEGORY_ADHESIVES_TILING` | 12 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS` | `SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS` | `SYS_CATEGORY_ALLIED_PRODUCTS` | 6 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | `SYS_CATEGORY_FLOOR_TILE_COATINGS` | 21 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | 19 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | 19 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | `SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | `SYS_CATEGORY_SEALANTS_REPAIR` | 14 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING` | `SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN` | `SYS_CATEGORY_WATERPROOFING` | 14 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING` | `SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL` | `SYS_CATEGORY_WATERPROOFING` | 14 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT` | `SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS` | `SYS_CATEGORY_WATERPROOFING` | 14 |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING` | `SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE` | `SYS_CATEGORY_WATERPROOFING` | 14 |

For every pair, Phase 8's candidate mapping is `approved=false`, the Release 4 candidate is `migrationApproved=false`, and the Phase 10E source ledger has `approved=false`, `migrationApproved=false`, and `retirementApproved=false`. Manifest `targetId` is null; its Release 4 IDs are recorded only as prospective candidates.

## Product/Variant owner state and proposed action

The read-only production owner scan and Phase 10E dependency paths identify 4 Products and 7 Variants. Every proposed handling action below is `RETAIN_LEGACY_METADATA`; no owner is approved for mutation or remap.

| Owner | State | Proposed action |
| --- | --- | --- |
| `PROD-515E99F5F2C24423B75AEBFE81CB075A` | ACTIVE | `RETAIN_LEGACY_METADATA` |
| `PROD-6198168F50EA48BB9209914A7A2003D2` | ACTIVE | `RETAIN_LEGACY_METADATA` |
| `PROD-78125CD6E1864CA1AF4E3E71C915D025` | DELETED (`isDeleted=1`) | `RETAIN_LEGACY_METADATA` |
| `PROD-C446FD4E4DD349DAB46DDFEDA251915D` | DELETED (`isDeleted=1`) | `RETAIN_LEGACY_METADATA` |
| `VAR-089A2A0AA0A14E45AEC89328F3A193E6` | INACTIVE (`isDeleted=0`) | `RETAIN_LEGACY_METADATA` |
| `VAR-233931D4CB8A432E8F2DC88912B59C48` | ACTIVE | `RETAIN_LEGACY_METADATA` |
| `VAR-3F8DCEC102144603B4BFF7DF558ECFDF` | INACTIVE (`isDeleted=0`) | `RETAIN_LEGACY_METADATA` |
| `VAR-42F8F567B7F54AC9A653C5826B53344B` | ACTIVE | `RETAIN_LEGACY_METADATA` |
| `VAR-808222B8F37A40138FE9416965A61F49` | ACTIVE | `RETAIN_LEGACY_METADATA` |
| `VAR-CF94091746164266B8DA7863706991A0` | ACTIVE | `RETAIN_LEGACY_METADATA` |
| `VAR-FE7BA134B0B94E058B21689F4DBB757B` | ACTIVE | `RETAIN_LEGACY_METADATA` |

This corrects the prior report's conflation of INACTIVE Variant status with deletion. Product/Variant IDs, SKU/barcode, values, timestamps, and historical meaning remain protected.

## Query and count reconciliation

- Production `sync_queries` row count: **195**; complete Phase 10E query digest: `311e4bd99435b5efb23d4f20192abc7677336169e6451787188f52e4e49fe303`.
- Protected legacy queries: **10**. Every row is `active=0`, `cursor=null`, and `BLOCK_MIGRATION_NO_REWRITE`. `lastSyncedAt` is null on six rows; the four non-null values are `2026-10-02T13:27:30.683249Z`, `2026-10-02T13:27:31.066930Z`, `2026-10-02T13:27:31.956359Z`, and `2026-10-02T13:27:37.720967Z`. Raw `queryKey` and `queryJson` remain in the Phase 10E protected query records and are unchanged.
- Diff identities: 4,958 rows; 483 dependency-bearing ledger identities plus 2 separately enumerated reference-only identities.
- Dispositions: 1,128 `CANONICAL_KEEP`; 1,055 `NEW_CANONICAL`; 242 `LEGACY_RETAIN_REQUIRED`; 2 `MIGRATION_REQUIRED`; 2,506 `REVIEW_REQUIRED`; 25 `SAFE_UNREFERENCED_RETIREMENT_CANDIDATE`.
- Omitted templates: 2,267, all retained as `REVIEW_REQUIRED`. Attribute rows deactivated: 6. Option rows deactivated: 184, of which 163 are referenced. Omitted units: 5, of which 1 has a cached direct reference.

## Manifest closure and false-approval validation

`docs/phase10f-migration-approval-manifest.json` now records 14 concrete `identityReviewActions`: the ten duplicate legacy IDs and the four separate Ceiling/Basement document/payload identities. Each `sourceId` resolves either to the exact Phase 10E `(sourceCollection, documentId)` entry or to an explicit `referenceOnlyIdentities` entry. Every `targetId` is null; prospective canonical IDs are separately identified and tests require them to exist in the Release 4 fixture. All action IDs are unique and every action has `approved=false`, `migrationApproved=false`, and `retirementApproved=false`. The manifest also records the 195/10 query counts and the Phase 10E sync-query digest.

No Phase 8 mapping is approved, no Phase 10E live/migration/retirement approval is true, and the Release 4 review remains isolated-only and unapproved. These records are planning recommendations only.

## Files and validation

Only Phase 10F planning/reporting artifacts were changed: the Phase 10F report, its approval manifest, its Python proof tests, and this addendum. Phase 8–10 source evidence, Release 4 content, application code, and production data were not changed.

- Focused Phase 10F Python plan-proof tests: **15/15 passed**.
- Full Flutter workspace tests: **633/633 passed** (`flutter test --no-pub --timeout 5m --reporter expanded`). The Phase 9C guarded verification reported `processViolation=false`, `checksumViolation=false`, and matching initial/final account and backup hashes.
- Focused Phase 10F-B Python plan-proof tests: **15/15 passed**.
- `flutter analyze --no-pub`: **49 pre-existing diagnostics (0 errors, 6 warnings, 43 infos)**; no Phase 10F-B application/Dart source was changed. The analyzer exits nonzero because existing diagnostics remain.
- Final production SHA-256 matched the pre-verification values: account `76419c2ae88c03719f0965709d2e81f7cfbc65a6021278a79c93f9a14f83ee70`; backup `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651`; public-config `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012`.

## Final disposition

The Ceiling payload discrepancy was a real reporting typo: the previously reported form omitted `COATINGS`. The corrected, exact legacy payload ID is `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS`; it is an extant reference-only identity with 21 template dependencies. No remapping is authorized. The migration plan remains **BLOCKED** pending independent row-level decisions and approvals. No migration, install, retirement, query rewrite, Firestore access, or Phase 11 work occurred.
