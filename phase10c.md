# Phase 10C — Canonical content contract correction

**Status: review-model correction and isolated verification complete. 136/136 candidates evaluated; 135 SELECTABLE_READY, one DOMAIN_REVIEW_REQUIRED.** Basement Waterproofing remains blocked on its required material/unit dimension. No live successor release or legacy migration is approved.

## Preflight and scope

Branch: `fix/product-master-audit`. Phase 10B commit: `2a94928d9703b5578d168722f8c0611c390e112c` (`fix(product-master): add explicit family unit contracts`). The working tree was clean before changes. Complete baseline workspace suite: **309/309 passed**.

Authoritative inputs are the committed [Phase 10B intended model](docs/phase10b-intended-catalogue.json), [Phase 10A decoded evidence](docs/phase10a-catalogue-audit.json), existing ProductUnitContract, ProductTemplateResolver, ProductValidator, colour conditions and placement rules. Exact category/subcategory IDs select family corrections; mutable names and insertion order do not select semantics.

All new metadata is review-only. Production account/public-config inspection uses the existing read-only audit paths (`mode=ro`/readOnly and `PRAGMA query_only=ON`), and byte hashing. Writable LocalDatabase bootstrap occurs only in freshly created temporary directories. No app was launched, live client used, Firestore accessed, installed catalogue imported, production sync query changed or Phase 8 migration executed.

## Machine artifact and accounting

The complete corrected contract is [docs/phase10c-canonical-content.json](docs/phase10c-canonical-content.json). Its generator is [tool/catalogue_phase10c.py](tool/catalogue_phase10c.py). Artifact kind: `CANONICAL_CONTENT_REVIEW_ONLY`; `importable=false`, `approvedForLiveExecution=false`, and every candidate has `migrationApproved=false`. There is no release version or installed release marker. This is not an installable successor release.

Each candidate includes canonical ID, family, intended selectability, attributes, placement, requiredness, defaults, options, conditions, unit rules, remaining domain reviews, exact source-evidence digests and field-level changes. Logical ordering and the fingerprint are deterministic. Raw source-contract digests retain authoring evidence separately; reordering the input candidates/attributes does not change logical content or its fingerprint.

Logical fingerprint: `042796faeaf023ce470428fb2403dff25bcdd332b11ad7c2e919bf368d7a52e9`.

| Accounting | Count | Result |
| --- | ---: | --- |
| Phase 10B prospective canonical candidates | 136 | Exact ID-set equality; each evaluated once |
| SELECTABLE_READY in review model | 135 | Actual resolver, selector and validator pass |
| DOMAIN_REVIEW_REQUIRED | 1 | Basement material/unit identity remains unresolved |
| Probable schema-residue candidates | 87 | All promoted only in the validated review model |
| Separate legacy duplicate records | 10 | Noncanonical, retained unchanged and unapproved |
| Miscellaneous | 1 | Disabled/review-required |
| Hand Sanitizers; historical Paint / Interior Wall Paint | 2 | Excluded |
| Total active-record intent accounting | 149 | 136 candidates plus 13 retained noncanonical records |

Installed `templateSelectable=false` evidence for the 87 records remains false in the unchanged Phase 10B source model. Temporary fixture selectability describes the review contract only; production flags are untouched.

## Correction measurements

Counts compare each candidate's corrected contract with its Phase 10B intended contract. They count per-template attribute occurrences, not unique global attribute IDs. Changes to options count option sets rather than individual option entries; placement/requiredness/default changes can overlap on the same attribute.

**133/136 templates changed** in recorded content fields. Thinners, Stainers and Universal Stainers retain their already compatible contracts. Attribute occurrences: **2,124 → 2,021**.

