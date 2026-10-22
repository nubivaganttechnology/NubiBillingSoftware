# Phase 8 — Legacy IDs, Duplicates, Orphans and Catalogue Cleanup Design

**Phase:** `PHASE_8_LEGACY_IDS_DUPLICATES_ORPHANS_CATALOGUE_CLEANUP`
**Date:** 2026-10-04
**Status:** Analysis, deterministic proposals and isolated migration proof complete; **ready for review**. **No live cleanup executed.** All execution approvals remain false.

The full workspace passes **200/200 tests**. The migration proofs pass **31/31 direct Python/SQLite tests**, plus a Flutter check of the actual representative target through the production template resolver. `flutter analyze` reports **51 pre-existing issues, zero new diagnostics**. Production SQLite files remain byte-identical; Firestore writes are **0**.

## 1. Preflight and boundaries

| Requirement | Result |
| --- | --- |
| Required branch | fix/product-master-audit |
| Phase 7C committed | 2ca19744aa61ce177614730e8d657449e887b3fa — test(product-master): prove edit atomicity and identity safety |
| Initial working tree | Clean |
| Baseline full workspace suite | 168/168 passed; exit 0 |
| Baseline analyzer | 51 issues: 5 warnings, 46 infos, 0 errors; exit 1 |
| Checksums before inspection | Recorded before any SQLite inspection or test run |
| Production access | SQLite URI mode=ro plus PRAGMA query_only=ON; read-only connections closed explicitly |
| Live mutations | No SQLite writes, Firestore writes, seeds, catalogue deactivations or migration execution |
| Production application files | No files under lib/ modified |
| Phase 9 | Not started |

The inventory covers the current account database, including active/inactive/deleted rows and cached query/config references. The public-config database was inspected read-only and contains zero categories, subcategories, templates, Products, Variants and units. The `.db.bak` is historical evidence, excluded from current-record denominators; its missing-Product lookup was read-only.

These are complete counts for this local cache, not a claim about every remote tenant or uncached historical record. Zero local references alone is not authorization for global retirement.

## 2. Inventory counts and definitions

| Required count | Result |
| --- | --- |
| brokenReferences | 1 |
| differentParentNameGroups | 1 |
| duplicateCategoryGroups | 1 |
| duplicateSubcategoryGroups | 10 |
| legacyReferencedCategories | 3 |
| legacyReferencedSubcategories | 3 |
| missingSubcategoryTemplateGroups | 2 |
| orphanTemplateGroups | 53 |
| safeCanonicalMappings | 3 |
| unitAliases | 1 |
| unsafeAmbiguousMappings | 88 |

| Records | Active | Inactive | Total |
| --- | --- | --- | --- |
| category | 24 | 10 | 34 |
| subcategory | 149 | 49 | 198 |
| unit | 27 | 0 | 27 |

The inventory classifies **259 category/subcategory/unit records**, enumerates **199 template groups / 3,377 template rows**, and records **3874 reference occurrences**. It scans every cached local document table plus `sync_outbox`, `sync_queries` and `sync_conflicts`, including nested values and map keys.

Reference counts count field occurrences, not distinct owning records. They include inactive/deleted owners and cached query specifications. Declaring an entity's own ID, audit old-ID values, and friendly historical display strings are not operational foreign references. Flags are nonexclusive: a referenced duplicate can also require domain review.

`orphanTemplateGroups = 53` means groups without an active READY owner with active template rows: **2 missing subcategory definitions + 49 retired subcategories + 2 active but unusable groups**. Physical missing-owner groups are counted separately as 2. Legacy Product-reference counts include deleted Products; 3 categories and 3 subcategories qualify. All 59 inactive category/subcategory definitions still have some cached reference, frequently template or child-parent links.

There are **3 verified category-level rename proposals** and **88 unresolved mapping entries**. The 3 proposals are not a complete approved execution plan: their cached query/dependent references and Product subcategory targets must also clear the validation gates. The domain-review list contains 140 record/group/broken-reference cases; one legacy ID may have both a catalogue-record case and a template-group case.

Machine-readable deliverables:

- [Complete inventory and every reference location](docs/phase8-catalogue-inventory.json)
- [Canonical mapping manifest](docs/phase8-canonical-mappings.json), including the recommended model fields and explicit `approved: false`
- [Representative read-only source fixture](test/fixtures/phase8_representative_legacy.json)

## 3. All duplicate category groups

| Normalized name | IDs | Scope policy |
| --- | --- | --- |
| interior wall coatings | PM_C6btLkx5SyZvUQOzOeUUd7XxsFh2_BUS-6CB1F7443C2142159B8EBE3F9303839B_CATEGORY_23f9b9314131ef27, SYS_CATEGORY_INTERIOR_WALL_COATINGS | BUSINESS and SYSTEM collide by name; no cross-scope merge proposed |

The BUSINESS Interior Wall Coatings definition has no verified semantic bridge to the SYSTEM record. It remains `DOMAIN_REVIEW_REQUIRED`; a name match provides no migration approval.

## 4. All duplicate subcategory groups under the same parent

| Parent ID | Normalized name | Record IDs | Policy |
| --- | --- | --- | --- |
| SYS_CATEGORY_ADHESIVES_TILING | tile adhesives | SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES, SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES | Keep all; differing or unverified template contracts require review |
| SYS_CATEGORY_ALLIED_PRODUCTS | thinners | SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS, SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS | Keep all; differing or unverified template contracts require review |
| SYS_CATEGORY_FLOOR_TILE_COATINGS | epoxy flooring | SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING, SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING | Keep all; differing or unverified template contracts require review |
| SYS_CATEGORY_PUTTY_SURFACE_PREPARATION | acrylic putty | SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY, SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY | Keep all; differing or unverified template contracts require review |
| SYS_CATEGORY_PUTTY_SURFACE_PREPARATION | waterproof wall putty | SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY, SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY | Keep all; differing or unverified template contracts require review |
| SYS_CATEGORY_SEALANTS_REPAIR | acrylic sealants | SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS, SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS | Keep all; differing or unverified template contracts require review |
| SYS_CATEGORY_WATERPROOFING | bathroom & kitchen waterproofing | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING, SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN | Keep all; differing or unverified template contracts require review |
| SYS_CATEGORY_WATERPROOFING | exterior wall waterproofing | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING, SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL | Keep all; differing or unverified template contracts require review |
| SYS_CATEGORY_WATERPROOFING | interior dampness treatment | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT, SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS | Keep all; differing or unverified template contracts require review |
| SYS_CATEGORY_WATERPROOFING | roof & terrace waterproofing | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING, SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE | Keep all; differing or unverified template contracts require review |

## 5. Same names under different valid parents

These remain distinct identities. The planner never performs a global name merge.

| Normalized name | IDs and parents | Classification |
| --- | --- | --- |
| exterior textures | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_TEXTURES → SYS_CATEGORY_EXTERIOR_WALL_COATINGS, SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_EXTERIOR_TEXTURES → SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS | DOMAIN_REVIEW_REQUIRED; keep distinct parents |

## 6. All legacy category/subcategory IDs referenced by saved Products

### Categories

| Legacy ID | Name | Product refs | All refs | Active-owner refs | Disposition |
| --- | --- | --- | --- | --- | --- |
| PM_CATEGORY_93d0611d84196d62 | Paint | 1 | 2 | 1 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED |
| SYS_CATEGORY_ACCESSORIES | Accessories | 1 | 6 | 1 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| SYS_CATEGORY_EXTERIOR_WALL_PAINTS | Exterior Wall Paints | 1 | 7 | 1 | LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |

### Subcategories

| Legacy ID | Name | Product refs | All refs | Active-owner refs | Disposition |
| --- | --- | --- | --- | --- | --- |
| PM_SUBCATEGORY_ce0bf39843417fca | Interior Wall Paint | 1 | 3 | 0 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED |
| SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH | Brush | 1 | 8 | 1 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS | Economy Exterior Paints | 1 | 16 | 1 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |

Active Sharlimar_paint_001 references the retired Exterior Wall Paints category and retired Economy Exterior Paints subcategory. Active Professional Paint Brush references the retired Accessories category and Brush subcategory. The deleted Royale Glitz Product still references BUSINESS Paint / Interior Wall Paint. The latter active classification has no valid template and remains unresolved; it is not inferred to be a particular interior emulsion from the Product's display name.

## 7. Deterministic mapping model and all proposals

`CatalogueCanonicalMapping` carries `recordType`, `legacyId`, `canonicalId`, `reason`, `referenceCount`, `safeToDeactivate`, `requiresDataMigration`, and `warnings`, plus explicit approval and semantic-evidence fields. IDs, parent context, scope, declared aliases and full template semantics drive proposals. Normalized names only identify collisions/candidates.

A null target means **no mapping proposed**. `requiresDataMigration` means references must move before retirement could occur; it does not authorize that migration. No unresolved record is auto-mapped. No proposed mapping permits Product/Variant identity, SKU/barcode or historical-reference replacement.

| Type | Legacy ID | Canonical ID | References | Safe to deactivate now | Migration needed | Reason / warnings |
| --- | --- | --- | --- | --- | --- | --- |
| category | PM_C6btLkx5SyZvUQOzOeUUd7XxsFh2_BUS-6CB1F7443C2142159B8EBE3F9303839B_CATEGORY_23f9b9314131ef27 | — | 0 | False | False | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | PM_CATEGORY_93d0611d84196d62 | — | 2 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_ACCESSORIES | — | 6 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_EXTERIOR_WALL_PAINTS | SYS_CATEGORY_EXTERIOR_WALL_COATINGS | 7 | False | True | Explicit current SYSTEM category alias; same catalogue/business scope. |
| category | SYS_CATEGORY_FLOOR_COATINGS | SYS_CATEGORY_FLOOR_TILE_COATINGS | 3 | False | True | Explicit current SYSTEM category alias; same catalogue/business scope. |
| category | SYS_CATEGORY_HEALTH_HYGIENE | — | 1 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_INDUSTRIAL_COATINGS | — | 4 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_INTERIOR_WALL_COATINGS | — | 21 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_INTERIOR_WALL_PAINTS | SYS_CATEGORY_INTERIOR_WALL_COATINGS | 5 | False | True | Explicit current SYSTEM category alias; same catalogue/business scope. |
| category | SYS_CATEGORY_METAL_PAINTS | — | 4 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_PRIMERS_PUTTY | — | 4 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_WALLPAPERS | — | 4 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_WALL_TEXTURES | — | 8 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_WOOD_COATINGS | — | 5 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | PM_SUBCATEGORY_ce0bf39843417fca | — | 3 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES | — | 8 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS | — | 6 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING | — | 21 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY | — | 17 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY | — | 17 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS | — | 9 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH | — | 8 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_ROLLER | — | 4 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_SANDPAPER | — | 3 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_MISCELLANEOUS | — | 6 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS | — | 6 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_TEXTURES | — | 24 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS | — | 16 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_EXTERIOR_EMULSION | — | 13 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_PREMIUM_EXTERIOR_PAINTS | — | 13 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_WEATHER_RESISTANT_PAINTS | — | 13 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_CONCRETE_COATING | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_EPOXY_FLOORING | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_FLOOR_PAINT | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING | — | 21 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS | — | 22 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_ANTI_CORROSION_COATING | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_EPOXY_COATING | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_HEAT_RESISTANT_COATING | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_PROTECTIVE_COATING | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_DISTEMPER | — | 13 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_ECONOMY_PAINTS | — | 13 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_EMULSION_PAINTS | — | 13 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_LUXURY_PAINTS | — | 13 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_PREMIUM_PAINTS | — | 13 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ANTI_CORROSION_PAINT | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_DECORATIVE_METAL_PAINT | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ENAMEL_PAINT | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_PROTECTIVE_COATING | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_EXTERIOR_WALL_PRIMER | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_INTERIOR_WALL_PRIMER | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WALL_PUTTY | — | 7 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WOOD_PRIMER | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY | — | 19 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY | — | 19 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS | — | 14 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_EXTERIOR_TEXTURES | — | 23 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_DESIGNER_WALLPAPER | — | 4 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_NON_WOVEN_WALLPAPER | — | 4 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_PAPER_WALLPAPER | — | 4 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_VINYL_WALLPAPER | — | 4 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_3D_TEXTURE | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_CONCRETE_TEXTURE | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_DESIGNER_TEXTURE | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_MARBLE_TEXTURE | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_METALLIC_TEXTURE | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STONE_TEXTURE | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STUCCO_TEXTURE | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_VELVET_TEXTURE | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING | — | 14 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_WATERPROOFING | — | 7 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_CRACK_REPAIR | — | 7 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_DAMP_PROOFING | — | 7 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING | — | 14 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT | — | 14 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING | — | 14 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_TERRACE_WATERPROOFING | — | 7 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_WALL_WATERPROOFING | — | 7 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_MELAMINE | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_PU_COATING | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_POLISH | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_SEALER | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_STAIN | — | 12 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN | — | 15 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL | — | 15 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS | — | 15 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE | — | 15 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| unit | PM_UNIT_3871fc5bdee74d78 | — | 2 | False | True | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Exact dimension/kind/scale/meaning metadata is missing or incompatible; retain display alias.; No unambiguous ID/parent/semantic mapping established; keep record. |
| templateGroup | SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS | — | 22 | False | True | Missing subcategory definition; no verified parent context. DOMAIN_REVIEW_REQUIRED |
| templateGroup | SYS_SUBCATEGORY_WATERPROOFING_BASEMENT | — | 15 | False | True | Missing subcategory definition; no verified parent context. DOMAIN_REVIEW_REQUIRED |

