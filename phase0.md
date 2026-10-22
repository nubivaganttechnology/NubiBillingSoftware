# PHASE 0 - Product Master Safety Baseline

**Role**: Senior Flutter/SQLite/Firestore Engineer
**Phase**: `PHASE_0_SAFETY_AND_BASELINE`
**Mode**: `SAFE_PREPARATION`
**Status**: **COMPLETED / PASSED**

---

## 1. Git Status

* **Project Root**: `/Users/sksuman/StudioProjects/NubiBillingSoftware-main`
* **Git Repository Status**: Not currently initialized as a Git repository (`fatal: not a git repository`).
* **Uncommitted / Untracked Files**: Entire directory tree is currently unversioned in Git.
* **Safety Recommendations**:
  1. Initialize Git in the project root (`git init`).
  2. Create an initial baseline commit of the current repository state.
  3. Create and switch to a dedicated branch named `fix/product-master-audit` before beginning Phase 1 repair edits.
* **Compliance Note**: No files were committed, stashed, or discarded during Phase 0.

---

## 2. Audit Report Baseline

* **File Path**: `/Users/sksuman/StudioProjects/NubiBillingSoftware-main/PRODUCT_FORM_AUDIT_REPORT.md`
* **File Size**: `1,656,964` bytes (~1.65 MB)
* **SHA-256 Checksum**: `fef134bb433a5531e3c34ef1cdd70a86b91347e9fe61c899a85a9f8fb38501d7`
* **Audit Baseline Metrics Summary**:

| Audit Measure | Baseline Value |
| --- | --- |
| Active Category → Subcategory combinations checked | **149** (148 SYSTEM + 1 legacy BUSINESS) |
| Distinct selectable combinations (after deduplication) | **139** |
| Fully clean combinations | **0** |
| Severity Breakdown (mutually exclusive highest per combo) | **138 Critical** / **4 High** / **7 Medium** / **0 Low** |
| Visible choices severity breakdown | **128 Critical** / **4 High** / **7 Medium** |
| Absent ACTIVE field template | **1** |
| Profiles with declared fields missing from active rows | **37** |
| Profiles with PRODUCT vs VARIANT placement disagreements | **69** |
| Profiles with default disagreements | **74** |
| Profiles with option disagreements | **128** |

* **Preservation Status**: The audit report file remains **100% untouched and preserved** as the immutable benchmark for subsequent repair phases.

---

## 3. SQLite Baseline

* **Database File Path**: `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db`
* **File Size**: `9,728,000` bytes (~9.73 MB)
* **SHA-256 Checksum**: `d51f4e8bb87919dbee8eafb72fe08fa8df37b732259655ee52472e6f563ceca2`
* **Schema Version (`PRAGMA user_version`)**: `3`
* **WAL / Journal Status**: No `.db-wal` or `.db-journal` files exist alongside the database file.
* **Inspection Mode**: Executed strictly read-only (`mode=ro&immutable=1`). No application startup, vacuuming, migration, compaction, or modification was performed.

---

## 4. Master Data Inventory

Read-only inspection of SQLite master data tables (`local_*` tables and sync tables):

| Table Name | Exists | Total Rows | Active Rows | Active System | Active Business | Inactive / Deleted |
| --- | --- | --- | --- | --- | --- | --- |
| `local_brands` (`brands`) | Yes | 10 | 9 | 7 | 2 | 1 |
| `local_product_categories` (`product_categories`) | Yes | 34 | 24 | 23 | 1 | 10 |
| `local_product_subcategories` (`product_subcategories`) | Yes | 198 | 149 | 149 | 0 | 49 |
| `local_product_attributes` (`product_attributes`) | Yes | 50 | 49 | 49 | 0 | 1 |
| `local_product_attribute_options` (`product_attribute_options`) | Yes | 221 | 198 | 197 | 1 | 23 |
| `local_subcategory_attribute_templates` (`subcategory_attribute_templates`) | Yes | 3377 | 2290 | 2290 | 0 | 1087 |
| `local_units` (`units`) | Yes | 27 | 27 | 27 | 0 | 0 |
| `local_product_catalogue_releases` (`product_catalogue_releases`) | Yes | 1 | 1 | 1 | 0 | 0 |
| `local_products` (`products`) | Yes | 4 | 2 | 0 | 2 | 2 |
| `local_product_variants` (`product_variants`) | Yes | 7 | 5 | 0 | 5 | 2 |
| `sync_queries` | Yes | 195 | 195 | N/A | N/A | 0 |
| `sync_outbox` | Yes | 0 | 0 | N/A | N/A | 0 |