| Correction | Occurrences | Templates affected |
| --- | ---: | ---: |
| Attributes added | 16 | 10 |
| Attributes removed | 119 | 29 |
| Requiredness corrected | 334 | 93 |
| PRODUCT/VARIANT placement corrected | 150 | 75 |
| Field types corrected | 0 | 0 |
| Defaults corrected/cleared | 363 | 99 |
| Option sets corrected | 428 | 106 |
| Visibility conditions corrected | 464 | 93 |
| Conditional requiredness corrected | 316 | 93 |
| Explicit selling-unit defaults normalized | 9 | 9 |
| Automatic legacy default rules removed | 84 | 84 |
| Semantic roles reconciled | 176 | 101 |
| Finite option contracts made explicit | 353 | 125 |

Field types are retained where exact profile evidence supports them, including finite SELECT Product Colour sets. Unsupported raw colour default rules are replaced by explicit conditions, not by hidden inference. HSN/SAC stays a canonical Product field; Purchase Rate, Selling Price and ordinary MRP are absent from dynamic metadata. Existing canonical identity fields remain outside the dynamic attribute engine.

Finite reviewed sets explicitly use `allowAddNewOption=false` (353 attribute occurrences). This is a prospective content policy: arbitrary additions cannot bypass the reviewed option restrictions. It does not change installed BUSINESS options or authorize overwriting BUSINESS data; future custom-option behavior needs its explicit contract. Unsupported technical defaults remain unset rather than invented.

## Per-family corrected contracts

The count below includes all 136 candidates. Conversion eligibility is inherited from explicit Phase 10B unit contracts; conversion starts OFF everywhere. Pack/selling presentation is separate from measurement bases.

| Family | Candidates | Ready | Conversion eligible | Correction summary |
| --- | ---: | ---: | ---: | --- |
| ADHESIVE | 5 | 5 | 0 | Supported substrates/application and optional technical details; mass; no decorative chemistry/colour. |
| ADMIXTURE | 5 | 5 | 5 | Concrete application, supported dosage/mixing/shelf life; volume; decorative colour/finish removed. |
| ALLIED | 3 | 3 | 3 | Explicit supported allied profile fields and presentation; no coating chemistry inherited. |
| AUTOMOTIVE_COATING | 1 | 1 | 1 | Exact Metal/Plastic application; Product finish/colour and valid variant identity; volume. |
| CEILING_PAINT | 1 | 1 | 1 | Interior / Ceiling against prospective document ID; volume, supported colour identities. |
| DIY_PRESENTATION | 3 | 3 | 0 | Exact Piece/Sheet/Set profile presentation; supported design/kit/dimensions; no chemistry. |
| ENAMEL | 8 | 8 | 8 | Metal/Wood/Concrete only as exact profiles establish; Product finish/colour mode; Satin = Satin, no generic Wood/Clear/PU-Thinner default. |
| EXTERIOR_COATING | 12 | 12 | 12 | Exterior / Wall; exact Roof & Exterior profile retains supported Roof substrate; volume. |
| FLOOR_COATING | 5 | 5 | 5 | Usage option/default Floor; exact Floor/Concrete/Tile/Stone substrates retained; volume. |
| INDUSTRIAL_COATING | 13 | 13 | 13 | Exact industrial substrates, supported finish/colour, optional technical details; no invented residential usage. |
| INTERIOR_COATING | 10 | 10 | 10 | Interior / Wall; exact colour and finish options, optional coats/thinner; volume. |
| INTERIOR_EXTERIOR_COATING | 3 | 3 | 3 | Interior & Exterior; exact-profile substrates; volume. |
| MASKING_TAPE | 1 | 1 | 0 | Roll; width/length and their units at VARIANT; no chemistry; conversion disabled. |
| PIPE_GI_COATING | 2 | 2 | 2 | Exact Pipe/GI/Metal profile content; Product finish/colour, optional chemistry with no guessed thinner. |
| POWDER_COATING | 1 | 1 | 1 | Mass; Metal, optional Product finish and valid ready-colour identities; no inferred tintability. |
| PRIMER | 11 | 11 | 10 | Exact substrate/usage; no decorative finish; Fixed Colour or N/A when meaningful; explicit units. |
| PUTTY_POWDER | 7 | 7 | 7 | Mass; Wall/Concrete only per exact profile; Fixed Colour/N/A where represented, no tint/base/shade identity. |
| ROOF_TILE_COATING | 1 | 1 | 1 | Exact roof/tile profile retained (Exterior, Roof/Tile/Concrete), not category-wide Floor inference. |
| SANDPAPER | 1 | 1 | 0 | Sheet; grit at VARIANT; no chemistry; conversion disabled. |
| SEALANT | 7 | 7 | 0 | Supported application/substrate; no decorative chemistry; explicit presentation, no inferred measurement conversion. |
| SPRAY_AEROSOL | 1 | 1 | 0 | Relevant optional Product finish and colour identities; dilution/coats removed; Can presentation does not infer a base. |
| TEXTURE_COATING | 5 | 5 | 5 | Supported exact texture/finish/application; Product mode/finish, variant shade/base only under active colour mode. |
| TOOLS | 3 | 3 | 0 | Piece; brush/roller dimensions at VARIANT; supported material/type only; conversion disabled. |
| WALL_COVERING | 2 | 2 | 0 | Roll; design/pattern/dimensions only; conversion disabled. |
| WATERPROOFING | 11 | 10 | 0 | Exact application/substrate; no decorative chemistry; one material dimension per reviewed profile; Basement blocked. |
| WOOD_FINISH | 13 | 13 | 13 | Wood substrate; Product finish/colour mode; no globally selected Clear colour mode; exact profile finish values retained, uncertain thinner optional. |
| WOOD_TREATMENT | 1 | 1 | 1 | Wood / application and shelf-life only; decorative chemistry removed. |

