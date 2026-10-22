# Phase 9 — Catalogue compiler, import and sync repair

Date: 2026-10-04. Branch: `fix/product-master-audit`.

**Implementation and isolated proof are complete; unconditional closure is withheld because the production account SQLite checksum changed while an independently running app held it open for writing.** The final full suite passed **247/247 tests**. Flutter analyzer reports **51 pre-existing diagnostics, zero new diagnostics**. No live catalogue import, Phase 8 migration, production query cleanup or Firestore write was performed by this work. Changes are uncommitted for review.

## Preflight and safety exception

- Phase 8 was committed at `a23ef4bdf547cdc0e833b0abcbe1640cf9de3696` (`test(product-master): design and prove catalogue migration safety`). The requested branch was active and the initial working tree was clean.
- Baseline workspace suite: **200/200 passed**. Baseline analysis: **51 diagnostics** (5 warnings, 46 infos, zero errors).
- Production checksums were captured before inspection. Inspection used read-only SQLite connections (`mode=ro`/`OpenMode.readOnly`, with `query_only`); the new migration/import/sync tests use temporary SQLite databases and controlled REST doubles.
- An existing production read-only audit encountered `SQLITE_BUSY`. `lsof` showed the already-running `testflutt` process **PID 92086**, handle **21u**, holding the account database read/write. Its executable was `build/macos/Build/Products/Debug/testflutter.app/Contents/MacOS/testflutter`, with process start time Sun Oct 4 14:56:40 2026. This work did not launch that application.
- Comparing the captured inventories found **zero changed rows** in categories, subcategories, template rows and catalogue releases. **40 sync_queries rows changed**: `lastSyncedAt` in 40, `lastAttemptAt` in 40, and `cursor` in 39. Captured query specifications, keys and active states did not change. This evidence is consistent with concurrent application sync; the running process's activity was not controlled by these tests.
- The original checksum is retained below. The database was not restored or rewritten to conceal the discrepancy. The user was asked to close NubiBill for verification; no reply had arrived when this report was prepared.
- Two existing read-only audit tests now set a connection-local 5-second busy timeout and `query_only=ON`. These pragmas do not mutate the database; the final suite passed with them.

**Production-unchanged acceptance is not satisfied for the whole observation interval.** Agent access remained read-only, but the observed account file changed externally. Review this exception before treating Phase 9 as closed.

## Sources capable of affecting catalogue state

| Source/path | Capability and disposition |
| --- | --- |
| `lib/data/catalogue/system_catalogue_metadata.dart` | Previously combined SQLite correction and heuristic defaults. Now a pure versioned compiler: fixed IDs, explicit profile rules, options/units/templates, no database writes. |
| `lib/data/catalogue/catalogue_contract.dart` | Single schema/compiler/release compatibility contract; document identity, collision/reference/metadata validation, frozen generated option/unit identities and content fingerprint. |
| `lib/data/catalogue/system_catalogue_snapshot.dart` | Sole validated PAINT SYSTEM snapshot installation path: one transaction for catalogue rows, broad-query cursors and final installed-release marker. |
| `lib/data/local/local_data_source.dart` | Generic remote-row upsert/materialization and complete-query reconciliation; used inside the snapshot transaction. BUSINESS/pending rows protected by snapshot collision validation. |
| `lib/data/local/local_database.dart` | SQLite table/bootstrap/schema-upgrade paths, including durable `sync_queries` metadata. No live schema migration was run by this work. |
| `lib/data/services/firestore_rest_service.dart` | REST encoding/decoding, release/page queries and remote write primitives. New tests substitute controlled clients; no live client writes were invoked. |
| `lib/data/sync/sync_engine.dart` | Remote release checks, staged catalogue reads, version/cursor application, outbox push, retries and lease. PAINT SYSTEM pulls now go through the validated atomic release pipeline. |
| `lib/data/services/offline_firestore_service.dart` | Local BUSINESS writes/outbox and query registration/bootstrap/prerequisite keys. All query-key call sites now share the registry contract. |
| `lib/data/sync/sync_query_registry.dart` | Deterministic query identity/upsert, protected legacy reference audit, explicit maintenance reconciliation. Does not rewrite legacy IDs. |
| Product/business repositories and existing ID generator | Explicit BUSINESS catalogue creation and local Product/Variant persistence remain separate from SYSTEM compiler identities. Product/Variant/SKU identity generation was not changed. |
| `test/fixtures/system_catalogue_v3.json` | Archived historical compiler input with literal identities; unchanged. Contains malformed duplicate option groups, now rejected. |
| `test/support/catalogue_import_fixture.dart` | Explicit test-only successor input excluding 11 documented redundant option IDs, used only for isolated success/regression proofs. |
| `tool/refresh_system_catalogue_test.dart` | Existing explicit maintenance entrypoint can pull/import a live snapshot when deliberately invoked; it was **not run**. It now inherits snapshot revision/collision safeguards. Its historical version-3 expectation is deferred. |
| `tool/repair_brush_catalogue.py` | Historical brush planner formerly had an unversioned remote apply path. `--apply` now exits with a diagnostic before database/remote access; remote-writer code removed. |
| `tool/plan_product_template_corrections.py` | Read-only correction planner now emits review-only artifacts requiring a versioned release. It does not publish corrections. |
| `tool/catalogue_phase8.py` and Phase 8 mapping artifacts | Existing read-only inventory/isolated migration design; not changed, approved or executed against production. |