The category proposals use explicit aliases on current SYSTEM records in the same catalogue/business scope:

- `SYS_CATEGORY_EXTERIOR_WALL_PAINTS` → `SYS_CATEGORY_EXTERIOR_WALL_COATINGS` (7 cached reference occurrences).
- `SYS_CATEGORY_FLOOR_COATINGS` → `SYS_CATEGORY_FLOOR_TILE_COATINGS` (3).
- `SYS_CATEGORY_INTERIOR_WALL_PAINTS` → `SYS_CATEGORY_INTERIOR_WALL_COATINGS` (5).

Accessories → Painting Tools & Accessories remains unresolved because an explicit verified bridge was not established. Split/renamed legacy domains such as Primers & Putty, Metal Paints, Wood Coatings and Industrial Coatings remain review items. Subcategory candidates with different template signatures are never promoted to automatic mappings.

## 8. All orphan / unusable template groups

Every row is retained and enumerated by ID in the JSON inventory. Groups below remain `ORPHAN_TEMPLATE_GROUP` and `DOMAIN_REVIEW_REQUIRED`; no template group has an automatic remap.

| Subcategory ID | Owner exists | Owner status | Rows | Active rows | Reason |
| --- | --- | --- | --- | --- | --- |
| SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS | False | — | 21 | 21 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH | True | INACTIVE | 5 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_ROLLER | True | INACTIVE | 4 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_SANDPAPER | True | INACTIVE | 3 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_MISCELLANEOUS | True | ACTIVE | 6 | 5 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS | True | INACTIVE | 13 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_EXTERIOR_EMULSION | True | INACTIVE | 13 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_PREMIUM_EXTERIOR_PAINTS | True | INACTIVE | 13 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_WEATHER_RESISTANT_PAINTS | True | INACTIVE | 13 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_CONCRETE_COATING | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_EPOXY_FLOORING | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_FLOOR_PAINT | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS | True | ACTIVE | 22 | 3 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_ANTI_CORROSION_COATING | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_EPOXY_COATING | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_HEAT_RESISTANT_COATING | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_PROTECTIVE_COATING | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_DISTEMPER | True | INACTIVE | 13 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_ECONOMY_PAINTS | True | INACTIVE | 13 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_EMULSION_PAINTS | True | INACTIVE | 13 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_LUXURY_PAINTS | True | INACTIVE | 13 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_PREMIUM_PAINTS | True | INACTIVE | 13 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ANTI_CORROSION_PAINT | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_DECORATIVE_METAL_PAINT | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ENAMEL_PAINT | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_PROTECTIVE_COATING | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_EXTERIOR_WALL_PRIMER | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_INTERIOR_WALL_PRIMER | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WALL_PUTTY | True | INACTIVE | 7 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WOOD_PRIMER | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_DESIGNER_WALLPAPER | True | INACTIVE | 4 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_NON_WOVEN_WALLPAPER | True | INACTIVE | 4 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_PAPER_WALLPAPER | True | INACTIVE | 4 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_VINYL_WALLPAPER | True | INACTIVE | 4 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_3D_TEXTURE | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_CONCRETE_TEXTURE | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_DESIGNER_TEXTURE | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_MARBLE_TEXTURE | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_METALLIC_TEXTURE | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STONE_TEXTURE | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STUCCO_TEXTURE | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_VELVET_TEXTURE | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_WATERPROOFING | True | INACTIVE | 7 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_CRACK_REPAIR | True | INACTIVE | 7 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_DAMP_PROOFING | True | INACTIVE | 7 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_TERRACE_WATERPROOFING | True | INACTIVE | 7 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_WALL_WATERPROOFING | True | INACTIVE | 7 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_MELAMINE | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_PU_COATING | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_POLISH | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_SEALER | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_STAIN | True | INACTIVE | 12 | 0 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| SYS_SUBCATEGORY_WATERPROOFING_BASEMENT | False | — | 14 | 14 | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |

The physical missing-owner groups are `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` (21 rows) and `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT` (14 rows). Unknown parent context prevents selecting a target solely from similar template contents.

The two active-owner unusable groups are Miscellaneous (6 rows) and Health/Hygiene Hand Sanitizers (22 rows). Scope/readiness metadata is retained as a review case; this phase makes no scope or catalogue-content changes.

## 9. All retired-but-referenced IDs

| Type | ID | References | Product refs | Template refs |
| --- | --- | --- | --- | --- |
| category | SYS_CATEGORY_ACCESSORIES | 6 | 1 | 0 |
| category | SYS_CATEGORY_EXTERIOR_WALL_PAINTS | 7 | 1 | 0 |
| category | SYS_CATEGORY_FLOOR_COATINGS | 3 | 0 | 0 |
| category | SYS_CATEGORY_INDUSTRIAL_COATINGS | 4 | 0 | 0 |
| category | SYS_CATEGORY_INTERIOR_WALL_PAINTS | 5 | 0 | 0 |
| category | SYS_CATEGORY_METAL_PAINTS | 4 | 0 | 0 |
| category | SYS_CATEGORY_PRIMERS_PUTTY | 4 | 0 | 0 |
| category | SYS_CATEGORY_WALLPAPERS | 4 | 0 | 0 |
| category | SYS_CATEGORY_WALL_TEXTURES | 8 | 0 | 0 |
| category | SYS_CATEGORY_WOOD_COATINGS | 5 | 0 | 0 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH | 8 | 1 | 5 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_ROLLER | 4 | 0 | 4 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_SANDPAPER | 3 | 0 | 3 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS | 16 | 1 | 13 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_EXTERIOR_EMULSION | 13 | 0 | 13 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_PREMIUM_EXTERIOR_PAINTS | 13 | 0 | 13 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_WEATHER_RESISTANT_PAINTS | 13 | 0 | 13 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_CONCRETE_COATING | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_EPOXY_FLOORING | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_FLOOR_PAINT | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_ANTI_CORROSION_COATING | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_EPOXY_COATING | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_HEAT_RESISTANT_COATING | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_PROTECTIVE_COATING | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_DISTEMPER | 13 | 0 | 13 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_ECONOMY_PAINTS | 13 | 0 | 13 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_EMULSION_PAINTS | 13 | 0 | 13 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_LUXURY_PAINTS | 13 | 0 | 13 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_PREMIUM_PAINTS | 13 | 0 | 13 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ANTI_CORROSION_PAINT | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_DECORATIVE_METAL_PAINT | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ENAMEL_PAINT | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_PROTECTIVE_COATING | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_EXTERIOR_WALL_PRIMER | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_INTERIOR_WALL_PRIMER | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WALL_PUTTY | 7 | 0 | 7 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WOOD_PRIMER | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_DESIGNER_WALLPAPER | 4 | 0 | 4 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_NON_WOVEN_WALLPAPER | 4 | 0 | 4 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_PAPER_WALLPAPER | 4 | 0 | 4 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_VINYL_WALLPAPER | 4 | 0 | 4 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_3D_TEXTURE | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_CONCRETE_TEXTURE | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_DESIGNER_TEXTURE | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_MARBLE_TEXTURE | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_METALLIC_TEXTURE | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STONE_TEXTURE | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STUCCO_TEXTURE | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_VELVET_TEXTURE | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_WATERPROOFING | 7 | 0 | 7 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_CRACK_REPAIR | 7 | 0 | 7 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_DAMP_PROOFING | 7 | 0 | 7 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_TERRACE_WATERPROOFING | 7 | 0 | 7 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_WALL_WATERPROOFING | 7 | 0 | 7 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_MELAMINE | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_PU_COATING | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_POLISH | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_SEALER | 12 | 0 | 12 |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_STAIN | 12 | 0 | 12 |

## 10. Unit aliases and broken references

| Alias ID | Display name | Reference count | Candidate | Disposition |
| --- | --- | --- | --- | --- |
| PM_UNIT_3871fc5bdee74d78 | L | 2 | SYS_UNIT_LITRE | UNIT_ALIAS + DOMAIN_REVIEW_REQUIRED; retain |

The legacy `PM_UNIT_3871fc5bdee74d78` / `L` has two ID references on an inactive Variant. Its dimension, unit kind, scale and exact meaning are missing; the current Litre record also lacks sufficient semantic metadata for a verified automatic conversion. No real alias remap is proposed. Synthetic exact-metadata tests prove L → Litre behavior and preserve historical `unitName: L`. Packaging → measurement, scale mismatches and missing metadata are rejected.

| Owning record | Missing target | Field | Classification / recommendation |
| --- | --- | --- | --- |
| VAR-233931D4CB8A432E8F2DC88912B59C48 | PROD-4B68A3FB3C10447F8A5696B17739C81F | productId | BROKEN_REFERENCE + DOMAIN_REVIEW_REQUIRED. Recover original referenced record from authorized backup/server evidence; never auto-attach or regenerate identity. |

Active Variant `VAR-233931D4CB8A432E8F2DC88912B59C48` references locally absent Product `PROD-4B68A3FB3C10447F8A5696B17739C81F`. A read-only lookup in the existing `.db.bak` did not find that Product either. Review authoritative backup/server evidence for the **original ID**, tenant and business before proposing a separate repair. Nothing was attached, recreated, retired or written in production.

