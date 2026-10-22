# Phase 10B — Unit contract and catalogue intent normalization

**Status: Phase 10B implementation and isolated proof complete; ready for review.** Catalogue content and migration approvals remain pending. No final corrected successor release was generated or installed. No production catalogue flag, duplicate identity, template group, Product, Variant, SKU, barcode or historical reference was changed.

Branch: `fix/product-master-audit`. Preflight working tree was clean. Committed Phase 10A HEAD: `5ef897fabda99e60a5801cd6a5159775d682c520`. Baseline workspace: **268/268 tests passed**. All production inspection uses existing read-only audit helpers (`mode=ro`/readOnly and `PRAGMA query_only=ON`), plus file-byte hashing. No writable production bootstrap, app launch, seed, migration or live client was used.

## Resolved unit contract

Before: `allowedBaseUnits` inherited all 27 global unit names and `conversionAllowed=true` regardless of profile. After: `ProductUnitContract` decodes explicit subcategory `unitRules`, or nested profile rules, into the one `ResolvedUnitRule` consumed by the form and validator. Global unit masters supply ID/name and dimension lookup only.

The resolved fields are `allowedPackUnits`, `defaultPackUnit`, `allowedBaseUnits`, `defaultBaseUnit`, `allowedSellingUnits`, `defaultSellingUnit`, `conversionAllowed`, `conversionDimension`, and `conversionRequiresExplicitFactor`. Legacy sold-as property names remain compatibility aliases. Unit IDs and their own display names reconcile locally; unit codes such as legacy `L` are not treated as approved canonical aliases.

Missing explicit rules emit `UNIT_CONTRACT_MISSING`, expose only authored profile/template pack/selling lists, return no base-unit fallback, and disable conversion. Explicit empty template options do not inherit global attribute options. Conflicting profile/template lists expose only their explicit intersection with a review diagnostic. No first-global-option default is selected.

Invalid explicit contracts fail closed with `DOMAIN_REVIEW_REQUIRED`/ERROR and invalid resolver readiness: unknown unit targets, invalid defaults/types, mixed base dimensions, container measurement bases, unsupported dimensions, or conversion without an explicit measurement base/factor. Packaged conversion additionally requires exact positive finite `measurementContent.amount` and compatible `measurementContent.unit` metadata. Containers do not determine a measurement base. Conversion starts OFF; pack size never supplies a conversion factor automatically.

Existing converted Edit state without a compatible contract is retained for review rather than silently reset. Validator blocks an invalid save; no existing persisted quantities or unit references are rewritten by this resolution change. With conversion OFF, the existing stock representation `baseUnitId == commercialUnitId`, factor 1, is preserved and is not classified as measurement conversion.

## Intended family rules

These are review contracts derived from explicit category/subcategory IDs and Phase 10A profile evidence. They are not installed metadata. Selling/presentation sets remain per-profile, separate from measurement bases. No widget uses category-name heuristics.

| Family | Candidate count | Pack/base contract | Conversion eligibility |
| --- | ---: | --- | --- |
| ADHESIVE | 5 | Evidence-supported Kilogram/Gram only; default Kilogram | Disabled by default |
| ADMIXTURE | 5 | Litre/Millilitre; default Litre; VOLUME | Allowed, explicit factor |
| VOLUME_COATING | 88 | Litre/Millilitre; default Litre; VOLUME | Allowed, explicit factor |
| POWDER | 8 | Kilogram/Gram; default Kilogram; MASS | Allowed, explicit factor |
| SEALANT | 7 | Explicit profile presentation/pack choices; no measurement base | Disabled without exact content |
| DIY_PRESENTATION | 3 | Explicit Piece/Sheet/Set profile choices; no measurement base | Disabled |
| SPRAY_AEROSOL | 1 | Explicit profile pack choices; Can is selling/presentation, no measurement base | Disabled |
| TOOLS | 3 | Piece | Disabled |
| MASKING_TAPE | 1 | Roll | Disabled |
| SANDPAPER | 1 | Sheet | Disabled |
| WALL_COVERING | 2 | Roll | Disabled |
| WATERPROOFING | 12 | Exactly one profile-supported mass or volume set; ambiguous Basement returns no set | Disabled by default |

**Intended canonical model: 136 candidates, 101 conversion-eligible and 35 conversion-disabled. Every new form starts with conversion OFF.** The 101 comprise 88 coating/primer/enamel/wood/industrial profiles, 8 putty/powder profiles and 5 admixtures. These counts do not describe a new installed release or 136 runtime selectable forms.

### Remaining unit decisions

Ten candidates carry explicit unit review questions. Basement is deliberately blocked: its profile does not establish one material dimension. The other nine have restricted sets but no evidence-supported selling-unit default; that default remains null rather than invented. Presentation/content quantities for sealants and aerosols remain unapproved, and conversion stays disabled.