**101 conversion-eligible / 35 conversion-disabled**, unchanged from Phase 10B. Eligible bases are compatible measurement units only, at most two per candidate. Waterproofing, adhesives, sealants and aerosols remain conversion-disabled where exact content is unavailable. With conversion OFF, the existing stock convention base = commercial unit and factor 1 represents stock identity, not container-to-measurement conversion.

Nine missing selling defaults are normalized to the **sole explicitly allowed profile selling unit**. No global first-option fallback, new pack/base choice, conversion dimension or measurement content is introduced:

| Exact canonical ID | Sole allowed selling unit = new default |
| --- | --- |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_DAMPNESS_EFFLORESCENCE_SEALERS` | Bucket |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_HEAT_REFLECTIVE_COATINGS` | Bucket |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_NEW_CONSTRUCTION_WATERPROOFING` | Bucket |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_REPAIR_CRACK_WATERPROOFING` | Bucket |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_TWO_COMPONENT_WATERPROOFING` | Set |
| `SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN` | Bag |
| `SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL` | Bucket |
| `SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS` | Bucket |
| `SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE` | Bucket |

## Colour, placement, defaults and conditions

Finish and Colour Availability (`colourType`, compatible with the existing canonical colour engine) resolve at PRODUCT. Fixed Colour activates PRODUCT Product Colour. Multiple Ready Colours activates VARIANT Shade/Colour, optional Shade Code and Colour Family. Tintable activates VARIANT Base Type and optional Base Code. Clear/Transparent, N/A and omitted colour mode hide all dependent colour/shade/base identity fields.

Colour mode is optional, not globally required. Active Fixed/Ready/Tintable modes require only the relevant identity; tests remove that identity and verify the validator rejects the incomplete form. Inactive identity fields are not required and their stale values are removed. Every offered Ready/Tintable mode has the corresponding variant attributes. Conditions explicitly use the supported PRODUCT scope and reference an authored attribute.

Brush/Roller dimensions, grit and represented SKU-defining width/length/design dimensions are VARIANT. No attribute resolves at both levels. Pack Size, Pack Unit and Selling Unit use the canonical variant field contract. All defaults are checked in authored metadata and again after actual resolution; equality proves the resolver did not quietly discard an invalid default. SELECT sets are finite/nonempty for ready candidates; MULTI_SELECT defaults are members of the exact sets.

No correction globally broadens Usage merely to validate Floor. Epoxy Flooring retains `Floor` in its own allowed set and defaults to Floor. Coats normalize to 1/2/3/4/As Required/N/A, without an unsupported universal two-coat default. Known exact-profile defaults are retained; unresolved chemistry gets neutral optional thinner choices and no thinner default.

## Before/after audit metrics

These are **intended-contract** measurements, not counts from a live catalogue import. Phase 10B had already repaired some structural problems; zero-to-zero results prove preservation rather than claim new fixes. Direct corrected resolver/validator simulation supplies the after assertions.

| Metric | Phase 10B intended model | Phase 10C review model |
| --- | ---: | ---: |
| Evaluated canonical candidates | 136 pending content validation | 136 audited |
| Minimally constructible, fully simulated ready forms | Not proven in 10B | 135 |
| Finish occurrences at VARIANT | 76 | 0 |
| Colour-mode occurrences at VARIANT | 76 | 0 |
| PRODUCT/VARIANT intersections | 0 | 0 |
| Invalid SELECT/MULTI_SELECT defaults | 0 | 0 |
| Irrelevant chemistry in noncoating templates | 2 | 0 |
| Missing sole-choice selling defaults | 9 | 0 |
| Maximum allowed measurement base list | 2 | 2 |
| Required-hidden fields in option/colour simulation | Not fully simulated | 0 |
| Unsupported conditions / missing targets | Not fully simulated | 0 |
| Duplicate option values | Not fully simulated | 0 |
| Unexplained critical/high structural defects | Not fully simulated | 0 |
| Explicit blocked required unit/material identity | Basement | Basement |

Basement's empty required pack-unit option set is an **explained blocking domain issue**, not a valid ready contract. No test declares its unit contract valid or bypasses its invalid readiness. Optional domain reviews below remain explicit; these counts do not claim final chemistry approval.

## Duplicate canonical-content decisions

All ten pairs keep `approved=false` and `migrationApproved=false`. The artifact records every Phase 10A semantic-conflict path, both side evidence digests and the corrected canonical contract digest. Tests require exact conflict-path accounting. The canonical content is corrected from its own verified profile plus Phase 10C rules; conflicting legacy rows are not unioned into it. This does not establish duplicate equivalence or approve any migration.

| Group | Prospective canonical ID | Retained legacy ID | Content decision |
| --- | --- | --- | --- |
| Tile Adhesives | `SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | Retain mass/substrate/application form and Bag presentation; finite reviewed substrate options, no paint chemistry. |
| Thinners | `SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS` | `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS` | Retain supported shelf-life/VOC and volume/Can presentation; no new chemistry assumption. |
| Epoxy Flooring | `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | Floor usage/default and exact Floor/Concrete substrate; Product mode/finish, conditional variant identity. |
| Acrylic Putty | `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | Mass / Wall / Interior, Fixed Colour or N/A, explicit White where fixed profile establishes it; no tint/shade identity. |
| Waterproof Wall Putty | `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | Mass / Wall+Concrete / Interior & Exterior; fixed-colour contract, Bag presentation. |
| Acrylic Sealants | `SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | Exact substrate and optional technical contract, Millilitre pack / Cartridge presentation; no inferred measurement base. |
| Bathroom & Kitchen Waterproofing | `SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN` | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING` | Interior / Wall+Floor, mass / Bag; decorative chemistry removed. |
| Exterior Wall Waterproofing | `SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL` | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING` | Exterior / Wall+Concrete, volume / Bucket; decorative chemistry removed. |
| Interior Dampness Treatment | `SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS` | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT` | Interior / Wall, volume / Bucket; decorative chemistry removed. |
| Roof & Terrace Waterproofing | `SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE` | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING` | Roof usage and Roof surface, volume / Bucket; decorative chemistry removed. |