## 11. All DOMAIN_REVIEW_REQUIRED cases

| Type | ID / owner | References | Candidates (unapproved) | Review reason |
| --- | --- | --- | --- | --- |
| category | PM_C6btLkx5SyZvUQOzOeUUd7XxsFh2_BUS-6CB1F7443C2142159B8EBE3F9303839B_CATEGORY_23f9b9314131ef27 | 0 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | PM_CATEGORY_93d0611d84196d62 | 2 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_ACCESSORIES | 6 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_HEALTH_HYGIENE | 1 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_INDUSTRIAL_COATINGS | 4 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_INTERIOR_WALL_COATINGS | 21 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_METAL_PAINTS | 4 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_PRIMERS_PUTTY | 4 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_WALLPAPERS | 4 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_WALL_TEXTURES | 8 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| category | SYS_CATEGORY_WOOD_COATINGS | 5 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | PM_SUBCATEGORY_ce0bf39843417fca | 3 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES | 8 | SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS | 6 | SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING | 21 | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY | 17 | SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY | 17 | SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS | 9 | SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH | 8 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_ROLLER | 4 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_SANDPAPER | 3 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES | 12 | SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_MISCELLANEOUS | 6 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS | 6 | SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_TEXTURES | 24 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS | 16 | SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_ECONOMY_EXTERIOR_PAINTS | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_EXTERIOR_EMULSION | 13 | SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_EMULSION | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_PREMIUM_EXTERIOR_PAINTS | 13 | SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_PREMIUM_EXTERIOR_PAINTS | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_WEATHER_RESISTANT_PAINTS | 13 | SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_WEATHER_RESISTANT_PAINTS | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_CONCRETE_COATING | 12 | SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_CONCRETE_COATING | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_EPOXY_FLOORING | 12 | SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING, SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_FLOOR_PAINT | 12 | SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_FLOOR_PAINT | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING | 21 | SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS | 22 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_ANTI_CORROSION_COATING | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_EPOXY_COATING | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_HEAT_RESISTANT_COATING | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_PROTECTIVE_COATING | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_DISTEMPER | 13 | SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_PAINTS | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_ECONOMY_PAINTS | 13 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_EMULSION_PAINTS | 13 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_LUXURY_PAINTS | 13 | SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_LUXURY_INTERIOR_PAINTS | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_PREMIUM_PAINTS | 13 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ANTI_CORROSION_PAINT | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_DECORATIVE_METAL_PAINT | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ENAMEL_PAINT | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_PROTECTIVE_COATING | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_EXTERIOR_WALL_PRIMER | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_INTERIOR_WALL_PRIMER | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WALL_PUTTY | 7 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WOOD_PRIMER | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY | 19 | SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY | 19 | SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS | 14 | SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_EXTERIOR_TEXTURES | 23 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_DESIGNER_WALLPAPER | 4 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_NON_WOVEN_WALLPAPER | 4 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_PAPER_WALLPAPER | 4 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_VINYL_WALLPAPER | 4 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_3D_TEXTURE | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_CONCRETE_TEXTURE | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_DESIGNER_TEXTURE | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_MARBLE_TEXTURE | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_METALLIC_TEXTURE | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STONE_TEXTURE | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STUCCO_TEXTURE | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_VELVET_TEXTURE | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING | 14 | SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_WATERPROOFING | 7 | SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_CRACK_REPAIR | 7 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_DAMP_PROOFING | 7 | SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING | 14 | SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT | 14 | SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING | 14 | SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_TERRACE_WATERPROOFING | 7 | SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_WALL_WATERPROOFING | 7 | SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_MELAMINE | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_PU_COATING | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_POLISH | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_SEALER | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_STAIN | 12 |  | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN | 15 | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL | 15 | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS | 15 | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| subcategory | SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE | 15 | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Name/parent candidate is insufficient: template semantics differ or candidates conflict.; No unambiguous ID/parent/semantic mapping established; keep record. |
| unit | PM_UNIT_3871fc5bdee74d78 | 2 | SYS_UNIT_LITRE | DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence. Exact dimension/kind/scale/meaning metadata is missing or incompatible; retain display alias.; No unambiguous ID/parent/semantic mapping established; keep record. |
| templateGroup | SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS | 22 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH | 8 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_ROLLER | 4 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_SANDPAPER | 3 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_MISCELLANEOUS | 6 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS | 16 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_EXTERIOR_EMULSION | 13 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_PREMIUM_EXTERIOR_PAINTS | 13 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_WEATHER_RESISTANT_PAINTS | 13 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_CONCRETE_COATING | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_EPOXY_FLOORING | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_FLOOR_PAINT | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS | 22 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_ANTI_CORROSION_COATING | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_EPOXY_COATING | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_HEAT_RESISTANT_COATING | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_PROTECTIVE_COATING | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_DISTEMPER | 13 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_ECONOMY_PAINTS | 13 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_EMULSION_PAINTS | 13 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_LUXURY_PAINTS | 13 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_PREMIUM_PAINTS | 13 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ANTI_CORROSION_PAINT | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_DECORATIVE_METAL_PAINT | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ENAMEL_PAINT | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_PROTECTIVE_COATING | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_EXTERIOR_WALL_PRIMER | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_INTERIOR_WALL_PRIMER | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WALL_PUTTY | 7 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WOOD_PRIMER | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_DESIGNER_WALLPAPER | 4 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_NON_WOVEN_WALLPAPER | 4 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_PAPER_WALLPAPER | 4 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_VINYL_WALLPAPER | 4 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_3D_TEXTURE | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_CONCRETE_TEXTURE | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_DESIGNER_TEXTURE | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_MARBLE_TEXTURE | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_METALLIC_TEXTURE | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STONE_TEXTURE | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STUCCO_TEXTURE | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_VELVET_TEXTURE | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_WATERPROOFING | 7 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_CRACK_REPAIR | 7 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_DAMP_PROOFING | 7 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_TERRACE_WATERPROOFING | 7 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_WALL_WATERPROOFING | 7 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_MELAMINE | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_PU_COATING | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_POLISH | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_SEALER | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_STAIN | 12 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| templateGroup | SYS_SUBCATEGORY_WATERPROOFING_BASEMENT | 15 |  | No approved ID/parent mapping for template group; semantic comparison alone cannot attach it. |
| brokenReference | VAR-233931D4CB8A432E8F2DC88912B59C48 | 1 | PROD-4B68A3FB3C10447F8A5696B17739C81F | Recover original referenced record from authorized backup/server evidence; never auto-attach or regenerate identity. |

## 12. Proposed atomic migration algorithm

The implementation is a sandbox prototype in `tool/catalogue_phase8.py`. Its CLI only generates an inventory JSON. The migration class creates its own new temporary database from supplied rows; it accepts no writable live-database path and validates that the connection still points to its owned temporary database.

1. Load the mapping JSON through `load_canonical_mappings()`. Select only explicitly reviewed test mappings; unapproved/null-target/unresolved-domain entries are rejected.
2. Validate source/target IDs, active targets, READY template rows and parent-category coherence. Product classification pairs must resolve together. Unit dimension/kind/scale/meaning must match exactly.
3. Reject mapping cycles, self-maps, duplicate sources and unflattened chains. Product/Variant identity mappings are forbidden.
4. Scan every known reference. Approved mutable locations are Product classification fields, Variant unit-ID fields, subcategory parent IDs and template subcategory references. Historical, role/config, cached-query, pending-outbox, nested/unknown reference locations block the operation; they are never blindly rewritten.
5. Start one SQLite `BEGIN IMMEDIATE` transaction and verify the locked snapshot still matches validation.
6. Update approved Product category/subcategory IDs only; preserve IDs, names, timestamps, payload attributes and all history fields.
7. Update approved Variant unit IDs only; preserve Product links, Variant IDs, SKU, barcode, quantities, conversion factors and historical display strings.
8. Update approved dependent subcategory/template references. Orphan/legacy templates must have an identical semantic signature and explicit parent approval. Keep every template row ID.
9. Recount operational references to every migrated legacy ID. Only when all are zero mark legacy definitions/templates `INACTIVE`, retaining their IDs and payloads. Any blocker aborts the whole operation before retirement.
10. Write audit rows and commit atomically. Audit fields are `migrationId`, `recordType`, `legacyId`, `canonicalId`, `referenceCountBefore`, `referenceCountAfter`, `timestamp`, `status`, `notes`. Sandbox audit status is `SIMULATED`; notes record approval evidence. Any failure, including audit insertion, rolls back all reference changes, retirements and audit rows.

Raw encoded JSON is patched at approved top-level keys, rather than decoded/re-encoded wholesale, preserving timestamp encodings and unrelated fields. Indexed classification/status columns are changed alongside their payload fields. Existing sync revisions/status and remote update metadata remain untouched in the sandbox. No Firestore/outbox delivery or live rollout is implemented in this phase.

Current cached `sync_queries` contain legacy IDs (including two references to the old Exterior Wall Paints category). The prototype deliberately rejects their implicit replacement. Review of those dependencies is still required before a complete execution plan can be approved; no compiler/sync repair was attempted.

## 13. Isolated migration and identity proof

The representative fixture copies actual legacy category/subcategory rows, one actual Product and its Variant, and the real canonical target/template metadata from read-only production. It is a subset: legacy template groups and cached query specifications are intentionally excluded from the success fixture and remain fully listed in the inventory. Its success test uses **test-only hypothetical explicit semantic approval**, proving mechanics without approving that production subcategory mapping.

The production `ProductTemplateResolver` independently resolves that representative canonical target to **READY** in a temporary database using the real `LocalDatabase` schema. Python migration fixtures preserve the original row columns and encoded document payload shape; they are independently owned temporary SQLite databases, not live-schema migrations.

Synthetic fixtures cover complete approved category/subcategory/unit dependencies, historical purchase/inventory payloads, orphan templates, and protected config/sync references. Tests assert exact history and sync-metadata snapshots and unchanged Product/Variant identity, SKU/barcode, timestamps and unrelated Product attributes. Successful approved fixtures leave zero operational references to migrated IDs while retaining legacy definitions and old-ID audit evidence.

| Required proof | Result |
| --- | --- |
| Retired category → canonical; Product ID unchanged | PASS |
| Retired subcategory → canonical; Variant identities unchanged | PASS |
| Referenced duplicate retained until references migrate | PASS; observed before retirement and rows never deleted |
| Same-name different-parent subcategories not merged | PASS; separate inventory groups and cross-parent rejection |
| L → Litre only for exact semantics | PASS; historical display preserved |
| Packaging never merged into measurement | PASS |
| Orphan template detected | PASS |
| Ambiguous orphan requires review | PASS; no writes or discarded rows |
| Missing Product detected; no auto-attachment | PASS |
| Cycle rejected | PASS |
| Missing canonical target rejected | PASS |
| Forced failure rolls back every reference update | PASS; Product, Variant, dependencies, pre-retirement and audit stages |
| Successful isolated migration clears migrated IDs | PASS; audit referenceCountAfter=0 |
| Product/Variant ID, SKU/barcode, timestamps/history unchanged | PASS |
| Unapproved/review mappings and foreign DB connection rejected | PASS |
| Config/map-key/history/outbox references block migration | PASS |
| Audit collision/replay failure rolls back | PASS |

