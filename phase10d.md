# Phase 10D — Basement evidence gate and successor release decision

**Status: STOP before Release 4 generation. Final material classification: INSUFFICIENT_EVIDENCE.** Basement Waterproofing remains DOMAIN_REVIEW_REQUIRED and is not READY. The repository does not establish an exclusive liquid, powder/cementitious, or concrete separate-material product contract. No Release 4 manifest, fixture, fingerprint, import or publication was created.

This follows the explicit critical release gate and stop condition: do not generate Release 4 unless Basement's required material/unit contract becomes defensible. A generic default or mixed unit menu is insufficient. The evidence audit and verification are complete; the successor-release portion remains blocked for a domain decision.

## Preflight

- Active branch: `fix/product-master-audit`.
- Phase 10C committed at **`761fdebeeb83d545ee16c6c9a9c7c4023bf2383f`**, `fix(product-master): correct canonical catalogue content contracts`.
- Working tree clean before this phase.
- Complete baseline workspace: **460/460 tests passed**, including all Phase 10C simulations.
- Account, backup and public-config SHA-256, size, mtime and sidecar presence captured before tests and production inspection.
- Account/public-config SQL opened exclusively with `mode=ro` and `PRAGMA query_only=ON`. Backup was hash-only. No writable production bootstrap, app launch or Firestore client was used.

Authoritative inputs remain the committed Phase 10A/10B/10C JSON evidence, existing compiler/profile definitions, CatalogueContract, SystemCatalogueSnapshot and archived fixture/history. No input content was rewritten.

## Basement evidence and classification

Prospective canonical document ID:
`SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING`.

Installed payload / historical template-group identity:
`SYS_SUBCATEGORY_WATERPROOFING_BASEMENT`.

The complete evidence, independent template rows, current reference locations, source hashes and repository-history inventory are saved in [docs/phase10d-basement-evidence.json](docs/phase10d-basement-evidence.json).

### Authored installed profile

The current decoded profile explicitly allows **Litre, Millilitre, Kilogram and Gram**. It defaults Pack Unit to **Litre** and selling presentation to **Bucket**, while allowing Bucket, Can, Bag, Drum, Litre and Kilogram. Thus its default is a preference inside a mixed physical-dimension menu, not an exclusive liquid-material declaration.

The profile contains no exclusive physical form, material form, mass/volume discriminator, material-specific content quantity, or separate named material-product definition. Substrate/application values (Concrete, Wall, Floor; Interior & Exterior) describe use, not physical form. Optional mixing/dilution/coating fields and broad thinner menus do not establish a measurement dimension.

| Evidence source | Exact finding | Conclusion |
| --- | --- | --- |
| Current document-ID subcategory payload | Payload identity differs from document; mixed volume/mass `allowedUnits`; Litre / Bucket defaults | No exclusive material declaration |
| Current document-ID template group | 14 ACTIVE rows; unit options Litre, Millilitre, Kilogram, Gram; default Litre | Both dimensions explicitly allowed |
| Historical payload-ID template group, inspected separately | 14 ACTIVE rows; unit options Litre, Millilitre, Kilogram; default Litre | Both dimensions explicitly allowed; no exclusive material proof |
| Current compiler `profileFor` | No Basement-specific material profile; category falls into WATERPROOFING | Family selection supplies no physical-form evidence |
| Current compiler Waterproofing profile | Generic expression `unit: isBathroom ? Kilogram : Litre`, mixed allowed mass/volume/presentation units | Litre default is not a Basement-specific domain fact |
| Baseline historical compiler `0ca93d7` | Category/name waterproofing/damp heuristic; same generic Bathroom vs Litre branch | Earlier defaults also come from a broad family branch |
| Phase 9 compiler `22821f4` | Explicit family/profile selection replaces name branching; generic Waterproofing unit expression retained | Deterministic compiler identity repair did not establish Basement material semantics |
| Archived raw v3 fixture | 57 subcategories / 93 templates; no Basement record or either Basement identity | No independent archived liquid/powder declaration |
| Historical audit reports | Record current Litre / Bucket defaults and matching application scope | Observations of existing defaults, not certification of liquid-only material |
| Current local Products, either identity | Zero references to both IDs | No concrete stored product/material evidence resolves the ambiguity |
| Public-config read-only search | Zero Basement matches | No additional domain contract there |

