# NubiBill ERP - Secure Product Stock Quantity Management Report

**Date:** October 2026  
**Module:** Inventory & Stock Control, Procurement, Sales, Local Database & Multi-Tenant Security  
**Status:** Implemented & Verified  

---

## 1. Executive Summary

In enterprise ERP systems, physical stock integrity is paramount. Allowing arbitrary quantity edits—especially for freshly created products that have never been received via a vendor purchase receipt or formal opening stock declaration—creates severe accounting discrepancies, valuation distortion, shrinkage concealment, and GST audit vulnerabilities.

This implementation establishes an **immutable, transaction-driven, and offline-resilient stock control architecture** across NubiBill Flutter ERP. Direct quantity modification has been eliminated. Every stock change now requires an authorized, atomic transaction ledger entry, supported by FIFO batch allocation, multi-tier employee permissions, manager approval workflows, and complete audit provenance.

---

## 2. Business Rules & Enforcement Matrix

| Workflow / Event | Permitted Method | Required Permission | Pre-Conditions & Validations | Stock Impact |
| :--- | :--- | :--- | :--- | :--- |
| **Product Creation** | Product Master Form | `catalog.edit` / Owner | Product saved with master attributes (SKU, barcode, GST, units). Stock not initialized in form. | Stock = 0 (`OUT_OF_STOCK`). No purchase bill created. |
| **Direct Stock Edit** | *Blocked* | N/A | Tapping stock counts or bypassing transactions is blocked. | Blocked. System displays error guiding to authorized channels. |
| **Opening Stock** | Opening Stock Dialog | `inventory.opening_stock` | Non-duplicate check (variant has never had opening stock or purchases at outlet); Reason required; Qty > 0. | Stock increases to exact declared count. Batch `BATCH_OP_...` created. Status: `POSTED`. |
| **Purchase Draft** | Purchase Bill (Draft) | `procurement.manage` | Direct bill saved with `status: DRAFT` or `PENDING_RECEIPT`. | **No change to available stock.** |
| **Purchase Receipt** | Approve Direct Bill / Goods Receipt | `procurement.manage` / `inventory.adjust` | Vendor bill verified and approved. | Stock increases by received quantity. Available batch created. Ledger entry logged. |
| **Retail / POS Sale** | Sales Invoice Posting | POS Cashier / `sales` | Available stock $\ge$ quantity requested. FIFO batch depletion. | Stock decreases by sold quantity. Batches deducted. Movement: `OUT`. |
| **Adjustment (Request)** | Stock Adjustment Dialog | `inventory.adjust` | User lacks `inventory.approve_adjustment`. Reason required. Decrease checks (stock > 0, qty $\le$ stock). | **No change to stock.** Status: `PENDING_APPROVAL`. |
| **Adjustment (Approval)** | Audit History Dialog / Manager Hub | `inventory.approve_adjustment` | Adjustment in `PENDING_APPROVAL`. Revalidates available stock for negative adjustments. | Stock balance updated atomically. Status: `POSTED`. |
| **Adjustment (Rejection)** | Audit History Dialog / Manager Hub | `inventory.approve_adjustment` | Adjustment in `PENDING_APPROVAL`. | Stock balance untouched. Status: `REJECTED`. |
| **Decrease from 0** | Any outward channel | Any | Available stock $\le 0$. | **Blocked immediately** with: *"Stock cannot be reduced because the available quantity is 0."* |
| **Insufficient Stock** | Any outward channel | Any | Requested quantity $>$ available stock. | **Blocked immediately** with: *"Insufficient available stock. Please check the quantity."* |

---

## 3. Core Architectural Components

### 3.1. Canonical Stock Balance Identity
Previous revisions had occasional divergence in stock document keys (e.g. `_DIRECT_`). The architecture now standardizes on a single canonical document key across all modules:
$$\text{StockBalanceId} = \text{tenantId}\_\text{outletId}\_\text{variantId}$$
This guarantees that stock balances in `PurchaseRepository`, `SalesRepository`, `StockMovementService`, `InventoryRepository`, and `AppController` reference the identical local SQLite row and Firestore document.

### 3.2. 17-Field Enterprise Audit Ledger Model
All stock movements produce an immutable `StockTransactionAuditModel` record in `FirebaseConstants.stockMovements` (`local_stock_movements` in SQLite):

