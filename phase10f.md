
For each of these ten pairs, the Phase 10E ledger shows **template-owner references only**: respectively 12, 6, 21, 19, 19, 14, 14, 14, 14 and 14 `local_subcategory_attribute_templates` rows. It shows zero Product, Variant, sync-query, and other direct owner rows for these ten subcategory IDs; any option-value details are embedded within the individual template owner payload/path evidence. Exact owner IDs, active/deleted flags, and each field/path remain on each exact legacy `documentId` row in the source ledger. Thus none of the ten mappings is approved or needed for direct Product/Variant ID remapping on this evidence; historical template resolution is still mandatory.
# Phase 10F — Production migration and retention plan

**Status: BLOCKED. Planning and proof only. No migration, mapping, retirement, Release 4 install, sync-query rewrite, live import, Firestore operation, or Phase 11 work was performed.** This is not production authorization. The Phase 10E snapshot would deactivate 2,535 identities/rows (including 1,422 active omissions); Release 4 must not be installed until every blocking disposition below is resolved and explicitly approved.

## 1. Preflight, evidence and safety

- Branch `fix/product-master-audit`; Phase 10E commit `6bce76dd7f7009edcdb96753c2d41ec64eede875` (`feat(product-master): build and verify isolated catalogue release 4`); clean before Phase 10F outputs were created.
- Phase 10E says its pre-change baseline was 465/465; Phase 10F ran `flutter test --no-pub --timeout 5m --reporter expanded` as a complete workspace baseline. It completed with 633/633 tests passing; Phase 10F-B adds separate identity-closure proofs and reruns validation.
- Re-captured production dependencies using the Phase 10E `--audit-installed` read-only path. Account and public-config were opened query-only/read-only; backup was hash-only; `PRAGMA query_only=1` was asserted. No production SQLite writes, no Phase 8 migration, no Release 4 installation. No Firestore read or write.
- Authoritative source: [Phase 10E installed-v3/Release-4 diff](docs/phase10e-installed-v3-v4-diff.json), all 4,958 row dispositions and exact cached references; [Release 4 review](docs/catalogue-release-v4-review.json); [Release 4 fixture](test/fixtures/system_catalogue_v4.json); [Phase 8 inventory](docs/phase8-catalogue-inventory.json) and [Phase 8 mappings](docs/phase8-canonical-mappings.json); [Phase 10A](docs/phase10a-catalogue-audit.json), [10B](docs/phase10b-intended-catalogue.json), [10C](docs/phase10c-canonical-content.json), and [10D](docs/phase10d-basement-evidence.json).
- Phase 10E records Release 4 fingerprint `b29528b8ed70428c`, semantic SHA-256 `3f02fef8f5ce368757f28c0b64ab797f19585efbeb0dd5263a4b1a38cac285ef`, and marker version 4/schema 1/compiler 6. The fixture/review are isolated-only and not live-approved.
- Phase 10E production before/after byte hashes: account `76419c2ae88c03719f0965709d2e81f7cfbc65a6021278a79c93f9a14f83ee70`; backup `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651`; public-config `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012`. Phase 10E records unchanged sizes/mtime and no sidecars. Phase 10F test observation rechecked account and backup against those hashes with no process/checksum violation. Final after-phase checksums are recorded in the verification addendum before completion.

## 2. Exact disposition accounting and interpretation

The complete source ledger has **4,958 unique `(collection, documentId)` rows** and exact before-payload fields/digests, action, classification, reference count, owner table/ID, active/deleted flag, JSON path, reference role, and field changes. The cached dependency census identifies **483 dependency-bearing ledger identities** plus **2 historical/reference-only identities**. SQL indexed mirrors are intentionally not additional logical references. Direct IDs, embedded JSON/map keys, attribute-scoped option-name values, inactive/deleted owners, config/history records and sync-query JSON are represented at exact `referenceRecords.locations[].path`; the approved query-only rescanner was rerun in this phase.