Repository search covered all current Basement mentions, all **22 reachable commits**, and **20 distinct matching file versions**. The history contains 19 matching paths (one audit test has two versions); all metadata-bearing versions refer to the same unresolved mixed-unit evidence. Current and historical generic compiler declarations were inspected separately even though they contain no literal Basement declaration. Source-file hashes for **25 files** are recorded in the evidence artifact. No live Firestore lookup was attempted.

### Why the other classifications are rejected

| Possible classification | Decision |
| --- | --- |
| VOLUME | Rejected: no explicit liquid-only material evidence; mass choices remain authored; Litre is also a generic fallback/default. |
| MASS | Rejected: no powder/cementitious-only declaration; volume choices and Litre default remain authored. |
| DISTINCT_PRODUCTS_REQUIRED | Not proven: a mixed unit menu can be legacy/compiler residue. There are no concrete separate liquid and powder products/contracts establishing distinct intent. |
| **INSUFFICIENT_EVIDENCE** | **Selected, exactly one final classification.** Required material identity cannot be established from available evidence. |

A display name, Bucket presentation, Water thinner default or Litre default is not used to infer physical form. No conversion factor or measurement content is invented.

### Current versus historical template semantics

Both groups contain the same 14 attribute IDs, but remain independent identities. Current document rows include Gram in Pack Unit; historical payload rows do not. Current Usage has an explicit Interior & Exterior option; the historical row inherits its options. Historical rows default Dilution Type to Water and Coats to 2 Coats, whereas those current document rows have no default. These differences do not establish concrete distinct material products and do not authorize grafting either group into the other.

The Phase 10C prospective content uses the current document-ID group and removes irrelevant decorative chemistry. It deliberately keeps required Pack Unit unresolved, with empty pack/base lists and conversion disabled. The actual ProductTemplateResolver still returns invalid readiness with DOMAIN_REVIEW_REQUIRED / ERROR. This test does not bypass that diagnostic or call Basement selectable.

| Identity | Product references | Template references | Sync-query references | Other/history references |
| --- | ---: | ---: | ---: | ---: |
| `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING` | 0 | 14 | 0 | 0 |
| `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT` | 0 | 14 | 0 | 0 |

Counts search every table and JSON value/map key in account/public-config, including inactive rows and history/config references; indexed mirrors are recorded separately from logical dependencies. A record's own identity is excluded from dependency counts. The installed subcategory's mismatched payload ID is recorded as identity evidence, not an extra dependent row. Thus the historical identity has 14 logical template dependencies; an older inventory that counted its own payload identity showed 15. No historical reference has been removed.

Account search found 29 Basement-bearing rows: one subcategory and the two independent 14-row template groups. There are no Basement Product or sync-query rows. The registry nevertheless protects the historical identity against future unreviewed query registration.

## Release gate and requested quality proofs

**Release 4 is not generated.** No `docs/catalogue-release-v4-review.json` or `test/fixtures/system_catalogue_v4.json` was created. CatalogueContract remains schema revision **1**, compiler revision **6**; target data version **4** remains a proposal. The observed production release remains catalogueVersion **3**, localMetadataRevision **5**, unchanged.

The committed Phase 10C model remains non-importable and unapproved, with 136 candidates: **135 SELECTABLE_READY and one blocked Basement candidate**. All 87 schema-residue records remain ready only in that review model. Miscellaneous remains disabled/review-required; Hand Sanitizers and historical Paint / Interior Wall Paint remain excluded. Ten legacy duplicate members remain noncanonical and unchanged. Nothing is installed or retired.

