# Product Management implementation

The core list, image-URL rendering, dynamic editing and safe archiving workflow is implemented. Media upload and assisted image search remain pending a configured storage/search provider. This is not a claim that all requested live-application scenarios have been verified.

## Files

Created:
- `lib/presentation/products/product_thumbnail.dart`
- `test/product_thumbnail_test.dart`
- `PRODUCT_MANAGEMENT_CHANGES.md`

Modified for this task:
- `lib/data/models/product_model.dart`: local synchronization status and correct active-state handling.
- `lib/data/local/local_data_source.dart`: expose synchronization metadata separately from Firestore document fields.
- `lib/data/repositories/product_repository.dart`: image aliases, legacy variant preservation, full dynamic updates, classification/type/unit/conversion validation, name/brand reservations, stock reads and atomic status changes.
- `lib/data/repositories/purchase_repository.dart`: exclude inactive variants/products from choices for new purchases; historical document readers remain unchanged.
- `lib/presentation/app_controller.dart`: permission checks, scoped stock loading, full editing and bulk status actions.
- `lib/presentation/products/product_pages.dart`: desktop rows, expanded variant table, selection, confirmation, actions and shared dynamic form.
- `test/offline_sync_test.dart`: offline full-edit/image persistence, restart/upload, historical archiving and outlet stock isolation regressions.

These files also include earlier catalogue/offline changes already present in the working tree; they were not reverted.

## Image cause and fix

The repository previously read only `productImage`, ignoring saved `imageUrl`, and the list always rendered an initial avatar rather than an image. Parsing now accepts `imageUrl` and the legacy `productImage` field. The shared form writes both aliases, including an empty string for explicit removal. SQLite and the outbox retain these fields in their existing JSON document payloads; no media schema migration is required.

`ProductThumbnail` uses a 52px network image with loading/error placeholders. Empty, malformed, unsupported-scheme and failed network URLs display the product initial. The form provides URL entry, live preview, replacement and removal. It does not download or permanently store external image bytes, perform automated image selection, or introduce hardcoded image URLs.

## List and editing

The list has selection, image, product name/code/subcategory, resolved brand/category, variant count, stock, status, synchronization status and actions. Rows expand into separate variant columns for specification, SKU, barcode, pack/unit, shade, price, stock, GST, status and editing. Master IDs are resolved from the locally loaded master records; unavailable system/master IDs are not printed as labels. Stock uses the existing thousandths convention and the selected tenant/business/outlet, with the existing storage permission.

Add, Edit Product, Manage Variants and Duplicate share `_StructuredProductFormPage`. Edit reconstructs PRODUCT/VARIANT controls from the saved subcategory template, loads SQLite master/options through the repository, prefills saved attributes and supplies defaults only when values are absent. It preserves attributes outside the current template. HSN, default/variant GST, barcode, prices, status, pack size, pack unit, base unit and commercial conversion are exposed. Generated product codes and SKUs remain read-only. Existing variant identities are retained. The subsequent product-entry refinement adds new variants using the existing sequence allocator and permits removing only unsaved variants. See PRODUCT_ENTRY_WORKFLOW.md.

The legacy `_ProductFormDialog` and its fixed-field UI were removed. The old repository/controller `updateProductVariant` methods remain as compatibility APIs; the normal Product Management workflow does not invoke them.

## Deletion and synchronization

Single/bulk actions check update or `product.delete` permission and require confirmation. Both unused and historically referenced products use status-based archiving (`status=DELETED`, document `isDeleted=true`), rather than physical deletion. Variants remain stored and are deactivated. No invoice, purchase, inventory movement or historical line is removed. Deactivation remembers prior variant statuses, allowing activation to restore them without indiscriminately activating every variant.

Full edits and status changes use the existing atomic transaction abstraction. In the application this is `OfflineFirestoreService`: entity changes and durable outbox operations commit together in SQLite, then the UI reloads local data immediately. Firestore REST uploads occur later through the existing engine with version/conflict protection. Archiving queues UPDATE operations, consistent with status-based deactivation. Local synchronization metadata is not inserted into Firestore business payloads. SQLite schema version remains **2**.

## Validation and limits

- `flutter test`: **33 passed**, including placeholder widgets, offline image/attribute persistence across restart, synchronization, history retention and outlet isolation.
- `flutter analyze`: **0 errors**, **44 existing diagnostics** (5 warnings and 39 infos); it still exits nonzero due to existing diagnostics. No new diagnostics remain in the product changes.
- `flutter build macos --debug`: successful.
- `git diff --check`: clean.
- No runtime `ProductCatalogue` or `_ProductFormDialog` references remain in `lib`.

Tests use real SQLite and a controlled REST remote, not the production Firestore project. Live Product Management interaction, real image-host responses, production uploads and reconnect behavior on the user's installation have not been verified. Image-search/upload integration needs the provider configuration requested in the conversation. Image URLs survive offline restart; image bytes are not cached for offline display. Missing/inactive historical classifications may need selection of available local masters before the dynamic form can save.