| Disposition | Rows | Review/retention rule |
| --- | ---: | --- |
| `CANONICAL_KEEP` | 1,128 | Still requires review of any changed referenced semantic fields before installation; not blanket approval. |
| `NEW_CANONICAL` | 1,055 | Insert only with complete approved snapshot transaction. |
| `LEGACY_RETAIN_REQUIRED` | 242 | Retain/read-resolve while any reference remains; no ordinary complete-query deactivation. |
| `MIGRATION_REQUIRED` | 2 | Blocking; resolve exact ID/payload or ambiguous mapping with explicit per-identity decision. |
| `REVIEW_REQUIRED` | 2,506 | Blocking; includes every omitted template row because absence is not proof of safe retirement. |
| `SAFE_UNREFERENCED_RETIREMENT_CANDIDATE` | 25 | Candidate only; zero references is not retirement approval. |

Diff effects: 1,055 inserts, 1,368 replacements, 2,535 deactivations (including already-inactive rows touched by reconciliation), 1,422 active omissions. No hard deletion is proposed. All manifest approvals are false in [the Phase 10F approval manifest](docs/phase10f-migration-approval-manifest.json). The 483 identity count refers to the exact Phase 10E ledger convention; reference-only identities are separately enumerated and not hidden in that count.

**Reason a row cannot be retired by ordinary snapshot reconciliation:** referenced rows retain Product/Variant values, templates/profiles, category/subcategory ancestry, attribute/option/unit IDs, sync filters, config/history values, or multiple ambiguous semantic owners as listed in that row's exact ledger `referenceRecords`. `MIGRATION_REQUIRED` means identity correction/remapping is needed or competing prospective targets exist. `REVIEW_REQUIRED` templates need content/history review even without a template-ID foreign key. `SAFE_UNREFERENCED_RETIREMENT_CANDIDATE` still requires a fresh complete-reference proof and explicit retirement approval.

## 3. High-priority identity decisions

No mapping below is approved. “Retain” means preserve as inactive/read-only historical metadata as appropriate, not make selectable. Exact per-owner evidence is in the named `documentId` row and any `referenceOnlyIdentities` record in the Phase 10E ledger; do not group by display label.

### Ten same-parent duplicate subcategories