Phase 10C logical fingerprint remains:
`042796faeaf023ce470428fb2403dff25bcdd332b11ad7c2e919bf368d7a52e9`.

**Release 4 fingerprint: not applicable / not generated.** The Phase 10C fingerprint is not presented as a release fingerprint.

| Requested Release 4 proof | Result |
| --- | --- |
| Deterministic Release 4 generation / compiler validation | GATED — no Release 4 payload exists |
| Canonical / selector count | No Release 4 count; existing intended model is 136 candidates, 135 ready, one blocked |
| Document/payload identity mismatch count | NOT MEASURED for Release 4; no fixture exists |
| Same-parent canonical duplicate collision count | NOT MEASURED for Release 4 |
| Active template / orphan / invalid-reference counts | NOT MEASURED for Release 4 |
| PRODUCT/VARIANT intersection; invalid defaults/options; required-hidden fields; supported conditions | Existing Phase 10C proofs pass; no imported Release 4 certification |
| Invalid required unit contracts | Basement remains the one known blocker in the review model; no Release 4 gate pass |
| First actual snapshot import / version-4 marker | NOT ATTEMPTED |
| Identical second import / logical idempotence | NOT ATTEMPTED |
| Failure during categories | NOT ATTEMPTED for Release 4 |
| Failure during subcategories | NOT ATTEMPTED for Release 4 |
| Failure during attributes/options | NOT ATTEMPTED for Release 4 |
| Failure during templates | NOT ATTEMPTED for Release 4 |
| Failure before release marker | NOT ATTEMPTED for Release 4 |
| Failure after marker before commit | NOT ATTEMPTED for Release 4 |
| Exact selector ID-set / complete imported-form simulation | GATED for Release 4; existing Phase 10C model reverified |
| Zero unexplained CRITICAL/HIGH Release 4 defects | Not certified: required unit evidence remains missing |

No placeholder dimension, malformed v3 copy, guessed snapshot, partial Release 4 or temporary release marker was created to bypass the stop condition. Existing Phase 9 atomicity/idempotence tests pass in the full workspace suite; they are not substituted for new-release-specific proofs.

The optional 84 thinner-choice reviews and 12 Wood colour-mode-default reviews remain unset/optional and are not release blockers. Only Basement's required material/unit area blocks this phase.

## Migration interlock — source findings, no execution

The actual `SystemCatalogueSnapshot.import` calls `LocalDataSource.upsertRemote` with a complete query restricted to **scopeType = SYSTEM** for each collection. The latter marks omitted SYNCED SYSTEM catalogue rows INACTIVE (or tombstones rows lacking catalogue metadata). This complete-snapshot reconciliation does **not** first inspect Product/template/history references or Phase 8 mapping approvals.

Therefore omission from canonical release content cannot serve as approval to retire a currently installed duplicate. The importer and its complete-snapshot behavior were not weakened or changed. A fresh isolated database does not prove safety over production's unresolved identities.

### Ten current duplicate legacy IDs

All counts below include inactive reference rows. Each exact reference record/location is included in the evidence JSON. All pairs retain **approved=false and migrationApproved=false**. Prospective canonical ID preference is not semantic equivalence, retirement permission or an executed remap.

