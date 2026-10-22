# Shared Add / Edit Product workflow

## Changes

Normal entry uses the existing `_StructuredProductFormPage` for Add, Edit and Duplicate. It contains Product Identity, Product Details, Sellable Variants / SKUs and Product Image sections. No second product schema or legacy edit dialog was introduced.

`Configure for this Business`, `Add Business Attribute` and their configuration dialog were removed from the product-entry widget. Repository/controller BUSINESS attribute configuration APIs remain intact for a future Settings location. Permission-controlled master creation and legitimate Add Option actions remain; paired measurement-unit fields also retain Add Option where allowed.

## Measurement and selling units

Previously `_save` copied the dynamic `unit` attribute into `baseUnitId`/`unitId` and inferred `baseQuantityPerCommercialUnit` from `packSize`. A Brush template with `unit=inch` could consequently treat inches as inventory quantities.

Dynamic measurements now remain in `attributeValues`. An optional `measurementUnitAttributeId` on an attribute definition/template links its numeric value to a second dynamic attribute. The form renders the two controls together at the same PRODUCT/VARIANT level, using catalogue options. It does not infer brush definitions or default selling units from names.

`How is this item sold?` separately collects the selected selling unit:

- Individual item: `commercialUnitId=baseUnitId=selected selling unit`, conversion `1`; unnecessary conversion inputs are hidden.
- Pack / Box / Carton: collect selling unit, Contains and unit of the contents; display `1 Pack = 12 Piece` using the selected local master names. Both units and the positive conversion remain the existing persisted fields.

Existing packaging mode is reconstructed from the saved unit IDs and conversion, and saved pack-unit/measurement values are preserved. Switching the mode is an explicit user change. No hardcoded Piece/Pack ID or size-derived conversion is applied.

## HSN, tax and other fields

The single HSN / SAC field writes canonical `product.hsnCode`. Blank/missing canonical HSN reads legacy `attributeValues.hsnCode` as fallback. The legacy dynamic HSN control is suppressed, and structured saves remove that duplicate from dynamic values. Canonical HSN is validated as 4–8 digits; GST uses the existing 0–2800 basis-point range. A required legacy HSN template validates the canonical field. New variants inherit canonical HSN and default GST; editing propagates canonical HSN rather than creating an independent dynamic value.

Description is in Product Details. Dynamic controls retain data types, levels, order, required/default behavior and option permissions. Template changes retain values, including attributes outside the new template, rather than discarding them. Existing SKU/variant IDs stay unchanged. Unsaved variants can be added/removed in both Add and Edit; new SKUs use the existing business sequence in the atomic transaction. Missing legacy SKU sequences produce a controlled error rather than restarting allocation at a duplicate code. Barcode input is available during creation and editing, with local business-scoped collision checks.

Price editing uses existing variant fields. Add does not invent price/stock-opening transactions or a second stock source.

## Images

The image section has a larger icon-based preview, loading/error handling, URL entry, replacement and removal. Existing `imageUrl`/`productImage` compatibility remains. Choose Image and Find Image are visible but disabled because the repository has no configured media upload or image-search provider. No Firebase Storage, image bytes/base64, scraping or automatic external-image assignment was added. Provider integration is still outstanding.

## Persistence

Reads continue through repositories to SQLite. Existing atomic writes commit products, variants, sequence updates and sync outbox entries together. Firestore REST synchronization remains asynchronous and conflict protected. No SQLite migration is needed: the catalogue metadata is already stored in JSON payloads and product conversion fields already exist. Schema version remains **2**.

## Brush catalogue handoff

`tool/brush_catalogue_seed_manifest.json` is an administrator reference, not runtime catalogue data or an automatic seed script. It specifies six SYSTEM definitions, six Brush template rows and eighteen option records:

| Attribute | Level | Type | Options / metadata |
| --- | --- | --- | --- |
| Brush Type | PRODUCT | SELECT | Flat, Angle, Round, Wall Brush, Varnish Brush, Utility Brush |
| Bristle Material | PRODUCT | SELECT | Synthetic, Nylon, Polyester, Natural Bristle, Mixed Bristle |
| Handle Material | PRODUCT | SELECT | Plastic, Wood, Rubber Grip |
| Suitable Surface | PRODUCT | MULTI_SELECT | Wall, Wood, Metal |
| Brush Size | VARIANT | NUMBER | Required; `measurementUnitAttributeId=brushSizeUnit` |
| Size unit | VARIANT | SELECT | Required; inch; default inch |

The collections are `product_attributes`, `product_attribute_options` and `subcategory_attribute_templates`; all suggested records have `scopeType=SYSTEM`, `status=ACTIVE`, `catalogueId=PAINT_V1`. Before seeding, reuse matching existing IDs and replace `__EXISTING_BRUSH_SUBCATEGORY_ID__` with the actual Brush subcategory document ID. Verify the locally synchronized Piece unit; Pack/Box/Carton units are needed only for packaged selling. Do not seed these options in Flutter or from normal business entry.

The production/local catalogue was not available for a live inventory of existing Brush definitions. Therefore this manifest is the exact required record specification, not a verified claim that every listed record is missing in production. No SYSTEM records were written during this task.

## Files

Modified:
- `lib/data/models/product_attribute.dart`
- `lib/data/repositories/product_repository.dart`
- `lib/presentation/products/product_pages.dart`
- `lib/presentation/products/product_thumbnail.dart`
- `test/offline_sync_test.dart`
- `test/product_repository_test.dart`
- `test/product_thumbnail_test.dart`
- `PRODUCT_MANAGEMENT_CHANGES.md`

Created:
- `test/product_entry_form_test.dart`
- `tool/brush_catalogue_seed_manifest.json`
- `PRODUCT_ENTRY_WORKFLOW.md`

## Validation

`flutter test`: **38 passed**, including actual Add/Edit widget interactions, measurement versus Piece save payloads, HSN appearing once, prefilling, preservation of other variants/hidden attributes/images, icon placeholders, and real SQLite offline creation/restart/edit/new-SKU/outbox synchronization against a controlled REST remote.

`flutter analyze`: **0 errors**, **44 existing diagnostics** (5 warnings, 39 infos). It exits nonzero because those pre-existing diagnostics remain. No new product-entry diagnostics remain. `flutter build macos --debug` succeeded. `git diff --check` is clean. No legacy `_ProductFormDialog` usage remains.

Live production Firestore synchronization and the user's running application were not exercised; widget/SQLite tests provide the stated coverage. Media-provider integration and central catalogue verification/seeding remain external follow-up work.
