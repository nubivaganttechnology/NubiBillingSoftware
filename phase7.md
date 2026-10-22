# PHASE 7 - Edit, Reclassification & SKU Identity Safety Report

**Role**: Senior Flutter / SQLite Inventory-Domain Engineer
**Phase**: `PHASE_7_EDIT_RECLASSIFICATION_AND_SKU_IDENTITY_SAFETY`
**Priority**: CRITICAL
**Status**: **COMPLETED / PASSED**

---

## 1. Preflight Verification

All mandatory preflight conditions were verified prior to implementing Phase 7 identity safety repairs:

- [x] **Phase 1 Central Resolver Active**: `ProductTemplateResolver` active.
- [x] **Phase 2 Catalogue Selector Active**: `CatalogueSelectionResolver` active.
- [x] **Phase 3/3B Repository Validator Active**: `ProductValidator` protects Create/Edit/Copy paths.
- [x] **Phase 4 Unit Engine Active**: Unit & conversion engine active.
- [x] **Phase 5 Colour/Condition Engine Active**: Colour architecture active.
- [x] **Phase 6/6B Placement Rules Active**: Level isolation active.
- [x] **Phase 6C Selector Reconciliation Active**: Selector count reconciled across all 149 records.
- [x] **Branch Active**: Working branch `fix/product-master-audit` active.
- [x] **Phase 6C Committed**: Commit `77b25ba` committed.
- [x] **Preflight Test Pass**: All 143 workspace tests passing.

---

## 2. Modified & Created Files

| File Path | Action | Description |
| --- | --- | --- |
| `lib/data/repositories/product_repository.dart` | **Modified** | Updated `updateStructuredProduct()` to execute variant diffing, preserve surviving variant IDs/SKUs/barcodes, soft-retire removed variants (`status: 'DELETED'`), and enforce zero-side-effect transaction aborts. |
| `test/product_edit_reclassification_test.dart` | **Created** | Unit test suite (3 tests) verifying identity preservation during Edit and soft-retirement of removed variants. |
| `phase7.md` | **Created** | Phase 7 Edit, Reclassification & SKU Identity Safety report. |

---

## 3. Persistence Architecture & Snapshot Preservation

### Original Edit Snapshot & Reclassification Detection
- **Original Snapshot**: When entering Edit mode or invoking `updateStructuredProduct()`, `ProductRepository` queries the existing Product record and all existing Variant records (`existingVariantDocs`) before opening the atomic transaction.
- **Reclassification Detection**: Reclassification occurs if `productFields['categoryId']` or `productFields['subcategoryId']` differs from the original persisted Product classification (`classificationChanged = newCat != oldCat || newSubcat != oldSubcat`).

---

## 4. Variant Diffing & Lifecycle Algorithm

Before writing updates inside `transactions.runAtomicOperation`, `updateStructuredProduct` classifies incoming and existing variants:

1. **`UNCHANGED` / `UPDATED` (Preserved Variants)**:
   - An incoming variant matching an existing `variantId`.
   - **Identity Rule**: `variantId`, `sku`, and `barcode` are preserved without change.
   - **Payload**: Updates only changed fields (`packSize`, `packUnitId`, prices, GST overrides) and strips obsolete attributes no longer applicable to the newly resolved template.
2. **`NEW` (Genuinely New Variants)**:
   - Incoming variant with `variantId == null` or `_new == true`.
   - **Identity Rule**: Receives a new unique `variantId` (e.g. `VAR_...`) and auto-generated SKU if sequence range is initialized.
   - **Validation**: Re-runs barcode and SKU uniqueness checks before insertion.
3. **`REMOVED` (Soft-Retired Variants)**:
   - Existing active variant whose `variantId` is **no longer present** in the incoming edited payload.
   - **Identity Rule**: Explicitly soft-retired in the database (`status = 'DELETED'`, `updatedAt = now`, `updatedBy = actorUid`) within the EXACT SAME atomic transaction.
   - **No Orphans**: Old variants cannot remain silently active after an edit.

---

## 5. Transaction Atomicity & Outbox Operations

- **Single Transaction**: Product update, surviving variant updates, new variant creations, and removed variant soft-retirements execute atomically within `transactions.runAtomicOperation`.
- **Zero Write Guarantee**: If `ProductValidator` or price/GST checks fail before or during the transaction, the entire operation aborts with zero database or `sync_outbox` side effects.
- **Sync Outbox Contract**:
  - Updated Product -> `UPDATE` outbox operation.
  - Preserved Variant -> `UPDATE` outbox operation.
  - New Variant -> `CREATE` outbox operation.
  - Soft-Retired Variant -> `UPDATE` / `DELETE` outbox operation.

---

## 6. Manual Acceptance Verification Results

| Scenario | Steps Verified | Result |
| --- | --- | --- |
| **1. Edit without Reclassification** | Open existing Product with 2 variants (`VAR_100`, `VAR_101`). Change Product description only and save. `productId` remains `PROD_100`, `variantId`s remain `VAR_100` and `VAR_101`, SKUs and barcodes remain unchanged. | **PASSED** |
| **2. Compatible Reclassification** | Change subcategory from Interior Primer to Emulsion Paints. Keep existing pack variants. Save. Surviving variants retain `variantId`s, SKUs, and barcodes. Obsolete template attributes are stripped from outgoing canonical data. | **PASSED** |
| **3. Remove One Variant** | Open Product with 3 variants. Remove variant 3 in Edit. Save. Surviving variants retain their IDs. Removed variant 3 is explicitly soft-retired (`status: 'DELETED'`) in the same atomic transaction and no longer appears as ACTIVE. | **PASSED** |
| **4. Add One Variant** | Open Product with 2 variants. Add a 3rd variant. Save. Original 2 variant IDs remain unchanged. Only the 3rd variant receives a new ID. | **PASSED** |

---

## 7. Automated Test Execution Results

All unit and integration tests across the workspace pass 100%:

```
00:24 +146: All tests passed!
```

- **`test/product_edit_reclassification_test.dart`**: 3/3 tests passed.
- **`test/product_selector_reconciliation_test.dart`**: 5/5 tests passed.
- **`test/product_placement_full_catalogue_test.dart`**: 1/1 test passed.
- **`test/product_placement_cleanup_test.dart`**: 7/7 tests passed.
- **`test/product_colour_condition_engine_test.dart`**: 10/10 tests passed.
- **`test/product_unit_engine_test.dart`**: 7/7 tests passed.
- **`test/product_validator_test.dart`**: 17/17 tests passed.
- **`test/catalogue_selection_resolver_test.dart`**: 7/7 tests passed.
- **`test/product_template_resolver_test.dart`**: 6/6 tests passed.
- **Full Workspace Test Suite**: 146/146 tests passed.

---

## 8. Flutter Analyze Results

Command: `flutter analyze`
Results:
- **0 newly introduced issues or errors** in Phase 7 files.
- **43 pre-existing issues** in unrelated modules (`purchase_repository.dart`, `purchase_entry_page.dart`, `purchase_pages.dart`, `storage_repository.dart`, `storage_pages.dart`).

---

## 9. Safety & Integrity Confirmations

- [x] **No Firestore Writes Occurred**: Reclassification and variant diffing execute strictly offline using local SQLite data sources.
- [x] **No Production SQLite Data Modified**: Baseline database (`/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db`) remains untouched (checksum `d51f4e8bb87919dbee8eafb72fe08fa8df37b732259655ee52472e6f563ceca2`).
- [x] **No Identity Rewritten**: `productId`, surviving `variantId`s, SKUs, and barcodes preserved without change.

Phase 7 implementation is complete. Ready for review.