No upstream live seed/release publisher implementation is supplied in this repository. External publishers must produce the validated versioned manifest; their deployment and Firestore publication were not exercised here.

## Compiler and identity contract

- **Schema revision = 1; compiler revision = 6; historical data release = 3.** Data release versions and compiler revisions are independent. A supported future data release must declare schema 1/compiler 6. Unsupported, lower or ambiguous compiler provenance fails with diagnostics.
- Compiler revision 6 supersedes the observed historical correction revision 5, but `localMetadataRevision` is **not** inferred to be compiler provenance. Installed version 3 with correction metadata 5 and no declared compiler/fingerprint cannot be overwritten by a same-version regeneration; a reviewed newer versioned release is required.
- Legacy version-3 compatibility is limited to the declared fresh canonical manifest. Already-compiled metadata is validated and retained, rather than regenerating corrected defaults on repeated import. A compiled manifest must declare its schema and supported profile.
- Removed category-name `contains('wood')` and other category/subcategory display-name profile guessing, branch-order masking, unknown-category fallback and name-based category/subcategory ID rebinding. Profiles use immutable category/subcategory IDs or explicit supported metadata/profile identifiers. Unknown/conflicting profiles and parent conflicts fail safely.
- Canonical SYSTEM category/subcategory IDs are retained from the declared manifest. Generated controlled options/units use frozen literal IDs. Generated template IDs use immutable subcategory/attribute identity. None is derived from insertion order or mutable display formatting. Document ID must equal payload ID; only an absent payload identity may be filled from the document identity.
- All eight current Metal & Wood Enamels subcategory IDs are covered. `SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SATIN_ENAMELS` selects **SATIN_ENAMEL**, with Satin finish. The other seven use the explicit ENAMEL family. These resolve with Metal/Wood surface, Multiple Ready Colours and MTO, without generic Wood/Clear/PU-Thinner leakage. Broader subcategory chemistry/template correction remains deferred.
- Current Ceiling Paints and Basement Waterproofing IDs generate only their declared canonical template groups. Historical orphan IDs are not attached, auto-migrated or used to create parallel canonical records.
- Generated metadata agrees with the existing ProductTemplateResolver contract. Compiler `productColour` placement is PRODUCT; existing colour conditions and other intended placement rules remain validated through the actual resolver. Neither resolver, the unit engine, Product UI nor repository identity logic was rewritten.
- Deterministic logical fingerprint: **FNV-1a 64-bit**, used for change detection, not authentication. Documents/maps are ordered deterministically; timestamps and bookkeeping are ignored. Semantically ordered lists, including default-rule priority, are preserved. Same semantic release produces the same fingerprint; changed defaults/priority are detected.

## Atomic and idempotent import proof

Import validates completeness, revision, canonical identities, parent references, attributes/options/templates, conditions/defaults and collisions before persistence. Installed-state checks run inside the transaction. Catalogue rows are applied first; broad SYSTEM cursor metadata participates in the same transaction; the installed release marker is the final row write before commit.

| Scenario | Proof/result |
| --- | --- |
| First supported import | Succeeds in isolated SQLite, installs declared schema/compiler/version and fingerprint. |
| Exact same release imported twice | Complete logical database snapshot A equals B, including timestamps, query registry and outbox; second import is a true no-op. |
| Repeated/duplicate category, subcategory, template or option identities | Rejected before mutation; no parallel records. Same-parent normalized-name collision also rejects name-based rebinding. |
| Failure after `product_attributes` writes | Forced callback exception restores all prior rows, release, cursors and outbox. |
| Failure immediately before marker | All catalogue/query changes roll back; previous marker survives. |
| Failure immediately after marker write, before commit | Marker and all related row/cursor changes roll back together. |
| Older/unsupported schema/compiler or future installed compiler | Rejected; existing state remains intact. |
| Same data version with changed content | Rejected as immutable-release violation; supported explicitly newer corrected release retains its supplied values. |
| BUSINESS records/options/templates/outbox | Remain byte-for-byte unchanged through SYSTEM imports. Same-ID SYSTEM/BUSINESS or pending collision rejects atomically. |
| Product/Variant/SKU/barcode/history | Isolated import and alias metadata preserve these rows byte-for-byte. No alias migration occurs. |

