# PHASE 1 - Authoritative Metadata Contract & Central Resolver Report

**Role**: Senior Flutter Architecture Engineer
**Phase**: `PHASE_1_AUTHORITATIVE_METADATA_CONTRACT`
**Priority**: CRITICAL
**Status**: **COMPLETED / PASSED**

---

## 1. Preflight Prerequisites Verification

All mandatory preflight conditions were verified prior to implementing Phase 1 code changes:

- [x] **Physical SQLite Backup**: Physical backup verified and created at `/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak`.
- [x] **Git Initialized**: Workspace initialized with Git repository in project root.
- [x] **Baseline Committed**: Baseline commit `baseline: Phase 0 safety snapshot` created.
- [x] **Branch Active**: Working branch `fix/product-master-audit` active.

---

## 2. Modified & Created Files

| File Path | Action | Description |
| --- | --- | --- |
| `lib/data/models/resolved_product_template.dart` | **Created** | Authoritative metadata models (`ResolvedProductTemplate`, `ResolvedTemplateAttribute`, `ResolvedAttributeOption`, `ResolvedCondition`, `ResolvedUnitRule`, `TemplateDiagnostic`, `TemplateReadinessState`, `AttributeLevel`, `ConditionScope`). |
| `lib/data/services/product_template_resolver.dart` | **Created** | Central Product Master template resolver evaluating SQLite catalogue metadata deterministically without Firestore network calls. |
| `lib/data/repositories/product_repository.dart` | **Modified** | Integrated `ProductTemplateResolver` into `resolveTemplate()` and updated `loadTemplate()` to delegate to the central resolver. |
| `lib/presentation/app_controller.dart` | **Modified** | Exposed `resolveProductTemplate()` on `AppController` and unified `loadProductTemplate()` delegation. |
| `lib/presentation/products/product_pages.dart` | **Modified** | Updated `_StructuredProductFormPageState` (Add, Edit, Copy workflows) to consume `resolveProductTemplate()` centrally. |
| `test/product_template_resolver_test.dart` | **Created** | Unit test suite verifying template resolution, scope precedence, level assignment, options merge, default validation, and offline execution. |
| `test/product_entry_form_test.dart` | **Modified** | Added `resolveProductTemplate` support to `EntryController` mock test controller. |

---

## 3. Authoritative Metadata Contract

The single authoritative runtime metadata contract is defined by `ResolvedProductTemplate` and its child models:

1. **`ResolvedProductTemplate`**:
   - `categoryId`, `subcategoryId`, `categoryName`, `subcategoryName`
   - `readiness` (`TemplateReadinessState`: `ready`, `unavailable`, `invalid`, `missingTemplate`)
   - `productAttributes`: List of attributes assigned to `AttributeLevel.product`.
   - `variantAttributes`: List of attributes assigned to `AttributeLevel.variant`.
   - `technicalAttributes`: List of attributes designated as technical details.
   - `unitRules`: `ResolvedUnitRule` (allowed pack, sold-as, base units, default units).
   - `diagnostics`: List of `TemplateDiagnostic` records capturing metadata mismatches, invalid defaults, and missing definitions.

2. **`ResolvedTemplateAttribute`**:
   - `attributeId`, `displayName`, `level` (`AttributeLevel`), `dataType` (`TEXT`, `NUMBER`, `SELECT`, `MULTI_SELECT`, `BOOLEAN`), `required`, `defaultValue`
   - `options`: Centralized `List<ResolvedAttributeOption>`
   - `allowMultiple`, `allowAddNewOption`, `hint`, `exampleValue`, `technical`, `sortOrder`
   - `conditions`: List of `ResolvedCondition` for field visibility / requirements
   - `semanticRole`, `measurementDimension`, `measurementUnitAttributeId`, `minimumExclusive`, `defaultRules`, `visibleWhen`, `requiredWhen`
   - `toProductAttribute()`: Guarantees 100% backward compatibility for legacy callers.

---

## 4. Precedence Rules & Central Resolver Flow

### Precedence Contract
1. **SYSTEM Definition Baseline**: Global attribute definitions from `product_attributes` where `scopeType='SYSTEM'`.
2. **SYSTEM Template Configuration**: Template row definitions from `subcategory_attribute_templates` where `scopeType='SYSTEM'` and matching `subcategoryId`.
3. **BUSINESS Override Configuration**: Template row overrides from `subcategory_attribute_templates` where `scopeType='BUSINESS'` and matching `businessId`.
4. **BUSINESS Custom Options**: Custom options from `product_attribute_options` where `scopeType='BUSINESS'` merged only when `allowAddNewOption == true`.
5. **Central Option Deduplication**: Options normalized by trimming whitespace and case-insensitive deduplication.
6. **Default Validation**: Select defaults not present in the resolved option set generate an `INVALID_DEFAULT` warning diagnostic and are cleared to prevent unselectable selections.