| Exact candidate ID | Name | Required review |
| --- | --- | --- |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING` | Basement Waterproofing | DOMAIN_REVIEW_REQUIRED: select one supported material dimension; installed profile mixes or omits dimensions |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_DAMPNESS_EFFLORESCENCE_SEALERS` | Dampness & Efflorescence Sealers | DOMAIN_REVIEW_REQUIRED: choose an explicit selling-unit default |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_HEAT_REFLECTIVE_COATINGS` | Heat Reflective Coatings | DOMAIN_REVIEW_REQUIRED: choose an explicit selling-unit default |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_NEW_CONSTRUCTION_WATERPROOFING` | New Construction Waterproofing | DOMAIN_REVIEW_REQUIRED: choose an explicit selling-unit default |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_REPAIR_CRACK_WATERPROOFING` | Repair & Crack Waterproofing | DOMAIN_REVIEW_REQUIRED: choose an explicit selling-unit default |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_TWO_COMPONENT_WATERPROOFING` | Two-Component Waterproofing | DOMAIN_REVIEW_REQUIRED: choose an explicit selling-unit default |
| `SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN` | Bathroom & Kitchen Waterproofing | DOMAIN_REVIEW_REQUIRED: choose an explicit selling-unit default |
| `SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL` | Exterior Wall Waterproofing | DOMAIN_REVIEW_REQUIRED: choose an explicit selling-unit default |
| `SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS` | Interior Dampness Treatment | DOMAIN_REVIEW_REQUIRED: choose an explicit selling-unit default |
| `SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE` | Roof & Terrace Waterproofing | DOMAIN_REVIEW_REQUIRED: choose an explicit selling-unit default |

## Selector intent and content definitions

The separate [intended-catalogue manifest](docs/phase10b-intended-catalogue.json) accounts for all 149 active records. It contains 136 `SELECTABLE_PENDING_CONTENT_VALIDATION` candidates, 10 separate legacy duplicate review entries, 2 exclusions, and 1 disabled/review entry. All **87 probable schema-residue records** are pending-selectable in this model, retain their installed `templateSelectable=false` evidence, and retain `approved=false`.

Miscellaneous remains disabled/review-required; Hand Sanitizers and historical Paint → Interior Wall Paint remain excluded. No production selectability flag changes. The historical Phase 10A audit JSON remains unchanged. Its runtime evidence comparison now excludes only the evolving derived unit rules/diagnostics; decoded records, identities, selector eligibility, counts, attributes and original metadata remain checked.

Every canonical candidate records allowed attributes, PRODUCT/VARIANT levels, requiredness, options, defaults, conditions, units and intended selectability. Non-unit content is a pending contract based on Phase 10A evidence, not a declaration that all existing content defects have been corrected. Domain-specific attribute/default/option corrections and full-content approval belong to subsequent reviewed Phase 10 work.

Artifact kind: `CATALOGUE_INTENT_REVIEW_ONLY`; `importable=false`, `approvedForLiveExecution=false`, no release marker/version. Identical evidence produces identical artifact content; reordered input produces identical logical records, candidate contracts, reviews and fingerprint. Exact source ordering is separately recorded in the evidence fingerprint.

Logical intent fingerprint: `8d1225c14759a558e4644a1548dc71ad1ce747a21d53e08d689c20464bd6747c`.

## Duplicate review manifest

All ten Phase 10A compiler-preferred candidates are modeled prospectively. Every review includes exact canonical/legacy IDs, semantic conflict paths, the recommended pending contract and a domain question. Both `approved` and `migrationApproved` remain false. Legacy candidates are excluded from canonical definitions without deleting or retiring their production records. Requiredness/default/options/placement and material/presentation conflicts remain domain decisions; identity preference is not semantic equivalence or migration approval.