Failure injection is a test-only callback after actual SQL mutations inside the sandbox transaction. At the Product and Variant stages tests inspect the new references before throwing. At the audit stage all 3 audit rows and retirements exist before the forced exception. Exact snapshots after rollback match the original database, including historical rows and zero audit side effects. Legacy rows remain in their original ACTIVE state on every failure.

All direct Python proof cases:

- **PASS** — `test_ambiguous_orphan_requires_review_and_is_retained`

- **PASS** — `test_broken_variant_parent_detected_not_auto_repaired`

- **PASS** — `test_business_category_not_merged_by_name`

- **PASS** — `test_config_map_key_reference_blocks_retirement`

- **PASS** — `test_cycle_rejected`

- **PASS** — `test_duplicate_is_kept_until_all_references_move`

- **PASS** — `test_exact_approved_orphan_remap_retains_row_identity`

- **PASS** — `test_executor_refuses_a_connection_it_does_not_own`

- **PASS** — `test_forced_failure_rolls_back_every_stage`

- **PASS** — `test_historical_reference_blocks_whole_migration`

- **PASS** — `test_identity_timestamps_history_and_sync_metadata_unchanged`

- **PASS** — `test_l_alias_requires_exact_semantics`

- **PASS** — `test_mapping_json_load_preserves_approval_and_audit_fields`

- **PASS** — `test_migration_audit_failure_rolls_back_and_does_not_replay`

- **PASS** — `test_missing_target_rejected`

- **PASS** — `test_non_ready_target_rejected`

- **PASS** — `test_orphan_template_group_detected`

- **PASS** — `test_packaging_never_merged_into_measurement`

- **PASS** — `test_pending_outbox_reference_blocks_migration`

- **PASS** — `test_product_or_variant_identity_mapping_rejected`

- **PASS** — `test_read_only_connection_cannot_mutate`

- **PASS** — `test_real_representative_copy_preserves_identity_and_history_fields`

- **PASS** — `test_retired_category_preserves_product_id`

- **PASS** — `test_retired_subcategory_preserves_variant_identity`

- **PASS** — `test_role_config_nested_reference_blocks_retirement`

- **PASS** — `test_same_name_under_different_parents_never_auto_merges`

- **PASS** — `test_success_clears_all_migrated_reference_ids`

- **PASS** — `test_unapproved_or_ambiguous_mapping_rejected`

- **PASS** — `test_unit_missing_dimension_is_domain_review_required`

- **PASS** — `test_unit_scale_mismatch_rejected`

- **PASS** — `test_unresolved_domain_review_cannot_be_marked_approved`

## 14. Verification and files

- Baseline `flutter test --reporter expanded`: **168/168 passed**, exit 0.
- Final `flutter test --reporter expanded`: **200/200 passed**, exit 0: `00:20 +200: All tests passed!`.
- `python3 -B -m unittest discover -s tool/tests -p test_catalogue_phase8.py -v`: **31/31 passed**, exit 0.
- New Flutter registrations: **31 direct Python proofs + 1 actual READY resolver proof = 32**.
- Final `flutter analyze`: **51 existing issues** (5 warnings, 46 infos, 0 errors), exit 1; normalized diagnostic set identical to baseline, **0 new issues**.
- `git diff --check`: passed.

Logs: `/private/tmp/phase8-baseline-tests.log`, `/private/tmp/phase8-baseline-analyze.log`, `/private/tmp/phase8-migration-tests.log`, `/private/tmp/phase8-final-tests.log`, `/private/tmp/phase8-final-analyze.log`. Flutter/Dart verification used approved access to SDK cache/telemetry metadata outside the workspace.

Files added:

| File | Purpose |
| --- | --- |
| tool/catalogue_phase8.py | Read-only inventory, mapping model/loader, sandbox-only atomic migration prototype |
| tool/tests/test_catalogue_phase8.py | 31 direct SQLite proof cases |
| test/catalogue_phase8_migration_test.dart | Register Python proofs in the full workspace suite; real READY resolver test |
| test/fixtures/phase8_representative_legacy.json | Representative read-only source records for isolated copies |
| docs/phase8-catalogue-inventory.json | Complete catalogue inventory, classifications, all reference locations and review cases |
| docs/phase8-canonical-mappings.json | Deterministic proposed mappings; every approval false |
| phase8.md | This complete report |

No existing production code, catalogue master data, Product/Variant IDs, SKU/barcode or historical references were changed. Phase 8 changes remain uncommitted for review.

## 15. Production checksums and Firestore safety

| File | Before SHA-256 | After SHA-256 |
| --- | --- | --- |
| /Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db | 02741485aa4c73a9dc1c0f363a4517d6009adcb1351792f510ba4ce53970e21c | 02741485aa4c73a9dc1c0f363a4517d6009adcb1351792f510ba4ce53970e21c |
| /Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak | 853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651 | 853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651 |
| /Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db | c641b3c18a4dcd49f09960476298db9a993a5f6382bf52294441975c08aad957 | c641b3c18a4dcd49f09960476298db9a993a5f6382bf52294441975c08aad957 |

The production file set and sizes are unchanged too. No WAL/SHM sidecar appeared. File hashes were obtained by reading bytes; production SQLite connections were exclusively read-only.

**Zero Firestore writes:** the new migration/inventory tools import no network/Firestore client and expose no remote-write operation. The Flutter resolver reader supports only SQLite queries; every other interface call throws. No application, seed script or sync engine was launched. Existing suite REST tests use mock clients; existing production catalogue audits use read-only SQLite connections.

## Appendix A — Every category, subcategory and unit classified

Reference locations, ownership status, scope context, aliases, unit metadata and proposed candidates accompany every ID in the JSON inventory. The table below includes active and inactive definitions and a reference count for every legacy ID.

