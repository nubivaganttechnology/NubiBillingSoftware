# Offline SQLite / Firestore REST implementation

SQLite is now the runtime source injected into every existing repository in `main.dart`. No Firebase Flutter plugins were introduced. The existing collection names and document payloads are retained.

## Created files

- `lib/data/local/local_database.dart`: per-project/account SQLite files, schema and additive migrations.
- `lib/data/local/local_data_source.dart`: indexed scoped reads, UPSERT, JSON payload preservation, tombstones and pending-write protection.
- `lib/data/services/offline_firestore_service.dart`: repository-compatible SQLite adapter, bootstrap authorization reads, persistent query registration and atomic local writes.
- `lib/data/sync/connectivity_service.dart`: network-change triggers; connectivity is not treated as proof of REST reachability.
- `lib/data/sync/sync_outbox_repository.dart`: persistent batches, dependency ordering, retries and database lease.
- `lib/data/sync/sync_engine.dart`: conditional REST batch uploads, downloads, conflict logging, diagnostics and state notifications.
- `test/offline_sync_test.dart`: real SQLite persistence, migration and sync regression tests with a controlled REST service.
- `test/offline_auth_test.dart`: secure offline-session restoration and network-failure preservation tests.
- `OFFLINE_SYNC_IMPLEMENTATION.md`: this report.

## Modified files for this task

- `pubspec.yaml`, `pubspec.lock`: SQLite, desktop SQLite driver, connectivity and path dependencies.
- `lib/main.dart`: repository injection, desktop driver setup, connectivity startup and application-resume trigger.
- `lib/core/network/api_client.dart`: distinguish network failures from authorization/server failures.
- `lib/core/storage/token_storage.dart`: store the remembered ID token and expiry exclusively in existing secure storage; read legacy refresh-only entries.
- `lib/data/repositories/auth_repository.dart`: restore cached sessions offline without erasing credentials after network failure; back off repeated refresh failures.
- `lib/data/repositories/business_repository.dart`: save business and name reservation in one atomic batch.
- `lib/data/repositories/product_repository.dart`: require initial product/sequence coverage before offline code allocation.
- `lib/data/services/firebase_auth_rest_service.dart`: preserve network error classification.
- `lib/data/services/firestore_data_service.dart`: optional offline write-prerequisite contract.
- `lib/data/services/firestore_rest_service.dart`: preserve network error classification.
- `lib/presentation/app_controller.dart`: login/workspace sync triggers, permission-scoped prefetch, post-sync local refresh, access revalidation and workspace race protection.
- `lib/presentation/dashboard/admin_dashboard_page.dart`: Synced/Syncing/Offline/Pending/Sync error indicator and manual retry.
- `lib/presentation/products/product_pages.dart`: refresh open form templates/options without clearing entered values.
- `macos/Flutter/GeneratedPluginRegistrant.swift`, `windows/flutter/generated_plugin_registrant.cc`, `windows/flutter/generated_plugins.cmake`: generated plugin registration.

Earlier brand-ID/catalogue migration changes remain in the workspace; their deleted catalogue/exporter files are not new offline-sync changes.

## Schema and migrations

The project previously had no SQLite schema. New databases migrate from 0 to **2**. Migration 1 creates document tables, outbox, query registry, conflicts and lease. Migration 2 adds persisted pull-attempt/error diagnostics and a conflict lookup index. A real version-1-to-version-2 upgrade test verifies that documents and queued operations survive. Normal migrations never drop the database.

Each document table stores:

- `remoteId` (original Firestore document ID), `payloadJson` (Firestore typed fields, retaining arrays, maps, timestamps and defaults).
- `scopeType`, `status`, `catalogueId`, `businessTypeId`, `businessSubTypeId`.
- `tenantId`, `businessId`, `outletId`, `categoryId`, `subcategoryId`, `attributeId`.
- `syncStatus`, `localUpdatedAt`, `remoteUpdatedAt`, `remoteUpdateTime`, `lastSyncedAt`, `isDeleted`, `syncError`.
- `localRevision`, `acknowledgedRevision` for dependent queued operations.

