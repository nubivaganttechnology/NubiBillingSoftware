# Product Master correction

The live account SQLite catalogue was refreshed from **catalogueVersion 1 to 3**. The running macOS app was restarted with its original Firebase configuration and loaded the updated code successfully. Purchase and Inventory modules were not changed for this correction.

## Catalogue audit and cause

SQLite was inspected before widget changes. Its schemaVersion was 3, but its catalogueVersion was **1**; catalogueVersion 3 did not exist locally. Schema version and catalogue release version are separate.

The cached release and SYSTEM categories were from the October 2 catalogue. Active SYSTEM sync queries had HTTP 429 quota failures, so the October 3 normalized release, inactive v1 records and new templates had not reached SQLite. The published remote release was already **3**. Its catalogueId remains `PAINT_V1`; this stable ID does not mean its active version-2 records are obsolete. Incremental version 3 retains normalized version-2 members.

| SQLite collection | Before: active SYSTEM | After: active SYSTEM | After: inactive SYSTEM |
|---|---:|---:|---:|
| product_categories | 11 | 22 | 10 |
| product_subcategories | 49 | 114 | 49 |
| product_attributes | 21 | 37 | 3 |
| product_attribute_options | 16 | 139 | 5 |
| subcategory_attribute_templates | 511 | 1598 | 511 |
| product_catalogue_releases | 1, version 1 | 1, version 3 | 0 |
| units | 5 | 25 | 0 |

Old SYSTEM choices including Accessories, Interior Wall Paints, Metal Paints and Floor Coatings are inactive. **Paint is an existing BUSINESS category**, so it remains available as custom data. The pending BUSINESS “Interior Wall Coatings” record remains stored and queued; the picker offers the canonical SYSTEM choice once for that name. Business-scoped categories, subcategories, units and pending options were preserved.

The maintenance import took a SQLite backup at `/tmp/nubibill-catalogue-v3/account-before-catalogue-1791022676719.db` and passed equality checks for business catalogue rows and the sync outbox. Before/after summaries are in `product-master-catalogue-before.json` and `product-master-catalogue-after.json`.

## Sync and metadata

SYSTEM catalogue downloads are staged and committed together. A failed page keeps the prior release, rows and cursors intact. Complete snapshots mark missing synced SYSTEM catalogue records inactive; pending records and BUSINESS rows are protected. SYSTEM reads use the release check's server read time to keep collections consistent during concurrent publication.

The release fingerprint includes a local metadata revision. Version-3 ingestion supplies missing Colour Type/Base Code definitions, controlled coat/thinner options, conditional visibility/required rules, technical sections, measurement links, unit restrictions and packaging units. These supplements are applied to SQLite during ingestion. The remote release remains version 3. The migration is restricted to release 3; future releases can supply their own authoritative metadata. Repeated imports preserve business options and recreate applicable supplements consistently.

The existing event-driven release mechanism remains in use. No catalogue polling timer or Firestore call was added to the form. Once cached, masters, options and templates are read through the SQLite-backed service.

## Form behaviour

Brand / Company → Category → Subcategory selects one dynamic template. An incompatible category change clears the subcategory. Template changes remove unsupported attributes, preserve applicable user values and replace previous template defaults with the new defaults.

Persistent labels and searchable SELECT controls come from metadata. TEXT, NUMBER, SELECT, MULTI_SELECT and BOOLEAN use the corresponding renderer; numeric bounds, conditional requirements and technical sections also come from metadata. Multi-select fields use searchable chips. Measurement fields pair with their declared measurement unit attribute.

The sections are Product Identity, Product Specifications, Sellable Variants, collapsed Technical Details, and Product Image. Desktop fields use two columns and mobile fields use one. Technical Details contains only fields supported by the selected template.

| Colour Type | Visible colour fields | Required fields |
|---|---|---|
| Ready Colour | Shade / Colour, Shade Code, Colour Family | Shade / Colour, Colour Family |
| Tintable Base | Base Type, Base Code | Base Type |
| Clear / Transparent | Colour and base fields hidden | No shade or base required |
| Not Applicable | Colour and base fields hidden | No shade or base required |

Colour Type is a required variant SELECT for templates supporting colour/base attributes. Base Type also appears for Ready Colour when a template explicitly requires it. Its hint is “Select the tinting base supplied by the manufacturer”, with White, Pastel, Deep, Accent, Neutral and Clear Base options. Existing applicable shade/base values can infer Colour Type through metadata default rules. Changing colour type clears irrelevant values; save validation ignores hidden attributes.

Finish / Sheen is a populated SELECT with an empty selection hint. Recommended Coats and Dilution / Thinner Type are controlled SELECTs in Technical Details. Colour Family supports permission-gated business options.