Failure injection uses the snapshot's optional transaction-scoped `failureProbe(stage, executor)` and REST doubles that fail controlled page requests. No actual storage was corrupted.

The archived version-3 fixture contains **11 exact duplicate option groups**: six `brushType` and five `bristleMaterial` `SYS_OPT_*` records duplicate `SYS_OPTION_*` records. It remains unchanged and has a rejection test. Isolated success fixtures explicitly exclude those eleven IDs through the test helper; this is neither runtime silent deduplication nor approval of any Phase 8 mapping. A malformed live release now fails safely and needs a reviewed successor release.

## Release sync, cursor and quota behavior

- Automatic checks use a durable **15-minute** freshness window. Explicit catalogue refresh can request a lightweight marker check, but an unchanged version still causes **zero full catalogue pull**. The behavior survives engine restart.
- A newer compatible published PAINT release stages a complete normalized snapshot and commits only after validation. A consistent server read time is retained across pages/collections. Failed page/import leaves installed release and catalogue cursor/revision state unchanged; diagnostic attempt/error metadata may be recorded.
- A release may supply positive stable `collectionRevisions`. When they are unchanged, local SYSTEM collection content is retained; only changed collections are fetched. The isolated 3→4 release test pulls the marker and changed options collection only. Legacy release 3 without revision metadata requires a bounded full snapshot when its release changes; it is not repeatedly rescanned while unchanged.
- PAINT SYSTEM data cannot bootstrap without a supported published release. Narrow/document/unfiltered queries cannot bypass the versioned SYSTEM import safeguards. Other non-PAINT/unversioned bootstrap catalogues retain ordinary collection cursor behavior; the PAINT compiler does not guess their semantics.
- Cursor advancement now correctly decodes Firestore filter values when recognizing broad SYSTEM queries. Cursor writes and installed marker are atomic with catalogue rows.
- `checkCatalogue` requests catalogue pull without Product push. Outbox-only push makes no catalogue pull. Product form metadata/field-dependent reads remain local, with zero Firestore reads and zero query registration in the explicit proof.
- No 45-second full-collection catalogue polling was introduced. The existing 30-second lease heartbeat is local SQLite coordination, not a catalogue read.
- Quota/resource exhaustion persists backoff: initial **one hour**, exponential doubling, maximum **24 hours**. Both RESOURCE_EXHAUSTED spelling forms are recognized; exception codes are stored even when the message is opaque. Manual refresh cannot bypass quota backoff. Local SQLite remains available.

## Query identity, isolated cleanup and protected legacy references

Canonical query keys recursively order map keys and normalize/deduplicate AND filters; equivalent query registration upserts one durable identity. Duplicate maintenance keeps a conservative oldest/NULL cursor to prefer safe rereading over skipped records. Bootstrap/prerequisite lookups use the same key function.

Explicit `reconcile` maintenance is proven only on temporary databases. It merges equivalent registrations conservatively and deactivates safely covered narrower SYSTEM queries only when an initialized broad query covers them. Specifications remain available; protected legacy specifications are preserved byte-for-byte. This maintenance is not installed as automatic on-open live cleanup and was not executed on production.

The committed Phase 8 protected set contains **64 IDs**; it is a guard list, not approved alias mappings. Registry audit includes inactive queries; new registration or active sync with protected legacy references is rejected. Those findings remain blockers for any later reviewed migration: no silent ID substitution or approval occurs here.

Read-only preflight inventory: **195 queries**, **50 active**, **zero equivalent duplicate groups**, **10 legacy-reference queries, all inactive**. Five distinct protected IDs appear:

- `PM_SUBCATEGORY_ce0bf39843417fca`
- `SYS_CATEGORY_ACCESSORIES`
- `SYS_CATEGORY_EXTERIOR_WALL_PAINTS`
- `SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH`
- `SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS`

Full query keys, specifications, activity/cursor/error state, protected IDs, installed release metadata and revision distributions are retained in [docs/phase9-query-audit.json](docs/phase9-query-audit.json). The installed PAINT release is version 3, correction metadata revision 5, with no declared schema/compiler provenance. This finding is intentionally surfaced as a safe-import blocker, not corrected on live data.