### Resolver Execution Flow
```
Subcategory Request (tenantId, businessId, subcategoryId)
       │
       ▼
Query Subcategory & Category Metadata (local SQLite)
       │
       ▼
Query Global Option Records (SYSTEM + BUSINESS)
       │
       ▼
Query Attribute Definitions (SYSTEM + BUSINESS)
       │
       ▼
Query Subcategory Attribute Templates (SYSTEM -> BUSINESS Override)
       │
       ▼
For each attribute in effective template:
   ├─ Merge definition + template row properties
   ├─ Determine AttributeLevel (PRODUCT vs VARIANT)
   ├─ Resolve allowed options & validate defaultValue
   ├─ Resolve conditions & technical field designation
   └─ Build ResolvedTemplateAttribute
       │
       ▼
Resolve Unit Rules & Determine Readiness State (ready, missingTemplate, invalid)
       │
       ▼
Return ResolvedProductTemplate
```

---

## 5. Hardcoded Domain Branches Removed or Deferred

- **Unified Add, Edit & Copy Resolution**: Removed independent/divergent template loading paths across Add Product, Edit Product, and Copy Product screens in `_StructuredProductFormPageState`. All modes now invoke `widget.controller.resolveProductTemplate()`.
- **Deferred Domain Branch Changes**: Hardcoded paint/wood/colour mode logic in `product_pages.dart` (`colourMode`, `colourType`, `Tintable Base`, `Ready Colour`) was preserved via compatibility adapters for Phase 1 to prevent breaking existing catalogue data prior to Phase 3/5 template corrections.

---

## 6. Unresolved Catalogue Disagreements Deferred to Subsequent Repair Phases

- **Profile vs Template Placement Disagreements**: 69 category/subcategory combinations where profile metadata disagrees with template placement are detected and recorded as `TemplateDiagnostic` (`PROFILE_PLACEMENT_DISAGREEMENT`), deferred to Phase 3 for template fixes.
- **Option Set & Default Disagreements**: 128 option disagreements and 74 default disagreements are surfaced as `INVALID_DEFAULT` diagnostics by the resolver, deferred to Phase 3 for bulk template corrections.
- **Unit Conversion Factor Calibration**: Broad unit data corrections across all 149 combinations deferred to Phase 4.

---

## 7. Automated Tests Added & Updated

1. **`test/product_template_resolver_test.dart`** (New Test Suite):
   - `same subcategory resolves identically for Add and Edit`: Verified Add and Edit resolve identical metadata.
   - `same SQLite state resolves deterministically`: Verified deterministic resolution output across invocations.
   - `PRODUCT and VARIANT levels come from resolver`: Verified explicit level assignment to `productAttributes` vs `variantAttributes`.
   - `invalid defaults generate diagnostics and clear default`: Verified invalid defaults produce `INVALID_DEFAULT` warning diagnostic and nullify invalid default values.
   - `BUSINESS custom option merge obeys allowAddNewOption`: Verified custom option merging respects `allowAddNewOption` flag and issues `UNAUTHORIZED_CUSTOM_OPTION` when prohibited.
   - `resolver performs NO Firestore network calls`: Verified execution runs strictly against local SQLite query layer.

2. **`test/product_entry_form_test.dart`** (Updated):
   - Added `resolveProductTemplate` support to `EntryController` mock test controller.

---

## 8. Test Execution Results

All unit and integration tests across the repository pass 100%:

```
00:18 +89: All tests passed!
```

---

## 9. Flutter Analyze Results

Command: `flutter analyze`
Results:
- **0 newly introduced issues or errors** in Phase 1 files.
- **43 pre-existing issues** reported in unrelated modules (`purchase_repository.dart`, `purchase_entry_page.dart`, `purchase_pages.dart`, `storage_repository.dart`, `storage_pages.dart`).

---

## 10. Integrity & Safety Confirmations

- [x] **No Firestore REST Writes Occurred**: All resolver operations execute read-only queries via the local SQLite query service.
- [x] **No Production SQLite Data Modified**: Baseline database (`nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db`) remains unmodified with checksum `d51f4e8bb87919dbee8eafb72fe08fa8df37b732259655ee52472e6f563ceca2`.
- [x] **No Product or Variant Identity Modified**: All product IDs, variant IDs, SKUs, and barcodes preserved without change.

Phase 1 implementation is complete. Ready for review.
