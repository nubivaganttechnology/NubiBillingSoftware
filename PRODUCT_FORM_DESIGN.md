# Product form redesign

Add Product and Edit Product use the existing shared `_StructuredProductFormPage`. Persistence remains UI → repository → SQLite plus persistent outbox → authenticated Firestore REST. No database migration, collection change or stock architecture change was needed.

## Files changed in this redesign

- `lib/presentation/widgets/nubi_form.dart` — new reusable form components.
- `lib/presentation/products/product_pages.dart` — shared Add/Edit presentation, responsive fields, hints, inline validation, variant duplication, image section and mobile save action.
- `lib/data/models/product_attribute.dart` — optional hintText, exampleValue and measurementDimension metadata.
- `lib/data/models/product_master_value.dart` — optional measurementDimension metadata.
- `lib/data/repositories/product_repository.dart` — preserve presentation/measurement metadata when assembling synchronized catalogue records; persistence flow unchanged.
- `test/product_entry_form_test.dart` — actual shared Add/Edit form tests, responsive tests and rendered previews.
- `test/product_repository_test.dart` — metadata preservation through catalogue merging.
- `tool/brush_catalogue_seed_manifest.json` — administrator reference extended with dimensional metadata and mm/cm options; not runtime data or automatic seeding.
- `docs/product-form-desktop.png` and `docs/product-form-mobile.png` — widget-rendered previews using catalogue fixtures, not production screenshots.
- `PRODUCT_FORM_DESIGN.md` — this report.

Earlier product/offline work in the shared working tree is separate from this presentation iteration.

## Reusable components

`NubiFormTheme`, `NubiFormColumn`, `NubiFieldGrid`, `NubiWideField`, `NubiFormSection`, `NubiVariantCard` and `NubiImagePicker` share the application's colors. Existing master autocomplete, thumbnail and dynamic attribute controls remain in use; no parallel product schema or separate edit implementation was introduced.

Fields use persistent floating labels, minimum 56px height, 12px rounded borders and comfortable padding. Section spacing is 28px, field spacing 18–20px, and section padding is 24px on desktop / 16px on smaller screens. The centered form is capped at 1200px. Short controls occupy two columns when there is room; long fields and multi-select groups span the row. Mobile uses a single column and a bottom Save Product action. Variant cards show a header, duplicate action, specifications, SKU/barcode and packaging controls with consistent gaps. Duplicating clears the ID/SKU/barcode and uses existing SKU allocation on save. Saved variants retain their IDs.

## Dynamic hints and measurements

Hints prefer catalogue `hintText` (or legacy `hint`). Otherwise SELECT uses “Select <name>”, MULTI_SELECT uses “Select one or more”, NUMBER uses `exampleValue` where provided or “Enter a number”, and TEXT uses “Enter <name>”. Catalogue IDs never become hint labels.

Measurement controls are paired through `measurementUnitAttributeId`; selling/commercial units remain independent. If a measurement dimension is supplied, choices are matched against locally synchronized units with the same dimension. LENGTH choices therefore exclude Piece. Without dimension metadata the form uses only that attribute's defined options, never all selling units. Invalid existing dimension choices are shown as an inline validation error rather than silently replaced. Existing conversion values remain preserved; conversion inputs appear only for packaging.

For Brush, the central catalogue needs the existing Brush template linked to Brush Size and Size Unit, options inch/mm/cm, `measurementDimension: LENGTH`, and matching dimensional metadata on the units records. Product-level Brush Type, Bristle Material, Handle Material and Suitable Surface definitions/options/templates are listed in the administrator manifest. Match actual existing IDs and replace its subcategory placeholder before any seeding. Live production catalogue contents have not been audited or changed.

## Images and validation

The image section has a compact preview and an explanatory empty state. Desktop places actions beside it; mobile stacks them. Paste URL, Replace and Remove reuse existing image persistence. Choose Image and Find Image explain that their providers are currently unavailable; no storage/search service was invented.

Inline validation covers mounted product/dynamic fields, tax and packaging inputs; existing repository validation remains authoritative for the complete save. Save shows a busy state and prevents duplicate submission. No technical Business configuration links were reintroduced, and permission checks for master creation/Add Option remain.

## Verification

- `flutter test`: 42 tests passed, including actual Add/Edit preservation, responsive form rendering, dimensional filtering, SQLite restart/outbox and catalogue metadata merging.
- Layouts tested at 390px, 768px and 1280px without reported overflow exceptions.
- Desktop and mobile previews were rendered and visually inspected.
- `flutter analyze`: zero errors; 44 existing diagnostics (5 warnings and 39 informational notices). The analyzer exits nonzero because existing warnings remain; it is not a clean analyzer run. No new diagnostics remain from this redesign.
- `flutter build macos --debug`: succeeded. The existing secure-storage plugin reports a future Swift Package Manager compatibility warning.

The previews use test fixtures. Production login, a live remote round trip, external media providers and catalogue seeding require the configured application environment.