| Legacy current ID | Prospective canonical ID | Exact parent category ID | Dependencies | Recommendation |
| --- | --- | --- | ---: | --- |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | `SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | `SYS_CATEGORY_ADHESIVES_TILING` | 12 | Keep legacy identity and its content/refs. Do not merge its conflicting profile/template semantics; any future Product remap requires record-by-record semantic confirmation. |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS` | `SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS` | `SYS_CATEGORY_ALLIED_PRODUCTS` | 6 | Retain old identity and historical form values; no inference from name. |
| `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | `SYS_CATEGORY_FLOOR_TILE_COATINGS` | 21 | Retain; confirm historical floor/coating semantics before any remap. |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | 19 | Retain; do not transfer legacy template content to canonical form. |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | 19 | Retain; review old values and unit contract before any remap. |
| `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | `SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | `SYS_CATEGORY_SEALANTS_REPAIR` | 14 | Retain; no name-only mapping. |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING` | `SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN` | `SYS_CATEGORY_WATERPROOFING` | 14 | Retain; old template group remains separately addressable. |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING` | `SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL` | `SYS_CATEGORY_WATERPROOFING` | 14 | Retain; no merging template history. |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT` | `SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS` | `SYS_CATEGORY_WATERPROOFING` | 14 | Retain; no name-only mapping. |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING` | `SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE` | `SYS_CATEGORY_WATERPROOFING` | 14 | Retain; no name-only mapping. |

All ten corresponding Phase 8 source mappings have `approved=false`; Phase 10E ledger rows have `approved=false`, `migrationApproved=false`, and `retirementApproved=false`; corresponding Release 4 review candidates have `migrationApproved=false`. The decision evidence explicitly records profile/template semantic conflicts for canonical duplicate handling; corrected canonical contract content does not authorize rewriting extant business rows. Per pair: preserve old identity and old template/history read path; remap a specific live owner only with semantic-owner approval, a separately approved migration, verification and rollback evidence. Keep approval and retirement approval false.

### Ceiling and Basement identities

| Current identity | Future ID (if any) | Dependencies / owners | Recommendation |
| --- | --- | --- | --- |
| Ceiling document `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` | none: the Release 4 canonical document ID is the same ID, but the installed payload identity is the distinct legacy ID `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` | 22 on the document row; legacy payload identity has 21 historical dependencies. | `MIGRATION_REQUIRED`: the payload ID is confirmed as an actual stored identity, not a typo. First design and approve document/payload identity correction and preserve/resolve both identity keys. Do not overwrite/correct the payload opportunistically in snapshot reconciliation. Retain old template groups and resolver access. |
| Basement document `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING` | no approved target; Release 4 has separate `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_LIQUID` and `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_CEMENTITIOUS` contracts | 14 template refs, no Product refs, no protected-query refs; historical payload ID below also has 14 template refs. | `MIGRATION_REQUIRED`, blocking. Keep as a distinct legacy record until each reference and the material meaning is resolved. Never choose Liquid or Cementitious by default. |
| Basement payload `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT` | none approved (same two prospective candidates only) | 14 local template dependencies, no Product/query dependencies | Preserve old payload/template resolution independently of document identity; no reuse for either new ID and no automatic crosswalk. |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_MISCELLANEOUS` (Miscellaneous) | none | 6 refs | Retain legacy selectable/history identity only as current behavior requires; Release 4 omission does not justify retiring it. New canonical target absent. |
| `SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS` (Hand Sanitizers) | none | 22 refs | Retain legacy identity and old values; new target absent. |
| `SYS_CATEGORY_INTERIOR_WALL_PAINTS` / `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_INTERIOR_WALL_PAINT` (legacy Paint / Interior Wall Paint) | no verified target | Phase 10A identifies BUSINESS category `PM_CATEGORY_93d0611d84196d62` and subcategory `PM_SUBCATEGORY_ce0bf39843417fca`, missing template; separate from similarly named SYSTEM IDs. | Preserve BUSINESS scope and Product ancestry, do not convert to SYSTEM or a canonical coating by label. Exact current product refs remain in ledger. |
| `SYS_CATEGORY_ACCESSORIES` and legacy `SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH` | no approved target mapping | Category 6 refs; Brush 8 refs; active Product `PROD-515E99F5F2C24423B75AEBFE81CB075A` references category, Brush subcategory and historical option values. | Retain classification/attribute metadata; no reclassify or option normalization. |
| `SYS_CATEGORY_EXTERIOR_WALL_PAINTS` and `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS` | Release 4 category `SYS_CATEGORY_EXTERIOR_WALL_COATINGS`; no approved subcategory target | Category 7 refs; Economy Exterior Paints 16 refs; active Product `PROD-6198168F50EA48BB9209914A7A2003D2` references both. | Preserve category and subcategory IDs. Phase 8 has an explicit category alias proposal but its `approved` remains false; category alias is not permission to change Product or query references. No verified subcategory equivalence. |
| legacy `SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_BRUSH` / Economy Exterior Paint classifications | no approved targets | Active Product IDs above plus Product attribute values; exact refs include attribute-scoped options and direct classification IDs. | Read-only legacy classification compatibility; remap only after human-confirmed semantic decision. |

For every row above, Product refs, Variant refs, template refs, option refs, sync-query refs and history/config refs are the exact `referenceRecords` in Phase 10E under the `documentId` (and the two `referenceOnlyIdentities` IDs). A zero for a reference type means none was found by the complete cached scan, not that a decision is approved. Indexed SQL mirrors are not extra logical references.

## 4. Product and Variant protection

The ledger identifies **11 distinct Product/Variant owner records** with dependencies on omitted/replaced classification, unit, attribute or option identities: 4 Products and 7 Variants. (The owner set includes soft-deleted/inactive historical rows.) Every individual field path, status, dependency ID and reference role remains itemized in Phase 10E; this report deliberately does not reproduce those values by display name.