| Group | Legacy ID | Prospective canonical ID | Product | Templates (active) | Sync queries | Other/history |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Tile Adhesives | `SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | `SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES` | 0 | 12 (7) | 0 | 0 |
| Thinners | `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS` | `SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS` | 0 | 6 (5) | 0 | 0 |
| Epoxy Flooring | `SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | `SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING` | 0 | 21 (19) | 0 | 0 |
| Acrylic Putty | `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY` | 0 | 19 (10) | 0 | 0 |
| Waterproof Wall Putty | `SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | `SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY` | 0 | 19 (10) | 0 | 0 |
| Acrylic Sealants | `SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | `SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS` | 0 | 14 (7) | 0 | 0 |
| Bathroom & Kitchen Waterproofing | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING` | `SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN` | 0 | 14 (14) | 0 | 0 |
| Exterior Wall Waterproofing | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING` | `SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL` | 0 | 14 (14) | 0 | 0 |
| Interior Dampness Treatment | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT` | `SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS` | 0 | 14 (14) | 0 | 0 |
| Roof & Terrace Waterproofing | `SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING` | `SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE` | 0 | 14 (14) | 0 | 0 |

### Additional retention / identity boundaries

- `SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_MISCELLANEOUS`: six template references; zero Product/query/history references. Disabling selectability does not approve retirement by omission.
- `SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS`: 22 template references; zero Product/query/history references. Exclusion from Paint selection does not approve deletion/retirement.
- `SYS_CATEGORY_HEALTH_HYGIENE`: one dependent subcategory (Hand Sanitizers); zero Product/template/query/history references. A bare snapshot restricted to the 21 candidate parents would also omit this active SYSTEM category.
- `PM_SUBCATEGORY_ce0bf39843417fca` (historical Interior Wall Paint): one Product reference and two sync-query references; no templates. It lacks an explicit SYSTEM payload scope, so it is not implicitly retired by the SYSTEM-only complete query. It remains excluded and unresolved; neither references nor scope are rewritten.
- `SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS`: 21 old payload-ID template dependencies; zero Product/query/history references. The future reviewed Ceiling document ID is `SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS`; payload identity correction and old-group handling remain unapproved.
- `SYS_SUBCATEGORY_WATERPROOFING_BASEMENT`: 14 old payload-ID template dependencies; zero Product/query/history references. Prospective document ID is retained, but required content and identity decisions remain blocked/unapproved.

These are the currently active category/subcategory omissions and the reviewed mismatch/exclusion boundaries identified from the canonical candidate set; full stored locations are captured in the evidence artifact. Older retired category/subcategory/template identities and their Product/query/history references remain listed in the complete [Phase 8 inventory](docs/phase8-catalogue-inventory.json) and [mapping review](docs/phase8-canonical-mappings.json). Those mappings remain unapproved. Since no Release 4 manifest or final template/option ID set exists, **the exact whole-release retirement diff cannot yet be certified**. No claim is made that only the ten duplicates require migration analysis.

### Required future ordering

**Installation before reviewed migration/retention decisions is unsafe.** A future release needs a coordinated, reviewed process whose reference-migration stage precedes the complete snapshot application:

1. Resolve Basement material/presentation content from authoritative domain evidence; regenerate and verify a complete canonical release only after that decision.
2. Produce an exact installed-versus-release diff for every SYSTEM collection, including categories, subcategories, attributes/options, units and template IDs. Explicitly resolve retained disabled/excluded records and all retirement targets rather than treating absence as approval.
3. Obtain the required Phase 8 identity/reference/migration approvals separately. Preserve Product/Variant IDs, SKU/barcode, timestamps and historical transaction references. Do not assume old templates are equivalent; map/retain/archive them only under approved decisions.
4. Resolve protected legacy sync-query references under those same reviewed mappings; any unresolved protected query blocks migration. Current zero query references for a duplicate pair do not approve its template retirement.
5. With app/sync activity controlled, migrate approved references/identity metadata atomically, audit old-to-new mappings, and prove target readiness plus zero unresolved references before retiring old records. If historical references must remain, keep their referenced records as approved retained metadata.
6. Apply the validated complete release atomically and write its installed marker last. Verify all canonical forms, retention requirements, fingerprints and query state before resuming normal operation.

The current migration and snapshot routines own separate transactions. A single coordinated SQLite transaction would need explicit integration and proof; **this phase does not claim that integration exists or implement it**. A reviewed staged process must prevent intervening readers/sync from observing partially transitioned metadata. No mapping, retirement, alias rewrite or production query update is approved here.

The new isolated registry test inserts a synthetic historical Basement query into temporary SQLite only. `auditLegacy` reports BLOCK_MIGRATION; `upsert` rejects `legacy-query-reference` and leaves the query byte/logically unchanged. This proves the existing query interlock, not a production cleanup or release installation.

## Verification results

- Complete workspace before changes: **460/460 passed**.
- Dedicated Phase 10D evidence suite: **5/5 passed**.
- Final complete workspace: **465/465 passed**, elapsed 3m38s.
- Existing Phase 10C re-simulation: **136 candidates, 135 minimally constructible forms, 4,465 SELECT option cases and 236 conversion cases**. Existing exact selector ID-set reconciliation and all five stale-state widget transitions pass. These run against the review model, not an imported Release 4.
- Existing 120-second production safety guard passes; no writer/checksum violation reported.
- `flutter analyze --no-pub`: **49 pre-existing diagnostics**, 6 warnings and 43 infos, zero errors. Normalized comparison against the Phase 10C baseline finds **zero new diagnostics**. Exit 1 reflects the unchanged baseline.
- Dart formatting completed; `git diff --check` passes.

The five new proofs cover mixed-unit evidence and classification, invalid actual resolver/readiness and closed release gate, independent historical/current template groups, unchanged archived/source evidence, and protected-query blocking without rewrite in temporary SQLite. They perform no production connection, HTTP call or release import.

Commands:

```sh
flutter test --no-pub --timeout 5m --reporter expanded
flutter test --no-pub --timeout 5m --reporter expanded test/catalogue_phase10d_evidence_test.dart
flutter analyze --no-pub
```

Logs: `/private/tmp/phase10d-baseline-tests.log`, `/private/tmp/phase10d-dedicated-tests.log`, `/private/tmp/phase10d-final-tests.log`, `/private/tmp/phase10d-analyze.log`. The five-minute timeout accommodates the existing 120-second guard; no test is skipped.

## Production before/after safety

Before and after full capture records match, including full SHA-256, file size, nanosecond mtime and absence of WAL/SHM/journal sidecars. Account/public-config SQL connections were read-only with query_only; backup was hashed only.

| Production file | Size before = after | mtimeNs before = after | Full SHA-256 before = after | Sidecars |
| --- | ---: | ---: | --- | --- |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db` | 9744384 | 1791112106494478057 | `76419c2ae88c03719f0965709d2e81f7cfbc65a6021278a79c93f9a14f83ee70` | none before/after |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak` | 9728000 | 1791091536646307789 | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | none before/after |
| `/Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db` | 937984 | 1791111851757294196 | `dd843acb814c696323789030f7539b93ae30e7bc0a2ccfdeb3fbc44cd94fa012` | none before/after |

Capture files: `/private/tmp/phase10d-before.json` and `/private/tmp/phase10d-after.json`.

**Zero production SQLite writes and zero Firestore access, reads or writes.** Production catalogue rows, templateSelectable flags, release markers, Products/Variants/SKU/barcode, historical references and sync queries remain unchanged. No live import, Phase 8 migration, legacy retirement, query cleanup or Phase 11 work occurred.

## Files added

- `docs/phase10d-basement-evidence.json` — read-only evidence capture, source/history hashes, classification and reference/interlock inventory.
- `test/catalogue_phase10d_evidence_test.dart` — five evidence/closed-gate/query-interlock proofs.
- `phase10d.md` — this stopped-phase report.

No existing source, Phase 10C artifact, compiler/importer, archived fixture or production data was modified. Changes remain uncommitted for review.

## Required domain decision

Provide an authoritative contract identifying whether this exact Basement canonical form represents **liquid-only material**, **powder/cementitious-only material**, or **explicit separate material forms**, with compatible pack/selling units and defaults. Conversion remains disabled unless an explicit compatible factor/content contract is established. Identity and migration approval remain separate decisions.

Until that evidence exists, keep Basement DOMAIN_REVIEW_REQUIRED and keep Release 4 ungenerated. Phase 10D stops here for review.