| Type | ID | Name | Parent | Status | References | Classification flags |
| --- | --- | --- | --- | --- | --- | --- |
| category | PM_C6btLkx5SyZvUQOzOeUUd7XxsFh2_BUS-6CB1F7443C2142159B8EBE3F9303839B_CATEGORY_23f9b9314131ef27 | Interior Wall Coatings | — | ACTIVE | 0 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_SHADOW |
| category | PM_CATEGORY_93d0611d84196d62 | Paint | — | ACTIVE | 2 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED |
| category | SYS_CATEGORY_ACCESSORIES | Accessories | — | INACTIVE | 6 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| category | SYS_CATEGORY_ADHESIVES_TILING | Adhesives & Tiling | — | ACTIVE | 11 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_ADMIXTURES | Admixtures | — | ACTIVE | 10 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_ALLIED_PRODUCTS | Allied Products | — | ACTIVE | 8 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_AUTOMOTIVE_COATINGS | Automotive Coatings | — | ACTIVE | 2 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_DIY_AEROSOLS | DIY & Aerosols | — | ACTIVE | 6 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_EXTERIOR_WALL_COATINGS | Exterior Wall Coatings | — | ACTIVE | 24 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_EXTERIOR_WALL_PAINTS | Exterior Wall Paints | — | INACTIVE | 7 | LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| category | SYS_CATEGORY_FLOOR_COATINGS | Floor Coatings | — | INACTIVE | 3 | LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| category | SYS_CATEGORY_FLOOR_TILE_COATINGS | Floor & Tile Coatings | — | ACTIVE | 13 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_HEALTH_HYGIENE | Health & Hygiene | — | ACTIVE | 1 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED |
| category | SYS_CATEGORY_INDUSTRIAL_COATINGS | Industrial Coatings | — | INACTIVE | 4 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| category | SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS | Interior & Exterior Coatings | — | ACTIVE | 6 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_INTERIOR_WALL_COATINGS | Interior Wall Coatings | — | ACTIVE | 21 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| category | SYS_CATEGORY_INTERIOR_WALL_PAINTS | Interior Wall Paints | — | INACTIVE | 5 | LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| category | SYS_CATEGORY_METAL_PAINTS | Metal Paints | — | INACTIVE | 4 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| category | SYS_CATEGORY_METAL_WOOD_ENAMELS | Metal & Wood Enamels | — | ACTIVE | 16 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES | Painting Tools & Accessories | — | ACTIVE | 6 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_PIPE_GI_COATINGS | Pipe & GI Coatings | — | ACTIVE | 4 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_POWDER_COATINGS | Powder Coatings | — | ACTIVE | 2 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_PRIMERS_PUTTY | Primers & Putty | — | INACTIVE | 4 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| category | SYS_CATEGORY_PRIMERS_UNDERCOATS | Primers & Undercoats | — | ACTIVE | 13 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | Protective & Industrial Coatings | — | ACTIVE | 28 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_PUTTY_SURFACE_PREPARATION | Putty & Surface Preparation | — | ACTIVE | 15 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_SEALANTS_REPAIR | Sealants & Repair | — | ACTIVE | 14 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS | Textures & Special Effects | — | ACTIVE | 12 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_WALLPAPERS | Wallpapers | — | INACTIVE | 4 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| category | SYS_CATEGORY_WALL_COVERINGS | Wall Coverings | — | ACTIVE | 3 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_WALL_TEXTURES | Wall Textures | — | INACTIVE | 8 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| category | SYS_CATEGORY_WATERPROOFING | Waterproofing | — | ACTIVE | 32 | CANONICAL_ACTIVE |
| category | SYS_CATEGORY_WOOD_COATINGS | Wood Coatings | — | INACTIVE | 5 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| category | SYS_CATEGORY_WOOD_FINISHES | Wood Finishes | — | ACTIVE | 28 | CANONICAL_ACTIVE |
| subcategory | PM_SUBCATEGORY_ce0bf39843417fca | Interior Wall Paint | PM_CATEGORY_93d0611d84196d62 | ACTIVE | 3 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED |
| subcategory | SYS_SUBCATEGORY_ADHESIVES_TILING_GROUT | Grout & Joint Fillers | SYS_CATEGORY_ADHESIVES_TILING | ACTIVE | 8 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES | Tile Adhesives | SYS_CATEGORY_ADHESIVES_TILING | ACTIVE | 8 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_ADMIXTURES_PLASTICIZERS | Plasticizers & Retarders | SYS_CATEGORY_ADMIXTURES | ACTIVE | 8 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_ADMIXTURES_WATERPROOFING | Waterproofing Admixtures | SYS_CATEGORY_ADMIXTURES | ACTIVE | 16 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS | Thinners | SYS_CATEGORY_ALLIED_PRODUCTS | ACTIVE | 6 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_ECONOMY_EXTERIOR_PAINTS | Economy Exterior Paints | SYS_CATEGORY_EXTERIOR_WALL_COATINGS | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_EMULSION | Exterior Emulsion | SYS_CATEGORY_EXTERIOR_WALL_COATINGS | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_PREMIUM_EXTERIOR_PAINTS | Premium Exterior Paints | SYS_CATEGORY_EXTERIOR_WALL_COATINGS | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_WEATHER_RESISTANT_PAINTS | Weather Resistant Paints | SYS_CATEGORY_EXTERIOR_WALL_COATINGS | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_CONCRETE_COATING | Concrete Coating | SYS_CATEGORY_FLOOR_TILE_COATINGS | ACTIVE | 21 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING | Epoxy Flooring | SYS_CATEGORY_FLOOR_TILE_COATINGS | ACTIVE | 21 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_FLOOR_PAINT | Floor Paint | SYS_CATEGORY_FLOOR_TILE_COATINGS | ACTIVE | 21 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_PAINTS | Economy Interior Paints | SYS_CATEGORY_INTERIOR_WALL_COATINGS | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_LUXURY_INTERIOR_PAINTS | Luxury Interior Paints | SYS_CATEGORY_INTERIOR_WALL_COATINGS | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ANTI_CORROSION_PAINT | Anti-Corrosion Paint | SYS_CATEGORY_METAL_WOOD_ENAMELS | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_DECORATIVE_METAL_PAINT | Decorative Metal Paint | SYS_CATEGORY_METAL_WOOD_ENAMELS | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ENAMEL_PAINT | Enamel Paint | SYS_CATEGORY_METAL_WOOD_ENAMELS | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_ANTI_CORROSION | Anti-Corrosion Coating | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_EPOXY | Epoxy Coating | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_HEAT_RESISTANT | Heat Resistant Coating | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_PROTECTIVE | Protective Coating | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY | Acrylic Putty | SYS_CATEGORY_PUTTY_SURFACE_PREPARATION | ACTIVE | 17 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY | Waterproof Wall Putty | SYS_CATEGORY_PUTTY_SURFACE_PREPARATION | ACTIVE | 17 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS | Acrylic Sealants | SYS_CATEGORY_SEALANTS_REPAIR | ACTIVE | 9 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SEALANTS_REPAIR_PU_SEALANTS | Polyurethane Sealants | SYS_CATEGORY_SEALANTS_REPAIR | ACTIVE | 9 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH | Brush | SYS_CATEGORY_ACCESSORIES | INACTIVE | 8 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_ROLLER | Roller | SYS_CATEGORY_ACCESSORIES | INACTIVE | 4 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_SANDPAPER | Sandpaper | SYS_CATEGORY_ACCESSORIES | INACTIVE | 3 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_MARBLE_STONE_FIXING | Marble & Stone Fixing | SYS_CATEGORY_ADHESIVES_TILING | ACTIVE | 13 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES | Tile Adhesives | SYS_CATEGORY_ADHESIVES_TILING | ACTIVE | 12 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_GROUTS | Tile Grouts | SYS_CATEGORY_ADHESIVES_TILING | ACTIVE | 13 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_WOODWORKING_MULTI_SURFACE_ADHESIVES | Woodworking & Multi-Surface Adhesives | SYS_CATEGORY_ADHESIVES_TILING | ACTIVE | 15 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ADMIXTURES_CONCRETE_ADMIXTURES | Concrete Admixtures | SYS_CATEGORY_ADMIXTURES | ACTIVE | 9 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ADMIXTURES_CONSTRUCTION_ADDITIVES | Construction Additives | SYS_CATEGORY_ADMIXTURES | ACTIVE | 9 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ADMIXTURES_PLASTICIZERS | Plasticizers | SYS_CATEGORY_ADMIXTURES | ACTIVE | 9 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_MISCELLANEOUS | Miscellaneous | SYS_CATEGORY_ALLIED_PRODUCTS | ACTIVE | 6 | DOMAIN_REVIEW_REQUIRED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_STAINERS | Stainers | SYS_CATEGORY_ALLIED_PRODUCTS | ACTIVE | 16 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS | Thinners | SYS_CATEGORY_ALLIED_PRODUCTS | ACTIVE | 6 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_UNIVERSAL_STAINERS | Universal Stainers | SYS_CATEGORY_ALLIED_PRODUCTS | ACTIVE | 16 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS | Automotive Coatings | SYS_CATEGORY_AUTOMOTIVE_COATINGS | ACTIVE | 29 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_KITS | DIY Kits | SYS_CATEGORY_DIY_AEROSOLS | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_STICKERS | DIY Stickers | SYS_CATEGORY_DIY_AEROSOLS | ACTIVE | 29 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_SPRAY_PAINTS | Spray Paints | SYS_CATEGORY_DIY_AEROSOLS | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_ECONOMY_EXTERIOR_EMULSIONS | Economy Exterior Emulsions | SYS_CATEGORY_EXTERIOR_WALL_COATINGS | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_SHEEN_EMULSIONS | Exterior Sheen Emulsions | SYS_CATEGORY_EXTERIOR_WALL_COATINGS | ACTIVE | 25 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_TEXTURES | Exterior Textures | SYS_CATEGORY_EXTERIOR_WALL_COATINGS | ACTIVE | 24 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_LUXURY_EXTERIOR_EMULSIONS | Luxury Exterior Emulsions | SYS_CATEGORY_EXTERIOR_WALL_COATINGS | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_PREMIUM_EXTERIOR_EMULSIONS | Premium Exterior Emulsions | SYS_CATEGORY_EXTERIOR_WALL_COATINGS | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_ROOF_EXTERIOR_COATINGS | Roof & Exterior Coatings | SYS_CATEGORY_EXTERIOR_WALL_COATINGS | ACTIVE | 25 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_SUPER_LUXURY_EXTERIOR_EMULSIONS | Super Luxury Exterior Emulsions | SYS_CATEGORY_EXTERIOR_WALL_COATINGS | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_WATERPROOF_EXTERIOR_PAINT_SYSTEMS | Waterproof Exterior Paint Systems | SYS_CATEGORY_EXTERIOR_WALL_COATINGS | ACTIVE | 25 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS | Economy Exterior Paints | SYS_CATEGORY_EXTERIOR_WALL_PAINTS | INACTIVE | 16 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_EXTERIOR_EMULSION | Exterior Emulsion | SYS_CATEGORY_EXTERIOR_WALL_PAINTS | INACTIVE | 13 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_PREMIUM_EXTERIOR_PAINTS | Premium Exterior Paints | SYS_CATEGORY_EXTERIOR_WALL_PAINTS | INACTIVE | 13 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_WEATHER_RESISTANT_PAINTS | Weather Resistant Paints | SYS_CATEGORY_EXTERIOR_WALL_PAINTS | INACTIVE | 13 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_CONCRETE_COATING | Concrete Coating | SYS_CATEGORY_FLOOR_COATINGS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_EPOXY_FLOORING | Epoxy Flooring | SYS_CATEGORY_FLOOR_COATINGS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_FLOOR_PAINT | Floor Paint | SYS_CATEGORY_FLOOR_COATINGS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING | Epoxy Flooring | SYS_CATEGORY_FLOOR_TILE_COATINGS | ACTIVE | 21 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_FLOOR_COATINGS | Floor Coatings | SYS_CATEGORY_FLOOR_TILE_COATINGS | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_ROOF_TILE_COATINGS | Roof & Tile Coatings | SYS_CATEGORY_FLOOR_TILE_COATINGS | ACTIVE | 25 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_STONE_TILE_COATINGS | Stone & Tile Coatings | SYS_CATEGORY_FLOOR_TILE_COATINGS | ACTIVE | 25 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS | Hand Sanitizers | SYS_CATEGORY_HEALTH_HYGIENE | ACTIVE | 22 | DOMAIN_REVIEW_REQUIRED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_ANTI_CORROSION_COATING | Anti-Corrosion Coating | SYS_CATEGORY_INDUSTRIAL_COATINGS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_EPOXY_COATING | Epoxy Coating | SYS_CATEGORY_INDUSTRIAL_COATINGS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_HEAT_RESISTANT_COATING | Heat Resistant Coating | SYS_CATEGORY_INDUSTRIAL_COATINGS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_PROTECTIVE_COATING | Protective Coating | SYS_CATEGORY_INDUSTRIAL_COATINGS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_ACRYLIC_PAINTS | Acrylic Paints | SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_MULTI_SURFACE_EMULSIONS | Multi-Surface Emulsions | SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_UNIVERSAL_EMULSIONS | Universal Emulsions | SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS | Ceiling Paints | SYS_CATEGORY_INTERIOR_WALL_COATINGS | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_DESIGNER_FINISHES | Designer Finishes | SYS_CATEGORY_INTERIOR_WALL_COATINGS | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_DISTEMPERS | Distempers | SYS_CATEGORY_INTERIOR_WALL_COATINGS | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_EMULSIONS | Economy Interior Emulsions | SYS_CATEGORY_INTERIOR_WALL_COATINGS | ACTIVE | 25 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_HEALTH_HYGIENE_PAINTS | Health & Hygiene Paints | SYS_CATEGORY_INTERIOR_WALL_COATINGS | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_INTERIOR_SHEEN_EMULSIONS | Interior Sheen Emulsions | SYS_CATEGORY_INTERIOR_WALL_COATINGS | ACTIVE | 26 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_KIDS_THEME_PAINTS | Kids & Theme Paints | SYS_CATEGORY_INTERIOR_WALL_COATINGS | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_LUXURY_INTERIOR_EMULSIONS | Luxury Interior Emulsions | SYS_CATEGORY_INTERIOR_WALL_COATINGS | ACTIVE | 25 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_PREMIUM_INTERIOR_EMULSIONS | Premium Interior Emulsions | SYS_CATEGORY_INTERIOR_WALL_COATINGS | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_DISTEMPER | Distemper | SYS_CATEGORY_INTERIOR_WALL_PAINTS | INACTIVE | 13 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_ECONOMY_PAINTS | Economy Paints | SYS_CATEGORY_INTERIOR_WALL_PAINTS | INACTIVE | 13 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_EMULSION_PAINTS | Emulsion Paints | SYS_CATEGORY_INTERIOR_WALL_PAINTS | INACTIVE | 13 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_LUXURY_PAINTS | Luxury Paints | SYS_CATEGORY_INTERIOR_WALL_PAINTS | INACTIVE | 13 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_PREMIUM_PAINTS | Premium Paints | SYS_CATEGORY_INTERIOR_WALL_PAINTS | INACTIVE | 13 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ANTI_CORROSION_PAINT | Anti-Corrosion Paint | SYS_CATEGORY_METAL_PAINTS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_DECORATIVE_METAL_PAINT | Decorative Metal Paint | SYS_CATEGORY_METAL_PAINTS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ENAMEL_PAINT | Enamel Paint | SYS_CATEGORY_METAL_PAINTS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_PROTECTIVE_COATING | Protective Coating | SYS_CATEGORY_METAL_PAINTS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_EPOXY_ENAMELS | Epoxy Enamels | SYS_CATEGORY_METAL_WOOD_ENAMELS | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_METALLIC_FINISHES | Metallic Finishes | SYS_CATEGORY_METAL_WOOD_ENAMELS | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_PU_ENAMELS | PU Enamels | SYS_CATEGORY_METAL_WOOD_ENAMELS | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SATIN_ENAMELS | Satin Enamels | SYS_CATEGORY_METAL_WOOD_ENAMELS | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SYNTHETIC_ENAMELS | Synthetic Enamels | SYS_CATEGORY_METAL_WOOD_ENAMELS | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_BRUSH | Brush | SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES | ACTIVE | 10 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_MASKING_TAPE | Masking Tape | SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES | ACTIVE | 11 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_PAINTING_TOOLS | Painting Tools | SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_ROLLER | Roller | SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES | ACTIVE | 7 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_SANDPAPER_ABRASIVES | Sandpaper & Abrasives | SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES | ACTIVE | 4 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PIPE_GI_COATINGS_GI_COATINGS | GI Coatings | SYS_CATEGORY_PIPE_GI_COATINGS | ACTIVE | 28 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PIPE_GI_COATINGS_PIPE_COATINGS | Pipe Coatings | SYS_CATEGORY_PIPE_GI_COATINGS | ACTIVE | 28 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_POWDER_COATINGS_POWDER_COATINGS | Powder Coatings | SYS_CATEGORY_POWDER_COATINGS | ACTIVE | 28 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_EXTERIOR_WALL_PRIMER | Exterior Wall Primer | SYS_CATEGORY_PRIMERS_PUTTY | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_INTERIOR_WALL_PRIMER | Interior Wall Primer | SYS_CATEGORY_PRIMERS_PUTTY | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WALL_PUTTY | Wall Putty | SYS_CATEGORY_PRIMERS_PUTTY | INACTIVE | 7 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WOOD_PRIMER | Wood Primer | SYS_CATEGORY_PRIMERS_PUTTY | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_ANTI_CORROSIVE_METAL_PRIMERS | Anti-Corrosive Metal Primers | SYS_CATEGORY_PRIMERS_UNDERCOATS | ACTIVE | 19 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_CEMENT_PRIMERS | Cement Primers | SYS_CATEGORY_PRIMERS_UNDERCOATS | ACTIVE | 20 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_EPOXY_PRIMERS | Epoxy Primers | SYS_CATEGORY_PRIMERS_UNDERCOATS | ACTIVE | 21 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_EXTERIOR_WALL_PRIMERS | Exterior Wall Primers | SYS_CATEGORY_PRIMERS_UNDERCOATS | ACTIVE | 19 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_GENERAL_PURPOSE_PRIMERS | General Purpose Primers | SYS_CATEGORY_PRIMERS_UNDERCOATS | ACTIVE | 20 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_INTERIOR_WALL_PRIMERS | Interior Wall Primers | SYS_CATEGORY_PRIMERS_UNDERCOATS | ACTIVE | 19 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_METAL_PRIMERS | Metal Primers | SYS_CATEGORY_PRIMERS_UNDERCOATS | ACTIVE | 19 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_SEALERS_UNDERCOATS | Sealers & Undercoats | SYS_CATEGORY_PRIMERS_UNDERCOATS | ACTIVE | 20 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_WOOD_PRIMERS | Wood Primers | SYS_CATEGORY_PRIMERS_UNDERCOATS | ACTIVE | 19 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_CAN_COATINGS | Can Coatings | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | ACTIVE | 28 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_CONCRETE_PROTECTIVE_COATINGS | Concrete Protective Coatings | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | ACTIVE | 27 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_DIRECT_TO_METAL_COATINGS | Direct-to-Metal Coatings | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | ACTIVE | 28 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_FIREPROOF_COATINGS | Fireproof Coatings | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | ACTIVE | 28 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_INDUSTRIAL_TOP_COATS | Industrial Top Coats | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | ACTIVE | 26 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_INTERMEDIATE_COATS | Intermediate Coats | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | ACTIVE | 26 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_PROTECTIVE_PRIMERS | Protective Primers | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | ACTIVE | 31 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_ROAD_MARKING_COATINGS | Road Marking Coatings | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | ACTIVE | 29 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_SPECIALITY_INDUSTRIAL_COATINGS | Speciality Industrial Coatings | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | ACTIVE | 27 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_TANK_LINERS | Tank Liners | SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS | ACTIVE | 26 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY | Acrylic Putty | SYS_CATEGORY_PUTTY_SURFACE_PREPARATION | ACTIVE | 19 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_CEMENT_PAINT | Cement Paint | SYS_CATEGORY_PUTTY_SURFACE_PREPARATION | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_CEMENT_PUTTY | Cement Putty | SYS_CATEGORY_PUTTY_SURFACE_PREPARATION | ACTIVE | 20 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_CRACK_FILLERS_REPAIR_COMPOUNDS | Crack Fillers & Repair Compounds | SYS_CATEGORY_PUTTY_SURFACE_PREPARATION | ACTIVE | 16 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_SURFACE_FILLERS | Surface Fillers | SYS_CATEGORY_PUTTY_SURFACE_PREPARATION | ACTIVE | 16 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WALL_PUTTY | Wall Putty | SYS_CATEGORY_PUTTY_SURFACE_PREPARATION | ACTIVE | 19 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY | Waterproof Wall Putty | SYS_CATEGORY_PUTTY_SURFACE_PREPARATION | ACTIVE | 19 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS | Acrylic Sealants | SYS_CATEGORY_SEALANTS_REPAIR | ACTIVE | 14 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_BITUMINOUS_COAL_TAR_SEALANTS | Bituminous & Coal Tar Sealants | SYS_CATEGORY_SEALANTS_REPAIR | ACTIVE | 13 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_JOINT_SEALANTS | Joint Sealants | SYS_CATEGORY_SEALANTS_REPAIR | ACTIVE | 15 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_POLYSULPHIDE_SEALANTS | Polysulphide Sealants | SYS_CATEGORY_SEALANTS_REPAIR | ACTIVE | 13 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_PU_SEALANTS | PU Sealants | SYS_CATEGORY_SEALANTS_REPAIR | ACTIVE | 15 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_SILICONE_SEALANTS | Silicone Sealants | SYS_CATEGORY_SEALANTS_REPAIR | ACTIVE | 14 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_DESIGNER_DECORATIVE_FINISHES | Designer & Decorative Finishes | SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_EXTERIOR_TEXTURES | Exterior Textures | SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS | ACTIVE | 23 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_GLITTER_METALLIC_ACCENTS | Glitter & Metallic Accents | SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_INTERIOR_DESIGNER_TEXTURES | Interior Designer Textures | SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_INTERIOR_TEXTURES | Interior Textures | SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_STENCILS_WALL_ART | Stencils & Wall Art | SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS | ACTIVE | 29 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_DESIGNER_WALLPAPER | Designer Wallpaper | SYS_CATEGORY_WALLPAPERS | INACTIVE | 4 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_NON_WOVEN_WALLPAPER | Non-Woven Wallpaper | SYS_CATEGORY_WALLPAPERS | INACTIVE | 4 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_PAPER_WALLPAPER | Paper Wallpaper | SYS_CATEGORY_WALLPAPERS | INACTIVE | 4 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_VINYL_WALLPAPER | Vinyl Wallpaper | SYS_CATEGORY_WALLPAPERS | INACTIVE | 4 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_COVERINGS_WALLPAPERS | Wallpapers | SYS_CATEGORY_WALL_COVERINGS | ACTIVE | 7 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_3D_TEXTURE | 3D Texture | SYS_CATEGORY_WALL_TEXTURES | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_CONCRETE_TEXTURE | Concrete Texture | SYS_CATEGORY_WALL_TEXTURES | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_DESIGNER_TEXTURE | Designer Texture | SYS_CATEGORY_WALL_TEXTURES | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_MARBLE_TEXTURE | Marble Texture | SYS_CATEGORY_WALL_TEXTURES | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_METALLIC_TEXTURE | Metallic Texture | SYS_CATEGORY_WALL_TEXTURES | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STONE_TEXTURE | Stone Texture | SYS_CATEGORY_WALL_TEXTURES | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STUCCO_TEXTURE | Stucco Texture | SYS_CATEGORY_WALL_TEXTURES | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_VELVET_TEXTURE | Velvet Texture | SYS_CATEGORY_WALL_TEXTURES | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING | Basement Waterproofing | SYS_CATEGORY_WATERPROOFING | ACTIVE | 14 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING | Bathroom & Kitchen Waterproofing | SYS_CATEGORY_WATERPROOFING | ACTIVE | 14 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_WATERPROOFING | Bathroom Waterproofing | SYS_CATEGORY_WATERPROOFING | INACTIVE | 7 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_CRACK_REPAIR | Crack Repair | SYS_CATEGORY_WATERPROOFING | INACTIVE | 7 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_DAMPNESS_EFFLORESCENCE_SEALERS | Dampness & Efflorescence Sealers | SYS_CATEGORY_WATERPROOFING | ACTIVE | 15 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_DAMP_PROOFING | Damp Proofing | SYS_CATEGORY_WATERPROOFING | INACTIVE | 7 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING | Exterior Wall Waterproofing | SYS_CATEGORY_WATERPROOFING | ACTIVE | 14 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_HEAT_REFLECTIVE_COATINGS | Heat Reflective Coatings | SYS_CATEGORY_WATERPROOFING | ACTIVE | 15 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT | Interior Dampness Treatment | SYS_CATEGORY_WATERPROOFING | ACTIVE | 14 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_LATEX_BONDING_REPAIR_ADMIXTURES | Latex Bonding & Repair Admixtures | SYS_CATEGORY_WATERPROOFING | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_NEW_CONSTRUCTION_WATERPROOFING | New Construction Waterproofing | SYS_CATEGORY_WATERPROOFING | ACTIVE | 15 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_REPAIR_CRACK_WATERPROOFING | Repair & Crack Waterproofing | SYS_CATEGORY_WATERPROOFING | ACTIVE | 15 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING | Roof & Terrace Waterproofing | SYS_CATEGORY_WATERPROOFING | ACTIVE | 14 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_TERRACE_WATERPROOFING | Terrace Waterproofing | SYS_CATEGORY_WATERPROOFING | INACTIVE | 7 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_TWO_COMPONENT_WATERPROOFING | Two-Component Waterproofing | SYS_CATEGORY_WATERPROOFING | ACTIVE | 15 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_WALL_WATERPROOFING | Wall Waterproofing | SYS_CATEGORY_WATERPROOFING | INACTIVE | 7 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_WATERPROOFING_ADDITIVES_PRIMERS | Waterproofing Additives & Primers | SYS_CATEGORY_WATERPROOFING | ACTIVE | 31 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_MELAMINE | Melamine | SYS_CATEGORY_WOOD_COATINGS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_PU_COATING | PU Coating | SYS_CATEGORY_WOOD_COATINGS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_POLISH | Wood Polish | SYS_CATEGORY_WOOD_COATINGS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_SEALER | Wood Sealer | SYS_CATEGORY_WOOD_COATINGS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_STAIN | Wood Stain | SYS_CATEGORY_WOOD_COATINGS | INACTIVE | 12 | DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, RETIRED_BUT_REFERENCED |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_ACRYLIC_WOOD_LACQUERS | Acrylic Wood Lacquers | SYS_CATEGORY_WOOD_FINISHES | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_ANTI_TERMITE_TREATMENT | Anti-Termite Treatment | SYS_CATEGORY_WOOD_FINISHES | ACTIVE | 33 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_GENERAL_WOOD_COATINGS | General Wood Coatings | SYS_CATEGORY_WOOD_FINISHES | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_LUXURY_WOOD_FINISHES | Luxury Wood Finishes | SYS_CATEGORY_WOOD_FINISHES | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_MELAMINE_WOOD_FINISHES | Melamine Wood Finishes | SYS_CATEGORY_WOOD_FINISHES | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_POLYURETHANE_VARNISHES | Polyurethane Varnishes | SYS_CATEGORY_WOOD_FINISHES | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_PU_WOOD_FINISHES | PU Wood Finishes | SYS_CATEGORY_WOOD_FINISHES | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_SEALERS | Wood Sealers | SYS_CATEGORY_WOOD_FINISHES | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_STAINS_DYES | Wood Stains & Dyes | SYS_CATEGORY_WOOD_FINISHES | ACTIVE | 24 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_VARNISHES | Wood Varnishes | SYS_CATEGORY_WOOD_FINISHES | ACTIVE | 23 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_WALL_COVERINGS_DESIGNER_WALLPAPER | Designer Wallpaper | SYS_CATEGORY_WALL_COVERINGS | ACTIVE | 7 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN | Bathroom & Kitchen Waterproofing | SYS_CATEGORY_WATERPROOFING | ACTIVE | 15 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL | Exterior Wall Waterproofing | SYS_CATEGORY_WATERPROOFING | ACTIVE | 15 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS | Interior Dampness Treatment | SYS_CATEGORY_WATERPROOFING | ACTIVE | 15 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE | Roof & Terrace Waterproofing | SYS_CATEGORY_WATERPROOFING | ACTIVE | 15 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, DUPLICATE_REFERENCED |
| subcategory | SYS_SUBCATEGORY_WOOD_FINISHES_MELAMINE | Melamine Wood Finish | SYS_CATEGORY_WOOD_FINISHES | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_WOOD_FINISHES_PU_WOOD_FINISH | PU Wood Finish | SYS_CATEGORY_WOOD_FINISHES | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_POLISH | Wood Polish | SYS_CATEGORY_WOOD_FINISHES | ACTIVE | 22 | CANONICAL_ACTIVE |
| subcategory | SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_SEALER | Wood Sealer | SYS_CATEGORY_WOOD_FINISHES | ACTIVE | 22 | CANONICAL_ACTIVE |
| unit | PM_UNIT_3871fc5bdee74d78 | L | — | ACTIVE | 2 | CANONICAL_ACTIVE, DOMAIN_REVIEW_REQUIRED, LEGACY_REFERENCED, UNIT_ALIAS |
| unit | SYS_UNIT_BAG | Bag | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_BOTTLE | Bottle | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_BOX | Box | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_BUCKET | Bucket | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_CAN | Can | — | ACTIVE | 3 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_CARTRIDGE | Cartridge | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_CM | cm | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_DRUM | Drum | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_FOOT | Foot | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_GRAM | Gram | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_INCH | inch | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_JAR | Jar | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_KILOGRAM | Kilogram | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_LITRE | Litre | — | ACTIVE | 7 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_METRE | Metre | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_MILLILITRE | Millilitre | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_MM | mm | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_PACK | Pack | — | ACTIVE | 2 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_PIECE | Piece | — | ACTIVE | 12 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_POUCH | Pouch | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_ROLL | Roll | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_SET | Set | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_SHEET | Sheet | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_SQUARE_FOOT | Square Foot | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_SQUARE_METRE | Square Metre | — | ACTIVE | 0 | CANONICAL_ACTIVE |
| unit | SYS_UNIT_TUBE | Tube | — | ACTIVE | 0 | CANONICAL_ACTIVE |