## Ceiling/Basement prospective content

Ceiling Paints uses `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS`, with Interior usage, Ceiling substrate and the explicit volume contract. Its installed payload identity `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` remains unchanged. The corrected prospective form is READY and passes simulation; optional thinner evidence remains pending.

Basement uses `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING`. Its installed payload identity `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT` remains unchanged. Existing document-group substrate/application content is normalized, but the mixed/omitted material dimension blocks required Pack Unit and readiness. Conversion remains disabled, no mass/volume choice is invented, and no live approval exists.

Both contracts preserve evidence of the current document-ID template group (18 Ceiling / 14 Basement source rows). Neither old payload-ID orphan template group is grafted into the prospective contract or merged. Both identity and migration approvals remain false.

## Every remaining domain review

There are **98 field-level review entries across 85 candidates**: two blocking entries for the same Basement unit/material area, 84 optional thinner choices and 12 optional colour-mode defaults. The 96 optional entries do not block the 135 verified forms: their values/defaults remain optional/unset. No technical chemistry, brand specification or material dimension is fabricated.

### Blocking review

| Exact candidate ID / name | Field | Exact reason |
| --- | --- | --- |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING` / Basement Waterproofing | `unit` | Required unit identity cannot be resolved without exact material evidence. |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING` / Basement Waterproofing | `unitRules.materialDimension` | DOMAIN_REVIEW_REQUIRED: select one supported material dimension; installed profile mixes or omits dimensions |