- Products: `PROD-515E99F5F2C24423B75AEBFE81CB075A` (ACTIVE); `PROD-6198168F50EA48BB9209914A7A2003D2` (ACTIVE); `PROD-78125CD6E1864CA1AF4E3E71C915D025` (DELETED, `isDeleted=1`); `PROD-C446FD4E4DD349DAB46DDFEDA251915D` (DELETED, `isDeleted=1`).
- Variants: `VAR-089A2A0AA0A14E45AEC89328F3A193E6` (INACTIVE, `isDeleted=0`); `VAR-233931D4CB8A432E8F2DC88912B59C48` (ACTIVE); `VAR-3F8DCEC102144603B4BFF7DF558ECFDF` (INACTIVE, `isDeleted=0`); `VAR-42F8F567B7F54AC9A653C5826B53344B`, `VAR-808222B8F37A40138FE9416965A61F49`, `VAR-CF94091746164266B8DA7863706991A0`, `VAR-FE7BA134B0B94E058B21689F4DBB757B` (ACTIVE).
- Handling for each distinct owner (the source ledger retains every referenced identity/path; this is a conservative per-record proposal, not an approval):

| Owner table | Owner ID | State | Proposed action |
| --- | --- | --- | --- |
| Product | `PROD-515E99F5F2C24423B75AEBFE81CB075A` | active | `RETAIN_LEGACY_METADATA` |
| Product | `PROD-6198168F50EA48BB9209914A7A2003D2` | active | `RETAIN_LEGACY_METADATA` |
| Product | `PROD-78125CD6E1864CA1AF4E3E71C915D025` | DELETED (`isDeleted=1`) | `RETAIN_LEGACY_METADATA` |
| Product | `PROD-C446FD4E4DD349DAB46DDFEDA251915D` | DELETED (`isDeleted=1`) | `RETAIN_LEGACY_METADATA` |
| Variant | `VAR-089A2A0AA0A14E45AEC89328F3A193E6` | INACTIVE (`isDeleted=0`) | `RETAIN_LEGACY_METADATA` |
| Variant | `VAR-233931D4CB8A432E8F2DC88912B59C48` | active | `RETAIN_LEGACY_METADATA` |
| Variant | `VAR-3F8DCEC102144603B4BFF7DF558ECFDF` | INACTIVE (`isDeleted=0`) | `RETAIN_LEGACY_METADATA` |
| Variant | `VAR-42F8F567B7F54AC9A653C5826B53344B` | active | `RETAIN_LEGACY_METADATA` |
| Variant | `VAR-808222B8F37A40138FE9416965A61F49` | active | `RETAIN_LEGACY_METADATA` |
| Variant | `VAR-CF94091746164266B8DA7863706991A0` | active | `RETAIN_LEGACY_METADATA` |
| Variant | `VAR-FE7BA134B0B94E058B21689F4DBB757B` | active | `RETAIN_LEGACY_METADATA` |
- **Classification/category/subcategory:** preserve every saved categoryId/subcategoryId. Existing `SYS_CATEGORY_ACCESSORIES`, `SYS_CATEGORY_EXTERIOR_WALL_PAINTS`, Brush and Economy Exterior Paint references are not automatically reassigned. Missing/legacy product classifications get `RETAIN_LEGACY_METADATA`; a future record-specific mapping is `REMAP_REQUIRED` only after approved semantics; any existing broken pointer would be `RECOVER_BROKEN_REFERENCE` only after source-of-truth confirmation; no unrelated row is `NO_ACTION` merely because its name resembles a current category.
- **Units:** retain readable old unit IDs including `SYS_UNIT_PACK` (2 Variant references) and `SYS_UNIT_CAN` (one deleted historical Variant dependency among its multiple unit fields); do not convert commercial/base/pack units by string or numeric factor without per-variant evidence. `SYS_UNIT_PIECE` dependencies are also listed on three active Variant rows, although Piece is present in Release 4; preserve those values and check target semantics before a unit table replacement.
- **Attributes/options:** preserve old typed values in `attributeValues`; do not erase values whose definition/options are omitted or replaced. The Phase 10E ledger includes 163 referenced deactivated option IDs and context-scoped display-value dependencies (the deactivated option row total is 184); historical values are not coerced into a new canonical option set.
- For every one of 11 owners, requested proposed action is exactly one of: `REMAP_REQUIRED` (only after identity approval), `RETAIN_LEGACY_METADATA` (current default for old semantic values), `RECOVER_BROKEN_REFERENCE` (only a proven broken ref), or `NO_ACTION` (only after exact evidence proves no affected reference). **No Product or Variant is currently approved for remap or mutation.** Preserve Product ID, Variant ID, SKU, barcode, timestamps, transaction snapshots and historical meaning byte-for-byte/logically unchanged.