## Appendix B — Every template group

The JSON includes every template row ID and a semantic fingerprint for each group; no row was discarded during enumeration.

| Subcategory ID | Total rows | Active rows | References | Classification flags |
| --- | --- | --- | --- | --- |
| SYS_SUBCATEGORY_ADHESIVES_TILING_GROUT | 7 | 7 | 8 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES | 7 | 7 | 8 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_ADMIXTURES_PLASTICIZERS | 7 | 7 | 8 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_ADMIXTURES_WATERPROOFING | 15 | 14 | 16 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS | 5 | 5 | 6 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_ECONOMY_EXTERIOR_PAINTS | 22 | 21 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_EMULSION | 22 | 21 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_PREMIUM_EXTERIOR_PAINTS | 22 | 21 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_WEATHER_RESISTANT_PAINTS | 22 | 21 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_CONCRETE_COATING | 20 | 19 | 21 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING | 20 | 19 | 21 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_FLOOR_PAINT | 20 | 19 | 21 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS | 21 | 21 | 22 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_PAINTS | 22 | 21 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_LUXURY_INTERIOR_PAINTS | 22 | 21 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ANTI_CORROSION_PAINT | 23 | 20 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_DECORATIVE_METAL_PAINT | 21 | 20 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ENAMEL_PAINT | 21 | 20 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_ANTI_CORROSION | 21 | 19 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_EPOXY | 21 | 19 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_HEAT_RESISTANT | 21 | 19 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_PROTECTIVE | 21 | 19 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY | 16 | 10 | 17 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY | 16 | 10 | 17 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS | 8 | 7 | 9 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SEALANTS_REPAIR_PU_SEALANTS | 8 | 7 | 9 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH | 5 | 0 | 8 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_ROLLER | 4 | 0 | 4 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_SANDPAPER | 3 | 0 | 3 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_MARBLE_STONE_FIXING | 12 | 7 | 13 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES | 12 | 7 | 12 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_GROUTS | 12 | 7 | 13 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_WOODWORKING_MULTI_SURFACE_ADHESIVES | 14 | 7 | 15 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_ADMIXTURES_CONCRETE_ADMIXTURES | 8 | 7 | 9 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_ADMIXTURES_CONSTRUCTION_ADDITIVES | 8 | 7 | 9 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_ADMIXTURES_PLASTICIZERS | 8 | 7 | 9 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_MISCELLANEOUS | 6 | 5 | 6 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_STAINERS | 15 | 5 | 16 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS | 6 | 5 | 6 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_UNIVERSAL_STAINERS | 15 | 5 | 16 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS | 28 | 20 | 29 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_KITS | 23 | 2 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_STICKERS | 28 | 6 | 29 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_SPRAY_PAINTS | 23 | 19 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_ECONOMY_EXTERIOR_EMULSIONS | 23 | 21 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_SHEEN_EMULSIONS | 24 | 21 | 25 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_TEXTURES | 23 | 21 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_LUXURY_EXTERIOR_EMULSIONS | 23 | 21 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_PREMIUM_EXTERIOR_EMULSIONS | 23 | 21 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_ROOF_EXTERIOR_COATINGS | 24 | 21 | 25 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_SUPER_LUXURY_EXTERIOR_EMULSIONS | 23 | 21 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_WATERPROOF_EXTERIOR_PAINT_SYSTEMS | 24 | 21 | 25 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS | 13 | 0 | 16 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_EXTERIOR_EMULSION | 13 | 0 | 13 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_PREMIUM_EXTERIOR_PAINTS | 13 | 0 | 13 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_WEATHER_RESISTANT_PAINTS | 13 | 0 | 13 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_CONCRETE_COATING | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_EPOXY_FLOORING | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_FLOOR_PAINT | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING | 21 | 19 | 21 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_FLOOR_COATINGS | 22 | 19 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_ROOF_TILE_COATINGS | 24 | 19 | 25 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_STONE_TILE_COATINGS | 24 | 19 | 25 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS | 22 | 3 | 22 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_ANTI_CORROSION_COATING | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_EPOXY_COATING | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_HEAT_RESISTANT_COATING | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_PROTECTIVE_COATING | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_ACRYLIC_PAINTS | 22 | 21 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_MULTI_SURFACE_EMULSIONS | 23 | 21 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_UNIVERSAL_EMULSIONS | 23 | 21 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS | 22 | 18 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_DESIGNER_FINISHES | 23 | 21 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_DISTEMPERS | 23 | 21 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_EMULSIONS | 24 | 21 | 25 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_HEALTH_HYGIENE_PAINTS | 23 | 21 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_INTERIOR_SHEEN_EMULSIONS | 24 | 21 | 26 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_KIDS_THEME_PAINTS | 23 | 21 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_LUXURY_INTERIOR_EMULSIONS | 24 | 21 | 25 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_PREMIUM_INTERIOR_EMULSIONS | 24 | 21 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_DISTEMPER | 13 | 0 | 13 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_ECONOMY_PAINTS | 13 | 0 | 13 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_EMULSION_PAINTS | 13 | 0 | 13 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_LUXURY_PAINTS | 13 | 0 | 13 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_PREMIUM_PAINTS | 13 | 0 | 13 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ANTI_CORROSION_PAINT | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_DECORATIVE_METAL_PAINT | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ENAMEL_PAINT | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_PROTECTIVE_COATING | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_EPOXY_ENAMELS | 21 | 20 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_METALLIC_FINISHES | 21 | 20 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_PU_ENAMELS | 21 | 20 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SATIN_ENAMELS | 21 | 20 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SYNTHETIC_ENAMELS | 21 | 20 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_BRUSH | 10 | 8 | 10 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_MASKING_TAPE | 11 | 6 | 11 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_PAINTING_TOOLS | 23 | 2 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_ROLLER | 7 | 6 | 7 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_SANDPAPER_ABRASIVES | 4 | 3 | 4 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PIPE_GI_COATINGS_GI_COATINGS | 27 | 19 | 28 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PIPE_GI_COATINGS_PIPE_COATINGS | 27 | 19 | 28 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_POWDER_COATINGS_POWDER_COATINGS | 27 | 16 | 28 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_EXTERIOR_WALL_PRIMER | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_INTERIOR_WALL_PRIMER | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WALL_PUTTY | 7 | 0 | 7 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WOOD_PRIMER | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_ANTI_CORROSIVE_METAL_PRIMERS | 19 | 18 | 19 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_CEMENT_PRIMERS | 19 | 18 | 20 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_EPOXY_PRIMERS | 20 | 18 | 21 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_EXTERIOR_WALL_PRIMERS | 19 | 18 | 19 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_GENERAL_PURPOSE_PRIMERS | 19 | 18 | 20 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_INTERIOR_WALL_PRIMERS | 19 | 18 | 19 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_METAL_PRIMERS | 19 | 18 | 19 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_SEALERS_UNDERCOATS | 19 | 18 | 20 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_WOOD_PRIMERS | 19 | 18 | 19 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_CAN_COATINGS | 27 | 19 | 28 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_CONCRETE_PROTECTIVE_COATINGS | 26 | 19 | 27 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_DIRECT_TO_METAL_COATINGS | 27 | 19 | 28 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_FIREPROOF_COATINGS | 27 | 19 | 28 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_INDUSTRIAL_TOP_COATS | 25 | 19 | 26 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_INTERMEDIATE_COATS | 25 | 19 | 26 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_PROTECTIVE_PRIMERS | 30 | 18 | 31 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_ROAD_MARKING_COATINGS | 28 | 19 | 29 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_SPECIALITY_INDUSTRIAL_COATINGS | 26 | 19 | 27 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_TANK_LINERS | 25 | 19 | 26 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY | 19 | 10 | 19 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_CEMENT_PAINT | 23 | 10 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_CEMENT_PUTTY | 19 | 10 | 20 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_CRACK_FILLERS_REPAIR_COMPOUNDS | 15 | 10 | 16 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_SURFACE_FILLERS | 15 | 10 | 16 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WALL_PUTTY | 19 | 10 | 19 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY | 19 | 10 | 19 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS | 14 | 7 | 14 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_BITUMINOUS_COAL_TAR_SEALANTS | 12 | 7 | 13 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_JOINT_SEALANTS | 14 | 7 | 15 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_POLYSULPHIDE_SEALANTS | 12 | 7 | 13 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_PU_SEALANTS | 14 | 7 | 15 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_SILICONE_SEALANTS | 14 | 7 | 14 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_DESIGNER_DECORATIVE_FINISHES | 22 | 19 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_EXTERIOR_TEXTURES | 22 | 19 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_GLITTER_METALLIC_ACCENTS | 22 | 6 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_INTERIOR_DESIGNER_TEXTURES | 22 | 19 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_INTERIOR_TEXTURES | 22 | 19 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_STENCILS_WALL_ART | 28 | 6 | 29 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_DESIGNER_WALLPAPER | 4 | 0 | 4 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_NON_WOVEN_WALLPAPER | 4 | 0 | 4 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_PAPER_WALLPAPER | 4 | 0 | 4 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_VINYL_WALLPAPER | 4 | 0 | 4 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_COVERINGS_WALLPAPERS | 7 | 6 | 7 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_3D_TEXTURE | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_CONCRETE_TEXTURE | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_DESIGNER_TEXTURE | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_MARBLE_TEXTURE | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_METALLIC_TEXTURE | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STONE_TEXTURE | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STUCCO_TEXTURE | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_VELVET_TEXTURE | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING | 14 | 14 | 14 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING | 14 | 14 | 14 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_WATERPROOFING | 7 | 0 | 7 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_CRACK_REPAIR | 7 | 0 | 7 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_DAMPNESS_EFFLORESCENCE_SEALERS | 14 | 14 | 15 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_DAMP_PROOFING | 7 | 0 | 7 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING | 14 | 14 | 14 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_HEAT_REFLECTIVE_COATINGS | 14 | 14 | 15 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT | 14 | 14 | 14 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_LATEX_BONDING_REPAIR_ADMIXTURES | 23 | 14 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_NEW_CONSTRUCTION_WATERPROOFING | 14 | 14 | 15 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_REPAIR_CRACK_WATERPROOFING | 14 | 14 | 15 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING | 14 | 14 | 14 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_TERRACE_WATERPROOFING | 7 | 0 | 7 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_TWO_COMPONENT_WATERPROOFING | 14 | 14 | 15 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_WALL_WATERPROOFING | 7 | 0 | 7 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_WATERPROOFING_ADDITIVES_PRIMERS | 30 | 18 | 31 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_MELAMINE | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_PU_COATING | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_POLISH | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_SEALER | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_STAIN | 12 | 0 | 12 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_ACRYLIC_WOOD_LACQUERS | 22 | 20 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_ANTI_TERMITE_TREATMENT | 32 | 20 | 33 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_GENERAL_WOOD_COATINGS | 23 | 20 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_LUXURY_WOOD_FINISHES | 22 | 20 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_MELAMINE_WOOD_FINISHES | 22 | 20 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_POLYURETHANE_VARNISHES | 22 | 20 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_PU_WOOD_FINISHES | 22 | 20 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_SEALERS | 23 | 20 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_STAINS_DYES | 23 | 20 | 24 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_VARNISHES | 22 | 20 | 23 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_WALL_COVERINGS_DESIGNER_WALLPAPER | 6 | 6 | 7 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_WATERPROOFING_BASEMENT | 14 | 14 | 15 | ORPHAN_TEMPLATE_GROUP, DOMAIN_REVIEW_REQUIRED |
| SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN | 14 | 14 | 15 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL | 14 | 14 | 15 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS | 14 | 14 | 15 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE | 14 | 14 | 15 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_WOOD_FINISHES_MELAMINE | 21 | 20 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_WOOD_FINISHES_PU_WOOD_FINISH | 21 | 20 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_POLISH | 21 | 20 | 22 | CANONICAL_ACTIVE |
| SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_SEALER | 21 | 20 | 22 | CANONICAL_ACTIVE |