## Verification

| Check | Result |
| --- | --- |
| Preflight workspace suite | 200 passed. |
| Final workspace `flutter test --reporter expanded` | **247 passed, zero failed**, approximately 27 seconds. |
| New dedicated Phase 9 proofs | **47 tests**; compiler/import/query/sync safety plus actual resolver regression. Individual results follow below. |
| `flutter analyze` | **51 existing diagnostics: 5 warnings, 46 infos, zero errors. Exit 1**, as at baseline. Normalized baseline/final diagnostic sets match exactly: zero added, zero removed. |
| Full catalogue selector proof after isolated import | Every active imported subcategory accounted for by actual selector reconciliation. |
| Full catalogue placement/orphan proof after isolated import | Zero PRODUCT/VARIANT placement intersections; zero newly generated active orphan template groups. |
| Colour, units, repository validation and edit identity/atomicity | Existing suites pass in the final full run. |
| Formatting/patch integrity | `git diff --check` passed. |

Logs captured locally: `/private/tmp/phase9-baseline-tests.log`, `/private/tmp/phase9-baseline-analyze.log`, `/private/tmp/phase9-isolated-tests.log`, `/private/tmp/phase9-full-tests.log`, `/private/tmp/phase9-final-analyze.log`. These are local verification evidence, not committed deliverables.

## Production checksums (SHA-256)

Paths are under `/Users/sksuman/Documents/`.

| File | Before | After | Result |
| --- | --- | --- | --- |
| `nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db` | `e0f621fc7271325e8378b4d6b677c98e1d9ce07d5c028d2b990612978a870580` | `5d7ea26300c6542932cf4cfdf9617ed1a68a74e4866470d9723b9254c87c7d95` | **Changed during concurrent app activity** |
| `nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak` | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | Unchanged |
| `nubibill-test1-bcebe-public-config.db` | `20cf0f320c9cbe6a62bcf8e6d1cc4e4a190bb13060522bbd8286d42e03be23e0` | `20cf0f320c9cbe6a62bcf8e6d1cc4e4a190bb13060522bbd8286d42e03be23e0` | Unchanged |

All three file sizes are unchanged. The captured catalogue-table comparison is limited to categories, subcategories, template rows and releases; it does not prove every production table unchanged. No broader unchanged claim is made for Product/history rows in the concurrently modified production file. Identity preservation is proven in isolated tests.

**Zero Firestore writes by agent commands/tests.** New sync tests use controlled doubles and isolated local persistence. The running external application's network activity was not monitored, so zero global Firestore activity during the entire interval cannot be certified. No seed script, live catalogue import/deactivation, live Phase 8 mapping, production query cleanup or Product/Variant identity rewrite was executed.

## Files modified or added

- `lib/data/catalogue/catalogue_contract.dart` — new versioned validation/identity/fingerprint contract.
- `lib/data/catalogue/system_catalogue_metadata.dart` — pure deterministic explicit-profile compiler.
- `lib/data/catalogue/system_catalogue_snapshot.dart` — atomic guarded installation and failure-injection seam.
- `lib/data/sync/sync_query_registry.dart` — new query canonicalization, protected-reference audit and explicit isolated maintenance.
- `lib/data/sync/sync_engine.dart` — release pipeline, incremental collection revisions, durable checks/backoff, cursor safety and push/pull separation.
- `lib/data/services/offline_firestore_service.dart` — registry registration and consistent bootstrap/prerequisite keys.
- `test/catalogue_compiler_sync_test.dart` — 47 direct isolated proofs.
- `test/support/catalogue_import_fixture.dart` — explicit test-only successor to malformed archived fixture.
- `test/system_catalogue_test.dart` — pure compiler/atomic importer contract regression updates.
- `test/dynamic_product_master_acceptance_test.dart` — shared isolated successor fixture loader.
- `test/product_placement_full_catalogue_test.dart` — read-only timeout/query-only pragmas.
- `test/product_selector_reconciliation_test.dart` — read-only timeout/query-only pragmas.
- `tool/repair_brush_catalogue.py` — disables unversioned remote apply and emits review-only planning.
- `tool/plan_product_template_corrections.py` — explicit review-only/versioned-release requirement.
- `docs/phase9-query-audit.json` — complete protected query findings and production safety evidence.
- `phase9.md` — this report.

## Review disposition

Compiler determinism, repeat-import idempotence, rollback, BUSINESS preservation, release-driven incremental pull, query deduplication, legacy detection and quota protection pass isolated proofs and full workspace regression. Phase 8 approvals remain false; no production cleanup or bulk template correction is authorized by these changes.