---

## 5. Firestore Catalogue Collections

* **Identified Firestore REST Collections**:
  * `brands`
  * `product_categories`
  * `product_subcategories`
  * `product_attributes`
  * `product_attribute_options`
  * `subcategory_attribute_templates`
  * `units`
  * `product_catalogue_releases`
  * `products`
  * `product_variants`
  * Auxiliary collections: `shades`, `pack_sizes`, `hsn_codes`, `product_classification_options`
* **Safety Confirmation**: Zero network writes, catalogue seeding scripts, migrations, or sync operations were initiated. Remote Firestore remains completely unchanged.

---

## 6. Product Master Code Surface Map

| Responsibility Surface | File Path(s) |
| --- | --- |
| **Add Product & Edit Product Screens** | `/Users/sksuman/StudioProjects/NubiBillingSoftware-main/lib/presentation/products/product_pages.dart` (`ProductManagementPage`, `_StructuredProductFormPage`, `_ProductTile`, `_ProductBadge`, `_SummaryCard`) |
| **Dynamic Attribute Renderer** | `product_pages.dart` (`_renderDynamicFields`, `_buildAttributeField`, `_buildOptionDropdown`) |
| **Category & Subcategory Selection** | `product_pages.dart` (`_category`, `_subcategory` drop-down controllers & cascading listeners) |
| **Template Loading** | `product_pages.dart` (`_loadSubcategoryTemplate` querying `ProductRepository.getTemplatesForSubcategory`) |
| **PRODUCT vs VARIANT Field Rendering** | `product_pages.dart` (placement checks rendering attributes at Product header level vs inside Variant rows) |
| **Colour Conditions** | `product_pages.dart` (`COLOUR_MODE`, `FIXED_COLOUR`, `READY_COLOUR`, `TINTABLE` conditional field builders) |
| **Unit Selection & Pack Conversion** | `product_pages.dart` (`_baseUnit`, `_salesUnit`, `_packSize`, `_conversionFactor`, conversion preview calculator) |
| **SKU Generation & Barcode Validation** | `product_pages.dart` (`_generateSku`, barcode length & pattern validators) |
| **Product & Variant Save Actions** | `product_pages.dart` (`_save`, building `ProductModel` & `ProductVariantModel` payloads) |
| **Form Layout & UI Controls** | `/Users/sksuman/StudioProjects/NubiBillingSoftware-main/lib/presentation/widgets/nubi_form.dart` (`NubiFormTheme`, `NubiFormColumn`, `NubiWideField`, `NubiFieldGrid`, `NubiFormSection`) |
| **Product Thumbnail Widget** | `/Users/sksuman/StudioProjects/NubiBillingSoftware-main/lib/presentation/products/product_thumbnail.dart` (`ProductThumbnail`) |
| **Repository Validation & Catalogue Reads** | `/Users/sksuman/StudioProjects/NubiBillingSoftware-main/lib/data/repositories/product_repository.dart` (`ProductRepository` validation for SKU/barcode uniqueness, conversion factors, catalog fetches) |
| **System Catalogue Metadata & Snapshot** | `/Users/sksuman/StudioProjects/NubiBillingSoftware-main/lib/data/catalogue/system_catalogue_metadata.dart` (`SystemCatalogueMetadata`) <br> `/Users/sksuman/StudioProjects/NubiBillingSoftware-main/lib/data/catalogue/system_catalogue_snapshot.dart` (`SystemCatalogueSnapshot`) |
| **Data Models** | `lib/data/models/product_model.dart`<br>`lib/data/models/product_variant_model.dart`<br>`lib/data/models/product_attribute.dart`<br>`lib/data/models/product_master_value.dart` |
| **SQLite Database Schema & Access** | `lib/data/local/local_database.dart` (`LocalDatabase`)<br>`lib/data/local/local_data_source.dart` (`LocalDataSource`) |
| **Firestore REST Sync & Offline Layer** | `lib/data/services/offline_firestore_service.dart`<br>`lib/data/services/firestore_rest_service.dart`<br>`lib/data/sync/sync_engine.dart`<br>`lib/core/constants/firebase_constants.dart` |
| **App Controller State Management** | `/Users/sksuman/StudioProjects/NubiBillingSoftware-main/lib/presentation/app_controller.dart` (`loadProducts`, `loadProductMasters`, `saveProduct`, `setProductStatus`) |