## Appendix C — Every Product classification reference

| Product ID | Field | Referenced ID | Exists | Product active |
| --- | --- | --- | --- | --- |
| PROD-78125CD6E1864CA1AF4E3E71C915D025 | categoryId | PM_CATEGORY_93d0611d84196d62 | True | False |
| PROD-515E99F5F2C24423B75AEBFE81CB075A | categoryId | SYS_CATEGORY_ACCESSORIES | True | True |
| PROD-6198168F50EA48BB9209914A7A2003D2 | categoryId | SYS_CATEGORY_EXTERIOR_WALL_PAINTS | True | True |
| PROD-C446FD4E4DD349DAB46DDFEDA251915D | categoryId | SYS_CATEGORY_INTERIOR_WALL_COATINGS | True | False |
| PROD-78125CD6E1864CA1AF4E3E71C915D025 | subcategoryId | PM_SUBCATEGORY_ce0bf39843417fca | True | False |
| PROD-515E99F5F2C24423B75AEBFE81CB075A | subcategoryId | SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH | True | True |
| PROD-6198168F50EA48BB9209914A7A2003D2 | subcategoryId | SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS | True | True |
| PROD-C446FD4E4DD349DAB46DDFEDA251915D | subcategoryId | SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_INTERIOR_SHEEN_EMULSIONS | True | False |

