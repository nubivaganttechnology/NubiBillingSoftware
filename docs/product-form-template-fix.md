# Metadata-driven product form correction

The form renders product and variant fields using attributeLevel and dataType. No product, brand or subcategory name is checked by Flutter UI code.

## Changes and causes

| Issue | Cause and resolution |
| --- | --- |
| Stale Usage after changing template | UI used putIfAbsent and retained unrelated values. Loaded templates now reconcile applicable attributes, remove invalid options, apply the selected defaults, and clear removed attributes. Changed catalogue defaults are also reconciled on sync. |
| Inconsistent category/subcategory | Existing category selection clears subcategory, and repository validates parent-filtered masters on create/edit. Fixed picker lifecycle so typing a replacement selection does not recreate the input and lose the search. |
| Interior remains selectable for an Exterior template | Synced SYSTEM defaults are correct, but global Usage options apply to every template. Repository now honors an explicit template options restriction. Nine SYSTEM template corrections are supplied. |
| Free text for controlled fields | SYSTEM definitions baseType, colourFamily, segment and dilutionType are TEXT and have no options in the synced snapshot. These need catalogue-owner configured master options and SELECT metadata; widget code deliberately does not invent options. Usage, Surface, Finish and Unit already have controlled definitions. |
| Missing new-SKU prices | UI hid fields and omitted values for new variants; repository create/new-variant allowlists discarded prices. All three prices now render, validate and persist on create/edit/copy. |
| GST inheritance | New variants accept blank GST to inherit product Default GST. Saved records carry gstOverride so subsequent edits preserve inheritance; legacy records without that flag retain their existing rate. Effective GST is still stored for existing billing consumers. |
| Ambiguous selling field | Renamed to Selling Mode; explains that it controls the existing conversion. Pack size and its physical unit remain distinct from Selling Unit and inventory conversion. Pack unit resolves the template unit against the existing unit master. |
| Stale saved attributes | Removed _savedAttributes merge on save. Applicable untouched values remain; inapplicable attributes are removed from the form's saved maps. |
| Copy identity | Variant copy and product copy clear SKU identity and barcode; existing repository sequence generates new SKU on save. |
| Validation | Required multi-select participates in Form validation; required pack size must be positive. Invalid options, nonfinite numbers, negative prices and invalid GST are rejected. Existing business-scoped barcode/SKU protections remain. |
| HSN | Product-level input searches existing HSN master cache and permits validated 4–8 digit codes. Snapshot contains zero HSN master records. No product-name HSN/GST rules. |
| Performance | Options load once per scope rather than per attribute. Production repository uses the existing SQLite-backed FirestoreDataService; no REST calls added in build, no new polling, sync listeners or conversion model. |

## Catalogue correction

`product-template-audit.json` identifies the exact SYSTEM records inspected from the read-only synced SQLite snapshot. The snapshot contains three products, with zero category/subcategory mismatches and zero Interior/Exterior Usage mismatches. Current live Firestore was not fetched or mutated. Local catalogue rows are not patched independently of their source.

`tool/product_template_corrections.json` is the source correction for nine wall-paint Usage templates: retain correct default, restrict options to that default, disallow custom Usage additions on those templates. Other templates may explicitly support Both through their own options. BUSINESS options and overrides are not changed.

Generate a fresh guarded REST commit:

```sh
python3 tool/plan_product_template_corrections.py --database /path/to/nubibill.db --project test1-bcebe
```

`product-template-correction-commit.json` contains the commit generated from the inspected snapshot. It uses update masks, SYSTEM scope checks, remote update-time preconditions and server updatedAt transforms. Submit through the existing administrator REST migration process, then run the normal catalogue sync. Regenerate against fresh synced metadata if preconditions fail. No upload was performed in this session. Controlled options for the four TEXT definitions remain a catalogue configuration prerequisite; do not turn those into empty SELECTs or fabricate brand-specific defaults.

## Files changed in this task

- lib/presentation/products/product_pages.dart
- lib/presentation/app_controller.dart
- lib/data/repositories/product_repository.dart
- lib/data/models/product_variant_model.dart
- test/product_entry_form_test.dart
- test/product_repository_test.dart
- test/offline_sync_test.dart
- tool/product_template_corrections.json
- tool/plan_product_template_corrections.py
- docs/product-template-audit.json
- docs/product-template-correction-commit.json
- docs/product-form-template-fix.md

Other pre-existing working-tree changes were preserved.

## Manual verification

1. Apply and sync the catalogue corrections. Choose an Interior template, enter values, switch to Exterior: correct Usage appears, unavailable values disappear, and Interior cannot be selected under the corrected Exterior template. Change category and confirm subcategory is cleared.
2. Check PRODUCT attributes in Product Details and VARIANT attributes in SKU cards. Confirm searchable options, required markers, and Add option only where metadata allows it. Check at desktop and narrow widths.
3. Create a variant with positive pack size, physical Unit, Selling Unit, barcode, MRP, selling price and purchase rate. Try zero pack size, negative prices, invalid GST and duplicate barcodes. Save must reject invalid entries.
4. Copy a variant. Attributes/prices remain editable; barcode is blank and SKU is generated on save. Change identifying values before saving to avoid duplicate SKU combinations.
5. Leave variant GST blank, save and reopen: it inherits product GST. Set an explicit override, save and reopen: it remains an override. Clear it and change product GST: inherited rate follows the product.
6. Disconnect, save, and confirm product/variants appear immediately from SQLite with pending sync. Restart and verify attributes, prices and units. Reconnect and verify existing outbox upload completes. Inspect sync activity to confirm no repeated catalogue polling.
7. Populate the existing HSN master through normal catalogue sync and confirm search uses its names/codes without another source.

## Automated validation

All 52 tests passed in product_entry_form_test.dart, product_repository_test.dart and offline_sync_test.dart. These cover template switching, restricted options, commercial field persistence, responsive layouts, local restart/outbox replay and idle zero-read behavior. Analysis of all seven changed Dart files produced no errors or warnings; six existing curly-brace style infos remain in app_controller.dart. Whole-repository analysis also reported unrelated existing diagnostics (44 total). The migration planner successfully generated nine guarded writes from the read-only snapshot. Live remote migration and actual-device acceptance steps remain unexecuted.