The catalogue tables are `local_brands`, `local_product_categories`, `local_product_subcategories`, `local_units`, `local_product_attributes`, `local_product_attribute_options`, `local_subcategory_attribute_templates` and `local_product_catalogue_releases`.

```sql
CREATE TABLE sync_outbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  batchId TEXT NOT NULL,
  entityType TEXT NOT NULL,
  documentId TEXT NOT NULL,
  operation TEXT NOT NULL CHECK(operation IN ('CREATE','UPDATE','DELETE')),
  tenantId TEXT, businessId TEXT, outletId TEXT,
  payloadJson TEXT NOT NULL,
  readSetJson TEXT NOT NULL,
  localRevision INTEGER NOT NULL,
  createdAt TEXT NOT NULL,
  attemptCount INTEGER NOT NULL DEFAULT 0,
  lastAttemptAt TEXT, lastError TEXT,
  status TEXT NOT NULL DEFAULT 'PENDING'
    CHECK(status IN ('PENDING','PROCESSING','FAILED'))
);
```

`batchId` retains the original repository transaction; `readSetJson` retains its version baselines. A leased batch cannot be uploaded by two engines simultaneously. An interrupted PROCESSING batch is recovered when the lease expires; the lease expires after five minutes and is renewed during active sync.

## Flows

**Reads:** UI → existing repository → SQLite adapter → scoped SQLite query. Product dropdowns/templates do not perform a live REST request. First-time authorization/bootstrap cache misses may require REST; fetched records are committed to SQLite before repository results are returned. Remembered sessions require one previous successful online initialization for offline use.

**Downloads:** sync uses authenticated REST queries, stores complete payloads with SQLite UPSERT, records pull diagnostics, then notifies the controller/form to reread SQLite. SYSTEM catalogue prefetch starts with releases, brands, categories, subcategories, units, attributes, options and templates. Inactive records are downloaded so deactivation replaces stale ACTIVE cache entries. Successful complete queries can tombstone missing synchronized records; pending local records are never overwritten or removed by pulls.

**Writes:** repository validation → SQLite transaction → local records plus outbox rows → immediate UI success. Sync uploads the original multi-document batch using Firestore create/update-time preconditions. It records confirmed update times and removes outbox rows only after success. Pending newer revisions remain intact. Failed requests retain records and operations.

An ambiguous upload response is checked against the complete intended batch before retrying, preventing duplicate posting. Remote version conflicts are recorded in `sync_conflicts`, with failed batches retained. Dependent operations wait; unrelated batches can continue. There is no force-overwrite or last-write-wins path for posted documents. Existing purchase approval/payment/stock/ledger logic runs inside the same original atomic group.

## Entity coverage

All existing repository interfaces use the adapter. Local tables cover businesses, outlets, employees, products/variants, storage locations/godowns/racks/shelves, stock balances, inventory movements, suppliers and their business links/products/balances/ledger/payments/credits/allocations, purchase bills, purchase orders/items, goods receipts/items, purchase returns, legacy purchases, and invoice/customer dashboard reads. User/role/permission/business-type/configuration records are also cached. Sequences, uniqueness keys and business-name reservations synchronize with dependent records.

Purchase bill line items remain embedded JSON because that is the existing remote schema. Goods-receipt and purchase-order items have their existing separate collection mirrors. No incompatible purchase/invoice item schema was invented.

Not implemented: operational expenses, tinting, hold bills, new sales/invoice editing, and other unfinished modules. Firebase sign-in, identity creation and token refresh remain server operations; employee identity creation cannot be performed offline. No service-account keys, passwords or tokens are written to SQLite.

## Validation

- `flutter test`: **28 tests passed**.
- `flutter analyze`: **zero errors; 44 existing warnings/informational diagnostics**, standard command exits nonzero. No new offline-sync diagnostics remain.
- `flutter build macos --debug`: **final native build succeeded**, including the version-2 schema and plugin integration.
- `git diff --check`: clean.
- No direct Firestore reads were found in presentation/UI code. Remaining direct remote reads are in sync, Firebase authentication, and first-time authorization/bootstrap cache misses.

