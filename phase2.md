# PHASE 2 - Catalogue Selection Scope & Readiness Report

**Role**: Senior Flutter / SQLite Catalogue Engineer
**Phase**: `PHASE_2_CATALOGUE_SELECTION_SCOPE_AND_READINESS`
**Priority**: CRITICAL
**Status**: **COMPLETED / PASSED**

---

## 1. Preflight Verification

All Phase 2 preflight requirements were verified prior to implementation:

- [x] **Phase 1 Resolver Verified**: `ProductTemplateResolver` active and 6/6 tests passing.
- [x] **Branch Active**: Working branch `fix/product-master-audit` active.
- [x] **Phase 1 Committed**: Phase 1 changes committed (`fix(product-master): add authoritative template resolver`).
- [x] **SQLite Baseline Untouched**: Production database (`/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db`) untouched (checksum `d51f4e8bb87919dbee8eafb72fe08fa8df37b732259655ee52472e6f563ceca2`).
- [x] **Resolver Integration**: Product form uses `resolveProductTemplate` from Phase 1.

---

## 2. Modified & Created Files

| File Path | Action | Description |
| --- | --- | --- |
| `lib/data/services/catalogue_selection_resolver.dart` | **Created** | Authoritative selection resolver service (`CatalogueSelectionResolver`) evaluating category/subcategory eligibility, readiness, business scope exclusions, duplicate handling, and diagnostics. |
| `lib/data/models/product_master_value.dart` | **Modified** | Added optional `rawFields` map to `ProductMasterValue` to support raw metadata inspection without breaking callers. |
| `lib/data/repositories/product_repository.dart` | **Modified** | Integrated `getEligibleCategories()` and `getEligibleSubcategories()` using `CatalogueSelectionResolver`. |
| `lib/presentation/app_controller.dart` | **Modified** | Exposed `getEligibleCategories()` and `getEligibleSubcategories()` on `AppController` and updated `loadProductMasters()` to filter Create Product selectors by readiness. |
| `lib/presentation/products/product_pages.dart` | **Modified** | Updated `_StructuredProductFormPageState._initialize()` to resolve and display legacy classifications with a clear indicator without losing references or crashing. |
| `test/catalogue_selection_resolver_test.dart` | **Created** | Comprehensive unit test suite (7 tests) verifying eligibility filtering, Hand Sanitizers exclusion, missing template exclusion, duplicate handling, and offline execution. |

---

## 3. Selector Eligibility Contract & Supported Exclusion Reasons

A category or subcategory choice is **eligible for normal Product Creation** if and only if it satisfies all of the following:

1. **Status & Deletion**: `status == 'ACTIVE'` and `isDeleted != 1`.
2. **Template Selectability**: `templateSelectable != false`.
3. **Template Status**: `templateStatus != 'UNAVAILABLE'` and `templateStatus != 'INVALID'`.
4. **Business Scope Applicability**: Record is not explicitly excluded from current business scope (e.g. `HARDWARE/PAINTS` scope or `PAINTS` sub-type).
5. **Template Readiness**: `ProductTemplateResolver.resolveTemplate()` yields `TemplateReadinessState.ready` with non-empty active template rows in `subcategory_attribute_templates`.
6. **Category Child Rule**: A Category is eligible if and only if it has **at least one** eligible, selectable child subcategory.

### Supported Exclusion Reasons (`SelectionExclusionReason`)

| Exclusion Reason | Explanation |
| --- | --- |
| `excludedByBusinessType` | Excluded by business scope/sub-type tags (e.g. Hand Sanitizers under Paints). |
| `missingTemplate` | Record has no active template rows in `subcategory_attribute_templates` (e.g. legacy `Paint -> Interior Wall Paint`). |
| `unavailableStatus` | Record status is `INACTIVE` or `templateStatus` is `UNAVAILABLE`/`INVALID`. |
| `notTemplateSelectable` | Record explicitly declares `templateSelectable: false`. |
| `emptyCategory` | Category contains zero eligible child subcategories for normal creation. |
| `duplicateShadowed` | Record is a duplicate `BUSINESS` record shadowed by a canonical `SYSTEM` record. |
| `explicitlyExcluded` | Explicitly marked ineligible by scope rules. |

---