### Optional chemistry reviews

For each exact candidate below, field **`dilutionType`** remains DOMAIN_REVIEW_REQUIRED with this reason: **Exact chemistry/thinner choice has no explicit default evidence; manufacturer-neutral options, optional and no default.** Current neutral choices are Manufacturer Recommended Thinner, Ready to Use, Two Component and N/A. These are choices for user-supplied product information, not inferred chemistry or a guessed default. Confirm a tighter chemistry-specific option/default contract only from explicit product/family evidence.

| Exact canonical ID | Name |
| --- | --- |
| `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_ECONOMY_EXTERIOR_PAINTS` | Economy Exterior Paints |
| `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_EMULSION` | Exterior Emulsion |
| `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_PREMIUM_EXTERIOR_PAINTS` | Premium Exterior Paints |
| `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_WEATHER_RESISTANT_PAINTS` | Weather Resistant Paints |
| `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_CONCRETE_COATING` | Concrete Coating |
| `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | Epoxy Flooring |
| `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_FLOOR_PAINT` | Floor Paint |
| `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_PAINTS` | Economy Interior Paints |
| `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_LUXURY_INTERIOR_PAINTS` | Luxury Interior Paints |
| `SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ANTI_CORROSION_PAINT` | Anti-Corrosion Paint |
| `SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_DECORATIVE_METAL_PAINT` | Decorative Metal Paint |
| `SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ENAMEL_PAINT` | Enamel Paint |
| `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_ANTI_CORROSION` | Anti-Corrosion Coating |
| `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_EPOXY` | Epoxy Coating |
| `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_HEAT_RESISTANT` | Heat Resistant Coating |
| `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_PROTECTIVE` | Protective Coating |
| `SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS` | Automotive Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_ECONOMY_EXTERIOR_EMULSIONS` | Economy Exterior Emulsions |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_SHEEN_EMULSIONS` | Exterior Sheen Emulsions |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_TEXTURES` | Exterior Textures |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_LUXURY_EXTERIOR_EMULSIONS` | Luxury Exterior Emulsions |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_PREMIUM_EXTERIOR_EMULSIONS` | Premium Exterior Emulsions |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_ROOF_EXTERIOR_COATINGS` | Roof & Exterior Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_SUPER_LUXURY_EXTERIOR_EMULSIONS` | Super Luxury Exterior Emulsions |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_WATERPROOF_EXTERIOR_PAINT_SYSTEMS` | Waterproof Exterior Paint Systems |
| `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_FLOOR_COATINGS` | Floor Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_ROOF_TILE_COATINGS` | Roof & Tile Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_STONE_TILE_COATINGS` | Stone & Tile Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_ACRYLIC_PAINTS` | Acrylic Paints |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_MULTI_SURFACE_EMULSIONS` | Multi-Surface Emulsions |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_UNIVERSAL_EMULSIONS` | Universal Emulsions |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` | Ceiling Paints |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_DESIGNER_FINISHES` | Designer Finishes |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_DISTEMPERS` | Distempers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_EMULSIONS` | Economy Interior Emulsions |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_HEALTH_HYGIENE_PAINTS` | Health & Hygiene Paints |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_INTERIOR_SHEEN_EMULSIONS` | Interior Sheen Emulsions |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_KIDS_THEME_PAINTS` | Kids & Theme Paints |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_LUXURY_INTERIOR_EMULSIONS` | Luxury Interior Emulsions |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_PREMIUM_INTERIOR_EMULSIONS` | Premium Interior Emulsions |
| `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_EPOXY_ENAMELS` | Epoxy Enamels |
| `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_METALLIC_FINISHES` | Metallic Finishes |
| `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_PU_ENAMELS` | PU Enamels |
| `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SATIN_ENAMELS` | Satin Enamels |
| `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SYNTHETIC_ENAMELS` | Synthetic Enamels |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PIPE_GI_COATINGS_GI_COATINGS` | GI Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PIPE_GI_COATINGS_PIPE_COATINGS` | Pipe Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_ANTI_CORROSIVE_METAL_PRIMERS` | Anti-Corrosive Metal Primers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_CEMENT_PRIMERS` | Cement Primers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_EPOXY_PRIMERS` | Epoxy Primers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_EXTERIOR_WALL_PRIMERS` | Exterior Wall Primers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_GENERAL_PURPOSE_PRIMERS` | General Purpose Primers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_INTERIOR_WALL_PRIMERS` | Interior Wall Primers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_METAL_PRIMERS` | Metal Primers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_SEALERS_UNDERCOATS` | Sealers & Undercoats |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_WOOD_PRIMERS` | Wood Primers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_CAN_COATINGS` | Can Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_CONCRETE_PROTECTIVE_COATINGS` | Concrete Protective Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_DIRECT_TO_METAL_COATINGS` | Direct-to-Metal Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_FIREPROOF_COATINGS` | Fireproof Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_INDUSTRIAL_TOP_COATS` | Industrial Top Coats |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_INTERMEDIATE_COATS` | Intermediate Coats |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_PROTECTIVE_PRIMERS` | Protective Primers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_ROAD_MARKING_COATINGS` | Road Marking Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_SPECIALITY_INDUSTRIAL_COATINGS` | Speciality Industrial Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_TANK_LINERS` | Tank Liners |
| `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_DESIGNER_DECORATIVE_FINISHES` | Designer & Decorative Finishes |
| `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_EXTERIOR_TEXTURES` | Exterior Textures |
| `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_INTERIOR_DESIGNER_TEXTURES` | Interior Designer Textures |
| `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_INTERIOR_TEXTURES` | Interior Textures |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_WATERPROOFING_ADDITIVES_PRIMERS` | Waterproofing Additives & Primers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_ACRYLIC_WOOD_LACQUERS` | Acrylic Wood Lacquers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_GENERAL_WOOD_COATINGS` | General Wood Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_LUXURY_WOOD_FINISHES` | Luxury Wood Finishes |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_MELAMINE_WOOD_FINISHES` | Melamine Wood Finishes |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_POLYURETHANE_VARNISHES` | Polyurethane Varnishes |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_PU_WOOD_FINISHES` | PU Wood Finishes |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_SEALERS` | Wood Sealers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_STAINS_DYES` | Wood Stains & Dyes |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_VARNISHES` | Wood Varnishes |
| `SYS_SUBCATEGORY_WOOD_FINISHES_MELAMINE` | Melamine Wood Finish |
| `SYS_SUBCATEGORY_WOOD_FINISHES_PU_WOOD_FINISH` | PU Wood Finish |
| `SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_POLISH` | Wood Polish |
| `SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_SEALER` | Wood Sealer |