## 5. Attribute, option and unit compatibility

- Phase 10E would deactivate 6 attribute rows: `colourMode` (active, 219 dependencies), `sellingUnit` (active, 5), `suitableSurface` (active, 13), `tapeColour` (active, 8), `tapeType` (active, 7), and `hsnCode` (already inactive, 59 path-level dependencies across 7 Product/Variant owners). Keep all definitions available to historical readers; `hsnCode` cannot simply disappear because it is not a Release 4 form attribute.
- Of 184 deactivated option rows, 163 have cached references. Retain omitted/replaced option identities and values in read-only legacy metadata as required by historical records/templates. Use attribute identity plus option identity/context, not display name, to disambiguate. Never union legacy choices into Release 4 canonical options or force old values through current validation. New Product forms consume only the canonical Release 4 option contract; history resolvers must support legacy schema/version.
- All five omitted units from the Release 4 snapshot: `SYS_UNIT_BOX`, `SYS_UNIT_FOOT`, `SYS_UNIT_PACK`, `SYS_UNIT_SQUARE_FOOT`, `SYS_UNIT_SQUARE_METRE`. `SYS_UNIT_PACK` has two Variant dependencies; four remaining omissions have no cached direct reference (candidate only). `SYS_UNIT_CAN` remains a separate legacy-referenced identity and is not counted among those five omissions. Retain old units for history/transactions when required, with read-only status outside new selectors; never reinterpret their dimensions or silently substitute aliases.
- Historical template/profile option sets/defaults, including old Ceiling and Basement payload groups, remain resolvable without changing saved Product/Variant values. Release 4 validation governs newly created canonical forms only, not historical decoding.

## 6. Template retention

The complete snapshot would deactivate **all 2,267 absent template rows**. Phase 10E's scanner finds no direct template-ID references; that is not evidence the rows are expendable because references are commonly through parent IDs, embedded profiles/config, historical values, resolver expectations or saved document context. Consequently all 2,267 are `REVIEW_REQUIRED`, not “superseded” by default. Separate semantic proof has not classified individual rows as purely superseded versus history-required in the committed cached inventory; this is a **blocking evidence gap**, not permission to drop.

- Keep the old template rows/payloads and immutable template IDs in an append-only/read-only legacy store or equivalent versioned resolver source. Maintain old parent/payload identities for decoding. Exclude them from the new Product selector/form query by explicit release/version/selectability gating; retention must not reactivate them or make them selectable for new Product creation.
- Before installation, generate a row-level retention decision for each of the 2,267 IDs, grouping only by exact parent ID/version after reviewing each row; record historical dependants and checksum. Either retain resolvable legacy content or present explicit evidence for retirement and obtain per-row retirement approval. Do not graft old rows into the 2,032 Release 4 templates or mutate their option semantics.

## 7. Protected sync query interlock

All **195** registered sync queries remain intact. The 10 individually protected queries below have `active=0` and are `BLOCK_MIGRATION_NO_REWRITE`. Cursor and `lastSyncedAt` remain exactly as recorded, including nulls. Do not delete, reactivate, rewrite query keys/JSON, reset cursor/attempt timestamps or “clean” them in this phase. Full original `queryKey`, raw `queryJson`, exact cursor, `lastSyncedAt`, `legacyIds`, and active flag are in the Phase 10E `protectedLegacyQueries` array; the source also records full sync-query digest.