## 4. Previously Visible Invalid Choices Now Filtered from Create Selectors

| Previously Visible Choice | Audit Finding | Phase 2 Creation Selector Status |
| --- | --- | --- |
| **Health & Hygiene → Hand Sanitizers** | Tagged HARDWARE/PAINTS, but excluded from Paints scope and marked `UNAVAILABLE`. | **Filtered / Absent** in Paints context (`excludedByBusinessType`). |
| **Paint → Interior Wall Paint** | Active record `PM_SUBCATEGORY_ce0bf39843417fca` had zero active template rows. | **Filtered / Absent** (`missingTemplate`). |
| **Duplicate BUSINESS Interior Wall Coatings** | Empty duplicate BUSINESS category without eligible child subcategories. | **Filtered / Absent** (`emptyCategory` & `duplicateShadowed`). |
| **Unselectable Legacy Enamel Records** | Declared `templateSelectable: false`. | **Filtered / Absent** (`notTemplateSelectable`). |
| **Empty Categories** | Categories with 0 eligible subcategories. | **Filtered / Absent** (`emptyCategory`). |

---

## 5. Deterministic Duplicate Resolution

1. **Canonical Scope Preference**: When multiple categories or subcategories share the same normalized display name (whitespace trimmed, lowercase):
   - Canonical `SYSTEM` scope records (`scopeType == 'SYSTEM'`) are preferred.
   - Duplicate `BUSINESS` records with identical names do not shadow or replace canonical `SYSTEM` records for normal creation dropdowns.
2. **Deterministic Fallback**: If multiple duplicate records exist within the same scope without a canonical differentiator, selection is ordered deterministically by ID/remoteId and logged as a `DUPLICATE_CATEGORY_NAME` or `DUPLICATE_SUBCATEGORY_NAME` diagnostic.
3. **Data Preservation**: Zero master records were deleted or altered in SQLite/Firestore storage. All records remain preserved for legacy reference and future cleanup.

---

## 6. Legacy Product Compatibility (Edit / Inspection Exception)

- Existing products referencing legacy or unavailable classifications (e.g. `Paint -> Interior Wall Paint`) continue to load smoothly in Edit/Duplicate forms.
- If a saved product's category or subcategory is no longer eligible for normal creation, `_initialize()` formats the display name with a non-destructive indicator (e.g., `'Interior Wall Paint (Legacy classification)'`).
- No legacy references are deleted, dropped, or corrupted.

---

## 7. Diagnostic API Overview

Developer/test diagnostic query API (`getSelectionDiagnostics()`):
- **`recordId`**: Document ID / remoteId.
- **`displayName`**: Display name.
- **`type`**: `CATEGORY` or `SUBCATEGORY`.
- **`scopeType`**: `SYSTEM` or `BUSINESS`.
- **`eligible`**: `true` / `false`.
- **`exclusionReason`**: `SelectionExclusionReason` enum value.
- **`message`**: Readable diagnostic explanation.

---

## 8. Test Execution Results

All unit and integration tests across the repository pass 100%:

```
00:18 +96: All tests passed!
```

- **`test/catalogue_selection_resolver_test.dart`**: 7/7 tests passed.
- **`test/product_template_resolver_test.dart`**: 6/6 tests passed.
- **Full Test Suite**: 96/96 tests passed.

---

## 9. Flutter Analyze Results

Command: `flutter analyze`
Results:
- **0 newly introduced issues or errors** in Phase 2 files.
- **43 pre-existing issues** in unrelated modules (`purchase_repository.dart`, `purchase_entry_page.dart`, `purchase_pages.dart`, `storage_repository.dart`, `storage_pages.dart`).

---

## 10. Integrity & Safety Confirmations

- [x] **No Firestore Writes Occurred**: Selection filtering executes strictly read-only local queries.
- [x] **No Production SQLite Data Modified**: Baseline database (`nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db`) remains untouched (checksum `d51f4e8bb87919dbee8eafb72fe08fa8df37b732259655ee52472e6f563ceca2`).
- [x] **No Legacy Master Records Deleted**: Zero rows were deleted or mutated.
- [x] **No Product/Variant Identity Changed**: All product IDs, variant IDs, SKUs, and barcodes preserved.

Phase 2 implementation is complete. Ready for review.