### Optional colour-mode default reviews

For every candidate below, field **`colourType.defaultValue`** remains DOMAIN_REVIEW_REQUIRED with this reason: **Generic Wood/Clear default is not evidence of a fixed sellable colour mode; user chooses mode.** The unsupported default is removed. The actual colour modes and their dependent fields still pass the full option matrix; a missing optional default does not block product construction. Exact-profile finish options/defaults are retained separately; a Clear finish does not automatically select Clear colour availability.

| Exact canonical ID | Name |
| --- | --- |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_ACRYLIC_WOOD_LACQUERS` | Acrylic Wood Lacquers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_GENERAL_WOOD_COATINGS` | General Wood Coatings |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_LUXURY_WOOD_FINISHES` | Luxury Wood Finishes |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_MELAMINE_WOOD_FINISHES` | Melamine Wood Finishes |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_POLYURETHANE_VARNISHES` | Polyurethane Varnishes |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_PU_WOOD_FINISHES` | PU Wood Finishes |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_SEALERS` | Wood Sealers |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_VARNISHES` | Wood Varnishes |
| `SYS_SUBCATEGORY_WOOD_FINISHES_MELAMINE` | Melamine Wood Finish |
| `SYS_SUBCATEGORY_WOOD_FINISHES_PU_WOOD_FINISH` | PU Wood Finish |
| `SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_POLISH` | Wood Polish |
| `SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_SEALER` | Wood Sealer |