Tests cover initial catalogue download, no per-dropdown REST fetch, SYSTEM/BUSINESS catalogue persistence across offline restart, array defaults/options, queued create/edit persistence, lost acknowledgements, duplicate sync attempts, conflicts, independent batches, soft deletion, tenant/account isolation, rollback, two real product creations with variants/sequences, purchase approval/payment/stock/ledger posting, lease recovery, secure session restore and schema upgrade.

Live authenticated database/UI validation remains pending: Computer Use permissions were denied. Controlled REST tests do not establish that deployed security rules allow every new sync query. Web runtime support is not included; native Android/iOS/macOS use sqflite, and Windows/Linux use the SQLite FFI driver. Only macOS was built in this environment.

## Outlet product placement (`outlet_products`)

`products` and `product_variants` remain **business-level masters**; they are never duplicated per outlet. `outlet_products` (SQLite `local_outlet_products`, schema v7) records which outlet carries which product:

`tenantId, businessId, outletId, productId, status, isActive, createdAt, updatedAt` and optional `variantIds` (absent = all variants). The document id is a deterministic hash of `tenantId+businessId+outletId+productId`, which enforces the unique logical key.

- Flow: Firestore `outlet_products` → pull (one business-wide query, not outlet-filtered) → SQLite `local_outlet_products` → Products UI reads SQLite only. Switching outlets is a local filter and issues no Firestore read.
- Create from an outlet: one SQLite transaction writes product + variants (if new) + the placement for the *current* outlet + `sync_outbox` rows (one batch), then syncs asynchronously. Other outlets are not assigned.
- Products page: outlet mode lists only ACTIVE placements for the current tenant/business/outlet and sums only `stock_balances` of that outlet. There is no Combined view: Products is always outlet-scoped and shows "Select an Outlet" when none is selected.
- "Add existing product" creates only the placement (reactivating an inactive one); it never writes product or variant masters.
- Migration (`OutletPlacementBackfill`, schema v8 marker table): runs once per business, for owners, after the first complete sync of products, variants, placements, stock balances, inventory transactions, goods-receipt items and purchase-order items. A product is placed at an outlet **only** when existing data proves it (an explicit `outletId` on the product/variant, or outlet-attributed stock, inventory, goods-receipt, purchase-order, purchase-bill or invoice records). Products with no proof stay unassigned (never assigned to every outlet), are not shown in any outlet, and are assigned with "Add existing product". Product/variant masters are only read; existing placement rows (including deliberately inactive ones) are never overwritten.
- The new sync query reads `outlet_products` by tenant and business; deployed Firestore security rules must allow that collection.

### Firestore index for `outlet_products`
The pull query (`tenantId`+`businessId` equality, `updatedAt` cursor range, `__name__` order) needs the composite index `outlet_products(businessId, tenantId, updatedAt)`, declared in `firestore.indexes.json` like every other synced collection. Deploy with `firebase deploy --only firestore:indexes`.

## Placement provenance, sequence rebase and product images

- `outlet_products.placementSource` is `NEW_PRODUCT`, `MANUAL_ASSIGNMENT` or `LEGACY_BACKFILL` (evidence-only backfill); `createdBy` records the actor. Rows created before this field existed have no source and are never auto-corrected.
- A FAILED outbox batch caused by `Remote version changed for document_sequences/...` is retried automatically. `_rebaseSequenceWrites` raises the counter to at least the remote value, shifts the codes issued by the batch (e.g. `PRD-0007` → `PRD-0008`) in the outbox payloads and local rows, and never lowers a counter or reuses an issued code.
- `createStructuredProduct` starts numbering after the highest code already issued in the business, even when the stored counter is stale.
- `ProductThumbnail` renders a fixed-size box; empty, invalid or unreadable image URLs show the letter placeholder.
- Header sync status depends only on the current run or FAILED outbox rows; errors on inactive `sync_queries` are historical and ignored.