```dart
class StockTransactionAuditModel {
  final String transactionId;       // Unique UUID or idempotency key
  final String businessId;          // Scoped business entity
  final String outletId;            // Scoped outlet location
  final String productId;           // Parent product ID
  final String variantId;           // Specific variant SKU
  final String transactionType;     // OPENING_STOCK, PURCHASE_RECEIPT, SALE, ADJUSTMENT_IN, ADJUSTMENT_OUT, etc.
  final String sourceDocumentId;    // Bill ID, Invoice ID, GRN, or Adjustment Ref
  final int previousQuantity;       // Stock balance immediately prior to posting
  final int changedQuantity;        // Delta quantity applied
  final int newQuantity;            // Stock balance immediately after posting
  final String unit;                // Unit of measure (e.g., PCS, KG, BOTTLE)
  final String reason;              // Mandatory business/audit reason
  final String performedBy;         // User UID who initiated or submitted the change
  final String? approvedBy;         // Manager UID who approved the change
  final String approvalStatus;      // POSTED, PENDING_APPROVAL, REJECTED
  final DateTime createdAt;         // UTC timestamp
  final String syncStatus;          // SYNCED, PENDING_SYNC, CONFLICT
  final String? tenantId;           // Multi-tenant root
  final int? unitCostPaise;         // Unit cost in paise (for valuation)
  final String? batchId;            // FIFO batch identifier
  final String? rejectionReason;    // Manager note if rejected
}
```

### 3.3. Inventory Repository (`InventoryRepository`)
Centralizes inventory operational workflows:
- `getAvailableStock`: Safe retrieval returning `0` for uninitialized products rather than failing.
- `hasOpeningStockBeenInitialized`: Queries historical transactions and opening batches to prevent duplicate setup entries.
- `addOpeningStock`: Enforces `inventory.opening_stock` permission, validates non-duplicate setup, creates opening batch (`BATCH_OP_...`), batch movement (`IN`), balance record, and posted audit trail atomically.
- `requestOrApplyAdjustment`: Validates `inventory.adjust`, blocks decreases from 0 or beyond stock, verifies permissions, and either marks the transaction `PENDING_APPROVAL` (no stock change) or atomically posts the batch and balance update if the user has `inventory.approve_adjustment`.
- `approveAdjustment`: Enforces `inventory.approve_adjustment`, verifies pending status, revalidates stock safety, updates batches and balances atomically, and marks status `POSTED`.
- `rejectAdjustment`: Marks status `REJECTED` and records rejection reason without altering balances.
- `getStockHistory`: Retrieves the complete audit ledger for any variant or outlet with search and filter capabilities.

### 3.4. Hierarchical Role & Permission Catalog
`PermissionCatalog` was updated with the canonical `inventoryPermissions` definitions and a hierarchical matcher:
- `inventory.view`: View current stock and movement history.
- `inventory.opening_stock`: Initial physical stock entry during store onboarding.
- `inventory.adjust`: Request adjustments (damage, loss, physical counts).
- `inventory.approve_adjustment`: Managerial authorization to apply adjustment deltas.
- Hierarchical matching ensures that wildcard grants like `inventory` or `inventory.*` automatically satisfy child permissions (`inventory.adjust`).

---

## 4. UI Modernization & Interaction Safeguards

The Inventory Dashboard (`InventoryDashboardPage`) now features a secure action hub:

```
+-------------------------------------------------------------+
| [Package] Premium Arabica Coffee Beans                      |
|           1kg Whole Bean • KG           [ 0 ] [Out of Stock]|
+-------------------------------------------------------------+
|  [+] Add Purchase                                           |
|      Receive inventory from verified vendor bill.           |
|                                                             |
|  [✓] Add Opening Stock                                      |
|      Register existing physical stock during setup.         |
|                                                             |
|  [⚙] Stock Adjustment                                       |
|      Physical corrections, breakage, damage, or counts.     |
|                                                             |
|  [◷] Stock History                                          |
|      Immutable audit ledger of stock movements.             |
+-------------------------------------------------------------+
```

1. **Direct Manipulation Prevention**: Tapping stock level indicators when stock is zero displays:
   > *"This product has no recorded stock. Please enter a purchase receipt, authorized opening stock, or stock adjustment."*