## Appendix D — Every Variant Product/unit-ID reference

| Variant ID | Field | Referenced ID | Exists | Variant active |
| --- | --- | --- | --- | --- |
| VAR-233931D4CB8A432E8F2DC88912B59C48 | productId | PROD-4B68A3FB3C10447F8A5696B17739C81F | False | True |
| VAR-42F8F567B7F54AC9A653C5826B53344B | productId | PROD-515E99F5F2C24423B75AEBFE81CB075A | True | True |
| VAR-CF94091746164266B8DA7863706991A0 | productId | PROD-515E99F5F2C24423B75AEBFE81CB075A | True | True |
| VAR-FE7BA134B0B94E058B21689F4DBB757B | productId | PROD-515E99F5F2C24423B75AEBFE81CB075A | True | True |
| VAR-808222B8F37A40138FE9416965A61F49 | productId | PROD-6198168F50EA48BB9209914A7A2003D2 | True | True |
| VAR-3F8DCEC102144603B4BFF7DF558ECFDF | productId | PROD-78125CD6E1864CA1AF4E3E71C915D025 | True | False |
| VAR-089A2A0AA0A14E45AEC89328F3A193E6 | productId | PROD-C446FD4E4DD349DAB46DDFEDA251915D | True | False |
| VAR-3F8DCEC102144603B4BFF7DF558ECFDF | baseUnitId | PM_UNIT_3871fc5bdee74d78 | True | False |
| VAR-3F8DCEC102144603B4BFF7DF558ECFDF | unitId | PM_UNIT_3871fc5bdee74d78 | True | False |
| VAR-089A2A0AA0A14E45AEC89328F3A193E6 | baseUnitId | SYS_UNIT_CAN | True | False |
| VAR-089A2A0AA0A14E45AEC89328F3A193E6 | commercialUnitId | SYS_UNIT_CAN | True | False |
| VAR-089A2A0AA0A14E45AEC89328F3A193E6 | unitId | SYS_UNIT_CAN | True | False |
| VAR-089A2A0AA0A14E45AEC89328F3A193E6 | packUnitId | SYS_UNIT_LITRE | True | False |
| VAR-233931D4CB8A432E8F2DC88912B59C48 | baseUnitId | SYS_UNIT_LITRE | True | True |
| VAR-233931D4CB8A432E8F2DC88912B59C48 | packUnitId | SYS_UNIT_LITRE | True | True |
| VAR-233931D4CB8A432E8F2DC88912B59C48 | unitId | SYS_UNIT_LITRE | True | True |
| VAR-808222B8F37A40138FE9416965A61F49 | baseUnitId | SYS_UNIT_LITRE | True | True |
| VAR-808222B8F37A40138FE9416965A61F49 | packUnitId | SYS_UNIT_LITRE | True | True |
| VAR-808222B8F37A40138FE9416965A61F49 | unitId | SYS_UNIT_LITRE | True | True |
| VAR-233931D4CB8A432E8F2DC88912B59C48 | commercialUnitId | SYS_UNIT_PACK | True | True |
| VAR-808222B8F37A40138FE9416965A61F49 | commercialUnitId | SYS_UNIT_PACK | True | True |
| VAR-42F8F567B7F54AC9A653C5826B53344B | baseUnitId | SYS_UNIT_PIECE | True | True |
| VAR-42F8F567B7F54AC9A653C5826B53344B | commercialUnitId | SYS_UNIT_PIECE | True | True |
| VAR-42F8F567B7F54AC9A653C5826B53344B | packUnitId | SYS_UNIT_PIECE | True | True |
| VAR-42F8F567B7F54AC9A653C5826B53344B | unitId | SYS_UNIT_PIECE | True | True |
| VAR-CF94091746164266B8DA7863706991A0 | baseUnitId | SYS_UNIT_PIECE | True | True |
| VAR-CF94091746164266B8DA7863706991A0 | commercialUnitId | SYS_UNIT_PIECE | True | True |
| VAR-CF94091746164266B8DA7863706991A0 | packUnitId | SYS_UNIT_PIECE | True | True |
| VAR-CF94091746164266B8DA7863706991A0 | unitId | SYS_UNIT_PIECE | True | True |
| VAR-FE7BA134B0B94E058B21689F4DBB757B | baseUnitId | SYS_UNIT_PIECE | True | True |
| VAR-FE7BA134B0B94E058B21689F4DBB757B | commercialUnitId | SYS_UNIT_PIECE | True | True |
| VAR-FE7BA134B0B94E058B21689F4DBB757B | packUnitId | SYS_UNIT_PIECE | True | True |
| VAR-FE7BA134B0B94E058B21689F4DBB757B | unitId | SYS_UNIT_PIECE | True | True |

## Appendix E — Scanned table counts

| Table | Rows |
| --- | --- |
| local_app_config | 0 |
| local_brands | 10 |
| local_business_name_reservations | 0 |
| local_business_sub_types | 7 |
| local_business_types | 6 |
| local_businesses | 5 |
| local_customers | 0 |
| local_document_sequences | 5 |
| local_employees | 4 |
| local_godown_code_reservations | 1 |
| local_godowns | 0 |
| local_goods_receipt_items | 0 |
| local_goods_receipts | 0 |
| local_hsn_codes | 0 |
| local_inventory_transactions | 0 |
| local_invoices | 0 |
| local_outlets | 7 |
| local_pack_sizes | 0 |
| local_payment_allocations | 0 |
| local_permissions | 64 |
| local_product_attribute_options | 221 |
| local_product_attributes | 50 |
| local_product_catalogue_releases | 1 |
| local_product_categories | 34 |
| local_product_classification_options | 0 |
| local_product_subcategories | 198 |
| local_product_unique_keys | 4 |
| local_product_variants | 7 |
| local_products | 4 |
| local_purchase_bills | 0 |
| local_purchase_order_items | 0 |
| local_purchase_orders | 0 |
| local_purchase_returns | 0 |
| local_purchases | 0 |
| local_racks | 0 |
| local_roles | 10 |
| local_shades | 0 |
| local_shelves | 0 |
| local_stock_balances | 0 |
| local_storage_locations | 0 |
| local_subcategory_attribute_templates | 3377 |
| local_supplier_balances | 1 |
| local_supplier_businesses | 1 |
| local_supplier_credits | 0 |
| local_supplier_ledger_entries | 0 |
| local_supplier_payments | 0 |
| local_supplier_products | 0 |
| local_suppliers | 1 |
| local_units | 27 |
| local_user | 2 |
| sync_conflicts | 0 |
| sync_outbox | 0 |
| sync_queries | 195 |

Phase 8 analysis and isolated proof are complete. All unresolved semantic cases remain available for review, all live execution approvals remain false, production data is unchanged, and Phase 9 has not begun.