| # | Exact query identity (collection + protected filter ID) | State | Decision needed before any rewrite |
| ---: | --- | --- | --- |
| 1 | `product_subcategories` / `SYS_CATEGORY_ACCESSORIES` / tenant+business+ACTIVE | inactive; cursor null; lastSyncedAt null | Preserve category or approve mapping and prove no Brush/other results lost. |
| 2 | `product_subcategories` / `SYS_CATEGORY_EXTERIOR_WALL_PAINTS` / tenant+business+ACTIVE | inactive; cursor null; lastSyncedAt `2026-10-02T13:27:30.683249Z` | Resolve unapproved category alias with Product/subcategory semantics; no name-based rewrite. |
| 3 | `product_subcategories` / `SYS_CATEGORY_ACCESSORIES` / SYSTEM+ACTIVE | inactive; cursor null; lastSyncedAt null | Preserve old SYSTEM category filter or explicitly approve its replacement. |
| 4 | `product_subcategories` / `SYS_CATEGORY_EXTERIOR_WALL_PAINTS` / SYSTEM+ACTIVE | inactive; cursor null; lastSyncedAt `2026-10-02T13:27:31.066930Z` | Resolve category alias separately from business-scoped query #2. |
| 5 | `subcategory_attribute_templates` / `PM_SUBCATEGORY_ce0bf39843417fca` / BUSINESS+tenant+business | inactive; cursor null; lastSyncedAt null | Keep BUSINESS Paint history distinct from SYSTEM coatings; no cross-scope mapping. |
| 6 | `subcategory_attribute_templates` / `SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH` / BUSINESS+tenant+business | inactive; cursor null; lastSyncedAt null | Keep legacy Brush templates for saved BUSINESS records; no reactivation or rewrite. |
| 7 | `subcategory_attribute_templates` / `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS` / BUSINESS+tenant+business | inactive; cursor null; lastSyncedAt `2026-10-02T13:27:37.720967Z` | Preserve Economy classification and resolve active Product semantics before any mapping. |
| 8 | `subcategory_attribute_templates` / `PM_SUBCATEGORY_ce0bf39843417fca` / SYSTEM+ACTIVE | inactive; cursor null; lastSyncedAt null | Resolve historical payload/query ID and scope mismatch; preserve original key. |
| 9 | `subcategory_attribute_templates` / `SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH` / SYSTEM+ACTIVE | inactive; cursor null; lastSyncedAt null | Keep legacy Brush template identity until any Product/option migration has separate approval. |
| 10 | `subcategory_attribute_templates` / `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS` / SYSTEM+ACTIVE | inactive; cursor null; lastSyncedAt `2026-10-02T13:27:31.956359Z` | Keep legacy template filter; resolve exact canonical semantics first. |

The above names identify the protected identity sets, not substitutes for exact query keys. The manifest and source ledger are the authority for each query's complete JSON and protected IDs. All query migration approvals remain false.

## 8. Deterministic migration/install ordering (future only)

1. Freeze application and sync writers and enter maintenance mode; verify no other process can write account/public-config or Firestore.
2. Take a new consistent, verified backup of account DB and public-config DB; record byte size, SHA-256, SQLite integrity result, file/sidecar state, and backup/restore drill evidence. Hash-only inspection of the old backup is not backup validation.
3. Verify the exact production preimage fingerprint against the approved Phase 10F change set; abort on any byte/logical preimage drift, outstanding WAL/SHM/journal, changed query digest, or unknown application writer.
4. Apply only individually approved semantic reference remaps. Preserve Product/Variant/SKU/barcode/timestamps/transaction meaning; write an audit mapping ledger with before/after owner IDs and values. Do not retire records here.
5. Retain needed old attribute/option/unit/template/profile metadata and decoder paths as read-only, non-selectable history. This is additive compatibility, not canonical option-set widening.
6. Re-scan full account and public-config references; verify zero unresolved mandatory references, every retained historical value decodes, and each proposed retirement has zero mandatory owners plus explicit retirement approval. Protected sync-query decisions must be resolved or explicitly retained unchanged.
7. Install the Release 4 snapshot and approved remaps in a **single SQLite transaction** with a transactionally consistent release marker/fingerprint; perform no external Firestore side effect in that transaction. If installation cannot share the transaction, retain a maintenance-mode barrier and prevent every app/sync reader/writer from observing the intermediate state until both stages and verification finish. Never allow split transaction exposure.
8. Verify installed marker/version/schema/compiler/fingerprint exactly matches the isolated reviewed release.
9. Verify canonical selector/forms expose only intended Release 4 READY records and retained legacy templates are not selectable for new Product creation.
10. Verify historical Product/Variant reads/edits, SKU/barcode, transactions, old option values and unit display/meaning.
11. Verify sync-query count, raw key/JSON, active flags, cursor, attempt timestamps, `lastSyncedAt`, lease/outbox state and digest against approved plan; no query changes without separate approval.
12. Resume application/sync writers only after all gates pass and postimage fingerprints are recorded; retain logs and backup.