---

## 7. Existing Automated Tests

* **`test/system_catalogue_test.dart`**: Tests system catalogue snapshot initialization, SQLite table population, release versioning, and profile configurations.
* **`test/dynamic_product_master_acceptance_test.dart`**: Acceptance test suite covering dynamic template loading, category/subcategory field rendering, and variant generation.
* **`test/product_entry_form_test.dart`**: UI widget test suite validating Product Form rendering, unit pickers, conversion factors, field inputs, and form submission.
* **`test/product_repository_test.dart`**: Repository unit test suite validating SKU uniqueness, barcode uniqueness, transaction rollback on save failure, and Firestore data serialization.
* **`test/product_thumbnail_test.dart`**: Widget test for product thumbnail rendering.
* **`test/firestore_sync_rest_test.dart`**: Integration test for Firestore REST catalogue sync operations.
* **`test/offline_sync_test.dart`**: Test suite for offline queueing, `sync_outbox`, and database replication.

---

## 8. Risks Before Phase 1

1. **Unversioned Workspace**: Project is not currently tracked in Git, creating a risk if intermediate edits need to be rolled back.
2. **Dual Metadata Reference**: Hardcoded catalogue metadata in `system_catalogue_metadata.dart` must remain synchronized with database tables in SQLite and Firestore.
3. **Sync Outbox Side Effects**: Uncontrolled test saves during Phase 1 could write to `sync_outbox` and attempt synchronization with Firestore REST backend.
4. **Scope Partitioning**: Care must be taken to distinguish `SYSTEM` scope (`isSystem=1`) from `BUSINESS` scope overrides so tenant data is not corrupted.

---

## 9. Backup / Restore Checklist

- [x] **Audit Report**: Benchmark `PRODUCT_FORM_AUDIT_REPORT.md` verified and locked (SHA256: `fef134bb433a5531e3c3...`).
- [ ] **SQLite Physical Backup**: Prior to Phase 1, copy SQLite database file:
  `cp /Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db /Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak`
- [ ] **Git Tracking Initialization**:
  1. `git init`
  2. `git add . && git commit -m "baseline: phase 0 safety snapshot"`
  3. `git checkout -b fix/product-master-audit`
- [ ] **Firestore Collection Export**: Export or snapshot production/test Firestore collections (`brands`, `product_categories`, `product_subcategories`, `product_attributes`, `product_attribute_options`, `subcategory_attribute_templates`, `units`) before running any repair scripts.
- [ ] **Single-Step Restore Verification**: Restoring the `.db.bak` file returns the runtime database immediately to checksum `d51f4e8bb87919dbee8eafb72fe08fa8df37b732259655ee52472e6f563ceca2`.

---

## 10. Phase 0 Pass/Fail

**Result**: **PASS**

**Evaluation against Phase 0 Pass Conditions**:
1. Current repository state is fully analyzed and understood.
2. Audit report (`PRODUCT_FORM_AUDIT_REPORT.md`) is preserved completely unchanged.
3. SQLite baseline (path, size, checksum, schema version 3, journal status) is recorded.
4. No Product Master logic or data was modified.
5. No Firestore writes, seed scripts, or migrations were executed.
6. Product Master source surfaces across UI, repository, models, DB, and sync layers are mapped.
7. Relevant test suites are identified.
8. A clear 5-step backup/restore strategy exists before Phase 1.
