# Phase 10A — Catalogue intent and duplicate disposition

Status: decision-support audit complete; catalogue intent is not yet domain-approved. No correction, successor release, retirement, migration or mapping approval was performed. Phase 10 content correction remains gated by the decisions listed below.

Branch: `fix/product-master-audit`. Preflight HEAD: `e284f4010694144f873bf80dda309ed065488fe3` (`audit(product-master): record phase 10 catalogue blockers`), which commits the Phase 10 stopped report. Working tree was clean before this audit. Phase 9D is committed at `320f4a56b1f93392817facfbaababf3332f2f857`.

All account/public-config inspections used SQLite `mode=ro` or `OpenDatabaseOptions(readOnly: true)` and `PRAGMA query_only=ON`; no writable bootstrap or application was launched. Backup was hashed only. There were zero production SQLite writes and zero Firestore reads/writes. The synthetic mutation-rejection test attempts an INSERT only on its own temporary database.

## Corrected selector truth

The historical assertion of 147 selectable records was invalid. The test inspected `dataJson` (not this schema's `payloadJson`) and fell back to denormalized SQL columns. Those columns do not contain the decoded names, `templateSelectable`, `templateStatus` or profiles. It supplied row IDs as display names, losing same-parent name equivalence, and ignored 88 explicit disabled flags. Counting 149 minus the missing-template and excluded records therefore did not represent runtime selection.

The repaired test constructs the real `LocalDataSource`, invokes its payload-decoding query path, and runs `ProductTemplateResolver` and `CatalogueSelectionResolver`. Runtime chooses the payload subcategory ID; the audit retains document ID separately. It independently derives the expected parent/name selector set from eligibility results and compares it to actual selector output. Neither 59 nor 49 is hardcoded in the assertions. The saved evidence is also checked against every current runtime-decoded record.

Current installed catalogue is `PAINT_V1`, data version 3, stored metadata revision 5. No release was generated or imported in Phase 10A.

| Measure | Observed count |
| --- | --- |
| Active subcategory rows | 149 |
| Individually eligible records | 59 |
| Selectable selector entries after same-parent name dedupe | 49 |
| Eligible categories | 15 |
| Explicit templateSelectable=false records | 88 |
| Active same-parent duplicate groups | 10 |
| Document/payload mismatch rows | 2 |

The 59 eligible rows include both members of all ten duplicate pairs and both identity-mismatch rows. Deduplication hides ten eligible rows; it does not resolve their semantics. The selector currently exposes the two payload identities. Eligibility and audit disposition are separate facts: duplicate/mismatched eligible rows remain review cases. Resolver READY alone is insufficient because selector flags can still exclude a record.

| Exactly-one classification | Count |
| --- | --- |
| SELECTABLE_READY | 37 |
| INTENTIONALLY_DISABLED | 0 |
| MISSING_TEMPLATE | 1 |
| BUSINESS_SCOPE_EXCLUDED | 1 |
| UNAVAILABLE | 1 |
| DUPLICATE_REVIEW | 20 |
| IDENTITY_MISMATCH_REVIEW | 2 |
| OTHER_DOMAIN_REVIEW | 87 |

Classification priority is mismatch, duplicate, explicit business exclusion, missing template, unavailable metadata, disabled flag review, selectable-ready, other review. No disabling flag was treated as proof of intentional business design. All 149 document IDs appear exactly once.

## Complete per-record accounting

The linked [machine evidence](docs/phase10a-catalogue-audit.json) contains, for every row, the full decoded profile/raw fields, category identity/name, scope, raw flags/status, total/active template count, resolver readiness/diagnostics, eligibility/exclusion reason, duplicate-group key, document/payload IDs, resolved attributes/units and reference counts. `payload = document` below means exact identity agreement. Profile column shows raw profile status/revision; the complete profile is retained in JSON. Template counts are for the runtime payload ID, excluding SQL tombstones; active count is also shown.

| Category / ID | Subcategory / document ID | Payload ID | Scope; profile status/revision | Selectable flag / template status | Templates total/active | Readiness; eligible; exclusion | Classification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Paint / `PM_CATEGORY_93d0611d84196d62` | Interior Wall Paint / `PM_SUBCATEGORY_ce0bf39843417fca` | payload = document | BUSINESS; absent/absent | null / absent / null / absent | 0/0 | missingTemplate; False; missingTemplate | MISSING_TEMPLATE |
| Adhesives & Tiling / `SYS_CATEGORY_ADHESIVES_TILING` | Grout & Joint Fillers / `SYS_SUBCATEGORY_ADHESIVES_TILING_GROUT` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 7/7 | ready; True; none | SELECTABLE_READY |
| Adhesives & Tiling / `SYS_CATEGORY_ADHESIVES_TILING` | Tile Adhesives / `SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 7/7 | ready; True; none | DUPLICATE_REVIEW |
| Admixtures / `SYS_CATEGORY_ADMIXTURES` | Plasticizers & Retarders / `SYS_SUBCATEGORY_ADMIXTURES_PLASTICIZERS` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 7/7 | ready; True; none | SELECTABLE_READY |
| Admixtures / `SYS_CATEGORY_ADMIXTURES` | Waterproofing Admixtures / `SYS_SUBCATEGORY_ADMIXTURES_WATERPROOFING` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 15/14 | ready; True; none | SELECTABLE_READY |
| Allied Products / `SYS_CATEGORY_ALLIED_PRODUCTS` | Thinners / `SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 5/5 | ready; True; none | DUPLICATE_REVIEW |
| Exterior Wall Coatings / `SYS_CATEGORY_EXTERIOR_WALL_COATINGS` | Economy Exterior Paints / `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_ECONOMY_EXTERIOR_PAINTS` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 22/21 | ready; True; none | SELECTABLE_READY |
| Exterior Wall Coatings / `SYS_CATEGORY_EXTERIOR_WALL_COATINGS` | Exterior Emulsion / `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_EMULSION` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 22/21 | ready; True; none | SELECTABLE_READY |
| Exterior Wall Coatings / `SYS_CATEGORY_EXTERIOR_WALL_COATINGS` | Premium Exterior Paints / `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_PREMIUM_EXTERIOR_PAINTS` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 22/21 | ready; True; none | SELECTABLE_READY |
| Exterior Wall Coatings / `SYS_CATEGORY_EXTERIOR_WALL_COATINGS` | Weather Resistant Paints / `SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_WEATHER_RESISTANT_PAINTS` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 22/21 | ready; True; none | SELECTABLE_READY |
| Floor & Tile Coatings / `SYS_CATEGORY_FLOOR_TILE_COATINGS` | Concrete Coating / `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_CONCRETE_COATING` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 20/19 | ready; True; none | SELECTABLE_READY |
| Floor & Tile Coatings / `SYS_CATEGORY_FLOOR_TILE_COATINGS` | Epoxy Flooring / `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 20/19 | ready; True; none | DUPLICATE_REVIEW |
| Floor & Tile Coatings / `SYS_CATEGORY_FLOOR_TILE_COATINGS` | Floor Paint / `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_FLOOR_PAINT` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 20/19 | ready; True; none | SELECTABLE_READY |
| Interior Wall Coatings / `SYS_CATEGORY_INTERIOR_WALL_COATINGS` | Economy Interior Paints / `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_PAINTS` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 22/21 | ready; True; none | SELECTABLE_READY |
| Interior Wall Coatings / `SYS_CATEGORY_INTERIOR_WALL_COATINGS` | Luxury Interior Paints / `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_LUXURY_INTERIOR_PAINTS` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 22/21 | ready; True; none | SELECTABLE_READY |
| Metal & Wood Enamels / `SYS_CATEGORY_METAL_WOOD_ENAMELS` | Anti-Corrosion Paint / `SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ANTI_CORROSION_PAINT` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 23/20 | ready; True; none | SELECTABLE_READY |
| Metal & Wood Enamels / `SYS_CATEGORY_METAL_WOOD_ENAMELS` | Decorative Metal Paint / `SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_DECORATIVE_METAL_PAINT` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 21/20 | ready; True; none | SELECTABLE_READY |
| Metal & Wood Enamels / `SYS_CATEGORY_METAL_WOOD_ENAMELS` | Enamel Paint / `SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ENAMEL_PAINT` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 21/20 | ready; True; none | SELECTABLE_READY |
| Protective & Industrial Coatings / `SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS` | Anti-Corrosion Coating / `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_ANTI_CORROSION` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 21/19 | ready; True; none | SELECTABLE_READY |
| Protective & Industrial Coatings / `SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS` | Epoxy Coating / `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_EPOXY` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 21/19 | ready; True; none | SELECTABLE_READY |
| Protective & Industrial Coatings / `SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS` | Heat Resistant Coating / `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_HEAT_RESISTANT` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 21/19 | ready; True; none | SELECTABLE_READY |
| Protective & Industrial Coatings / `SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS` | Protective Coating / `SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_PROTECTIVE` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 21/19 | ready; True; none | SELECTABLE_READY |
| Putty & Surface Preparation / `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | Acrylic Putty / `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 16/10 | ready; True; none | DUPLICATE_REVIEW |
| Putty & Surface Preparation / `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | Waterproof Wall Putty / `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 16/10 | ready; True; none | DUPLICATE_REVIEW |
| Sealants & Repair / `SYS_CATEGORY_SEALANTS_REPAIR` | Acrylic Sealants / `SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 8/7 | ready; True; none | DUPLICATE_REVIEW |
| Sealants & Repair / `SYS_CATEGORY_SEALANTS_REPAIR` | Polyurethane Sealants / `SYS_SUBCATEGORY_SEALANTS_REPAIR_PU_SEALANTS` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 8/7 | ready; True; none | SELECTABLE_READY |
| Adhesives & Tiling / `SYS_CATEGORY_ADHESIVES_TILING` | Marble & Stone Fixing / `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_MARBLE_STONE_FIXING` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 12/7 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Adhesives & Tiling / `SYS_CATEGORY_ADHESIVES_TILING` | Tile Adhesives / `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 12/7 | ready; True; none | DUPLICATE_REVIEW |
| Adhesives & Tiling / `SYS_CATEGORY_ADHESIVES_TILING` | Tile Grouts / `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_GROUTS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 12/7 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Adhesives & Tiling / `SYS_CATEGORY_ADHESIVES_TILING` | Woodworking & Multi-Surface Adhesives / `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_WOODWORKING_MULTI_SURFACE_ADHESIVES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 14/7 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Admixtures / `SYS_CATEGORY_ADMIXTURES` | Concrete Admixtures / `SYS_SUBCATEGORY_SYS_CATEGORY_ADMIXTURES_CONCRETE_ADMIXTURES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 8/7 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Admixtures / `SYS_CATEGORY_ADMIXTURES` | Construction Additives / `SYS_SUBCATEGORY_SYS_CATEGORY_ADMIXTURES_CONSTRUCTION_ADDITIVES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 8/7 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Admixtures / `SYS_CATEGORY_ADMIXTURES` | Plasticizers / `SYS_SUBCATEGORY_SYS_CATEGORY_ADMIXTURES_PLASTICIZERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 8/7 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Allied Products / `SYS_CATEGORY_ALLIED_PRODUCTS` | Miscellaneous / `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_MISCELLANEOUS` | payload = document | SYSTEM; absent/absent | false / UNAVAILABLE | 6/5 | ready; False; notTemplateSelectable | UNAVAILABLE |
| Allied Products / `SYS_CATEGORY_ALLIED_PRODUCTS` | Stainers / `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_STAINERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 15/5 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Allied Products / `SYS_CATEGORY_ALLIED_PRODUCTS` | Thinners / `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 6/5 | ready; True; none | DUPLICATE_REVIEW |
| Allied Products / `SYS_CATEGORY_ALLIED_PRODUCTS` | Universal Stainers / `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_UNIVERSAL_STAINERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 15/5 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Automotive Coatings / `SYS_CATEGORY_AUTOMOTIVE_COATINGS` | Automotive Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 28/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| DIY & Aerosols / `SYS_CATEGORY_DIY_AEROSOLS` | DIY Kits / `SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_KITS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/2 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| DIY & Aerosols / `SYS_CATEGORY_DIY_AEROSOLS` | DIY Stickers / `SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_STICKERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 28/6 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| DIY & Aerosols / `SYS_CATEGORY_DIY_AEROSOLS` | Spray Paints / `SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_SPRAY_PAINTS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Exterior Wall Coatings / `SYS_CATEGORY_EXTERIOR_WALL_COATINGS` | Economy Exterior Emulsions / `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_ECONOMY_EXTERIOR_EMULSIONS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Exterior Wall Coatings / `SYS_CATEGORY_EXTERIOR_WALL_COATINGS` | Exterior Sheen Emulsions / `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_SHEEN_EMULSIONS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 24/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Exterior Wall Coatings / `SYS_CATEGORY_EXTERIOR_WALL_COATINGS` | Exterior Textures / `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_TEXTURES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Exterior Wall Coatings / `SYS_CATEGORY_EXTERIOR_WALL_COATINGS` | Luxury Exterior Emulsions / `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_LUXURY_EXTERIOR_EMULSIONS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Exterior Wall Coatings / `SYS_CATEGORY_EXTERIOR_WALL_COATINGS` | Premium Exterior Emulsions / `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_PREMIUM_EXTERIOR_EMULSIONS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Exterior Wall Coatings / `SYS_CATEGORY_EXTERIOR_WALL_COATINGS` | Roof & Exterior Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_ROOF_EXTERIOR_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 24/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Exterior Wall Coatings / `SYS_CATEGORY_EXTERIOR_WALL_COATINGS` | Super Luxury Exterior Emulsions / `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_SUPER_LUXURY_EXTERIOR_EMULSIONS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Exterior Wall Coatings / `SYS_CATEGORY_EXTERIOR_WALL_COATINGS` | Waterproof Exterior Paint Systems / `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_WATERPROOF_EXTERIOR_PAINT_SYSTEMS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 24/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Floor & Tile Coatings / `SYS_CATEGORY_FLOOR_TILE_COATINGS` | Epoxy Flooring / `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 21/19 | ready; True; none | DUPLICATE_REVIEW |
| Floor & Tile Coatings / `SYS_CATEGORY_FLOOR_TILE_COATINGS` | Floor Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_FLOOR_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 22/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Floor & Tile Coatings / `SYS_CATEGORY_FLOOR_TILE_COATINGS` | Roof & Tile Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_ROOF_TILE_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 24/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Floor & Tile Coatings / `SYS_CATEGORY_FLOOR_TILE_COATINGS` | Stone & Tile Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_STONE_TILE_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 24/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Health & Hygiene / `SYS_CATEGORY_HEALTH_HYGIENE` | Hand Sanitizers / `SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS` | payload = document | SYSTEM; absent/absent | null / absent / UNAVAILABLE | 22/3 | ready; False; unavailableStatus | BUSINESS_SCOPE_EXCLUDED |
| Interior & Exterior Coatings / `SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS` | Acrylic Paints / `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_ACRYLIC_PAINTS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 22/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Interior & Exterior Coatings / `SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS` | Multi-Surface Emulsions / `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_MULTI_SURFACE_EMULSIONS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Interior & Exterior Coatings / `SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS` | Universal Emulsions / `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_UNIVERSAL_EMULSIONS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Interior Wall Coatings / `SYS_CATEGORY_INTERIOR_WALL_COATINGS` | Ceiling Paints / `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` | `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS` | SYSTEM; ACTIVE/absent | true / READY | 21/21 | ready; True; none | IDENTITY_MISMATCH_REVIEW |
| Interior Wall Coatings / `SYS_CATEGORY_INTERIOR_WALL_COATINGS` | Designer Finishes / `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_DESIGNER_FINISHES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Interior Wall Coatings / `SYS_CATEGORY_INTERIOR_WALL_COATINGS` | Distempers / `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_DISTEMPERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Interior Wall Coatings / `SYS_CATEGORY_INTERIOR_WALL_COATINGS` | Economy Interior Emulsions / `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_EMULSIONS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 24/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Interior Wall Coatings / `SYS_CATEGORY_INTERIOR_WALL_COATINGS` | Health & Hygiene Paints / `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_HEALTH_HYGIENE_PAINTS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Interior Wall Coatings / `SYS_CATEGORY_INTERIOR_WALL_COATINGS` | Interior Sheen Emulsions / `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_INTERIOR_SHEEN_EMULSIONS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 24/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Interior Wall Coatings / `SYS_CATEGORY_INTERIOR_WALL_COATINGS` | Kids & Theme Paints / `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_KIDS_THEME_PAINTS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Interior Wall Coatings / `SYS_CATEGORY_INTERIOR_WALL_COATINGS` | Luxury Interior Emulsions / `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_LUXURY_INTERIOR_EMULSIONS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 24/21 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Interior Wall Coatings / `SYS_CATEGORY_INTERIOR_WALL_COATINGS` | Premium Interior Emulsions / `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_PREMIUM_INTERIOR_EMULSIONS` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 24/21 | ready; True; none | SELECTABLE_READY |
| Metal & Wood Enamels / `SYS_CATEGORY_METAL_WOOD_ENAMELS` | Epoxy Enamels / `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_EPOXY_ENAMELS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 21/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Metal & Wood Enamels / `SYS_CATEGORY_METAL_WOOD_ENAMELS` | Metallic Finishes / `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_METALLIC_FINISHES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 21/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Metal & Wood Enamels / `SYS_CATEGORY_METAL_WOOD_ENAMELS` | PU Enamels / `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_PU_ENAMELS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 21/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Metal & Wood Enamels / `SYS_CATEGORY_METAL_WOOD_ENAMELS` | Satin Enamels / `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SATIN_ENAMELS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 21/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Metal & Wood Enamels / `SYS_CATEGORY_METAL_WOOD_ENAMELS` | Synthetic Enamels / `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SYNTHETIC_ENAMELS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 21/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Painting Tools & Accessories / `SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES` | Brush / `SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_BRUSH` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 10/8 | ready; True; none | SELECTABLE_READY |
| Painting Tools & Accessories / `SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES` | Masking Tape / `SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_MASKING_TAPE` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 11/6 | ready; True; none | SELECTABLE_READY |
| Painting Tools & Accessories / `SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES` | Painting Tools / `SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_PAINTING_TOOLS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/2 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Painting Tools & Accessories / `SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES` | Roller / `SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_ROLLER` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 7/6 | ready; True; none | SELECTABLE_READY |
| Painting Tools & Accessories / `SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES` | Sandpaper & Abrasives / `SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_SANDPAPER_ABRASIVES` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 4/3 | ready; True; none | SELECTABLE_READY |
| Pipe & GI Coatings / `SYS_CATEGORY_PIPE_GI_COATINGS` | GI Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_PIPE_GI_COATINGS_GI_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 27/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Pipe & GI Coatings / `SYS_CATEGORY_PIPE_GI_COATINGS` | Pipe Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_PIPE_GI_COATINGS_PIPE_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 27/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Powder Coatings / `SYS_CATEGORY_POWDER_COATINGS` | Powder Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_POWDER_COATINGS_POWDER_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 27/16 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Primers & Undercoats / `SYS_CATEGORY_PRIMERS_UNDERCOATS` | Anti-Corrosive Metal Primers / `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_ANTI_CORROSIVE_METAL_PRIMERS` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 19/18 | ready; True; none | SELECTABLE_READY |
| Primers & Undercoats / `SYS_CATEGORY_PRIMERS_UNDERCOATS` | Cement Primers / `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_CEMENT_PRIMERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 19/18 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Primers & Undercoats / `SYS_CATEGORY_PRIMERS_UNDERCOATS` | Epoxy Primers / `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_EPOXY_PRIMERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 20/18 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Primers & Undercoats / `SYS_CATEGORY_PRIMERS_UNDERCOATS` | Exterior Wall Primers / `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_EXTERIOR_WALL_PRIMERS` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 19/18 | ready; True; none | SELECTABLE_READY |
| Primers & Undercoats / `SYS_CATEGORY_PRIMERS_UNDERCOATS` | General Purpose Primers / `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_GENERAL_PURPOSE_PRIMERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 19/18 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Primers & Undercoats / `SYS_CATEGORY_PRIMERS_UNDERCOATS` | Interior Wall Primers / `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_INTERIOR_WALL_PRIMERS` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 19/18 | ready; True; none | SELECTABLE_READY |
| Primers & Undercoats / `SYS_CATEGORY_PRIMERS_UNDERCOATS` | Metal Primers / `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_METAL_PRIMERS` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 19/18 | ready; True; none | SELECTABLE_READY |
| Primers & Undercoats / `SYS_CATEGORY_PRIMERS_UNDERCOATS` | Sealers & Undercoats / `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_SEALERS_UNDERCOATS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 19/18 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Primers & Undercoats / `SYS_CATEGORY_PRIMERS_UNDERCOATS` | Wood Primers / `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_WOOD_PRIMERS` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 19/18 | ready; True; none | SELECTABLE_READY |
| Protective & Industrial Coatings / `SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS` | Can Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_CAN_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 27/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Protective & Industrial Coatings / `SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS` | Concrete Protective Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_CONCRETE_PROTECTIVE_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 26/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Protective & Industrial Coatings / `SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS` | Direct-to-Metal Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_DIRECT_TO_METAL_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 27/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Protective & Industrial Coatings / `SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS` | Fireproof Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_FIREPROOF_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 27/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Protective & Industrial Coatings / `SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS` | Industrial Top Coats / `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_INDUSTRIAL_TOP_COATS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 25/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Protective & Industrial Coatings / `SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS` | Intermediate Coats / `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_INTERMEDIATE_COATS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 25/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Protective & Industrial Coatings / `SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS` | Protective Primers / `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_PROTECTIVE_PRIMERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 30/18 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Protective & Industrial Coatings / `SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS` | Road Marking Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_ROAD_MARKING_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 28/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Protective & Industrial Coatings / `SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS` | Speciality Industrial Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_SPECIALITY_INDUSTRIAL_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 26/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Protective & Industrial Coatings / `SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS` | Tank Liners / `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_TANK_LINERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 25/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Putty & Surface Preparation / `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | Acrylic Putty / `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 19/10 | ready; True; none | DUPLICATE_REVIEW |
| Putty & Surface Preparation / `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | Cement Paint / `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_CEMENT_PAINT` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/10 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Putty & Surface Preparation / `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | Cement Putty / `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_CEMENT_PUTTY` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 19/10 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Putty & Surface Preparation / `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | Crack Fillers & Repair Compounds / `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_CRACK_FILLERS_REPAIR_COMPOUNDS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 15/10 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Putty & Surface Preparation / `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | Surface Fillers / `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_SURFACE_FILLERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 15/10 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Putty & Surface Preparation / `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | Wall Putty / `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WALL_PUTTY` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 19/10 | ready; True; none | SELECTABLE_READY |
| Putty & Surface Preparation / `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION` | Waterproof Wall Putty / `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 19/10 | ready; True; none | DUPLICATE_REVIEW |
| Sealants & Repair / `SYS_CATEGORY_SEALANTS_REPAIR` | Acrylic Sealants / `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 14/7 | ready; True; none | DUPLICATE_REVIEW |
| Sealants & Repair / `SYS_CATEGORY_SEALANTS_REPAIR` | Bituminous & Coal Tar Sealants / `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_BITUMINOUS_COAL_TAR_SEALANTS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 12/7 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Sealants & Repair / `SYS_CATEGORY_SEALANTS_REPAIR` | Joint Sealants / `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_JOINT_SEALANTS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 14/7 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Sealants & Repair / `SYS_CATEGORY_SEALANTS_REPAIR` | Polysulphide Sealants / `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_POLYSULPHIDE_SEALANTS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 12/7 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Sealants & Repair / `SYS_CATEGORY_SEALANTS_REPAIR` | PU Sealants / `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_PU_SEALANTS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 14/7 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Sealants & Repair / `SYS_CATEGORY_SEALANTS_REPAIR` | Silicone Sealants / `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_SILICONE_SEALANTS` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 14/7 | ready; True; none | SELECTABLE_READY |
| Textures & Special Effects / `SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS` | Designer & Decorative Finishes / `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_DESIGNER_DECORATIVE_FINISHES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 22/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Textures & Special Effects / `SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS` | Exterior Textures / `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_EXTERIOR_TEXTURES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 22/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Textures & Special Effects / `SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS` | Glitter & Metallic Accents / `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_GLITTER_METALLIC_ACCENTS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 22/6 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Textures & Special Effects / `SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS` | Interior Designer Textures / `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_INTERIOR_DESIGNER_TEXTURES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 22/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Textures & Special Effects / `SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS` | Interior Textures / `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_INTERIOR_TEXTURES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 22/19 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Textures & Special Effects / `SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS` | Stencils & Wall Art / `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_STENCILS_WALL_ART` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 28/6 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Wall Coverings / `SYS_CATEGORY_WALL_COVERINGS` | Wallpapers / `SYS_SUBCATEGORY_SYS_CATEGORY_WALL_COVERINGS_WALLPAPERS` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 7/6 | ready; True; none | SELECTABLE_READY |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Basement Waterproofing / `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING` | `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT` | SYSTEM; ACTIVE/absent | true / READY | 14/14 | ready; True; none | IDENTITY_MISMATCH_REVIEW |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Bathroom & Kitchen Waterproofing / `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 14/14 | ready; True; none | DUPLICATE_REVIEW |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Dampness & Efflorescence Sealers / `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_DAMPNESS_EFFLORESCENCE_SEALERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 14/14 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Exterior Wall Waterproofing / `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 14/14 | ready; True; none | DUPLICATE_REVIEW |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Heat Reflective Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_HEAT_REFLECTIVE_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 14/14 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Interior Dampness Treatment / `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 14/14 | ready; True; none | DUPLICATE_REVIEW |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Latex Bonding & Repair Admixtures / `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_LATEX_BONDING_REPAIR_ADMIXTURES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/14 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | New Construction Waterproofing / `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_NEW_CONSTRUCTION_WATERPROOFING` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 14/14 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Repair & Crack Waterproofing / `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_REPAIR_CRACK_WATERPROOFING` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 14/14 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Roof & Terrace Waterproofing / `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING` | payload = document | SYSTEM; ACTIVE/absent | true / READY | 14/14 | ready; True; none | DUPLICATE_REVIEW |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Two-Component Waterproofing / `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_TWO_COMPONENT_WATERPROOFING` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 14/14 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Waterproofing Additives & Primers / `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_WATERPROOFING_ADDITIVES_PRIMERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 30/18 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Wood Finishes / `SYS_CATEGORY_WOOD_FINISHES` | Acrylic Wood Lacquers / `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_ACRYLIC_WOOD_LACQUERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 22/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Wood Finishes / `SYS_CATEGORY_WOOD_FINISHES` | Anti-Termite Treatment / `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_ANTI_TERMITE_TREATMENT` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 32/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Wood Finishes / `SYS_CATEGORY_WOOD_FINISHES` | General Wood Coatings / `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_GENERAL_WOOD_COATINGS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Wood Finishes / `SYS_CATEGORY_WOOD_FINISHES` | Luxury Wood Finishes / `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_LUXURY_WOOD_FINISHES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 22/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Wood Finishes / `SYS_CATEGORY_WOOD_FINISHES` | Melamine Wood Finishes / `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_MELAMINE_WOOD_FINISHES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 22/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Wood Finishes / `SYS_CATEGORY_WOOD_FINISHES` | Polyurethane Varnishes / `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_POLYURETHANE_VARNISHES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 22/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Wood Finishes / `SYS_CATEGORY_WOOD_FINISHES` | PU Wood Finishes / `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_PU_WOOD_FINISHES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 22/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Wood Finishes / `SYS_CATEGORY_WOOD_FINISHES` | Wood Sealers / `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_SEALERS` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Wood Finishes / `SYS_CATEGORY_WOOD_FINISHES` | Wood Stains & Dyes / `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_STAINS_DYES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 23/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Wood Finishes / `SYS_CATEGORY_WOOD_FINISHES` | Wood Varnishes / `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_VARNISHES` | payload = document | SYSTEM; ACTIVE/5 | false / READY | 22/20 | ready; False; notTemplateSelectable | OTHER_DOMAIN_REVIEW |
| Wall Coverings / `SYS_CATEGORY_WALL_COVERINGS` | Designer Wallpaper / `SYS_SUBCATEGORY_WALL_COVERINGS_DESIGNER_WALLPAPER` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 6/6 | ready; True; none | SELECTABLE_READY |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Bathroom & Kitchen Waterproofing / `SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 14/14 | ready; True; none | DUPLICATE_REVIEW |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Exterior Wall Waterproofing / `SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 14/14 | ready; True; none | DUPLICATE_REVIEW |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Interior Dampness Treatment / `SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 14/14 | ready; True; none | DUPLICATE_REVIEW |
| Waterproofing / `SYS_CATEGORY_WATERPROOFING` | Roof & Terrace Waterproofing / `SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 14/14 | ready; True; none | DUPLICATE_REVIEW |
| Wood Finishes / `SYS_CATEGORY_WOOD_FINISHES` | Melamine Wood Finish / `SYS_SUBCATEGORY_WOOD_FINISHES_MELAMINE` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 21/20 | ready; True; none | SELECTABLE_READY |
| Wood Finishes / `SYS_CATEGORY_WOOD_FINISHES` | PU Wood Finish / `SYS_SUBCATEGORY_WOOD_FINISHES_PU_WOOD_FINISH` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 21/20 | ready; True; none | SELECTABLE_READY |
| Wood Finishes / `SYS_CATEGORY_WOOD_FINISHES` | Wood Polish / `SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_POLISH` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 21/20 | ready; True; none | SELECTABLE_READY |
| Wood Finishes / `SYS_CATEGORY_WOOD_FINISHES` | Wood Sealer / `SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_SEALER` | payload = document | SYSTEM; ACTIVE/5 | null / absent / READY | 21/20 | ready; True; none | SELECTABLE_READY |

## Disposition of all 88 disabled records

87 records: `PROBABLY_SHOULD_BE_SELECTABLE`, an inference requiring review, not approval. Every one has an ACTIVE revision-5 profile and raw `templateStatus=READY`, with diagnostics claiming missing `allowedSellingUnits`/`allowedOptions`/selling units. Their profiles instead contain `allowedSoldAs` and `optionsOverrides`, the vocabulary used by `_ProfileConfig` in the compiler. The resolver can construct READY templates. This is consistent with a metadata schema/validation mismatch, rather than evidence that all these product families were deliberately removed from Paint/Hardware.

Current compiler profile generation sets `templateStatus=READY` but does not establish the intended disposition of preserved `templateSelectable=false` flags. A future successor contract must explicitly reconcile these flags after content/family validation. Do not enable them merely because READY resolution succeeds.

One record, `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_MISCELLANEOUS`, has no ACTIVE profile and raw status UNAVAILABLE (`Missing ACTIVE template profile`). It has six template rows and the resolver still reports READY, illustrating why raw selector controls must also be inspected. Its disposition is `DOMAIN_REVIEW_REQUIRED`; retain disabled until its intended scope/contract is defined.

No false-flag record has an active same-parent same-name sibling in this inventory; no uniquely newer canonical sibling was proven. No inactive parent was found for these 88 rows, which does not establish that an entire legacy family was intentionally retired. No explicit domain exclusion reason is present for the 87 schema-residue cases. The only Product-referenced false record is Interior Sheen Emulsions (one saved Product); that reference must be preserved. All others have zero local Product references.

In the following table, `S` means the common schema-residue evidence above and recommendation conditional on explicit domain/content validation; `M` means the missing-profile Miscellaneous case. Each exact record has its own evidence and actual `approved=false` in JSON.

| Exact ID / name | Parent | Profile status/revision | Raw status / resolver | Templates total/active | Product refs | Disposition / evidence |
| --- | --- | --- | --- | --- | --- | --- |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_MARBLE_STONE_FIXING` / Marble & Stone Fixing | Adhesives & Tiling (`SYS_CATEGORY_ADHESIVES_TILING`) | ACTIVE/5 | READY / ready | 12/7 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_GROUTS` / Tile Grouts | Adhesives & Tiling (`SYS_CATEGORY_ADHESIVES_TILING`) | ACTIVE/5 | READY / ready | 12/7 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_WOODWORKING_MULTI_SURFACE_ADHESIVES` / Woodworking & Multi-Surface Adhesives | Adhesives & Tiling (`SYS_CATEGORY_ADHESIVES_TILING`) | ACTIVE/5 | READY / ready | 14/7 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ADMIXTURES_CONCRETE_ADMIXTURES` / Concrete Admixtures | Admixtures (`SYS_CATEGORY_ADMIXTURES`) | ACTIVE/5 | READY / ready | 8/7 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ADMIXTURES_CONSTRUCTION_ADDITIVES` / Construction Additives | Admixtures (`SYS_CATEGORY_ADMIXTURES`) | ACTIVE/5 | READY / ready | 8/7 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ADMIXTURES_PLASTICIZERS` / Plasticizers | Admixtures (`SYS_CATEGORY_ADMIXTURES`) | ACTIVE/5 | READY / ready | 8/7 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_MISCELLANEOUS` / Miscellaneous | Allied Products (`SYS_CATEGORY_ALLIED_PRODUCTS`) | absent/absent | UNAVAILABLE / ready | 6/5 | 0 | DOMAIN_REVIEW_REQUIRED / M |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_STAINERS` / Stainers | Allied Products (`SYS_CATEGORY_ALLIED_PRODUCTS`) | ACTIVE/5 | READY / ready | 15/5 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_UNIVERSAL_STAINERS` / Universal Stainers | Allied Products (`SYS_CATEGORY_ALLIED_PRODUCTS`) | ACTIVE/5 | READY / ready | 15/5 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS` / Automotive Coatings | Automotive Coatings (`SYS_CATEGORY_AUTOMOTIVE_COATINGS`) | ACTIVE/5 | READY / ready | 28/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_KITS` / DIY Kits | DIY & Aerosols (`SYS_CATEGORY_DIY_AEROSOLS`) | ACTIVE/5 | READY / ready | 23/2 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_STICKERS` / DIY Stickers | DIY & Aerosols (`SYS_CATEGORY_DIY_AEROSOLS`) | ACTIVE/5 | READY / ready | 28/6 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_SPRAY_PAINTS` / Spray Paints | DIY & Aerosols (`SYS_CATEGORY_DIY_AEROSOLS`) | ACTIVE/5 | READY / ready | 23/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_ECONOMY_EXTERIOR_EMULSIONS` / Economy Exterior Emulsions | Exterior Wall Coatings (`SYS_CATEGORY_EXTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 23/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_SHEEN_EMULSIONS` / Exterior Sheen Emulsions | Exterior Wall Coatings (`SYS_CATEGORY_EXTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 24/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_TEXTURES` / Exterior Textures | Exterior Wall Coatings (`SYS_CATEGORY_EXTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 23/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_LUXURY_EXTERIOR_EMULSIONS` / Luxury Exterior Emulsions | Exterior Wall Coatings (`SYS_CATEGORY_EXTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 23/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_PREMIUM_EXTERIOR_EMULSIONS` / Premium Exterior Emulsions | Exterior Wall Coatings (`SYS_CATEGORY_EXTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 23/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_ROOF_EXTERIOR_COATINGS` / Roof & Exterior Coatings | Exterior Wall Coatings (`SYS_CATEGORY_EXTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 24/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_SUPER_LUXURY_EXTERIOR_EMULSIONS` / Super Luxury Exterior Emulsions | Exterior Wall Coatings (`SYS_CATEGORY_EXTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 23/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_COATINGS_WATERPROOF_EXTERIOR_PAINT_SYSTEMS` / Waterproof Exterior Paint Systems | Exterior Wall Coatings (`SYS_CATEGORY_EXTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 24/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_FLOOR_COATINGS` / Floor Coatings | Floor & Tile Coatings (`SYS_CATEGORY_FLOOR_TILE_COATINGS`) | ACTIVE/5 | READY / ready | 22/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_ROOF_TILE_COATINGS` / Roof & Tile Coatings | Floor & Tile Coatings (`SYS_CATEGORY_FLOOR_TILE_COATINGS`) | ACTIVE/5 | READY / ready | 24/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_STONE_TILE_COATINGS` / Stone & Tile Coatings | Floor & Tile Coatings (`SYS_CATEGORY_FLOOR_TILE_COATINGS`) | ACTIVE/5 | READY / ready | 24/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_ACRYLIC_PAINTS` / Acrylic Paints | Interior & Exterior Coatings (`SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS`) | ACTIVE/5 | READY / ready | 22/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_MULTI_SURFACE_EMULSIONS` / Multi-Surface Emulsions | Interior & Exterior Coatings (`SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS`) | ACTIVE/5 | READY / ready | 23/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_UNIVERSAL_EMULSIONS` / Universal Emulsions | Interior & Exterior Coatings (`SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS`) | ACTIVE/5 | READY / ready | 23/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_DESIGNER_FINISHES` / Designer Finishes | Interior Wall Coatings (`SYS_CATEGORY_INTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 23/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_DISTEMPERS` / Distempers | Interior Wall Coatings (`SYS_CATEGORY_INTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 23/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_EMULSIONS` / Economy Interior Emulsions | Interior Wall Coatings (`SYS_CATEGORY_INTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 24/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_HEALTH_HYGIENE_PAINTS` / Health & Hygiene Paints | Interior Wall Coatings (`SYS_CATEGORY_INTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 23/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_INTERIOR_SHEEN_EMULSIONS` / Interior Sheen Emulsions | Interior Wall Coatings (`SYS_CATEGORY_INTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 24/21 | 1 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_KIDS_THEME_PAINTS` / Kids & Theme Paints | Interior Wall Coatings (`SYS_CATEGORY_INTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 23/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_LUXURY_INTERIOR_EMULSIONS` / Luxury Interior Emulsions | Interior Wall Coatings (`SYS_CATEGORY_INTERIOR_WALL_COATINGS`) | ACTIVE/5 | READY / ready | 24/21 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_EPOXY_ENAMELS` / Epoxy Enamels | Metal & Wood Enamels (`SYS_CATEGORY_METAL_WOOD_ENAMELS`) | ACTIVE/5 | READY / ready | 21/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_METALLIC_FINISHES` / Metallic Finishes | Metal & Wood Enamels (`SYS_CATEGORY_METAL_WOOD_ENAMELS`) | ACTIVE/5 | READY / ready | 21/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_PU_ENAMELS` / PU Enamels | Metal & Wood Enamels (`SYS_CATEGORY_METAL_WOOD_ENAMELS`) | ACTIVE/5 | READY / ready | 21/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SATIN_ENAMELS` / Satin Enamels | Metal & Wood Enamels (`SYS_CATEGORY_METAL_WOOD_ENAMELS`) | ACTIVE/5 | READY / ready | 21/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SYNTHETIC_ENAMELS` / Synthetic Enamels | Metal & Wood Enamels (`SYS_CATEGORY_METAL_WOOD_ENAMELS`) | ACTIVE/5 | READY / ready | 21/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_PAINTING_TOOLS` / Painting Tools | Painting Tools & Accessories (`SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES`) | ACTIVE/5 | READY / ready | 23/2 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PIPE_GI_COATINGS_GI_COATINGS` / GI Coatings | Pipe & GI Coatings (`SYS_CATEGORY_PIPE_GI_COATINGS`) | ACTIVE/5 | READY / ready | 27/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PIPE_GI_COATINGS_PIPE_COATINGS` / Pipe Coatings | Pipe & GI Coatings (`SYS_CATEGORY_PIPE_GI_COATINGS`) | ACTIVE/5 | READY / ready | 27/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_POWDER_COATINGS_POWDER_COATINGS` / Powder Coatings | Powder Coatings (`SYS_CATEGORY_POWDER_COATINGS`) | ACTIVE/5 | READY / ready | 27/16 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_CEMENT_PRIMERS` / Cement Primers | Primers & Undercoats (`SYS_CATEGORY_PRIMERS_UNDERCOATS`) | ACTIVE/5 | READY / ready | 19/18 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_EPOXY_PRIMERS` / Epoxy Primers | Primers & Undercoats (`SYS_CATEGORY_PRIMERS_UNDERCOATS`) | ACTIVE/5 | READY / ready | 20/18 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_GENERAL_PURPOSE_PRIMERS` / General Purpose Primers | Primers & Undercoats (`SYS_CATEGORY_PRIMERS_UNDERCOATS`) | ACTIVE/5 | READY / ready | 19/18 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_SEALERS_UNDERCOATS` / Sealers & Undercoats | Primers & Undercoats (`SYS_CATEGORY_PRIMERS_UNDERCOATS`) | ACTIVE/5 | READY / ready | 19/18 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_CAN_COATINGS` / Can Coatings | Protective & Industrial Coatings (`SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS`) | ACTIVE/5 | READY / ready | 27/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_CONCRETE_PROTECTIVE_COATINGS` / Concrete Protective Coatings | Protective & Industrial Coatings (`SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS`) | ACTIVE/5 | READY / ready | 26/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_DIRECT_TO_METAL_COATINGS` / Direct-to-Metal Coatings | Protective & Industrial Coatings (`SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS`) | ACTIVE/5 | READY / ready | 27/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_FIREPROOF_COATINGS` / Fireproof Coatings | Protective & Industrial Coatings (`SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS`) | ACTIVE/5 | READY / ready | 27/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_INDUSTRIAL_TOP_COATS` / Industrial Top Coats | Protective & Industrial Coatings (`SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS`) | ACTIVE/5 | READY / ready | 25/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_INTERMEDIATE_COATS` / Intermediate Coats | Protective & Industrial Coatings (`SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS`) | ACTIVE/5 | READY / ready | 25/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_PROTECTIVE_PRIMERS` / Protective Primers | Protective & Industrial Coatings (`SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS`) | ACTIVE/5 | READY / ready | 30/18 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_ROAD_MARKING_COATINGS` / Road Marking Coatings | Protective & Industrial Coatings (`SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS`) | ACTIVE/5 | READY / ready | 28/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_SPECIALITY_INDUSTRIAL_COATINGS` / Speciality Industrial Coatings | Protective & Industrial Coatings (`SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS`) | ACTIVE/5 | READY / ready | 26/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_TANK_LINERS` / Tank Liners | Protective & Industrial Coatings (`SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS`) | ACTIVE/5 | READY / ready | 25/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_CEMENT_PAINT` / Cement Paint | Putty & Surface Preparation (`SYS_CATEGORY_PUTTY_SURFACE_PREPARATION`) | ACTIVE/5 | READY / ready | 23/10 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_CEMENT_PUTTY` / Cement Putty | Putty & Surface Preparation (`SYS_CATEGORY_PUTTY_SURFACE_PREPARATION`) | ACTIVE/5 | READY / ready | 19/10 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_CRACK_FILLERS_REPAIR_COMPOUNDS` / Crack Fillers & Repair Compounds | Putty & Surface Preparation (`SYS_CATEGORY_PUTTY_SURFACE_PREPARATION`) | ACTIVE/5 | READY / ready | 15/10 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_SURFACE_FILLERS` / Surface Fillers | Putty & Surface Preparation (`SYS_CATEGORY_PUTTY_SURFACE_PREPARATION`) | ACTIVE/5 | READY / ready | 15/10 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_BITUMINOUS_COAL_TAR_SEALANTS` / Bituminous & Coal Tar Sealants | Sealants & Repair (`SYS_CATEGORY_SEALANTS_REPAIR`) | ACTIVE/5 | READY / ready | 12/7 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_JOINT_SEALANTS` / Joint Sealants | Sealants & Repair (`SYS_CATEGORY_SEALANTS_REPAIR`) | ACTIVE/5 | READY / ready | 14/7 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_POLYSULPHIDE_SEALANTS` / Polysulphide Sealants | Sealants & Repair (`SYS_CATEGORY_SEALANTS_REPAIR`) | ACTIVE/5 | READY / ready | 12/7 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_PU_SEALANTS` / PU Sealants | Sealants & Repair (`SYS_CATEGORY_SEALANTS_REPAIR`) | ACTIVE/5 | READY / ready | 14/7 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_DESIGNER_DECORATIVE_FINISHES` / Designer & Decorative Finishes | Textures & Special Effects (`SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS`) | ACTIVE/5 | READY / ready | 22/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_EXTERIOR_TEXTURES` / Exterior Textures | Textures & Special Effects (`SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS`) | ACTIVE/5 | READY / ready | 22/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_GLITTER_METALLIC_ACCENTS` / Glitter & Metallic Accents | Textures & Special Effects (`SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS`) | ACTIVE/5 | READY / ready | 22/6 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_INTERIOR_DESIGNER_TEXTURES` / Interior Designer Textures | Textures & Special Effects (`SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS`) | ACTIVE/5 | READY / ready | 22/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_INTERIOR_TEXTURES` / Interior Textures | Textures & Special Effects (`SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS`) | ACTIVE/5 | READY / ready | 22/19 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_STENCILS_WALL_ART` / Stencils & Wall Art | Textures & Special Effects (`SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS`) | ACTIVE/5 | READY / ready | 28/6 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_DAMPNESS_EFFLORESCENCE_SEALERS` / Dampness & Efflorescence Sealers | Waterproofing (`SYS_CATEGORY_WATERPROOFING`) | ACTIVE/5 | READY / ready | 14/14 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_HEAT_REFLECTIVE_COATINGS` / Heat Reflective Coatings | Waterproofing (`SYS_CATEGORY_WATERPROOFING`) | ACTIVE/5 | READY / ready | 14/14 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_LATEX_BONDING_REPAIR_ADMIXTURES` / Latex Bonding & Repair Admixtures | Waterproofing (`SYS_CATEGORY_WATERPROOFING`) | ACTIVE/5 | READY / ready | 23/14 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_NEW_CONSTRUCTION_WATERPROOFING` / New Construction Waterproofing | Waterproofing (`SYS_CATEGORY_WATERPROOFING`) | ACTIVE/5 | READY / ready | 14/14 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_REPAIR_CRACK_WATERPROOFING` / Repair & Crack Waterproofing | Waterproofing (`SYS_CATEGORY_WATERPROOFING`) | ACTIVE/5 | READY / ready | 14/14 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_TWO_COMPONENT_WATERPROOFING` / Two-Component Waterproofing | Waterproofing (`SYS_CATEGORY_WATERPROOFING`) | ACTIVE/5 | READY / ready | 14/14 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_WATERPROOFING_ADDITIVES_PRIMERS` / Waterproofing Additives & Primers | Waterproofing (`SYS_CATEGORY_WATERPROOFING`) | ACTIVE/5 | READY / ready | 30/18 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_ACRYLIC_WOOD_LACQUERS` / Acrylic Wood Lacquers | Wood Finishes (`SYS_CATEGORY_WOOD_FINISHES`) | ACTIVE/5 | READY / ready | 22/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_ANTI_TERMITE_TREATMENT` / Anti-Termite Treatment | Wood Finishes (`SYS_CATEGORY_WOOD_FINISHES`) | ACTIVE/5 | READY / ready | 32/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_GENERAL_WOOD_COATINGS` / General Wood Coatings | Wood Finishes (`SYS_CATEGORY_WOOD_FINISHES`) | ACTIVE/5 | READY / ready | 23/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_LUXURY_WOOD_FINISHES` / Luxury Wood Finishes | Wood Finishes (`SYS_CATEGORY_WOOD_FINISHES`) | ACTIVE/5 | READY / ready | 22/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_MELAMINE_WOOD_FINISHES` / Melamine Wood Finishes | Wood Finishes (`SYS_CATEGORY_WOOD_FINISHES`) | ACTIVE/5 | READY / ready | 22/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_POLYURETHANE_VARNISHES` / Polyurethane Varnishes | Wood Finishes (`SYS_CATEGORY_WOOD_FINISHES`) | ACTIVE/5 | READY / ready | 22/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_PU_WOOD_FINISHES` / PU Wood Finishes | Wood Finishes (`SYS_CATEGORY_WOOD_FINISHES`) | ACTIVE/5 | READY / ready | 22/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_SEALERS` / Wood Sealers | Wood Finishes (`SYS_CATEGORY_WOOD_FINISHES`) | ACTIVE/5 | READY / ready | 23/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_STAINS_DYES` / Wood Stains & Dyes | Wood Finishes (`SYS_CATEGORY_WOOD_FINISHES`) | ACTIVE/5 | READY / ready | 23/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_FINISHES_WOOD_VARNISHES` / Wood Varnishes | Wood Finishes (`SYS_CATEGORY_WOOD_FINISHES`) | ACTIVE/5 | READY / ready | 22/20 | 0 | PROBABLY_SHOULD_BE_SELECTABLE / S |

## Ten duplicate-pair semantic comparisons

All ten pairs are SYSTEM / ACTIVE under the same explicit parent and catalogue context, with raw templateStatus READY. In each pair one raw selectable flag is absent and the other true; absence is allowed by current eligibility rules. Neither member has `templateSelectable=false`.

Every pair is classified `SEMANTIC_CONFLICT`, with `recommendedApproval=NEEDS_DOMAIN_CONFIRMATION` and actual `approved=false`. This is a conservative conclusion about the complete authored/effective contracts, not an assertion that the similarly named businesses necessarily intended distinct products. None qualifies for an automatic merge. No inferred subset relation is used to erase differences in defaults, field type, options, requiredness or placement.

Comparison retains raw active template rows, authored profiles, resolved field IDs/types/levels/requiredness/defaults/options/conditions, allowed units and ordering/sections. Physical SQL insertion order is ignored; sortOrder and option order are retained. Only row identity and documented synchronization timestamps/provenance/version metadata are removed from contract signatures. Revision/profile key differences remain visible and cannot alone prove equivalence. Full left/right contracts and diffs are in JSON.

Compiler declarations provide a preferred *identity candidate* for each group: the unique ID explicitly declared in `canonicalCategories`. This is deterministic evidence of compiler intent; it does not approve that candidate's current form semantics. The other member is the potential legacy candidate. References and template semantics must be reviewed before any future migration.

### Tile Adhesives — Adhesives & Tiling

Parent: `SYS_CATEGORY_ADHESIVES_TILING`. Preferred compiler identity candidate: `SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES`. Potential legacy candidate: `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES`. Both remain active and untouched.

Resolved forms are identical (4 PRODUCT, 3 VARIANT fields); authored selling options differ: Bag/Bucket versus Bag/Pouch/Bucket/Kilogram, and profile schema/requiredFields differ. Template row content differs despite equal active row counts. Confirm permissible packaging before any merge.


| ID | All referencing records / occurrences | Active referencing records | Product refs | Template refs (all statuses) | Sync-query refs | Other tables |
| --- | --- | --- | --- | --- | --- | --- |
| `SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | 8/8 | 8 | 0 | 7 | 0 | {"local_product_subcategories": 1} |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | 12/12 | 7 | 0 | 12 | 0 | {} |

Reference migration would cover the listed template rows, including inactive historical rows, plus the nested profile self-reference where present. No Product reference exists to either member of this pair. No local sync query references either exact ID. Requiredness, placement, conditions and ordering are explicitly included in both contracts; equality of a particular field does not erase the other differences. Phase 8 migration cannot be safely approved as an automatic equivalent merge on this evidence. Business/domain confirmation is required; actual approval remains false.

### Thinners — Allied Products

Parent: `SYS_CATEGORY_ALLIED_PRODUCTS`. Preferred compiler identity candidate: `SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS`. Potential legacy candidate: `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS`. Both remain active and untouched.

Resolved forms are identical (2 PRODUCT, 3 VARIANT fields); authored selling options add Bucket on one side, and profile schema/requiredFields differ. Confirm container choices and source contract.


| ID | All referencing records / occurrences | Active referencing records | Product refs | Template refs (all statuses) | Sync-query refs | Other tables |
| --- | --- | --- | --- | --- | --- | --- |
| `SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS` | 6/6 | 6 | 0 | 5 | 0 | {"local_product_subcategories": 1} |
| `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS` | 6/6 | 5 | 0 | 6 | 0 | {} |

Reference migration would cover the listed template rows, including inactive historical rows, plus the nested profile self-reference where present. No Product reference exists to either member of this pair. No local sync query references either exact ID. Requiredness, placement, conditions and ordering are explicitly included in both contracts; equality of a particular field does not erase the other differences. Phase 8 migration cannot be safely approved as an automatic equivalent merge on this evidence. Business/domain confirmation is required; actual approval remains false.

### Epoxy Flooring — Floor & Tile Coatings

Parent: `SYS_CATEGORY_FLOOR_TILE_COATINGS`. Preferred compiler identity candidate: `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING`. Potential legacy candidate: `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING`. Both remain active and untouched.

Resolved usage options differ: six global values versus Interior & Exterior only. The long-ID record rejects its raw Floor default and resolves it to null. Profile finish/default/thinner/options and variant ordering differ. Decide Floor usage contract before merging.


| ID | All referencing records / occurrences | Active referencing records | Product refs | Template refs (all statuses) | Sync-query refs | Other tables |
| --- | --- | --- | --- | --- | --- | --- |
| `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | 21/21 | 20 | 0 | 20 | 0 | {"local_product_subcategories": 1} |
| `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | 21/21 | 19 | 0 | 21 | 0 | {} |

Reference migration would cover the listed template rows, including inactive historical rows, plus the nested profile self-reference where present. No Product reference exists to either member of this pair. No local sync query references either exact ID. Requiredness, placement, conditions and ordering are explicitly included in both contracts; equality of a particular field does not erase the other differences. Phase 8 migration cannot be safely approved as an automatic equivalent merge on this evidence. Business/domain confirmation is required; actual approval remains false.

### Acrylic Putty — Putty & Surface Preparation

Parent: `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION`. Preferred compiler identity candidate: `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY`. Potential legacy candidate: `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY`. Both remain active and untouched.

Resolved Product Colour is TEXT versus SELECT restricted to White; Usage is the global six-value set versus Interior only. Authored profile schema and variant fields differ. Decide colour identity and valid usage.


| ID | All referencing records / occurrences | Active referencing records | Product refs | Template refs (all statuses) | Sync-query refs | Other tables |
| --- | --- | --- | --- | --- | --- | --- |
| `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | 17/17 | 11 | 0 | 16 | 0 | {"local_product_subcategories": 1} |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | 19/19 | 10 | 0 | 19 | 0 | {} |

Reference migration would cover the listed template rows, including inactive historical rows, plus the nested profile self-reference where present. No Product reference exists to either member of this pair. No local sync query references either exact ID. Requiredness, placement, conditions and ordering are explicitly included in both contracts; equality of a particular field does not erase the other differences. Phase 8 migration cannot be safely approved as an automatic equivalent merge on this evidence. Business/domain confirmation is required; actual approval remains false.

### Waterproof Wall Putty — Putty & Surface Preparation

Parent: `SYS_CATEGORY_PUTTY_SURFACE_PREPARATION`. Preferred compiler identity candidate: `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY`. Potential legacy candidate: `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY`. Both remain active and untouched.

Resolved Product Colour is TEXT versus SELECT White; Usage is the global set versus Interior & Exterior only. Authored surface defaults and profile schema/variant fields differ. Decide supported substrates and colour/usage.


| ID | All referencing records / occurrences | Active referencing records | Product refs | Template refs (all statuses) | Sync-query refs | Other tables |
| --- | --- | --- | --- | --- | --- | --- |
| `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | 17/17 | 11 | 0 | 16 | 0 | {"local_product_subcategories": 1} |
| `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | 19/19 | 10 | 0 | 19 | 0 | {} |

Reference migration would cover the listed template rows, including inactive historical rows, plus the nested profile self-reference where present. No Product reference exists to either member of this pair. No local sync query references either exact ID. Requiredness, placement, conditions and ordering are explicitly included in both contracts; equality of a particular field does not erase the other differences. Phase 8 migration cannot be safely approved as an automatic equivalent merge on this evidence. Business/domain confirmation is required; actual approval remains false.

### Acrylic Sealants — Sealants & Repair

Parent: `SYS_CATEGORY_SEALANTS_REPAIR`. Preferred compiler identity candidate: `SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS`. Potential legacy candidate: `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS`. Both remain active and untouched.

Resolved forms are identical (4 PRODUCT, 3 VARIANT fields), while authored allowed units differ (Millilitre/Gram versus Cartridge/Tube/Pouch/Kilogram/Litre), as do unit/surface defaults and technical fields. Measurement/container semantics must be decided; equal resolved forms do not prove equivalence.


| ID | All referencing records / occurrences | Active referencing records | Product refs | Template refs (all statuses) | Sync-query refs | Other tables |
| --- | --- | --- | --- | --- | --- | --- |
| `SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | 9/9 | 8 | 0 | 8 | 0 | {"local_product_subcategories": 1} |
| `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | 14/14 | 7 | 0 | 14 | 0 | {} |

Reference migration would cover the listed template rows, including inactive historical rows, plus the nested profile self-reference where present. No Product reference exists to either member of this pair. No local sync query references either exact ID. Requiredness, placement, conditions and ordering are explicitly included in both contracts; equality of a particular field does not erase the other differences. Phase 8 migration cannot be safely approved as an automatic equivalent merge on this evidence. Business/domain confirmation is required; actual approval remains false.

### Bathroom & Kitchen Waterproofing — Waterproofing

Parent: `SYS_CATEGORY_WATERPROOFING`. Preferred compiler identity candidate: `SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN`. Potential legacy candidate: `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING`. Both remain active and untouched.

Resolved Usage is Interior only versus the six-value global set. Authored allowed units are mixed volume/mass versus mass only, and soldAs/variant-field/default contracts differ. Confirm powder versus liquid family intent.


| ID | All referencing records / occurrences | Active referencing records | Product refs | Template refs (all statuses) | Sync-query refs | Other tables |
| --- | --- | --- | --- | --- | --- | --- |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING` | 14/14 | 14 | 0 | 14 | 0 | {} |
| `SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN` | 15/15 | 15 | 0 | 14 | 0 | {"local_product_subcategories": 1} |

Reference migration would cover the listed template rows, including inactive historical rows, plus the nested profile self-reference where present. No Product reference exists to either member of this pair. No local sync query references either exact ID. Requiredness, placement, conditions and ordering are explicitly included in both contracts; equality of a particular field does not erase the other differences. Phase 8 migration cannot be safely approved as an automatic equivalent merge on this evidence. Business/domain confirmation is required; actual approval remains false.

### Exterior Wall Waterproofing — Waterproofing

Parent: `SYS_CATEGORY_WATERPROOFING`. Preferred compiler identity candidate: `SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL`. Potential legacy candidate: `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING`. Both remain active and untouched.

Resolved Usage is Exterior only versus the six-value global set. Both currently resolve Surface=Roof despite authored Wall/Concrete evidence: inherited defaults are not evidence of intended equivalence. Authored unit and selling contracts differ.


| ID | All referencing records / occurrences | Active referencing records | Product refs | Template refs (all statuses) | Sync-query refs | Other tables |
| --- | --- | --- | --- | --- | --- | --- |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING` | 14/14 | 14 | 0 | 14 | 0 | {} |
| `SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL` | 15/15 | 15 | 0 | 14 | 0 | {"local_product_subcategories": 1} |

Reference migration would cover the listed template rows, including inactive historical rows, plus the nested profile self-reference where present. No Product reference exists to either member of this pair. No local sync query references either exact ID. Requiredness, placement, conditions and ordering are explicitly included in both contracts; equality of a particular field does not erase the other differences. Phase 8 migration cannot be safely approved as an automatic equivalent merge on this evidence. Business/domain confirmation is required; actual approval remains false.

### Interior Dampness Treatment — Waterproofing

Parent: `SYS_CATEGORY_WATERPROOFING`. Preferred compiler identity candidate: `SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS`. Potential legacy candidate: `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT`. Both remain active and untouched.

Resolved Usage is Interior only versus the six-value global set. Authored unit/selling contracts and defaults differ. Confirm substrate/material and valid usage.


| ID | All referencing records / occurrences | Active referencing records | Product refs | Template refs (all statuses) | Sync-query refs | Other tables |
| --- | --- | --- | --- | --- | --- | --- |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT` | 14/14 | 14 | 0 | 14 | 0 | {} |
| `SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS` | 15/15 | 15 | 0 | 14 | 0 | {"local_product_subcategories": 1} |

Reference migration would cover the listed template rows, including inactive historical rows, plus the nested profile self-reference where present. No Product reference exists to either member of this pair. No local sync query references either exact ID. Requiredness, placement, conditions and ordering are explicitly included in both contracts; equality of a particular field does not erase the other differences. Phase 8 migration cannot be safely approved as an automatic equivalent merge on this evidence. Business/domain confirmation is required; actual approval remains false.

### Roof & Terrace Waterproofing — Waterproofing

Parent: `SYS_CATEGORY_WATERPROOFING`. Preferred compiler identity candidate: `SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE`. Potential legacy candidate: `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING`. Both remain active and untouched.

Resolved Usage is Exterior only versus the six-value global set. Authored units are mixed volume/mass versus volume only, and selling/default contracts differ. Confirm Roof usage and material-dependent units.


| ID | All referencing records / occurrences | Active referencing records | Product refs | Template refs (all statuses) | Sync-query refs | Other tables |
| --- | --- | --- | --- | --- | --- | --- |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING` | 14/14 | 14 | 0 | 14 | 0 | {} |
| `SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE` | 15/15 | 15 | 0 | 14 | 0 | {"local_product_subcategories": 1} |

Reference migration would cover the listed template rows, including inactive historical rows, plus the nested profile self-reference where present. No Product reference exists to either member of this pair. No local sync query references either exact ID. Requiredness, placement, conditions and ordering are explicitly included in both contracts; equality of a particular field does not erase the other differences. Phase 8 migration cannot be safely approved as an automatic equivalent merge on this evidence. Business/domain confirmation is required; actual approval remains false.

Reference counts scan every table in both account and public-config databases, including configuration/map keys, roles, pending sync data and any historical rows. Counts distinguish unique referencing records from reference occurrences; indexed SQL mirrors are recorded separately to avoid double-counting decoded references. Own top-level subcategory identity is excluded; a nested profile's subcategory reference is a dependency and counted. All source record IDs/paths, active-owner status, table breakdowns and counts for every active/payload ID are in `allReferenceCounts` in JSON. These are local-only findings, not proof that unseen remote references are absent.

The account has 195 sync queries, 50 active. Ten contain other protected legacy IDs according to the current registry. None contains either exact ID of these ten pairs or the four Ceiling/Basement identities. Those ten other protected queries remain unchanged and must still block unsafe future migration; no cleanup or query rewrite occurred.

## Ceiling Paints and Basement Waterproofing identity review

Origin tracing found that the pre-Phase-9 compiler at `0ca93d775c9a6fd2cccf7b6c0c5beadd7978d220` loaded `remoteId` as `id` and independently decoded the payload fields, then wrote document names from that original `id`. It generated template IDs/references using payload `subcategoryId`. There was no document/payload equality validation at this boundary, so the path could preserve a mismatched definition while generating a second template group. This establishes the historical mechanism that permitted divergence, not the exact event that first introduced these two payload IDs.

The archived v3 fixture contains neither of these exact document/payload pairs. The installed v3/revision-5 rows and Phase 8 inventory provide the old-ID group evidence. The exact original emitter/import event is not recoverable from the inspected offline history; no live Firestore lookup was attempted. Phase 9 (`22821f4`) added `CatalogueContract.decode` identity validation. Its dedicated Ceiling/Basement regression explicitly supplies the two current document IDs and proves compilation does not attach old-ID orphan groups. The current compiler preserves supplied definition IDs; neither family is regenerated from display labels, and neither appears as a separately generated canonical entry in the current declaration. A mismatched installed definition cannot simply be compiled as a valid release.

### Ceiling Paints

Current active definition document: `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS`. Its raw payload ID and runtime selector identity are `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS`. Current compiler profile is `INTERIOR_COATING`. Recommendation: use the current **document ID** as the prospective canonical identity when a consistent explicit successor definition is reviewed; never infer or rewrite the installed payload identity automatically. `recommendedApproval=NEEDS_DOMAIN_CONFIRMATION`, actual `approved=false`.


| Identity | Active templates | All template refs / all referencing records | Product refs | Sync-query refs |
| --- | --- | --- | --- | --- |
| SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS | 18 | 22 / 22 | 0 | 0 |
| SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS | 21 | 21 / 21 | 0 | 0 |

The document group has 18 active template rows; the payload group has 21. Product Colour placement is PRODUCT versus VARIANT, coat default is absent versus 2 Coats, and selling options differ. The payload group also includes segment/shelfLife/warranty fields. These are not interchangeable template groups; retain and review both.

### Basement Waterproofing

Current active definition document: `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING`. Its raw payload ID and runtime selector identity are `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT`. Current compiler profile is `WATERPROOFING`. Recommendation: use the current **document ID** as the prospective canonical identity when a consistent explicit successor definition is reviewed; never infer or rewrite the installed payload identity automatically. `recommendedApproval=NEEDS_DOMAIN_CONFIRMATION`, actual `approved=false`.


| Identity | Active templates | All template refs / all referencing records | Product refs | Sync-query refs |
| --- | --- | --- | --- | --- |
| SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING | 14 | 14 / 14 | 0 | 0 |
| SYS_SUBCATEGORY_WATERPROOFING_BASEMENT | 14 | 14 / 14 | 0 | 0 |

Each group has 14 active rows. Document-group coat/thinner defaults are absent; payload-group defaults are 2 Coats/Water. Document units include Gram; payload units do not. Usage options/default representation also differ. Equal group size does not prove semantic equivalence.

## Unit-rule boundary and proposed Phase 10B

All 59 individually eligible records resolve 27 global base-unit names and `conversionAllowed=true`. `ProductTemplateResolver._resolveUnitRules` directly sets `allowedBaseUnits: globalUnits` and `conversionAllowed: true`; neither is read from template metadata. Pack and selling sets *can* be restricted through the resolved unit/soldAs attribute option sets, with fallback to all global units. Their rule defaults currently use the first option, rather than a separate family-specific unit contract.

The UI currently uses allowedPackUnits for base choices and filters recognized commercial containers where measurement choices exist; conversion remains opt-in and the repository validates explicit conversions. These guards mitigate some risks but do not constitute the requested family-specific allowedBaseUnits/conversionAllowed metadata contract. Global true does not mean every existing Product is converted or that every invalid conversion is saved.

Conclusion: an architecture/contract gap spanning Phase 4 and Phase 10. Content alone cannot express the complete resolved restriction. Recommend a separately scoped Phase 10B change to decode explicit per-template/family allowed base units, conversion eligibility and defaults; then make UI and validator consume that contract consistently, rejecting unresolved/unsupported units rather than falling back globally. Preserve all Product/Variant identities and existing historical unit references. Do not implement this change or enable conversion in Phase 10A.

The following are proposed review boundaries based on the supplied Phase 10 family contracts, not invented technical specifications. Packaging choices require exact profile evidence; containers must not become measurement bases. Conversion starts OFF and is allowed only with an explicit supported dimension/factor contract.

| Major family | Expected pack/measurement set | Selling/container boundary | Expected measurement base/conversion |
| --- | --- | --- | --- |
| Interior/exterior/interior & exterior coatings; primers; enamels; wood finishes | Litre/Millilitre | Only profile-supported Can/Bucket/etc. | Volume base Litre/Millilitre; conversion opt-in if approved |
| Protective/industrial coatings | Litre/Millilitre unless exact material says powder | Explicit chemistry/material profile; no residential default inference | Volume, or mass for an explicitly distinct powder profile |
| Putty, cement paint, powder coatings, powder fillers | Kilogram/Gram | Bag/Bucket/etc. only by exact profile | Mass base Kilogram/Gram; no container base |
| Waterproofing | Litre/Millilitre or Kilogram/Gram by material | Do not expose both dimensions without material evidence | One approved material dimension; not inferred from name |
| Adhesives/tiling | Kilogram/Gram or explicit liquid adhesive volume | Bag/Pouch/Bucket by profile | Mass or volume from exact profile; no global mix |
| Sealants/repair | Cartridge/Tube/Pouch or supported mass/volume presentation | Separate packaged SKU from its declared content amount | Measurement base only if exact mass/volume content and factor are supplied; otherwise OFF |
| Admixtures | Litre/Millilitre | Profile-supported Bottle/Can/Drum | Volume; opt-in conversion only if explicit |
| Brushes/rollers/tools | Piece | Explicit Piece/Set/Pack as supported | No measurement conversion by default; dimensions are variant attributes |
| Sandpaper | Sheet | Explicit Sheet/Pack/Roll only when supported | No conversion inferred from packaging |
| Masking tape | Roll | Roll/Pack as supported | No conversion inferred from width/roll count |
| Wallpaper/wall coverings | Roll (Sheet only for explicitly supported family) | Roll/Sheet contract and dimensions reviewed | No inferred linear/area conversion |
| DIY stickers/stencils | Piece/Sheet/Roll according to explicit profile | No coating chemistry inheritance | OFF unless explicit domain unit contract |
| Spray/aerosols | Exact volume-content or packaged Piece/Can profile | Do not assume Can means a volume base | OFF unless declared volume/factor contract |
| Thinners | Litre/Millilitre | Profile-supported Can/Bottle/Drum | Volume only; packaging never a measurement base |

## Epoxy Flooring usage-default recommendation

Record: `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING`; intended compiler family `FLOOR_COATING`. Its active usage row has raw default `Floor`, but the restricted allowed options are only `Interior & Exterior`. The resolver emits `INVALID_DEFAULT` and clears the effective default to null. The other same-parent candidate permits Floor via the six-value global Usage options. Current FLOOR_COATING generation explicitly defaults usage/surface to Floor, and the supplied approved Usage list includes Floor.

Recommended content correction for a future reviewed release: retain the business-relevant Floor default and add Floor to this exact floor-profile usage option set. Do not replace it with a residential Interior/Exterior default just to silence validation. Whether Interior & Exterior should remain as an additional choice belongs to the pair's domain contract decision. Do not globally broaden unrelated usage sets. No metadata was changed here.

## Decisions required before Phase 10 correction

- All 87 probable schema-residue disabled records: review their exact family contracts and explicitly decide restored eligibility; the table above names every record. Interior Sheen Emulsions additionally has a saved Product reference.
- Miscellaneous: define scope, active profile and intended selectable status, or explicitly retain disabled.
- Every one of the ten duplicate pairs: approve intended fields/units/options/defaults and then canonical identity/reference disposition. All ten have semantic conflicts; none is approved for automatic merge.
- Ceiling Paints and Basement Waterproofing: confirm the prospective document-ID definitions and disposition of both non-equivalent template groups. Original mismatch provenance remains unresolved.
- Approve a scoped Phase 10B unit-rule contract change if full family-specific base/conversion behavior is required.
- Confirm Epoxy Floor usage option/default policy as part of the floor profile; resolve any retained alternatives.

Hand Sanitizers remains intentionally excluded from HARDWARE/PAINTS. Legacy Paint / Interior Wall Paint remains MISSING_TEMPLATE and must not be enabled as a normal selectable form. No claim that 147 forms ought to be selectable is supported by current evidence. No record was classified as intentionally disabled solely from a false flag. No Phase 8 approval file was edited.

## Verification and files

Baseline complete workspace suite: 248/248 passed. Final complete workspace suite: 268/268 passed with `flutter test --timeout 5m --reporter expanded`; the extended timeout accommodates the existing 120-second guarded safety test. Dedicated changed/added Dart tests: 25 (five selector tests, five decoded-accounting/safety tests, fifteen registered Python evidence proofs). The Python proofs also passed directly (15/15). The ten duplicate groups each have a separately registered semantic-diff proof. Additional proofs cover 88 dispositions, identity mismatch evidence, semantic sensitivity to requiredness/default/options/placement/order, all-table reference detection, and temporary-SQLite mutation rejection.

The final full-suite existing production safety guard observed 120 seconds / 23 samples and no process or checksum violation; final verification below also confirms unchanged production files. Analyzer: baseline 54 diagnostics (6 warnings, 48 infos, 0 errors); final 53 (6 warnings, 47 infos, 0 errors), zero new diagnostics. The removed sqlite3 import from the faulty selector test eliminated one existing dependency diagnostic. `flutter analyze` still exits nonzero for this pre-existing baseline; it is not reported as a clean analyzer run.

Files changed/added:

- `test/product_selector_reconciliation_test.dart` — replace invalid raw-SQL selector proof with runtime decoding/resolvers; preserve focused eligibility tests.
- `test/support/decoded_catalogue_audit.dart` — real LocalDataSource reader and exact document/payload reconciliation; read-only database guard.
- `test/catalogue_phase10a_audit_test.dart` — 149/88/10/mismatch accounting, saved/runtime evidence equality and production byte/mtime/sidecar safety.
- `test/catalogue_phase10a_semantic_test.dart` — register fifteen Python proofs in the workspace suite.
- `tool/catalogue_phase10a.py` — read-only evidence extraction, all-table reference inventory, conservative semantic comparison and unapproved recommendations.
- `tool/tests/test_catalogue_phase10a.py` — direct decision-evidence and temporary-SQLite guard proofs.
- `docs/phase10a-catalogue-audit.json` — complete machine-readable per-record/pair/reference evidence.
- `phase10a.md` — this report.

No production Dart code, catalogue fixture, catalogue metadata, Phase 8 mapping file, Product identity, Variant identity, SKU, barcode, historical reference, or live sync query was changed. There is no corrected successor release artifact.

## Production integrity

Before/after checksums, size and nanosecond mtime match exactly. No WAL, SHM or journal existed or appeared for account, backup or public-config. Final escalated read-only `lsof` found no account/public-config handles and executable-name process inspection found no testflutter/NubiBill application. The audit cannot claim remote data was inspected; it performed zero Firestore access.

| Absolute path | Size before = after | mtime ns before = after | SHA-256 before | SHA-256 after |
| --- | --- | --- | --- | --- |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db` | 9744384 | 1791112106494478057 | `76419c2ae88c03719f0965709d2e81f7cfbc65a6021278a79c93f9a14f83ee70` | `76419c2ae88c03719f0965709d2e81f7cfbc65a6021278a79c93f9a14f83ee70` |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak` | 9728000 | 1791091536646307789 | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db` | 937984 | 1791111851757294196 | `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012` | `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012` |

Phase 10A is ready for review. Production remains unchanged. The deliverable supports choosing the next Phase 10 path; it does not approve or execute any catalogue merge, retirement, migration, flag change, unit-rule implementation or template correction. Phase 11 was not begun.