2. **Opening Stock Dialog**: Enforces quantity $> 0$, requires a non-empty setup note, and guards against duplicate execution.
3. **Stock Adjustment Dialog**: Displays live projected balances with color-coded safety badges. If a decrease from 0 is attempted, it blocks submission with:
   > *"Stock cannot be reduced because the available quantity is 0."*
   If requested decrease exceeds available stock, it blocks with:
   > *"Insufficient available stock. Please check the quantity."*
4. **Approval Awareness**: If an employee without approval rights submits an adjustment, the dialog informs:
   > *"Stock adjustment is awaiting approval."*
5. **Stock Movement Audit Modal**: Displays chronological ledger entries with inward/outward indicators, approval badges, user timestamps, audit reasons, and inline Approve/Reject action buttons for authorized managers.

---

## 5. Offline-First & Synchronization Safeguards

1. **SQLite Native Transactions**: All stock balance increments, batch allocations, batch movements, and ledger entries execute within atomic SQLite transactions (`tx.runAtomicOperation`). If any sub-step fails, all changes rollback completely.
2. **Idempotent Outbox Synchronization**: Every stock movement carries a unique `transactionId`. Replayed sync packets or duplicate network deliveries identify existing transaction documents, preventing double-counting.
3. **Multi-Outlet Stock Isolation**: Stock balances are partitioned strictly by `tenantId`, `businessId`, and `outletId`. A product received in Outlet A has zero stock effect on Outlet B.
4. **No Silent Overwrites**: Synchronizing offline adjustments does not overwrite server balances with stale snapshots; adjustments apply calculated deltas against verified batch allocations.

---

## 6. Verification & Automated Test Results

### 6.1. Inventory Stock Management Specification Tests (`test/inventory_stock_management_test.dart`)
All 12 business test scenarios pass with 100% compliance:

```
✓ Scenario 1: New product without purchase exists with stock 0 and OUT status
✓ Scenario 2: Increase stock directly is blocked without authorized transaction
✓ Scenario 3: Decrease stock from 0 is strictly blocked
✓ Scenario 4: Opening stock of 10 units sets stock to 10 and prevents duplicates
✓ Scenario 5: Purchase draft of 20 units does not alter stock balance
✓ Scenario 6: Receive purchase of 20 units increases stock by 20 exactly once
✓ Scenario 7: Sell 5 units when available stock is 10 reduces balance to 5
✓ Scenario 8: Decrease 15 units when available stock is 10 is blocked
✓ Scenario 9: Unapproved adjustment leaves available stock unchanged until approved
✓ Scenario 10: Unauthorized employee adjustment is blocked by backend
✓ Scenario 11: Duplicate offline sync posts transaction only once
✓ Scenario 12: Same product in different outlets maintains completely independent stock
✓ Audit history tracks complete 17 fields accurately
```

### 6.2. Multilingual & Responsive UI Tests (`test/inventory_dashboard_multilingual_test.dart`)
```
✓ Renders in English with modern KPI metrics, Table View & Actions
✓ Renders in Hindi (हिन्दी) with complete accurate terminology
✓ Renders in Bengali (বাংলা) with complete accurate terminology
✓ In-place Language Switcher updates controller locale seamlessly
✓ Search query filters inventory table accurately
✓ KPI card tap filters list by status and Card View toggle works
✓ Opens Product Details modal with complete technical specifications
✓ Renders with zero overflow across Mobile (390px), Tablet (820px), Desktop (1440px)
```

### 6.3. Static Analysis (`flutter analyze`)
```
Analyzing inventory_dashboard_page.dart, inventory_repository.dart, app_controller.dart, stock_transaction_audit_model.dart...
No issues found! (0 errors, 0 warnings, 0 infos)
```

---

## 7. Remaining Considerations & Operational Recommendations

1. **Barcode Scanning at Zero Stock**: When scanning items at the POS counter that have 0 stock, POS cashier mode alerts the cashier that available stock is 0 and requires a supervisor override if negative stock billing is explicitly permitted by business policy (disabled by default).
2. **Periodic Cycle Counting**: For store operations with frequent manual adjustments, management should configure weekly cycle count reviews using the `COUNT_CORRECTION` movement type with mandatory dual-signoff.
3. **Data Preservation**: Existing database schemas and tables (`local_stock_balances`, `local_inventory_batches`, `local_stock_movements`) were strictly preserved without destructive migrations. Existing catalog items and historical sales records remain intact.