The production checksum exception prevents an unconditional “all acceptance criteria met” conclusion. Review the completed changes and concurrent-app evidence. A stable read-only verification interval is needed for production-safety closure; it would not erase the original observed change. No subsequent phase has begun.

## Dedicated Phase 9 case results

| Case | Result |
| --- | --- |
| 1. compiler identical input is pure and generates identical IDs/payloads | PASS |
| 2. compiler input document order does not affect output | PASS |
| 3. logical fingerprint ignores timestamps and document order but detects defaults | PASS |
| 4. all current Metal & Wood Enamels IDs use explicit enamel profiles; Satin avoids Wood/Clear/PU defaults | PASS |
| 5. display formatting cannot change profile or generated IDs | PASS |
| 6. document ID equals canonical payload ID in every compiler collection | PASS |
| 7. document/payload mismatch fails before mutation | PASS |
| 8. unknown and conflicting profiles fail with diagnostic rather than guess | PASS |
| 9. Ceiling and Basement compile current IDs without attaching old orphan groups | PASS |
| 10. archived malformed v3 option duplicates fail safely without alias migration | PASS |
| 11. first import succeeds; identical second import has exact same database state | PASS |
| 12. duplicate product_categories rejected without creating parallel records | PASS |
| 13. duplicate product_subcategories rejected without creating parallel records | PASS |
| 14. duplicate subcategory_attribute_templates rejected without creating parallel records | PASS |
| 15. duplicate product_attribute_options rejected without creating parallel records | PASS |
| 16. same-name active record under same parent rejects name-based ID reassignment | PASS |
| 17. BUSINESS category, corrected option, override and outbox survive SYSTEM import | PASS |
| 18. SYSTEM/BUSINESS same document ID collision fails atomically | PASS |
| 19. forced import failure at product_attributes preserves prior rows, release, cursors and outbox | PASS |
| 20. forced import failure at before_release_marker preserves prior rows, release, cursors and outbox | PASS |
| 21. forced import failure at after_release_marker preserves prior rows, release, cursors and outbox | PASS |
| 22. older compiler and unsupported schema cannot overwrite installed newer state | PASS |
| 23. same release with changed defaults is rejected; corrected explicit newer release remains unchanged | PASS |
| 24. full isolated catalogue resolves with zero PRODUCT/VARIANT placement intersections and no active orphan groups | PASS |
| 25. unchanged release makes zero full catalogue pulls and survives engine restart | PASS |
| 26. newer release triggers required pull and installs only after success | PASS |
| 27. failed release pull leaves installed marker and all catalogue cursors unchanged | PASS |
| 28. quota cooldown serves SQLite and blocks repeated remote checks | PASS |
| 29. catalogue-only check never pushes Product outbox and outbox-only push never pulls catalogue | PASS |
| 30. Product form metadata and repeated field-dependent reads make zero Firestore reads or query registrations | PASS |
| 31. equivalent query specs dedupe despite field/filter/key ordering and duplicate filters | PASS |
| 32. isolated registry reconciliation preserves legacy specs and conservatively dedupes cursors | PASS |
| 33. stable collection revisions fetch only changed collections; failed changes leave revisions/cursors intact | PASS |
| 34. automatic catalogue checks use durable freshness; manual check still does no unchanged full pull | PASS |
| 35. RESOURCE_EXHAUSTED with opaque message persists quota backoff that manual refresh cannot bypass | PASS |
| 36. legacy admin unversioned apply cannot make Firestore writes | PASS |
| 37. explicit isolated registry cleanup deactivates safely covered queries without deleting specifications | PASS |
| 38. selector reconciliation accounts for every active imported subcategory | PASS |
| 39. catalogue imports and alias metadata preserve Product, Variant, SKU, barcode and historical rows byte-for-byte | PASS |
| 40. invalid parents, active orphan templates and condition metadata fail before writes | PASS |
| 41. legacy correction revision is not inferred as compiler provenance or overwritten by same-version defaults | PASS |
| 42. installed future compiler revision blocks older import even at same data version | PASS |
| 43. compiled manifest still rejects unknown profile and undeclared schema | PASS |
| 44. PAINT SYSTEM rows without a published release cannot bootstrap unversioned metadata | PASS |
| 45. unfiltered catalogue query cannot bypass validated SYSTEM release import | PASS |
| 46. incomplete compiler input and incompatible remote marker fail with diagnostics before cursors advance | PASS |
| 47. logical fingerprint preserves priority order of default rules | PASS |