Dependency graph: freeze → backup → preimage → approved remaps → legacy retention → zero unresolved refs → snapshot+marker → selector/forms → history readability → query integrity → resume. Each node depends on its predecessor; there are no cycles. Steps 7–11 are atomic/maintenance-barrier protected; no snapshot may be visible before prerequisites.

## 9. Rollback plan (design only)

**Backup preconditions:** coordinated quiescence; verified SQLite-consistent account and public-config backups taken at the same maintenance point; separate SHA-256, sizes and sidecar inventory; `PRAGMA integrity_check` on copies; verified readable storage and access controls; documented restore procedure and a successful restore drill on disposable copies. Capture preimage logical table digests for Products, Variants, SKUs, barcodes, transaction/history, all catalogue collections, all sync queries and relevant metadata; capture release marker/fingerprint and app version/config. Preserve the immutable approved remap ledger. Do not rely on the Phase 10E backup's hash alone.

**Rollback triggers:** any preimage mismatch; unapproved or out-of-scope row change; remap count/owner mismatch; missing historical Product/Variant/template/option/unit readability; changed Product/Variant/SKU/barcode/timestamp/transaction identity or meaning; wrong release marker/fingerprint; selector exposes legacy templates or omits a canonical READY record; any sync-query key/JSON/active/cursor/attempt/lastSyncedAt difference not explicitly approved; SQLite integrity failure; app/sync failure or any evidence of partial commit; account/public-config hashes inconsistent with the approved postimage. A trigger keeps writers frozen and stops further processing.

**Restore:** keep app/sync frozen; restore the verified account DB and its matching public-config DB plus associated catalogue/release marker/config metadata from the same pre-migration backup set; restore required sidecars only according to SQLite's supported consistent-backup procedure; do not independently restore mismatched generations. Reopen restored copies read-only for integrity and checksums before swapping paths under maintenance. Recompute all preimage digests and release/query markers. If any restore proof fails, do not resume writers; escalate for recovery. Record operator, time, source backup hashes, restored hashes and result. No rollback is executed in Phase 10F.

**Identity proof:** compare ordered exact rows/columns and logical digests for `productId`, `variantId`, SKU, barcode, timestamps, all product/variant attribute/unit/classification IDs and values, history/transaction snapshots, sync query keys/JSON/active/cursors/attempt timestamps/`lastSyncedAt`, and catalogue marker/fingerprint to captured preimage. Require zero missing/extra/duplicate identities and exact query digest equality. Also compare DB file hashes when a byte-identical restore is expected; logical identity proof is mandatory even when SQLite file layout differs.

## 10. Approval blockers and manifest contract

`docs/phase10f-migration-approval-manifest.json` defines the per-source-row action identity (`PHASE10F:<collection>:<documentId>`), exact owner evidence carried from Phase 10E, reason/risk derivation, and mandatory false defaults. Its deterministic row projection is keyed by exact `(collection, documentId)` rather than name, with explicit blockers for all `REVIEW_REQUIRED`, `LEGACY_RETAIN_REQUIRED`, `MIGRATION_REQUIRED`, historical templates and protected queries. No earlier authoritative evidence explicitly approves any production migration/remap/retirement; Phase 8 candidate mappings are `approved=false`, Phase 10E live approvals are false. Thus `preapprovedMappings` is empty and every approval remains false.

