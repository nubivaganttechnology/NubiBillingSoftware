# Phase 10 — Product Master template correction: stopped preflight report

**Status: STOPPED; Phase 10 is not complete. No catalogue content corrections were made.** Ten active same-parent duplicate groups cannot be retained together in an importable successor under the unchanged Phase 9 contract. Phase 8 explicitly marks their semantic/identity choices unresolved and every execution approval remains false. Choosing, merging, renaming, omitting or retiring one identity to get a complete release accepted would require a decision not authorized in this phase.

The invoked user stop condition is: **“If correction requires approving unresolved Phase 8 migration mapping, STOP.”** No mapping was approved and no architecture guard was weakened. This report preserves concrete findings and isolated proof for review; it is not a template-correction closure report.

A second preflight finding invalidates the stated 147-template working baseline: the actual decoded installed catalogue has **59 individually eligible records and 49 parent-aware selectable entries**, with **88 active records explicitly marked `templateSelectable=false`**. A test asserting the requested 147 baseline failed. This discrepancy must be reconciled before claiming coverage of every intended form.

## Preflight and verification

| Check | Result |
| --- | --- |
| Branch | `fix/product-master-audit` — confirmed. |
| Phase 9D committed | `320f4a56b1f93392817facfbaababf3332f2f857` — `test(product-master): close phase 9 production safety`. Initial HEAD. |
| Initial working tree | Clean; implementation files remain unchanged. |
| Complete baseline workspace suite | **248/248 passed** with `flutter test --timeout 5m --reporter expanded`; exit 0, `02:02 +248: All tests passed!`. |
| Initial ordinary-timeout run | 247 passed; the existing 120-second Phase 9C guard timed out at the runner's default 30 seconds. No source change was made; the longer runner timeout resolved this. |
| Flutter analysis | **54 pre-existing issues: 6 warnings, 48 infos, zero errors**; exit 1. This is the current checked-out baseline, not the older Phase 9 count of 51. No workspace Dart files changed, so no new analyzer diagnostics were introduced. |
| Isolated preflight proof | **11/11 passed**: one decoded installed-catalogue observation plus ten expected collision rejection cases. These verify the blocker, not successful corrections. |
| App/process checks | Before and at the safety endpoint, `pgrep -ifl 'testflutter\|nubibill'` returned no matches; `lsof` on account/public-config returned no handles. Approved read-only process visibility was used. No app was launched. |
| Production data | Account, backup and public-config hashes, sizes and modification times all match before/after; no sidecars. |
| Firestore | Zero live reads/writes by this work. Tests use existing doubles/MockClient. |

All direct production inventory connections used SQLite `mode=ro` and `PRAGMA query_only=ON` through the existing read-only inventory helper. A byte-identical account copy was placed in temporary storage and opened read-only/query-only for the actual `LocalDataSource.query`, `ProductTemplateResolver` and `CatalogueSelectionResolver` audit. Write-capable import rejection tests created separate empty temporary databases; no production bootstrap or migration was invoked.

## Why a complete successor is blocked

Phase 9 rejects active normalized-name collisions within the same catalogue, business scope and explicit parent. The current installed data has the ten groups listed below. Their IDs and parents are preserved in the proofs. Each isolated test proposes **data release 4, schema revision 1, compiler revision 6**, with the actual parent and both active subcategory identities. The actual `SystemCatalogueSnapshot.import` rejects each with **`catalogue-collision` before writing any catalogue row or outbox row**.

These are deliberately minimal validation scaffolds, not corrected release artifacts. No valid corrected successor was generated, published or installed.

The existing importer treats incoming SYSTEM collections as complete snapshots. Omitting an existing SYSTEM row is not a harmless patch: `LocalDataSource.upsertRemote` marks missing SYSTEM catalogue rows inactive. Supplying only a convenient canonical subset would therefore encode a legacy-retirement decision. No such omission/retirement decision was taken. A complete release retaining these unresolved active pairs fails validation; weakening duplicate validation, changing their parent/scope or choosing identities would exceed this content-only authorization.

Phase 8's explicit policy for these groups is **“Keep all; differing or unverified template contracts require review.”** The original review/approval state remains intact in [phase8.md](phase8.md) and [docs/phase8-canonical-mappings.json](docs/phase8-canonical-mappings.json).