Duplicate/identity migration decisions and all Phase 8 mappings remain separate and unapproved, including those whose prospective content is now valid. Content readiness is not migration authorization.

## Actual isolated form simulation

The new fixture creates a fresh temporary SQLite LocalDatabase, seeds only reviewed catalogue metadata/unit masters, decodes through the real LocalDataSource, and resolves through the actual ProductTemplateResolver. A query-only catalogue adapter has no remote client. FirestoreRestService static field encoding is a local serialization utility; it performs no HTTP request.

**136 resolver audits pass:** 135 READY plus Basement's asserted invalid unit contract and explicit blocking reason. All **135 ready candidates** build representative blank Create states, apply defaults, fill visible required values and pass the actual ProductValidator. The complete loop exercises **4,465 SELECT option cases** including every offered colour mode; it validates hidden/effective requiredness and checks the forbidden identity group is absent. Active Fixed/Ready/Tintable identity removal is rejected as missing required data.

**236 conversion cases** pass: 202 compatible-base cases across the 101 eligible candidates, plus 34 negative attempts on otherwise-ready conversion-disabled candidates. The blocked Basement candidate is checked separately as invalid rather than counted as a valid conversion form. Each eligible contract requires an explicit factor and compatible measurement dimension; no pack-size inference is used. Existing Phase 10B negative validator tests also remain passing in the full suite.

Every ready candidate is additionally valid with optional colour mode omitted. The selector's actual SQLite-decoded eligible ID set equals the 135 reviewed READY candidates. Product/Variant tables, outbox and catalogue release markers remain empty in the new metadata fixture. This phase proves new form content construction, not a production save or legacy reference migration.

### State-leakage regressions

These are actual ProductManagementPage widget transitions with a local controller double, followed by validation of captured save fields through the actual SQLite-backed ProductValidator. They are fresh Create flows; no saved Product/Variant identity is reassigned.

| Transition | Result |
| --- | --- |
| Wall Putty → Interior Wall Primer | PASS: mass → volume pack/selling rules; incompatible conversion/base cleared; target surface defaults |
| Interior Paint → Brush | PASS: Piece defaults, conversion OFF; paint/base/shade fields removed; variant size required correctly |
| Litre coating → Sandpaper | PASS: Sheet, no conversion/chemistry; grit is VARIANT |
| Sealant cartridge → liquid primer | PASS: presentation state removed, volume defaults; no inferred factor/container base |
| Powder coating → aerosol | PASS: mass conversion cleared; aerosol presentation reconciled, conversion OFF |