**Every still-blocking approval:** (1) resolve/review all 2,506 `REVIEW_REQUIRED` rows, including 2,267 templates; (2) approve retention/migration strategy for 242 `LEGACY_RETAIN_REQUIRED` rows; (3) explicitly resolve both `MIGRATION_REQUIRED` rows and two reference-only identities; (4) semantic decision for each of ten duplicate pairs; (5) explicit choices for Basement historical identities and Ceiling document/payload identity; (6) row-level Product/Variant mapping/retention decisions with zero identity mutation presumed; (7) retained legacy attributes/options/units and reader behavior; (8) per-query mapping/retention decision for all 10 protected queries; (9) per-record retirement approvals for all 25 retirement candidates if retirement is later requested; (10) separately approved production backup/maintenance/install and rollback authorization. No Release 4 omission, display-name similarity, “zero cached refs,” or a prior domain split decision supplies these approvals.

## 11. Acceptance tests and completion report

Phase 10F plan-proof tests cover: all 4,958 disposition rows accounted exactly once; 483 dependency-bearing identities plus separate historical identities preserved in census; Product/Variant owner handling; 2,267 template retention gates; unit/attribute/option compatibility; 10 query interlocks; false approval defaults; acyclic migration dependencies; rollback completeness; production read-only and no-Firestore/Release-4-install assertions. These tests validate evidence and plan only; they must not import/install a release or mutate production.

- Diff rows reviewed: 4,958; dependency-bearing identities: 483 (plus 2 `referenceOnlyIdentities`).
- Counts: 1,128 CANONICAL_KEEP; 1,055 NEW_CANONICAL; 242 LEGACY_RETAIN_REQUIRED; 2 MIGRATION_REQUIRED; 2,506 REVIEW_REQUIRED; 25 SAFE_UNREFERENCED_RETIREMENT_CANDIDATE.
- Product/Variant refs: 11 distinct owners (4 Products, 7 Variants), exact identity/status list in §4 and exact per-reference paths in Phase 10E.
- Template-retention inventory: 2,267 deactivated rows; all 2,267 remain REVIEW_REQUIRED pending row-by-row history resolution; no direct template-ID refs found is not retirement proof.
- Attribute/option/unit inventory: 6 attribute rows deactivated (all six named in §5), 184 option rows deactivated/163 referenced, 5 omitted units (one referenced), plus exact IDs and owners in Phase 10E.
- Protected queries: 10 / 195; all individually gated in §7; no rewrite/deletion/reactivation.
- Ten duplicate-pair recommendations and Ceiling/Basement recommendations: §3; no auto-approval.
- Required execution order: §8; transaction/maintenance recommendation: one SQLite transaction, or a strict maintenance barrier spanning migration+snapshot+verification.
- Rollback: §9, complete design; not executed.
- BLOCKING approvals: all ten groups in §10; all approval booleans false.
- Changed files: `phase10f.md`, `docs/phase10f-migration-approval-manifest.json`, `tool/tests/test_catalogue_phase10f.py`, and `phase10F_B.md`. No production/catalogue source changes.
- Full workspace baseline (complete workspace suite): **633/633 passed**. Phase 10F-B identity/evidence tests: **15/15 passed**. `flutter analyze --no-pub`: **49 existing diagnostics (0 errors, 6 warnings, 43 infos); zero Phase 10F code diagnostics**. Analyzer exits nonzero because the workspace has pre-existing diagnostics. See the [Phase 10F-B forensic addendum](phase10F_B.md) for exact identity closure and final post-verification results.
- Production hashes before/after: account `76419c2ae88c03719f0965709d2e81f7cfbc65a6021278a79c93f9a14f83ee70`; backup `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651`; public-config `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012`. Final hashes matched Phase 10E exactly.
- Firestore: zero access and zero writes. Production: unchanged; no Release 4 installation, live import, query mutation or migration. Phase 11 not started.

## Final status

Phase 10F produced a deterministic, reviewable plan and false-by-default approval gate. It does **not** satisfy production transition approval: unresolved row-level history and semantics are intentional blockers. Stop before any production operation until the manifest is explicitly completed and independently approved. No references are to be erased or hidden to make the counts pass.