| Group | Prospective canonical candidate | Retained legacy candidate | Approval |
| --- | --- | --- | --- |
| Tile Adhesives | `SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | false |
| Thinners | `SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS` | `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS` | false |
| Epoxy Flooring | `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | false |
| Acrylic Putty | `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | false |
| Waterproof Wall Putty | `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | false |
| Acrylic Sealants | `SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | false |
| Bathroom & Kitchen Waterproofing | `SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN` | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING` | false |
| Exterior Wall Waterproofing | `SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL` | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING` | false |
| Interior Dampness Treatment | `SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS` | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT` | false |
| Roof & Terrace Waterproofing | `SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE` | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING` | false |

## Prospective identity contracts and Epoxy Flooring

Ceiling Paints: prospective canonical ID `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS`; installed payload evidence remains `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS`.

Basement Waterproofing: prospective canonical ID `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING`; installed payload evidence remains `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT`.

The two prospective forms use the current document-ID template groups (18 Ceiling rows and 14 Basement rows), retain their authored contracts separately, and require global-definition reconciliation before content approval. Old payload-ID orphan template groups are not grafted onto the prospective definitions, rewritten or merged. Both identity and migration approvals remain false.

Epoxy Flooring candidate `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` locally allows `usage=Floor` and defaults to Floor. Other Usage option sets are not broadened. The conflicting duplicate identity and its migration remain unapproved.

## Verification

All generated candidate metadata is seeded into a fresh temporary SQLite database and decoded by the actual LocalDataSource/ProductTemplateResolver. No catalogue release marker is installed. All 136 candidates are checked: no global base list, no more than two allowed bases, only compatible physical bases when conversion is enabled, and counts 101/35. The expected blocked unit contract is Basement Waterproofing; the proof does not hide or approve it.

Validator proofs pass for ID/display-name agreement and explicit compatible conversion; reject out-of-contract pack/selling/base units, incompatible dimensions, disabled conversion, and absent/non-positive/non-finite factors. Invalid/missing contract tests verify diagnostics and no fallback. The empty authored-options regression first failed against global definition inheritance, then passed after the decoder fix.

Both shared reconciliation and actual widget flows pass all five transitions:

| Transition | Result |
| --- | --- |
| Wall Putty → Interior Wall Primer | PASS: mass → volume, conversion reset |
| Interior Paint → Brush | PASS: volume → Piece, conversion disabled |
| Litre coating → Sandpaper | PASS: volume → Sheet, conversion disabled |
| Sealant cartridge → liquid primer | PASS: presentation → volume, conversion remains initially OFF |
| Powder coating → aerosol | PASS: mass conversion cleared, Can remains presentation, conversion disabled |

Checks include restricted menus, no stale base/factor, default reconciliation, saved master-unit IDs, stock factor 1 when OFF, and unchanged variantId/SKU/barcode in the shared transition. Existing fixture updates add explicit unit contracts/master records; original colour, atomicity, identity and offline assertions remain intact. Two older unit-engine tests now invoke the actual resolved reconciliation helper instead of copying the former widget heuristic; their measurement-base assertions remain, while factor assertions now require explicit input rather than automatic pack-size copying.

Full workspace: **309/309 passed**, `flutter test --no-pub --timeout 5m --reporter expanded`. Dedicated Phase 10B plus colour/unit-engine suite: **58/58 passed** (29 unit-contract tests, 5 widget transitions, 7 manifest proofs, 10 colour checks, 7 existing unit-engine regressions). Python manifest suite: 7/7 passed and registered in the Flutter workspace suite. Existing Phase 9C read-only process/checksum/table guard completed its 120-second observation with no writer/checksum violation.

`flutter analyze`: **49 pre-existing diagnostics**, 6 warnings and 43 infos, 0 errors; baseline 53 (6 warnings, 47 infos). **0 new diagnostics**, 4 prior brace infos removed in modified files. Analyze still returns nonzero for the existing warnings; this report does not claim a diagnostic-free workspace. `git diff --check` passes.

## Production safety

Before and after capture: exact bytes, file size, mtime in nanoseconds, SHA-256 and WAL/SHM/journal presence. All three records are identical. Account/public-config audits run read-only; backup is hashed only. No production SQLite write transaction, catalogue import, sync-query change or Phase 8 migration was executed. Zero Firestore access, reads or writes; sync tests use local services/fakes only.

| Production file | Size before = after | mtimeNs before = after | SHA-256 before = after | Sidecars |
| --- | ---: | ---: | --- | --- |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db` | 9744384 | 1791112106494478057 | `76419c2ae88c03719f0965709d2e81f7cfbc65a6021278a79c93f9a14f83ee70` | none before/after |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak` | 9728000 | 1791091536646307789 | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | none before/after |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db` | 937984 | 1791111851757294196 | `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012` | none before/after |

## Files modified

- `docs/phase10b-intended-catalogue.json`
- `lib/data/models/resolved_product_template.dart`
- `lib/data/services/product_template_resolver.dart`
- `lib/data/services/product_unit_contract.dart`
- `lib/data/services/product_validator.dart`
- `lib/presentation/products/product_pages.dart`
- `phase10b.md`
- `test/catalogue_phase10a_audit_test.dart`
- `test/catalogue_phase10b_manifest_test.dart`
- `test/offline_sync_test.dart`
- `test/product_colour_condition_engine_test.dart`
- `test/product_edit_atomicity_test.dart`
- `test/product_entry_form_test.dart`
- `test/product_unit_contract_form_test.dart`
- `test/product_unit_contract_test.dart`
- `test/product_unit_engine_test.dart`
- `tool/catalogue_phase10b.py`
- `tool/tests/test_catalogue_phase10b.py`

Phase 10B stops here for review. Remaining unit/default questions, duplicate semantics and prospective identity decisions remain explicit and unapproved. No final successor release, live migration, production retirement or Phase 11 work was started.