Assertions cover allowed pack/selling IDs, stock base/factor when OFF, hidden stale identity removal, exact target dynamic-field set, source conversion reset, target surface defaults and valid captured form. No category-name logic was added to widgets; production UI/resolver/validator code is unchanged.

## Test and analyzer results

- Baseline complete workspace: **309/309 passed**.
- New dedicated Phase 10C suite: **151/151 passed** (136 candidate audits, one selector/accounting test, nine independent Python evidence/structure proofs registered in Flutter, five widget transitions).
- Final complete workspace: **460/460 passed**, including existing identity/atomicity, compiler/import/sync, colour/unit/placement/selector and validator regressions.
- `flutter analyze --no-pub`: **49 existing diagnostics**, 6 warnings and 43 infos, 0 errors. Baseline also 49; normalized severity/message/file/code comparison shows **0 new / 0 removed**. Exit 1 reflects the unchanged existing baseline.
- Dart formatter reports no outstanding changes. `git diff --check` passes.

Commands:

```sh
flutter test --no-pub --timeout 5m --reporter expanded
flutter test --no-pub --timeout 5m --reporter expanded test/catalogue_phase10c_content_test.dart test/catalogue_phase10c_state_test.dart
flutter analyze --no-pub
python3 -B -m unittest tool.tests.test_catalogue_phase10c
python3 tool/catalogue_phase10c.py
```

The five-minute test timeout accommodates the existing 120-second guarded observation; no guard is skipped. Final workspace elapsed time was 3m42s. Verification logs are `/private/tmp/phase10c-baseline-tests.log`, `/private/tmp/phase10c-dedicated-final.log`, `/private/tmp/phase10c-final-workspace.log`, `/private/tmp/phase10c-baseline-analyze.log` and `/private/tmp/phase10c-final-analyze.log`.

## Production safety

Before/after captures are byte hashes plus size, nanosecond mtime and WAL/SHM/journal existence. **All three capture records are identical.** Account/public-config audits remain read-only; backup is hashed only. The existing 120-second production guard passed inside the full workspace suite.

| Production file | Size before = after | mtimeNs before = after | SHA-256 before = after | Sidecars before/after |
| --- | ---: | ---: | --- | --- |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db` | 9744384 | 1791112106494478057 | `76419c2ae88c03719f0965709d2e81f7cfbc65a6021278a79c93f9a14f83ee70` | none / none |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak` | 9728000 | 1791091536646307789 | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | none / none |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db` | 937984 | 1791111851757294196 | `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012` | none / none |

Capture files: `/private/tmp/phase10c-before.json` and `/private/tmp/phase10c-after.json`. Comparison asserts full record equality, not merely a matching shortened hash.

**Zero production SQLite writes; zero Firestore access, reads or writes.** No production Product/Variant/SKU/barcode identity, historical reference, catalogue flag, row or sync query changed. No live import, release publication, duplicate retirement, Phase 8 mapping execution or Phase 11 work occurred.

## Exact files added

- `docs/phase10c-canonical-content.json` — complete non-importable content review and evidence.
- `tool/catalogue_phase10c.py` — deterministic canonical-content review builder.
- `tool/tests/test_catalogue_phase10c.py` — nine independent structural/evidence proofs.
- `test/support/phase10c_model.dart` — isolated SQLite fixture and representative form builder.
- `test/catalogue_phase10c_content_test.dart` — all-candidate resolver/selector/validator/options/conversion proofs.
- `test/catalogue_phase10c_state_test.dart` — five real form transitions.
- `phase10c.md` — this report.

No tracked pre-existing file, archived Phase 10A/B artifact or production Dart source was modified. Changes remain uncommitted for review.

## Review decision

Phase 10C's review-only correction and verification are complete. **135 candidates are eligible in the validated review model; Basement requires a material/unit decision before it can become READY.** Optional evidence questions are listed above, all migration/live approvals remain false, and no final live successor release has been generated or installed. Stop here for review.