| Product classification | Normal unit/default | Compatible alternatives or measurement |
|---|---|---|
| Paint/coatings, primers, enamels, wood finishes, waterproofing, admixtures | Litre | Compatible volume/container units |
| Putty & Surface Preparation | Kilogram | Gram, Bag |
| Adhesives & Tiling | Kilogram | Gram, Bag, Litre |
| Sealants & Repair | Cartridge | Tube, Pouch, Kilogram, Litre |
| Brush / Roller | Piece | Size: inch/mm/cm; selling: Piece/Pack/Box/Set |
| Sandpaper & Abrasives | Sheet | Compatible pack units |
| Masking Tape | Roll | Compatible pack units |
| Wall Coverings | Roll | Dimensions: Metre/cm/mm; compatible sheet/area units |

Cartridge, Tube, Pouch, Bottle, Jar, Drum and Bag were added to the local SYSTEM unit catalogue during ingestion. Unit choices are restricted by template metadata. Brush templates contain populated Brush Type, Bristle Material and Handle Material SELECTs and numeric Brush Size, without paint attributes. Putty, wallpaper and sealant templates have their own fields and defaults.

Simple SKUs need their template's pack/selling unit. An optional “Use pack / unit conversion” checkbox reveals the conversion controls. Variant GST inherits product GST; “Override GST” reveals the extra field. Existing explicit overrides are retained. Measurement units and selling units remain separate.

Purchase Rate, Selling Price and MRP inputs and save payload keys were removed from Add/Edit Product. Stored legacy prices were retained; repository tests verify edits omitting prices preserve those values.

“+ Add option” appears only for an eligible attribute and authorized user. The existing controller checks master permission; the repository creates a BUSINESS option through SQLite and sync_outbox. The form reloads the local template and selects the new option immediately.

## Validation and verification

Product name, valid brand/category/subcategory, required visible attributes, variants, units, positive applicable pack/measurement values, barcode uniqueness and generated SKU uniqueness are validated. Repository validation uses the same visibility/required metadata as the form and removes hidden/unsupported attribute values before saving.

The targeted regression suite passed **68 tests** covering catalogue replacement, partial-download rollback, repeat imports, pending business data, offline reads/options, colour requirements, paint-to-brush interaction, unit defaults, legacy prices, SKU/barcode validation, responsive layouts and Products/Purchase clicks. The live database import verification passed separately.

Analysis of the changed Product Master implementation, tests and maintenance tool reported **No issues found**. Full-project `flutter analyze --no-pub` reported **44 existing issues** in unchanged AppController, Procurement and Storage files: 5 warnings and 39 informational diagnostics, with no errors. Those modules were left outside this task's scope.

## Changed files

| File | Change |
|---|---|
| `lib/data/catalogue/system_catalogue_metadata.dart` | Versioned catalogue metadata migration and release fingerprint |
| `lib/data/catalogue/system_catalogue_snapshot.dart` | Guarded complete SYSTEM snapshot import |
| `lib/data/local/local_data_source.dart` | Inactivate obsolete SYSTEM catalogue rows while protecting pending data |
| `lib/data/models/product_attribute.dart` | Metadata for conditions, defaults, sections, roles and numeric bounds |
| `lib/data/repositories/product_repository.dart` | Canonical master choices, metadata/options merging, classification and conditional validation |
| `lib/data/sync/sync_engine.dart` | Atomic catalogue publication and consistent server snapshot |
| `lib/presentation/products/product_pages.dart` | Simplified shared Add/Edit form, conditional fields, units and dialog/controller lifecycle fixes |
| `test/system_catalogue_test.dart` | Catalogue and normalized form/save acceptance tests |
| `test/fixtures/system_catalogue_v3.json` | Representative published v3 records and obsolete v1 records |
| `test/offline_sync_test.dart` | Supported dynamic attribute fixtures and legacy-price preservation check |
| `test/product_entry_form_test.dart` | Price removal, responsive form and controller lifecycle regression checks |
| `tool/refresh_system_catalogue_test.dart` | Explicit maintenance entry point with backup, lease and preservation checks |
| `docs/product-master-catalogue-before.json` | Initial SQLite audit summary |
| `docs/product-master-catalogue-after.json` | Live SQLite version-3 audit summary |
| `docs/product-master-correction.md` | Findings, behaviour, validation and file list |

Earlier click fixes in this conversation also changed `lib/presentation/dashboard/admin_dashboard_page.dart` and added `test/dashboard_navigation_test.dart`. Existing recurring-work audit changes to connectivity code/tests were preserved.