## Every blocking duplicate identity — DOMAIN_REVIEW_REQUIRED

Review field: **canonical classification identity and equivalence of the two template/profile contracts**. No canonical target is approved. Names alone are insufficient evidence.

| Category / parent | Subcategory | Exact active IDs | Isolated import result |
| --- | --- | --- | --- |
| Adhesives & Tiling / `SYS_CATEGORY_ADHESIVES_TILING` | tile adhesives | `SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES`; `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | `catalogue-collision`; zero rows written |
| Allied Products / `SYS_CATEGORY_ALLIED_PRODUCTS` | thinners | `SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS`; `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS` | `catalogue-collision`; zero rows written |
| Floor & Tile Coatings / `SYS_CATEGORY_FLOOR_TILE_COATINGS` | epoxy flooring | `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING`; `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | `catalogue-collision`; zero rows written |
| Putty & Surface Preparation / `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | acrylic putty | `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY`; `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | `catalogue-collision`; zero rows written |
| Putty & Surface Preparation / `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | waterproof wall putty | `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY`; `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | `catalogue-collision`; zero rows written |
| Sealants & Repair / `SYS_CATEGORY_SEALANTS_REPAIR` | acrylic sealants | `SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS`; `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | `catalogue-collision`; zero rows written |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | bathroom & kitchen waterproofing | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING`; `SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN` | `catalogue-collision`; zero rows written |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | exterior wall waterproofing | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING`; `SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL` | `catalogue-collision`; zero rows written |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | interior dampness treatment | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT`; `SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS` | `catalogue-collision`; zero rows written |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | roof & terrace waterproofing | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING`; `SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE` | `catalogue-collision`; zero rows written |

Recorded Phase 8 reference counts are preserved as planning evidence below; they are not claims of newly approved migration safety.

| ID | Phase 8 reference count | Approved | Canonical target |
| --- | --- | --- | --- |
| `SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | 8 | False | `None` |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | 12 | False | `None` |
| `SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS` | 6 | False | `None` |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS` | 6 | False | `None` |
| `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | 21 | False | `None` |
| `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | 21 | False | `None` |
| `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | 17 | False | `None` |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | 19 | False | `None` |
| `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | 17 | False | `None` |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | 19 | False | `None` |
| `SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | 9 | False | `None` |
| `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | 14 | False | `None` |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING` | 14 | False | `None` |
| `SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN` | 15 | False | `None` |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING` | 14 | False | `None` |
| `SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL` | 15 | False | `None` |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT` | 14 | False | `None` |
| `SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS` | 15 | False | `None` |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING` | 14 | False | `None` |
| `SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE` | 15 | False | `None` |

## Actual installed selection reconciliation

The existing `test/product_selector_reconciliation_test.dart` audit checks `dataJson`, which is absent from this schema, then passes raw SQL columns to a fake reader. Actual catalogue metadata is stored in `payloadJson`. That fallback loses display names, template selection flags, profile restrictions and other payload semantics. Its passing 147 count does not prove 147 current selectable forms.

The new temporary probe uses the real local query decoder against a read-only account copy, preserving original payloads and SQL-index filtering. It observed:

| Measure | Observed |
| --- | --- |
| Active subcategory rows | 149 |
| Individually eligible/READY records evaluated | 59 |
| Parent-aware unique selectable entries | 49 |
| Eligible categories | 15 |
| Explicitly disabled by `templateSelectable=false` | 88 |
| Legacy Interior Wall Paint | 1, missing template; remains excluded |
| Hand Sanitizers | 1, unavailable by current metadata; remains excluded |
| Active same-parent duplicate groups | 10 |

The temporary probe first asserted 147 as required by the request and failed with an actual value of 59. The final observation test asserts the measured 59/49 values to preserve evidence; that passing observation does **not** satisfy or replace the requested 147-template coverage criterion. No disabled template was silently re-enabled.

Both Hand Sanitizers and historical `PM_SUBCATEGORY_ce0bf39843417fca` / Interior Wall Paint remain excluded. No normal selectable form was created for the legacy classification.

Two existing document/payload identity mismatches also remain:

| Document ID | Payload subcategoryId | Resolver finding |
| --- | --- | --- |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` | `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` | `MISSING_SUBCATEGORY` for the document ID |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING` | `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT` | `MISSING_SUBCATEGORY` for the document ID |

The historical orphan-group mappings for these payload IDs remain unapproved. Their aliases were not rewritten as a workaround.

## Partial resolved template audit and observed diagnostics

The machine-readable audit in [docs/phase10-preflight-audit.json](docs/phase10-preflight-audit.json) includes the actual 59 eligible records with exact category/subcategory IDs and names, current profile metadata, readiness, resolved PRODUCT/VARIANT attributes, required/optional fields, defaults, option lists, conditions, sections and unit-rule output. It also lists all 90 exclusions, all ten collision groups, recorded reference counts, proof outcomes and production checksums.

Across the 59 eligible records: **0 PRODUCT/VARIANT intersections**, **49 DOMAIN_REVIEW_REQUIRED diagnostics**, **1 INVALID_DEFAULT diagnostic**, and **2 MISSING_SUBCATEGORY diagnostics**. No after-correction audit exists because corrections were stopped. Counts are partial baseline observations, not complete zero-defect metrics.

The invalid default is exact: `SYS_CATEGORY_FLOOR_TILE_COATINGS` / `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING`, field **usage**, default **Floor** outside that template's allowed option set. The resolver discards the invalid default and emits a warning; this is not counted as a content correction.

Resolved unit-rule output for all 59 records includes **27 globally available base-unit names and `conversionAllowed=true`**. `ProductTemplateResolver._resolveUnitRules` currently returns these values unconditionally. This does not establish invalid transactions—other unit-engine checks still apply—but a content-only change cannot prove family-specific restrictions through that resolved contract. No claim of zero invalid conversion/base-unit configurations is made, and no resolver architecture change was performed.

All observed DOMAIN_REVIEW_REQUIRED field diagnostics are listed below. They concern disagreement between template and definition placement; this report does not invent family semantics to resolve them.

| Category / subcategory | Exact subcategory ID | Field | Diagnostic |
| --- | --- | --- | --- |
| Exterior Wall Coatings / Economy Exterior Paints | `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_ECONOMY_EXTERIOR_PAINTS` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Exterior Wall Coatings / Economy Exterior Paints | `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_ECONOMY_EXTERIOR_PAINTS` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Exterior Wall Coatings / Exterior Emulsion | `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_EMULSION` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Exterior Wall Coatings / Exterior Emulsion | `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_EMULSION` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Exterior Wall Coatings / Premium Exterior Paints | `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_PREMIUM_EXTERIOR_PAINTS` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Exterior Wall Coatings / Premium Exterior Paints | `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_PREMIUM_EXTERIOR_PAINTS` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Exterior Wall Coatings / Weather Resistant Paints | `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_WEATHER_RESISTANT_PAINTS` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Exterior Wall Coatings / Weather Resistant Paints | `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_WEATHER_RESISTANT_PAINTS` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Floor & Tile Coatings / Concrete Coating | `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_CONCRETE_COATING` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Floor & Tile Coatings / Concrete Coating | `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_CONCRETE_COATING` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Floor & Tile Coatings / Epoxy Flooring | `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Floor & Tile Coatings / Epoxy Flooring | `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Floor & Tile Coatings / Floor Paint | `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_FLOOR_PAINT` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Floor & Tile Coatings / Floor Paint | `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_FLOOR_PAINT` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Interior Wall Coatings / Economy Interior Paints | `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_PAINTS` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Interior Wall Coatings / Economy Interior Paints | `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_PAINTS` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Interior Wall Coatings / Luxury Interior Paints | `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_LUXURY_INTERIOR_PAINTS` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Interior Wall Coatings / Luxury Interior Paints | `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_LUXURY_INTERIOR_PAINTS` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Metal & Wood Enamels / Anti-Corrosion Paint | `SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ANTI_CORROSION_PAINT` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Metal & Wood Enamels / Anti-Corrosion Paint | `SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ANTI_CORROSION_PAINT` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Metal & Wood Enamels / Decorative Metal Paint | `SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_DECORATIVE_METAL_PAINT` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Metal & Wood Enamels / Decorative Metal Paint | `SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_DECORATIVE_METAL_PAINT` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Metal & Wood Enamels / Enamel Paint | `SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ENAMEL_PAINT` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Metal & Wood Enamels / Enamel Paint | `SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ENAMEL_PAINT` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Protective & Industrial Coatings / Anti-Corrosion Coating | `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_ANTI_CORROSION` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Protective & Industrial Coatings / Anti-Corrosion Coating | `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_ANTI_CORROSION` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Protective & Industrial Coatings / Epoxy Coating | `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_EPOXY` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Protective & Industrial Coatings / Epoxy Coating | `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_EPOXY` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Protective & Industrial Coatings / Heat Resistant Coating | `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_HEAT_RESISTANT` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Protective & Industrial Coatings / Heat Resistant Coating | `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_HEAT_RESISTANT` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Protective & Industrial Coatings / Protective Coating | `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_PROTECTIVE` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Protective & Industrial Coatings / Protective Coating | `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_PROTECTIVE` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Floor & Tile Coatings / Epoxy Flooring | `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Floor & Tile Coatings / Epoxy Flooring | `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Interior Wall Coatings / SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS | `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Interior Wall Coatings / SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS | `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Interior Wall Coatings / Premium Interior Emulsions | `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_PREMIUM_INTERIOR_EMULSIONS` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Interior Wall Coatings / Premium Interior Emulsions | `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_PREMIUM_INTERIOR_EMULSIONS` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Painting Tools & Accessories / Brush | `SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_BRUSH` | `sizeUnit` | Attribute sizeUnit level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Painting Tools & Accessories / Roller | `SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_ROLLER` | `sizeUnit` | Attribute sizeUnit level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Painting Tools & Accessories / Sandpaper & Abrasives | `SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_SANDPAPER_ABRASIVES` | `grit` | Attribute grit level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Wood Finishes / Melamine Wood Finish | `SYS_SUBCATEGORY_WOOD_FINISHES_MELAMINE` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Wood Finishes / Melamine Wood Finish | `SYS_SUBCATEGORY_WOOD_FINISHES_MELAMINE` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Wood Finishes / PU Wood Finish | `SYS_SUBCATEGORY_WOOD_FINISHES_PU_WOOD_FINISH` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Wood Finishes / PU Wood Finish | `SYS_SUBCATEGORY_WOOD_FINISHES_PU_WOOD_FINISH` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Wood Finishes / Wood Polish | `SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_POLISH` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Wood Finishes / Wood Polish | `SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_POLISH` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Wood Finishes / Wood Sealer | `SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_SEALER` | `finish` | Attribute finish level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |
| Wood Finishes / Wood Sealer | `SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_SEALER` | `colourType` | Attribute colourType level in template (VARIANT) disagrees with definition level (PRODUCT) and requires domain review. |

## Per-family correction disposition and metrics

Every family below has **zero corrections**. Counts represent individually eligible records actually resolved, including duplicate identities; the disabled intended families are listed by exact ID in the audit JSON. No material/chemistry assumptions, new technical requirements, dynamic HSN or pricing fields were introduced.

| Family/category | Resolved baseline records | Correction disposition |
| --- | --- | --- |
| Adhesives & Tiling | 3 | Stopped before content changes; 0 corrected |
| Admixtures | 2 | Stopped before content changes; 0 corrected |
| Allied Products | 2 | Stopped before content changes; 0 corrected |
| Exterior Wall Coatings | 4 | Stopped before content changes; 0 corrected |
| Floor & Tile Coatings | 4 | Stopped before content changes; 0 corrected |
| Interior Wall Coatings | 4 | Stopped before content changes; 0 corrected |
| Metal & Wood Enamels | 3 | Stopped before content changes; 0 corrected |
| Painting Tools & Accessories | 4 | Stopped before content changes; 0 corrected |
| Primers & Undercoats | 5 | Stopped before content changes; 0 corrected |
| Protective & Industrial Coatings | 4 | Stopped before content changes; 0 corrected |
| Putty & Surface Preparation | 5 | Stopped before content changes; 0 corrected |
| Sealants & Repair | 4 | Stopped before content changes; 0 corrected |
| Wall Coverings | 2 | Stopped before content changes; 0 corrected |
| Waterproofing | 9 | Stopped before content changes; 0 corrected |
| Wood Finishes | 4 | Stopped before content changes; 0 corrected |

| Requested correction metric | Result |
| --- | --- |
| Successor release used for correction testing | None; version 4 appeared only in negative collision-validation scaffolds. |
| Selectable templates evaluated | 59 per-record eligible; 49 parent-aware unique. Intended 147 coverage not established. |
| Templates changed | 0 |
| Attributes added | 0 |
| Attributes removed | 0 |
| Requiredness changes | 0 |
| Placement changes | 0 |
| Defaults corrected | 0 |
| Option sets corrected | 0 |
| Unit-rule corrections | 0 |
| Condition corrections | 0 |
| Full before/after CRITICAL/HIGH audit | Not completed; zero findings is not claimed. |
| Invalid defaults | At least 1 observed in eligible baseline; uncorrected. |
| Unexplained diagnostics target | Not met; recorded diagnostics remain for review. |
| All-template Create/default/SELECT/colour/conversion/validator simulation | Not run; blocked before corrected release. |
| Five requested state-leakage scenarios on corrected content | Not run. Existing regressions pass in baseline; no new content result is claimed. |
| Corrected family/colour/unit/placement/validator regressions | Not run; baseline suites pass only for their existing coverage. |
| Compiler/import determinism and idempotence | Existing Phase 9 regressions pass in full baseline. No corrected successor idempotence proof exists. |

The full workspace baseline passing is separate from Phase 10 acceptance: it includes the weak historical 147-count audit and does not erase the decoded selection mismatch or the expected import rejection proofs.

## Production SQLite safety

All checksums below are complete SHA-256 values. Paths are under `/Users/sksuman/Documents/`.

| File | Size before = after | SHA-256 before | SHA-256 after | Result |
| --- | --- | --- | --- | --- |
| `nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db` | 9744384 | `76419c2ae88c03719f0965709d2e81f7cfbc65a6021278a79c93f9a14f83ee70` | `76419c2ae88c03719f0965709d2e81f7cfbc65a6021278a79c93f9a14f83ee70` | Unchanged |
| `nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak` | 9728000 | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | Unchanged |
| `nubibill-test1-bcebe-public-config.db` | 937984 | `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012` | `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012` | Unchanged |

Modification-time nanoseconds, sizes and sidecar existence also match exactly; complete metadata is retained in the JSON audit. No WAL/SHM/journal appeared in before/after observations. Final process and handle checks found no app or open production DB handles.

**Zero production SQLite writes and zero live Firestore reads/writes by this work.** No live catalogue import, Phase 8 migration, approval, production query cleanup, seed, restore or identity rewrite occurred. Archived fixture and Product/Variant/SKU/barcode production identities remain untouched.

## Files and review disposition

Only these workspace files were added:

- `phase10.md` — this stopped-preflight report.
- `docs/phase10-preflight-audit.json` — decoded selection/template observations, complete exclusions and unresolved identities, ten isolated failure proofs, reference counts and safety evidence.

No production code, catalogue fixture, compiler, resolver, UI, unit engine, validator, migration manifest or test source was modified. Temporary probes and logs are outside the repository.

**Phase 10 remains open.** Resume content correction only after the unresolved duplicate identities/semantics and the actual installed selection baseline have an explicit reviewed disposition compatible with the Phase 9 import contract. This report grants no approval to execute any production mapping or retire a legacy ID. The unit-rule contract limitation and two historical identity mismatches also need a scoped decision before claiming complete content validation. Phase 11 has not begun. Awaiting review.

Local evidence: `/private/tmp/phase10-baseline-tests.log` (default-timeout failure), `/private/tmp/phase10-baseline-tests-long.log` (248 passed), `/private/tmp/phase10-baseline-analyze.log`, `/private/tmp/phase10-preflight-proof.log` (147-baseline assertion failure), `/private/tmp/phase10-preflight-proof-final.log` (11 blocker-observation proofs passed), `/private/tmp/phase10_preflight_test.dart`, `/private/tmp/phase10-read-only-copy.db`, `/private/tmp/phase10-sqlite-before.json`, `/private/tmp/phase10-sqlite-after.json`. Essential findings are retained in the report/audit, so review does not depend on temporary logs.
